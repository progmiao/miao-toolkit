using System.Diagnostics;
using System.Text;
using Miao.Common.Jobs;
using Miao.Software.Jobs.ConPty;

namespace Miao.Software.Jobs;

/// <summary>
/// 以 ConPTY 启动 powershell.exe，流式转发伪终端输出（ANSI），并解析约定进度行。
/// ConPTY 不可用时回退到无窗口 stdout/stderr 重定向。
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
            tempScript = Path.Combine(Path.GetTempPath(), $"miao-job-{jobId}-{Guid.NewGuid():N}.ps1");
            var body = BuildUtf8Script(scriptPathOrCommand);
            await File.WriteAllTextAsync(tempScript, body, new UTF8Encoding(encoderShouldEmitUTF8Identifier: true), cancellationToken)
                .ConfigureAwait(false);
            scriptPath = tempScript;
            ownsTemp = true;
        }

        try
        {
            var argList = new List<string>
            {
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                scriptPath,
            };
            if (arguments is not null)
                argList.AddRange(arguments);

            Emit(jobId, "log", "已启动 PowerShell 任务");
            Emit(jobId, "console", $"> powershell -NoProfile -File \"{Path.GetFileName(scriptPath)}\"\r\n");

            try
            {
                return await RunViaConPtyAsync(jobId, argList, cancellationToken).ConfigureAwait(false);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                Emit(jobId, "log", $"ConPTY 不可用，回退管道模式（{ex.Message}）");
                return await RunViaRedirectAsync(jobId, argList, cancellationToken).ConfigureAwait(false);
            }
        }
        finally
        {
            if (ownsTemp && tempScript is not null)
            {
                try { File.Delete(tempScript); } catch { /* ignore */ }
            }
        }
    }

    private async Task<JobResult> RunViaConPtyAsync(
        string jobId,
        IReadOnlyList<string> argList,
        CancellationToken cancellationToken)
    {
        var commandLine = BuildPowerShellCommandLine(argList);
        // 列数尽量宽：避免 ConPTY 对长 URL / 路径软折行，命令窗按「逻辑一行」横滑展示。
        // 进度条仍靠 \r 原地刷新；UI 侧会按最长行再 widen。
        using var session = ConPtySession.Start(commandLine, cols: 500, rows: 30);
        var filter = new ConsoleProtocolFilter();

        void HandleChunk(string chunk)
        {
            filter.Push(
                chunk,
                line => TryParseProgress(jobId, line),
                text => Emit(jobId, "console", text));
        }

        using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        var pumpTask = session.PumpOutputAsync(HandleChunk, linked.Token);

        int exitCode;
        try
        {
            exitCode = await session.WaitForExitAsync(cancellationToken).ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
            session.Kill();
            session.ClosePty();
            linked.Cancel();
            try { await pumpTask.ConfigureAwait(false); } catch { /* ignore */ }
            filter.Flush(line => TryParseProgress(jobId, line), text => Emit(jobId, "console", text));
            Emit(jobId, "log", "任务已取消");
            Emit(jobId, "console", "\r\n^C 任务已取消\r\n");
            return new JobResult(jobId, false, -1, "cancelled");
        }

        session.ClosePty();
        try { await pumpTask.ConfigureAwait(false); } catch { /* ignore */ }
        filter.Flush(line => TryParseProgress(jobId, line), text => Emit(jobId, "console", text));

        var ok = exitCode == 0;
        Emit(jobId, "log", ok ? "PowerShell 执行完成" : $"PowerShell 退出码 {exitCode}");
        Emit(jobId, ok ? "done" : "error", ok ? "完成" : $"退出码 {exitCode}");
        return new JobResult(jobId, ok, exitCode, ok ? "" : $"exit {exitCode}");
    }

    private async Task<JobResult> RunViaRedirectAsync(
        string jobId,
        IReadOnlyList<string> argList,
        CancellationToken cancellationToken)
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
        foreach (var a in argList)
            psi.ArgumentList.Add(a);

        using var process = new Process { StartInfo = psi, EnableRaisingEvents = true };
        var stderr = new StringBuilder();
        var filter = new ConsoleProtocolFilter();

        void OnLine(string? data)
        {
            if (data is null) return;
            filter.Push(
                data + "\n",
                line => TryParseProgress(jobId, line),
                text => Emit(jobId, "console", text));
        }

        process.OutputDataReceived += (_, e) => OnLine(e.Data);
        process.ErrorDataReceived += (_, e) =>
        {
            if (e.Data is null) return;
            stderr.AppendLine(e.Data);
            OnLine(e.Data);
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
            filter.Flush(line => TryParseProgress(jobId, line), text => Emit(jobId, "console", text));
            Emit(jobId, "log", "任务已取消");
            Emit(jobId, "console", "\r\n^C 任务已取消\r\n");
            return new JobResult(jobId, false, -1, "cancelled");
        }

        filter.Flush(line => TryParseProgress(jobId, line), text => Emit(jobId, "console", text));
        var ok = process.ExitCode == 0;
        Emit(jobId, "log", ok ? "PowerShell 执行完成" : $"PowerShell 退出码 {process.ExitCode}");
        Emit(jobId, ok ? "done" : "error", ok ? "完成" : $"退出码 {process.ExitCode}");
        return new JobResult(jobId, ok, process.ExitCode, stderr.ToString());
    }

    private static string BuildPowerShellCommandLine(IReadOnlyList<string> argList)
    {
        var sb = new StringBuilder();
        sb.Append("powershell.exe");
        foreach (var a in argList)
        {
            sb.Append(' ');
            sb.Append(QuoteArg(a));
        }
        return sb.ToString();
    }

    private static string QuoteArg(string value)
    {
        if (value.Length == 0) return "\"\"";
        if (value.IndexOfAny([' ', '\t', '"']) < 0) return value;
        return "\"" + value.Replace("\"", "\\\"") + "\"";
    }

    /// <summary>
    /// 在脚本前强制 UTF-8 控制台输出，避免 Write-Host 中文乱码。
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
