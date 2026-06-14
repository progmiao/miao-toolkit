# 第三方依赖 Plan + 编排（install/update/uninstall 统一）

function Get-ToolkitDepEffectiveIntent {
    param(
        $Tool,
        [ValidateSet('install', 'update', 'uninstall')]
        [string]$Intent
    )

    if ($Intent -eq 'update' -and -not (Test-ToolDepInstalled $Tool)) {
        return 'install'
    }
    return $Intent
}

function Test-ToolDepPackageNeedsUpgrade {
    param(
        $Package,
        [string]$EffectiveVersion,
        [hashtable]$ProbeCache,
        [switch]$SkipRemoteProbe
    )

    if ([string]::IsNullOrWhiteSpace($EffectiveVersion)) { return $false }

    $packageId = $null
    if ($Package.install -and $Package.install.packageId) {
        $packageId = [string]$Package.install.packageId
    }

    if (Test-DependencyVersionPolicyIsLatest -Dependency $Package) {
        if ($SkipRemoteProbe) { return $false }
        if ($packageId) {
            $cacheKey = "upgrade:$packageId|$EffectiveVersion"
            if ($ProbeCache.ContainsKey($cacheKey)) {
                return [bool]$ProbeCache[$cacheKey]
            }
            $available = Test-WingetPackageUpdateAvailable -PackageId $packageId -InstalledVersion $EffectiveVersion
            $ProbeCache[$cacheKey] = $available
            return $available
        }
        return $false
    }

    $target = (Get-DependencyVersionPolicy -Dependency $Package).Trim()
    return ((Normalize-Semver $EffectiveVersion) -ne (Normalize-Semver $target))
}

function Resolve-ToolDepPackageStatus {
    param(
        $Tool,
        $Package,
        [hashtable]$ProbeCache = $null,
        [switch]$SkipRemoteUpgradeProbe,
        [switch]$PreferLocalProbe
    )

    if (-not $ProbeCache) { $ProbeCache = @{} }

    $depId = Get-DependencyRecordId -Dependency $Package
    $depName = if ($Package.name) { [string]$Package.name } else { $depId }
    $packageId = if ($Package.install -and $Package.install.packageId) { [string]$Package.install.packageId } else { '' }
    $checkCommand = if ($Package.checkCommand) { [string]$Package.checkCommand } else { '' }
    $policy = Get-DependencyVersionPolicy -Dependency $Package

    $recorded = Get-ToolDepRecordedVersion -ToolId ([string]$Tool.id) -DependencyId $depId
    $commandAvailable = Test-ToolDepCommandAvailable -CheckCommand $checkCommand

    $actualVersion = $null
    if ($checkCommand -and $commandAvailable) {
        $cmdCacheKey = "cmd:$checkCommand"
        if ($ProbeCache.ContainsKey($cmdCacheKey)) {
            $actualVersion = [string]$ProbeCache[$cmdCacheKey]
        }
        else {
            $actualVersion = Resolve-ToolDepCheckCommandVersion -CheckCommand $checkCommand
            $ProbeCache[$cmdCacheKey] = $actualVersion
        }
    }

    $wingetVersion = $null
    if (-not $PreferLocalProbe -and $packageId) {
        $cacheKey = "winget:$packageId"
        if ($ProbeCache.ContainsKey($cacheKey)) {
            $wingetVersion = [string]$ProbeCache[$cacheKey]
        }
        else {
            $wingetVersion = Get-WingetPackageInstalledVersion -PackageId $packageId
            $ProbeCache[$cacheKey] = $wingetVersion
        }
        if (-not [string]::IsNullOrWhiteSpace($wingetVersion)) {
            $actualVersion = $wingetVersion
        }
    }

    $versionDrift = $false
    $effectiveVersion = $recorded
    if (-not [string]::IsNullOrWhiteSpace($actualVersion)) {
        if (-not [string]::IsNullOrWhiteSpace($recorded) -and $recorded -ne $actualVersion) {
            $versionDrift = $true
        }
        $effectiveVersion = $actualVersion
    }

    $hasRecord = -not [string]::IsNullOrWhiteSpace($recorded)
    $wingetInstalled = -not [string]::IsNullOrWhiteSpace($wingetVersion)
    $needsUpgrade = $false

    if ($commandAvailable -or $wingetInstalled) {
        $needsUpgrade = Test-ToolDepPackageNeedsUpgrade -Package $Package `
            -EffectiveVersion $effectiveVersion -ProbeCache $ProbeCache `
            -SkipRemoteUpgradeProbe:$SkipRemoteUpgradeProbe
    }

    $action = 'Skip'
    if (-not $hasRecord -and -not $commandAvailable -and -not $wingetInstalled) {
        $action = 'Install'
    }
    elseif (-not $hasRecord -and ($commandAvailable -or $wingetInstalled)) {
        if ($needsUpgrade) { $action = 'Upgrade' }
        else { $action = 'Reconcile' }
    }
    elseif ($hasRecord -and -not $commandAvailable) {
        $action = 'Repair'
    }
    elseif ($needsUpgrade) {
        $action = 'Upgrade'
    }
    elseif ($versionDrift) {
        $action = 'Reconcile'
    }

    return [pscustomobject]@{
        DependencyId      = $depId
        Name              = $depName
        PackageId         = $packageId
        Action            = $action
        RecordedVersion   = $recorded
        ActualVersion     = $actualVersion
        EffectiveVersion  = $effectiveVersion
        VersionDrift      = $versionDrift
        Policy            = $policy
        CheckCommand      = $checkCommand
        CommandAvailable  = $commandAvailable
        Package           = $Package
    }
}

