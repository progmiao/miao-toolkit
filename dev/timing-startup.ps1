$ErrorActionPreference = 'Stop'
$lib = 'F:\code\miao\miao-toolkit\package\core\lib'
$bin = 'F:\code\miao\miao-toolkit\package\bin'

$sw = [System.Diagnostics.Stopwatch]::StartNew()
. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib
$tLoad = $sw.ElapsedMilliseconds

Initialize-Paths -BinDirectory $bin
$tPaths = $sw.ElapsedMilliseconds

$tools = @(Discover-Tools)
$tDiscover = $sw.ElapsedMilliseconds

$null = New-ToolkitMenuHeader -HideSectionTitle
$tHeaderMeta = $sw.ElapsedMilliseconds

$null = Get-ToolkitHomeRowCache -Shell $null -Tools $tools
$tRowCache = $sw.ElapsedMilliseconds

Write-Output "Load-Core parse:     $tLoad ms"
Write-Output "Initialize-Paths:    $($tPaths - $tLoad) ms"
Write-Output "Discover-Tools:      $($tDiscover - $tPaths) ms (count=$($tools.Count))"
Write-Output "Header metadata:     $($tHeaderMeta - $tDiscover) ms"
Write-Output "Home row cache:      $($tRowCache - $tHeaderMeta) ms"
Write-Output "Total (no UI draw):  $tRowCache ms"

$menuFile = Join-Path $lib 'ui\console\Console-Menu.ps1'
$info = Get-Item $menuFile
Write-Output "Console-Menu.ps1:    $([math]::Round($info.Length/1KB)) KB, $((Get-Content $menuFile).Count) lines"
