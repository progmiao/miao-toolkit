using System.Text;
using Miao.Common.Jobs;
using Miao.Software.Dev.Claude;
using Miao.Software.Detect;

namespace Miao.Software.Dev.Claude;

/// <summary>Claude Code：WinGet 安装 / 升级 Anthropic.ClaudeCode。</summary>
public sealed class ClaudeInstallHandler : IToolActionHandler
{
    /// <inheritdoc />
    public string HandlerId => "claude.install";

    /// <inheritdoc />
    public async Task<JobResult> ExecuteAsync(ToolActionContext context, CancellationToken cancellationToken = default)
    {
        const string packageId = "Anthropic.ClaudeCode";
        var sb = new StringBuilder();
        sb.AppendLine("$ErrorActionPreference = 'Stop'");
        sb.AppendLine("Write-Host '##progress 8'");
        sb.AppendLine($"$id = '{packageId}'");
        sb.AppendLine(@"
Write-Host ""检测 winget 包 $id …""
$listed = winget list --id $id -e 2>&1 | Out-String
if ($LASTEXITCODE -eq 0 -and $listed -match [regex]::Escape($id)) {
  Write-Host '##progress 30'
  Write-Host '已安装，尝试 upgrade…'
  winget upgrade --id $id -e --accept-package-agreements --accept-source-agreements
  if ($LASTEXITCODE -ne 0) {
    Write-Host 'upgrade 无可用更新或已是最新，继续验证…'
  }
} else {
  Write-Host '##progress 30'
  Write-Host '执行 install…'
  winget install --id $id -e --accept-package-agreements --accept-source-agreements
  if ($LASTEXITCODE -ne 0) { throw ""winget install 失败 exit=$LASTEXITCODE"" }
}
$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
Write-Host '##progress 90'
if (Get-Command claude -ErrorAction SilentlyContinue) { Write-Host (claude --version) }
Write-Host '##progress 100'
Write-Host 'Claude Code CLI 已就绪'
");

        var result = await context.Jobs
            .RunPowerShellAsync(context.JobId, sb.ToString(), cancellationToken: cancellationToken)
            .ConfigureAwait(false);
        InstallDetector.ProbeAndStore(context.Db, context.ToolId, context.Manifest.Install?.Detect);
        return result;
    }
}

/// <summary>Claude Code：仅当 WinGet 管理时卸载。</summary>
public sealed class ClaudeUninstallHandler : IToolActionHandler
{
    /// <inheritdoc />
    public string HandlerId => "claude.uninstall";

    /// <inheritdoc />
    public async Task<JobResult> ExecuteAsync(ToolActionContext context, CancellationToken cancellationToken = default)
    {
        const string packageId = "Anthropic.ClaudeCode";
        var sb = new StringBuilder();
        sb.AppendLine("$ErrorActionPreference = 'Stop'");
        sb.AppendLine($"$id = '{packageId}'");
        sb.AppendLine(@"
Write-Host '##progress 10'
$listed = winget list --id $id -e 2>&1 | Out-String
if ($LASTEXITCODE -ne 0 -or $listed -notmatch [regex]::Escape($id)) {
  throw '未检测到 WinGet 管理的 Anthropic.ClaudeCode。若由 npm/Volta 安装，请手动卸载。'
}
Write-Host '##progress 40'
winget uninstall --id $id -e --accept-source-agreements
if ($LASTEXITCODE -ne 0) { throw ""winget uninstall 失败 exit=$LASTEXITCODE"" }
Write-Host '##progress 100'
Write-Host '已卸载 Claude Code（WinGet）'
");

        var result = await context.Jobs
            .RunPowerShellAsync(context.JobId, sb.ToString(), cancellationToken: cancellationToken)
            .ConfigureAwait(false);
        InstallDetector.ProbeAndStore(context.Db, context.ToolId, context.Manifest.Install?.Detect);
        return result;
    }
}

/// <summary>Claude Code：初始化默认 env + 注册预设 marketplace。</summary>
public sealed class ClaudeInitHandler : IToolActionHandler
{
    private readonly ClaudeCodeService _claude;

    /// <summary>创建处理器。</summary>
    public ClaudeInitHandler(ClaudeCodeService claude) => _claude = claude;

