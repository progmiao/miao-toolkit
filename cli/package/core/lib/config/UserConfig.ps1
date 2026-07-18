# 用户配置（%APPDATA%\Miao\config.json 或 MIAO_CONFIG）

$script:UserConfigCache = $null

function Get-UserConfigDirectory {
    if ($env:MIAO_CONFIG) {
        return $env:MIAO_CONFIG
    }
    return Join-Path $env:APPDATA 'Miao'
}

function Get-UserConfigPath {
    Join-Path (Get-UserConfigDirectory) 'config.json'
}

function Get-UserConfig {
    if ($script:UserConfigCache) {
        return $script:UserConfigCache
    }

    $path = Get-UserConfigPath
    if (-not (Test-Path $path)) {
        $script:UserConfigCache = [pscustomobject]@{ locale = $null }
        return $script:UserConfigCache
    }

    $script:UserConfigCache = Get-Content -Raw -Path $path -Encoding UTF8 | ConvertFrom-Json
    return $script:UserConfigCache
}

function Save-UserConfig {
    param($Config)

    $dir = Get-UserConfigDirectory
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $path = Get-UserConfigPath
    $json = ($Config | ConvertTo-Json -Depth 4)
    [IO.File]::WriteAllText($path, $json, [Text.UTF8Encoding]::new($true))
    $script:UserConfigCache = $Config
}
