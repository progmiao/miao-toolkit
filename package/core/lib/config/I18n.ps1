# 工具箱 core/i18n：locale + content；工具 tools/<id>/i18n/{code}.json：扁平键，code=文件名，跟随 Get-CurrentLocale

$script:ToolkitLocalesCache = $null
$script:ToolkitLocaleRegistryCache = $null
$script:I18nCatalogCache = @{}
$script:ToolI18nCatalogCache = @{}
$script:CurrentLocale = $null

# 快捷键不随语言变化，仅 common.* 文案进 i18n
$script:I18nKeys = @{
    Enter           = 'Enter'
    Esc             = 'Esc'
    Q               = 'Q'
    Y               = 'Y'
    N               = 'N'
    Space           = 'Space'
    ArrowsUpDown    = [char]0x2191 + [char]0x2193   # ↑↓
    ArrowsLeftRight = [char]0x2190 + [char]0x2192   # ←→
}
$global:I18nKeys = $script:I18nKeys

function Get-MiaoI18nKeys {
    if ($null -ne $script:I18nKeys) { return $script:I18nKeys }
    if ($null -ne $global:I18nKeys) { return $global:I18nKeys }
    throw 'I18nKeys not initialized. Load I18n.ps1 first.'
}

# 开发期固定的标点/分隔符，不进 i18n
$script:I18nHintSeparator = ' |  '
$script:I18nLabelSep = '：'
$script:I18nPromptListSep = ' / '

function Format-I18nKeyDisplay {
    param([string]$Key)

    if ([string]::IsNullOrWhiteSpace($Key)) { return '' }
    return '[' + $Key + ']'
}

function Format-I18nLabelLine {
    param(
        [string]$LabelKey,
        [string]$Value
    )

    $label = Get-I18n -Key $LabelKey
    if ([string]::IsNullOrWhiteSpace($Value)) { return $label }
    return $label + $script:I18nLabelSep + $Value
}

function Format-I18nFallbackLogoMiddle {
    $manifest = Get-Manifest
    $shortName = if ($manifest.shortName) { [string]$manifest.shortName } else { 'Miao' }
    return "   ( $shortName )   "
}

function Format-I18nPaginationPage {
    param(
        [string]$Current,
        [string]$Total
    )

    $prefix = Get-I18nRaw -Key 'common.nth'
    $suffix = Get-I18nRaw -Key 'common.page'
    $core = "$Current/$Total"
    if ([string]::IsNullOrEmpty($prefix) -and [string]::IsNullOrEmpty($suffix)) { return $core }
    return "$prefix$core$suffix"
}

function Format-I18nPaginationTotalCount {
    param(
        [int]$Count,
        [string]$Unit
    )

    $prefix = Get-I18nRaw -Key 'common.altogether'
    $suffix = Get-I18nRaw -Key 'common.totalSuffix'
    $countText = Format-ListTotalCountDisplay -Count $Count
    return " $prefix$countText $Unit$suffix"
}

function Format-I18nCurrentIndexHint {
    param([int]$Index)

    return (Get-I18n -Key 'common.current') + " $Index"
}

function Format-I18nInputBufferHint {
    param([string]$Buffer)

    return (Get-I18n -Key 'common.input') + $script:I18nLabelSep + $Buffer
}

function Format-I18nPressEnterBack {
    param([string]$BackSuffixKey = '')

    $text = (Get-I18n -Key 'common.press') + ' ' + (Format-I18nKeyDisplay $script:I18nKeys.Enter) + ' ' + (Get-I18n -Key 'common.back')
    if (-not [string]::IsNullOrWhiteSpace($BackSuffixKey)) {
        $text += (Get-I18n -Key $BackSuffixKey)
    }
    return $text
}

function Format-I18nSectionHeading {
    param([string]$LabelKey)

    return (Get-I18n -Key $LabelKey) + $script:I18nLabelSep
}

function Get-HomeListColHeader {
    return '     #  ' + (Get-I18n -Key 'common.option')
}

function Format-I18nSelectLanguageSectionTitle {
    $select = Get-I18n -Key 'common.select'
    $language = Get-I18n -Key 'common.language'
    if ((Get-CurrentLocale) -eq 'en') {
        return "$select $language"
    }
    return "$select$language"
}

function Get-AfterToolReturnListLine {
    return (Format-I18nKeyDisplay $script:I18nKeys.Enter) + '  ' + (Get-I18n -Key 'page.afterTool.backToToolList')
}

