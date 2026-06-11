$lib = Join-Path (Split-Path $PSScriptRoot -Parent) 'package\core\lib'
. (Join-Path $lib 'ui\shell\MultiSelectList.ps1')
(Get-Command Get-ShellMultiSelectCheckedSet).ScriptBlock.ToString()