function Resolve-ToolDepUninstallPackageStatus {
    param(
        $Tool,
        $Package,
        [hashtable]$ProbeCache = $null
    )

    if (-not $ProbeCache) { $ProbeCache = @{} }

    Update-ToolDepSessionPath

    $depId = Get-DependencyRecordId -Dependency $Package
    $depName = if ($Package.name) { [string]$Package.name } else { $depId }
    $packageId = if ($Package.install -and $Package.install.packageId) { [string]$Package.install.packageId } else { '' }
    $checkCommand = if ($Package.checkCommand) { [string]$Package.checkCommand } else { '' }

    $commandAvailable = Test-ToolDepCommandAvailable -CheckCommand $checkCommand
    $actualVersion = $null
    if ($packageId) {
        $cacheKey = "winget:$packageId"
        if ($ProbeCache.ContainsKey($cacheKey)) {
            $actualVersion = [string]$ProbeCache[$cacheKey]
        }
        else {
            $actualVersion = Get-WingetPackageInstalledVersion -PackageId $packageId
            $ProbeCache[$cacheKey] = $actualVersion
        }
    }

    $wingetInstalled = -not [string]::IsNullOrWhiteSpace($actualVersion)
    $action = if ($commandAvailable -or $wingetInstalled) { 'Uninstall' } else { 'Skip' }

    return [pscustomobject]@{
        DependencyId      = $depId
        Name              = $depName
        PackageId         = $packageId
        Action            = $action
        RecordedVersion   = (Get-ToolDepRecordedVersion -ToolId ([string]$Tool.id) -DependencyId $depId)
        ActualVersion     = $actualVersion
        EffectiveVersion  = $actualVersion
        VersionDrift      = $false
        Policy            = (Get-DependencyVersionPolicy -Dependency $Package)
        CheckCommand      = $checkCommand
        CommandAvailable  = $commandAvailable
        Package           = $Package
    }
}

function Test-ToolDepPlanItemExecutes {
    param(
        $PlanItem,
        [ValidateSet('install', 'update', 'uninstall')]
        [string]$Intent
    )

    $action = [string]$PlanItem.Status.Action
    switch ($Intent) {
        'install' {
            return ($action -in @('Install', 'Upgrade', 'Repair', 'Reconcile'))
        }
        'update' {
            return ($action -in @('Install', 'Upgrade', 'Repair', 'Reconcile'))
        }
        'uninstall' {
            return ($action -eq 'Uninstall')
        }
    }
    return $false
}

function Build-ToolDepSyncPlan {
    param(
        $Tool,
        [ValidateSet('install', 'update', 'uninstall')]
        [string]$Intent
    )

    $effectiveIntent = Get-ToolkitDepEffectiveIntent -Tool $Tool -Intent $Intent
    $probeCache = @{}
    $items = @()

    foreach ($pkg in @(Get-ToolDependencyPackages -Tool $Tool)) {
        $status = if ($Intent -eq 'uninstall') {
            Resolve-ToolDepUninstallPackageStatus -Tool $Tool -Package $pkg -ProbeCache $probeCache
        }
        else {
            Resolve-ToolDepPackageStatus -Tool $Tool -Package $pkg -ProbeCache $probeCache
        }

        $items += [pscustomobject]@{
            Status         = $status
            Intent         = $effectiveIntent
            ShouldExecute  = (Test-ToolDepPlanItemExecutes -PlanItem @{ Status = $status } -Intent $effectiveIntent)
            ExecuteAction  = if ($status.Action -in @('Install', 'Upgrade', 'Repair', 'Reconcile', 'Uninstall')) {
                $status.Action
            }
            else { $null }
        }
    }

    return [pscustomobject]@{
        Tool           = $Tool
        Intent         = $Intent
        EffectiveIntent = $effectiveIntent
        Items          = $items
        ProbeCache     = $probeCache
    }
}

