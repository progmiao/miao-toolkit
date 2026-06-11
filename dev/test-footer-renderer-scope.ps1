$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$lib = Join-Path $root 'package\core\lib'
. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib
Initialize-Paths -BinDirectory (Join-Path $root 'package\bin')

Import-MiaoModule -Name Cache

$global:TestFooterRendererScope = {
    $shell = Initialize-ToolkitShell
    Initialize-ToolkitShellBodyView -Shell $shell -SectionTitle 'test' -FooterTemplate SystemToolbarOnly
    $toolbar = New-ShellSystemToolbarConfig -HideBack -HideSystem -HideHelp
    $renderFooter = New-ShellSystemToolbarFooterRenderer -Shell $shell -ToolbarConfig $toolbar
    & $renderFooter
    Write-Host 'FOOTER RENDERER SCOPE OK'
}.GetNewClosure()

& $global:TestFooterRendererScope
