# test-claude-code-tool.ps1 — claude-code 工具发现、i18n、设置与插件解析

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$lib = Join-Path $root 'package\core\lib'
. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib
Initialize-Paths -BinDirectory (Join-Path $root 'package\bin')

$toolRoot = Join-Path $root 'package\tools\04-claude-code'
Initialize-PathsFromToolRoot -ToolRoot $toolRoot

$tool = Get-ToolFromDirectory -ToolRoot $toolRoot
if (-not $tool) { throw 'tool not discovered' }
if ([string]$tool.command -ne 'claude-code') { throw "unexpected command: $($tool.command)" }
if ([int]$tool.sortOrder -ne 4) { throw "unexpected sortOrder: $($tool.sortOrder)" }

$name = Resolve-ToolI18nLabel -ToolRoot $toolRoot -Key 'claude-code.name' -Fallback 'claude-code'
if ([string]::IsNullOrWhiteSpace($name)) { throw 'name i18n empty' }

$actions = @((Get-Content (Join-Path $toolRoot 'index.json') -Raw -Encoding UTF8 | ConvertFrom-Json).actions)
if ($actions.Count -ne 9) { throw "expected 9 actions, got $($actions.Count)" }
if ($actions[0].command -ne 'install') { throw 'first action must be install' }
if ($actions[1].command -ne 'init') { throw 'second action must be init' }
$expectedCommands = @(
    'install', 'init', 'inst-plug', 'upd-plug', 'uninst-plug',
    'config-api', 'config-proxy', 'update', 'uninstall'
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
    (New-ClaudePluginMenuItem -PluginId 'alpha@test' -Enabled $true)
)
$sortedSample = @(Sort-ClaudePluginMenuItems -Items $sortSample -FeaturedOrderMap $featuredMap)
if ([string]$sortedSample[0].PluginId -ne 'superpowers@superpowers-marketplace') {
    throw 'featured plugin should sort first'
}
if ([string]$sortedSample[1].PluginId -ne 'alpha@test' -or [string]$sortedSample[2].PluginId -ne 'zebra@test') {
    throw 'non-featured plugins should sort by PluginId after featured'
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
