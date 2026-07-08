# Shell 列表 — 搜索配置与输入 buffer 匹配（单选/多选共用）

function Resolve-ShellListSearchConfig {
    param($SearchConfig)

    $enabled = $true
    $columns = @(0)
    $normalize = 'Alphanumeric'
    $toggleKey = 'Slash'

    if ($null -ne $SearchConfig) {
        if ($SearchConfig.ContainsKey('Enabled')) {
            $enabled = [bool]$SearchConfig.Enabled
        }
        if ($SearchConfig.ContainsKey('Columns') -and $null -ne $SearchConfig.Columns) {
            $columns = @($SearchConfig.Columns | ForEach-Object { [int]$_ })
        }
        if ($SearchConfig.ContainsKey('Normalize') -and -not [string]::IsNullOrWhiteSpace([string]$SearchConfig.Normalize)) {
            $normalize = [string]$SearchConfig.Normalize
        }
        if ($SearchConfig.ContainsKey('LetterToggleKey') -and -not [string]::IsNullOrWhiteSpace([string]$SearchConfig.LetterToggleKey)) {
            $toggleKey = [string]$SearchConfig.LetterToggleKey
        }
    }

    if ($columns.Count -le 0) {
        $columns = @(0)
    }

    if ($toggleKey -eq '/') {
        $toggleKey = 'Slash'
    }

    return @{
        Enabled         = $enabled
        Columns         = @($columns)
        Normalize       = $normalize
        LetterToggleKey = $toggleKey
    }
}

function Normalize-ShellListSearchText {
    param(
        [string]$Text,
        [string]$Normalize = 'Alphanumeric'
    )

    if ([string]::IsNullOrEmpty($Text)) { return '' }

    $value = $Text.ToLowerInvariant()
    if ($Normalize -eq 'Alphanumeric') {
        return ($value -replace '[^a-z0-9]', '')
    }

    return $value
}

function Get-ShellListRowSearchTexts {
    param(
        $Row,
        [int[]]$Columns
    )

    $texts = @()
    if ($null -eq $Row -or $null -eq $Columns) { return @($texts) }

    $cells = @()
    if ($null -ne $Row.PSObject.Properties['Cells']) {
        $cells = @($Row.Cells)
    }

    foreach ($col in @($Columns)) {
        if ($col -ge 0 -and $col -lt $cells.Count) {
            $texts += [string]$cells[$col]
        }
    }

    return @($texts)
}

function Get-ShellListLetterSearchToggleKeyDisplay {
    param([string]$ToggleKey = 'Slash')

    if ($ToggleKey -eq '/') { $ToggleKey = 'Slash' }

    switch ([string]$ToggleKey) {
        'Slash' { return '/' }
        'ControlF' { return 'Ctrl+F' }
        'Grave' { return '·' }
        default { return [string]$ToggleKey }
    }
}

function Test-ShellListLetterSearchSlashKey {
    param($Key)

    if ($null -eq $Key) { return $false }

    if ($Key.Key -eq 'Oem2' -or $Key.Key -eq 'Divide') {
        return $true
    }

    $ch = [string]$Key.KeyChar
    if ([string]::IsNullOrEmpty($ch)) { return $false }

    return ($ch -eq '/') -or ($ch -eq [char]0xFF0F)
}

function Test-ShellListLetterSearchToggleKey {
    param(
        $Key,
        [string]$ToggleKey = 'Slash'
    )

    if ($null -eq $Key) { return $false }

    if ($ToggleKey -eq '/') { $ToggleKey = 'Slash' }

    switch ([string]$ToggleKey) {
        'Slash' {
            return (Test-ShellListLetterSearchSlashKey -Key $Key)
        }
        'ControlF' {
            $hasControl = ($Key.Modifiers -band [ConsoleModifiers]::Control) -ne 0
            if (-not $hasControl) { return $false }
            return ($Key.Key -eq 'F') -or ([string]$Key.KeyChar -match '^[fF]$')
        }
        'Grave' {
            if ($Key.Key -eq 'Oem3') { return $true }
            $ch = [string]$Key.KeyChar
            if ([string]::IsNullOrEmpty($ch)) { return $false }
            return ($ch -eq '`') -or ($ch -eq '~') -or ($ch -eq [char]0x00B7)
        }
        default {
            if ([string]::IsNullOrWhiteSpace([string]$Key.KeyChar)) { return $false }
            return ([string]$Key.KeyChar).ToLowerInvariant() -eq [string]$ToggleKey.ToLowerInvariant()
        }
    }
}

