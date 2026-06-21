$ErrorActionPreference = 'Stop'
$lib = Join-Path (Split-Path $PSScriptRoot -Parent) 'package\core\lib'
. (Join-Path $lib 'config\Paths.ps1')
. (Join-Path $lib 'ui\console\Console-Menu.ps1')
. (Join-Path $lib 'domain\Ensure-ToolDeps.ps1')
. (Join-Path $lib 'domain\Invoke-ToolDepPackage.ps1')
$ms = New-Object System.IO.MemoryStream
$sw = New-Object System.IO.StreamWriter($ms, [Text.UTF8Encoding]::new($false))
$sw.Write("found`r")
$sw.Write("downloading 25%`r")
$sw.Write("downloading 80%`r")
$sw.Write("installed`n")
$sw.Flush()
$ms.Position = 0
$reader = New-Object System.IO.StreamReader($ms, [Text.UTF8Encoding]::new($false))
$buffer = New-WingetStreamLineBuffer

$lines = @(Read-WingetStreamAvailableLines $reader $buffer)
$lines += @(Complete-WingetStreamLineBuffer $buffer)

if ($lines.Count -lt 3) {
    throw "expected multiple progress lines, got $($lines.Count)"
}
if ($lines -notcontains 'installed') {
    throw 'expected final newline-terminated line'
}

if (-not (Test-WingetDepStreamLineIsEphemeral 'downloading 42%')) {
    throw 'percent lines should be ephemeral'
}
if (Test-WingetDepStreamLineIsEphemeral 'Found Volta [Volta.Volta] Version 2.0.2') {
    throw 'found lines should be logged'
}

$args = @(Build-ToolDepWingetArgumentList -Verb install -PackageId 'Volta.Volta' -Package @{
    install = @{ packageId = 'Volta.Volta' }
})
if ($args -notcontains '--silent' -or $args -contains '--disable-interactivity') {
    throw 'default install args should use silent-first and not force disable-interactivity'
}
if ($args -notcontains '--accept-package-agreements' -or $args -notcontains '--accept-source-agreements') {
    throw 'install should auto-accept winget agreements'
}

$interactivePkg = @(Build-ToolDepWingetArgumentList -Verb install -PackageId 'Example.App' -Package @{
    install = @{ packageId = 'Example.App'; wingetSilent = $false }
})
if ($interactivePkg -contains '--silent') {
    throw 'wingetSilent=false should skip --silent'
}

$requiredInteractive = @(Build-ToolDepWingetArgumentList -Verb install -PackageId 'Example.App' -Package @{
    install = @{ packageId = 'Example.App'; installInteractiveRequired = $true }
})
if ($requiredInteractive -contains '--silent') {
    throw 'installInteractiveRequired should skip --silent'
}

$silentPkg = @(Build-ToolDepWingetArgumentList -Verb install -PackageId 'Example.App' -Package @{
    install = @{ packageId = 'Example.App'; wingetSilent = $true }
})
if ($silentPkg -notcontains '--silent' -or $silentPkg -notcontains '--accept-package-agreements') {
    throw 'wingetSilent=true should add --silent and agreement flags'
}

$scoped = @(Build-ToolDepWingetArgumentList -Verb install -PackageId 'Volta.Volta' -Package @{
    install = @{ packageId = 'Volta.Volta'; scope = 'user' }
})
if ($scoped -notcontains '--scope' -or $scoped -notcontains 'user') {
    throw 'explicit scope should be passed through'
}

$uninstall = @(Build-ToolDepWingetArgumentList -Verb uninstall -PackageId 'Volta.Volta' -Package @{
    install = @{ packageId = 'Volta.Volta' }
})
if ($uninstall -contains '--silent') {
    throw 'uninstall should not use --silent by default'
}
if (-not (Test-WingetStreamLineIsSpinnerOnly -Line '|')) {
    throw 'spinner lines should be detected'
}
$ansiSpinner = ([char]0x1b).ToString() + '[1G|'
if (-not (Test-WingetStreamLineIsSpinnerOnly -Line $ansiSpinner)) {
    throw 'ANSI spinner lines should be detected'
}
$ansiBar = ([char]0x1b).ToString() + '[2K' + ([char]0x1b).ToString() + '[1G/'
if ((Get-WingetStreamLineCleanText -Line $ansiBar) -ne '/') {
    throw 'ANSI sequences should be stripped from winget stream lines'
}
if (-not (Test-WingetDepStreamLineIsEphemeral -Line '|')) {
    throw 'spinner lines should be ephemeral'
}

