# 工具功能页标题：{工具名} - {功能名} [- {子阶段}]

function Import-ToolActionSectionTitleCore {
    param([string]$CoreLib)

    if (Get-Command Format-ToolActionSectionTitle -ErrorAction SilentlyContinue) {
        return
    }

    if (-not (Get-Command Resolve-ToolI18nLabel -ErrorAction SilentlyContinue)) {
        . (Join-Path $CoreLib 'config\Paths.ps1')
        . (Join-Path $CoreLib 'config\I18n.ps1')
    }
}

function Get-ToolkitToolDisplayName {
    param([string]$ToolRoot)

    if (Get-Command Get-ToolFromDirectory -ErrorAction SilentlyContinue) {
        $tool = Get-ToolFromDirectory -ToolRoot $ToolRoot
        if ($tool -and -not [string]::IsNullOrWhiteSpace([string]$tool.name)) {
            $unrecognized = if (Get-Command Get-I18n -ErrorAction SilentlyContinue) {
                Get-I18n -Key 'common.unrecognized'
            }
            else {
                'unrecognized'
            }
            if ([string]$tool.name -ne $unrecognized) {
                return [string]$tool.name
            }
        }
    }

    $configPath = Join-Path $ToolRoot 'index.json'
    if (Test-Path -LiteralPath $configPath) {
        $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $nameKey = [string]$config.name
        if (-not [string]::IsNullOrWhiteSpace($nameKey)) {
            $label = Resolve-ToolI18nLabel -ToolRoot $ToolRoot -Key $nameKey -Fallback $nameKey
            if (-not [string]::IsNullOrWhiteSpace($label)) {
                return $label
            }
        }
    }

    return Split-Path $ToolRoot -Leaf
}

function Format-ToolActionSectionTitle {
    param(
        [Parameter(Mandatory)]
        [string]$ToolRoot,
        [string]$ActionNameKey = '',
        [string]$ActionName = '',
        [string]$SubPhaseKey = '',
        [string]$SubPhase = ''
    )

    $toolName = Get-ToolkitToolDisplayName -ToolRoot $ToolRoot
    $actionLabel = [string]$ActionName
    if ([string]::IsNullOrWhiteSpace($actionLabel) -and -not [string]::IsNullOrWhiteSpace($ActionNameKey)) {
        $actionLabel = Resolve-ToolI18nLabel -ToolRoot $ToolRoot -Key $ActionNameKey -Fallback $ActionNameKey
    }

    $title = if ([string]::IsNullOrWhiteSpace($actionLabel)) {
        $toolName
    }
    else {
        "$toolName - $actionLabel"
    }

    $phaseLabel = [string]$SubPhase
    if ([string]::IsNullOrWhiteSpace($phaseLabel) -and -not [string]::IsNullOrWhiteSpace($SubPhaseKey)) {
        $phaseLabel = Resolve-ToolI18nLabel -ToolRoot $ToolRoot -Key $SubPhaseKey -Fallback ''
    }
    if (-not [string]::IsNullOrWhiteSpace($phaseLabel)) {
        $title = "$title - $phaseLabel"
    }

    return $title
}

function Extend-ToolActionSectionTitle {
    param(
        [Parameter(Mandatory)]
        [string]$BaseTitle,
        [Parameter(Mandatory)]
        [string]$ToolRoot,
        [string]$SubPhaseKey = '',
        [string]$SubPhase = ''
    )

    $phaseLabel = [string]$SubPhase
    if ([string]::IsNullOrWhiteSpace($phaseLabel) -and -not [string]::IsNullOrWhiteSpace($SubPhaseKey)) {
        $phaseLabel = Resolve-ToolI18nLabel -ToolRoot $ToolRoot -Key $SubPhaseKey -Fallback ''
    }
    if ([string]::IsNullOrWhiteSpace($phaseLabel)) {
        return $BaseTitle
    }
    return "$BaseTitle - $phaseLabel"
}