function Get-ShellListEffectiveLetterKeys {
    param(
        [hashtable]$LetterKeys,
        [switch]$LetterInputMode
    )

    if (-not $LetterInputMode) {
        return $LetterKeys
    }

    return @{}
}

function Resolve-ShellListInputBufferIndex {
    param(
        [array]$Rows,
        [string]$Buffer,
        [ValidateSet('Number', 'Letter')]
        [string]$InputMode,
        [hashtable]$SearchConfig,
        [scriptblock]$GetItemDisplayNumber = $null,
        [scriptblock]$TestItemEnabled = $null,
        [scriptblock]$ResolveMenuNumber = $null
    )

    if ([string]::IsNullOrEmpty($Buffer)) { return -1 }
    if ($Rows.Count -le 0) { return -1 }

    if ($InputMode -eq 'Number') {
        if ($Buffer -notmatch '^[0-9]+$') { return -1 }

        $num = [int]$Buffer
        if ($ResolveMenuNumber) {
            return (& $ResolveMenuNumber $Rows $num)
        }

        for ($i = 0; $i -lt $Rows.Count; $i++) {
            if ($TestItemEnabled -and -not (& $TestItemEnabled $Rows[$i] $i)) { continue }
            $displayNumber = if ($GetItemDisplayNumber) {
                & $GetItemDisplayNumber $Rows[$i] $i
            }
            else {
                $i + 1
            }
            if ([int]$displayNumber -eq $num) {
                return $i
            }
        }

        return -1
    }

    $normalizedBuffer = Normalize-ShellListSearchText -Text $Buffer -Normalize $SearchConfig.Normalize
    if ([string]::IsNullOrEmpty($normalizedBuffer)) { return -1 }

    for ($i = 0; $i -lt $Rows.Count; $i++) {
        if ($TestItemEnabled -and -not (& $TestItemEnabled $Rows[$i] $i)) { continue }

        foreach ($text in @(Get-ShellListRowSearchTexts -Row $Rows[$i] -Columns $SearchConfig.Columns)) {
            $normalizedText = Normalize-ShellListSearchText -Text $text -Normalize $SearchConfig.Normalize
            if (-not [string]::IsNullOrEmpty($normalizedText) -and $normalizedText.StartsWith($normalizedBuffer)) {
                return $i
            }
        }
    }

    return -1
}

function Test-ShellListInputBufferPrefixValid {
    param(
        [array]$Rows,
        [string]$Buffer,
        [ValidateSet('Number', 'Letter')]
        [string]$InputMode,
        [hashtable]$SearchConfig,
        [scriptblock]$GetItemDisplayNumber = $null,
        [scriptblock]$TestItemEnabled = $null,
        [scriptblock]$ResolveMenuNumber = $null
    )

    if ([string]::IsNullOrEmpty($Buffer)) { return $false }

    if ($InputMode -eq 'Number') {
        if ($Buffer -notmatch '^[0-9]+$') { return $false }

        for ($i = 0; $i -lt $Rows.Count; $i++) {
            if ($TestItemEnabled -and -not (& $TestItemEnabled $Rows[$i] $i)) { continue }
            $displayNumber = if ($GetItemDisplayNumber) {
                [string](& $GetItemDisplayNumber $Rows[$i] $i)
            }
            else {
                [string]($i + 1)
            }
            if ($displayNumber.StartsWith($Buffer)) {
                return $true
            }
        }

        return $false
    }

    if ($Buffer -notmatch '^[a-zA-Z0-9]+$') { return $false }

    return (Resolve-ShellListInputBufferIndex -Rows $Rows -Buffer $Buffer -InputMode Letter `
        -SearchConfig $SearchConfig -TestItemEnabled $TestItemEnabled) -ge 0
}
