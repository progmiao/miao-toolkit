# test-claude-code-tool.ps1 — claude-code 工具发现、i18n、设置与插件解析

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$lib = Join-Path $root 'package\core\lib'
. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib
Initialize-Paths -BinDirectory (Join-Path $root 'package\bin')

$toolRoot = Join-Path $root 'package\tools\05-claude-code'
Initialize-PathsFromToolRoot -ToolRoot $toolRoot

$tool = Get-ToolFromDirectory -ToolRoot $toolRoot
if (-not $tool) { throw 'tool not discovered' }
if ([string]$tool.command -ne 'claude-code') { throw "unexpected command: $($tool.command)" }
if ([int]$tool.sortOrder -ne 5) { throw "unexpected sortOrder: $($tool.sortOrder)" }

$name = Resolve-ToolI18nLabel -ToolRoot $toolRoot -Key 'claude-code.name' -Fallback 'claude-code'
if ([string]::IsNullOrWhiteSpace($name)) { throw 'name i18n empty' }

$actions = @((Get-Content (Join-Path $toolRoot 'index.json') -Raw -Encoding UTF8 | ConvertFrom-Json).actions)
if ($actions.Count -ne 7) { throw "expected 7 actions, got $($actions.Count)" }
if ($actions[0].command -ne 'install') { throw 'first action must be install' }
if ($actions[1].command -ne 'init') { throw 'second action must be init' }
$expectedCommands = @(
    'install', 'init', 'inst-plug', 'uninst-plug',
    'config-api', 'config-proxy', 'uninstall'
)
for ($i = 0; $i -lt $expectedCommands.Count; $i++) {
    if ([string]$actions[$i].command -ne $expectedCommands[$i]) {
        throw "action[$i] command should be [$($expectedCommands[$i])], got [$($actions[$i].command)]"
    }
}

. (Join-Path $toolRoot 'lib\claude-code-core.ps1')
. (Join-Path $toolRoot 'lib\claude-code-state.ps1')
. (Join-Path $toolRoot 'lib\claude-settings.ps1')
. (Join-Path $toolRoot 'lib\claude-plugin.ps1')
. (Join-Path $toolRoot 'lib\claude-code-presets.ps1')

if ((Compare-ClaudeSemVersion -Left '2.0.0' -Right '1.9.9') -ne 1) { throw 'Compare-ClaudeSemVersion gt failed' }
if ((Compare-ClaudeSemVersion -Left '1.0.0' -Right '1.0.0') -ne 0) { throw 'Compare-ClaudeSemVersion eq failed' }

$latestResolved = Resolve-ClaudePluginLatestVersion -PluginId 'alpha@test' -AvailableVersion '6.1.1' `
    -CatalogVersionMap @{ 'alpha@test' = '6.0.3' }
if ($latestResolved -ne '6.1.1') {
    throw "latest version should prefer higher available/catalog semver, got [$latestResolved]"
}
$installedEntry = New-ClaudePluginMenuItem -PluginId 'alpha@test' -Version '6.0.3' `
    -InstalledVersion '6.1.1' -Tags '' -Enabled $false
$installedOnlyRows = Build-ClaudePluginManageRows -Items @($installedEntry) -ToolRoot $toolRoot
if ([string]$installedOnlyRows[0].Cells[3] -match '已安装|installed') {
    throw 'installed version ahead of stale latest should not show installed tag'
}
if ([string]$installedOnlyRows[0].Cells[3] -ne '6.1.1') {
    throw "installed status cell should show current version only when ahead of latest, got [$($installedOnlyRows[0].Cells[3])]"
}