function Get-ToolDepPlanSummaryOutcome {
    param($Plan)

    $executeCount = @($Plan.Items | Where-Object { $_.ShouldExecute }).Count
    if ($executeCount -gt 0) { return 'hasWork' }

    if ($Plan.Intent -eq 'update') { return 'allLatest' }
    if ($Plan.Intent -eq 'install') { return 'nothingToDo' }
    if ($Plan.Intent -eq 'uninstall') { return 'nothingToDo' }
    return 'nothingToDo'
}

function Complete-ToolkitDepUninstallRecord {
    param(
        $Tool,
        $Runner
    )

    if ($Runner -and $Runner.State.Cancelled) { return }
    if ($Runner -and $null -ne $Runner.State.FailedCount -and [int]$Runner.State.FailedCount -gt 0) { return }
    Remove-ToolDepInstalled -ToolId ([string]$Tool.id)
}

function Get-ToolkitDepOperationSummaryKey {
    param(
        $Plan,
        [string]$Intent,
        $Runner
    )

    if ($Runner -and $null -ne $Runner.State.FailedCount -and [int]$Runner.State.FailedCount -gt 0) {
        return 'page.depOperation.summaryFailed'
    }
    if ($Runner -and $Runner.State.Failed) {
        return 'page.depOperation.summaryFailed'
    }

    $outcome = Get-ToolDepPlanSummaryOutcome -Plan $Plan
    if ($Intent -eq 'uninstall') {
        if ($outcome -eq 'nothingToDo') {
            return 'page.depOperation.summaryUninstallNothing'
        }
        return 'page.depOperation.summaryUninstallComplete'
    }

    switch ($outcome) {
        'allLatest' { return 'page.depOperation.summaryAllLatest' }
        'nothingToDo' { return 'page.depOperation.summaryNothingToDo' }
        default { return 'page.depOperation.summaryComplete' }
    }
}

function Sync-ToolDepInstalledState {
    param($Tool)

    if (-not (Test-ToolHasExternalDeps $Tool)) { return $true }

    $versions = @{}
    foreach ($dep in @(Get-ToolDependencyPackages -Tool $Tool)) {
        $depId = Get-DependencyRecordId -Dependency $dep
        $recorded = Get-ToolDepRecordedVersion -ToolId ([string]$Tool.id) -DependencyId $depId
        if (-not [string]::IsNullOrWhiteSpace($recorded)) { continue }

        $version = Get-ToolDepPackageRecordableVersion -Package $dep
        if (-not [string]::IsNullOrWhiteSpace($version)) {
            $versions[$depId] = $version
        }
    }

    if ($versions.Count -gt 0) {
        Set-ToolDepInstalled -ToolId ([string]$Tool.id) -DependencyVersions $versions
    }

    return (Test-ToolDepInstalled $Tool)
}

function Get-ToolSectionTitle {
    param($Tool)

    $unrecognized = Get-I18n -Key 'common.unrecognized'
    if ($Tool.name -and [string]$Tool.name -ne $unrecognized) {
        return [string]$Tool.name
    }
    if ($Tool.command) { return [string]$Tool.command }
    return [string]$Tool.id
}

