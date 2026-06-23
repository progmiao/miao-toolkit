# 路径与控制台初始化（由 bin/miao.ps1 调用 Initialize-Paths）

$script:ManifestCache = $null

function Test-ConsoleKeyAvailable {
    if ($Host.Name -ne 'ConsoleHost') { return $false }

    try {
        return [Console]::KeyAvailable
    }
    catch {
        return $false
    }
}

function Initialize-ConsoleVirtualKeyPeek {
    if ($script:ConsoleVirtualKeyPeekReady) { return }
    $script:ConsoleVirtualKeyPeekReady = $true
    if ($Host.Name -ne 'ConsoleHost') { return }

    try {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class MiaoConsoleVirtualKey {
    private const int StdInputHandle = -10;
    private const ushort KeyEventType = 1;

    [StructLayout(LayoutKind.Explicit)]
    public struct InputRecord {
        [FieldOffset(0)] public ushort EventType;
        [FieldOffset(4)] public KeyEventRecord KeyEvent;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct KeyEventRecord {
        [MarshalAs(UnmanagedType.Bool)] public bool KeyDown;
        public ushort RepeatCount;
        public ushort VirtualKeyCode;
        public ushort VirtualScanCode;
        public char UnicodeChar;
        public uint ControlKeyState;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GetStdHandle(int nStdHandle);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool PeekConsoleInput(IntPtr hConsoleInput, out InputRecord lpBuffer, uint nLength, out uint lpNumberOfEventsRead);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool ReadConsoleInput(IntPtr hConsoleInput, out InputRecord lpBuffer, uint nLength, out uint lpNumberOfEventsRead);

    private static string MapVirtualKey(ushort vk) {
        if (vk == 27) { return "Escape"; }
        if (vk == 13) { return "Enter"; }
        if (vk == 38) { return "UpArrow"; }
        if (vk == 40) { return "DownArrow"; }
        return "Other";
    }

    private static string ReadNextKeyDown() {
        IntPtr handle = GetStdHandle(StdInputHandle);
        while (true) {
            InputRecord record;
            uint read;
            if (!ReadConsoleInput(handle, out record, 1, out read) || read < 1) {
                return null;
            }
            if (record.EventType != KeyEventType) { continue; }
            if (!record.KeyEvent.KeyDown) { continue; }
            return MapVirtualKey(record.KeyEvent.VirtualKeyCode);
        }
    }

    public static string PeekNextKeyDown() {
        IntPtr handle = GetStdHandle(StdInputHandle);
        InputRecord record;
        uint read;
        if (!PeekConsoleInput(handle, out record, 1, out read) || read < 1) {
            return null;
        }
        if (record.EventType != KeyEventType || !record.KeyEvent.KeyDown) {
            return null;
        }
        return MapVirtualKey(record.KeyEvent.VirtualKeyCode);
    }

    public static string ConsumeNextKeyDown() {
        return ReadNextKeyDown();
    }
}
'@ -ErrorAction Stop
        $script:ConsoleVirtualKeyPeekEnabled = $true
    }
    catch {
        $script:ConsoleVirtualKeyPeekEnabled = $false
    }
}

function Get-ConsoleVirtualKeyPeek {
    Initialize-ConsoleVirtualKeyPeek
    if (-not $script:ConsoleVirtualKeyPeekEnabled) { return $null }
    if (-not (Test-ConsoleKeyAvailable)) { return $null }

    try {
        return [MiaoConsoleVirtualKey]::PeekNextKeyDown()
    }
    catch {
        return $null
    }
}

function Read-ConsoleVirtualKeyConsume {
    Initialize-ConsoleVirtualKeyPeek
    if (-not $script:ConsoleVirtualKeyPeekEnabled) {
        if (-not (Test-ConsoleKeyAvailable)) { return $null }
        $key = [Console]::ReadKey($true)
        return [string]$key.Key
    }

    try {
        return [MiaoConsoleVirtualKey]::ConsumeNextKeyDown()
    }
    catch {
        return $null
    }
}

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
        throw (Get-I18n -Key 'message.pathsNotInitialized')
    }
    return $script:HomeResolved
}

function Get-ToolsRoot {
    return Get-BundledToolsRoot
}

function Get-BundledToolsRoot {
    Join-Path (Get-Home) 'tools'
}

function Get-ExternalToolsRoot {
    Join-Path (Get-UserConfigDirectory) 'extensions\tools'
}

function Ensure-ExternalToolsRoot {
    $dir = Get-ExternalToolsRoot
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return $dir
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
        throw (Get-I18n -Key 'message.missingManifest')
    }

    $script:ManifestCache = Get-Content -Raw -Path $path -Encoding UTF8 | ConvertFrom-Json
    return $script:ManifestCache
}

function Write-ToolkitVersionLine {
    Write-Host (Get-Manifest).version
}

function Format-ReleaseDate {
    param([string]$Raw)

    if ([string]::IsNullOrWhiteSpace($Raw)) { return '-' }
    try {
        return ([DateTime]::Parse($Raw)).ToString('yyyy-MM-dd')
    }
    catch {
        if ($Raw -match '^(\d{4}-\d{2}-\d{2})') { return $Matches[1] }
        return $Raw
    }
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
    if ($Tool.command) { return [string]$Tool.command }
    if ($Tool.id) { return [string]$Tool.id }
    return ''
}

function Get-ShellListItemCommand {
    param($Item)

    if ($Item.command) { return [string]$Item.command }
    if ($Item.id) { return [string]$Item.id }
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
        name        = [int]$script:ToolkitToolListColumnWidths.name
        description = [int]$script:ToolkitToolListColumnWidths.description
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
