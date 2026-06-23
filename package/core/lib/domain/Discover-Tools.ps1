function Get-ToolkitReservedToolCommands {
    return @(
        'install', 'update', 'uninstall', 'help', 'list', 'version', 'sys', 'helper', 'lang', 'init', 'cache'
    )
}

function Test-ToolkitToolCommandName {
    param([string]$Command)

    if ([string]::IsNullOrWhiteSpace($Command)) { return $false }
    if ($Command -notmatch '^[a-z0-9]+(-[a-z0-9]+)*$') { return $false }
    if ($Command -in @(Get-ToolkitReservedToolCommands)) { return $false }
    return $true
}

function Resolve-BundledToolDirIdentity {
    param([string]$DirName)

    if ([string]::IsNullOrWhiteSpace($DirName)) { return $null }

    $idx = $DirName.IndexOf('-')
    if ($idx -lt 1) { return $null }

    $sortPart = $DirName.Substring(0, $idx)
    $commandPart = $DirName.Substring($idx + 1)

    if ($sortPart -notmatch '^\d+$') { return $null }
    if ([string]::IsNullOrWhiteSpace($commandPart)) { return $null }
    if (-not (Test-ToolkitToolCommandName -Command $commandPart)) { return $null }

    return @{
        sortOrder = [int]$sortPart
        command   = [string]$commandPart
        id        = [string]$commandPart
    }
}

function Resolve-ExternalToolDirIdentity {
    param([string]$DirName)

    if ([string]::IsNullOrWhiteSpace($DirName)) { return $null }
    if ($DirName.StartsWith('_')) { return $null }
    if ($DirName -match '^\d+-') { return $null }
    if (-not (Test-ToolkitToolCommandName -Command $DirName)) { return $null }

    return @{
        command = [string]$DirName
        id      = [string]$DirName
    }
}

function Resolve-ToolDirIdentity {
    param([string]$DirName)

    $identity = Resolve-BundledToolDirIdentity -DirName $DirName
    if (-not $identity) { return $null }

    return @{
        sortOrder = [int]$identity.sortOrder
        command   = [string]$identity.command
        id        = [string]$identity.id
        no        = [int]$identity.sortOrder
    }
}

function Get-DefaultToolFields {
    param(
        [string]$ToolDirName,
        [hashtable]$Identity = $null,
        [ValidateSet('bundled', 'external')]
        [string]$Origin = 'bundled'
    )

    $command = if ($Identity) { [string]$Identity.command } else { $ToolDirName }
    $sortOrder = if ($Identity -and $null -ne $Identity.sortOrder) { [int]$Identity.sortOrder } else { 0 }
    $id = if ($Identity) { [string]$Identity.id } else { $ToolDirName }

    [ordered]@{
        id              = $id
        command         = $command
        sortOrder       = $sortOrder
        no              = 0
        origin          = $Origin
        entry           = 'index.ps1'
        help            = 'help.md'
        interactive     = $true
        enabled         = $true
        requiresInstall = $true
    }
}

function Merge-ToolManifestFromBundledDirectory {
    param(
        [string]$ToolRoot,
        [string]$ToolDirName
    )

    $manifestPath = Join-Path $ToolRoot 'index.json'
    if (-not (Test-Path $manifestPath)) { return $null }

    $identity = Resolve-BundledToolDirIdentity -DirName $ToolDirName
    if (-not $identity) {
        Write-Warning (Get-I18n -Key 'message.toolDirNameInvalid' -Vars @{ dirName = $ToolDirName })
        return $null
    }

    return Merge-ToolManifestCore -ToolRoot $ToolRoot -ToolDirName $ToolDirName `
        -Identity $identity -Origin 'bundled'
}

function Merge-ToolManifestFromExternalDirectory {
    param(
        [string]$ToolRoot,
        [string]$ToolDirName
    )

    $manifestPath = Join-Path $ToolRoot 'index.json'
    if (-not (Test-Path $manifestPath)) { return $null }

    $identity = Resolve-ExternalToolDirIdentity -DirName $ToolDirName
    if (-not $identity) {
        Write-Warning (Get-I18n -Key 'message.toolExternalDirNameInvalid' -Vars @{ dirName = $ToolDirName })
        return $null
    }

    return Merge-ToolManifestCore -ToolRoot $ToolRoot -ToolDirName $ToolDirName `
        -Identity $identity -Origin 'external'
}

