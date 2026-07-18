# hermes — 分步骤进度（日志增量 + 时间 creep，避免长时间卡住后突跳）

function Get-HermesProgressFlowDefinition {
    param([string]$Flow)

    $bands = @{
        'fresh-install' = [ordered]@{
            detect      = @{ Base = 0; Cap = 14 }
            'install-run' = @{ Base = 14; Cap = 94 }
            complete    = @{ Base = 94; Cap = 100 }
        }
        'sync' = [ordered]@{
            detect       = @{ Base = 0; Cap = 8 }
            version      = @{ Base = 8; Cap = 14 }
            preflight    = @{ Base = 14; Cap = 20 }
            'update-check' = @{ Base = 20; Cap = 28 }
            'install-run'  = @{ Base = 28; Cap = 94 }
            complete     = @{ Base = 94; Cap = 100 }
        }
        'uninstall' = [ordered]@{
            'install-run' = @{ Base = 0; Cap = 94 }
            complete    = @{ Base = 94; Cap = 100 }
        }
    }

    if (-not $bands.ContainsKey($Flow)) {
        return $bands['fresh-install']
    }
    return $bands[$Flow]
}

function New-HermesProgressState {
    param(
        [ValidateSet('fresh-install', 'sync', 'uninstall')]
        [string]$Flow = 'fresh-install'
    )

    return @{
        Flow           = [string]$Flow
        Phase          = 'detect'
        PhaseStartTick = [Environment]::TickCount
        LogLineCount   = 0
        OutputSeen     = $false
        PhaseLogCount  = 0
    }
}

function Get-HermesProgressPhaseBand {
    param(
        $State,
        [string]$Phase = ''
    )

    $phaseName = if ([string]::IsNullOrWhiteSpace($Phase)) { [string]$State.Phase } else { $Phase }
    $definition = Get-HermesProgressFlowDefinition -Flow ([string]$State.Flow)
    if ($definition.Keys -contains $phaseName) {
        return $definition[$phaseName]
    }

    return @{ Base = 0; Cap = 99 }
}

function Apply-HermesProgressTarget {
    param(
        $Ui,
        [int]$Target,
        [switch]$Jump
    )

    if (-not $Ui -or -not $Ui.ItemInFlight) { return }

    $current = [int]$Ui.ItemSubPercent
    if ($current -lt 0) { $current = 0 }

    if ($Jump) {
        $next = [Math]::Max($current, $Target)
    }
    else {
        $delta = [Math]::Min(3, [Math]::Max(0, $Target - $current))
        $next = $current + $delta
    }

    if ($next -lt $current) { $next = $current }
    $cap = if ($Target -ge 100) { 100 } else { 99 }
    $Ui.ItemSubPercent = [Math]::Min($cap, $next)
}

function Set-HermesProgressPhase {
    param(
        $State,
        $Ui,
        [string]$Phase,
        [switch]$Jump
    )

    if (-not $State) { return }

    $State.Phase = [string]$Phase
    $State.PhaseStartTick = [Environment]::TickCount
    $State.PhaseLogCount = 0

    $band = Get-HermesProgressPhaseBand -State $State
    Apply-HermesProgressTarget -Ui $Ui -Target ([int]$band.Base) -Jump:$Jump
}

function Bump-HermesProgressFromLog {
    param(
        $State,
        $Ui
    )

    if (-not $State -or -not $Ui) { return }

    $State.LogLineCount++
    $State.PhaseLogCount++
    $State.OutputSeen = $true

    $band = Get-HermesProgressPhaseBand -State $State
    $span = [Math]::Max(1, [int]$band.Cap - [int]$band.Base - 1)
    $logTarget = [int]$band.Base + [Math]::Min($span - 1, [int][Math]::Floor([Math]::Sqrt([double]$State.PhaseLogCount) * 2.5))
    Apply-HermesProgressTarget -Ui $Ui -Target $logTarget
}

function Get-HermesProgressPhaseCreepSeconds {
    param(
        $State
    )

    switch ([string]$State.Phase) {
        'install-run' { return 3600 }
        'update-check' { return 90 }
        'preflight' { return 60 }
        'version' { return 45 }
        'detect' { return 75 }
        default { return 120 }
    }
}

function Sync-HermesProgressCreep {
    param(
        $State,
        $Ui
    )

    if (-not $State -or -not $Ui -or -not $Ui.ItemInFlight) { return }

    $band = Get-HermesProgressPhaseBand -State $State
    $span = [Math]::Max(1, [int]$band.Cap - [int]$band.Base - 1)
    $phaseStart = if ([int]$State.PhaseStartTick -gt 0) { [int]$State.PhaseStartTick } else { [int]$Ui.ExecuteStartTick }
    if ($phaseStart -le 0) { $phaseStart = [Environment]::TickCount }

    $phaseElapsed = [int][Math]::Max(0, [Math]::Floor(([Environment]::TickCount - $phaseStart) / 1000.0))
    $creepSeconds = Get-HermesProgressPhaseCreepSeconds -State $State
    if ($State.OutputSeen -and ($State.Phase -eq 'install-run')) {
        $creepSeconds = [int][Math]::Max(900, [Math]::Floor($creepSeconds * 0.75))
    }

    $creepTarget = [int]$band.Base + [Math]::Min($span - 1, [int][Math]::Floor($phaseElapsed * $span / [double]$creepSeconds))
    Apply-HermesProgressTarget -Ui $Ui -Target $creepTarget
}

function Complete-HermesProgress {
    param(
        $State,
        $Ui
    )

    if (-not $Ui) { return }
    if ($State) {
        $State.Phase = 'complete'
    }
    Apply-HermesProgressTarget -Ui $Ui -Target 100 -Jump
}

function Invoke-HermesProgressUiPump {
    param(
        $Context,
        $State,
        $Ui
    )

    Invoke-ToolkitDepBatchOperationUiPump -Context $Context
    Sync-HermesProgressCreep -State $State -Ui $Ui
}

function New-HermesProgressPump {
    param(
        $Context,
        $State,
        $Ui
    )

    $fnPump = Get-Command -Name Invoke-HermesProgressUiPump -CommandType Function -ErrorAction Stop
    $ctxRef = $Context
    $stateRef = $State
    $uiRef = $Ui

    return {
        & $fnPump -Context $ctxRef -State $stateRef -Ui $uiRef
    }.GetNewClosure()
}

function Write-HermesProgressLogLine {
    param(
        $Log,
        [string]$Text,
        [string]$Kind = 'text',
        [switch]$WithTimestamp,
        $ProgressState = $null,
        $Ui = $null
    )

    Write-HermesBatchLogLine -Log $Log -Text $Text -Kind $Kind -WithTimestamp:$WithTimestamp
    if ($ProgressState -and $Ui) {
        Bump-HermesProgressFromLog -State $ProgressState -Ui $Ui
    }
}
