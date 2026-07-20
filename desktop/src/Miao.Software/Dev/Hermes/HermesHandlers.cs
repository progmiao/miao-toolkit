using System.Text;
using Miao.Common.Jobs;
using Miao.Software.Detect;

namespace Miao.Software.Dev.Hermes;

/// <summary>
/// Hermes Agent：官方 install.ps1 安装或已存在时 hermes update。
/// </summary>
public sealed class HermesInstallHandler : IToolActionHandler
{
    /// <inheritdoc />
    public string HandlerId => "hermes.install";

    /// <inheritdoc />
    public async Task<JobResult> ExecuteAsync(ToolActionContext context, CancellationToken cancellationToken = default)
    {
        var sb = new StringBuilder();
        sb.AppendLine("$ErrorActionPreference = 'Stop'");
        sb.AppendLine(@"
function Refresh-Path { $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User') }
function Test-Hermes {
  $candidates = @(
    (Join-Path $env:LOCALAPPDATA 'hermes\hermes-agent\venv\Scripts\hermes.exe'),
    (Join-Path $env:LOCALAPPDATA 'hermes\bin\hermes.cmd')
  )
  foreach ($c in $candidates) { if (Test-Path $c) { return $true } }
  return [bool](Get-Command hermes -ErrorAction SilentlyContinue)
}
Write-Host '##progress 8'
Refresh-Path
$desk = winget list --id fathah.HermesDesktop -e 2>&1 | Out-String
if ($desk -match 'HermesDesktop|fathah') {
  Write-Host '注意：检测到 WinGet Hermes Desktop，与 Hermes Agent CLI 相互独立。'
}
Write-Host '##progress 20'
if (Test-Hermes) {
  Write-Host '已检测到 Hermes，执行 hermes update…'
  Write-Host '##progress 40'
  hermes update
  if ($LASTEXITCODE -ne 0) { throw ""hermes update 失败 exit=$LASTEXITCODE"" }
} else {
  Write-Host '执行官方安装脚本…'
  Write-Host '##progress 35'
  $url = 'https://hermes-agent.nousresearch.com/install.ps1'
  Invoke-RestMethod -Uri $url | Invoke-Expression
}
Refresh-Path
Write-Host '##progress 90'
if (Get-Command hermes -ErrorAction SilentlyContinue) {
  Write-Host (hermes --version 2>&1 | Out-String)
} else {
  Write-Host '安装完成；若命令不可用，请打开新终端后再试。'
}
Write-Host '##progress 100'
Write-Host '建议下一步：hermes setup --portal 或 hermes model'
");

        var result = await context.Jobs
            .RunPowerShellAsync(context.JobId, sb.ToString(), cancellationToken: cancellationToken)
            .ConfigureAwait(false);
        InstallDetector.ProbeAndStore(context.Db, context.ToolId, context.Manifest.Install?.Detect);
        return result;
    }
}

/// <summary>Hermes：hermes uninstall --yes（保留用户数据）。</summary>
public sealed class HermesUninstallHandler : IToolActionHandler
{
    /// <inheritdoc />
    public string HandlerId => "hermes.uninstall";

    /// <inheritdoc />
    public async Task<JobResult> ExecuteAsync(ToolActionContext context, CancellationToken cancellationToken = default)
    {
        var script = @"
$ErrorActionPreference = 'Stop'
function Refresh-Path { $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User') }
Refresh-Path
Write-Host '##progress 20'
if (-not (Get-Command hermes -ErrorAction SilentlyContinue)) {
  $exe = Join-Path $env:LOCALAPPDATA 'hermes\hermes-agent\venv\Scripts\hermes.exe'
  if (Test-Path $exe) { & $exe uninstall --yes }
  else { throw '未找到 hermes 命令' }
} else {
  hermes uninstall --yes
}
if ($LASTEXITCODE -ne 0) { throw ""hermes uninstall 失败 exit=$LASTEXITCODE"" }
Write-Host '##progress 100'
Write-Host 'Hermes CLI 已卸载（用户配置/数据按官方策略保留）'
";
        var result = await context.Jobs
            .RunPowerShellAsync(context.JobId, script, cancellationToken: cancellationToken)
            .ConfigureAwait(false);
        InstallDetector.ProbeAndStore(context.Db, context.ToolId, context.Manifest.Install?.Detect);
        return result;
    }
}