function Get-AfterToolExitLine {
    $manifest = Get-Manifest
    $shortName = if ($manifest.shortName) { [string]$manifest.shortName } else { 'Miao' }
    return (Format-I18nKeyDisplay $script:I18nKeys.Q) + '      ' + (Get-I18n -Key 'common.quit') + ' ' + $shortName
}

function Get-AfterToolPromptFallback {
    return (Get-I18nKeyHint -Key $script:I18nKeys.Enter -LabelKey 'common.backToList') `
        + $script:I18nPromptListSep `
        + (Get-I18nKeyHint -Key $script:I18nKeys.Q -LabelKey 'common.quit')
}

function Get-I18nRoot {
    if ($script:HomeResolved) {
        return Join-Path (Get-CoreRoot) 'i18n'
    }
    return Join-Path (Get-CorePackageRoot) 'i18n'
}

function Import-I18nLocaleDocument {
    param([string]$Path)

    if (-not (Test-Path $Path)) { return $null }

    $raw = Get-Content -Raw -Path $Path -Encoding UTF8 | ConvertFrom-Json
    $fileCode = [IO.Path]::GetFileNameWithoutExtension($Path)

    $meta = $raw.locale
    $code = if ($meta -and $meta.code) { [string]$meta.code.Trim() } else { $fileCode }
    if ([string]::IsNullOrWhiteSpace($code)) { return $null }

    $order = 9999
    if ($meta -and $null -ne $meta.order) {
        $order = [int]$meta.order
    }

    $name = if ($meta -and $meta.name) { [string]$meta.name } else { $code }
    $isDefault = ($meta -and $meta.isDefault -eq $true)

    $content = $raw.content
    if ($null -eq $content) {
        $content = @{}
        foreach ($prop in $raw.PSObject.Properties) {
            if ($prop.Name -eq 'locale') { continue }
            $content | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
        }
    }

    return [pscustomobject]@{
        order     = $order
        code      = $code
        name      = $name
        isDefault = $isDefault
        path      = $Path
        content   = $content
    }
}

function Get-ToolkitLocaleRegistry {
    if ($null -ne $script:ToolkitLocaleRegistryCache) {
        return $script:ToolkitLocaleRegistryCache
    }

    $root = Get-I18nRoot
    if (-not (Test-Path $root)) {
        $script:ToolkitLocaleRegistryCache = @()
        return $script:ToolkitLocaleRegistryCache
    }

    $entries = @()
    Get-ChildItem -Path $root -Filter '*.json' -File |
        Where-Object { -not $_.Name.StartsWith('_') } |
        ForEach-Object {
            $doc = Import-I18nLocaleDocument -Path $_.FullName
            if ($doc) { $entries += $doc }
        }

    $script:ToolkitLocaleRegistryCache = @($entries | Sort-Object { [int]$_.order }, { $_.code })
    return $script:ToolkitLocaleRegistryCache
}

function Get-ToolkitLocales {
    if ($null -ne $script:ToolkitLocalesCache) {
        return $script:ToolkitLocalesCache
    }

    $script:ToolkitLocalesCache = @(Get-ToolkitLocaleRegistry | ForEach-Object { [string]$_.code })
    return $script:ToolkitLocalesCache
}

function Get-DefaultToolkitLocale {
    $registry = @(Get-ToolkitLocaleRegistry)
    if ($registry.Count -eq 0) { return 'zh' }

    $defaultEntry = @($registry | Where-Object { $_.isDefault } | Select-Object -First 1)
    if ($defaultEntry.Count -gt 0) {
        return [string]$defaultEntry[0].code
    }

    return [string]$registry[0].code
}

function Get-ToolkitLocaleEntry {
    param([string]$LocaleCode)

    if ([string]::IsNullOrWhiteSpace($LocaleCode)) { return $null }
    return @(Get-ToolkitLocaleRegistry | Where-Object { $_.code -eq $LocaleCode } | Select-Object -First 1)
}

function Get-I18nConfig {
    return [pscustomobject]@{
        locales       = @(Get-ToolkitLocales)
        defaultLocale = (Get-DefaultToolkitLocale)
        registry      = @(Get-ToolkitLocaleRegistry)
    }
}