function Start-ToolkitDepOperation {
    param(
        $Tool,
        [ValidateSet('install', 'update', 'uninstall')]
        [string]$Intent,
        [hashtable]$Shell = $null,
        [string]$SectionTitle = '',
        [switch]$AutoContinue,
        $SharedLog = $null
    )

    if (-not (Test-ToolHasExternalDeps $Tool)) { return $true }

    if (-not (Test-WingetCliAvailable)) {
        if ($Shell) {
            $title = if ($SectionTitle) { $SectionTitle } else { [string]$Tool.id }
            $null = Invoke-ToolkitDepOperationView -Shell $Shell -SectionTitle $title -Tool $Tool `
                -Intent $Intent -PreflightErrorKey 'page.depOperation.wingetMissing'
            return $false
        }
        Write-Host (Get-I18n -Key 'page.depOperation.wingetMissing') -ForegroundColor Red
        return $false
    }

    if ($Shell) {
        $title = if ($SectionTitle) { $SectionTitle } else { (Get-ToolSectionTitle -Tool $Tool) }
        return Invoke-ToolkitDepOperationView -Shell $Shell -SectionTitle $title -Tool $Tool `
            -Intent $Intent -AutoContinue:$AutoContinue -SharedLog $SharedLog
    }

    return Invoke-ToolkitDepOperationConsole -Tool $Tool -Intent $Intent
}

function Start-ToolkitDepBatchOperation {
    param(
        [array]$Tools,
        [hashtable]$Shell,
        [string]$SectionTitle = '',
        [ValidateSet('install', 'update')]
        [string]$Intent = 'install'
    )

    if ($Tools.Count -eq 0) { return @{ Success = $true; FailedToolIds = @() } }

    $failed = @()
    $batchLog = New-ToolkitDepOperationLog
    $toolList = @($Tools)
    $toolTotal = $toolList.Count
    $toolIndex = 0
    foreach ($tool in $toolList) {
        $toolIndex++
        if ($toolIndex -gt 1) {
            Add-ToolkitDepLogSeparator -Log $batchLog
        }
        $title = if ($SectionTitle) { $SectionTitle } else { (Get-ToolSectionTitle -Tool $tool) }
        $isLast = ($toolIndex -eq $toolTotal)
        $ok = Start-ToolkitDepOperation -Tool $tool -Intent $Intent -Shell $Shell `
            -SectionTitle $title -AutoContinue:(-not $isLast) -SharedLog $batchLog
        if (Test-ShellNavMarker $ok) {
            return $ok
        }
        if (-not $ok) {
            $failed += [string]$tool.command
            if ($Shell.ExitMode) { break }
        }
    }

    return @{
        Success       = ($failed.Count -eq 0)
        FailedToolIds = @($failed)
    }
}

function Invoke-ToolkitDepOperationConsole {
    param(
        $Tool,
        [ValidateSet('install', 'update', 'uninstall')]
        [string]$Intent
    )

    $plan = Build-ToolDepSyncPlan -Tool $Tool -Intent $Intent
    $log = New-ToolkitDepOperationLog
    $runner = New-ToolkitDepOperationRunner -Tool $Tool -Plan $plan -Log $log

    $itemTotal = @($plan.Items).Count
    $itemIndex = 0
    foreach ($item in @($plan.Items)) {
        $itemIndex++
        if ($itemIndex -gt 1) {
            Add-ToolkitDepLogSeparator -Log $log
        }
        Add-ToolkitDepLogSection -Log $log -Title ([string]$item.Status.Name) `
            -Index $itemIndex -Total $itemTotal -Level 'package'
        & $runner.ProcessItem $item
        if ($runner.State.Cancelled) { break }
    }

    $runner.State.Failed = ([int]$runner.State.FailedCount -gt 0)

    if ($Intent -eq 'uninstall') {
        if (Test-ToolkitDepRunnerSuccess -Runner $runner) {
            Complete-ToolkitDepUninstallRecord -Tool $Tool -Runner $runner
        }
    }
    elseif ([int]$runner.State.SuccessCount -gt 0 -and ($Intent -in @('install', 'update'))) {
        Sync-ToolDepInstalledState -Tool $Tool | Out-Null
    }

    if (-not $runner.State.Cancelled) {
        $batchCounts = Format-ToolkitDepBatchCountsText -Intent $Intent `
            -TotalCount $itemTotal -SuccessCount ([int]$runner.State.SuccessCount) `
            -FailedCount ([int]$runner.State.FailedCount)
        if (-not [string]::IsNullOrWhiteSpace($batchCounts)) {
            Write-Host $batchCounts
        }
    }

    foreach ($line in @($log.Lines)) {
        $color = if ($line.Color) { $line.Color } else { [System.ConsoleColor]::Gray }
        if ($line.Kind -eq 'error') { $color = [System.ConsoleColor]::Red }
        elseif ($line.Kind -eq 'success') { $color = [System.ConsoleColor]::Green }
        elseif ($line.Kind -eq 'heading') { $color = [System.ConsoleColor]::Cyan }
        elseif ($line.Kind -eq 'section') { $color = [System.ConsoleColor]::Cyan }
        elseif ($line.Kind -in @('separator', 'hint')) { $color = [System.ConsoleColor]::DarkGray }
        $text = Format-ToolkitDepLogLineText -Line $line
        Write-Host $text -ForegroundColor $color
    }

    return (Test-ToolkitDepRunnerSuccess -Runner $runner)
}
