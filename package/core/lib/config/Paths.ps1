# 路径与控制台初始化（由 bin/miao.ps1 调用 Initialize-Paths）

$script:ManifestCache = $null

function Initialize-Console {
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        [Console]::InputEncoding = [System.Text.Encoding]::UTF8
        $script:OutputEncoding = [System.Text.Encoding]::UTF8
        if ($Host.Name -eq 'ConsoleHost') {
            chcp 65001 | Out-Null
        }
    }
    catch {
        # 非交互宿主时忽略
    }
}

function Initialize-Paths {
    param([string]$BinDirectory)
    Initialize-Console
    if ($env:MIAO_HOME) {
        $script:HomeResolved = $env:MIAO_HOME
        return
    }
    $script:HomeResolved = (Resolve-Path (Join-Path $BinDirectory '..')).Path
}

function Get-Home {
    if (-not $script:HomeResolved) {
        throw (Get-I18n -Key 'error.pathsNotInitialized')
    }
    return $script:HomeResolved
}

function Get-ToolsRoot {
    Join-Path (Get-Home) 'tools'
}

function Get-CoreRoot {
    Join-Path (Get-Home) 'core'
}

function Get-LibRoot {
    return Split-Path $PSScriptRoot -Parent
}

function Get-CorePackageRoot {
    return Split-Path (Get-LibRoot) -Parent
}

function Get-ManifestRawPath {
    if ($script:HomeResolved) {
        return Join-Path (Get-CoreRoot) 'manifest.json'
    }
    return Join-Path (Get-CorePackageRoot) 'manifest.json'
}

function Get-Manifest {
    if ($script:ManifestCache) {
        return $script:ManifestCache
    }

    $path = Get-ManifestRawPath
    if (-not (Test-Path $path)) {
        throw '未找到 core/manifest.json'
    }

    $script:ManifestCache = Get-Content -Raw -Path $path -Encoding UTF8 | ConvertFrom-Json
    return $script:ManifestCache
}

function Get-ManifestTemplateVars {
    param([hashtable]$Extra = @{})

    $manifest = Get-Manifest
    $vars = @{
        packageName = [string]$manifest.packageName
        shortName   = if ($manifest.shortName) { [string]$manifest.shortName } else { 'Miao' }
        title       = (Get-I18nRaw -Key 'brand.title')
        author      = [string]$manifest.author
        description = (Get-I18nRaw -Key 'brand.description')
        version     = [string]$manifest.version
        releaseDate = (Format-ReleaseDate $manifest.releaseDate)
        email       = (Get-BrandContactEmail)
    }
    foreach ($key in $Extra.Keys) {
        $vars[$key] = $Extra[$key]
    }
    return $vars
}

function Get-UserAgent {
    $manifest = Get-Manifest
    if ($manifest.userAgent) { return [string]$manifest.userAgent }
    if ($manifest.packageName) { return [string]$manifest.packageName }
    return 'Miao-Toolkit'
}

function Expand-UiTemplate {
    param(
        [string]$Template,
        [hashtable]$Vars = @{}
    )

    if ([string]::IsNullOrEmpty($Template)) { return '' }

    $result = $Template
    foreach ($key in $Vars.Keys) {
        $result = $result.Replace('{' + $key + '}', [string]$Vars[$key])
    }
    return $result
}

function Get-MenuNumberDisplayWidth {
    param(
        [int]$TotalCount = 0,
        [int]$MaxNumber = 0
    )

    $manifest = Get-Manifest
    $minDisplay = 2
    if ($manifest.menu -and ($null -ne $manifest.menu.numberDisplayWidth)) {
        $minDisplay = [Math]::Max(1, [int]$manifest.menu.numberDisplayWidth)
    }

    $value = if ($MaxNumber -gt 0) { $MaxNumber } elseif ($TotalCount -gt 0) { $TotalCount } else { 1 }
    $countDigits = ([string]$value).Length
    return [Math]::Max($minDisplay, $countDigits)
}

function Get-MenuNumberWidth {
    param(
        [int]$TotalCount = 0,
        [int]$MaxNumber = 0
    )
    return Get-MenuNumberDisplayWidth -TotalCount $TotalCount -MaxNumber $MaxNumber
}