function Get-CurrentLocale {
    if ($script:CurrentLocale) {
        return $script:CurrentLocale
    }

    $supported = @(Get-ToolkitLocales)
    $locale = $null

    if ($env:MIAO_LANG) {
        $locale = $env:MIAO_LANG.Trim()
    }
    else {
        $userConfig = Get-UserConfig
        if ($userConfig.locale) {
            $locale = [string]$userConfig.locale
        }
    }

    if ([string]::IsNullOrWhiteSpace($locale) -or ($supported.Count -gt 0 -and $supported -notcontains $locale)) {
        $locale = Get-DefaultToolkitLocale
    }

    $script:CurrentLocale = $locale
    return $script:CurrentLocale
}

function Reset-I18nLocaleCache {
    $script:CurrentLocale = $null
    $script:ToolkitLocalesCache = $null
    $script:ToolkitLocaleRegistryCache = $null
    $script:I18nCatalogCache = @{}
    $script:ToolI18nCatalogCache = @{}
}

function Sync-MiaoLocaleFromShell {
    param([hashtable]$Shell)

    if (-not $Shell) { return }
    $locale = [string]$Shell.HeaderLocale
    if ([string]::IsNullOrWhiteSpace($locale)) { return }
    if ((Get-CurrentLocale) -eq $locale) { return }

    $script:CurrentLocale = $locale
    $script:I18nCatalogCache = @{}
    $script:ToolI18nCatalogCache = @{}
}

function Set-UserLocale {
    param([string]$Locale)

    $locale = $Locale.Trim()
    $supported = @(Get-ToolkitLocales)
    if ($supported.Count -gt 0 -and $supported -notcontains $locale) {
        $template = Get-I18nRaw -Key 'message.unsupportedLocale'
        if ([string]::IsNullOrEmpty($template)) {
            throw $locale
        }
        throw (Expand-UiTemplate -Template $template -Vars @{ locale = $locale })
    }

    $config = Get-UserConfig
    if (-not $config.PSObject.Properties['locale']) {
        $config | Add-Member -NotePropertyName locale -NotePropertyValue $locale -Force
    }
    else {
        $config.locale = $locale
    }

    Save-UserConfig $config
    Reset-I18nLocaleCache
    $script:CurrentLocale = $locale
}

function Get-LocaleDisplayName {
    param([string]$LocaleCode)

    $entry = Get-ToolkitLocaleEntry -LocaleCode $LocaleCode
    if ($entry -and -not [string]::IsNullOrWhiteSpace($entry.name)) {
        return [string]$entry.name
    }
    return $LocaleCode
}

function Get-I18nHintSeparator {
    return $script:I18nHintSeparator
}

function Join-I18nParts {
    param(
        [string[]]$Parts,
        [string]$Separator = ''
    )

    if ([string]::IsNullOrEmpty($Separator)) {
        $Separator = Get-I18nHintSeparator
    }

    $segments = @()
    foreach ($part in $Parts) {
        if ([string]::IsNullOrWhiteSpace($part)) { continue }
        $segments += $part
    }

    if ($segments.Count -eq 0) { return '' }
    return ($segments -join $Separator)
}

# 快捷键固定写在代码里；LabelKey 指向 common 下可翻译词（如 common.confirm）
function Get-I18nKeyHint {
    param(
        [string]$Key,
        [string]$LabelKey,
        [hashtable]$Vars = @{}
    )

    $label = Get-I18n -Key $LabelKey -Vars $Vars
    if ([string]::IsNullOrWhiteSpace($Key)) { return $label }
    return (Format-I18nKeyDisplay $Key) + ' ' + $label
}

function Get-I18nArrowHint {
    param(
        [string]$Arrows,
        [string]$LabelKey,
        [hashtable]$Vars = @{}
    )

    $label = Get-I18n -Key $LabelKey -Vars $Vars
    if ([string]::IsNullOrWhiteSpace($Arrows)) { return $label }
    return (Format-I18nKeyDisplay $Arrows) + ' ' + $label
}

function Get-ToolkitI18nKeyHint {
    param(
        [string]$Key,
        [string]$LabelKey,
        [hashtable]$Vars = @{}
    )

    return Get-I18nKeyHint -Key $Key -LabelKey $LabelKey -Vars $Vars
}

function Get-ToolkitI18nArrowHint {
    param(
        [string]$Arrows,
        [string]$LabelKey,
        [hashtable]$Vars = @{}
    )

    return Get-I18nArrowHint -Arrows $Arrows -LabelKey $LabelKey -Vars $Vars
}

