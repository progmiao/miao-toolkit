# claude-code — 预设配置（presets/claude-code-presets.json）

function Get-ClaudeCodePresetsPath {
    param([string]$ToolRoot)

    return Join-Path $ToolRoot 'presets\claude-code-presets.json'
}

function Import-ClaudeCodePresetsConfig {
    param([string]$ToolRoot)

    $path = Get-ClaudeCodePresetsPath -ToolRoot $ToolRoot
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Claude Code preset config not found: $path"
    }

    $config = Get-Content -Raw -LiteralPath $path -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $config) {
        throw "Claude Code preset config is empty: $path"
    }

    $schemaVersion = 0
    if ($config.PSObject.Properties['schemaVersion']) {
        $schemaVersion = [int]$config.schemaVersion
    }
    if ($schemaVersion -ne 1) {
        throw "Unsupported Claude Code preset schemaVersion: $schemaVersion"
    }

    return $config
}

function Get-ClaudeCodeMarketplacePresetsPath {
    param([string]$ToolRoot)

    return (Get-ClaudeCodePresetsPath -ToolRoot $ToolRoot)
}

function Get-ClaudeCodeMarketplacePresets {
    param([string]$ToolRoot)

    $config = Import-ClaudeCodePresetsConfig -ToolRoot $ToolRoot
    $path = Get-ClaudeCodePresetsPath -ToolRoot $ToolRoot
    $entries = @($config.marketplaces)
    if ($entries.Count -le 0) {
        throw "Marketplace preset list is empty: $path"
    }

    $seen = @{}
    $items = @()
    foreach ($entry in $entries) {
        $source = if ($entry.PSObject.Properties['source']) { [string]$entry.source.Trim() } else { '' }
        if ([string]::IsNullOrWhiteSpace($source)) {
            throw "Marketplace preset entry missing source: $path"
        }
        if ($seen.ContainsKey($source)) {
            throw "Duplicate marketplace source in preset config: $source"
        }
        $seen[$source] = $true

        $label = if ($entry.PSObject.Properties['label']) { [string]$entry.label.Trim() } else { '' }
        if ([string]::IsNullOrWhiteSpace($label)) {
            $label = $source
        }

        $items += [pscustomobject]@{
            Source = $source
            Label  = $label
        }
    }

    return @($items)
}

function Get-ClaudeCodeFeaturedPluginOrderMap {
    param([string]$ToolRoot)

    $config = Import-ClaudeCodePresetsConfig -ToolRoot $ToolRoot
    if (-not $config.PSObject.Properties['featuredPlugins']) {
        return @{}
    }

    $entries = @($config.featuredPlugins)
    if ($entries.Count -le 0) {
        return @{}
    }

    $map = @{}
    $autoOrder = 0
    foreach ($entry in $entries) {
        $id = ''
        $order = $autoOrder

        if ($entry -is [string]) {
            $id = [string]$entry.Trim()
        }
        else {
            if ($entry.PSObject.Properties['id']) {
                $id = [string]$entry.id.Trim()
            }
            if ($entry.PSObject.Properties['order']) {
                $order = [int]$entry.order
            }
        }

        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        if ($map.ContainsKey($id)) { continue }

        $map[$id] = $order
        $autoOrder++
    }

    return $map
}

function Get-ClaudeMarketplaceRegistryRoot {
    return Join-Path (Join-Path $env:USERPROFILE '.claude') 'plugins\marketplaces'
}

function Get-ClaudeMarketplaceSourceRepoName {
    param([string]$Source)

    $text = [string]$Source
    if ($text -match '/([^/]+)$') {
        return $Matches[1]
    }

    return ($text -replace '[/\\]', '-')
}

function Test-ClaudeMarketplaceRegistered {
    param([string]$Source)

    $root = Get-ClaudeMarketplaceRegistryRoot
    if (-not (Test-Path -LiteralPath $root)) {
        return $false
    }

    $repoName = Get-ClaudeMarketplaceSourceRepoName -Source $Source
    foreach ($marketDir in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
        $dirName = [string]$marketDir.Name
        if ($dirName -eq $repoName) {
            return $true
        }

        $catalogPath = Join-Path (Join-Path $marketDir.FullName '.claude-plugin') 'marketplace.json'
        if (-not (Test-Path -LiteralPath $catalogPath)) { continue }

        try {
            $raw = Get-Content -Raw -LiteralPath $catalogPath -Encoding UTF8
            if ($raw -match [regex]::Escape($Source)) {
                return $true
            }
            if (-not [string]::IsNullOrWhiteSpace($repoName) -and $raw -match [regex]::Escape($repoName)) {
                return $true
            }
        }
        catch {
            continue
        }
    }

    return $false
}

function Invoke-ClaudeCodeMarketplacePresetRegister {
    param(
        [string]$Source,
        [scriptblock]$OnUiPoll = $null,
        [scriptblock]$OnChromePulse = $null
    )

    if (Test-ClaudeMarketplaceRegistered -Source $Source) {
        return [pscustomobject]@{
            Success = $true
            Skipped = $true
            Path    = ''
        }
    }

    if (-not (Test-ClaudeCodeCliAvailable)) {
        return [pscustomobject]@{
            Success = $false
            Path    = ''
        }
    }

    $result = Invoke-ClaudePluginMarketplaceAdd -Source $Source -OnUiPoll $OnUiPoll -OnChromePulse $OnChromePulse
    $output = [string]$result.Output
    $ok = $false
    if ($result.PSObject.Properties['Success']) {
        $ok = [bool]$result.Success
    }
    else {
        $ok = ($result.ExitCode -eq 0)
    }

    if (-not $ok -and $output -match '(?i)already') {
        $ok = $true
    }

    return [pscustomobject]@{
        Success = $ok
        Path    = if ($ok) { '' } else { $output.Trim() }
    }
}
