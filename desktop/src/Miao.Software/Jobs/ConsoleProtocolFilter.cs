using System.Text;

namespace Miao.Software.Jobs;

/// <summary>
/// 流式拆分协议行与命令窗输出：
/// - 完整以换行结束的 <c>##…</c> 行 → 进度/日志协议（不进命令窗）
/// - 其余（含裸 <c>\\r</c>、半行）立即进命令窗，供 xterm 实时刷新（与真终端一致）
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
                onConsole(line + "\n");
        }

        if (_pending.Length == 0) return;
        var rest = _pending.ToString();
        // 未完成的 ## 协议行暂扣；其它一律实时透出（Fetching \r 进度）
        if (LooksLikeProtocolPrefix(rest))
            return;

        onConsole(rest);
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
            onConsole(rest);
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
        if (s.IndexOf('\u001b') < 0) return s;
        var sb = new StringBuilder(s.Length);
        for (var i = 0; i < s.Length; i++)
        {
            if (s[i] != '\u001b')
            {
                sb.Append(s[i]);
                continue;
            }

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
                while (i < s.Length && s[i] != '\u0007')
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

            i++;
        }

        return sb.ToString();
    }
}