function Merge-ToolManifestCore {
    param(
        [string]$ToolRoot,
        [string]$ToolDirName,
        [hashtable]$Identity,
        [ValidateSet('bundled', 'external')]
        [string]$Origin
    )

    $manifestPath = Join-Path $ToolRoot 'index.json'
    $raw = Get-Content -Raw -Path $manifestPath -Encoding UTF8 | ConvertFrom-Json
    $defaults = Get-DefaultToolFields -ToolDirName $ToolDirName -Identity $Identity -Origin $Origin

    $tool = [ordered]@{}
    foreach ($key in @($defaults.Keys)) { $tool[$key] = $defaults[$key] }

    $ignoredIdentityKeys = @('no', 'command', 'id', 'sortOrder', 'origin')
    foreach ($prop in $raw.PSObject.Properties) {
        if ($prop.Name -in $ignoredIdentityKeys) {
            Write-Warning (Get-I18n -Key 'message.toolIdentityIgnored' -Vars @{
                dirName = $ToolDirName
                field   = [string]$prop.Name
            })
            continue
        }
        $tool[$prop.Name] = $prop.Value
    }

    $tool['_root'] = $ToolRoot
    $tool['_dirName'] = $ToolDirName
    return Apply-ToolI18nFields -Tool ([pscustomobject]$tool)
}

function Merge-ToolManifestFromDirectory {
    param(
        [string]$ToolRoot,
        [string]$ToolDirName
    )

    return Merge-ToolManifestFromBundledDirectory -ToolRoot $ToolRoot -ToolDirName $ToolDirName
}

function Get-ToolFromDirectory {
    param([string]$ToolRoot)

    $toolDirName = Split-Path $ToolRoot -Leaf
    return Merge-ToolManifestFromDirectory -ToolRoot $ToolRoot -ToolDirName $toolDirName
}

function Assign-ToolMenuNumbers {
    param([array]$Tools)

    if ($Tools.Count -eq 0) { return @() }

    $enabled = @($Tools | Where-Object { $_.enabled -ne $false })
    $bundled = @($enabled | Where-Object {
        -not $_.PSObject.Properties['origin'] -or [string]$_.origin -eq 'bundled'
    })
    $external = @($enabled | Where-Object {
        $_.PSObject.Properties['origin'] -and [string]$_.origin -eq 'external'
    })

    $sortedBundled = @($bundled | Sort-Object { [int]$_.sortOrder }, { [string]$_.command })
    $sortedExternal = @($external | Sort-Object { [string]$_.command })
    $ordered = @($sortedBundled) + @($sortedExternal)

    $no = 1
    foreach ($tool in $ordered) {
        $tool | Add-Member -NotePropertyName 'no' -NotePropertyValue $no -Force
        $no++
    }

    foreach ($tool in @($Tools | Where-Object { $_.enabled -eq $false })) {
        $tool | Add-Member -NotePropertyName 'no' -NotePropertyValue 0 -Force
    }

    return @($Tools | Sort-Object { if ([int]$_.no -le 0) { 1 } else { 0 } }, { [int]$_.no })
}

function Resolve-ToolMenuNumberIndex {
    param(
        [array]$Items,
        [int]$Number
    )

    for ($i = 0; $i -lt $Items.Count; $i++) {
        if ([int]$Items[$i].no -eq $Number) { return $i }
    }
    return -1
}

function Get-ToolMenuNumberDisplayWidth {
    param([array]$Tools)

    $maxNumber = 0
    foreach ($t in $Tools) {
        $n = [int]$t.no
        if ($n -gt $maxNumber) { $maxNumber = $n }
    }
    return Get-MenuNumberDisplayWidth -MaxNumber $maxNumber
}

function Get-ToolkitToolDirectories {
    param(
        [string]$ToolsRoot,
        [ValidateSet('bundled', 'external')]
        [string]$Origin
    )

    if (-not (Test-Path $ToolsRoot)) { return @() }

    return @(Get-ChildItem -Path $ToolsRoot -Directory | Where-Object {
        -not $_.Name.StartsWith('_')
    } | ForEach-Object {
        [pscustomobject]@{
            FullName = $_.FullName
            Name     = $_.Name
            Origin   = $Origin
        }
    })
}