function Get-ToolCommandName {
    param($Tool)
    if ($Tool.id) { return [string]$Tool.id }
    return ''
}

function Get-MenuCliCommandPrefix {
    $manifest = Get-Manifest
    if ($manifest.menu -and $manifest.menu.cliCommandPrefix) {
        return [string]$manifest.menu.cliCommandPrefix
    }
    return 'miao'
}

function Get-ToolMenuCommand {
    param($Tool)

    $prefix = Get-MenuCliCommandPrefix
    $name = Get-ToolCommandName -Tool $Tool
    if ([string]::IsNullOrWhiteSpace($prefix)) { return $name }
    if ([string]::IsNullOrWhiteSpace($name)) { return $prefix }
    return "$prefix $name"
}

function Test-MiaoDevMode {
    return ($env:MIAO_DEV -eq '1')
}

function Get-MenuColumnGap {
    $manifest = Get-Manifest
    if ($manifest.menu -and ($null -ne $manifest.menu.columnGap)) {
        return [Math]::Max(1, [int]$manifest.menu.columnGap)
    }
    return 2
}

function Get-ToolListColumnWidths {
    $manifest = Get-Manifest
    $defaults = @{
        command     = 12
        displayName = 14
        summary     = 29
        status      = 6
    }
    if ($manifest.menu -and $manifest.menu.toolListColumns) {
        $cols = $manifest.menu.toolListColumns
        foreach ($key in @($defaults.Keys)) {
            if ($null -ne $cols.$key) {
                $defaults[$key] = [Math]::Max(1, [int]$cols.$key)
            }
        }
    }
    return $defaults
}

function Get-MenuPageNumberDisplayWidth {
    param([int]$PageCount = 1)

    $manifest = Get-Manifest
    $minDisplay = 2
    if ($manifest.menu -and ($null -ne $manifest.menu.pageNumberDisplayWidth)) {
        $minDisplay = [Math]::Max(1, [int]$manifest.menu.pageNumberDisplayWidth)
    }
    $digits = ([string][Math]::Max(1, $PageCount)).Length
    return [Math]::Max($minDisplay, $digits)
}

function Get-MenuPageSize {
    $manifest = Get-Manifest
    if ($manifest.menu -and $manifest.menu.pageSize) {
        return [int]$manifest.menu.pageSize
    }
    return 10
}

function Get-MenuLoadMore {
    $manifest = Get-Manifest
    if ($manifest.menu -and $manifest.menu.loadMore) {
        return [int]$manifest.menu.loadMore
    }
    return (Get-MenuPageSize)
}

function Get-BrandSeparatorExtra {
    $manifest = Get-Manifest
    if ($manifest.menu -and ($null -ne $manifest.menu.brandSeparatorExtra)) {
        return [int]$manifest.menu.brandSeparatorExtra
    }
    return 1
}

function Get-BrandContactEmail {
    $manifest = Get-Manifest
    if ($manifest.contact -and $manifest.contact.email) {
        return [string]$manifest.contact.email
    }
    if ($manifest.ui -and $manifest.ui.email) {
        return [string]$manifest.ui.email
    }
    return ''
}

function Get-RepositoryBrowseUrl {
    $manifest = Get-Manifest
    if ($manifest.ui -and $manifest.ui.repositoryUrl) {
        return $manifest.ui.repositoryUrl
    }
    if ($manifest.repository) {
        return "https://github.com/$($manifest.repository)"
    }
    return ''
}

function Resolve-MenuPagingDefaults {
    param(
        [int]$PageSize = 0,
        [int]$LoadMore = 0,
        [int]$ViewHeight = 0
    )

    $resolvedPageSize = if ($PageSize -gt 0) { $PageSize } else { Get-MenuPageSize }
    $resolvedLoadMore = if ($LoadMore -gt 0) { $LoadMore } else { Get-MenuLoadMore }
    $resolvedViewHeight = if ($ViewHeight -gt 0) { $ViewHeight } else { $resolvedPageSize }

    return @{
        PageSize   = $resolvedPageSize
        LoadMore   = $resolvedLoadMore
        ViewHeight = $resolvedViewHeight
    }
}
