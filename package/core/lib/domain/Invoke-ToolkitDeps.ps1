function Get-DependencyVersionPolicy {
    param($Dependency)

    if ($Dependency.version) {
        return [string]$Dependency.version
    }
    if ($Dependency.updatePolicy) {
        return [string]$Dependency.updatePolicy
    }
    return 'latest'
}

function Test-DependencyVersionPolicyIsLatest {
    param($Dependency)

    $policy = (Get-DependencyVersionPolicy -Dependency $Dependency).Trim().ToLowerInvariant()
    return ($policy -eq 'latest')
}

function Test-ToolDependencyNeedsUpgrade {
    param($Tool)

    if (-not (Test-ToolHasExternalDeps $Tool)) { return $false }
    if (-not (Test-ToolDepInstalled $Tool)) { return $false }

    $probeCache = @{}
    foreach ($dep in @(Get-ToolDependencyPackages -Tool $Tool)) {
        $status = Resolve-ToolDepPackageStatus -Tool $Tool -Package $dep -ProbeCache $probeCache
        if ($status.Action -eq 'Upgrade') { return $true }
    }

    return $false
}

function Test-ToolDependencyNeedsImmediateLocalAttention {
    param($Tool)

    if (-not (Test-ToolHasExternalDeps $Tool)) { return $false }
    if (-not (Test-ToolDepInstalled $Tool)) { return $false }

    foreach ($dep in @(Get-ToolDependencyPackages -Tool $Tool)) {
        $depId = Get-DependencyRecordId -Dependency $dep
        $recorded = Get-ToolDepRecordedVersion -ToolId ([string]$Tool.id) -DependencyId $depId
        if ([string]::IsNullOrWhiteSpace($recorded)) { continue }

        $checkCommand = if ($dep.checkCommand) { [string]$dep.checkCommand } else { '' }
        if ($checkCommand -and -not (Test-ToolDepCommandAvailable -CheckCommand $checkCommand)) {
            return $true
        }

        if (-not (Test-DependencyVersionPolicyIsLatest -Dependency $dep)) {
            $target = (Get-DependencyVersionPolicy -Dependency $dep).Trim()
            if ((Normalize-Semver $recorded) -ne (Normalize-Semver $target)) {
                return $true
            }
        }
    }

    return $false
}

