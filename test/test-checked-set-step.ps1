$ErrorActionPreference = 'Continue'
$lib = Join-Path (Split-Path $PSScriptRoot -Parent) 'package\core\lib'
. (Join-Path $lib 'ui\shell\MultiSelectList.ps1')

$shell = @{ TestMultiListChecked = [System.Collections.Generic.HashSet[int]]::new() }
$field = Get-ShellMultiSelectCheckedFieldName -CacheKey 'Test'
Write-Host "field=[$field]"
Write-Host "shell has key: $($shell.ContainsKey($field))"
$set = $shell[$field]
Write-Host "set null: $($null -eq $set)"
Write-Host "set type: $($set.GetType().FullName)"

$out = Get-ShellMultiSelectCheckedSet -Shell $shell -CacheKey 'Test'
Write-Host "out null: $($null -eq $out)"
Write-Host "out count: $(@($out).Count)"
