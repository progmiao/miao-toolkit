$ErrorActionPreference = 'Stop'
$lib = Join-Path (Split-Path $PSScriptRoot -Parent) 'package\core\lib'
. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib

$keys = Get-MiaoI18nKeys
if (-not $keys.Enter) { throw 'missing Enter key' }
$tb = New-ShellSystemToolbarConfig -HideBack
if ($tb.Segments.Count -lt 1) { throw 'empty toolbar' }
Write-Host 'I18NKEYS SCOPE OK'
