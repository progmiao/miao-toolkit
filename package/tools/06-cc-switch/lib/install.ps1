# WinGet 简易工具 — 安装（检测/安装/更新）

param(
    [hashtable]$ToolkitShell = $null,
    $Action = $null,
    [int]$PageSize = 0,
    [int]$ViewHeight = 0
)

$ErrorActionPreference = 'Stop'
$toolRoot = Split-Path $PSScriptRoot -Parent
$coreLib = Join-Path $toolRoot '..\..\core\lib'
. (Join-Path $coreLib 'domain\Winget-SimpleTool.ps1')

$page = Initialize-WingetSimpleToolActionPage -ToolRoot $toolRoot -ToolkitShell $ToolkitShell `
    -PageSize $PageSize -ViewHeight $ViewHeight
$shell = $page.Shell
$sectionTitle = Get-WingetSimpleToolActionSectionTitle -ToolRoot $toolRoot -Action $Action `
    -ScriptLeaf 'install.ps1'

return Invoke-WingetSimpleToolInstallPage -Shell $shell -SectionTitle $sectionTitle `
    -ToolRoot $toolRoot -CoreLib $page.CoreLib
