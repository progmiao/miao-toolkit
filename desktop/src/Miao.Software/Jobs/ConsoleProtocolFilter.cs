using System.Text;

namespace Miao.Software.Jobs;

/// <summary>
/// 流式拆分协议行与命令窗输出：
/// - 完整以换行结束的 <c>##…</c> 行 → 进度/日志协议（不进命令窗）
/// - 其余（含裸 <c>\\r</c>、半行）立即进命令窗，供 xterm 实时刷新（与真终端一致）
/// - 纯换行仍透出，避免半行 + 被剥离的协议行导致下一句粘连
/// </summary>
internal sealed class ConsoleProtocolFilter
{
    private readonly StringBuilder _pending = new();

    /// <summary>喂入一块输出。</summary>
    public void Push(string chunk, Action<string> onProtocolLine, Action<string> onConsole)
    {
        if (string.IsNullOrEmpty(chunk)) return;
        _pending.Append(chunk);

        while (true)
        {
            var text = _pending.ToString();
            // 只按真正换行切协议行；裸 \r 留给命令窗做原地刷新
            var nl = text.IndexOf('\n');
            if (nl < 0) break;

            var lineEnd = nl;
            if (lineEnd > 0 && text[lineEnd - 1] == '\r')
                lineEnd--;

            var line = text[..lineEnd];
            _pending.Remove(0, nl + 1);

            if (LooksLikeProtocolLine(line))
                onProtocolLine(StripAnsi(line));
            else
                EmitConsole(onConsole, line + "\n");
        }

        if (_pending.Length == 0) return;
        var rest = _pending.ToString();
        // 未完成的 ## 协议行暂扣；其它一律实时透出（Fetching \r 进度）
        if (LooksLikeProtocolPrefix(rest))
            return;

        EmitConsole(onConsole, rest);
        _pending.Clear();
    }

    /// <summary>任务结束时冲刷残留。</summary>
    public void Flush(Action<string> onProtocolLine, Action<string> onConsole)
    {
        if (_pending.Length == 0) return;
        var rest = _pending.ToString();
        _pending.Clear();
        if (LooksLikeProtocolLine(rest) || LooksLikeProtocolPrefix(rest))
            onProtocolLine(StripAnsi(rest));
        else if (rest.Length > 0)
            EmitConsole(onConsole, rest);
    }

    private static void EmitConsole(Action<string> onConsole, string text)
    {
        var cleaned = StripAnsi(text);
        // 仅含清屏/擦行等控制残留时可能变空，勿刷空块
        if (cleaned.Length == 0) return;
        // 纯换行必须透出：半行实时透出后，若随后是 ##progress 被吃掉，
        // UI 的 pending 半行要靠这个 \n 冲刷，否则会与下一句粘成一行。
        if (IsNewlineOnly(cleaned))
        {
            onConsole(cleaned);
            return;
        }
        if (IsConsoleNoiseOnly(cleaned)) return;
        onConsole(cleaned);
    }

    /// <summary>是否只含换行（可带 \r），用于保留行分隔。</summary>
    private static bool IsNewlineOnly(string s)
    {
        for (var i = 0; i < s.Length; i++)
        {
            if (s[i] is not ('\r' or '\n')) return false;
        }
        return s.Length > 0;
    }

    /// <summary>剥完 ANSI 后是否只剩空白 / 无意义碎片（不含纯换行，见 <see cref="IsNewlineOnly"/>）。</summary>
    private static bool IsConsoleNoiseOnly(string s)
    {
        var t = s.AsSpan().Trim();
        if (t.Length == 0) return true;
        // 整段仍是孤儿 CSI 碎片（如连续 [K）
        for (var i = 0; i < t.Length;)
        {
            if (t[i] is '\r' or '\n' or '\t' or ' ')
            {
                i++;
                continue;
            }
            if (t[i] == '[' && TrySkipOrphanCsi(t, ref i))
                continue;
            return false;
        }
        return true;
    }

