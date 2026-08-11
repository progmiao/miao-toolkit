using System.Text;
using Miao.Common.Jobs;
using Miao.Software.Detect;

namespace Miao.Software.Dev.Hermes;

/// <summary>
/// Hermes：官方 install.ps1 安装或已存在时 hermes update。
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
  Write-Host '注意：检测到 WinGet Hermes Desktop，与 Hermes CLI 相互独立。'
}
Write-Host '##progress 20'
if (Test-Hermes) {
  Write-Host '已检测到 Hermes，执行 hermes update（非交互，不恢复本地 stash）…'
  Write-Host '##progress 40'
  # --yes：跳过交互；discard：更新后丢掉 autostash（等同 Restore local changes? N）
  try { hermes config set updates.non_interactive_local_changes discard 2>&1 | Out-Host } catch { }
  $prevEAP = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  # 个别版本仍可能读 stdin；预置 n 作兜底
  ""n"" | hermes update --yes
  $updExit = $LASTEXITCODE
  $ErrorActionPreference = $prevEAP
  if ($updExit -ne 0) { throw ""hermes update 失败 exit=$updExit"" }
} else {
  Write-Host '执行官方安装脚本（跳过交互向导）…'
  Write-Host '##progress 35'
  $url = 'https://hermes-agent.nousresearch.com/install.ps1'
  # irm|iex 无法传参；用 scriptblock 传入 -SkipSetup/-NonInteractive，避免卡在 setup 菜单
  & ([scriptblock]::Create((Invoke-RestMethod -Uri $url))) -SkipSetup -NonInteractive
  if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) {
    throw ""官方安装脚本失败 exit=$LASTEXITCODE""
  }
}
Refresh-Path
Write-Host '##progress 75'
if (-not (Get-Command hermes -ErrorAction SilentlyContinue)) {
  $fallback = Join-Path $env:LOCALAPPDATA 'hermes\hermes-agent\venv\Scripts\hermes.exe'
  if (Test-Path $fallback) {
    $env:Path = (Split-Path $fallback -Parent) + ';' + $env:Path
  }
}
if (Get-Command hermes -ErrorAction SilentlyContinue) {
  Write-Host (hermes --version 2>&1 | Out-String)
  Write-Host '##progress 85'
  Write-Host '执行 Quick Setup（Nous Portal）…'
  hermes setup --portal
  if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) {
    Write-Host (""hermes setup --portal 退出码=$LASTEXITCODE；可稍后在终端重试。"")
  }
} else {
  Write-Host '安装完成；若命令不可用，请打开新终端后再试：hermes setup --portal'
}
Write-Host '##progress 100'
Write-Host 'Hermes 安装/更新流程结束'
");

        var result = await context.Jobs
            .RunPowerShellAsync(context.JobId, sb.ToString(), cancellationToken: cancellationToken)
            .ConfigureAwait(false);
        InstallDetector.ProbeAndStore(context.Db, context.ToolId, context.Manifest.Install?.Detect);
        return result;
    }
}

/// <summary>Hermes：停 gateway / 杀锁文件进程后 hermes uninstall，再强制清残留安装目录。</summary>
public sealed class HermesUninstallHandler : IToolActionHandler
{
    /// <inheritdoc />
    public string HandlerId => "hermes.uninstall";

