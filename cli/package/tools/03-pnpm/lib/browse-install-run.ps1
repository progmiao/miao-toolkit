# pnpm — 浏览并安装：批量安装进度与日志视图

function Get-PnpmBrowseInstallCoreLib {
    if ($script:PnpmBrowseInstallCoreLib) {
        return $script:PnpmBrowseInstallCoreLib
    }
    if ($coreLib) {
        return [string]$coreLib
    }

    $toolRoot = Split-Path $PSScriptRoot -Parent
    $script:PnpmBrowseInstallCoreLib = (Join-Path $toolRoot '..\..\core\lib')
    return $script:PnpmBrowseInstallCoreLib
}

function Ensure-PnpmBrowseInstallShellUi {
    $coreLib = Get-PnpmBrowseInstallCoreLib

    foreach ($rel in @(
            'ui\shell\SystemToolbar.ps1'
            'ui\shell\Exit.ps1'
            'ui\shell\Footer.ps1'
            'ui\shell\DepOperationView.ps1'
            'domain\Invoke-ToolDepPackage.ps1'
        )) {
        $path = Join-Path $coreLib $rel
        $name = [IO.Path]::GetFileNameWithoutExtension($rel)
        if ($name -eq 'Invoke-ToolDepPackage') {
            if (Get-Command Get-WingetStreamLineCleanText -ErrorAction SilentlyContinue) { continue }
        }
        elseif ($name -eq 'DepOperationView') {
            if (Get-Command Draw-ToolkitDepOperationView -ErrorAction SilentlyContinue) { continue }
        }
        elseif ($name -eq 'Footer') {
            if (Get-Command Invoke-ToolkitShellRegisteredFooter -ErrorAction SilentlyContinue) { continue }
        }
        elseif ($name -eq 'Exit') {
            if (Get-Command Write-ShellExitFooter -ErrorAction SilentlyContinue) { continue }
        }
        elseif ($name -eq 'SystemToolbar') {
            if (Get-Command Set-ToolkitShellToolbarLocked -ErrorAction SilentlyContinue) { continue }
        }
        . $path
    }

    $batchOpPath = Join-Path $coreLib 'ui\shell\ToolkitDepBatchOperation.ps1'
    if (-not (Get-Command Initialize-ToolkitDepBatchOperationView -ErrorAction SilentlyContinue)) {
        . $batchOpPath
    }
}

function New-PnpmBrowseInstallLog {
    param(
        [int]$ViewportRows = 0,
        [int]$BrandInnerWidth = 0
    )

    return [pscustomobject]@{
        Lines           = [System.Collections.Generic.List[object]]::new()
        AutoScroll      = $true
        ScrollOffset    = 0
        ViewportRows    = $ViewportRows
        BrandInnerWidth = $BrandInnerWidth
    }
}

function Write-PnpmBrowseInstallLogLine {
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
        if ($Log.Lines.Count -le 0) { break }
        $Log.Lines.RemoveAt(0)
        if ($Log.ScrollOffset -gt 0) { $Log.ScrollOffset-- }
    }

    if ($Log.AutoScroll -and [int]$Log.ViewportRows -gt 0) {
        $Log.ScrollOffset = [Math]::Max(0, $Log.Lines.Count - [int]$Log.ViewportRows)
    }
}