function Test-ToolDependencyNeedsLocalAttention {
    param($Tool)

    if (-not (Test-ToolHasExternalDeps $Tool)) { return $false }
    if (-not (Test-ToolDepInstalled $Tool)) { return $false }
    if (Test-ToolDependencyNeedsImmediateLocalAttention -Tool $Tool) { return $true }

    $probeCache = @{}
    foreach ($dep in @(Get-ToolDependencyPackages -Tool $Tool)) {
        $status = Resolve-ToolDepPackageStatus -Tool $Tool -Package $dep -ProbeCache $probeCache `
            -SkipRemoteUpgradeProbe -PreferLocalProbe
        if ($status.Action -in @('Install', 'Upgrade', 'Repair', 'Reconcile')) {
            return $true
        }
    }

    return $false
}

function Test-ToolDependencyShouldShowUpdateMenu {
    param($Tool)

    if (-not (Test-ToolDepInstalled $Tool)) { return $false }
    if (Test-ToolDependencyNeedsLocalAttention -Tool $Tool) { return $true }
    return (Test-ToolDependencyNeedsUpgrade -Tool $Tool)
}

function Stop-ToolDependencyUpgradeProbeWorker {
    param($Probe)

    if (-not $Probe) { return }

    if ($Probe.Job) {
        Stop-Job $Probe.Job -ErrorAction SilentlyContinue
        Remove-Job $Probe.Job -Force -ErrorAction SilentlyContinue
    }

    if ($Probe.PowerShell) {
        try {
            if ($Probe.Handle -and -not $Probe.Handle.IsCompleted) {
                $Probe.PowerShell.Stop()
            }
        }
        catch {}
        try { $Probe.PowerShell.Dispose() } catch {}
    }

    if ($Probe.Runspace) {
        try { $Probe.Runspace.Close() } catch {}
        try { $Probe.Runspace.Dispose() } catch {}
    }
}

function Get-ToolsWithExternalDeps {
    param(
        [array]$Tools,
        [string[]]$ToolIds = @()
    )

    $filtered = @($Tools | Where-Object { Test-ToolHasExternalDeps $_ })
    if ($ToolIds.Count -eq 0) {
        return @($filtered | Sort-Object { [int]$_.no })
    }

    $result = @()
    foreach ($id in $ToolIds) {
        $tool = $filtered | Where-Object { $_.command -eq $id -or $_.id -eq $id } | Select-Object -First 1
        if (-not $tool) {
            Write-Warning (Get-I18n -Key 'page.install.unknownTool' -Vars @{ toolId = $id })
            continue
        }
        $result += $tool
    }
    return @($result | Sort-Object { [int]$_.no })
}

function Invoke-ToolUninstall {
    param(
        $Tool,
        [hashtable]$Shell = $null,
        [string]$SectionTitle = ''
    )

    if (-not (Test-ToolHasExternalDeps $Tool)) {
        if (-not $Shell) {
            Write-Host (Get-I18n -Key 'page.install.noExternalDeps' -Vars @{ toolId = $Tool.id }) -ForegroundColor DarkGray
        }
        return $true
    }

    return Start-ToolkitDepOperation -Tool $Tool -Intent uninstall -Shell $Shell `
        -SectionTitle $SectionTitle
}

function Resolve-MiaoToolboxDepArgs {
    param([string[]]$Rest)

    if ($Rest.Count -eq 0) {
        return @{
            Mode      = 'toolbox'
            ToolIds   = @()
            SelectAll = $false
        }
    }

    if ($Rest[0] -eq 'all') {
        return @{
            Mode      = 'toolbox'
            ToolIds   = @()
            SelectAll = $true
        }
    }

    return @{
        Mode      = 'tool'
        ToolIds   = @($Rest)
        SelectAll = $false
    }
}

function Start-ToolkitToolDepSession {
    param(
        [array]$Tools,
        [string[]]$ToolIds,
        [ValidateSet('install', 'update', 'uninstall')]
        [string]$Intent
    )

    if ($ToolIds.Count -eq 0) {
        Write-Host (Get-I18n -Key 'page.toolDeps.toolCommandNeedsToolId') -ForegroundColor Red
        return 1
    }

    $tool = Get-Tool $ToolIds[0] -Tools $Tools
    if (-not $tool) {
        Write-Host (Get-I18n -Key 'message.unknownTool' -Vars @{ toolId = $ToolIds[0] }) -ForegroundColor Red
        return 1
    }

    if (-not (Test-ToolHasExternalDeps $tool)) {
        Write-Host (Get-I18n -Key 'page.install.noExternalDeps' -Vars @{ toolId = $tool.id }) -ForegroundColor DarkGray
        return 1
    }

    Import-MiaoModule -Name ToolDeps
    return (Start-ToolkitShellSession -Tools $Tools -InitialView ToolDep `
        -CurrentTool $tool -CurrentToolId $ToolIds[0] -ToolDepIntent $Intent)
}

function Invoke-ToolkitInstallDeps {
    param(
        [array]$Tools,
        [string[]]$Rest = @()
    )

    $resolved = Resolve-MiaoToolboxDepArgs -Rest $Rest
    Import-MiaoModule -Name Install

    if ($resolved.Mode -eq 'tool') {
        return (Start-ToolkitToolDepSession -Tools $Tools -ToolIds $resolved.ToolIds -Intent install)
    }

    return (Start-ToolboxDepInstallSession -Tools $Tools -SelectAll:$resolved.SelectAll)
}

function Invoke-ToolkitUpdateDeps {
    param(
        [array]$Tools,
        [string[]]$Rest = @()
    )

    $resolved = Resolve-MiaoToolboxDepArgs -Rest $Rest
    Import-MiaoModule -Name Install

    if ($resolved.Mode -eq 'tool') {
        return (Start-ToolkitToolDepSession -Tools $Tools -ToolIds $resolved.ToolIds -Intent update)
    }

    return (Start-ToolboxDepUpdateSession -Tools $Tools -SelectAll:$resolved.SelectAll)
}

function Invoke-ToolkitUninstallDeps {
    param(
        [array]$Tools,
        [string[]]$Rest = @()
    )

    $resolved = Resolve-MiaoToolboxDepArgs -Rest $Rest
    Import-MiaoModule -Name Install

    if ($resolved.Mode -eq 'tool') {
        return (Start-ToolkitToolDepSession -Tools $Tools -ToolIds $resolved.ToolIds -Intent uninstall)
    }

    return (Start-ToolboxDepUninstallSession -Tools $Tools -SelectAll:$resolved.SelectAll)
}

function Test-ToolDependencyMenuAction {
    param($Action)

    return ($Action -and $Action._kind -eq 'toolDeps')
}

function Get-ToolDependencyProbeKey {
    param([string]$ToolId)

    return "ToolDepUpgradeProbe_$ToolId"
}

function Start-ToolDependencyUpgradeProbe {
    param(
        $Tool,
        [hashtable]$Shell
    )

    if (-not $Shell) { return }
    if (-not (Test-ToolHasExternalDeps $Tool)) { return }
    if (-not (Test-ToolDepInstalled $Tool)) { return }

    $key = Get-ToolDependencyProbeKey -ToolId ([string]$Tool.id)
    if ($Shell.ContainsKey($key)) { return }

    $toolRoot = [string]$Tool._root
    $binDir = (Resolve-Path (Join-Path $toolRoot '..\..\bin')).Path
    $libDir = (Resolve-Path (Join-Path $toolRoot '..\..\core\lib')).Path

    $probeScript = {
        param($ProbeToolRoot, $ProbeBinDir, $ProbeLibDir)

        $ErrorActionPreference = 'Stop'
        . (Join-Path $ProbeLibDir 'bootstrap\Load-Core.ps1') -LibDirectory $ProbeLibDir
        Initialize-Paths -BinDirectory $ProbeBinDir
        . (Join-Path $ProbeLibDir 'domain\Check-Update.ps1')
        . (Join-Path $ProbeLibDir 'domain\Ensure-ToolDeps.ps1')
        . (Join-Path $ProbeLibDir 'config\Deps-State.ps1')
        . (Join-Path $ProbeLibDir 'domain\Invoke-ToolDepPackage.ps1')
        . (Join-Path $ProbeLibDir 'domain\Invoke-ToolkitDepOperation.ps1')
        . (Join-Path $ProbeLibDir 'domain\Invoke-ToolkitDeps.ps1')

        $probeTool = Get-ToolFromDirectory -ToolRoot $ProbeToolRoot
        return (Test-ToolDependencyShouldShowUpdateMenu -Tool $probeTool)
    }

    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.Open()
    $powershell = [powershell]::Create()
    $powershell.Runspace = $runspace
    [void]$powershell.AddScript($probeScript).AddArgument($toolRoot).AddArgument($binDir).AddArgument($libDir)
    $handle = $powershell.BeginInvoke()

    $Shell[$key] = @{
        Runspace   = $runspace
        PowerShell = $powershell
        Handle     = $handle
        Done       = $false
        Available  = $false
    }
}

function Sync-ToolDependencyUpgradeProbe {
    param(
        $Tool,
        [hashtable]$Shell
    )

    if (-not $Shell) { return $false }

    $key = Get-ToolDependencyProbeKey -ToolId ([string]$Tool.id)
    if (-not $Shell.ContainsKey($key)) { return $false }

    $probe = $Shell[$key]
    if ($probe.Done) { return [bool]$probe.Available }

    if ($probe.Job) {
        if ($probe.Job.State -eq 'Running') { return [bool]$probe.Available }

        $available = $false
        if ($probe.Job.State -eq 'Completed') {
            $result = Receive-Job $probe.Job -ErrorAction SilentlyContinue
            if ($result) { $available = [bool]$result }
        }

        Remove-Job $probe.Job -Force -ErrorAction SilentlyContinue
        $Shell[$key] = @{
            Done      = $true
            Available = $available
        }
        return $available
    }

    $handle = $probe.Handle
    $powershell = $probe.PowerShell
    if (-not $handle -or -not $powershell) { return $false }
    if (-not $handle.IsCompleted) { return [bool]$probe.Available }

    $available = $false
    try {
        $result = $powershell.EndInvoke($handle)
        if ($result) { $available = [bool]$result }
    }
    catch {}
    finally {
        Stop-ToolDependencyUpgradeProbeWorker -Probe $probe
    }

    $Shell[$key] = @{
        Done      = $true
        Available = $available
    }
    return $available
}

function Reset-ToolDependencyUpgradeProbe {
    param(
        $Tool,
        [hashtable]$Shell
    )

    if (-not $Shell -or -not $Tool) { return }

    $key = Get-ToolDependencyProbeKey -ToolId ([string]$Tool.id)
    if (-not $Shell.ContainsKey($key)) { return }

    Stop-ToolDependencyUpgradeProbeWorker -Probe $Shell[$key]
    $Shell.Remove($key)
}

function Update-ToolDependencyMenuProbe {
    param(
        $Tool,
        [hashtable]$Shell,
        [ref]$UpdateMenuAvailable
    )

    $previous = [bool]$UpdateMenuAvailable.Value
    $UpdateMenuAvailable.Value = $false

    if (-not (Test-ToolHasExternalDeps $Tool)) {
        Reset-ToolDependencyUpgradeProbe -Tool $Tool -Shell $Shell
        return ($previous -ne $false)
    }

    if (-not (Test-ToolDepInstalled $Tool)) {
        Reset-ToolDependencyUpgradeProbe -Tool $Tool -Shell $Shell
        return ($previous -ne $false)
    }

    if (Test-ToolDependencyNeedsImmediateLocalAttention -Tool $Tool) {
        $UpdateMenuAvailable.Value = $true
    }

    Start-ToolDependencyUpgradeProbe -Tool $Tool -Shell $Shell
    if (Sync-ToolDependencyUpgradeProbe -Tool $Tool -Shell $Shell) {
        $UpdateMenuAvailable.Value = $true
    }

    return ($UpdateMenuAvailable.Value -ne $previous)
}

function Get-ToolDependencyMenuDescriptionKey {
    param(
        $Tool,
        [ValidateSet('install', 'update', 'uninstall')]
        [string]$Kind
    )

    $summaryKey = switch ($Kind) {
        'install' { 'page.toolDeps.installSummary' }
        'update' { 'page.toolDeps.updateSummary' }
        'uninstall' { 'page.toolDeps.uninstallSummary' }
    }

    $menus = Get-ToolDependencyMenus -Tool $Tool
    if (-not $menus) {
        return $summaryKey
    }

    $depsEntry = $menus.$Kind
    if ($null -eq $depsEntry) {
        return $summaryKey
    }

    $i18nKey = [string]$depsEntry
    if ([string]::IsNullOrWhiteSpace($i18nKey)) {
        return $summaryKey
    }

    if (-not [string]::IsNullOrWhiteSpace($Tool._root)) {
        $resolved = Get-ToolI18nRaw -ToolRoot $Tool._root -Key $i18nKey
        if (-not [string]::IsNullOrWhiteSpace($resolved)) {
            return $i18nKey
        }
    }

    return $summaryKey
}

function Get-ToolDependencyMenuI18nKeys {
    param(
        $Tool,
        [ValidateSet('install', 'update', 'uninstall')]
        [string]$Kind
    )

    $nameKey = switch ($Kind) {
        'install' { 'page.toolDeps.installLabel' }
        'update' { 'page.toolDeps.updateLabel' }
        'uninstall' { 'page.toolDeps.uninstallLabel' }
    }

    return @{
        nameKey        = $nameKey
        descriptionKey = (Get-ToolDependencyMenuDescriptionKey -Tool $Tool -Kind $Kind)
    }
}

function Resolve-ToolMenuI18nText {
    param(
        [string]$ToolRoot,
        [string]$Key
    )

    if ([string]::IsNullOrWhiteSpace($Key)) { return '' }

    if ($Key.StartsWith('page.')) {
        return Get-I18n -Key $Key
    }

    $value = Get-ToolI18nRaw -ToolRoot $ToolRoot -Key $Key
    if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }

    $coreValue = Get-I18nRaw -Key $Key
    if (-not [string]::IsNullOrWhiteSpace($coreValue)) { return $coreValue }

    return $Key
}

function Get-ToolDependencyMenuCommandDisplay {
    return '---'
}

function Get-ToolMenuItemCommand {
    param($Action)

    if (Test-ToolDependencyMenuAction $Action) {
        return Get-ToolDependencyMenuCommandDisplay
    }

    return Get-ShellListItemCommand $Action
}

function Resolve-ToolMenuActionName {
    param(
        [string]$ToolRoot,
        $Action
    )

    if (Test-ToolDependencyMenuAction $Action) {
        return Resolve-ToolMenuI18nText -ToolRoot $ToolRoot -Key ([string]$Action.name)
    }

    return Resolve-ToolI18nLabel -ToolRoot $ToolRoot -Key ([string]$Action.name) `
        -Fallback (Get-ShellListItemCommand $Action)
}

function Resolve-ToolMenuActionDescription {
    param(
        [string]$ToolRoot,
        $Action
    )

    if ([string]::IsNullOrWhiteSpace([string]$Action.description)) {
        if (-not $Action.enabled -and $Action.name) {
            return '[即将推出]'
        }
        return ''
    }

    if (Test-ToolDependencyMenuAction $Action) {
        return Resolve-ToolMenuI18nText -ToolRoot $ToolRoot -Key ([string]$Action.description)
    }

    $description = Get-ToolI18nRaw -ToolRoot $ToolRoot -Key ([string]$Action.description)
    if ($null -eq $description) { $description = '' }
    if (-not $Action.enabled -and $Action.name) {
        return "$description [即将推出]".Trim()
    }
    return $description
}

function ConvertTo-ToolMenuListRows {
    param(
        [string]$ToolRoot,
        [array]$MenuItems
    )

    return ConvertTo-ShellListRows -Items $MenuItems -KeepSource -MapCells {
        param($Action, [int]$Index)
        @(
            (Get-ToolMenuItemCommand $Action)
            (Resolve-ToolMenuActionName -ToolRoot $ToolRoot -Action $Action)
            (Resolve-ToolMenuActionDescription -ToolRoot $ToolRoot -Action $Action)
        )
    } -GetNumber {
        param($Action, [int]$Index)
        if ($null -ne $Action.PSObject.Properties['no'] -and [int]$Action.no -gt 0) {
            return [int]$Action.no
        }
        return $Index + 1
    } -GetEnabled {
        param($Action, [int]$Index)
        if (Test-ToolDependencyMenuAction $Action) { return $true }
        return [bool]$Action.enabled
    }
}

function New-ToolDependencyMenuAction {
    param(
        $Tool,
        [ValidateSet('install', 'update', 'uninstall')]
        [string]$Kind
    )

    $keys = Get-ToolDependencyMenuI18nKeys -Tool $Tool -Kind $Kind
    return [pscustomobject]@{
        _kind       = 'toolDeps'
        command     = $Kind
        name        = $keys.nameKey
        description = $keys.descriptionKey
        enabled     = $true
    }
}

function Get-ToolDependencyInstallMenuAction {
    param($Tool)

    return New-ToolDependencyMenuAction -Tool $Tool -Kind install
}

function Get-ToolDependencyUpdateMenuAction {
    param($Tool)

    return New-ToolDependencyMenuAction -Tool $Tool -Kind update
}

function Get-ToolDependencyUninstallMenuAction {
    param($Tool)

    return New-ToolDependencyMenuAction -Tool $Tool -Kind uninstall
}

function Get-ToolMenuItems {
    param(
        [array]$BusinessActions,
        $Tool,
        [switch]$DependencyUpdateAvailable
    )

    if (-not (Test-ToolHasExternalDeps $Tool)) {
        return @($BusinessActions)
    }

    if (-not (Test-ToolDepInstalled $Tool)) {
        return @(Get-ToolDependencyInstallMenuAction -Tool $Tool)
    }

    $items = @($BusinessActions)
    $items += @(Get-ToolDependencyUninstallMenuAction -Tool $Tool)
    if ($DependencyUpdateAvailable) {
        $items += @(Get-ToolDependencyUpdateMenuAction -Tool $Tool)
    }
    return $items
}

function Invoke-ToolDependencyMenuAction {
    param(
        $Tool,
        $Action,
        [hashtable]$Shell = $null,
        [string]$SectionTitle = ''
    )

    if (-not (Test-ToolDependencyMenuAction $Action)) {
        return 1
    }

    $intent = [string]$Action.command
    $ok = $false

    switch ($intent) {
        'install' {
            $ok = Invoke-ToolInstall -Tool $Tool -Shell $Shell -SectionTitle $SectionTitle
        }
        'update' {
            $ok = Invoke-ToolUpdate -Tool $Tool -Shell $Shell -SectionTitle $SectionTitle
        }
        'uninstall' {
            $ok = Invoke-ToolUninstall -Tool $Tool -Shell $Shell -SectionTitle $SectionTitle
        }
        default {
            return 1
        }
    }

    if (Test-ShellNavMarker $ok) {
        return $ok
    }

    if ($Shell) {
        return $(if ($ok) { 0 } else { 1 })
    }

    if ($ok) {
        Write-Host (Get-I18n -Key 'common.done') -ForegroundColor Green
        return 0
    }

    Write-Host (Get-I18n -Key 'common.failed') -ForegroundColor Red
    return 1
}

function Wait-ToolDependencyMenuContinue {
    Write-Host ''
    Read-Host (Format-I18nPressEnterBack -BackSuffixKey 'page.toolDeps.backTarget')
}
