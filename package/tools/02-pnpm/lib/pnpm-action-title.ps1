# pnpm — 功能页标题（工具名 - 功能名 [- 子阶段]）

if (-not (Get-Command Format-ToolActionSectionTitle -ErrorAction SilentlyContinue)) {
    $pnpmActionTitleCoreLib = Join-Path $PSScriptRoot '..\..\..\core\lib'
    . (Join-Path $pnpmActionTitleCoreLib 'ui\shell\ToolActionSectionTitle.ps1')
}

function Import-PnpmActionTitleCore {
    param([string]$CoreLib)

    Import-ToolActionSectionTitleCore -CoreLib $CoreLib
}

function Resolve-PnpmToolAction {
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

function Get-PnpmActionSectionTitle {
    param(
        [string]$ToolRoot,
        $Action = $null,
        [string]$ScriptLeaf = '',
        [string]$SubPhaseKey = ''
    )

    $resolved = Resolve-PnpmToolAction -ToolRoot $ToolRoot -Action $Action -ScriptLeaf $ScriptLeaf
    if (-not $resolved) {
        return (Get-ToolkitToolDisplayName -ToolRoot $ToolRoot)
    }

    return (Format-ToolActionSectionTitle -ToolRoot $ToolRoot -ActionNameKey ([string]$resolved.name) `
        -SubPhaseKey $SubPhaseKey)
}

function Extend-PnpmActionSectionTitle {
    param(
        [string]$BaseTitle,
        [string]$ToolRoot,
        [string]$SubPhaseKey
    )

    return Extend-ToolActionSectionTitle -BaseTitle $BaseTitle -ToolRoot $ToolRoot `
        -SubPhaseKey $SubPhaseKey
}