function Get-MenuListHintLine {
    param(
        [int]$Index = 0,
        [string]$NumberBuffer = ''
    )

    $hint = Join-I18nParts -Parts @(
        (Get-I18nArrowHint -Arrows $script:I18nKeys.ArrowsUpDown -LabelKey 'common.select')
        (Get-I18nArrowHint -Arrows $script:I18nKeys.ArrowsLeftRight -LabelKey 'common.pageTurn')
        (Format-I18nCurrentIndexHint -Index $Index)
        (Get-I18nKeyHint -Key $script:I18nKeys.Enter -LabelKey 'common.confirm')
        (Get-I18nKeyHint -Key $script:I18nKeys.Esc -LabelKey 'common.quit')
    )

    if (-not [string]::IsNullOrEmpty($NumberBuffer)) {
        $hint += (Get-I18nHintSeparator) + (Format-I18nInputBufferHint -Buffer $NumberBuffer)
    }

    return $hint
}

function Get-InstallPageFooterHint {
    return (Join-I18nParts -Parts @(
        (Get-I18nKeyHint -Key $script:I18nKeys.Space -LabelKey 'common.toggle')
        (Get-I18nKeyHint -Key $script:I18nKeys.Enter -LabelKey 'common.confirm')
        (Get-I18nKeyHint -Key $script:I18nKeys.Q -LabelKey 'common.back')
    ))
}

function Get-ToolkitI18nRaw {
    param([string]$Key)

    return Get-I18nRaw -Key $Key
}

function Get-ToolkitI18n {
    param(
        [string]$Key,
        [hashtable]$Vars = @{}
    )

    return Get-I18n -Key $Key -Vars $Vars
}

function Get-I18nCatalog {
    param([string]$Locale = (Get-CurrentLocale))

    if (-not $script:I18nCatalogCache) {
        $script:I18nCatalogCache = @{}
    }

    if ($script:I18nCatalogCache.ContainsKey($Locale)) {
        return $script:I18nCatalogCache[$Locale]
    }

    $entry = Get-ToolkitLocaleEntry -LocaleCode $Locale
    if ($entry -and $entry.content) {
        $script:I18nCatalogCache[$Locale] = $entry.content
        return $script:I18nCatalogCache[$Locale]
    }

    $script:I18nCatalogCache[$Locale] = @{}
    return $script:I18nCatalogCache[$Locale]
}

function Get-ToolI18nRoot {
    param([string]$ToolRoot)

    return Join-Path $ToolRoot 'i18n'
}

function Import-ToolI18nCatalog {
    param([string]$Path)

    if (-not (Test-Path $Path)) { return $null }

    $raw = Get-Content -Raw -Path $Path -Encoding UTF8 | ConvertFrom-Json
    if ($raw.content) {
        return $raw.content
    }

    return $raw
}

function Get-ToolI18nCatalog {
    param(
        [string]$ToolRoot,
        [string]$Locale = (Get-CurrentLocale)
    )

    if (-not $script:ToolI18nCatalogCache) {
        $script:ToolI18nCatalogCache = @{}
    }

    $cacheKey = "$ToolRoot|$Locale"
    if ($script:ToolI18nCatalogCache.ContainsKey($cacheKey)) {
        return $script:ToolI18nCatalogCache[$cacheKey]
    }

    $path = Join-Path (Get-ToolI18nRoot -ToolRoot $ToolRoot) "$Locale.json"
    $catalog = Import-ToolI18nCatalog -Path $path
    if ($null -eq $catalog) {
        $script:ToolI18nCatalogCache[$cacheKey] = @{}
        return $script:ToolI18nCatalogCache[$cacheKey]
    }

    $script:ToolI18nCatalogCache[$cacheKey] = $catalog
    return $script:ToolI18nCatalogCache[$cacheKey]
}

function Resolve-ToolI18nLabel {
    param(
        [string]$ToolRoot,
        [string]$Key,
        [string]$Fallback = ''
    )

    if ([string]::IsNullOrWhiteSpace($Key)) {
        if (-not [string]::IsNullOrWhiteSpace($Fallback)) { return $Fallback }
        return (Get-I18n -Key 'common.unrecognized')
    }

    $value = Get-ToolI18nRaw -ToolRoot $ToolRoot -Key $Key
    if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
    if (-not [string]::IsNullOrWhiteSpace($Fallback)) { return $Fallback }
    return (Get-I18n -Key 'common.unrecognized')
}