    /// <inheritdoc />
    public string HandlerId => "claude.init";

    /// <inheritdoc />
    public Task<JobResult> ExecuteAsync(ToolActionContext context, CancellationToken cancellationToken = default)
    {
        try
        {
            context.Jobs.EmitLog(context.JobId, "开始初始化 Claude Code…");
            var detail = _claude.Init();
            foreach (var line in detail.Split('\n'))
                context.Jobs.EmitLog(context.JobId, line);
            context.Jobs.EmitProgress(context.JobId, 100);
            return Task.FromResult(new JobResult(context.JobId, true, 0, detail));
        }
        catch (Exception ex)
        {
            return Task.FromResult(new JobResult(context.JobId, false, 1, ex.Message));
        }
    }
}

/// <summary>批量安装精选 / 指定插件（Options 中 plugins 逗号分隔，或 Versions 复用）。</summary>
public sealed class ClaudePluginInstallHandler : IToolActionHandler
{
    private readonly ClaudeCodeService _claude;

    /// <summary>创建处理器。</summary>
    public ClaudePluginInstallHandler(ClaudeCodeService claude) => _claude = claude;

    /// <inheritdoc />
    public string HandlerId => "claude.plugin-install";

    /// <inheritdoc />
    public Task<JobResult> ExecuteAsync(ToolActionContext context, CancellationToken cancellationToken = default)
    {
        var ids = ResolvePluginIds(context);
        if (ids.Count == 0)
            return Task.FromResult(new JobResult(context.JobId, false, 1, "未指定插件 id"));

        var okAll = true;
        var sb = new StringBuilder();
        for (var i = 0; i < ids.Count; i++)
        {
            var id = ids[i];
            context.Jobs.EmitProgress(context.JobId, (int)(10 + 80.0 * (i + 1) / ids.Count));
            context.Jobs.EmitLog(context.JobId, $"安装插件 {id}…");
            var (ok, detail) = _claude.InstallPlugin(id);
            sb.AppendLine(ok ? $"OK {id}" : $"FAIL {id}: {detail}");
            if (!ok) okAll = false;
            else context.Jobs.EmitLog(context.JobId, detail);
        }

        context.Jobs.EmitProgress(context.JobId, 100);
        return Task.FromResult(new JobResult(context.JobId, okAll, okAll ? 0 : 1, sb.ToString()));
    }

    private static List<string> ResolvePluginIds(ToolActionContext context)
    {
        if (context.Options.TryGetValue("plugins", out var csv) && !string.IsNullOrWhiteSpace(csv))
            return csv.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).ToList();
        return context.Versions.Where(v => !string.IsNullOrWhiteSpace(v)).ToList();
    }
}

/// <summary>批量卸载插件。</summary>
public sealed class ClaudePluginUninstallHandler : IToolActionHandler
{
    private readonly ClaudeCodeService _claude;

    /// <summary>创建处理器。</summary>
    public ClaudePluginUninstallHandler(ClaudeCodeService claude) => _claude = claude;

    /// <inheritdoc />
    public string HandlerId => "claude.plugin-uninstall";

    /// <inheritdoc />
    public Task<JobResult> ExecuteAsync(ToolActionContext context, CancellationToken cancellationToken = default)
    {
        var ids = context.Options.TryGetValue("plugins", out var csv) && !string.IsNullOrWhiteSpace(csv)
            ? csv.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).ToList()
            : context.Versions.Where(v => !string.IsNullOrWhiteSpace(v)).ToList();

        if (ids.Count == 0)
            return Task.FromResult(new JobResult(context.JobId, false, 1, "未指定插件 id"));

        var okAll = true;
        var sb = new StringBuilder();
        foreach (var id in ids)
        {
            context.Jobs.EmitLog(context.JobId, $"卸载插件 {id}…");
            var (ok, detail) = _claude.UninstallPlugin(id);
            sb.AppendLine(ok ? $"OK {id}" : $"FAIL {id}: {detail}");
            if (!ok) okAll = false;
        }

        context.Jobs.EmitProgress(context.JobId, 100);
        return Task.FromResult(new JobResult(context.JobId, okAll, okAll ? 0 : 1, sb.ToString()));
    }
}
