function Get-DefaultToolFields {
    param([string]$ToolDirName)

    [ordered]@{
        id              = $ToolDirName
        command         = $ToolDirName
        no              = 0
        entry           = 'index.ps1'
        install         = 'install.ps1'
        help            = 'help.md'
        interactive     = $true
        enabled         = $true
        requiresInstall = $true
    }
}

function Get-ToolFromDirectory {
    param([string]$ToolRoot)

    $toolDirName = Split-Path $ToolRoot -Leaf
    $manifestPath = Join-Path $ToolRoot 'index.json'
    if (-not (Test-Path $manifestPath)) { return $null }

    $raw = Get-Content -Raw -Path $manifestPath -Encoding UTF8 | ConvertFrom-Json
    $defaults = Get-DefaultToolFields $toolDirName

    $tool = [ordered]@{}
    foreach ($key in @($defaults.Keys)) { $tool[$key] = $defaults[$key] }
    foreach ($prop in $raw.PSObject.Properties) { $tool[$prop.Name] = $prop.Value }

    $tool['_root'] = $ToolRoot
    return Apply-ToolI18nFields -Tool ([pscustomobject]$tool)
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
        $manifestPath = Join-Path $_.FullName 'index.json'
        if (-not (Test-Path $manifestPath)) { return }

        $raw = Get-Content -Raw -Path $manifestPath -Encoding UTF8 | ConvertFrom-Json
        $defaults = Get-DefaultToolFields $_.Name

        $tool = [ordered]@{}
        foreach ($key in @($defaults.Keys)) { $tool[$key] = $defaults[$key] }
        foreach ($prop in $raw.PSObject.Properties) { $tool[$prop.Name] = $prop.Value }

        if ($tool.enabled -eq $false) { return }
        if ([string]::IsNullOrWhiteSpace([string]$tool.command)) {
            $tool.command = $tool.id
        }
        if ([int]$tool.no -le 0) {
            Write-Warning (Get-I18n -Key 'message.toolNoMissing' -Vars @{ command = $tool.command })
            $tool.no = 9999
        }
        $tool['_root'] = $_.FullName
        $result += Apply-ToolI18nFields -Tool ([pscustomobject]$tool)
    }

    $seen = @{}
    foreach ($t in $result) {
        $n = [int]$t.no
        if ($seen.ContainsKey($n)) {
            Write-Warning (Get-I18n -Key 'message.toolNoDuplicate' -Vars @{
                no           = $n
                firstCommand = $seen[$n]
                secondCommand = $t.command
            })
        }
        else {
            $seen[$n] = $t.command
        }
    }

    $result | Sort-Object { [int]$_.no }
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
