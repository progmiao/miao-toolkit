$ErrorActionPreference = 'Stop'
$r1 = [pscustomobject]@{ Cells = @('') }
Write-Host "null eq cells: $($null -eq $r1.Cells)"
Write-Host "not cells: $(-not $r1.Cells)"
Write-Host "cells count: $($r1.Cells.Count)"
Write-Host "props: $($r1.PSObject.Properties['Cells'] -ne $null)"
