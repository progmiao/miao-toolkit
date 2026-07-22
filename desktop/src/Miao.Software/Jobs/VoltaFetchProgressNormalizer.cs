using System.Text;
using System.Text.RegularExpressions;

namespace Miao.Software.Jobs;

/// <summary>
/// 将 Volta「Fetching …」进度压成单行后再发给 UI；取消/结束时丢弃未完成碎片，不倾倒原始多行。
/// </summary>
internal sealed partial class VoltaFetchProgressNormalizer
{
    private readonly StringBuilder _pending = new();
    private string _pkg = "";
    private bool _inFetch;
    private bool _drawn;

    /// <summary>喂入命令窗文本。</summary>
    public void Push(string chunk, Action<string> emit)
    {
        if (string.IsNullOrEmpty(chunk)) return;
        // 纯空白不推进（避免命令窗被空行刷屏）
        if (string.IsNullOrWhiteSpace(chunk) && chunk.IndexOf('\u001b') < 0)
            return;

        _pending.Append(chunk);
        while (ProcessOnce(emit))
        {
            /* drain */
        }
    }

    /// <summary>结束时：完成已画出的进度行，丢弃缓冲中的 Fetching 残骸。</summary>
    public void Flush(Action<string> emit)
    {
        while (ProcessOnce(emit))
        {
            /* drain */
        }

        // 关键：不要把 pending 里的原始 Fetching 倾倒出去
        _pending.Clear();
        EndFetchLine(emit);
    }

    private void EndFetchLine(Action<string> emit)
    {
        if (_inFetch && _drawn)
            emit("\n");
        _inFetch = false;
        _drawn = false;
    }

    private bool ProcessOnce(Action<string> emit)
    {
        var text = _pending.ToString();
        if (text.Length == 0) return false;

        var fetch = FetchRegex().Match(text);
        if (!fetch.Success)
        {
            var pctOnly = PctOnlyRegex().Match(text);
            if (_inFetch && pctOnly.Success)
            {
                EmitProgress(emit, int.Parse(pctOnly.Groups[1].Value));
                _pending.Remove(0, pctOnly.Index + pctOnly.Length);
                TrimLeadingWs();
                return _pending.Length > 0;
            }

            if (_inFetch && IsNoise(text))
            {
                _pending.Clear();
                return false;
            }

            EndFetchLine(emit);
            if (!IsNoise(text))
                emit(text);
            _pending.Clear();
            return false;
        }

        if (fetch.Index > 0)
        {
            var prefix = text[..fetch.Index];
            _pending.Remove(0, fetch.Index);
            if (!IsNoise(prefix))
            {
                EndFetchLine(emit);
                emit(prefix);
            }
            return true;
        }

        _inFetch = true;
        Match lastFetch = fetch;
        foreach (Match m in FetchRegex().Matches(text))
            lastFetch = m;
        if (lastFetch.Index > 0)
        {
            _pending.Remove(0, lastFetch.Index);
            text = _pending.ToString();
            lastFetch = FetchRegex().Match(text);
        }

        if (lastFetch.Success)
            _pkg = lastFetch.Groups[1].Value;

        var pctMatch = PctRegex().Match(text);
        if (!pctMatch.Success)
        {
            // 尚未有 %：先画 0% 一行，避免长时间空白；后续只更新同一行
            if (!_drawn && !string.IsNullOrEmpty(_pkg))
                EmitProgress(emit, 0);

            if (_pending.Length > 2000)
            {
                var s = _pending.ToString();
                _pending.Clear();
                Match last = Match.Empty;
                foreach (Match x in FetchRegex().Matches(s))
                    last = x;
                if (last.Success)
                {
                    _pkg = last.Groups[1].Value;
                    _pending.Append(s[last.Index..]);
                }
            }
            return false;
        }

        EmitProgress(emit, int.Parse(pctMatch.Groups[1].Value));
        _pending.Remove(0, pctMatch.Index + pctMatch.Length);
        TrimLeadingWs();
        return _pending.Length > 0;
    }

    private void EmitProgress(Action<string> emit, int pct)
    {
        // 首次：先换行，避免 \r 清掉上一行「volta install …」
        if (!_drawn)
            emit("\n");
        else
            emit("\r\u001b[2K");

        emit(FormatLine(_pkg, pct));
        _drawn = true;
        _inFetch = true;
    }

    private void TrimLeadingWs()
    {
        while (_pending.Length > 0 && char.IsWhiteSpace(_pending[0]))
            _pending.Remove(0, 1);
    }

    private static bool IsNoise(string s) =>
        string.IsNullOrWhiteSpace(s) || PctOnlyRegex().IsMatch(s);

    private static string FormatLine(string pkg, int pct)
    {
        pct = Math.Clamp(pct, 0, 100);
        var shortPkg = pkg.Length > 20 ? pkg[..19] + "…" : pkg;
        const int width = 14;
        var filled = (int)Math.Round(pct / 100.0 * width);
        var head = filled > 0 ? new string('=', Math.Max(0, filled - 1)) + ">" : "";
        var bar = "[" + head + new string(' ', Math.Max(0, width - head.Length)) + "]";
        // 与 UI 一致的单行文案；不加尾换行，后续用 \r 覆盖
        return $"Fetching {shortPkg}  {bar} {pct,3}%";
    }

    [GeneratedRegex(@"Fetching\s+(\S+)", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex FetchRegex();

    [GeneratedRegex(@"(\d{1,3})\s*%", RegexOptions.CultureInvariant)]
    private static partial Regex PctRegex();

    [GeneratedRegex(@"^\s*(\d{1,3})\s*%\s*$", RegexOptions.CultureInvariant)]
    private static partial Regex PctOnlyRegex();
}
