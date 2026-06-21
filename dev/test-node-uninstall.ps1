$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\package\tools\node\lib\volta-node.ps1')

$ordered = Order-NodeVersionsForUninstall -VersionsToUninstall @('25.8.1', '25.8.2') -DefaultVersion '25.8.1'
Write-Output "order=$($ordered -join ',')"

$info = @{ '25.8.1' = $true; '25.8.2' = $true; '20.0.0' = $true }
$rep = Get-NodeDefaultReplacementVersion -InstalledMap $info -ExcludeVersion '25.8.1'
Write-Output "replacement=$rep"

$removedDefault = Test-VoltaDefaultVersionWasUninstalled -InitialDefault '25.8.1' `
    -SuccessfullyUninstalledVersions @('25.8.1')
Write-Output "removedDefault=$removedDefault"

$needsIntervention = Test-VoltaNodeDefaultNeedsIntervention -InstalledMap @{ '25.8.2' = $true } -CurrentDefault '25.8.2'
Write-Output "voltaHandled=$([bool](-not $needsIntervention))"

$needsIntervention2 = Test-VoltaNodeDefaultNeedsIntervention -InstalledMap @{ '25.8.2' = $true; '20.0.0' = $true } -CurrentDefault '20.0.0'
Write-Output "needsIntervention=$needsIntervention2"

$planDefault = Get-NodeBrowseUninstallOperationPlan -InitialDefault '25.8.1' `
    -InstalledMap @{ '25.8.1' = $true; '25.8.2' = $true; '20.0.0' = $true } `
    -OrderedVersions @('25.8.1')
Write-Output "planTotal=$($planDefault.TotalSteps) defaultPlanned=$($planDefault.DefaultRestorePlanned) replacement=$($planDefault.DefaultRestoreReplacement)"

$planNoDefault = Get-NodeBrowseUninstallOperationPlan -InitialDefault '25.8.1' `
    -InstalledMap @{ '25.8.1' = $true; '25.8.2' = $true } `
    -OrderedVersions @('25.8.2')
Write-Output "planNoDefaultTotal=$($planNoDefault.TotalSteps) defaultPlanned=$($planNoDefault.DefaultRestorePlanned)"

$planLast = Get-NodeBrowseUninstallOperationPlan -InitialDefault '25.8.1' `
    -InstalledMap @{ '25.8.1' = $true } `
    -OrderedVersions @('25.8.1')
Write-Output "planLastTotal=$($planLast.TotalSteps) defaultPlanned=$($planLast.DefaultRestorePlanned)"

$selected = Resolve-NodeBrowseUninstallSelectionVersions -Items @(
    [pscustomobject]@{ SearchKey = '22.0.0'; Source = [pscustomobject]@{ Version = '22.0.0' } }
)
Write-Output "selected=$($selected -join ',')"

if (Test-VoltaNodeVersionImageDirName -DirName 'v20.10.0' -Version '20.1.0') {
    throw '20.1.0 must not match v20.10.0'
}
if (-not (Test-VoltaNodeVersionImageDirName -DirName 'v20.1.0' -Version '20.1.0')) {
    throw '20.1.0 must match v20.1.0'
}

$orderedSingle = @((Order-NodeVersionsForUninstall -VersionsToUninstall @('26.3.1') -DefaultVersion '26.3.1'))
if ($orderedSingle.Count -ne 1 -or [string]$orderedSingle[0] -ne '26.3.1') {
    throw "single-version order failed: count=$($orderedSingle.Count) value=$($orderedSingle[0])"
}

$planned = @((Get-NodeBrowseUninstallPlanVersions -Items @(
    [pscustomobject]@{ Version = '26.3.1' }
) -InstalledMap @{ '26.3.1' = $true; '20.0.0' = $true }))
if ($planned.Count -ne 1 -or $planned[0] -ne '26.3.1') {
    throw "plan versions failed: $($planned -join '|')"
}

if (Test-VoltaNodeVersionAbsent -Version '') {
    throw 'empty version must not be treated as absent'
}

if (-not (Test-VoltaNodeUninstallLineIgnorable -Line 'error: Uninstalling node is not supported yet.')) {
    throw 'volta unsupported line should be ignorable'
}

if (-not (Test-VoltaNodeVersionInventoryArtifactName -Name 'node-v20.1.0-win-x64.zip' -Version '20.1.0')) {
    throw 'inventory zip name should match version'
}
if (-not (Test-VoltaNodeVersionInventoryArtifactName -Name 'node-v20.1.0-win-x64' -Version '20.1.0')) {
    throw 'inventory extract dir should match version'
}
if (Test-VoltaNodeVersionInventoryArtifactName -Name 'node-v20.10.0-win-x64.zip' -Version '20.1.0') {
    throw '20.1.0 must not match 20.10.0 inventory artifact'
}
if (-not (Test-VoltaNodeVersionInventoryArtifactName -Name 'node-v20.1.0-npm' -Version '20.1.0')) {
    throw 'inventory npm marker should match version'
}

$lib = Join-Path $PSScriptRoot '..\package\tools\node\lib'
foreach ($f in @('browse-uninstall.ps1', 'browse-uninstall-run.ps1', 'browse-install-run.ps1')) {
    $path = Join-Path $lib $f
    $tokens = $null
    $errs = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errs)
    if ($errs.Count -gt 0) {
        Write-Output "PARSE ERR $f"
        $errs | ForEach-Object { Write-Output $_.ToString() }
    }
    else {
        Write-Output "OK $f"
    }
}
