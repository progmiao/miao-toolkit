function Get-DefaultToolFields {
    param([string]$ToolDirName)

    [ordered]@{
        id              = $ToolDirName
        number          = 0
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
    return [pscustomobject]$tool
}

function Resolve-ToolMenuNumberIndex {
    param(
        [array]$Items,
        [int]$Number
    )

    for ($i = 0; $i -lt $Items.Count; $i++) {
        if ([int]$Items[$i].number -eq $Number) { return $i }
    }
    return -1
}

function Get-ToolMenuNumberDisplayWidth {
    param([array]$Tools)

    $maxNumber = 0
    foreach ($t in $Tools) {
        $n = [int]$t.number
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
        if ([int]$tool.number -le 0) {
            Write-Warning "工具 $($tool.id) 未配置 number，请在 index.json 中设置全局唯一编号"
            $tool.number = 9999
        }
        $tool['_root'] = $_.FullName
        $result += [pscustomobject]$tool
    }

    $seen = @{}
    foreach ($t in $result) {
        $n = [int]$t.number
        if ($seen.ContainsKey($n)) {
            Write-Warning "工具编号重复: $n ($($seen[$n]) / $($t.id))"
        }
        else {
            $seen[$n] = $t.id
        }
    }

    $result | Sort-Object { [int]$_.number }
}

function Get-Tool {
    param([string]$Id)

    Discover-Tools | Where-Object { $_.id -eq $Id } | Select-Object -First 1
}
