# 无依赖 WinGet 工具：安装（含检测/更新）与卸载

function Import-WingetSimpleToolShellCore {
    param([string]$CoreLib)

    if (-not (Get-Command Initialize-PathsFromToolRoot -ErrorAction SilentlyContinue)) {
        . (Join-Path $CoreLib 'config\Paths.ps1')
        . (Join-Path $CoreLib 'config\ListLayout.ps1')
        . (Join-Path $CoreLib 'config\UserConfig.ps1')
        . (Join-Path $CoreLib 'config\I18n.ps1')
    }

    foreach ($rel in @(
            'ui\console\Console-Menu.ps1'
            'ui\shell\Nav.ps1'
            'ui\shell\SystemToolbar.ps1'
            'ui\shell\SingleSelectList.ps1'
            'ui\shell\MultiSelectList.ps1'
            'ui\shell\ShellListModel.ps1'
            'ui\shell\ToolkitShellList.ps1'
            'ui\shell\Draw.ps1'
            'ui\shell\Layout.ps1'
            'ui\shell\Header.ps1'
            'ui\shell\Title.ps1'
            'ui\shell\Exit.ps1'
            'ui\shell\Footer.ps1'
        )) {
        . (Join-Path $CoreLib $rel)
    }

    foreach ($rel in @(
            'ui\shell\ShellListSearch.ps1'
            'ui\shell\ToolkitShellListLoad.ps1'
        )) {
        . (Join-Path $CoreLib $rel)
    }
}

function Import-WingetSimpleToolCore {
    param([string]$CoreLib)

    if (-not (Get-Command Invoke-WingetDepProcess -ErrorAction SilentlyContinue)) {
        . (Join-Path $CoreLib 'domain\Invoke-ToolDepPackage.ps1')
    }
    if (-not (Get-Command Get-WingetPackageInstalledVersion -ErrorAction SilentlyContinue)) {
        . (Join-Path $CoreLib 'domain\Ensure-ToolDeps.ps1')
    }
    if (-not (Get-Command Initialize-ToolkitDepBatchOperationView -ErrorAction SilentlyContinue)) {
        $batchPath = Join-Path $CoreLib 'ui\shell\BatchExecution.ps1'
        if (Test-Path -LiteralPath $batchPath) {
            . $batchPath
        }
        $depViewPath = Join-Path $CoreLib 'ui\shell\DepOperationView.ps1'
        if (Test-Path -LiteralPath $depViewPath) {
            . $depViewPath
        }
    }
}

function Get-WingetSimpleToolCommand {
    param([string]$ToolRoot)

    $tool = Get-ToolFromDirectory -ToolRoot $ToolRoot
    if ($tool -and $tool.command) {
        return [string]$tool.command
    }

    $dirName = Split-Path $ToolRoot -Leaf
    $idx = $dirName.IndexOf('-')
    if ($idx -ge 0) {
        return [string]$dirName.Substring($idx + 1)
    }
    return [string]$dirName
}

function Get-WingetSimpleToolPackageConfig {
    param([string]$ToolRoot)

    $configPath = Join-Path $ToolRoot 'index.json'
    $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $config.winget) {
        throw "winget config missing in $configPath"
    }
    return $config.winget
}

function Get-WingetSimpleToolPackageId {
    param([string]$ToolRoot)

    return [string](Get-WingetSimpleToolPackageConfig -ToolRoot $ToolRoot).packageId
}

function Get-WingetSimpleToolI18n {
    param(
        [string]$ToolRoot,
        [string]$Suffix,
        [hashtable]$Vars = @{}
    )

    $prefix = Get-WingetSimpleToolCommand -ToolRoot $ToolRoot
    $key = "$prefix.$Suffix"
    return Get-ToolI18n -ToolRoot $ToolRoot -Key $key -Vars $Vars
}

