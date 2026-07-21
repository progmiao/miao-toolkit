using System.Diagnostics;
using System.Text;
using Miao.Common.Jobs;

namespace Miao.Software.Jobs;

/// <summary>
/// 以无窗口方式启动 powershell.exe，流式转发 stdout/stderr，并解析约定进度行。
/// 状态类消息用 kind=log；原始命令输出用 kind=console。
/// </summary>
public sealed class JobRunner
{
    /// <summary>任务过程事件（日志、进度、命令输出等）。</summary>
    public event Action<JobEvent>? Event;

    /// <summary>
    /// 异步执行一段 PowerShell（脚本文件或 -Command 文本）。
    /// </summary>
    public async Task<JobResult> RunPowerShellAsync(
        string jobId,
        string scriptPathOrCommand,
        IReadOnlyList<string>? arguments = null,
        CancellationToken cancellationToken = default)
    {
        var psi = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8,
        };

        psi.ArgumentList.Add("-NoProfile");
        psi.ArgumentList.Add("-ExecutionPolicy");
        psi.ArgumentList.Add("Bypass");

        if (File.Exists(scriptPathOrCommand))
        {
            psi.ArgumentList.Add("-File");
            psi.ArgumentList.Add(scriptPathOrCommand);
        }
        else
        {
            psi.ArgumentList.Add("-Command");
            psi.ArgumentList.Add(scriptPathOrCommand);
        }

        if (arguments is not null)
        {
            foreach (var arg in arguments)
                psi.ArgumentList.Add(arg);
        }

        Emit(jobId, "log", "已启动 PowerShell 任务");
        Emit(jobId, "console", $"> {psi.FileName} {string.Join(' ', psi.ArgumentList)}");

        using var process = new Process { StartInfo = psi, EnableRaisingEvents = true };
        var stderr = new StringBuilder();

        process.OutputDataReceived += (_, e) =>
        {
            if (e.Data is null) return;
            Emit(jobId, "console", e.Data);
            TryParseProgress(jobId, e.Data);
        };
        process.ErrorDataReceived += (_, e) =>
        {
            if (e.Data is null) return;
            stderr.AppendLine(e.Data);
            Emit(jobId, "console", e.Data);
        };

        if (!process.Start())
            return new JobResult(jobId, false, -1, "无法启动 PowerShell");

        process.BeginOutputReadLine();
        process.BeginErrorReadLine();

        try
        {
            await process.WaitForExitAsync(cancellationToken).ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
            try { process.Kill(entireProcessTree: true); } catch { /* ignore */ }
            Emit(jobId, "log", "任务已取消");
            Emit(jobId, "console", "^C 任务已取消");
            return new JobResult(jobId, false, -1, "cancelled");
        }

        var ok = process.ExitCode == 0;
        Emit(jobId, "log", ok ? "PowerShell 执行完成" : $"PowerShell 退出码 {process.ExitCode}");
        Emit(jobId, ok ? "done" : "error", ok ? "完成" : $"退出码 {process.ExitCode}");
        return new JobResult(jobId, ok, process.ExitCode, stderr.ToString());
    }

    private void TryParseProgress(string jobId, string line)
    {
        TryParseTagged(jobId, line, "##progress ", (payload) =>
        {
            if (int.TryParse(payload.Split(' ', '\t')[0], out var pct))
                Emit(jobId, "progress", pct.ToString());
        });

        TryParseTagged(jobId, line, "##task ", (payload) =>
        {
            if (!string.IsNullOrWhiteSpace(payload))
                Emit(jobId, "task", payload.Trim());
        });

        TryParseTagged(jobId, line, "##batch ", (payload) =>
        {
            // ##batch current total  （current 从 1 起）
            var parts = payload.Split([' ', '\t', '/'], StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length >= 2 &&
                int.TryParse(parts[0], out var cur) &&
                int.TryParse(parts[1], out var total))
            {
                Emit(jobId, "batch", $"{Math.Max(0, cur)} {Math.Max(0, total)}");
            }
        });
    }

    private static void TryParseTagged(string jobId, string line, string prefix, Action<string> onMatch)
    {
        var idx = line.IndexOf(prefix, StringComparison.OrdinalIgnoreCase);
        if (idx < 0) return;
        onMatch(line[(idx + prefix.Length)..].Trim());
    }

    /// <summary>向 UI 推送一条状态日志（供非 PowerShell Handler 使用）。</summary>
    public void EmitLog(string jobId, string message) => Emit(jobId, "log", message);

    /// <summary>向 UI 推送一行命令输出。</summary>
    public void EmitConsole(string jobId, string message) => Emit(jobId, "console", message);

    /// <summary>向 UI 推送进度 0–100。</summary>
    public void EmitProgress(string jobId, int percent) =>
        Emit(jobId, "progress", Math.Clamp(percent, 0, 100).ToString());

    private void Emit(string jobId, string kind, string message) =>
        Event?.Invoke(new JobEvent(jobId, kind, message, DateTimeOffset.Now));
}
