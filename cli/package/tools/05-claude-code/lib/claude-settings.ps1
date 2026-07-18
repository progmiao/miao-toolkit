# claude-code — settings.json 与 Miao 侧密钥存储

function Get-ClaudeCodeUserConfigPath {
    Join-Path (Get-UserConfigDirectory) 'claude-code.json'
}

function Get-ClaudeCodeSettingsPath {
    Join-Path (Join-Path $env:USERPROFILE '.claude') 'settings.json'
}

function Get-ClaudeCodeUserSecrets {
    $path = Get-ClaudeCodeUserConfigPath
    if (-not (Test-Path -LiteralPath $path)) {
        return [ordered]@{
            api   = [ordered]@{}
            proxy = [ordered]@{}
        }
    }

    try {
        $raw = Get-Content -Raw -LiteralPath $path -Encoding UTF8 | ConvertFrom-Json
        return $raw
    }
    catch {
        return [ordered]@{
            api   = [ordered]@{}
            proxy = [ordered]@{}
        }
    }
}

function Save-ClaudeCodeUserSecrets {
    param($Secrets)

    $dir = Get-UserConfigDirectory
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $path = Get-ClaudeCodeUserConfigPath
    $json = ($Secrets | ConvertTo-Json -Depth 6)
    [IO.File]::WriteAllText($path, $json, [Text.UTF8Encoding]::new($true))
}

function Read-ClaudeCodeSettingsJson {
    $path = Get-ClaudeCodeSettingsPath
    if (-not (Test-Path -LiteralPath $path)) {
        return [ordered]@{}
    }

    try {
        $raw = Get-Content -Raw -LiteralPath $path -Encoding UTF8 | ConvertFrom-Json
        if ($null -eq $raw) { return [ordered]@{} }
        return $raw
    }
    catch {
        return [ordered]@{}
    }
}

function ConvertTo-ClaudeCodeHashtable {
    param($InputObject)

    if ($null -eq $InputObject) { return @{} }

    if ($InputObject -is [hashtable]) {
        return [hashtable]$InputObject
    }

    $result = @{}
    foreach ($prop in $InputObject.PSObject.Properties) {
        $value = $prop.Value
        if ($value -is [System.Management.Automation.PSCustomObject]) {
            $result[$prop.Name] = ConvertTo-ClaudeCodeHashtable -InputObject $value
        }
        elseif ($value -is [System.Collections.IEnumerable] -and $value -isnot [string]) {
            $result[$prop.Name] = @($value)
        }
        else {
            $result[$prop.Name] = $value
        }
    }
    return $result
}

function Merge-ClaudeCodeEnvSettings {
    param(
        [hashtable]$EnvUpdates,
        [string[]]$EnvRemoveKeys = @()
    )

    $settingsPath = Get-ClaudeCodeSettingsPath
    $settingsDir = Split-Path $settingsPath -Parent
    if (-not (Test-Path $settingsDir)) {
        New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
    }

    $settings = ConvertTo-ClaudeCodeHashtable -InputObject (Read-ClaudeCodeSettingsJson)
    if (-not $settings.ContainsKey('env') -or $null -eq $settings['env']) {
        $settings['env'] = @{}
    }

    $envMap = @{}
    if ($settings['env'] -is [hashtable]) {
        foreach ($key in $settings['env'].Keys) {
            $envMap[$key] = [string]$settings['env'][$key]
        }
    }
    else {
        foreach ($prop in $settings['env'].PSObject.Properties) {
            $envMap[$prop.Name] = [string]$prop.Value
        }
    }

    foreach ($removeKey in @($EnvRemoveKeys)) {
        if ([string]::IsNullOrWhiteSpace($removeKey)) { continue }
        if ($envMap.ContainsKey($removeKey)) {
            $envMap.Remove($removeKey)
        }
    }

    foreach ($key in $EnvUpdates.Keys) {
        $value = $EnvUpdates[$key]
        if ([string]::IsNullOrWhiteSpace([string]$value)) {
            if ($envMap.ContainsKey($key)) {
                $envMap.Remove($key)
            }
            continue
        }
        $envMap[$key] = [string]$value
    }

    if ($envMap.Count -eq 0) {
        if ($settings.ContainsKey('env')) {
            $settings.Remove('env')
        }
    }
    else {
        $settings['env'] = $envMap
    }

    $json = ($settings | ConvertTo-Json -Depth 8)
    [IO.File]::WriteAllText($settingsPath, $json, [Text.UTF8Encoding]::new($true))
    return $settingsPath
}

function Apply-ClaudeCodeInitDefaults {
    return Merge-ClaudeCodeEnvSettings -EnvUpdates @{
        DISABLE_LOGIN_COMMAND = '1'
    }
}

