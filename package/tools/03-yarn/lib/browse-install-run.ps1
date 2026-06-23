# yarn — 浏览并安装：批量安装进度与日志视图

function Get-YarnBrowseInstallCoreLib {
    if ($script:YarnBrowseInstallCoreLib) {
        return $script:YarnBrowseInstallCoreLib
    }
    if ($coreLib) {
        return [string]$coreLib
    }

    $toolRoot = Split-Path $PSScriptRoot -Parent
    $script:YarnBrowseInstallCoreLib = (Join-Path $toolRoot '..\..\core\lib')
    return $script:YarnBrowseInstallCoreLib
}

function Ensure-YarnBrowseInstallShellUi {
    $coreLib = Get-YarnBrowseInstallCoreLib

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

function New-YarnBrowseInstallLog {
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

function Write-YarnBrowseInstallLogLine {
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

function Run-YarnBrowseInstallOperation {
    param(
        [hashtable]$Shell,
        [array]$Items,
        [string]$SectionTitle = ''
    )

    Ensure-YarnBrowseInstallShellUi

    $versions = @((Ensure-StringArray -Value @($Items | ForEach-Object {
        if ($_.Version) { Normalize-YarnVersionLabel -Version ([string]$_.Version) }
        elseif ($_.Source -and $_.Source.Version) { Normalize-YarnVersionLabel -Version ([string]$_.Source.Version) }
        else { '' }
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })))
    $total = $versions.Count
    if ($total -le 0) {
        return $null
    }

    $sectionTitle = if (-not [string]::IsNullOrWhiteSpace($SectionTitle)) {
        $SectionTitle
    }
    else {
        $script:YarnActionSectionTitle
    }
    $ctx = Initialize-ToolkitDepBatchOperationView -Shell $Shell -SectionTitle $sectionTitle `
        -ProgressTotal $total -ReadyStatusText (Get-YarnBrowseI18n -Key 'yarn.browse.installStatusReady')

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
            $target = "yarn@$ver"
            $ui.ItemSubPercent = 0
            $ui.ProgressName = $target
            $ui.ItemInFlight = $true
            $ui.ExecuteStartTick = [Environment]::TickCount
            $ui.ProgressStatus = (Get-YarnBrowseI18n -Key 'yarn.browse.installStatusWorking' -Vars @{
                spinner = '|'
                version = $ver
            })
            & $RedrawView

            if ($ui.ProgressCurrent -gt 0) {
                Write-YarnBrowseInstallLogLine -Log $log -Text '' -Kind 'separator'
            }
            Write-YarnBrowseInstallLogLine -Log $log -Text (Get-YarnBrowseI18n -Key 'yarn.browse.installLogStart' -Vars @{
                version = $ver
            }) -Kind 'heading' -WithTimestamp

            $outputLines = [System.Collections.Generic.List[string]]::new()
            $exitCode = 1
            try {
                $proc = Start-Process -FilePath 'volta' -ArgumentList @('install', "yarn@$ver") `
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
                Write-YarnBrowseInstallLogLine -Log $log -Text (Get-YarnBrowseI18n -Key 'yarn.browse.installLogSuccess' -Vars @{
                    version = $ver
                }) -Kind 'success' -WithTimestamp
            }
            else {
                $failedCount++
                Write-YarnBrowseInstallLogLine -Log $log -Text (Get-YarnBrowseI18n -Key 'yarn.browse.installLogFailed' -Vars @{
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

function Run-YarnBrowseUninstallOperation {
    param(
        [hashtable]$Shell,
        [array]$Items,
        [string]$SectionTitle = ''
    )

    Ensure-YarnBrowseInstallShellUi

    $versions = @((Ensure-StringArray -Value @($Items | ForEach-Object {
        if ($_.Version) { Normalize-YarnVersionLabel -Version ([string]$_.Version) }
        elseif ($_.Source -and $_.Source.Version) { Normalize-YarnVersionLabel -Version ([string]$_.Source.Version) }
        else { '' }
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })))
    $total = $versions.Count
    if ($total -le 0) {
        return $null
    }

    $sectionTitle = if (-not [string]::IsNullOrWhiteSpace($SectionTitle)) {
        $SectionTitle
    }
    else {
        $script:YarnActionSectionTitle
    }
    $ctx = Initialize-ToolkitDepBatchOperationView -Shell $Shell -SectionTitle $sectionTitle `
        -ProgressTotal $total -ReadyStatusText (Get-YarnBrowseUninstallI18n -Key 'yarn.uninstall.statusReady')

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
            $target = "yarn@$ver"
            $ui.ProgressName = $target
            $ui.ItemInFlight = $true
            $ui.ProgressStatus = (Get-YarnBrowseUninstallI18n -Key 'yarn.uninstall.uninstallStatusWorking' -Vars @{
                spinner = '|'
                version = $ver
            })
            & $RedrawView

            Write-YarnBrowseInstallLogLine -Log $log -Text (Get-YarnBrowseUninstallI18n -Key 'yarn.uninstall.logStart' -Vars @{
                version = $ver
            }) -Kind 'heading' -WithTimestamp

            $stderr = (& volta uninstall "yarn@$ver" 2>&1 | ForEach-Object { [string]$_ })
            $exitCode = $LASTEXITCODE
            $cliUnsupported = Test-VoltaYarnUninstallExitIgnorable -ExitCode $exitCode -OutputLines $stderr

            if ($cliUnsupported) {
                Write-YarnBrowseInstallLogLine -Log $log -Text (Get-YarnBrowseUninstallI18n -Key 'yarn.uninstall.logVoltaCliUnsupported' -Vars @{
                    code = [string]$exitCode
                }) -Kind 'hint' -WithTimestamp
                Write-YarnBrowseInstallLogLine -Log $log -Text (Get-YarnBrowseUninstallI18n -Key 'yarn.uninstall.logCleanupStart' -Vars @{
                    version = $ver
                }) -Kind 'text' -WithTimestamp
                $removed = Remove-VoltaYarnVersionImagePaths -Version $ver
                if ($removed -le 0) {
                    Write-YarnBrowseInstallLogLine -Log $log -Text (Get-YarnBrowseUninstallI18n -Key 'yarn.uninstall.logCleanupNone' -Vars @{
                        version = $ver
                    }) -Kind 'hint'
                }
            }

            $ui.ItemInFlight = $false
            $stillListed = Test-YarnVersionStillListed -Version $ver

            if (-not $stillListed) {
                $successCount++
                Write-YarnBrowseInstallLogLine -Log $log -Text (Get-YarnBrowseUninstallI18n -Key 'yarn.uninstall.logSuccess' -Vars @{
                    version = $ver
                }) -Kind 'success' -WithTimestamp
            }
            else {
                $failedCount++
                Write-YarnBrowseInstallLogLine -Log $log -Text (Get-YarnBrowseUninstallI18n -Key 'yarn.uninstall.logVerifyListed' -Vars @{
                    version = $ver
                }) -Kind 'error' -WithTimestamp
                Write-YarnBrowseInstallLogLine -Log $log -Text (Get-YarnBrowseUninstallI18n -Key 'yarn.uninstall.logFailed' -Vars @{
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