function Discover-Tools {
    $result = @()

    foreach ($entry in @(Get-ToolkitToolDirectories -ToolsRoot (Get-BundledToolsRoot) -Origin 'bundled')) {
        $tool = Merge-ToolManifestFromBundledDirectory -ToolRoot $entry.FullName -ToolDirName $entry.Name
        if (-not $tool) { continue }
        if ($tool.enabled -eq $false) { continue }
        $result += $tool
    }

    foreach ($entry in @(Get-ToolkitToolDirectories -ToolsRoot (Get-ExternalToolsRoot) -Origin 'external')) {
        $tool = Merge-ToolManifestFromExternalDirectory -ToolRoot $entry.FullName -ToolDirName $entry.Name
        if (-not $tool) { continue }
        if ($tool.enabled -eq $false) { continue }
        $result += $tool
    }

    $seenCommand = @{}
    $deduped = [System.Collections.Generic.List[object]]::new()
    foreach ($t in $result) {
        $cmd = [string]$t.command
        if ($seenCommand.ContainsKey($cmd)) {
            Write-Warning (Get-I18n -Key 'message.toolCommandDuplicate' -Vars @{
                command   = $cmd
                firstDir  = [string]$seenCommand[$cmd]
                secondDir = [string]$t._dirName
            })
            continue
        }

        $seenCommand[$cmd] = [string]$t._dirName
        $deduped.Add($t) | Out-Null
    }

    return @(Assign-ToolMenuNumbers -Tools @($deduped))
}

function Register-ToolkitLiveToolDir {
    param(
        [hashtable]$LiveByCommand,
        [string]$ToolRoot,
        [string]$DirName,
        [ValidateSet('bundled', 'external')]
        [string]$Origin
    )

    if ($Origin -eq 'bundled') {
        $identity = Resolve-BundledToolDirIdentity -DirName $DirName
    }
    else {
        $identity = Resolve-ExternalToolDirIdentity -DirName $DirName
    }
    if (-not $identity) { return }

    $command = [string]$identity.command
    if ($LiveByCommand.ContainsKey($command)) {
        $existing = $LiveByCommand[$command]
        if ([string]$existing.origin -eq 'bundled' -and $Origin -eq 'external') { return }
    }

    $LiveByCommand[$command] = @{
        _root    = $ToolRoot
        _dirName = $DirName
        origin   = $Origin
    }
}

function Get-ToolkitLiveToolDirsByCommand {
    $liveByCommand = @{}

    $bundledRoot = Get-BundledToolsRoot
    if (Test-Path $bundledRoot) {
        Get-ChildItem -Path $bundledRoot -Directory | ForEach-Object {
            if ($_.Name.StartsWith('_')) { return }
            Register-ToolkitLiveToolDir -LiveByCommand $liveByCommand `
                -ToolRoot $_.FullName -DirName $_.Name -Origin 'bundled'
        }
    }

    $externalRoot = Get-ExternalToolsRoot
    if (Test-Path $externalRoot) {
        Get-ChildItem -Path $externalRoot -Directory | ForEach-Object {
            if ($_.Name.StartsWith('_')) { return }
            Register-ToolkitLiveToolDir -LiveByCommand $liveByCommand `
                -ToolRoot $_.FullName -DirName $_.Name -Origin 'external'
        }
    }

    return $liveByCommand
}

