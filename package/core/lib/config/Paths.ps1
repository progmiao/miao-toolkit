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
        throw (Get-I18n -Key 'error.missingManifest')
    }

    $script:ManifestCache = Get-Content -Raw -Path $path -Encoding UTF8 | ConvertFrom-Json
    return $script:ManifestCache
}

function Get-ManifestTemplateVars {
    param([hashtable]$Extra = @{})

    $manifest = Get-Manifest
    $vars = @{
        shortName   = if ($manifest.shortName) { [string]$manifest.shortName } else { 'Miao' }
        title       = (Get-I18nRaw -Key 'brand.title')
        author      = (Get-BrandAuthorName)
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

    return Get-ListNumberDisplayWidth -TotalCount $TotalCount -MaxNumber $MaxNumber
}

function Get-MenuNumberWidth {
    param(
        [int]$TotalCount = 0,
        [int]$MaxNumber = 0
    )
    return Get-ListNumberDisplayWidth -TotalCount $TotalCount -MaxNumber $MaxNumber
}

function Get-ToolCommandName {
    param($Tool)
    if ($Tool.id) { return [string]$Tool.id }
    return ''
}

function Get-MenuCliCommandPrefix {
    return [string]$script:ToolkitCliCommandPrefix
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
    return [Math]::Max(1, [int]$script:ToolkitListColumnGap)
}

function Get-ToolListColumnWidths {
    return @{
        command     = [int]$script:ToolkitToolListColumnWidths.command
        displayName = [int]$script:ToolkitToolListColumnWidths.displayName
        summary     = [int]$script:ToolkitToolListColumnWidths.summary
        status      = [int]$script:ToolkitToolListColumnWidths.status
    }
}

function Get-MenuPageNumberDisplayWidth {
    param([int]$PageCount = 1)

    $digits = ([string][Math]::Max(1, $PageCount)).Length
    return [Math]::Max($script:ListPageNumberMinDisplayWidth, $digits)
}

function Get-PagingPageSize {
    $manifest = Get-Manifest
    if ($null -ne $manifest.pageSize) {
        return [int]$manifest.pageSize
    }
    if ($manifest.paging -and $manifest.paging.pageSize) {
        return [int]$manifest.paging.pageSize
    }
    if ($manifest.menu -and $manifest.menu.pageSize) {
        return [int]$manifest.menu.pageSize
    }
    return 10
}

function Get-MenuPageSize {
    return Get-PagingPageSize
}

function Get-BrandSeparatorExtra {
    return [int]$script:ToolkitBrandSeparatorExtra
}

function Get-BrandContactEmail {
    $manifest = Get-Manifest
    if ($manifest.email) {
        return [string]$manifest.email
    }
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
        [int]$ViewHeight = 0
    )

    $resolvedPageSize = if ($PageSize -gt 0) { $PageSize } else { Get-MenuPageSize }
    $resolvedViewHeight = if ($ViewHeight -gt 0) { $ViewHeight } else { $resolvedPageSize }

    return @{
        PageSize   = $resolvedPageSize
        ViewHeight = $resolvedViewHeight
    }
}
