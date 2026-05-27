# 工具箱与工具多语言（core/i18n、tools/<id>/i18n；语种以工具箱目录下 *.json 为准）

$script:ToolkitLocalesCache = $null
$script:I18nCatalogCache = @{}
$script:ToolI18nCatalogCache = @{}
$script:CurrentLocale = $null

function Get-I18nRoot {
    if ($script:HomeResolved) {
        return Join-Path (Get-CoreRoot) 'i18n'
    }
    return Join-Path (Get-CorePackageRoot) 'i18n'
}

function Get-ToolkitLocales {
    if ($null -ne $script:ToolkitLocalesCache) {
        return $script:ToolkitLocalesCache
    }

    $root = Get-I18nRoot
    if (-not (Test-Path $root)) {
        $script:ToolkitLocalesCache = @()
        return $script:ToolkitLocalesCache
    }

    $names = @(Get-ChildItem -Path $root -Filter '*.json' -File |
        ForEach-Object { $_.BaseName } |
        Sort-Object)
    $script:ToolkitLocalesCache = $names
    return $script:ToolkitLocalesCache
}

function Get-DefaultToolkitLocale {
    $locales = @(Get-ToolkitLocales)
    if ($locales.Count -eq 0) { return 'zh' }
    if ($locales -contains 'zh') { return 'zh' }
    return [string]$locales[0]
}

function Get-I18nConfig {
    return [pscustomobject]@{
        locales       = @(Get-ToolkitLocales)
        defaultLocale = (Get-DefaultToolkitLocale)
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
    $script:I18nCatalogCache = @{}
    $script:ToolI18nCatalogCache = @{}
}

function Set-UserLocale {
    param([string]$Locale)

    $locale = $Locale.Trim()
    $supported = @(Get-ToolkitLocales)
    if ($supported.Count -gt 0 -and $supported -notcontains $locale) {
        $template = Get-I18nRaw -Key 'error.unsupportedLocale'
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

    $key = "page.lang.locale.$LocaleCode"
    $name = Get-I18nRaw -Key $key
    if ([string]::IsNullOrWhiteSpace($name)) { return $LocaleCode }
    return $name
}

function Get-I18nHintSeparator {
    $sep = Get-I18nRaw -Key 'common.hintSeparator'
    if ([string]::IsNullOrEmpty($sep)) { return ' |  ' }
    return $sep
}

function Join-I18nParts {
    param(
        [string[]]$Keys,
        [hashtable]$Vars = @{},
        [string]$Separator = ''
    )

    if ([string]::IsNullOrEmpty($Separator)) {
        $Separator = Get-I18nHintSeparator
    }

    $parts = @()
    foreach ($key in $Keys) {
        if ([string]::IsNullOrWhiteSpace($key)) { continue }
        $text = Get-I18n -Key $key -Vars $Vars
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            $parts += $text
        }
    }

    if ($parts.Count -eq 0) { return '' }
    return ($parts -join $Separator)
}

function Get-MenuListHintLine {
    param(
        [int]$Index = 0,
        [string]$NumberBuffer = ''
    )

    $hint = Join-I18nParts -Keys @(
        'common.action.navSelect'
        'common.action.navPage'
        'common.action.currentIndex'
        'common.action.confirmEnter'
        'common.action.quitEsc'
    ) -Vars @{ index = $Index }

    if (-not [string]::IsNullOrEmpty($NumberBuffer)) {
        $hint += (Get-I18nHintSeparator) + (Get-I18n -Key 'common.action.inputBuffer' -Vars @{ buffer = $NumberBuffer })
    }

    return $hint
}

function Get-InstallDepsFooterHint {
    return (Join-I18nParts -Keys @(
        'common.action.toggleSpace'
        'common.action.confirmEnter'
        'common.action.backQ'
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

    if ($script:I18nCatalogCache.ContainsKey($Locale)) {
        return $script:I18nCatalogCache[$Locale]
    }

    $path = Join-Path (Get-I18nRoot) "$Locale.json"
    if (-not (Test-Path $path)) {
        $script:I18nCatalogCache[$Locale] = @{}
        return $script:I18nCatalogCache[$Locale]
    }

    $catalog = Get-Content -Raw -Path $path -Encoding UTF8 | ConvertFrom-Json
    $script:I18nCatalogCache[$Locale] = $catalog
    return $catalog
}

function Get-ToolI18nRoot {
    param([string]$ToolRoot)

    return Join-Path $ToolRoot 'i18n'
}

function Get-ToolI18nCatalog {
    param(
        [string]$ToolRoot,
        [string]$Locale = (Get-CurrentLocale)
    )

    $cacheKey = "$ToolRoot|$Locale"
    if ($script:ToolI18nCatalogCache.ContainsKey($cacheKey)) {
        return $script:ToolI18nCatalogCache[$cacheKey]
    }

    $path = Join-Path (Get-ToolI18nRoot -ToolRoot $ToolRoot) "$Locale.json"
    if (-not (Test-Path $path)) {
        $script:ToolI18nCatalogCache[$cacheKey] = @{}
        return $script:ToolI18nCatalogCache[$cacheKey]
    }

    $catalog = Get-Content -Raw -Path $path -Encoding UTF8 | ConvertFrom-Json
    $script:ToolI18nCatalogCache[$cacheKey] = $catalog
    return $catalog
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
    $value = Resolve-I18nKey -Object (Get-ToolI18nCatalog -ToolRoot $ToolRoot -Locale $locale) -Key $Key

    if ([string]::IsNullOrEmpty($value)) {
        $fallback = Get-DefaultToolkitLocale
        if ($locale -ne $fallback) {
            $value = Resolve-I18nKey -Object (Get-ToolI18nCatalog -ToolRoot $ToolRoot -Locale $fallback) -Key $Key
        }
    }

    return $value
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
