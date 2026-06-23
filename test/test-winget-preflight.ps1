$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$lib = Join-Path $root 'package\core\lib'
. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib
Initialize-Paths -BinDirectory (Join-Path $root 'package\bin')
Import-MiaoModule -Name ToolDeps

$wingetPlan = [pscustomobject]@{
    Items = @(
        [pscustomobject]@{
            ShouldExecute = $true
            _kind         = 'toolPackage'
            Status        = [pscustomobject]@{
                Package = [pscustomobject]@{
                    install = [pscustomobject]@{
                        type      = 'winget'
                        packageId = 'Volta.Volta'
                    }
                }
            }
        }
    )
}

$skipPlan = [pscustomobject]@{
    Items = @(
        [pscustomobject]@{
            ShouldExecute = $false
            _kind         = 'toolPackage'
            Status        = [pscustomobject]@{
                Package = [pscustomobject]@{
                    install = [pscustomobject]@{
                        type      = 'winget'
                        packageId = 'Volta.Volta'
                    }
                }
            }
        }
    )
}

if (-not (Test-ToolkitPlanNeedsWingetBackend -Plan $wingetPlan)) {
    throw 'winget backend plan should require winget'
}
if (Test-ToolkitPlanNeedsWingetBackend -Plan $skipPlan) {
    throw 'skipped plan items should not require winget backend'
}

if (Test-WingetCliAvailable) {
    if (Get-ToolkitDepWingetPreflightErrorKey -Plan $wingetPlan) {
        throw 'preflight should pass when winget is available'
    }
}
else {
    if ((Get-ToolkitDepWingetPreflightErrorKey -Plan $wingetPlan) -ne 'page.depOperation.wingetMissing') {
        throw 'preflight should return wingetMissing when winget unavailable'
    }
}

if (Get-ToolkitDepWingetPreflightErrorKey -Plan $skipPlan) {
    throw 'preflight should not run when no executable winget work'
}

$tools = @(Discover-Tools)
$node = Get-Tool 'node' -Tools $tools
if (-not $node) { throw 'node tool missing' }

$built = Build-ToolkitDepOperationPlan -Tool $node -Intent install -AllTools $tools
$runtimeItems = @($built.Items | Where-Object { $_. _kind -eq 'runtime' })
if ($runtimeItems.Count -gt 0) {
    throw 'Build-ToolkitDepOperationPlan must not inject winget runtime items'
}

Write-Host 'test-winget-preflight: OK'
