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

    foreach ($dep in @($Tool.dependencies)) {
        $depId = Get-DependencyRecordId -Dependency $dep
        $recorded = Get-ToolDepRecordedVersion -ToolId ([string]$Tool.id) -DependencyId $depId
        if ([string]::IsNullOrWhiteSpace($recorded)) { return $true }

        if (Test-DependencyVersionPolicyIsLatest -Dependency $dep) {
            $packageId = $null
            if ($dep.install -and $dep.install.packageId) {
                $packageId = [string]$dep.install.packageId
            }
            if ($packageId -and (Test-WingetPackageUpdateAvailable -PackageId $packageId -InstalledVersion $recorded)) {
                return $true
            }
            continue
        }

        $target = (Get-DependencyVersionPolicy -Dependency $dep).Trim()
        if ((Normalize-Semver $recorded) -ne (Normalize-Semver $target)) {
            return $true
        }
    }

    return $false
}

function Get-ToolsWithExternalDeps {
    param(
        [array]$Tools,
        [string[]]$ToolIds = @()
    )

    $filtered = @($Tools | Where-Object { Test-ToolHasExternalDeps $_ })
    if ($ToolIds.Count -eq 0) {
        return @($filtered | Sort-Object { [int]$_.number })
    }

    $result = @()
    foreach ($id in $ToolIds) {
        $tool = $filtered | Where-Object { $_.id -eq $id } | Select-Object -First 1
        if (-not $tool) {
            Write-Warning (Get-I18n -Key 'install.unknownTool' -Vars @{ toolId = $id })
            continue
        }
        $result += $tool
    }
    return @($result | Sort-Object { [int]$_.number })
}

function Invoke-ToolUninstall {
    param(
        $Tool,
        [switch]$Preview
    )

    if (-not (Test-ToolHasExternalDeps $Tool)) {
        Write-Host (Get-I18n -Key 'install.noExternalDeps' -Vars @{ toolId = $Tool.id }) -ForegroundColor DarkGray
        return $true
    }

    $uninstallScript = Join-Path $Tool._root 'uninstall.ps1'
    if (-not (Test-Path $uninstallScript)) {
        Write-Host (Get-I18n -Key 'install.missingUninstallScript' -Vars @{ toolId = $Tool.id }) -ForegroundColor Red
        return $false
    }

    if ($Preview) {
        Write-Host "[预览] 将执行: $($Tool.id)/uninstall.ps1" -ForegroundColor Yellow
        return $true
    }

    Write-Host (Get-I18n -Key 'install.uninstalling' -Vars @{ name = $Tool.displayName }) -ForegroundColor Cyan
    & $uninstallScript
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        return $false
    }

    Remove-ToolDepInstalled -ToolId ([string]$Tool.id)
    return $true
}

function Invoke-ToolkitInstallDeps {
    param(
        [array]$Tools,
        [string[]]$ToolIds = @(),
        [switch]$Preview
    )

    return (Start-InstallDepsSession -Tools $Tools -FocusToolIds $ToolIds -Preview:$Preview)
}

function Invoke-ToolkitUninstallDeps {
    param(
        [array]$Tools,
        [string[]]$ToolIds,
        [switch]$Preview
    )

    if ($ToolIds.Count -eq 0) {
        Write-Host (Get-I18n -Key 'install.uninstallNeedsToolId') -ForegroundColor Red
        return 1
    }

    $targets = @(Get-ToolsWithExternalDeps -Tools $Tools -ToolIds $ToolIds)
    if ($targets.Count -eq 0) {
        Write-Host (Get-I18n -Key 'install.noTargets') -ForegroundColor DarkGray
        return 1
    }

    $exitCode = 0
    foreach ($tool in $targets) {
        if (-not (Invoke-ToolUninstall -Tool $tool -Preview:$Preview)) {
            $exitCode = 1
        }
    }
    return $exitCode
}

function Test-ToolDependencyMenuAction {
    param($Action)

    return ($Action -and $Action._kind -eq 'toolDeps')
}

function Get-ToolDependencyInstallMenuAction {
    return [pscustomobject]@{
        _kind   = 'toolDeps'
        id      = 'deps-install'
        label   = (Get-I18n -Key 'tool.deps.installLabel')
        summary = (Get-I18n -Key 'tool.deps.installSummary')
        enabled = $true
    }
}

function Get-ToolDependencyMenuActions {
    param($Tool)

    if (-not (Test-ToolHasExternalDeps $Tool)) { return @() }

    return @(
        (Get-ToolDependencyInstallMenuAction)
        [pscustomobject]@{
            _kind   = 'toolDeps'
            id      = 'deps-uninstall'
            label   = (Get-I18n -Key 'tool.deps.uninstallLabel')
            summary = (Get-I18n -Key 'tool.deps.uninstallSummary')
            enabled = $true
        }
    )
}

function Get-ToolMenuItems {
    param(
        [array]$BusinessActions,
        $Tool
    )

    if (-not (Test-ToolHasExternalDeps $Tool)) {
        return @($BusinessActions)
    }

    if (-not (Test-ToolDepInstalled $Tool)) {
        return @(Get-ToolDependencyInstallMenuAction)
    }

    $items = @($BusinessActions)
    $items += @(Get-ToolDependencyMenuActions -Tool $Tool)
    return $items
}

function Invoke-ToolDependencyMenuAction {
    param(
        $Tool,
        $Action,
        [switch]$Preview
    )

    switch ([string]$Action.id) {
        'deps-install' {
            $ok = Invoke-ToolInstall -Tool $Tool -Preview:$Preview
            if ($ok) {
                Write-Host (Get-I18n -Key 'install.statusDone') -ForegroundColor Green
                return 0
            }

            Write-Host (Get-I18n -Key 'install.statusFailed') -ForegroundColor Red
            return 1
        }
        'deps-uninstall' {
            if (Invoke-ToolUninstall -Tool $Tool -Preview:$Preview) {
                Write-Host (Get-I18n -Key 'install.statusDone') -ForegroundColor Green
                return 0
            }

            Write-Host (Get-I18n -Key 'install.statusFailed') -ForegroundColor Red
            return 1
        }
        default {
            return 1
        }
    }
}

function Wait-ToolDependencyMenuContinue {
    Write-Host ''
    Read-Host (Get-I18n -Key 'tool.deps.pressEnterToBack')
}
