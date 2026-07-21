using System.Diagnostics;
using System.Text;
using Miao.Common.Jobs;

namespace Miao.Software.Jobs;

/// <summary>
/// 以无窗口方式启动 powershell.exe，流式转发 stdout/stderr，并解析约定进度行。
/// 状态类消息用 kind=log；原始命令输出用 kind=console。
/// 脚本一律落盘为 UTF-8（带 BOM）再 -File 执行，避免中文 Write-Host 乱码。
/// </summary>
public sealed class JobRunner
{
    /// <summary>任务过程事件（日志、进度、命令输出等）。</summary>
    public event Action<JobEvent>? Event;

    /// <summary>
    /// 异步执行一段 PowerShell（已有脚本文件路径，或内联命令文本）。
    /// </summary>
    /// <param name="jobId">任务 id。</param>
    /// <param name="scriptPathOrCommand">.ps1 路径或内联脚本。</param>
    /// <param name="arguments">附加参数（仅 -File 时有用）。</param>
    /// <param name="cancellationToken">取消令牌。</param>
    /// <returns>退出码与 stderr 摘要。</returns>
    public async Task<JobResult> RunPowerShellAsync(
        string jobId,
        string scriptPathOrCommand,
        IReadOnlyList<string>? arguments = null,
        CancellationToken cancellationToken = default)
    {
        string? tempScript = null;
        string scriptPath;
        var ownsTemp = false;

        if (File.Exists(scriptPathOrCommand))
        {
            scriptPath = scriptPathOrCommand;
        }
        else
        {
            // 内联脚本 → UTF-8 BOM 临时文件，保证中文与控制台输出编码一致
            tempScript = Path.Combine(Path.GetTempPath(), $"miao-job-{jobId}-{Guid.NewGuid():N}.ps1");
            var body = BuildUtf8Script(scriptPathOrCommand);
            await File.WriteAllTextAsync(tempScript, body, new UTF8Encoding(encoderShouldEmitUTF8Identifier: true), cancellationToken)
                .ConfigureAwait(false);
            scriptPath = tempScript;
            ownsTemp = true;
        }

        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
                StandardOutputEncoding = new UTF8Encoding(false),
                StandardErrorEncoding = new UTF8Encoding(false),
            };

            psi.ArgumentList.Add("-NoProfile");
            psi.ArgumentList.Add("-ExecutionPolicy");
            psi.ArgumentList.Add("Bypass");
            psi.ArgumentList.Add("-File");
            psi.ArgumentList.Add(scriptPath);

            if (arguments is not null)
            {
                foreach (var arg in arguments)
                    psi.ArgumentList.Add(arg);
            }

            Emit(jobId, "log", "已启动 PowerShell 任务");
            Emit(jobId, "console", $"> powershell -NoProfile -File \"{Path.GetFileName(scriptPath)}\"");

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
        finally
        {
            if (ownsTemp && tempScript is not null)
            {
                try { File.Delete(tempScript); } catch { /* ignore */ }
            }
        }
    }

    /// <summary>
    /// 在脚本前强制 UTF-8 控制台输出，避免 Write-Host 中文在管道中乱码。
    /// </summary>
    private static string BuildUtf8Script(string userScript)
    {
        var sb = new StringBuilder();
        sb.AppendLine("$ErrorActionPreference = 'Stop'");
        sb.AppendLine("$OutputEncoding = New-Object System.Text.UTF8Encoding $false");
        sb.AppendLine("[Console]::OutputEncoding = $OutputEncoding");
        sb.AppendLine("[Console]::InputEncoding = $OutputEncoding");
        sb.AppendLine(userScript);
        return sb.ToString();
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
            // ##batch current total  （current 从 1 起）；前端可不展示 xx/xx，仅作兼容
            var parts = payload.Split([' ', '\t', '/'], StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length >= 2 &&
                int.TryParse(parts[0], out var cur) &&
                int.TryParse(parts[1], out var total))
            {
                Emit(jobId, "batch", $"{Math.Max(0, cur)} {Math.Max(0, total)}");
            }
        });

        TryParseTagged(jobId, line, "##log ", (payload) =>
        {
            if (!string.IsNullOrWhiteSpace(payload))
                Emit(jobId, "log", payload.Trim());
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

    /// <summary>向 UI 推送当前任务文案（进度条上方）。</summary>
    public void EmitTask(string jobId, string message) => Emit(jobId, "task", message);

    private void Emit(string jobId, string kind, string message) =>
        Event?.Invoke(new JobEvent(jobId, kind, message, DateTimeOffset.Now));
}