$catalogMap = @{ 'beta@test' = '6.0.3' }
$updateEntry = [pscustomobject]@{ PluginId = 'beta@test'; version = '6.1.0' }
if (-not (Test-ClaudePluginUpdateAvailable -InstalledEntry $updateEntry -CatalogVersionMap $catalogMap `
        -AvailableVersion '6.2.0')) {
    throw 'update should be available when CLI available version exceeds installed'
}

$split = Split-ClaudePluginId -PluginId 'superpowers@claude-plugins-official'
if ($split.Name -ne 'superpowers' -or $split.Marketplace -ne 'claude-plugins-official') {
    throw 'Split-ClaudePluginId failed'
}

$marketPresets = @(Get-ClaudeCodeMarketplacePresets -ToolRoot $toolRoot)
if ($marketPresets.Count -ne 3) { throw "expected 3 marketplace presets, got $($marketPresets.Count)" }
if ([string]$marketPresets[0].Source -ne 'obra/superpowers-marketplace') {
    throw 'unexpected first marketplace preset source'
}

$featuredMap = Get-ClaudeCodeFeaturedPluginOrderMap -ToolRoot $toolRoot
if ($featuredMap.Count -ne 1) {
    throw "expected 1 featured plugin preset, got $($featuredMap.Count)"
}
if (-not $featuredMap.ContainsKey('superpowers@superpowers-marketplace')) {
    throw 'featured plugin preset missing superpowers@superpowers-marketplace'
}

$sortSample = @(
    (New-ClaudePluginMenuItem -PluginId 'zebra@test' -Enabled $true)
    (New-ClaudePluginMenuItem -PluginId 'superpowers@superpowers-marketplace' -Featured $true -Enabled $true)
    (New-ClaudePluginMenuItem -PluginId 'alpha@test' -Tags 'installed' -Enabled $false)
    (New-ClaudePluginMenuItem -PluginId 'beta@test' -Tags 'installed' -Featured $true -Enabled $false)
    (New-ClaudePluginMenuItem -PluginId 'gamma@test' -Enabled $true)
)
$installedMap = @{
    'alpha@test' = $true
    'beta@test'  = $true
}
$sortedSample = @(Sort-ClaudePluginMenuItems -Items $sortSample -FeaturedOrderMap $featuredMap `
    -InstalledMap $installedMap)
if ([string]$sortedSample[0].PluginId -ne 'beta@test') {
    throw 'installed featured plugin should sort first'
}
if ([string]$sortedSample[1].PluginId -ne 'alpha@test') {
    throw 'installed non-featured plugin should sort after installed featured'
}
if ([string]$sortedSample[2].PluginId -ne 'superpowers@superpowers-marketplace') {
    throw 'featured installable plugin should sort before other installable plugins'
}
if ([string]$sortedSample[3].PluginId -ne 'gamma@test' -or [string]$sortedSample[4].PluginId -ne 'zebra@test') {
    throw 'remaining plugins should sort by PluginId'
}

$marketItems = @($marketPresets | ForEach-Object {
    New-ClaudePluginMenuItem -PluginId ([string]$_.Source) -Description ([string]$_.Label) `
        -Enabled $true -Source $_
})
$marketRows = Build-ClaudePluginRows -Items $marketItems -ToolRoot $toolRoot
if ($marketRows.Count -lt 1) { throw 'marketplace rows empty' }
if (@($marketRows[0].Cells).Count -ne 2) {
    throw "marketplace row expected 2 cells, got $(@($marketRows[0].Cells).Count)"
}

$pluginLayout = New-ClaudePluginListLayout
if ([string]$pluginLayout.Preset -ne 'HalfSplit') {
    throw 'plugin list layout should use HalfSplit preset'
}
if ([int]$pluginLayout.ScrollColumn -ne 1) {
    throw 'plugin list layout should scroll detail column'
}

$featuredItem = New-ClaudePluginMenuItem -PluginId 'superpowers@superpowers-marketplace' -Featured $true -Enabled $true
$plainItem = New-ClaudePluginMenuItem -PluginId 'alpha@test' -Enabled $true
$featuredRows = Build-ClaudePluginRows -Items @($featuredItem) -ToolRoot $toolRoot
if (-not $featuredRows[0].CellColors -or $featuredRows[0].CellColors[0] -ne (Get-ClaudeFeaturedPluginNameColor)) {
    throw 'featured plugin row should color plugin id column'
}

$shell = @{ BrandInnerWidth = 120; LayoutLineMetrics = @{ StartColumn = 0; EndColumn = 100 } }
$resolved = Resolve-ShellListLayout -Shell $shell -Layout $pluginLayout -NumWidth 0 -Mode Multi `
    -HideNumberColumn
if ([int]$resolved.Widths[0] -lt 30 -or [int]$resolved.Widths[1] -lt 30) {
    throw "plugin columns too narrow: $($resolved.Widths[0]), $($resolved.Widths[1])"
}
$halfDelta = [Math]::Abs([int]$resolved.Widths[0] - [int]$resolved.Widths[1])
if ($halfDelta -gt 2) {
    throw "plugin columns should split roughly half: $($resolved.Widths[0]) vs $($resolved.Widths[1])"
}

$specNoNum = Build-ShellMultiSelectListRowSpec -RowCacheEntry @{
    BodyPlain    = 'plugin-id          detail'
    BodySegments = @(
        @{ Text = 'plugin-id          '; Color = [System.ConsoleColor]::Gray }
        @{ Text = 'detail'; Color = [System.ConsoleColor]::Gray }
    )
    LineColor    = [System.ConsoleColor]::Gray
    Enabled      = $true
} -Selected $false -Checked $false -NumWidth 0 -DisplayNumber 1 -Gap '  ' -HideNumberColumn
if ($specNoNum.Segments[0].Text -match '\d{2}') {
    throw 'HideNumberColumn should not render number prefix'
}
if ($specNoNum.Segments[0].Text -notmatch '\[ \]$') {
    throw 'first column should sit adjacent to check mark'
}

$manageLayout = New-ClaudePluginManageListLayout -Shell $shell
$manageResolved = Resolve-ShellListLayout -Shell $shell -Layout $manageLayout -NumWidth 0 -Mode Multi `
    -HideNumberColumn
if ($manageLayout.ContainsKey('Headers')) {
    throw 'manage plugin layout should not expose column headers'
}
if ([int]$manageResolved.Widths[0] -ne [int]$resolved.Widths[0]) {
    throw 'manage plugin name column width should match install'
}
if (@($manageResolved.Widths).Count -ne 4) {
    throw 'manage plugin layout should have 4 columns'
}
if ([int]$manageLayout.ScrollColumn -ne 3) {
    throw 'manage plugin status column should scroll'
}

$uninstallLayout = New-ClaudePluginUninstallListLayout -Shell $shell
$uninstallResolved = Resolve-ShellListLayout -Shell $shell -Layout $uninstallLayout -NumWidth 0 -Mode Multi `
    -HideNumberColumn
if ([int]$uninstallResolved.Widths[0] -ne [int]$resolved.Widths[0]) {
    throw 'uninstall plugin name column width should match install'
}
if ($uninstallLayout.ContainsKey('Headers')) {
    throw 'uninstall plugin layout should not expose column headers'
}
if (@($uninstallResolved.Widths).Count -ne 3) {
    throw 'uninstall plugin layout should have 3 columns'
}

$manageRows = Build-ClaudePluginManageRows -Items @(
    (New-ClaudePluginMenuItem -PluginId 'superpowers@superpowers-marketplace' -Version '1.1.0' `
        -InstalledVersion '1.0.0' -Tags 'installed' -Enabled $false)
    (New-ClaudePluginMenuItem -PluginId 'beta@test' -Version '2.1.0' -InstalledVersion '2.0.0' `
        -UpdateVersion '2.1.0' -HasUpdate $true -Tags 'update:2.1.0' -Enabled $true)
    (New-ClaudePluginMenuItem -PluginId 'gamma@test' -Version '1.0.0' -Enabled $true)
) -ToolRoot $toolRoot
if (@($manageRows[0].Cells).Count -ne 4) {
    throw "manage row expected 4 cells, got $(@($manageRows[0].Cells).Count)"
}
if ([string]$manageRows[0].Cells[0] -ne 'superpowers') {
    throw 'manage row should show plugin short name in first column'
}
if ([string]$manageRows[0].Cells[1] -ne 'superpowers-marketplace') {
    throw 'manage row should show marketplace name in second column'
}
if ([string]$manageRows[0].Cells[2] -ne '1.1.0') {
    throw 'manage row latest version cell mismatch'
}
if ($manageRows[0].Enabled -ne $false -or $manageRows[1].Enabled -ne $true -or $manageRows[2].Enabled -ne $true) {
    throw 'manage rows should disable only installed up-to-date plugins'
}
if ([string]$manageRows[0].Cells[3] -notmatch '1\.0\.0') {
    throw 'installed status cell should show current version'
}
if ([string]$manageRows[2].Cells[3] -ne '-') {
    throw 'not installed plugin should show dash in status column'
}

$orphanInstalled = New-ClaudePluginMenuItem -PluginId 'orphan@test' -Version '1.0.0' `
    -InstalledVersion '1.0.0' -Tags 'installed' -Enabled $false
if (-not (Test-ClaudePluginMenuItemInstalled -Item $orphanInstalled)) {
    throw 'installed-only menu item should be detected as installed'
}
$orphanRows = Build-ClaudePluginManageRows -Items @($orphanInstalled) -ToolRoot $toolRoot
if ([string]$orphanRows[0].Cells[3] -notmatch '1\.0\.0') {
    throw 'installed-only plugin should show current version in status column'
}

$uninstallRows = Build-ClaudePluginUninstallRows -Items @(
    (New-ClaudePluginMenuItem -PluginId 'superpowers@superpowers-marketplace' -Version '1.0.0' -Enabled $true)
)
if (@($uninstallRows[0].Cells).Count -ne 3) {
    throw "uninstall row expected 3 cells, got $(@($uninstallRows[0].Cells).Count)"
}
if ([string]$uninstallRows[0].Cells[0] -ne 'superpowers') {
    throw 'uninstall row should show plugin short name in first column'
}
if ([string]$uninstallRows[0].Cells[1] -ne 'superpowers-marketplace') {
    throw 'uninstall row should show marketplace name in second column'
}
if ([string]$uninstallRows[0].Cells[2] -ne '1.0.0') {
    throw 'uninstall row version cell mismatch'
}

function Test-ParseClaudeVersionLine {
    param([string]$Line)
    if ($Line -match '(\d+\.\d+\.\d+)') { return $Matches[1] }
    return $Line
}
if ('2.1.186' -ne (Test-ParseClaudeVersionLine '2.1.186 (Claude Code)')) {
    throw 'version semver extract failed'
}

if (Get-Command Resolve-ClaudeCodeWingetInstallVerb -ErrorAction SilentlyContinue) {
    # Dot-sourced above; verb defaults to install when winget package absent
    $verb = Resolve-ClaudeCodeWingetInstallVerb
    if ($verb -notin @('install', 'upgrade')) {
        throw "unexpected winget verb: $verb"
    }
}

$notWingetMsg = Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.cli.uninstallNotWingetManaged' `
    -Vars @{ path = 'C:\test\claude.cmd'; version = '1.0.0' }
if ($notWingetMsg -notmatch '1\.0\.0' -or $notWingetMsg -notmatch 'claude\.cmd') {
    throw 'uninstallNotWingetManaged i18n interpolation failed'
}

$coreLib = Join-Path $root 'package\core\lib'
$longDetail = ('x' * 80)
if (-not (Test-ShellListCellTextOverflow -Text $longDetail -Width 20)) {
    throw 'overflow detection failed'
}
$window = Format-ShellListTableCellText -Text $longDetail -Width 20 -MarqueeOffset 3 -MarqueeActive
if ($window.Length -ne 20) { throw "marquee window width should pad to 20, got $($window.Length)" }

. (Join-Path $coreLib 'domain\Ensure-ToolDeps.ps1')
$listSample = @"
名称        ID                   版本    源
------------------------------------------------
Claude Code Anthropic.ClaudeCode 2.1.187 winget
"@
$parsedVer = Get-WingetPackageInstalledVersionFromListText -Text $listSample -PackageId 'Anthropic.ClaudeCode'
if ($parsedVer -ne '2.1.187') {
    throw "winget list text parse failed, got [$parsedVer]"
}

if (-not (Test-ClaudeCodeInstalled -CoreLib $coreLib)) {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        $wingetListed = winget list --id Anthropic.ClaudeCode -e 2>&1 | Out-String
        if ($wingetListed -match 'Anthropic\.ClaudeCode') {
            throw 'Test-ClaudeCodeInstalled should detect WinGet package when CoreLib is provided'
        }
    }
}

$tmpdir = Join-Path ([IO.Path]::GetTempPath()) ("miao-cc-test-" + [Guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path $tmpdir -Force | Out-Null
$prevHome = $env:USERPROFILE
$prevAppData = $env:APPDATA
try {
    $fakeHome = Join-Path $tmpdir 'home'
    $fakeAppData = Join-Path $tmpdir 'appdata'
    New-Item -ItemType Directory -Path (Join-Path $fakeHome '.claude') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $fakeAppData 'Miao') -Force | Out-Null
    $env:USERPROFILE = $fakeHome
    $env:APPDATA = $fakeAppData
    Set-Item -Path Env:HOME -Value $fakeHome

    $path = Apply-ClaudeCodeInitDefaults
    if (-not (Test-Path -LiteralPath $path)) { throw 'init defaults did not write settings' }
    $settings = Get-Content -Raw -LiteralPath $path -Encoding UTF8 | ConvertFrom-Json
    if ([string]$settings.env.DISABLE_LOGIN_COMMAND -ne '1') {
        throw 'DISABLE_LOGIN_COMMAND not set'
    }

    $apiPath = Apply-ClaudeCodeApiSecrets -ApiConfig @{
        mode   = 'official'
        apiKey = 'test-key'
    }
    if (-not (Test-Path -LiteralPath $apiPath)) { throw 'api settings not written' }
    $settings2 = Get-Content -Raw -LiteralPath $apiPath -Encoding UTF8 | ConvertFrom-Json
    if ([string]$settings2.env.ANTHROPIC_API_KEY -ne 'test-key') {
        throw 'ANTHROPIC_API_KEY not merged'
    }

    $clearPath = Apply-ClaudeCodeApiSecrets -ApiConfig @{ mode = 'clear' }
    $settings3 = Get-Content -Raw -LiteralPath $clearPath -Encoding UTF8 | ConvertFrom-Json
    if ($settings3.env.PSObject.Properties['ANTHROPIC_API_KEY']) {
        throw 'api clear should remove ANTHROPIC_API_KEY'
    }
}
finally {
    $env:USERPROFILE = $prevHome
    $env:APPDATA = $prevAppData
    Remove-Item -LiteralPath $tmpdir -Recurse -Force -ErrorAction SilentlyContinue
}

$discovered = Discover-Tools -BundledToolsRoot (Join-Path $root 'package\tools')
$cc = @($discovered | Where-Object { $_.command -eq 'claude-code' } | Select-Object -First 1)
if (-not $cc) { throw 'claude-code missing from Discover-Tools' }
if ([int]$cc.no -lt 1) { throw 'claude-code menu no not assigned' }

Write-Host 'test-claude-code-tool: OK'