function Run-PnpmBrowseInstallOperation {
    param(
        [hashtable]$Shell,
        [array]$Items,
        [string]$SectionTitle = ''
    )

    Ensure-PnpmBrowseInstallShellUi

    $versions = @((Ensure-StringArray -Value @($Items | ForEach-Object {
        if ($_.Version) { Normalize-PnpmVersionLabel -Version ([string]$_.Version) }
        elseif ($_.Source -and $_.Source.Version) { Normalize-PnpmVersionLabel -Version ([string]$_.Source.Version) }
        else { '' }
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })))
    $total = $versions.Count
    if ($total -le 0) {
        return $null
    }

    $baseTitle = if (-not [string]::IsNullOrWhiteSpace($SectionTitle)) {
        $SectionTitle
    }
    else {
        $script:PnpmActionSectionTitle
    }
    $toolRoot = Split-Path $PSScriptRoot -Parent
    $sectionTitle = Extend-PnpmActionSectionTitle -BaseTitle $baseTitle -ToolRoot $toolRoot `
        -SubPhaseKey 'pnpm.section.installExecute'
    $ctx = Initialize-ToolkitDepBatchOperationView -Shell $Shell -SectionTitle $sectionTitle `

    $log = $ctx.Log
    $ui = $ctx.Ui
    $RedrawView = $ctx.RedrawView
    $onExitKey = $ctx.OnExitKey
    $uiPollState = $ctx.PollState

    $successCount = 0
    $failedCount = 0
    $cancelled = $false

    try {
        & $ctx.FnDrainStaleInput
        if (Get-Command Clear-ConsoleInputBuffer -ErrorAction SilentlyContinue) {
            Clear-ConsoleInputBuffer
        }

        Set-ToolkitShellToolbarLocked -Shell $Shell -Locked $true
        Start-ToolkitDepOperationBatch -Ui $ui
        & $RedrawView

        for ($i = 0; $i -lt $total; $i++) {
            if ($cancelled) { break }

            $ver = [string]$versions[$i]
            $target = "pnpm@$ver"
            $ui.ItemSubPercent = 0
            $ui.ProgressName = $target
            $ui.ItemInFlight = $true
            $ui.ExecuteStartTick = [Environment]::TickCount
            $ui.ProgressStatus = (Get-PnpmBrowseI18n -Key 'pnpm.browse.installStatusWorking' -Vars @{
                spinner = '|'
                version = $ver
            })
            & $RedrawView

            if ($ui.ProgressCurrent -gt 0) {
                Write-PnpmBrowseInstallLogLine -Log $log -Text '' -Kind 'separator'
            }
            Write-PnpmBrowseInstallLogLine -Log $log -Text (Get-PnpmBrowseI18n -Key 'pnpm.browse.installLogStart' -Vars @{
                version = $ver
            }) -Kind 'heading' -WithTimestamp

            $outputLines = [System.Collections.Generic.List[string]]::new()
            $exitCode = 1
            try {
                Ensure-VoltaPnpmFeatureEnabled
                $proc = Start-Process -FilePath 'volta' -ArgumentList @('install', "pnpm@$ver") `
                    -NoNewWindow -PassThru -Wait -RedirectStandardOutput ([IO.Path]::GetTempFileName()) `
                    -RedirectStandardError ([IO.Path]::GetTempFileName())
                $exitCode = $proc.ExitCode
            }
            catch {
                $outputLines.Add([string]$_.Exception.Message) | Out-Null
            }

            $ui.ItemInFlight = $false
            $ui.ItemSubPercent = -1

            if ($exitCode -eq 0) {
                $successCount++
                Write-PnpmBrowseInstallLogLine -Log $log -Text (Get-PnpmBrowseI18n -Key 'pnpm.browse.installLogSuccess' -Vars @{
                    version = $ver
                }) -Kind 'success' -WithTimestamp
            }
            else {
                $failedCount++
                Write-PnpmBrowseInstallLogLine -Log $log -Text (Get-PnpmBrowseI18n -Key 'pnpm.browse.installLogFailed' -Vars @{
                    version = $ver
                    code    = [string]$exitCode
                }) -Kind 'error' -WithTimestamp
            }

            $ui.ProgressCurrent = $i + 1
            & $RedrawView
        }

        if (-not $cancelled) {
            Set-ToolkitDepOperationBatchCompleteUi -Ui $ui -Intent install -TotalCount $total `
                -SuccessCount $successCount -FailedCount $failedCount -ProgressCurrent $total
        }

        return Invoke-ToolkitDepBatchOperationWaitLoop -Context $ctx
    }
    finally {
        Clear-ToolkitDepBatchOperationView -Context $ctx
    }
}

function Run-PnpmBrowseUninstallOperation {
    param(
        [hashtable]$Shell,
        [array]$Items,
        [string]$SectionTitle = ''
    )

    Ensure-PnpmBrowseInstallShellUi

    $versions = @((Ensure-StringArray -Value @($Items | ForEach-Object {
        if ($_.Version) { Normalize-PnpmVersionLabel -Version ([string]$_.Version) }
        elseif ($_.Source -and $_.Source.Version) { Normalize-PnpmVersionLabel -Version ([string]$_.Source.Version) }
        else { '' }
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })))
    $total = $versions.Count
    if ($total -le 0) {
        return $null
    }

    $baseTitle = if (-not [string]::IsNullOrWhiteSpace($SectionTitle)) {
        $SectionTitle
    }
    else {
        $script:PnpmActionSectionTitle
    }
    $toolRoot = Split-Path $PSScriptRoot -Parent
    $sectionTitle = Extend-PnpmActionSectionTitle -BaseTitle $baseTitle -ToolRoot $toolRoot `
        -SubPhaseKey 'pnpm.section.uninstallExecute'
    $ctx = Initialize-ToolkitDepBatchOperationView -Shell $Shell -SectionTitle $sectionTitle `

    $log = $ctx.Log
    $ui = $ctx.Ui
    $RedrawView = $ctx.RedrawView

    $successCount = 0
    $failedCount = 0

    try {
        Set-ToolkitShellToolbarLocked -Shell $Shell -Locked $true
        Start-ToolkitDepOperationBatch -Ui $ui
        & $RedrawView

        for ($i = 0; $i -lt $total; $i++) {
            $ver = [string]$versions[$i]
            $target = "pnpm@$ver"
            $ui.ProgressName = $target
            $ui.ItemInFlight = $true
            $ui.ProgressStatus = (Get-PnpmBrowseUninstallI18n -Key 'pnpm.uninstall.uninstallStatusWorking' -Vars @{
                spinner = '|'
                version = $ver
            })
            & $RedrawView

            Write-PnpmBrowseInstallLogLine -Log $log -Text (Get-PnpmBrowseUninstallI18n -Key 'pnpm.uninstall.logStart' -Vars @{
                version = $ver
            }) -Kind 'heading' -WithTimestamp

            Ensure-VoltaPnpmFeatureEnabled
            $stderr = (& volta uninstall "pnpm@$ver" 2>&1 | ForEach-Object { [string]$_ })
            $exitCode = $LASTEXITCODE
            $cliUnsupported = Test-VoltaPnpmUninstallExitIgnorable -ExitCode $exitCode -OutputLines $stderr

            if ($cliUnsupported) {
                Write-PnpmBrowseInstallLogLine -Log $log -Text (Get-PnpmBrowseUninstallI18n -Key 'pnpm.uninstall.logVoltaCliUnsupported' -Vars @{
                    code = [string]$exitCode
                }) -Kind 'hint' -WithTimestamp
                Write-PnpmBrowseInstallLogLine -Log $log -Text (Get-PnpmBrowseUninstallI18n -Key 'pnpm.uninstall.logCleanupStart' -Vars @{
                    version = $ver
                }) -Kind 'text' -WithTimestamp
                $removed = Remove-VoltaPnpmVersionImagePaths -Version $ver
                if ($removed -le 0) {
                    Write-PnpmBrowseInstallLogLine -Log $log -Text (Get-PnpmBrowseUninstallI18n -Key 'pnpm.uninstall.logCleanupNone' -Vars @{
                        version = $ver
                    }) -Kind 'hint'
                }
            }

            $ui.ItemInFlight = $false
            $stillListed = Test-PnpmVersionStillListed -Version $ver

            if (-not $stillListed) {
                $successCount++
                Write-PnpmBrowseInstallLogLine -Log $log -Text (Get-PnpmBrowseUninstallI18n -Key 'pnpm.uninstall.logSuccess' -Vars @{
                    version = $ver
                }) -Kind 'success' -WithTimestamp
            }
            else {
                $failedCount++
                Write-PnpmBrowseInstallLogLine -Log $log -Text (Get-PnpmBrowseUninstallI18n -Key 'pnpm.uninstall.logVerifyListed' -Vars @{
                    version = $ver
                }) -Kind 'error' -WithTimestamp
                Write-PnpmBrowseInstallLogLine -Log $log -Text (Get-PnpmBrowseUninstallI18n -Key 'pnpm.uninstall.logFailed' -Vars @{
                    version = $ver
                }) -Kind 'error'
            }

            $ui.ProgressCurrent = $i + 1
            & $RedrawView
        }

        Set-ToolkitDepOperationBatchCompleteUi -Ui $ui -Intent uninstall -TotalCount $total `
            -SuccessCount $successCount -FailedCount $failedCount -ProgressCurrent $total

        return Invoke-ToolkitDepBatchOperationWaitLoop -Context $ctx
    }
    finally {
        Clear-ToolkitDepBatchOperationView -Context $ctx
    }
}
