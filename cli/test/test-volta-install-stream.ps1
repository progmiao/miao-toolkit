$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$coreLib = Join-Path $root 'package\core\lib'
. (Join-Path $coreLib 'bootstrap\Load-Core.ps1') -LibDirectory $coreLib
. (Join-Path $coreLib 'domain\Invoke-ToolDepPackage.ps1')

$toolRoot = Join-Path $root 'package\tools\01-node'
. (Join-Path $toolRoot 'lib\browse-install-run.ps1')

$state = @{ LoggedSuccess = $false }

$progressLine = "Fetching node@20.18.0  [=============>                          ]  34%"
$decision = Get-VoltaInstallOutputDecision -Line $progressLine -OutputState $state
if ($decision.Percent -ne 34) {
    throw "expected percent 34, got $($decision.Percent)"
}

$ui = @{
    ItemSubPercent = -1
    StatusPlain    = $false
    StatusText     = ''
}
$loading = @{}
$log = New-NodeBrowseInstallLog -ViewportRows 3 -BrandInnerWidth 40
$redrawCounter = @{ Value = 0 }
$redraw = { $redrawCounter.Value++ }.GetNewClosure()
$null = Update-NodeVoltaInstallOutputLine -Line $progressLine -Ui $ui -LoadingState $loading `
    -OutputState $state -Log $log -Redraw $redraw
if ($ui.ItemSubPercent -ne 34) {
    throw "ui.ItemSubPercent expected 34, got $($ui.ItemSubPercent)"
}
if ($redrawCounter.Value -lt 1) {
    throw 'expected redraw after progress line'
}

$watchUi = @{
    ItemSubPercent = -1
    StatusPlain    = $false
    StatusText     = ''
    ProgressName   = 'node@20.18.0'
}
$fakeWatch = @{
    Ready               = $true
    TotalBytes          = [int64]25692164
    UnpackEstimateBytes = [int64]60000000
    BaselineBytes       = [int64]0
    LastPercent         = -1
    DownloadStartTick   = 0
    InstallStartTick    = [Environment]::TickCount - 5000
    Phase               = 'starting'
}
function Test-VoltaInstallTmpHasNodeExe { return $false }
function Get-VoltaInstallTmpBytes { return [int64]143412 }
$pct = Get-VoltaNodeInstallProgressWatchPercent -Watch $fakeWatch
if ($pct -lt 2 -or $pct -gt 64) {
    throw "download phase percent expected 2-64, got $pct"
}
function Test-VoltaInstallTmpHasNodeExe { return $true }
function Get-VoltaInstallTmpBytes { return [int64]62000000 }
$fakeWatch.LastPercent = -1
$pctUnpack = Get-VoltaNodeInstallProgressWatchPercent -Watch $fakeWatch
if ($pctUnpack -lt 65 -or $pctUnpack -gt 99) {
    throw "unpack phase percent expected 65-99, got $pctUnpack"
}
Remove-Item Function:Test-VoltaInstallTmpHasNodeExe -ErrorAction SilentlyContinue
Remove-Item Function:Get-VoltaInstallTmpBytes -ErrorAction SilentlyContinue
. (Join-Path $toolRoot 'lib\browse-install-run.ps1')

$watch = New-VoltaNodeInstallProgressWatch -Version '99.99.99'
if ($watch.Ready) {
    throw 'unexpected HEAD success for fake version'
}

$watchUi = @{
    ItemSubPercent = -1
    StatusPlain    = $false
    StatusText     = ''
    ProgressName   = 'node@20.18.0'
}
$watchState = @{ }
$fakeWatch = @{
    Ready               = $true
    TotalBytes          = [int64]1000
    UnpackEstimateBytes = [int64]1000
    BaselineBytes       = [int64]0
    LastPercent         = -1
    DownloadStartTick   = 0
    InstallStartTick    = [Environment]::TickCount
    Phase               = 'starting'
}
function Test-VoltaInstallTmpHasNodeExe { return $false }
function Get-VoltaInstallTmpBytes { return [int64]0 }
$null = Update-NodeVoltaInstallProgressFromWatch -Ui $watchUi -Watch $fakeWatch -Redraw $redraw `
    -Version '20.18.0'
