# claude-code — 功能页标题（与一级菜单列表名称同源）

function Import-ClaudeCodeActionTitleCore {
    param([string]$CoreLib)

    if (-not (Get-Command Resolve-ToolI18nLabel -ErrorAction SilentlyContinue)) {
        . (Join-Path $CoreLib 'config\Paths.ps1')
        . (Join-Path $CoreLib 'config\I18n.ps1')
    }
}

function Resolve-ClaudeCodeToolAction {
    param(
        [string]$ToolRoot,
        $Action = $null,
        [string]$ScriptLeaf = ''
    )

    if ($Action) { return $Action }

    $configPath = Join-Path $ToolRoot 'index.json'
    if (-not (Test-Path -LiteralPath $configPath)) { return $null }

    $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $actions = @($config.actions)
    if ([string]::IsNullOrWhiteSpace($ScriptLeaf)) { return $null }

    return @($actions | Where-Object {
        $scriptPath = [string]$_.script
        $scriptPath -and ($scriptPath -replace '\\', '/') -like "*$ScriptLeaf"
    } | Select-Object -First 1)
}

function Get-ClaudeCodeActionSectionTitle {
    param(
        [string]$ToolRoot,
        $Action = $null,
        [string]$ScriptLeaf = ''
    )

    $resolved = Resolve-ClaudeCodeToolAction -ToolRoot $ToolRoot -Action $Action -ScriptLeaf $ScriptLeaf
    if (-not $resolved) {
        if (Get-Command Get-ToolFromDirectory -ErrorAction SilentlyContinue) {
            $tool = Get-ToolFromDirectory -ToolRoot $ToolRoot
            if ($tool) {
                return [string]$tool.name
            }
        }
        return 'claude-code'
    }

    return (Resolve-ToolI18nLabel -ToolRoot $ToolRoot -Key ([string]$resolved.name) `
        -Fallback ([string]$resolved.command))
}
