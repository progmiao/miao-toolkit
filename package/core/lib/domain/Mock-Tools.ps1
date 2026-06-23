# 开发模式专用：主菜单 UI 测试模拟工具（不随正式发布包分发）

function Get-MockToolsConfigPath {
    if (-not (Test-MiaoDevMode)) { return $null }

    if ($env:MIAO_MOCK_TOOLS) {
        return $env:MIAO_MOCK_TOOLS
    }

    $miaoHome = Get-Home
    $repoTest = Join-Path (Split-Path $miaoHome -Parent) 'test\mock-tools.json'
    if (Test-Path $repoTest) { return $repoTest }

    return $null
}

function Get-MockToolsForMenu {
    if (-not (Test-MiaoDevMode)) { return @() }

    $path = Get-MockToolsConfigPath
    if (-not $path) { return @() }

    try {
        $cfg = Get-Content -Raw -Path $path -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        Write-Warning "无法读取模拟工具配置: $path"
        return @()
    }

    if ($cfg.enabled -ne $true) { return @() }

    $result = @()
    foreach ($raw in @($cfg.tools)) {
        $tool = [ordered]@{
            id              = [string]$raw.command
            command         = [string]$raw.command
            sortOrder       = 0
            no              = 0
            origin          = 'external'
            name            = [string]$raw.name
            description     = [string]$raw.description
            entry           = 'index.ps1'
            install         = 'install.ps1'
            help            = 'help.md'
            interactive     = $true
            enabled         = $true
            requiresInstall = $(if ($null -ne $raw.requiresInstall) { [bool]$raw.requiresInstall } else { $false })
            _root           = ''
            _mock           = $true
        }
        $result += [pscustomobject]$tool
    }
    return $result
}

function Get-ToolkitMenuTools {
    param([array]$RealTools)

    if (-not (Test-MiaoDevMode)) {
        return @($RealTools | Sort-Object { [int]$_.no })
    }

    $combined = @($RealTools) + @(Get-MockToolsForMenu)
    if ($combined.Count -eq 0) { return @() }

    $seenCommand = @{}
    $deduped = [System.Collections.Generic.List[object]]::new()
    foreach ($t in $combined) {
        $cmd = [string]$t.command
        if ($seenCommand.ContainsKey($cmd)) { continue }
        $seenCommand[$cmd] = $true
        $deduped.Add($t) | Out-Null
    }

    return @(Assign-ToolMenuNumbers -Tools @($deduped))
}

function Test-IsMockTool {
    param($Tool)
    return ($Tool -and $Tool._mock -eq $true)
}
