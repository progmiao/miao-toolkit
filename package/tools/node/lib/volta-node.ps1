# node - Volta / Node version helpers

function Assert-VoltaAvailable {
    if (Get-Command volta -ErrorAction SilentlyContinue) { return }

    Write-MessageBlock -Title '未找到 Volta' -Lines @(
        '请先安装 Volta (工具内 [安装] 或 winget install Volta.Volta).'
    ) -TitleColor Red
    exit 1
}

function Get-VoltaNodeVersionInfo {
    if (-not (Get-Command volta -ErrorAction SilentlyContinue)) {
        return @{ Map = @{}; Default = $null }
    }

    $installed = @{}
    $defaultVer = $null
    $raw = & volta list 2>$null | Out-String
    $nodeLinePattern = 'node@([0-9.]+)'

    foreach ($line in ($raw -split "`n")) {
        if ($line -match $nodeLinePattern) {
            $ver = $Matches[1]
            $installed[$ver] = $true
            if ($line -match '\(default\)') { $defaultVer = $ver }
        }
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

function Format-NodeVersionMenuLabel {
    param(
        $Item,
        [hashtable]$InstalledMap,
        [string]$DefaultVersion,
        [string]$ActiveVersion
    )

    $tag = ''
    if ($Item.Version -eq $ActiveVersion) { $tag += ' [当前]' }
    if ($InstalledMap.ContainsKey($Item.Version)) { $tag += ' [已安装]' }
    if ($Item.Version -eq $DefaultVersion) { $tag += ' [默认]' }
    if ($Item.Lts -and $Item.Lts -ne $false) { $tag += " [LTS:$($Item.Lts)]" }

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
