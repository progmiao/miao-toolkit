# 工具箱多语言（仅 core/i18n，不含 tools/ 下各工具）

$script:I18nConfigCache = $null
$script:I18nCatalogCache = @{}
$script:CurrentLocale = $null

function Get-I18nRoot {
    if ($script:HomeResolved) {
        return Join-Path (Get-CoreRoot) 'i18n'
    }
    return Join-Path (Get-CorePackageRoot) 'i18n'
}

function Get-I18nConfig {
    if ($script:I18nConfigCache) {
        return $script:I18nConfigCache
    }

    $path = Join-Path (Get-I18nRoot) 'i18n.json'
    if (-not (Test-Path $path)) {
        throw '未找到 core/i18n/i18n.json'
    }

    $script:I18nConfigCache = Get-Content -Raw -Path $path -Encoding UTF8 | ConvertFrom-Json
    return $script:I18nConfigCache
}

function Get-CurrentLocale {
    if ($script:CurrentLocale) {
        return $script:CurrentLocale
    }

    $config = Get-I18nConfig
    $locale = $null

    if ($env:MIAO_LANG) {
        $locale = $env:MIAO_LANG.Trim()
    }
    else {
        $userConfig = Get-UserConfig
        if ($userConfig.locale) {
            $locale = [string]$userConfig.locale
        }
        else {
            $locale = [string]$config.defaultLocale
        }
    }

    $supported = @($config.locales | ForEach-Object { [string]$_ })
    if ($supported -notcontains $locale) {
        $locale = [string]$config.defaultLocale
    }

    $script:CurrentLocale = $locale
    return $script:CurrentLocale
}

function Reset-I18nLocaleCache {
    $script:CurrentLocale = $null
    $script:I18nCatalogCache = @{}
}

function Set-UserLocale {
    param([string]$Locale)

    $locale = $Locale.Trim()
    $supported = @((Get-I18nConfig).locales | ForEach-Object { [string]$_ })
    if ($supported -notcontains $locale) {
        throw "不支持的语言: $Locale"
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

    $key = "settings.locale.$LocaleCode"
    $name = Get-I18nRaw -Key $key
    if ([string]::IsNullOrWhiteSpace($name)) { return $LocaleCode }
    return $name
}

function Get-I18nCatalog {
    param([string]$Locale = (Get-CurrentLocale))

    if ($script:I18nCatalogCache.ContainsKey($Locale)) {
        return $script:I18nCatalogCache[$Locale]
    }

    $path = Join-Path (Get-I18nRoot) "$Locale.json"
    if (-not (Test-Path $path)) {
        throw "未找到语言包: $Locale.json"
    }

    $catalog = Get-Content -Raw -Path $path -Encoding UTF8 | ConvertFrom-Json
    $script:I18nCatalogCache[$Locale] = $catalog
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
        $fallback = [string](Get-I18nConfig).defaultLocale
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
        throw "i18n 缺少键: $Key"
    }

    return Expand-UiTemplate -Template $template -Vars (Get-ManifestTemplateVars -Extra $Vars)
}

function Get-BrandTitle {
    return Get-I18nRaw -Key 'brand.title'
}
