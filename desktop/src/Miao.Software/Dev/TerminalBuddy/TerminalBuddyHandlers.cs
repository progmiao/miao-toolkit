using System.Text;
using Miao.Common.Jobs;
using Miao.Software.Detect;

namespace Miao.Software.Dev.TerminalBuddy;

/// <summary>
/// TerminalBuddy：Gitee Release 同步安装（检测版本后下载）、写标记与快捷方式。
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
Write-Host '##progress 8'
$api = ""https://gitee.com/api/v5/repos/$owner/$repo/releases/latest""
Write-Host ""查询 Release: $api""
$rel = Invoke-RestMethod -Uri $api -TimeoutSec 60
$tag = [string]$rel.tag_name
$item = $rel.assets | Where-Object { $_.name -eq $asset } | Select-Object -First 1
if (-not $item) { throw ""Release 中未找到 $asset"" }
$url = $item.browser_download_url
if (-not $url) { $url = $item.download_url }
$needDownload = $true
if (Test-Path $exePath) {
  try {
    $localVer = [Diagnostics.FileVersionInfo]::GetVersionInfo($exePath).FileVersion
    Write-Host ""本地 FileVersion=$localVer · 远程 tag=$tag""
  } catch { $localVer = $null }
  Write-Host '将下载最新 Release 覆盖安装（同步）'
}
Write-Host ""下载: $url""
Write-Host '##progress 30'
$tmp = Join-Path $env:TEMP (""tb-"" + [guid]::NewGuid().ToString('N') + '.exe')
Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing
Write-Host '##progress 70'
Copy-Item -LiteralPath $tmp -Destination $exePath -Force
Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
Set-Content -Path $marker -Value ((Get-Date -Format o) + ""`n"" + $tag) -Encoding UTF8
$shell = New-Object -ComObject WScript.Shell
$lnk1 = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\TerminalBuddy.lnk'
$s1 = $shell.CreateShortcut($lnk1); $s1.TargetPath = $exePath; $s1.WorkingDirectory = $installDir; $s1.Save()
$desk = [Environment]::GetFolderPath('Desktop')
$lnk2 = Join-Path $desk 'TerminalBuddy.lnk'
$s2 = $shell.CreateShortcut($lnk2); $s2.TargetPath = $exePath; $s2.WorkingDirectory = $installDir; $s2.Save()
Write-Host '##progress 100'
Write-Host ""已同步到 $exePath (tag=$tag)""
");

        var result = await context.Jobs
            .RunPowerShellAsync(context.JobId, sb.ToString(), cancellationToken: cancellationToken)
            .ConfigureAwait(false);

        InstallDetector.ProbeAndStore(context.Db, context.ToolId, install?.Detect);
        return result;
    }

    private static string Escape(string s) => s.Replace("'", "''");
}

/// <summary>TerminalBuddy 卸载：删程序目录与快捷方式，保留 %APPDATA%\TerminalBuddy。</summary>
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
Write-Host 'TerminalBuddy 已卸载（用户数据 %APPDATA%\TerminalBuddy 已保留）'
";
        var result = await context.Jobs
            .RunPowerShellAsync(context.JobId, script, cancellationToken: cancellationToken)
            .ConfigureAwait(false);
        InstallDetector.ProbeAndStore(context.Db, context.ToolId, context.Manifest.Install?.Detect);
        return result;
    }
}