function Apply-ClaudeCodeApiSecrets {
    param($ApiConfig)

    $secrets = Get-ClaudeCodeUserSecrets
    if (-not $secrets.api) {
        $secrets | Add-Member -NotePropertyName api -NotePropertyValue ([ordered]@{}) -Force
    }

    $mode = [string]$ApiConfig.mode
    $removeKeys = @(
        'ANTHROPIC_API_KEY'
        'ANTHROPIC_BASE_URL'
        'ANTHROPIC_AUTH_TOKEN'
    )

    if ($mode -eq 'clear') {
        $secrets.api = [ordered]@{ mode = 'clear' }
        Save-ClaudeCodeUserSecrets -Secrets $secrets
        return Merge-ClaudeCodeEnvSettings -EnvRemoveKeys $removeKeys
    }

    $envUpdates = @{}
    if ($mode -eq 'official') {
        $apiKey = [string]$ApiConfig.apiKey
        $secrets.api = [ordered]@{
            mode   = 'official'
            apiKey = $apiKey
        }
        $envUpdates['ANTHROPIC_API_KEY'] = $apiKey
        $removeKeys = @('ANTHROPIC_BASE_URL', 'ANTHROPIC_AUTH_TOKEN')
    }
    elseif ($mode -eq 'custom') {
        $baseUrl = [string]$ApiConfig.baseUrl
        $token = [string]$ApiConfig.authToken
        $secrets.api = [ordered]@{
            mode      = 'custom'
            baseUrl   = $baseUrl
            authToken = $token
        }
        $envUpdates['ANTHROPIC_BASE_URL'] = $baseUrl
        if (-not [string]::IsNullOrWhiteSpace($token)) {
            if ($token -match '^sk-ant-') {
                $envUpdates['ANTHROPIC_API_KEY'] = $token
                $removeKeys = @('ANTHROPIC_AUTH_TOKEN')
            }
            else {
                $envUpdates['ANTHROPIC_AUTH_TOKEN'] = $token
                $removeKeys = @('ANTHROPIC_API_KEY')
            }
        }
        else {
            $removeKeys = @('ANTHROPIC_API_KEY', 'ANTHROPIC_AUTH_TOKEN')
        }
    }

    Save-ClaudeCodeUserSecrets -Secrets $secrets
    return Merge-ClaudeCodeEnvSettings -EnvUpdates $envUpdates -EnvRemoveKeys $removeKeys
}

function Apply-ClaudeCodeProxySecrets {
    param($ProxyConfig)

    $secrets = Get-ClaudeCodeUserSecrets
    if (-not $secrets.proxy) {
        $secrets | Add-Member -NotePropertyName proxy -NotePropertyValue ([ordered]@{}) -Force
    }

    $removeKeys = @('HTTP_PROXY', 'HTTPS_PROXY')

    if ([string]$ProxyConfig.mode -eq 'clear') {
        $secrets.proxy = [ordered]@{ mode = 'clear' }
        Save-ClaudeCodeUserSecrets -Secrets $secrets
        return Merge-ClaudeCodeEnvSettings -EnvRemoveKeys $removeKeys
    }

    $httpProxy = [string]$ProxyConfig.httpProxy
    $httpsProxy = [string]$ProxyConfig.httpsProxy
    if ([string]::IsNullOrWhiteSpace($httpsProxy) -and -not [string]::IsNullOrWhiteSpace($httpProxy)) {
        $httpsProxy = $httpProxy
    }

    $secrets.proxy = [ordered]@{
        mode       = 'set'
        httpProxy  = $httpProxy
        httpsProxy = $httpsProxy
    }
    Save-ClaudeCodeUserSecrets -Secrets $secrets

    return Merge-ClaudeCodeEnvSettings -EnvUpdates @{
        HTTP_PROXY  = $httpProxy
        HTTPS_PROXY = $httpsProxy
    } -EnvRemoveKeys @()
}

function Sync-ClaudeCodeSettingsFromSecrets {
    $secrets = Get-ClaudeCodeUserSecrets
    $paths = @()

    if ($secrets.api -and [string]$secrets.api.mode -and [string]$secrets.api.mode -ne 'clear') {
        $paths += Apply-ClaudeCodeApiSecrets -ApiConfig $secrets.api
    }

    if ($secrets.proxy -and [string]$secrets.proxy.mode -and [string]$secrets.proxy.mode -ne 'clear') {
        $paths += Apply-ClaudeCodeProxySecrets -ProxyConfig $secrets.proxy
    }

    return @($paths | Select-Object -Unique)
}

function Test-ClaudeCodeSettingsFile {
    $path = Get-ClaudeCodeSettingsPath
    return (Test-Path -LiteralPath $path)
}