function Initialize-WingetSimpleToolActionPage {
    param(
        [string]$ToolRoot,
        [hashtable]$ToolkitShell = $null,
        [int]$PageSize = 0,
        [int]$ViewHeight = 0
    )

    $coreLib = Join-Path $ToolRoot '..\..\core\lib'
    Import-WingetSimpleToolShellCore -CoreLib $coreLib
    Initialize-PathsFromToolRoot -ToolRoot $ToolRoot

    $paging = Resolve-MenuPagingDefaults -PageSize $PageSize -ViewHeight $ViewHeight
    $standaloneShell = $false
    if (-not $ToolkitShell) {
        $ToolkitShell = Initialize-ToolkitShell
        $standaloneShell = $true
    }

    Sync-MiaoLocaleFromShell -Shell $ToolkitShell

    return [pscustomobject]@{
        ToolRoot        = $ToolRoot
        CoreLib         = $coreLib
        Shell           = $ToolkitShell
        PageSize        = $paging.PageSize
        ViewHeight      = $paging.ViewHeight
        StandaloneShell = $standaloneShell
    }
}

function Get-WingetSimpleToolActionSectionTitle {
    param(
        [string]$ToolRoot,
        $Action = $null,
        [string]$ScriptLeaf = ''
    )

    if (-not (Get-Command Format-ToolActionSectionTitle -ErrorAction SilentlyContinue)) {
        $coreLib = Join-Path $ToolRoot '..\..\core\lib'
        . (Join-Path $coreLib 'ui\shell\ToolActionSectionTitle.ps1')
    }

    if ($Action) {
        return (Format-ToolActionSectionTitle -ToolRoot $ToolRoot -ActionNameKey ([string]$Action.name))
    }

    if (-not [string]::IsNullOrWhiteSpace($ScriptLeaf)) {
        $configPath = Join-Path $ToolRoot 'index.json'
        if (Test-Path -LiteralPath $configPath) {
            $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $match = @($config.actions | Where-Object {
                [string]$_.script -match [regex]::Escape($ScriptLeaf)
            } | Select-Object -First 1)
            if ($match) {
                return (Format-ToolActionSectionTitle -ToolRoot $ToolRoot -ActionNameKey ([string]$match.name))
            }
        }
    }

    return (Get-ToolSectionTitle -Tool (Get-ToolFromDirectory -ToolRoot $ToolRoot))
}

function Invoke-WingetSimpleToolNoticePage {
    param(
        [hashtable]$Shell,
        [string]$SectionTitle,
        [string]$Message,
        [string]$CacheKey = ''
    )

    $cacheKey = if ([string]::IsNullOrWhiteSpace($CacheKey)) { 'WingetSimpleToolNotice' } else { $CacheKey }
    Clear-ShellListCache -Shell $Shell -CacheKey $cacheKey

    return Invoke-ToolkitShellList @{
        Mode             = 'Single'
        Shell            = $Shell
        SectionTitle     = $SectionTitle
        Rows             = @()
        CacheKey         = $cacheKey
        Toolbar          = (New-ShellSystemToolbarConfig)
        EmptyListMessage = $Message
    }
}

function New-WingetSimpleToolArgumentList {
    param(
        [ValidateSet('install', 'upgrade', 'uninstall')]
        [string]$Verb,
        [string]$ToolRoot
    )

    $cfg = Get-WingetSimpleToolPackageConfig -ToolRoot $ToolRoot
    $packageId = [string]$cfg.packageId
    $args = @($Verb, '--id', $packageId, '-e')

    if ($Verb -in @('install', 'upgrade')) {
        $args += @(
            '--accept-package-agreements'
            '--accept-source-agreements'
            '--silent'
        )
        $source = ''
        if ($cfg.PSObject.Properties['source']) {
            $source = [string]$cfg.source
        }
        if (-not [string]::IsNullOrWhiteSpace($source)) {
            $args += @('--source', $source)
        }
    }

    return @($args)
}

