using System.Text;
using Miao.Common.Jobs;
using Miao.Tools.Detect;

namespace Miao.Tools.Handlers;

/// <summary>
/// Node：经 Volta 安装 LTS（对照旧能力结果重写，无交互）。
/// </summary>
public sealed class NodeInstallHandler : IToolActionHandler
{
    /// <inheritdoc />
    public string HandlerId => "node.install";

    /// <inheritdoc />
    public async Task<JobResult> ExecuteAsync(ToolActionContext context, CancellationToken cancellationToken = default)
    {
        var sb = new StringBuilder();
        sb.AppendLine("$ErrorActionPreference = 'Stop'");
        sb.AppendLine("function Refresh-Path { $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User') }");
        sb.AppendLine("Write-Host '##progress 5'");
        sb.AppendLine("Write-Host '准备安装 Node.js（经 Volta，LTS）…'");
        sb.AppendLine("Refresh-Path");
        sb.AppendLine("if (-not (Get-Command volta -ErrorAction SilentlyContinue)) {");
        sb.AppendLine("  Write-Host '##progress 15'");
        sb.AppendLine("  Write-Host '未检测到 Volta，winget 安装 Volta.Volta…'");
        sb.AppendLine("  winget install --id Volta.Volta -e --accept-package-agreements --accept-source-agreements");
        sb.AppendLine("  if ($LASTEXITCODE -ne 0) { throw \"winget 安装 Volta 失败，exit=$LASTEXITCODE\" }");
        sb.AppendLine("  Refresh-Path; Start-Sleep -Seconds 1; Refresh-Path");
        sb.AppendLine("}");
        sb.AppendLine("Write-Host '##progress 45'");
        sb.AppendLine("if (-not (Get-Command volta -ErrorAction SilentlyContinue)) { throw '安装后仍未找到 volta' }");
        sb.AppendLine("Write-Host '##progress 55'");
        sb.AppendLine("volta install node@lts");
        sb.AppendLine("if ($LASTEXITCODE -ne 0) { throw \"volta install node@lts 失败\" }");
        sb.AppendLine("Write-Host '##progress 100'");
        sb.AppendLine("Refresh-Path; Write-Host (\"node: \" + (node -v))");

        var result = await context.Jobs
            .RunPowerShellAsync(context.JobId, sb.ToString(), cancellationToken: cancellationToken)
            .ConfigureAwait(false);

        InstallDetector.ProbeAndStore(context.Db, context.ToolId, context.Manifest.Install?.Detect);
        return result;
    }
}

/// <summary>
/// TerminalBuddy：Gitee Release 下载 exe、放到 LocalAppData\Programs、写标记与快捷方式（custom）。
/// </summary>
public sealed class TerminalBuddyInstallHandler : IToolActionHandler
{
    /// <inheritdoc />
    public string HandlerId => "terminal-buddy.install";

    /// <inheritdoc />
    public async Task<JobResult> ExecuteAsync(ToolActionContext context, CancellationToken cancellationToken = default)
    {
        var install = context.Manifest.Install;
        var owner = install?.GiteeOwner ?? "updateme";
        var repo = install?.GiteeRepo ?? "terminal-buddy";
        var asset = install?.AssetName ?? "terminal-buddy.exe";

        var sb = new StringBuilder();
        sb.AppendLine("$ErrorActionPreference = 'Stop'");
        sb.AppendLine($"$owner = '{Escape(owner)}'; $repo = '{Escape(repo)}'; $asset = '{Escape(asset)}'");
        sb.AppendLine(@"
$installDir = Join-Path $env:LOCALAPPDATA 'Programs\terminal-buddy'
$exePath = Join-Path $installDir $asset
$marker = Join-Path $installDir '.miao-installed'
New-Item -ItemType Directory -Force -Path $installDir | Out-Null
Write-Host '##progress 10'
$api = ""https://gitee.com/api/v5/repos/$owner/$repo/releases/latest""
Write-Host ""查询 Release: $api""
$rel = Invoke-RestMethod -Uri $api -TimeoutSec 60
$item = $rel.assets | Where-Object { $_.name -eq $asset } | Select-Object -First 1
if (-not $item) { throw ""Release 中未找到 $asset"" }
$url = $item.browser_download_url
if (-not $url) { $url = $item.download_url }
Write-Host ""下载: $url""
Write-Host '##progress 30'
Invoke-WebRequest -Uri $url -OutFile $exePath -UseBasicParsing
Write-Host '##progress 75'
Set-Content -Path $marker -Value (Get-Date -Format o) -Encoding UTF8
$shell = New-Object -ComObject WScript.Shell
$lnk1 = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\TerminalBuddy.lnk'
$s1 = $shell.CreateShortcut($lnk1); $s1.TargetPath = $exePath; $s1.WorkingDirectory = $installDir; $s1.Save()
$desk = [Environment]::GetFolderPath('Desktop')
$lnk2 = Join-Path $desk 'TerminalBuddy.lnk'
$s2 = $shell.CreateShortcut($lnk2); $s2.TargetPath = $exePath; $s2.WorkingDirectory = $installDir; $s2.Save()
Write-Host '##progress 100'
Write-Host ""已安装到 $exePath""
");

        var result = await context.Jobs
            .RunPowerShellAsync(context.JobId, sb.ToString(), cancellationToken: cancellationToken)
            .ConfigureAwait(false);

        InstallDetector.ProbeAndStore(context.Db, context.ToolId, install?.Detect);
        return result;
    }

    private static string Escape(string s) => s.Replace("'", "''");
}

/// <summary>TerminalBuddy 卸载：删目录与快捷方式。</summary>
public sealed class TerminalBuddyUninstallHandler : IToolActionHandler
{
    /// <inheritdoc />
    public string HandlerId => "terminal-buddy.uninstall";

    /// <inheritdoc />
    public async Task<JobResult> ExecuteAsync(ToolActionContext context, CancellationToken cancellationToken = default)
    {
        var script = @"
$ErrorActionPreference = 'Stop'
$installDir = Join-Path $env:LOCALAPPDATA 'Programs\terminal-buddy'
Write-Host '##progress 20'
Remove-Item -LiteralPath (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\TerminalBuddy.lnk') -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path ([Environment]::GetFolderPath('Desktop')) 'TerminalBuddy.lnk') -Force -ErrorAction SilentlyContinue
if (Test-Path $installDir) { Remove-Item -LiteralPath $installDir -Recurse -Force }
Write-Host '##progress 100'
Write-Host 'TerminalBuddy 已卸载'
";
        var result = await context.Jobs
            .RunPowerShellAsync(context.JobId, script, cancellationToken: cancellationToken)
            .ConfigureAwait(false);
        InstallDetector.ProbeAndStore(context.Db, context.ToolId, context.Manifest.Install?.Detect);
        return result;
    }
}