if ($watchUi.ItemSubPercent -ne 0) {
    throw "first watch tick should set 0%, got $($watchUi.ItemSubPercent)"
}
$fakeWatch.InstallStartTick = [Environment]::TickCount - 5000
function Get-VoltaInstallTmpBytes { return [int64]143412 }
$fakeWatch.LastPercent = -1
$null = Update-NodeVoltaInstallProgressFromWatch -Ui $watchUi -Watch $fakeWatch -Redraw $redraw `
    -Version '20.18.0'
if ($watchUi.ItemSubPercent -lt 2) {
    throw "second watch tick should advance download percent, got $($watchUi.ItemSubPercent)"
}
Remove-Item Function:Test-VoltaInstallTmpHasNodeExe -ErrorAction SilentlyContinue
Remove-Item Function:Get-VoltaInstallTmpBytes -ErrorAction SilentlyContinue
. (Join-Path $toolRoot 'lib\browse-install-run.ps1')
if (-not $decision.RedrawOnly) {
    throw 'progress line should be redraw-only'
}
if ($decision.LogText) {
    throw 'progress line should not be logged'
}

$successLine = 'success: installed and set node@20.18.0 (with npm@10.8.2) as default'
$decision2 = Get-VoltaInstallOutputDecision -Line $successLine -OutputState $state
if (-not $decision2.LogText) {
    throw 'success line should be logged once'
}
if (-not $state.LoggedSuccess) {
    throw 'success state should be marked'
}

$verboseState = @{ LoggedSuccess = $false; MinUnpackPercent = 0 }
$verboseLine = '[verbose] Unpacking node into ''C:\Users\meow\AppData\Local\Volta\tmp\.tmpABC'''
$verboseDecision = Get-VoltaInstallOutputDecision -Line $verboseLine -OutputState $verboseState
if (-not $verboseDecision.LogText -or $verboseDecision.LogText -notmatch '^Unpacking node') {
    throw 'verbose line should become log text without prefix'
}
if ($verboseState.VoltaPhase -ne 'unpacking' -or $verboseState.MinUnpackPercent -ne 66) {
    throw 'verbose unpack should mark unpack phase'
}

if (-not (Test-VoltaInstallStreamLineIsEphemeral -Line $progressLine)) {
    throw 'volta progress should be ephemeral'
}

$mockProc = New-Object System.Diagnostics.Process
$mockProc.StartInfo = New-Object System.Diagnostics.ProcessStartInfo
try { $mockProc.Start() | Out-Null } catch { }
if ($mockProc.HasExited) {
    $stdoutSub = Register-ObjectEvent -InputObject $mockProc -EventName OutputDataReceived -Action { } 
    $stderrSub = Register-ObjectEvent -InputObject $mockProc -EventName ErrorDataReceived -Action { }
    $state = @{
        Mode          = 'redirect'
        Process       = $mockProc
        Subscriptions = @($stdoutSub, $stderrSub)
    }
    $captured = @(Complete-NodeVoltaInstallProcessState -State $state)
    if ($captured.Count -ne 1) {
        throw "exit code capture should return one value, got $($captured.Count): $($captured -join ', ')"
    }
    Unregister-Event -SourceIdentifier $stdoutSub.Name -ErrorAction SilentlyContinue
    Unregister-Event -SourceIdentifier $stderrSub.Name -ErrorAction SilentlyContinue
}

if (-not (Test-VoltaConPtyAvailable)) {
    Write-Host 'test-volta-install-stream: OK (ConPTY unavailable, parser only)'
    exit 0
}

$session = New-Object MiaoVoltaConPtySession -ArgumentList @(
    "$env:SystemRoot\System32\ping.exe",
    '127.0.0.1 -n 2'
)
$deadline = [Environment]::TickCount + 30000
while (-not $session.HasExited -and [Environment]::TickCount -lt $deadline) {
    Start-Sleep -Milliseconds 50
}
if (-not $session.HasExited) {
    $session.Kill()
    throw 'ConPTY ping did not exit in time'
}
if ($session.ExitCode -ne 0) {
    throw "ConPTY ping exit code $($session.ExitCode)"
}
$session.Dispose()

Write-Host 'test-volta-install-stream: OK'