    /// <inheritdoc />
    public async Task<JobResult> ExecuteAsync(ToolActionContext context, CancellationToken cancellationToken = default)
    {
        // 官方 uninstall 在 Windows 上常因 gateway / python 锁住 .git pack 而「警告后仍报成功」，
        // 残留 hermes.exe / hermes.cmd 会使探测仍为 installed。先停进程再卸，卸后再强制清安装树。
        var script = @"
$ErrorActionPreference = 'Continue'
function Refresh-Path {
  $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
}
function Stop-HermesLocks {
  param([string]$Root)
  if (-not $Root) { return }
  try {
    if (Get-Command hermes -ErrorAction SilentlyContinue) {
      & hermes gateway stop 2>&1 | Out-Host
    }
  } catch { }
  Get-Process -ErrorAction SilentlyContinue | Where-Object {
    try { $_.Path -and ($_.Path.StartsWith($Root, [StringComparison]::OrdinalIgnoreCase)) } catch { $false }
  } | ForEach-Object {
    Write-Host (""结束占用进程: $($_.Name) ($($_.Id))"")
    Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
  }
  # 避免 Get-ScheduledTask / CIM 在部分机器上卡住，改用 schtasks
  foreach ($name in @('Hermes_Gateway','Hermes_Gateway_Watchdog')) {
    & schtasks.exe /End /TN $name 2>$null | Out-Null
    & schtasks.exe /Change /TN $name /DISABLE 2>$null | Out-Null
  }
}
function Remove-TreeRetry {
  param([string]$Path, [int]$Tries = 4)
  if (-not (Test-Path -LiteralPath $Path)) { return $true }
  for ($i = 1; $i -le $Tries; $i++) {
    Stop-HermesLocks -Root $Path
    Start-Sleep -Milliseconds (400 * $i)
    try {
      Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
      if (-not (Test-Path -LiteralPath $Path)) { return $true }
    } catch {
      Write-Host (""删除重试 $i/$Tries : $($_.Exception.Message)"")
    }
  }
  cmd.exe /c ('rd /s /q ""' + $Path + '""') | Out-Host
  return -not (Test-Path -LiteralPath $Path)
}

Refresh-Path
$hermesRoot = Join-Path $env:LOCALAPPDATA 'hermes'
$agentDir = Join-Path $hermesRoot 'hermes-agent'
$binCmd = Join-Path $hermesRoot 'bin\hermes.cmd'
Write-Host '##progress 15'
Write-Host '停止 gateway / 释放安装目录占用…'
Stop-HermesLocks -Root $hermesRoot
Start-Sleep -Seconds 1
Write-Host '##progress 35'
$ran = $false
if (Get-Command hermes -ErrorAction SilentlyContinue) {
  Write-Host '执行 hermes uninstall --yes…'
  & hermes uninstall --yes
  $ran = $true
} elseif (Test-Path -LiteralPath (Join-Path $agentDir 'venv\Scripts\hermes.exe')) {
  $exe = Join-Path $agentDir 'venv\Scripts\hermes.exe'
  Write-Host '执行本地 hermes.exe uninstall --yes…'
  & $exe uninstall --yes
  $ran = $true
} else {
  Write-Host '未找到 hermes 命令，改为直接清理安装目录…'
}
if ($ran -and ($LASTEXITCODE -ne $null) -and ($LASTEXITCODE -ne 0)) {
  Write-Host (""hermes uninstall 返回 exit=$LASTEXITCODE（将继续强制清理残留）"")
}
Write-Host '##progress 70'
Write-Host '强制清理安装残留（保留用户配置目录）…'
Stop-HermesLocks -Root $hermesRoot
$okAgent = Remove-TreeRetry -Path $agentDir
if (Test-Path -LiteralPath $binCmd) {
  Remove-Item -LiteralPath $binCmd -Force -ErrorAction SilentlyContinue
}
# 清掉空 bin 目录
$binDir = Join-Path $hermesRoot 'bin'
if ((Test-Path -LiteralPath $binDir) -and -not (Get-ChildItem -LiteralPath $binDir -Force -ErrorAction SilentlyContinue)) {
  Remove-Item -LiteralPath $binDir -Force -ErrorAction SilentlyContinue
}
Refresh-Path
Write-Host '##progress 90'
$stillExe = Test-Path -LiteralPath (Join-Path $agentDir 'venv\Scripts\hermes.exe')
$stillCmd = Test-Path -LiteralPath $binCmd
$stillCmdOnPath = [bool](Get-Command hermes -ErrorAction SilentlyContinue)
if ($stillExe -or $stillCmd -or (-not $okAgent -and (Test-Path -LiteralPath $agentDir))) {
  Write-Host '##progress 100'
  Write-Host '卸载未完成：安装目录仍有残留（常见原因是文件被占用）。'
  Write-Host (""请关闭所有 Hermes/相关终端后手动删除: $agentDir"")
  if ($stillCmdOnPath) { Write-Host 'PATH 上仍能解析到 hermes，请打开新终端或注销后再探测。' }
  throw 'Hermes 卸载后仍有安装残留'
}
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
