# 工具箱初始化快照：品牌区、工具目录、首页列表、各工具依赖状态（仅探测，不安装）

$script:ToolkitToolsMemoryCache = $null
$script:ToolkitDiskListRowCaches = @{}
$script:ToolkitInitManifest = $null
$script:ToolkitInitToolStateCache = $null
$script:ToolkitSessionInitValid = $null
$script:ToolkitSessionInitValidLocale = $null
$script:ToolkitHomeBrandSnapshot = $null
$script:ToolkitHomeBrandSnapshotLocale = $null
$script:ToolkitHomeRowsPayloadCache = $null
$script:ToolkitHomeRowsPayloadLocale = $null

function Clear-ToolkitSessionInitState {
    $script:ToolkitSessionInitValid = $null
    $script:ToolkitSessionInitValidLocale = $null
    $script:ToolkitHomeBrandSnapshot = $null
    $script:ToolkitHomeBrandSnapshotLocale = $null
    $script:ToolkitHomeRowsPayloadCache = $null
    $script:ToolkitHomeRowsPayloadLocale = $null
}

function Set-ToolkitSessionInitValidState {
    param(
        [bool]$Valid,
        [string]$Locale = (Get-CurrentLocale)
    )

    $script:ToolkitSessionInitValid = $Valid
    $script:ToolkitSessionInitValidLocale = [string]$Locale
}

function Get-ToolkitInitRoot {
    $dir = Join-Path (Get-UserConfigDirectory) 'init'
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return $dir
}

function Get-ToolkitInitManifestPath {
    Join-Path (Get-ToolkitInitRoot) 'manifest.json'
}

function Get-ToolkitInitBrandPath {
    param([string]$Locale)

    Join-Path (Get-ToolkitInitRoot) "brand.$Locale.json"
}

function Get-ToolkitInitCatalogPath {
    param([string]$Locale)

    Join-Path (Get-ToolkitInitRoot) "catalog.$Locale.json"
}

function Get-ToolkitInitHomeRowsPath {
    param([string]$Locale)

    Join-Path (Get-ToolkitInitRoot) "rows.$Locale.home.json"
}

function Get-ToolkitInitToolsStatePath {
    Join-Path (Get-ToolkitInitRoot) 'tools-state.json'
}