function Test-WingetSimpleToolInstalled {
    param(
        [string]$ToolRoot,
        [string]$CoreLib = ''
    )

    if (-not [string]::IsNullOrWhiteSpace($CoreLib)) {
        Import-WingetSimpleToolCore -CoreLib $CoreLib
    }

    if (-not (Get-Command Get-WingetPackageInstalledVersion -ErrorAction SilentlyContinue)) {
        return $false
    }

    $version = Get-WingetPackageInstalledVersion -PackageId (Get-WingetSimpleToolPackageId -ToolRoot $ToolRoot)
    return -not [string]::IsNullOrWhiteSpace($version)
}

function Get-WingetSimpleToolInstalledVersion {
    param(
        [string]$ToolRoot,
        [string]$CoreLib = ''
    )

    if (-not [string]::IsNullOrWhiteSpace($CoreLib)) {
        Import-WingetSimpleToolCore -CoreLib $CoreLib
    }

    return Get-WingetPackageInstalledVersion -PackageId (Get-WingetSimpleToolPackageId -ToolRoot $ToolRoot)
}

function Test-WingetSimpleToolUpdateAvailable {
    param(
        [string]$ToolRoot,
        [string]$CoreLib = ''
    )

    if (-not (Test-WingetSimpleToolInstalled -ToolRoot $ToolRoot -CoreLib $CoreLib)) {
        return $false
    }

    if (-not [string]::IsNullOrWhiteSpace($CoreLib)) {
        Import-WingetSimpleToolCore -CoreLib $CoreLib
    }

    if (-not (Get-Command Test-WingetPackageUpdateAvailable -ErrorAction SilentlyContinue)) {
        return $false
    }

    $packageId = Get-WingetSimpleToolPackageId -ToolRoot $ToolRoot
    $installedVersion = Get-WingetSimpleToolInstalledVersion -ToolRoot $ToolRoot -CoreLib $CoreLib
    return (Test-WingetPackageUpdateAvailable -PackageId $packageId `
        -InstalledVersion $(if ($installedVersion) { $installedVersion } else { '' }))
}

function Write-WingetSimpleToolBatchLogLine {
    param(
        $Log,
        [string]$Text,
        [string]$Kind = 'text',
        [switch]$WithTimestamp
    )

    if ($null -eq $Log -or $null -eq $Log.Lines) { return }

    $lineColor = [System.ConsoleColor]::Gray
    switch ($Kind) {
        'section' { $lineColor = [System.ConsoleColor]::Cyan }
        'success' { $lineColor = [System.ConsoleColor]::Green }
        'error' { $lineColor = [System.ConsoleColor]::Red }
        'heading' { $lineColor = [System.ConsoleColor]::White }
        'separator' { $lineColor = [System.ConsoleColor]::DarkGray }
    }

    $timestamp = if ($WithTimestamp) { (Get-Date).ToString('HH:mm:ss') } else { '' }
    $Log.Lines.Add([pscustomobject]@{
        Timestamp = $timestamp
        Text      = [string]$Text
        Kind      = $Kind
        Color     = $lineColor
    }) | Out-Null

    $maxLines = 500
    while ($Log.Lines.Count -gt $maxLines) {
        $Log.Lines.RemoveAt(0)
    }
}

function New-WingetSimpleToolOutputState {
    param(
        [ValidateSet('install', 'upgrade', 'uninstall')]
        [string]$Verb
    )

    $executeAction = if ($Verb -eq 'uninstall') { 'Uninstall' } else { 'Install' }
    return @{
        LastLoggedPercent        = -1
        LoggedPhases             = @{}
        SubstantiveLogCount      = 0
        PercentStage             = ''
        LoggedDownloadComplete   = $false
        LoggedInstallComplete    = $false
        WingetOutputSeen         = $false
        WingetInstallSilent      = $true
        ExecuteAction            = $executeAction
        InstallerAwaitingDialog  = $false
        InstallerPromptDismissed = $false
        InstallStarted           = $false
        InstallStartedTick       = 0
        WingetOperationSucceeded = $false
    }
}

function Update-WingetSimpleToolDepProgressFromDecision {
    param(
        $Ui,
        $WingetOutputState,
        $Decision
    )

    if ($null -eq $Ui -or $null -eq $WingetOutputState -or $null -eq $Decision) { return }

    if (Get-Command Update-ToolkitDepWingetProgressFromDecision -ErrorAction SilentlyContinue) {
        Update-ToolkitDepWingetProgressFromDecision -Ui $Ui -WingetOutputState $WingetOutputState -Decision $Decision
    }
}

function Sync-WingetSimpleToolDepProgressChrome {
    param(
        $Ui,
        $WingetOutputState
    )

    if ($null -eq $Ui -or $null -eq $WingetOutputState -or -not $Ui.ItemInFlight) { return }
    if (-not (Get-Command Sync-ToolkitDepWingetItemProgress -ErrorAction SilentlyContinue)) { return }

    $elapsed = 0
    if ([int]$Ui.ExecuteStartTick -gt 0) {
        $elapsed = [int][Math]::Floor(([Environment]::TickCount - [int]$Ui.ExecuteStartTick) / 1000.0)
    }
    Sync-ToolkitDepWingetItemProgress -Ui $Ui -WingetOutputState $WingetOutputState -ElapsedSeconds $elapsed
}

function Invoke-WingetSimpleToolStreamWork {
    param(
        $Context,
        [ValidateSet('install', 'upgrade', 'uninstall')]
        [string]$Verb,
        [string]$ToolRoot,
        [string]$SuccessSuffix,
        [string]$FailureSuffix,
        [scriptblock]$Pump,
        $WingetOutputState = $null
    )

    $log = $Context.Log
    $ui = $Context.Ui
    $RedrawView = $Context.RedrawView
    $label = Get-WingetSimpleToolPackageId -ToolRoot $ToolRoot
    $fnWriteLog = ${function:Write-WingetSimpleToolBatchLogLine}

    $sectionText = Get-I18n -Key 'page.depOperation.logSectionPackage' -Vars @{
        name  = $label
        index = 1
        total = 1
    }
    & $fnWriteLog -Log $log -Text $sectionText -Kind 'section' -WithTimestamp

    $ui.ProgressName = $label
    $ui.ItemInFlight = $true
    $ui.ExecuteStartTick = [Environment]::TickCount
    Set-ToolkitDepOperationInFlightStatus -Ui $ui -MainText $label -AdvanceSpinner
    & $RedrawView

    $wingetOutputState = if ($WingetOutputState) { $WingetOutputState } else { New-WingetSimpleToolOutputState -Verb $Verb }
    $fnGetOutputDecision = Get-Command Get-ToolkitDepWingetOutputDecision -ErrorAction SilentlyContinue
    $fnApplyProgress = ${function:Update-WingetSimpleToolDepProgressFromDecision}

    $onOutputLine = {
        param($Line)

        if ([string]::IsNullOrWhiteSpace($Line)) { return }

        $wingetOutputState['WingetOutputSeen'] = $true
        $decision = if ($fnGetOutputDecision) {
            & $fnGetOutputDecision -Line $Line -OutputState $wingetOutputState
        }
        else {
            @{ LogText = [string]$Line; StatusText = [string]$Line; Percent = -1; RedrawOnly = $false }
        }

        if ([int]$decision.Percent -ge 0 -or $decision.ProgressPhase) {
            & $fnApplyProgress -Ui $ui -WingetOutputState $wingetOutputState -Decision $decision
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$decision.StatusText)) {
            Set-ToolkitDepOperationInFlightStatus -Ui $ui -MainText ([string]$decision.StatusText) -AdvanceSpinner
        }

        if ($decision.LogText -and -not $decision.RedrawOnly) {
            & $fnWriteLog -Log $log -Text ([string]$decision.LogText) -Kind 'text' -WithTimestamp
        }

        & $Pump
        & $RedrawView
    }.GetNewClosure()

    $argumentList = New-WingetSimpleToolArgumentList -Verb $Verb -ToolRoot $ToolRoot
    $wingetResult = Invoke-WingetDepProcess -ArgumentList $argumentList `
        -OnOutputLine $onOutputLine `
        -OnUiPoll { & $Pump } `
        -OnChromePulse { & $Pump }

    $ok = $false
    if ($wingetResult) {
        if ($wingetResult.PSObject.Properties['Success']) {
            $ok = [bool]$wingetResult.Success
        }
        elseif ($null -ne $wingetResult.ExitCode) {
            $ok = ([int]$wingetResult.ExitCode -eq 0)
        }
    }

    if ($ok) {
        & $fnWriteLog -Log $log -Text (Get-WingetSimpleToolI18n -ToolRoot $ToolRoot -Suffix $SuccessSuffix) `
            -Kind 'success' -WithTimestamp
    }
    else {
        $detail = ''
        if ($wingetResult -and $wingetResult.Output) {
            $detail = [string]$wingetResult.Output
        }
        if ([string]::IsNullOrWhiteSpace($detail) -and $wingetResult -and $null -ne $wingetResult.ExitCode) {
            $detail = "exit $($wingetResult.ExitCode)"
        }
        if ([string]::IsNullOrWhiteSpace($detail)) { $detail = 'unknown error' }
        & $fnWriteLog -Log $log -Text (Get-WingetSimpleToolI18n -ToolRoot $ToolRoot -Suffix $FailureSuffix `
            -Vars @{ detail = $detail }) -Kind 'error' -WithTimestamp
    }

    return @{
        Ok     = $ok
        Result = $wingetResult
    }
}