$p = Get-WingetDepStreamLinePercent -Line '  ████████▒▒▒▒  42%'
if ($p -ne 42) {
    throw "expected percent 42, got $p"
}
$p2 = Get-WingetDepStreamLinePercent -Line '2.00 MB / 3.01 MB'
if ($p2 -lt 60 -or $p2 -gt 70) {
    throw "expected ~66 percent from MB line, got $p2"
}
if ((Get-WingetDepStreamLinePhase -Line 'Waiting for another install to complete') -ne 'waitOther') {
    throw 'waitOther phase not detected'
}
if ((Get-WingetDepStreamLinePhase -Line 'Successfully verified installer hash') -ne 'verify') {
    throw 'verify-complete line should classify as verify phase'
}
if ((Get-WingetDepStreamLinePhase -Line 'Starting package install') -ne 'startInstall') {
    throw 'startInstall phase not detected for English winget line'
}
$urlPhase = Get-WingetDepStreamLinePhase -Line 'https://github.com/volta-cli/volta/releases/download/v2.0.2/volta-2.0.2.msi'
if ($urlPhase -eq 'installerPackage') {
    throw 'remote .msi URL should not classify as installer package path'
}
$policy = Get-WingetDepPolicyConstants
if ([int]$policy.InstallerPromptFailMs -lt 60000) {
    throw 'installer prompt fail ms should be at least one minute'
}

$block = [string][char]0x2588
$shade = [string][char]0x2592
$barOnly = "  $($block * 7)$($shade * 6)"
$pBar = Get-WingetDepStreamLinePercent -Line $barOnly
if ($pBar -lt 45 -or $pBar -gt 60) {
    throw "expected ~50 percent from block bar, got $pBar"
}
$barMb = "  $($block * 24)$($shade * 6)  4.32 MB"
$barDone = "  $($block * 30)  5.32 MB / 5.32 MB"
if (-not (Test-WingetDepStreamLineIsProgressVisual -Line $barOnly)) {
    throw 'block progress bar should be detected as progress visual'
}
if (Test-WingetStreamLineUseful -Line $barMb) {
    throw 'progress visual lines should not be stored as useful winget output'
}
if (-not (Test-WingetDepStreamLineIsEphemeral -Line $barDone)) {
    throw 'completed progress bar line should be ephemeral'
}
if ((Get-WingetDepStreamLinePhase -Line $barMb) -ne 'progress') {
    throw 'progress visual should classify as progress phase'
}

if ((Get-WingetDepStreamLineDeclineKind -Line 'Install failed with exit code: 1602') -ne 'user') {
    throw 'installer user abort should classify as user decline'
}
if ((Get-WingetDepStreamLineDeclineKind -Line 'The operation was canceled by the user') -ne 'uac') {
    throw 'UAC cancel line should classify as uac decline'
}

$sampleShow = @"
Installer Url: https://github.com/volta-cli/volta/releases/download/v2.0.2/volta.msi
安装程序 URL: https://example.com/pkg.exe
"@
$parsedUrls = @(Parse-WingetShowInstallerDownloadUrls -Text $sampleShow)
if ($parsedUrls.Count -ne 2) {
    throw "expected two parsed installer urls, got $($parsedUrls.Count)"
}

$brandW = 48
$sep = Format-ToolkitShellContentSeparator -BrandInnerWidth $brandW
$brandLine = Format-BrandHorizontalLine -BrandInnerWidth $brandW
if ((Get-DisplayWidth $sep) -ne (Get-DisplayWidth $brandLine)) {
    throw 'content separator width should match brand horizontal line'
}

Write-Host 'test-winget-stream: OK'