function Apply-ToolI18nFields {
    param($Tool)

    if (-not $Tool -or [string]::IsNullOrWhiteSpace($Tool._root)) {
        return $Tool
    }

    $nameKey = ''
    if ($Tool.PSObject.Properties['name']) {
        $nameKey = [string]$Tool.name
    }

    $descriptionKey = ''
    if ($Tool.PSObject.Properties['description']) {
        $descriptionKey = [string]$Tool.description
    }

    $resolvedName = Resolve-ToolI18nLabel -ToolRoot $Tool._root -Key $nameKey
    $Tool | Add-Member -NotePropertyName 'name' -NotePropertyValue $resolvedName -Force

    $resolvedDescription = ''
    if (-not [string]::IsNullOrWhiteSpace($descriptionKey)) {
        $resolvedDescription = Get-ToolI18nRaw -ToolRoot $Tool._root -Key $descriptionKey
        if ($null -eq $resolvedDescription) { $resolvedDescription = '' }
    }
    $Tool | Add-Member -NotePropertyName 'description' -NotePropertyValue $resolvedDescription -Force

    return $Tool
}

function Resolve-I18nKey {
    param(
        $Object,
        [string]$Key
    )

    if ($null -eq $Object -or [string]::IsNullOrWhiteSpace($Key)) { return $null }

    $current = $Object
    foreach ($part in $Key.Split('.')) {
        if ($null -eq $current) { return $null }

        if ($current -is [System.Collections.IDictionary]) {
            if (-not $current.Contains($part)) { return $null }
            $current = $current[$part]
            continue
        }

        $prop = $current.PSObject.Properties[$part]
        if (-not $prop) { return $null }
        $current = $prop.Value
    }

    if ($null -eq $current) { return $null }
    return [string]$current
}

function Get-I18nRaw {
    param([string]$Key)

    $locale = Get-CurrentLocale
    $value = Resolve-I18nKey -Object (Get-I18nCatalog -Locale $locale) -Key $Key

    if ([string]::IsNullOrEmpty($value)) {
        $fallback = Get-DefaultToolkitLocale
        if ($locale -ne $fallback) {
            $value = Resolve-I18nKey -Object (Get-I18nCatalog -Locale $fallback) -Key $Key
        }
    }

    return $value
}

function Get-I18n {
    param(
        [string]$Key,
        [hashtable]$Vars = @{}
    )

    $template = Get-I18nRaw -Key $Key
    if ([string]::IsNullOrEmpty($template)) {
        return $Key
    }

    return Expand-UiTemplate -Template $template -Vars (Get-ManifestTemplateVars -Extra $Vars)
}

function Get-ToolI18nRaw {
    param(
        [string]$ToolRoot,
        [string]$Key
    )

    if ([string]::IsNullOrWhiteSpace($ToolRoot) -or [string]::IsNullOrWhiteSpace($Key)) {
        return $null
    }

    $locale = Get-CurrentLocale
    $value = Resolve-ToolI18nCatalogKey -Catalog (Get-ToolI18nCatalog -ToolRoot $ToolRoot -Locale $locale) -Key $Key

    if ([string]::IsNullOrEmpty($value)) {
        $fallback = Get-DefaultToolkitLocale
        if ($locale -ne $fallback) {
            $value = Resolve-ToolI18nCatalogKey -Catalog (Get-ToolI18nCatalog -ToolRoot $ToolRoot -Locale $fallback) -Key $Key
        }
    }

    return $value
}

function Resolve-ToolI18nCatalogKey {
    param(
        $Catalog,
        [string]$Key
    )

    if ($null -eq $Catalog -or [string]::IsNullOrWhiteSpace($Key)) { return $null }

    $value = Resolve-I18nKey -Object $Catalog -Key $Key
    if (-not [string]::IsNullOrEmpty($value)) { return $value }

    if ($Catalog -is [System.Collections.IDictionary] -and $Catalog.Contains($Key)) {
        return [string]$Catalog[$Key]
    }

    return $null
}

function Get-ToolI18n {
    param(
        [string]$ToolRoot,
        [string]$Key,
        [hashtable]$Vars = @{}
    )

    $template = Get-ToolI18nRaw -ToolRoot $ToolRoot -Key $Key
    if ([string]::IsNullOrEmpty($template)) {
        return $Key
    }

    return Expand-UiTemplate -Template $template -Vars (Get-ManifestTemplateVars -Extra $Vars)
}

function Get-BrandTitle {
    $title = Get-I18nRaw -Key 'brand.title'
    if ([string]::IsNullOrWhiteSpace($title)) { return 'brand.title' }
    return $title
}

function Get-BrandAuthorName {
    $name = Get-I18nRaw -Key 'brand.author'
    if ([string]::IsNullOrWhiteSpace($name)) { return 'brand.author' }
    return $name
}
