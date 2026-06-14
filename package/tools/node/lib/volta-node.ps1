# node - Volta / Node version helpers

function Assert-VoltaAvailable {
    if (Get-Command volta -ErrorAction SilentlyContinue) { return }

    Write-MessageBlock -Title '未找到 Volta' -Lines @(
        '请先安装 Volta (工具内 [安装] 或 winget install Volta.Volta).'
    ) -TitleColor Red
    exit 1
}

function Normalize-NodeVersionLabel {
    param([string]$Version)

    $v = [string]$Version.Trim()
    if ($v -match '^v(.+)$') { return $Matches[1] }
    return $v
}

function Resolve-NodeVersionFromVoltaListLine {
    param([string]$Line)

    $trimmed = [string]$Line.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) { return $null }

    $nodeAtPattern = 'node@([0-9]+(?:\.[0-9]+)*)'
    $voltaVPrefixPattern = 'v([0-9]+(?:\.[0-9]+)*)'

    if ($trimmed -match $nodeAtPattern) {
        $ver = Normalize-NodeVersionLabel -Version $Matches[1]
        if (-not [string]::IsNullOrWhiteSpace($ver)) { return $ver }
    }
    if ($trimmed -match $voltaVPrefixPattern) {
        $ver = Normalize-NodeVersionLabel -Version $Matches[1]
        if (-not [string]::IsNullOrWhiteSpace($ver)) { return $ver }
    }
    return $null
}

function Get-VoltaNodeVersionInfo {
    if (-not (Get-Command volta -ErrorAction SilentlyContinue)) {
        return @{ Map = @{}; Default = $null }
    }

    $installed = @{}
    $defaultVer = $null
    $raw = (& volta list node 2>&1 | Out-String)

    foreach ($line in ($raw -split "\r?\n")) {
        $trimmed = [string]$line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }

        $ver = Resolve-NodeVersionFromVoltaListLine -Line $trimmed
        if ([string]::IsNullOrWhiteSpace($ver)) { continue }
        $installed[$ver] = $true
        if ($trimmed -match '\(default\)') { $defaultVer = $ver }
    }

    return @{ Map = $installed; Default = $defaultVer }
}

function Get-ActiveNodeVersion {
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) { return $null }
    try {
        $v = (& node -v 2>$null).ToString().Trim()
        if ($v) { return ($v -replace '^v', '') }
    }
    catch {}
    return $null
}

function Get-RemoteNodeVersions {
    param([switch]$LtsOnly)

    $releases = Invoke-RestMethod 'https://nodejs.org/dist/index.json'
    if ($LtsOnly) {
        $releases = $releases | Where-Object { $_.lts -ne $false }
    }

    return @($releases | ForEach-Object {
        [PSCustomObject]@{
            Version = ($_.version -replace '^v', '')
            Lts     = $_.lts
            Date    = $_.date
        }
    })
}

function Get-NodeVersionStatusTags {
    param(
        $Item,
        [hashtable]$InstalledMap,
        [string]$DefaultVersion,
        [string]$ActiveVersion = ''
    )

    if ($null -eq $InstalledMap) { $InstalledMap = @{} }

    $version = Normalize-NodeVersionLabel -Version ([string]$Item.Version)
    $active = Normalize-NodeVersionLabel -Version $ActiveVersion
    $default = Normalize-NodeVersionLabel -Version $DefaultVersion

    $tag = ''
    if ($version -and $InstalledMap.ContainsKey($version)) { $tag += ' [已安装]' }
    if ($version -and $default -and $version -eq $default) { $tag += ' [默认]' }
    if ($version -and $active -and $version -eq $active) { $tag += ' [当前]' }
    if ($Item.Lts -and $Item.Lts -ne $false) { $tag += " [LTS:$($Item.Lts)]" }
    return $tag
}

function Format-NodeVersionMenuLabel {
    param(
        $Item,
        [hashtable]$InstalledMap,
        [string]$DefaultVersion,
        [string]$ActiveVersion = ''
    )

    $tag = Get-NodeVersionStatusTags -Item $Item -InstalledMap $InstalledMap `
        -DefaultVersion $DefaultVersion -ActiveVersion $ActiveVersion
    return "$($Item.Version)$tag"
}

function New-NodeVersionMenuItem {
    param(
        [string]$Version,
        $Lts = $false,
        [string]$Date = ''
    )

    return [PSCustomObject]@{
        Version = $Version
        Lts     = $Lts
        Date    = $Date
    }
}

function Sort-NodeVersionItems {
    param([array]$Items)

    return @($Items | Sort-Object { [version]($_.Version.Split('-')[0]) } -Descending)
}
