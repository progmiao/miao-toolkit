$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$lib = Join-Path $root 'package\core\lib'
$bin = Join-Path $root 'package\bin'
$toolRoot = Join-Path $root 'package\tools\node'

. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib
. (Join-Path $lib 'config\Paths.ps1')
Initialize-Paths -BinDirectory $bin
Initialize-Console
Import-MiaoModule -Name Tool

$coreLib = Join-Path $toolRoot '..\..\core\lib'
foreach ($rel in @(
        'domain\Ensure-ToolDeps.ps1'
        'config\Deps-State.ps1'
        'domain\Invoke-ToolDepPackage.ps1'
        'domain\Invoke-ToolkitDepOperation.ps1'
        'ui\shell\DepOperationView.ps1'
        'ui\shell\ToolkitDepBatchOperation.ps1'
        'domain\Invoke-ToolkitDeps.ps1'
    )) {
    . (Join-Path $coreLib $rel)
}

$shell = Initialize-ToolkitShell
$tool = Get-ToolFromDirectory -ToolRoot $toolRoot

# Simulate onBeforeExecute path
$plan = Build-ToolDepSyncPlan -Tool $tool -Intent install
$ctx = Initialize-ToolkitDepBatchOperationView -Shell $shell -SectionTitle 'deps' -ProgressTotal 1
$log = $ctx.Log
$ui = $ctx.Ui
$ui.ItemInFlight = $true
$fnGetI18n = Resolve-DepOperationFn 'Get-I18n'
$fnAddLog = Resolve-DepOperationFn 'Add-ToolkitDepLogLine'
$fnUpdateLoading = Resolve-DepOperationFn 'Update-ToolkitDepLoadingStatus'
$wingetOutputState = @{
    ExecuteAction = 'Install'
    WingetOutputSeen = $false
    InstallerAwaitingDialog = $false
    InstallStarted = $false
    InstallerPromptDismissed = $false
}

& $fnAddLog -Log $log -Text 'exec winget test' -WithTimestamp
& $fnAddLog -Log $log -Text 'may prompt line' -Kind 'heading' -WithTimestamp

try {
    & $fnAddLog -Log $log -Text (& $fnGetI18n -Key 'page.depOperation.logWingetStarting') -WithTimestamp
    $ui.ExecuteStartTick = [Environment]::TickCount
    $null = & $fnUpdateLoading -Ui $ui -WingetOutputState $wingetOutputState -ElapsedSeconds 0 -GetI18n $fnGetI18n
    $ctx.BrandRepairState.Requested = $true
    & $ctx.RedrawView
    Write-Host 'onBeforeExecute-sim: OK'
}
catch {
    Write-Host "FAIL $($_.Exception.GetType().FullName) $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    exit 1
}
