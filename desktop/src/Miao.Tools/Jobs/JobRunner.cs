using System.Diagnostics;
using System.Text;
using Miao.Common.Jobs;

namespace Miao.Tools.Jobs;

/// <summary>
/// 以无窗口方式启动 powershell.exe，流式转发 stdout/stderr，并解析约定进度行。
/// </summary>
public sealed class JobRunner
{
    /// <summary>任务过程事件（日志、进度等）。</summary>
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

        Emit(jobId, "log", $"启动: {psi.FileName} {string.Join(' ', psi.ArgumentList)}");

        using var process = new Process { StartInfo = psi, EnableRaisingEvents = true };
        var stderr = new StringBuilder();

        process.OutputDataReceived += (_, e) =>
        {
            if (e.Data is null) return;
            Emit(jobId, "log", e.Data);
            TryParseProgress(jobId, e.Data);
        };
        process.ErrorDataReceived += (_, e) =>
        {
            if (e.Data is null) return;
            stderr.AppendLine(e.Data);
            Emit(jobId, "log", e.Data);
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
            return new JobResult(jobId, false, -1, "cancelled");
        }

        var ok = process.ExitCode == 0;
        Emit(jobId, ok ? "done" : "error", ok ? "完成" : $"退出码 {process.ExitCode}");
        return new JobResult(jobId, ok, process.ExitCode, stderr.ToString());
    }

    private void TryParseProgress(string jobId, string line)
    {
        const string prefix = "##progress ";
        var idx = line.IndexOf(prefix, StringComparison.OrdinalIgnoreCase);
        if (idx < 0) return;
        var part = line[(idx + prefix.Length)..].Trim();
        if (int.TryParse(part.Split(' ', '\t')[0], out var pct))
            Emit(jobId, "progress", pct.ToString());
    }

    private void Emit(string jobId, string kind, string message) =>
        Event?.Invoke(new JobEvent(jobId, kind, message, DateTimeOffset.Now));
}