function Invoke-WingetSimpleToolInstallPage {
    param(
        [hashtable]$Shell,
        [string]$SectionTitle,
        [string]$ToolRoot,
        [string]$CoreLib
    )

    Import-WingetSimpleToolCore -CoreLib $CoreLib

    $readyText = Get-WingetSimpleToolI18n -ToolRoot $ToolRoot -Suffix 'cli.installStatusReady'
    $ctx = Initialize-ToolkitDepBatchOperationView -Shell $Shell -SectionTitle $SectionTitle `
        -ProgressTotal 1 -ReadyStatusText $readyText

    $log = $ctx.Log
    $ui = $ctx.Ui
    $RedrawView = $ctx.RedrawView
    $outcome = @{
        Intent        = 'install'
        SuccessCount  = 0
        FailedCount   = 0
        WorkPerformed = $false
    }

    try {
        & $ctx.FnDrainStaleInput
        if (Get-Command Clear-ConsoleInputBuffer -ErrorAction SilentlyContinue) {
            Clear-ConsoleInputBuffer
        }

        Set-ToolkitShellToolbarLocked -Shell $Shell -Locked $true
        $ui.ItemInFlight = $true
        $ui.ExecuteStartTick = [Environment]::TickCount
        Start-ToolkitDepOperationBatch -Ui $ui
        & $RedrawView

        $wingetOutputState = New-WingetSimpleToolOutputState -Verb 'install'
        $fnWriteLog = ${function:Write-WingetSimpleToolBatchLogLine}
        $fnSyncProgress = ${function:Sync-WingetSimpleToolDepProgressChrome}

        $pump = {
            Invoke-ToolkitDepBatchOperationUiPump -Context $ctx
            & $fnSyncProgress -Ui $ui -WingetOutputState $wingetOutputState
        }.GetNewClosure()

        $detectText = Get-WingetSimpleToolI18n -ToolRoot $ToolRoot -Suffix 'cli.detectStatus'
        Set-ToolkitDepOperationInFlightStatus -Ui $ui -MainText $detectText -AdvanceSpinner
        & $RedrawView
        & $pump
        & $fnWriteLog -Log $log -Text $detectText -Kind 'heading' -WithTimestamp

        $installed = Test-WingetSimpleToolInstalled -ToolRoot $ToolRoot -CoreLib $CoreLib
        & $pump

        if (-not $installed) {
            & $fnWriteLog -Log $log -Text (Get-WingetSimpleToolI18n -ToolRoot $ToolRoot `
                -Suffix 'cli.detectNotInstalled') -Kind 'text' -WithTimestamp
            $outcome.WorkPerformed = $true

            $streamResult = Invoke-WingetSimpleToolStreamWork -Context $ctx -Verb install `
                -ToolRoot $ToolRoot -SuccessSuffix 'cli.installSuccess' `
                -FailureSuffix 'cli.installFailed' -Pump $pump -WingetOutputState $wingetOutputState
            if ($streamResult.Ok) { $outcome.SuccessCount = 1 }
            else { $outcome.FailedCount = 1 }
        }
        else {
            $version = Get-WingetSimpleToolInstalledVersion -ToolRoot $ToolRoot -CoreLib $CoreLib
            $versionLabel = if ($version) { $version } else { '?' }
            & $fnWriteLog -Log $log -Text (Get-WingetSimpleToolI18n -ToolRoot $ToolRoot `
                -Suffix 'cli.detectInstalled' -Vars @{ version = $versionLabel }) `
                -Kind 'text' -WithTimestamp
            & $pump

            Set-ToolkitDepOperationInFlightStatus -Ui $ui -MainText (Get-WingetSimpleToolI18n -ToolRoot $ToolRoot `
                -Suffix 'cli.detectUpdatePreflight') -AdvanceSpinner
            & $RedrawView
            & $pump

            & $fnWriteLog -Log $log -Text (Get-WingetSimpleToolI18n -ToolRoot $ToolRoot `
                -Suffix 'cli.detectUpdatePreflight') -Kind 'text' -WithTimestamp

            Set-ToolkitDepOperationInFlightStatus -Ui $ui -MainText (Get-WingetSimpleToolI18n -ToolRoot $ToolRoot `
                -Suffix 'cli.detectUpdateStatus') -AdvanceSpinner
            & $RedrawView
            & $pump

            $updateCheck = Resolve-WingetPackageUpdateCheck -PackageId (Get-WingetSimpleToolPackageId -ToolRoot $ToolRoot) `
                -InstalledVersion $versionLabel -OnPulse $pump
            & $pump

            if ($updateCheck.Skipped) {
                $skipSuffix = if ([string]$updateCheck.SkipReason -eq 'timeout') {
                    'cli.detectUpdateSkippedTimeout'
                }
                else {
                    'cli.detectUpdateSkippedNetwork'
                }
                & $fnWriteLog -Log $log -Text (Get-WingetSimpleToolI18n -ToolRoot $ToolRoot `
                    -Suffix $skipSuffix -Vars @{ version = $versionLabel }) -Kind 'success' -WithTimestamp
                $outcome.SuccessCount = 1
            }
            elseif ($updateCheck.Available) {
                & $fnWriteLog -Log $log -Text (Get-WingetSimpleToolI18n -ToolRoot $ToolRoot `
                    -Suffix 'cli.detectUpdateAvailable') -Kind 'text' -WithTimestamp
                $outcome.Intent = 'update'
                $outcome.WorkPerformed = $true

                $streamResult = Invoke-WingetSimpleToolStreamWork -Context $ctx -Verb upgrade `
                    -ToolRoot $ToolRoot -SuccessSuffix 'cli.updateSuccess' `
                    -FailureSuffix 'cli.updateFailed' -Pump $pump -WingetOutputState $wingetOutputState
                if ($streamResult.Ok) { $outcome.SuccessCount = 1 }
                else { $outcome.FailedCount = 1 }
            }
            else {
                & $fnWriteLog -Log $log -Text (Get-WingetSimpleToolI18n -ToolRoot $ToolRoot `
                    -Suffix 'cli.alreadyLatest' -Vars @{ version = $versionLabel }) `
                    -Kind 'success' -WithTimestamp
                $outcome.SuccessCount = 1
            }
        }

        $ui.ItemInFlight = $false
        $ui.ItemSubPercent = -1
        $ui.ProgressCurrent = 1

        Set-ToolkitDepOperationBatchCompleteUi -Ui $ui -Intent $outcome.Intent `
            -TotalCount 1 -SuccessCount $outcome.SuccessCount -FailedCount $outcome.FailedCount `
            -ProgressCurrent 1

        return Invoke-ToolkitDepBatchOperationWaitLoop -Context $ctx
    }
    finally {
        Clear-ToolkitDepBatchOperationView -Context $ctx
    }
}

function Invoke-WingetSimpleToolUninstallPage {
    param(
        [hashtable]$Shell,
        [string]$SectionTitle,
        [string]$ToolRoot,
        [string]$CoreLib
    )

    Import-WingetSimpleToolCore -CoreLib $CoreLib

    if (-not (Test-WingetSimpleToolInstalled -ToolRoot $ToolRoot -CoreLib $CoreLib)) {
        return Invoke-WingetSimpleToolNoticePage -Shell $Shell -SectionTitle $SectionTitle `
            -Message (Get-WingetSimpleToolI18n -ToolRoot $ToolRoot -Suffix 'cli.notInstalled') `
            -CacheKey "$(Get-WingetSimpleToolCommand -ToolRoot $ToolRoot)UninstallNotice"
    }

    $readyText = Get-WingetSimpleToolI18n -ToolRoot $ToolRoot -Suffix 'cli.uninstallStatusReady'
    $ctx = Initialize-ToolkitDepBatchOperationView -Shell $Shell -SectionTitle $SectionTitle `
        -ProgressTotal 1 -ReadyStatusText $readyText

    $ui = $ctx.Ui
    $RedrawView = $ctx.RedrawView
    $successCount = 0
    $failedCount = 0

    try {
        & $ctx.FnDrainStaleInput
        if (Get-Command Clear-ConsoleInputBuffer -ErrorAction SilentlyContinue) {
            Clear-ConsoleInputBuffer
        }

        Set-ToolkitShellToolbarLocked -Shell $Shell -Locked $true
        Start-ToolkitDepOperationBatch -Ui $ui
        & $RedrawView

        $wingetOutputState = New-WingetSimpleToolOutputState -Verb 'uninstall'
        $fnSyncProgress = ${function:Sync-WingetSimpleToolDepProgressChrome}
        $pump = {
            Invoke-ToolkitDepBatchOperationUiPump -Context $ctx
            & $fnSyncProgress -Ui $ui -WingetOutputState $wingetOutputState
        }.GetNewClosure()

        $streamResult = Invoke-WingetSimpleToolStreamWork -Context $ctx -Verb uninstall `
            -ToolRoot $ToolRoot -SuccessSuffix 'cli.uninstallSuccess' `
            -FailureSuffix 'cli.uninstallFailed' -Pump $pump -WingetOutputState $wingetOutputState
        if ($streamResult -and $streamResult.Ok) { $successCount = 1 }
        else { $failedCount = 1 }

        $ui.ItemInFlight = $false
        $ui.ItemSubPercent = -1
        $ui.ProgressCurrent = 1

        Set-ToolkitDepOperationBatchCompleteUi -Ui $ui -Intent 'uninstall' `
            -TotalCount 1 -SuccessCount $successCount -FailedCount $failedCount -ProgressCurrent 1

        return Invoke-ToolkitDepBatchOperationWaitLoop -Context $ctx
    }
    finally {
        Clear-ToolkitDepBatchOperationView -Context $ctx
    }
}
