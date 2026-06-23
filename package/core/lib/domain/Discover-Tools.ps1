function Get-ToolkitReservedToolCommands {
    return @(
        'install', 'update', 'uninstall', 'help', 'list', 'version', 'sys', 'helper', 'lang', 'init', 'cache'
    )
}

function Resolve-ToolDirIdentity {
    param([string]$DirName)

    if ([string]::IsNullOrWhiteSpace($DirName)) { return $null }

    $idx = $DirName.IndexOf('-')
    if ($idx -lt 1) { return $null }

    $noPart = $DirName.Substring(0, $idx)
    $commandPart = $DirName.Substring($idx + 1)

    if ($noPart -notmatch '^\d+$') { return $null }
    if ([string]::IsNullOrWhiteSpace($commandPart)) { return $null }
    if ($commandPart -notmatch '^[a-z0-9]+(-[a-z0-9]+)*$') { return $null }

    $command = [string]$commandPart
    if ($command -in @(Get-ToolkitReservedToolCommands)) { return $null }

    return @{
        no      = [int]$noPart
        command = $command
        id      = $command
    }
}

function Get-DefaultToolFields {
    param(
        [string]$ToolDirName,
        [hashtable]$Identity = $null
    )

    $command = if ($Identity) { [string]$Identity.command } else { $ToolDirName }
    $no = if ($Identity) { [int]$Identity.no } else { 0 }
    $id = if ($Identity) { [string]$Identity.id } else { $ToolDirName }

    [ordered]@{
        id              = $id
        command         = $command
        no              = $no
        entry           = 'index.ps1'
        help            = 'help.md'
        interactive     = $true
        enabled         = $true
        requiresInstall = $true
    }
}

function Merge-ToolManifestFromDirectory {
    param(
        [string]$ToolRoot,
        [string]$ToolDirName
    )

    $manifestPath = Join-Path $ToolRoot 'index.json'
    if (-not (Test-Path $manifestPath)) { return $null }

    $identity = Resolve-ToolDirIdentity -DirName $ToolDirName
    if (-not $identity) {
        Write-Warning (Get-I18n -Key 'message.toolDirNameInvalid' -Vars @{ dirName = $ToolDirName })
        return $null
    }

    $raw = Get-Content -Raw -Path $manifestPath -Encoding UTF8 | ConvertFrom-Json
    $defaults = Get-DefaultToolFields -ToolDirName $ToolDirName -Identity $identity

    $tool = [ordered]@{}
    foreach ($key in @($defaults.Keys)) { $tool[$key] = $defaults[$key] }

    $ignoredIdentityKeys = @('no', 'command', 'id')
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

function Get-ToolFromDirectory {
    param([string]$ToolRoot)

    $toolDirName = Split-Path $ToolRoot -Leaf
    return Merge-ToolManifestFromDirectory -ToolRoot $ToolRoot -ToolDirName $toolDirName
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

function Discover-Tools {
    $toolsRoot = Get-ToolsRoot
    if (-not (Test-Path $toolsRoot)) {
        return @()
    }

    $result = @()
    Get-ChildItem -Path $toolsRoot -Directory | ForEach-Object {
        if ($_.Name.StartsWith('_')) { return }

        $tool = Merge-ToolManifestFromDirectory -ToolRoot $_.FullName -ToolDirName $_.Name
        if (-not $tool) { return }
        if ($tool.enabled -eq $false) { return }

        $result += $tool
    }

    $seenNo = @{}
    $seenCommand = @{}
    foreach ($t in $result) {
        $n = [int]$t.no
        if ($seenNo.ContainsKey($n)) {
            Write-Warning (Get-I18n -Key 'message.toolNoDuplicate' -Vars @{
                no            = $n
                firstCommand  = $seenNo[$n]
                secondCommand = [string]$t.command
            })
        }
        else {
            $seenNo[$n] = [string]$t.command
        }

        $cmd = [string]$t.command
        if ($seenCommand.ContainsKey($cmd)) {
            Write-Warning (Get-I18n -Key 'message.toolCommandDuplicate' -Vars @{
                command      = $cmd
                firstDir     = $seenCommand[$cmd]
                secondDir    = [string]$t._dirName
            })
        }
        else {
            $seenCommand[$cmd] = [string]$t._dirName
        }
    }

    $result | Sort-Object { [int]$_.no }
}

function Get-ToolkitLiveToolDirsByCommand {
    $liveByCommand = @{}
    $toolsRoot = Get-ToolsRoot
    if (-not (Test-Path $toolsRoot)) { return $liveByCommand }

    Get-ChildItem -Path $toolsRoot -Directory | ForEach-Object {
        if ($_.Name.StartsWith('_')) { return }

        $identity = Resolve-ToolDirIdentity -DirName $_.Name
        if (-not $identity) { return }

        $liveByCommand[[string]$identity.command] = @{
            _root    = $_.FullName
            _dirName = $_.Name
            no       = [int]$identity.no
        }
    }

    return $liveByCommand
}

function Sync-ToolkitToolsLivePaths {
    param([array]$Tools)

    if ($Tools.Count -eq 0) { return @() }

    $liveByCommand = Get-ToolkitLiveToolDirsByCommand
    $toolsRoot = Get-ToolsRoot

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
        $resolvedNo = $null

        if ($tool.PSObject.Properties['_dirName'] -and -not [string]::IsNullOrWhiteSpace([string]$tool._dirName)) {
            $dirPath = Join-Path $toolsRoot ([string]$tool._dirName)
            if (Test-Path $dirPath) {
                $resolvedRoot = $dirPath
                $resolvedDirName = [string]$tool._dirName
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
                $resolvedNo = [int]$live.no
            }
        }

        if ($resolvedRoot) {
            $tool | Add-Member -NotePropertyName '_root' -NotePropertyValue $resolvedRoot -Force
        }
        if ($resolvedDirName) {
            $tool | Add-Member -NotePropertyName '_dirName' -NotePropertyValue $resolvedDirName -Force
        }
        if ($null -ne $resolvedNo) {
            $tool | Add-Member -NotePropertyName 'no' -NotePropertyValue $resolvedNo -Force
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