    private static bool LooksLikeProtocolPrefix(string s)
    {
        var t = StripAnsi(s).TrimStart();
        return t.StartsWith("##", StringComparison.Ordinal);
    }

    private static bool LooksLikeProtocolLine(string s)
    {
        var t = StripAnsi(s).TrimStart();
        return t.StartsWith("##progress ", StringComparison.OrdinalIgnoreCase)
               || t.StartsWith("##task ", StringComparison.OrdinalIgnoreCase)
               || t.StartsWith("##batch ", StringComparison.OrdinalIgnoreCase)
               || t.StartsWith("##log ", StringComparison.OrdinalIgnoreCase);
    }

    private static string StripAnsi(string s)
    {
        if (string.IsNullOrEmpty(s)) return s;

        var sb = new StringBuilder(s.Length);
        for (var i = 0; i < s.Length; i++)
        {
            var c = s[i];

            // BEL / 其它 C0 控制符（保留 \t \n \r）
            if (c == '\u0007' || (c < 0x20 && c != '\t' && c != '\n' && c != '\r'))
                continue;

            if (c == '\u001b')
            {
                if (i + 1 >= s.Length) break;
                var next = s[i + 1];
                if (next == '[')
                {
                    i += 2;
                    while (i < s.Length && !((s[i] >= '@' && s[i] <= '~')))
                        i++;
                    continue;
                }

                if (next == ']')
                {
                    i += 2;
                    while (i < s.Length && s[i] != '\u0007' && s[i] != '\n' && s[i] != '\r')
                    {
                        if (s[i] == '\u001b' && i + 1 < s.Length && s[i + 1] == '\\')
                        {
                            i++;
                            break;
                        }
                        i++;
                    }
                    continue;
                }

                // 其它 ESC 序列：跳过 ESC 与下一字节
                i++;
                continue;
            }

            // ESC 丢失后的 OSC 窗口标题：]0;...
            if (c == ']' && i + 1 < s.Length && char.IsDigit(s[i + 1]))
            {
                var j = i + 1;
                while (j < s.Length && s[j] != '\u0007' && s[j] != '\n' && s[j] != '\r')
                {
                    if (s[j] == '\u001b' && j + 1 < s.Length && s[j + 1] == '\\')
                    {
                        j += 2;
                        break;
                    }
                    j++;
                }
                if (j < s.Length && s[j] == '\u0007') j++;
                i = j - 1;
                continue;
            }

            // ESC 丢失后的 CSI： [K  [?25h  [2J  [H  [m  [?9001h …
            // 不匹配进度条 [====>] 或任务序号 [1/2]
            if (c == '[')
            {
                var j = i;
                if (TrySkipOrphanCsi(s.AsSpan(), ref j))
                {
                    i = j - 1;
                    continue;
                }
            }

            sb.Append(c);
        }

        return sb.ToString();
    }

    /// <summary>
    /// 尝试跳过一段孤儿 CSI（无 ESC）。成功时 index 停在序列后一字节。
    /// </summary>
    private static bool TrySkipOrphanCsi(ReadOnlySpan<char> s, ref int index)
    {
        if (index >= s.Length || s[index] != '[') return false;
        var i = index + 1;
        if (i < s.Length && s[i] == '?') i++;
        var sawParam = false;
        while (i < s.Length && ((s[i] >= '0' && s[i] <= '9') || s[i] == ';'))
        {
            sawParam = true;
            i++;
        }
        if (i >= s.Length) return false;
        var final = s[i];
        // 仅吃控制类终字，避免误伤 [1/2]、[====>]
        if (final is >= 'A' and <= 'Z' or >= 'a' and <= 'z')
        {
            // 无参的 [K]/[H]/[m]/[J] 与带参的 [?25h]/[2J] 都允许
            _ = sawParam;
            index = i + 1;
            return true;
        }
        return false;
    }
}