function Sync-ToolkitToolsLivePaths {
    param([array]$Tools)

    if ($Tools.Count -eq 0) { return @() }

    $liveByCommand = Get-ToolkitLiveToolDirsByCommand
    $searchRoots = @(
        @{ Path = (Get-BundledToolsRoot); Origin = 'bundled' }
        @{ Path = (Get-ExternalToolsRoot); Origin = 'external' }
    )

    foreach ($tool in $Tools) {
        if (-not $tool) { continue }

        $entryName = if ($tool.PSObject.Properties['entry'] -and -not [string]::IsNullOrWhiteSpace([string]$tool.entry)) {
            [string]$tool.entry
        }
        else {
            'index.ps1'
        }
        if (-not $tool.PSObject.Properties['entry'] -or [string]::IsNullOrWhiteSpace([string]$tool.entry)) {
            $tool | Add-Member -NotePropertyName 'entry' -NotePropertyValue $entryName -Force
        }

        $resolvedRoot = $null
        $resolvedDirName = $null

        if ($tool.PSObject.Properties['_dirName'] -and -not [string]::IsNullOrWhiteSpace([string]$tool._dirName)) {
            foreach ($rootInfo in $searchRoots) {
                if (-not (Test-Path $rootInfo.Path)) { continue }
                $dirPath = Join-Path $rootInfo.Path ([string]$tool._dirName)
                if (Test-Path $dirPath) {
                    $resolvedRoot = $dirPath
                    $resolvedDirName = [string]$tool._dirName
                    break
                }
            }
        }

        if (-not $resolvedRoot -and $tool._root) {
            $cachedEntry = Join-Path ([string]$tool._root) $entryName
            if (Test-Path $cachedEntry) {
                $resolvedRoot = [string]$tool._root
                if ($tool.PSObject.Properties['_dirName'] -and $tool._dirName) {
                    $resolvedDirName = [string]$tool._dirName
                }
            }
        }

        if (-not $resolvedRoot) {
            $commandKey = if ($tool.command) { [string]$tool.command } else { [string]$tool.id }
            if ($commandKey -and $liveByCommand.ContainsKey($commandKey)) {
                $live = $liveByCommand[$commandKey]
                $resolvedRoot = [string]$live._root
                $resolvedDirName = [string]$live._dirName
            }
        }

        if ($resolvedRoot) {
            $tool | Add-Member -NotePropertyName '_root' -NotePropertyValue $resolvedRoot -Force
        }
        if ($resolvedDirName) {
            $tool | Add-Member -NotePropertyName '_dirName' -NotePropertyValue $resolvedDirName -Force
        }
    }

    return @($Tools)
}

function Resolve-ToolkitToolLiveRoot {
    param($Tool)

    if (-not $Tool) { return $null }

    $synced = @(Sync-ToolkitToolsLivePaths -Tools @($Tool))
    if ($synced.Count -lt 1) { return $null }

    $entryName = if ($synced[0].entry) { [string]$synced[0].entry } else { 'index.ps1' }
    $root = if ($synced[0]._root) { [string]$synced[0]._root } else { '' }
    if ([string]::IsNullOrWhiteSpace($root)) { return $null }

    $entry = Join-Path $root $entryName
    if (Test-Path $entry) { return $root }
    return $null
}

function Get-Tool {
    param(
        [string]$Id,
        [array]$Tools = $null
    )

    if ([string]::IsNullOrWhiteSpace($Id)) { return $null }

    if ($null -eq $Tools) {
        if (Get-Command Get-ToolkitTools -ErrorAction SilentlyContinue) {
            $tools = @(Get-ToolkitTools)
        }
        else {
            $tools = @(Discover-Tools)
        }
    }
    else {
        $tools = @($Tools)
    }
    $byCommand = @($tools | Where-Object { [string]$_.command -eq $Id } | Select-Object -First 1)
    if ($byCommand.Count -gt 0) { return $byCommand[0] }

    return $tools | Where-Object { [string]$_.id -eq $Id } | Select-Object -First 1
}

function Get-ToolsReferencingDependency {
    param(
        [string]$Fingerprint,
        [array]$Tools,
        [string]$ExcludeToolId = ''
    )

    if ([string]::IsNullOrWhiteSpace($Fingerprint)) { return @() }

    $refs = @()
    foreach ($tool in @($Tools)) {
        if ([string]$tool.id -eq $ExcludeToolId) { continue }
        if (-not (Test-ToolHasExternalDeps $tool)) { continue }

        foreach ($pkg in @(Get-ToolDependencyPackages -Tool $tool)) {
            if ((Get-DependencyFingerprint -Dependency $pkg) -eq $Fingerprint) {
                $refs += $tool
                break
            }
        }
    }

    return @($refs | Select-Object -Unique -Property id, command, name, _root)
}

function Get-ToolDepSharedWithOtherTools {
    param(
        $Tool,
        [array]$Tools
    )

    if (-not $Tool) { return @() }

    $shared = @()
    foreach ($pkg in @(Get-ToolDependencyPackages -Tool $Tool)) {
        $fp = Get-DependencyFingerprint -Dependency $pkg
        $others = @(Get-ToolsReferencingDependency -Fingerprint $fp -Tools $Tools `
            -ExcludeToolId ([string]$Tool.id))
        if ($others.Count -eq 0) { continue }

        $shared += [pscustomobject]@{
            Fingerprint = $fp
            Name        = if ($pkg.name) { [string]$pkg.name } else { $fp }
            Package     = $pkg
            OtherTools  = $others
        }
    }

    return @($shared)
}
