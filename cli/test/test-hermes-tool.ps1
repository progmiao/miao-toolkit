# test-hermes-tool.ps1 — hermes 工具发现、i18n、CLI 路径解析

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$lib = Join-Path $root 'package\core\lib'
. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib
Initialize-Paths -BinDirectory (Join-Path $root 'package\bin')

$toolRoot = Join-Path $root 'package\tools\08-hermes'
Initialize-PathsFromToolRoot -ToolRoot $toolRoot

$tool = Get-ToolFromDirectory -ToolRoot $toolRoot
if (-not $tool) { throw 'tool not discovered' }
if ([string]$tool.command -ne 'hermes') { throw "unexpected command: $($tool.command)" }
if ([int]$tool.sortOrder -ne 8) { throw "unexpected sortOrder: $($tool.sortOrder)" }

$config = Get-Content (Join-Path $toolRoot 'index.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($config.PSObject.Properties['winget']) { throw 'index.json should not contain winget config' }

$name = Resolve-ToolI18nLabel -ToolRoot $toolRoot -Key 'hermes.name' -Fallback 'hermes'
if ([string]::IsNullOrWhiteSpace($name)) { throw 'name i18n empty' }

$actions = @($config.actions)
if ($actions.Count -ne 2) { throw "expected 2 actions, got $($actions.Count)" }
if ($actions[0].command -ne 'install') { throw 'first action must be install' }
if ($actions[1].command -ne 'uninstall') { throw 'second action must be uninstall' }

$installScript = Get-Content (Join-Path $toolRoot 'lib\install.ps1') -Raw -Encoding UTF8
if ($installScript -notmatch 'BatchExecution\.ps1') {
    throw 'install.ps1 must preload BatchExecution at script scope'
}

. (Join-Path $toolRoot 'lib\hermes-core.ps1')
. (Join-Path $toolRoot 'lib\hermes-state.ps1')
. (Join-Path $toolRoot 'lib\hermes-progress.ps1')

$paths = Get-HermesKnownPaths
if ($paths.HermesExe -notmatch 'hermes-agent\\venv\\Scripts\\hermes\.exe$') {
    throw "unexpected HermesExe path: $($paths.HermesExe)"
}

if (Test-HermesInstalled) {
    Write-Host 'hermes CLI detected on machine; skipping mock-path tests'
}
else {
    $fakeRoot = Join-Path $env:TEMP ("miao-hermes-test-" + [guid]::NewGuid().ToString('N'))
    $fakeHermesHome = Join-Path $fakeRoot 'hermes'
    $fakeVenvScripts = Join-Path $fakeHermesHome 'hermes-agent\venv\Scripts'
    New-Item -ItemType Directory -Path $fakeVenvScripts -Force | Out-Null

    $fakeExe = Join-Path $fakeVenvScripts 'hermes.exe'
    '@echo off' | Set-Content -LiteralPath $fakeExe -Encoding ASCII

    $origLocalAppData = $env:LOCALAPPDATA
    try {
        $env:LOCALAPPDATA = $fakeRoot

        if (-not (Test-HermesInstalled)) {
            throw 'Test-HermesInstalled should be true when fake hermes.exe exists'
        }

        $resolved = Resolve-HermesExecutable
        if ($resolved -ne $fakeExe) {
            throw "Resolve-HermesExecutable expected fake exe, got [$resolved]"
        }
    }
    finally {
        $env:LOCALAPPDATA = $origLocalAppData
        Remove-Item -LiteralPath $fakeRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$wrapper = Get-HermesInstallWrapperScriptContent
if ($wrapper -notmatch '-SkipSetup') { throw 'install wrapper must pass -SkipSetup' }
if ($wrapper -notmatch 'hermes-agent\.nousresearch\.com') { throw 'install wrapper must use official URL' }

if ($script:HermesInstallProcessExitWaitMs -lt 7200000) {
    throw 'HermesInstallProcessExitWaitMs should be at least 120 minutes'
}

$progress = New-HermesProgressState -Flow 'fresh-install'
$band = Get-HermesProgressPhaseBand -State $progress -Phase 'install-run'
if ([int]$band.Base -ge [int]$band.Cap) { throw 'install-run progress band invalid' }

$ui = @{ ItemInFlight = $true; ItemSubPercent = 0; ExecuteStartTick = [Environment]::TickCount }
Bump-HermesProgressFromLog -State $progress -Ui $ui
if ([int]$ui.ItemSubPercent -le 0) { throw 'progress should advance on log output' }

. (Join-Path $toolRoot 'lib\hermes-batch.ps1')
$pump = New-HermesProgressPump -Context @{ Ui = $ui; PollState = @{} } -State $progress -Ui $ui
if (-not ($pump -is [scriptblock])) { throw 'New-HermesProgressPump should return scriptblock' }
try {
    & $pump
}
catch {
    if ([string]$_.Exception.Message -match 'Sync-HermesProgressCreep|Write-HermesProgressLogLine|Invoke-HermesProgressUiPump') {
        throw "progress pump should not fail on hermes command lookup: $($_.Exception.Message)"
    }
}

$updateAvailable = Resolve-HermesUpdateCheck -TimeoutMs 1000
if ($updateAvailable.Skipped -and $updateAvailable.SkipReason -eq 'network') {
    Write-Host 'network preflight skipped update check (expected in offline CI)'
}
elseif (-not (Test-HermesInstalled)) {
    if (-not $updateAvailable.Skipped) {
        throw 'update check should skip or fail when hermes is not installed'
    }
}

$hint = Get-HermesI18n -ToolRoot $toolRoot -Key 'hermes.cli.postInstallHint'
if ($hint -notmatch 'hermes setup') { throw 'postInstallHint missing setup guidance' }

Write-Host 'test-hermes-tool.ps1 OK'
