# 开发模式专用：主菜单 UI 测试模拟工具（不随正式发布包分发）

function Get-MockToolsConfigPath {
    if (-not (Test-MiaoDevMode)) { return $null }

    if ($env:MIAO_MOCK_TOOLS) {
        return $env:MIAO_MOCK_TOOLS
    }

    $miaoHome = Get-Home
    $repoDev = Join-Path (Split-Path $miaoHome -Parent) 'dev\mock-tools.json'
    if (Test-Path $repoDev) { return $repoDev }

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
            id              = [string]$raw.id
            number          = [int]$raw.number
            displayName     = [string]$raw.displayName
            summary         = [string]$raw.summary
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
        return @($RealTools | Sort-Object { [int]$_.number })
    }

    $all = @($RealTools) + @(Get-MockToolsForMenu)
    if ($all.Count -eq 0) { return @() }

    $seen = @{}
    foreach ($t in $all) {
        $n = [int]$t.number
        if ($seen.ContainsKey($n)) {
            Write-Warning "菜单工具编号重复: $n ($($seen[$n]) / $($t.id))"
        }
        else {
            $seen[$n] = $t.id
        }
    }

    return @($all | Sort-Object { [int]$_.number })
}

function Test-IsMockTool {
    param($Tool)
    return ($Tool -and $Tool._mock -eq $true)
}
