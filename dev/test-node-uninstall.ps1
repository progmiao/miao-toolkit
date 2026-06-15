$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\package\tools\node\lib\volta-node.ps1')

$ordered = Order-NodeVersionsForUninstall -VersionsToUninstall @('25.8.1', '25.8.2') -DefaultVersion '25.8.1'
Write-Output "order=$($ordered -join ',')"

$info = @{ '25.8.1' = $true; '25.8.2' = $true; '20.0.0' = $true }
$rep = Get-NodeDefaultReplacementVersion -InstalledMap $info -ExcludeVersion '25.8.1'
Write-Output "replacement=$rep"

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
