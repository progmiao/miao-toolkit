# test-terminal-buddy-tool.ps1 — terminal-buddy 工具发现、i18n、Gitee Release 解析

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$lib = Join-Path $root 'package\core\lib'
. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib
Initialize-Paths -BinDirectory (Join-Path $root 'package\bin')

$toolRoot = Join-Path $root 'package\tools\09-terminal-buddy'
Initialize-PathsFromToolRoot -ToolRoot $toolRoot

$tool = Get-ToolFromDirectory -ToolRoot $toolRoot
if (-not $tool) { throw 'tool not discovered' }
if ([string]$tool.command -ne 'terminal-buddy') { throw "unexpected command: $($tool.command)" }
if ([int]$tool.sortOrder -ne 9) { throw "unexpected sortOrder: $($tool.sortOrder)" }

$config = Get-Content (Join-Path $toolRoot 'index.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($config.PSObject.Properties['winget']) { throw 'index.json should not contain winget config' }
if (-not $config.gitee) { throw 'index.json must contain gitee config' }

$name = Resolve-ToolI18nLabel -ToolRoot $toolRoot -Key 'terminal-buddy.name' -Fallback 'terminal-buddy'
if ([string]::IsNullOrWhiteSpace($name)) { throw 'name i18n empty' }

$actions = @($config.actions)
if ($actions.Count -ne 4) { throw "expected 4 actions, got $($actions.Count)" }
if ($actions[0].command -ne 'install') { throw 'first action must be install' }
if ($actions[1].command -ne 'uninstall') { throw 'second action must be uninstall' }
if ($actions[2].command -ne 'gitee-doc') { throw 'third action must be gitee-doc' }
if ($actions[3].command -ne 'github-doc') { throw 'fourth action must be github-doc' }
if ([string]$actions[2].menuCommand -ne '-') { throw 'gitee-doc menuCommand must be -' }
if ([string]$actions[3].menuCommand -ne '-') { throw 'github-doc menuCommand must be -' }

$installScript = Get-Content (Join-Path $toolRoot 'lib\install.ps1') -Raw -Encoding UTF8
if ($installScript -notmatch 'BatchExecution\.ps1') {
    throw 'install.ps1 must preload BatchExecution at script scope'
}

. (Join-Path $toolRoot 'lib\terminal-buddy-core.ps1')
. (Join-Path $toolRoot 'lib\terminal-buddy-state.ps1')

$paths = Get-TerminalBuddyKnownPaths
if ($paths.ExePath -notmatch 'Programs\\terminal-buddy\\terminal-buddy\.exe$') {
    throw "unexpected ExePath: $($paths.ExePath)"
}

$url = Get-TerminalBuddyGiteeDownloadUrl -Tag 'v1.1.0' -ToolRoot $toolRoot
if ($url -notmatch 'gitee\.com/updateme/terminal-buddy/releases/download/v1\.1\.0/terminal-buddy\.exe') {
    throw "unexpected download url: $url"
}

$normalized = Normalize-TerminalBuddyVersion -Version 'v1.1.0'
if ($normalized -ne '1.1.0') { throw "version normalize failed: $normalized" }

if ((Compare-TerminalBuddyVersion -Installed '1.0.0' -Latest '1.1.0') -ge 0) {
    throw '1.0.0 should be older than 1.1.0'
}

if (Test-TerminalBuddyInstalled) {
    Write-Host 'terminal-buddy detected on machine; skipping mock-path tests'
}
else {
    $fakeRoot = Join-Path $env:TEMP ("miao-terminal-buddy-test-" + [guid]::NewGuid().ToString('N'))
    $fakeInstallDir = Join-Path $fakeRoot 'Programs\terminal-buddy'
    New-Item -ItemType Directory -Path $fakeInstallDir -Force | Out-Null

    $fakeExe = Join-Path $fakeInstallDir 'terminal-buddy.exe'
    Set-Content -LiteralPath $fakeExe -Value 'fake' -Encoding ASCII

    $origLocalAppData = $env:LOCALAPPDATA
    try {
        $env:LOCALAPPDATA = $fakeRoot

        if (-not (Test-TerminalBuddyInstalled)) {
            throw 'Test-TerminalBuddyInstalled should be true when fake exe exists'
        }

        $resolved = Resolve-TerminalBuddyExecutable
        if ($resolved -ne $fakeExe) {
            throw "Resolve-TerminalBuddyExecutable expected fake exe, got [$resolved]"
        }
    }
    finally {
        $env:LOCALAPPDATA = $origLocalAppData
        Remove-Item -LiteralPath $fakeRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Import-MiaoToolDepsModule
$menuRows = ConvertTo-ToolMenuListRows -ToolRoot $toolRoot -MenuItems @($actions[2])
if ($menuRows[0].Cells[0] -ne '-') {
    throw "gitee-doc menu command display should be -, got [$($menuRows[0].Cells[0])]"
}

try {
    $latest = Get-TerminalBuddyLatestRelease -ToolRoot $toolRoot
    if ([string]::IsNullOrWhiteSpace($latest.Tag)) {
        throw 'latest release tag empty'
    }
    if ($latest.DownloadUrl -notmatch 'terminal-buddy\.exe$') {
        throw "latest download url invalid: $($latest.DownloadUrl)"
    }
    Write-Host "gitee latest release: v$($latest.Tag)"
}
catch {
    Write-Host "gitee release API unavailable in this environment: $($_.Exception.Message)"
}

Write-Host 'test-terminal-buddy-tool.ps1 OK'
