$ErrorActionPreference = 'Stop'
$lib = Join-Path (Split-Path $PSScriptRoot -Parent) 'package\core\lib'
. (Join-Path $lib 'ui\shell\MultiSelectList.ps1')

$shell = @{ TestMultiListChecked = [System.Collections.Generic.HashSet[int]]::new() }
Write-Host "shell type: $($shell.GetType().FullName)"
$result = Get-ShellMultiSelectCheckedSet -Shell $shell -CacheKey 'Test'
Write-Host "result type: $($result.GetType().FullName)"
Write-Host "result null: $($null -eq $result)"
[void]$result.Add(1)
Write-Host 'CHECKED SET OK'