function Get-ToolkitInitFileHash {
    param([string]$Path)

    if (-not (Test-Path $Path)) { return '' }
    $bytes = [IO.File]::ReadAllBytes($Path)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-ToolkitInitStringHash {
    param([string]$Text)

    $bytes = [Text.Encoding]::UTF8.GetBytes([string]$Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-ToolkitInitSourceFiles {
    $files = @()
    $manifestPath = Get-ManifestRawPath
    if (Test-Path $manifestPath) { $files += $manifestPath }

    $i18nRoot = Get-I18nRoot
    if (Test-Path $i18nRoot) {
        $files += @(Get-ChildItem -Path $i18nRoot -Filter '*.json' -File |
            Where-Object { -not $_.Name.StartsWith('_') } |
            ForEach-Object { $_.FullName })
    }

    $coreLibDir = $script:MiaoCoreLibDir
    if ([string]::IsNullOrWhiteSpace($coreLibDir)) {
        $coreLibDir = $global:MiaoCoreLibDir
    }
    $layoutPath = Join-Path $coreLibDir 'config\ListLayout.ps1'
    if (Test-Path $layoutPath) { $files += $layoutPath }

    $toolsRoot = Get-BundledToolsRoot
    if (Test-Path $toolsRoot) {
        Get-ChildItem -Path $toolsRoot -Directory | ForEach-Object {
            $indexPath = Join-Path $_.FullName 'index.json'
            if (Test-Path $indexPath) { $files += $indexPath }
            $toolI18n = Join-Path $_.FullName 'i18n'
            if (Test-Path $toolI18n) {
                $files += @(Get-ChildItem -Path $toolI18n -Filter '*.json' -File | ForEach-Object { $_.FullName })
            }
        }
    }

    $externalToolsRoot = Get-ExternalToolsRoot
    if (Test-Path $externalToolsRoot) {
        Get-ChildItem -Path $externalToolsRoot -Directory | ForEach-Object {
            $indexPath = Join-Path $_.FullName 'index.json'
            if (Test-Path $indexPath) { $files += $indexPath }
            $toolI18n = Join-Path $_.FullName 'i18n'
            if (Test-Path $toolI18n) {
                $files += @(Get-ChildItem -Path $toolI18n -Filter '*.json' -File | ForEach-Object { $_.FullName })
            }
        }
    }

    return @($files | Sort-Object -Unique)
}

function New-ToolkitInitFingerprint {
    $parts = @()
    foreach ($path in @(Get-ToolkitInitSourceFiles)) {
        $parts += "$(Get-ToolkitInitFileHash -Path $path)|$path"
    }
    return (Get-ToolkitInitStringHash -Text ([string]::Join([char]0, $parts)))
}

function Convert-ToolToInitRecord {
    param($Tool)

    $record = [ordered]@{}
    foreach ($prop in $Tool.PSObject.Properties) {
        if ($prop.Name -eq '_mock') { continue }
        $record[$prop.Name] = $prop.Value
    }
    return [pscustomobject]$record
}

function Convert-InitRecordToTool {
    param($Record)

    if ($null -eq $Record) { return $null }
    if ($Record -is [pscustomobject]) {
        return $Record
    }
    return [pscustomobject]$Record
}

function Export-ToolkitRowCacheBuilt {
    param(
        $Built,
        [array]$Rows
    )

    $entries = @()
    for ($i = 0; $i -lt $Built.RowCache.Count; $i++) {
        $entry = $Built.RowCache[$i]
        $sourceKey = ''
        if ($entry.Source) {
            if ($entry.Source.command) { $sourceKey = [string]$entry.Source.command }
            elseif ($entry.Source.id) { $sourceKey = [string]$entry.Source.id }
        }
        elseif ($i -lt $Rows.Count) {
            $src = $null
            if ($Rows[$i].Payload) { $src = $Rows[$i].Payload }
            elseif ($Rows[$i].Source) { $src = $Rows[$i].Source }
            if ($src) {
                if ($src.command) { $sourceKey = [string]$src.command }
                elseif ($src.id) { $sourceKey = [string]$src.id }
            }
        }

        $segments = @()
        foreach ($seg in @($entry.BodySegments)) {
            $colorName = [string]$seg.Color
            if ($seg.Color -is [System.ConsoleColor]) {
                $colorName = [string][int]$seg.Color
            }
            $segments += @{
                Text  = [string]$seg.Text
                Color = $colorName
            }
        }

        $lineColor = [string][int]$entry.LineColor
        $entries += [pscustomobject]@{
            BodyPlain    = [string]$entry.BodyPlain
            BodySegments = $segments
            LineColor    = $lineColor
            Enabled      = [bool]$entry.Enabled
            Number       = [int]$entry.Number
            SourceKey    = $sourceKey
        }
    }

    return [pscustomobject]@{
        ColGap  = [string]$Built.ColGap
        Entries = $entries
    }
}

function Import-ToolkitRowCacheBuilt {
    param(
        $Payload,
        [hashtable]$SourceByKey
    )

    $entryList = @($Payload.Entries)
    $rowCache = New-Object 'object[]' @($entryList.Count)
    for ($i = 0; $i -lt $entryList.Count; $i++) {
        $raw = $entryList[$i]
        $segments = @()
        foreach ($seg in @($raw.BodySegments)) {
            $color = [System.ConsoleColor]::Gray
            if ($seg.Color -match '^\d+$') {
                $color = [System.ConsoleColor][int]$seg.Color
            }
            $segments += @{ Text = [string]$seg.Text; Color = $color }
        }

        $lineColor = [System.ConsoleColor]::Gray
        if ([string]$raw.LineColor -match '^\d+$') {
            $lineColor = [System.ConsoleColor][int]$raw.LineColor
        }

        $source = $null
        if ($raw.SourceKey -and $SourceByKey.ContainsKey([string]$raw.SourceKey)) {
            $source = $SourceByKey[[string]$raw.SourceKey]
        }

        $rowCache[$i] = [pscustomobject]@{
            BodyPlain    = [string]$raw.BodyPlain
            BodySegments = $segments
            LineColor    = $lineColor
            Enabled      = [bool]$raw.Enabled
            Source       = $source
            Number       = [int]$raw.Number
        }
    }

    return @{
        RowCache = $rowCache
        ColGap   = [string]$Payload.ColGap
    }
}

function Clear-ToolkitInitDirectory {
    $root = Get-ToolkitInitRoot
    if (-not (Test-Path $root)) { return }

    Get-ChildItem -Path $root -Force | ForEach-Object {
        Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Reset-ToolkitToolsMemoryCache {
    $script:ToolkitToolsMemoryCache = $null
    $script:ToolkitDiskListRowCaches = @{}
    $script:ToolkitInitManifest = $null
    $script:ToolkitInitToolStateCache = $null
    Clear-ToolkitSessionInitState
}

function Get-ToolkitInitManifest {
    if ($null -ne $script:ToolkitInitManifest) {
        return $script:ToolkitInitManifest
    }

    $path = Get-ToolkitInitManifestPath
    if (-not (Test-Path $path)) { return $null }

    try {
        $script:ToolkitInitManifest = Get-Content -Raw -Path $path -Encoding UTF8 | ConvertFrom-Json
        return $script:ToolkitInitManifest
    }
    catch {
        return $null
    }
}

function Test-ToolkitInitValidCore {
    $manifest = Get-ToolkitInitManifest
    if (-not $manifest) { return $false }

    $currentVersion = [string](Get-Manifest).version
    if ([string]$manifest.toolkitVersion -ne $currentVersion) { return $false }

    $fingerprint = New-ToolkitInitFingerprint
    if ([string]$manifest.fingerprint -ne $fingerprint) { return $false }

    $locale = Get-CurrentLocale
    if (-not (Test-Path (Get-ToolkitInitBrandPath -Locale $locale))) { return $false }
    if (-not (Test-Path (Get-ToolkitInitCatalogPath -Locale $locale))) { return $false }
    if (-not (Test-Path (Get-ToolkitInitHomeRowsPath -Locale $locale))) { return $false }
    if (-not (Test-Path (Get-ToolkitInitToolsStatePath))) { return $false }

    return $true
}

function Test-ToolkitInitValid {
    param([switch]$Refresh)

    $locale = Get-CurrentLocale
    if (-not $Refresh -and $null -ne $script:ToolkitSessionInitValid `
        -and [string]$script:ToolkitSessionInitValidLocale -eq $locale) {
        return [bool]$script:ToolkitSessionInitValid
    }

    $result = Test-ToolkitInitValidCore
    Set-ToolkitSessionInitValidState -Valid $result -Locale $locale
    return $result
}

function Test-ToolkitSessionInitReady {
    if ($null -ne $script:ToolkitSessionInitValid -and `
        [string]$script:ToolkitSessionInitValidLocale -eq (Get-CurrentLocale)) {
        return [bool]$script:ToolkitSessionInitValid
    }

    return (Test-ToolkitInitValid)
}

function Initialize-ToolkitHomeBundle {
    param([hashtable]$Shell = $null)

    if (-not (Test-ToolkitSessionInitReady)) { return $false }

    $locale = Get-CurrentLocale

    if ($null -eq $script:ToolkitToolsMemoryCache) {
        $script:ToolkitToolsMemoryCache = @(Get-ToolkitToolsFromInit -Locale $locale)
    }

    $brand = Get-ToolkitBrandSnapshot -Locale $locale
    if ($brand) {
        $script:ToolkitHomeBrandSnapshot = $brand
        $script:ToolkitHomeBrandSnapshotLocale = $locale
        if ($Shell) {
            $Shell['BrandSnapshot'] = $brand
        }
    }

    $path = Get-ToolkitInitHomeRowsPath -Locale $locale
    if (Test-Path $path) {
        try {
            $script:ToolkitHomeRowsPayloadCache = Get-Content -Raw -Path $path -Encoding UTF8 | ConvertFrom-Json
            $script:ToolkitHomeRowsPayloadLocale = $locale
        }
        catch {
            $script:ToolkitHomeRowsPayloadCache = $null
            $script:ToolkitHomeRowsPayloadLocale = $null
        }
    }

    if ($Shell) {
        $Shell['InitReady'] = $true
        $Shell['HomeBundleReady'] = $true
    }
    return $true
}

function Sync-ToolkitSessionInitState {
    param(
        [hashtable]$Shell = $null,
        [switch]$Refresh
    )

    $valid = Test-ToolkitInitValid -Refresh:$Refresh
    if ($Shell) {
        $Shell['InitReady'] = $valid
        if (-not $valid) {
            $Shell['HomeBundleReady'] = $false
            $Shell.Remove('BrandSnapshot')
        }
    }

    if ($valid) {
        Initialize-ToolkitHomeBundle -Shell $Shell | Out-Null
        if (Get-Command Get-ToolkitToolInitStateMap -ErrorAction SilentlyContinue) {
            $null = Get-ToolkitToolInitStateMap
        }
    }

    return $valid
}

function Get-ToolkitBrandSnapshot {
    param([string]$Locale = (Get-CurrentLocale))

    $path = Get-ToolkitInitBrandPath -Locale $Locale
    if (-not (Test-Path $path)) { return $null }

    try {
        return Get-Content -Raw -Path $path -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Get-ToolkitToolsFromInit {
    param([string]$Locale = (Get-CurrentLocale))

    $path = Get-ToolkitInitCatalogPath -Locale $Locale
    if (-not (Test-Path $path)) { return @() }

    $doc = Get-Content -Raw -Path $path -Encoding UTF8 | ConvertFrom-Json
    $tools = @($doc.tools | ForEach-Object { Convert-InitRecordToTool $_ })
    if (Get-Command Sync-ToolkitToolsLivePaths -ErrorAction SilentlyContinue) {
        return @(Sync-ToolkitToolsLivePaths -Tools $tools)
    }
    return $tools
}

function Get-ToolkitTools {
    if ($null -ne $script:ToolkitToolsMemoryCache) {
        return $script:ToolkitToolsMemoryCache
    }

    if (Test-ToolkitSessionInitReady) {
        $script:ToolkitToolsMemoryCache = @(Get-ToolkitToolsFromInit)
        return $script:ToolkitToolsMemoryCache
    }

    $script:ToolkitToolsMemoryCache = @(Discover-Tools)
    return $script:ToolkitToolsMemoryCache
}

function Get-ToolkitDiskListRowCache {
    param(
        [string]$CacheKey,
        [string]$Locale = (Get-CurrentLocale),
        [string]$LayoutKey,
        [string]$RowsKey
    )

    if (-not $script:ToolkitDiskListRowCaches) {
        $script:ToolkitDiskListRowCaches = @{}
    }

    $field = "$CacheKey|$Locale|$LayoutKey|$RowsKey"
    if ($script:ToolkitDiskListRowCaches.ContainsKey($field)) {
        return $script:ToolkitDiskListRowCaches[$field]
    }

    if (-not (Test-ToolkitSessionInitReady)) { return $null }
    if ($CacheKey -ne 'Home') { return $null }

    $path = Get-ToolkitInitHomeRowsPath -Locale $Locale
    $payload = $null
    if ($script:ToolkitHomeRowsPayloadCache -and `
        [string]$script:ToolkitHomeRowsPayloadLocale -eq $Locale) {
        $payload = $script:ToolkitHomeRowsPayloadCache
    }
    elseif (Test-Path $path) {
        try {
            $payload = Get-Content -Raw -Path $path -Encoding UTF8 | ConvertFrom-Json
        }
        catch {
            return $null
        }
    }
    else {
        return $null
    }

    try {
        if ([string]$payload.layoutKey -ne $LayoutKey) { return $null }
        if ([string]$payload.rowsKey -ne $RowsKey) { return $null }

        $sourceByKey = @{}
        foreach ($tool in @(Get-ToolkitTools)) {
            $key = if ($tool.command) { [string]$tool.command } else { [string]$tool.id }
            if (-not [string]::IsNullOrWhiteSpace($key)) {
                $sourceByKey[$key] = $tool
            }
        }

        $built = Import-ToolkitRowCacheBuilt -Payload $payload -SourceByKey $sourceByKey
        $script:ToolkitDiskListRowCaches[$field] = $built
        return $built
    }
    catch {
        return $null
    }
}

function Set-ToolkitSessionLocale {
    param([string]$Locale)

    $script:CurrentLocale = $Locale
    $script:I18nCatalogCache = @{}
    $script:ToolI18nCatalogCache = @{}
    Clear-ToolkitSessionInitState
}

function Discover-ToolsForLocale {
    param([string]$Locale)

    $previous = Get-CurrentLocale
    $changed = ($previous -ne $Locale)
    if ($changed) {
        Set-ToolkitSessionLocale -Locale $Locale
    }

    try {
        return @(Discover-Tools)
    }
    finally {
        if ($changed) {
            Set-ToolkitSessionLocale -Locale $previous
        }
    }
}

function Get-ToolkitToolInitStateMap {
    if ($null -ne $script:ToolkitInitToolStateCache) {
        return $script:ToolkitInitToolStateCache
    }

    $map = @{}
    $path = Get-ToolkitInitToolsStatePath
    if (-not (Test-Path $path)) {
        $script:ToolkitInitToolStateCache = $map
        return $map
    }

    try {
        $doc = Get-Content -Raw -Path $path -Encoding UTF8 | ConvertFrom-Json
        foreach ($prop in $doc.PSObject.Properties) {
            $entry = $prop.Value
            $map[[string]$prop.Name] = @{
                hasDeps          = [bool]$entry.hasDeps
                installed        = [bool]$entry.installed
                meetsRequirement = [bool]$entry.meetsRequirement
            }
        }
    }
    catch {
        $map = @{}
    }

    $script:ToolkitInitToolStateCache = $map
    return $map
}

function Get-ToolkitToolInitStateForTool {
    param($Tool)

    if (-not $Tool) { return $null }
    $map = Get-ToolkitToolInitStateMap
    $toolId = [string]$Tool.id
    if (-not $map.ContainsKey($toolId)) { return $null }
    return [pscustomobject]$map[$toolId]
}

function Invoke-ToolkitInitBuild {
    param(
        [scriptblock]$OnProgress = $null,
        [scriptblock]$OnUiPump = $null
    )

    $coreLibDir = $script:MiaoCoreLibDir
    if ([string]::IsNullOrWhiteSpace($coreLibDir)) {
        $coreLibDir = $global:MiaoCoreLibDir
    }
    foreach ($rel in @(
            'config\Deps-State.ps1'
            'domain\Ensure-ToolDeps.ps1'
            'domain\Invoke-ToolDepPackage.ps1'
            'domain\Invoke-ToolkitRuntime.ps1'
            'domain\Invoke-ToolkitDeps.ps1'
            'domain\Invoke-ToolkitDepOperation.ps1'
        )) {
        . (Join-Path $coreLibDir $rel)
    }

    $initRoot = Get-ToolkitInitRoot
    Clear-ToolkitInitDirectory

    $tmpRoot = Join-Path ([IO.Path]::GetTempPath()) ('miao-init-' + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null

    $locales = @(Get-ToolkitLocales)
    if ($locales.Count -eq 0) { $locales = @('zh') }

    $allTools = @(Discover-Tools)
    $fingerprint = New-ToolkitInitFingerprint
    $toolkitVersion = [string](Get-Manifest).version
    $buildProgress = @{
        Step  = 0
        Total = 2 + ($locales.Count * 3) + $allTools.Count
    }

    function Invoke-InitBuildUiPump {
        if ($OnUiPump) {
            & $OnUiPump
        }
    }

    function Invoke-InitBuildProgress {
        param(
            [string]$Message,
            [ValidateSet('toolbox', 'tool')]
            [string]$Phase = 'toolbox',
            [string]$ToolId = '',
            [int]$Percent = -1
        )

        $buildProgress.Step++
        if ($OnProgress) {
            & $OnProgress @{
                Step    = [int]$buildProgress.Step
                Total   = [int]$buildProgress.Total
                Message = $Message
                Phase   = $Phase
                ToolId  = $ToolId
                Percent = $(if ($Percent -ge 0) { $Percent } else { [int](100 * $buildProgress.Step / $buildProgress.Total) })
            }
        }
        Invoke-InitBuildUiPump
    }

    Invoke-InitBuildProgress -Message (Get-I18n -Key 'page.init.logScanFingerprint') -Phase toolbox
    Invoke-InitBuildProgress -Message (Get-I18n -Key 'page.init.logPrepareDirectory') -Phase toolbox

    foreach ($locale in $locales) {
        Invoke-InitBuildUiPump
        $tools = @(Discover-ToolsForLocale -Locale $locale)

        $header = New-ToolkitMenuHeader -HideSectionTitle
        $brandSnapshot = Get-MenuHeaderBrandSnapshot -Header $header -Locale $locale
        $brandPath = Join-Path $tmpRoot "brand.$locale.json"
        $brandJson = ($brandSnapshot | ConvertTo-Json -Depth 20 -Compress:$false)
        [IO.File]::WriteAllText($brandPath, $brandJson, [Text.UTF8Encoding]::new($true))
        Invoke-InitBuildUiPump

        Invoke-InitBuildProgress -Message (Get-I18n -Key 'page.init.logBrandBuilt' -Vars @{ locale = $locale }) -Phase toolbox

        $catalog = [pscustomobject]@{
            locale = $locale
            tools  = @($tools | ForEach-Object { Convert-ToolToInitRecord $_ })
        }
        $catalogPath = Join-Path $tmpRoot "catalog.$locale.json"
        $catalogJson = ($catalog | ConvertTo-Json -Depth 20 -Compress:$false)
        [IO.File]::WriteAllText($catalogPath, $catalogJson, [Text.UTF8Encoding]::new($true))
        Invoke-InitBuildUiPump

        Invoke-InitBuildProgress -Message (Get-I18n -Key 'page.init.logCatalogBuilt' -Vars @{
            locale = $locale
            count  = $tools.Count
        }) -Phase toolbox

        $rows = Get-HomeToolListRows -Tools $tools
        $maxNumber = 0
        foreach ($row in $rows) {
            $n = [int]$row.Number
            if ($n -gt $maxNumber) { $maxNumber = $n }
        }
        if ($maxNumber -lt $rows.Count) { $maxNumber = $rows.Count }
        if ($maxNumber -lt 1) { $maxNumber = 1 }
        $numWidth = Get-ListNumberDisplayWidth -MaxNumber $maxNumber
        $initShell = @{ LayoutBrandInnerWidth = (Get-ToolkitShellStandardBrandInnerWidth) }
        $listLayout = New-ShellListLayout
        $resolvedLayout = Resolve-ShellListLayout -Shell $initShell -Layout $listLayout `
            -NumWidth $numWidth -Mode Single
        $columnLayout = Resolve-ShellListLayoutColumnLayout -Layout $resolvedLayout
        $layoutKey = ($columnLayout.Widths -join ',')
        $rowsKey = Get-ShellListRowsCacheKey -Rows $rows
        $built = Build-ShellSingleSelectListRowCache -Rows $rows -ColumnLayout $columnLayout
        $payload = Export-ToolkitRowCacheBuilt -Built $built -Rows $rows
        $payload | Add-Member -NotePropertyName layoutKey -NotePropertyValue $layoutKey -Force
        $payload | Add-Member -NotePropertyName rowsKey -NotePropertyValue $rowsKey -Force
        $rowsPath = Join-Path $tmpRoot "rows.$locale.home.json"
        $rowsJson = ($payload | ConvertTo-Json -Depth 30 -Compress:$false)
        [IO.File]::WriteAllText($rowsPath, $rowsJson, [Text.UTF8Encoding]::new($true))
        Invoke-InitBuildUiPump

        Invoke-InitBuildProgress -Message (Get-I18n -Key 'page.init.logHomeRowsBuilt' -Vars @{ locale = $locale }) -Phase toolbox
    }

    $toolsState = [ordered]@{}
    foreach ($tool in $allTools) {
        Invoke-InitBuildUiPump
        $hasDeps = Get-ToolHasExternalDeps $tool
        if (-not $hasDeps) {
            $installed = $true
            $meets = $true
        }
        else {
            $installed = Get-ToolDepInstalled $tool
            $probeCache = @{}
            $meets = $true
            foreach ($pkg in @(Get-ToolDependencyPackages -Tool $tool)) {
                Invoke-InitBuildUiPump
                $status = Resolve-ToolDepPackageStatus -Tool $tool -Package $pkg -ProbeCache $probeCache `
                    -SkipRemoteUpgradeProbe -PreferLocalProbe
                if (-not $status.CommandAvailable) {
                    $meets = $false
                    break
                }
                if ($status.Action -in @('Install', 'Repair', 'Upgrade')) {
                    $meets = $false
                    break
                }
            }
        }

        $toolsState[[string]$tool.id] = [ordered]@{
            hasDeps          = [bool]$hasDeps
            installed        = [bool]$installed
            meetsRequirement = [bool]$meets
        }
        Invoke-InitBuildProgress -Message (Get-I18n -Key 'page.init.logToolStateBuilt' -Vars @{
            toolId = [string]$tool.id
        }) -Phase tool -ToolId ([string]$tool.id)
    }

    $toolsStatePath = Join-Path $tmpRoot 'tools-state.json'
    [IO.File]::WriteAllText($toolsStatePath, ($toolsState | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($true))

    $manifest = [pscustomobject]@{
        toolkitVersion = $toolkitVersion
        fingerprint    = $fingerprint
        builtAt        = (Get-Date).ToString('o')
        locales        = $locales
        toolIds        = @($allTools | ForEach-Object { [string]$_.id })
    }
    $manifestPath = Join-Path $tmpRoot 'manifest.json'
    [IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($true))
    Invoke-InitBuildUiPump

    if (Test-Path $tmpRoot) {
        Get-ChildItem -Path $tmpRoot -Force | ForEach-Object {
            Move-Item -LiteralPath $_.FullName -Destination (Join-Path $initRoot $_.Name) -Force
        }
        Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    Reset-ToolkitToolsMemoryCache
    $script:ToolkitInitManifest = $manifest
    Set-ToolkitSessionInitValidState -Valid $true
    Initialize-ToolkitHomeBundle | Out-Null

    Invoke-InitBuildProgress -Message (Get-I18n -Key 'page.init.logComplete') -Phase toolbox -Percent 100
}

# 兼容旧名称（测试与外部脚本）
function Get-ToolkitCacheRoot { Get-ToolkitInitRoot }
function Get-ToolkitCacheManifestPath { Get-ToolkitInitManifestPath }
function Get-ToolkitCacheCatalogPath { param([string]$Locale) Get-ToolkitInitCatalogPath -Locale $Locale }
function Get-ToolkitCacheHomeRowsPath { param([string]$Locale) Get-ToolkitInitHomeRowsPath -Locale $Locale }
function Clear-ToolkitCacheDirectory { Clear-ToolkitInitDirectory }
function Get-ToolkitCacheManifest { Get-ToolkitInitManifest }
function Test-ToolkitCacheValid { Test-ToolkitInitValid }
function Get-ToolkitToolsFromCache { param([string]$Locale = (Get-CurrentLocale)) Get-ToolkitToolsFromInit -Locale $Locale }
function Invoke-ToolkitCacheBuild {
    param(
        [scriptblock]$OnProgress = $null,
        [scriptblock]$OnUiPump = $null
    )
    Invoke-ToolkitInitBuild -OnProgress $OnProgress -OnUiPump $OnUiPump
}
