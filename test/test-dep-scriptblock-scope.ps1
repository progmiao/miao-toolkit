$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$lib = Join-Path $root 'package\core\lib'
$bin = Join-Path $root 'package\bin'
$toolRoot = Join-Path $root 'package\tools\01-node'

. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib
. (Join-Path $lib 'config\Paths.ps1')
Initialize-Paths -BinDirectory $bin
Import-MiaoToolDepsModule

& {
    $coreLib = Join-Path $root 'package\core\lib'
    . (Join-Path $coreLib 'ui\console\Console-Menu.ps1')
    Import-MiaoToolDepsModule

    function Test-GlobalRedrawClosure {
        $fnEnterBatch = Resolve-DepOperationFn 'Enter-ConsoleDrawBatch'
        $fnCompleteBatch = Resolve-DepOperationFn 'Complete-ConsoleDrawBatch'

        $RedrawDepOperationView = {
            & $fnEnterBatch
            & $fnCompleteBatch
        }.GetNewClosure()

        $onOutputLine = {
            param($Line)
            & $RedrawDepOperationView
        }.GetNewClosure()

        & $onOutputLine 'test-line'
    }
    Set-Item function:global:Test-GlobalRedrawClosure (Get-Command Test-GlobalRedrawClosure).ScriptBlock
    Test-GlobalRedrawClosure
    Write-Host 'Test-GlobalRedrawClosure: OK'
}

Write-Host 'test-dep-scriptblock-scope: OK'
