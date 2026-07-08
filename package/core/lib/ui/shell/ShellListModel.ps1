# Shell 列表：行模型、布局、选择结果

function New-ShellListLayout {
    param(
        [int[]]$Widths = @(),
        [string[]]$Headers = @()
    )

    if (@($Widths).Count -eq 0) {
        $cols = Get-ToolListColumnWidths
        $Widths = @([int]$cols.command, [int]$cols.name, 0)
    }

    return @{
        Widths  = @($Widths)
        Headers = @($Headers)
    }
}

function New-ShellListRow {
    param(
        [Parameter(Mandatory)]
        [string]$Id,
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string[]]$Cells,
        $Payload = $null,
        [string]$SearchKey = '',
        [bool]$Enabled = $true,
        [int]$Number = 0,
        [System.ConsoleColor[]]$CellColors = $null
    )

    $row = [ordered]@{
        Id        = [string]$Id
        Cells     = @($Cells | ForEach-Object { [string]$_ })
        Payload   = $Payload
        SearchKey = if ([string]::IsNullOrWhiteSpace($SearchKey)) { [string]$Id } else { [string]$SearchKey }
        Enabled   = [bool]$Enabled
        Number    = [int]$Number
    }
    if ($CellColors) {
        $row['CellColors'] = @($CellColors)
    }
    return [pscustomobject]$row
}

function New-ShellListSelectResult {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Pick', 'back', 'quit', 'sys', 'help', 'update', 'lang', 'install', 'init', 'sysUninstall')]
        [string]$Action,
        [array]$Ids = @(),
        [array]$Payloads = @(),
        [array]$Rows = @()
    )

    return @{
        _kind    = 'shellListSelect'
        Action   = [string]$Action
        Ids      = @($Ids)
        Payloads = @($Payloads)
        Rows     = @($Rows)
    }
}

function Test-ShellListSelectResult {
    param($Item)

    return ($Item -is [hashtable] -and [string]$Item._kind -eq 'shellListSelect')
}

function Get-ShellListSelectNavMarker {
    param($Result)

    if (-not (Test-ShellListSelectResult $Result)) { return $null }
    if ([string]$Result.Action -eq 'Pick') { return $null }
    return (Get-ShellNavMarker -Action ([string]$Result.Action))
}

function Resolve-ShellListLayoutColumnLayout {
    param([hashtable]$Layout)

    $result = @{
        Widths = @($Layout.Widths)
    }
    if ($Layout -and $Layout.ContainsKey('ScrollColumn')) {
        $result['ScrollColumn'] = [int]$Layout.ScrollColumn
    }
    if ($Layout -and $Layout.ContainsKey('ScrollIntervalMs')) {
        $result['ScrollIntervalMs'] = [int]$Layout.ScrollIntervalMs
    }
    return $result
}

function Normalize-ShellListRows {
    param(
        [array]$Rows,
        [hashtable]$Layout
    )

    if (-not $Layout -or -not $Layout.Widths) {
        throw 'Normalize-ShellListRows requires Layout.Widths.'
    }

    $widthCount = @($Layout.Widths).Count
    $normalized = New-Object 'System.Collections.Generic.List[object]'
    $index = 0

    foreach ($row in $Rows) {
        if ($null -eq $row.Cells) {
            throw 'ShellListRow requires Cells.'
        }

        $cells = @($row.Cells | ForEach-Object { [string]$_ })
        if ($cells.Count -ne $widthCount) {
            throw "ShellListRow.Cells count ($($cells.Count)) does not match layout ($widthCount)."
        }

        $number = $index + 1
        if ($null -ne $row.PSObject.Properties['Number'] -and [int]$row.Number -gt 0) {
            $number = [int]$row.Number
        }

        $enabled = $true
        if ($null -ne $row.PSObject.Properties['Enabled']) {
            $enabled = [bool]$row.Enabled
        }

        $searchKey = ''
        if ($null -ne $row.PSObject.Properties['SearchKey']) {
            $searchKey = [string]$row.SearchKey
        }

        $id = ''
        if ($null -ne $row.PSObject.Properties['Id'] -and -not [string]::IsNullOrWhiteSpace([string]$row.Id)) {
            $id = [string]$row.Id
        }
        elseif (-not [string]::IsNullOrWhiteSpace($searchKey)) {
            $id = $searchKey
        }
        else {
            $id = [string]$number
        }

        $payload = $null
        if ($null -ne $row.PSObject.Properties['Payload']) {
            $payload = $row.Payload
        }
        elseif ($null -ne $row.PSObject.Properties['Source']) {
            $payload = $row.Source
        }

        $cellColors = $null
        if ($null -ne $row.PSObject.Properties['CellColors'] -and $row.CellColors) {
            $cellColors = @($row.CellColors)
        }

        $normalized.Add([pscustomobject]@{
            Id        = $id
            Number    = $number
            Cells     = $cells
            Payload   = $payload
            SearchKey = $searchKey
            Enabled   = $enabled
            CellColors = $cellColors
        })
        $index++
    }

    return @($normalized.ToArray())
}

function Get-ShellListRowsCacheKey {
    param([array]$Rows)

    if ($Rows.Count -eq 0) { return '' }
    return (($Rows | ForEach-Object {
        $payloadKey = if ($null -ne $_.Payload) {
            if ($_.Payload.command) { [string]$_.Payload.command }
            elseif ($_.Payload.id) { [string]$_.Payload.id }
            else { [string]$_.Id }
        }
        else { [string]$_.Id }
        $key = if ($null -ne $_.PSObject.Properties['SearchKey']) { [string]$_.SearchKey } else { '' }
        $colorKey = ''
        if ($null -ne $_.PSObject.Properties['CellColors'] -and $_.CellColors) {
            $colorKey = (($_.CellColors | ForEach-Object { [string][int]$_ }) -join ',')
        }
        "$($_.Number):${key}:$($_.Cells -join '|'):$($_.Enabled):${colorKey}:$payloadKey"
    }) -join ';')
}

function Test-ShellListRowEnabled {
    param($Row, [int]$Index)

    if ($null -eq $Row) { return $false }
    if ($null -eq $Row.PSObject.Properties['Enabled']) { return $true }
    return [bool]$Row.Enabled
}

function Get-ShellListRowDisplayNumber {
    param(
        $Row,
        [int]$Index
    )

    if ($null -eq $Row) { return $Index + 1 }
    if ($null -ne $Row.PSObject.Properties['Number'] -and [int]$Row.Number -gt 0) {
        return [int]$Row.Number
    }
    return $Index + 1
}

function Resolve-ShellListRowNumberIndex {
    param(
        [array]$Rows,
        [int]$Number
    )

    if ($Number -lt 1) { return -1 }
    for ($i = 0; $i -lt $Rows.Count; $i++) {
        if ([int](Get-ShellListRowDisplayNumber -Row $Rows[$i] -Index $i) -eq $Number) {
            return $i
        }
    }
    return -1
}

function Get-ShellListRowSearchKey {
    param(
        $Row,
        [int]$Index
    )

    if ($null -eq $Row) { return '' }
    if ($null -ne $Row.PSObject.Properties['SearchKey'] -and -not [string]::IsNullOrEmpty([string]$Row.SearchKey)) {
        return [string]$Row.SearchKey
    }
    return [string](Get-ShellListRowDisplayNumber -Row $Row -Index $Index)
}

function Normalize-ShellListSearchKeyDigits {
    param([string]$Text)

    if ([string]::IsNullOrEmpty($Text)) { return '' }
    return ($Text -replace '\D', '')
}

function Test-ShellListSearchKeyPrefixMatch {
    param(
        [string]$SearchKey,
        [string]$Buffer,
        [switch]$DigitsOnly
    )

    if ([string]::IsNullOrEmpty($Buffer)) { return $true }

    if ($DigitsOnly) {
        if ($Buffer -notmatch '^[0-9]+$') { return $false }
        return (Normalize-ShellListSearchKeyDigits $SearchKey).StartsWith($Buffer)
    }

    if ($Buffer -notmatch '^[0-9.]+$') { return $false }
    return $SearchKey.StartsWith($Buffer)
}

function Resolve-ShellListRowSearchKeyPrefixIndex {
    param(
        [array]$Rows,
        [string]$Prefix,
        [scriptblock]$TestItemEnabled = $null,
        [switch]$SearchKeyDigitsOnly
    )

    if ([string]::IsNullOrEmpty($Prefix)) { return -1 }
    for ($i = 0; $i -lt $Rows.Count; $i++) {
        if ($TestItemEnabled -and -not (& $TestItemEnabled $Rows[$i] $i)) { continue }
        $key = Get-ShellListRowSearchKey -Row $Rows[$i] -Index $i
        if (Test-ShellListSearchKeyPrefixMatch -SearchKey $key -Buffer $Prefix -DigitsOnly:$SearchKeyDigitsOnly) {
            return $i
        }
    }
    return -1
}

function ConvertTo-ShellListSelectResult {
    param(
        $RawResult,
        [ValidateSet('Single', 'Multi')]
        [string]$Mode
    )

    if (Test-ShellNavMarker $RawResult) {
        return (New-ShellListSelectResult -Action ([string]$RawResult.action))
    }

    if ($Mode -eq 'Single') {
        if (-not $RawResult) {
            return (New-ShellListSelectResult -Action 'back')
        }
        $row = $RawResult
        return (New-ShellListSelectResult -Action 'Pick' `
            -Ids @([string]$row.Id) `
            -Payloads @($row.Payload) `
            -Rows @($row))
    }

    if ($null -eq $RawResult) {
        return (New-ShellListSelectResult -Action 'back')
    }

    $pickedRows = @($RawResult)
    $ids = @($pickedRows | ForEach-Object { [string]$_.Id })
    $payloads = @($pickedRows | ForEach-Object { $_.Payload })
    return (New-ShellListSelectResult -Action 'Pick' -Ids $ids -Payloads $payloads -Rows $pickedRows)
}

function Format-ShellListCatalogHeaders {
    param(
        [hashtable]$Layout
    )

    if (-not $Layout -or -not $Layout.Headers) { return '' }
    $headers = @($Layout.Headers | ForEach-Object { [string]$_ })
    if ($headers.Count -eq 0) { return '' }
    if (@($headers | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -eq 0) {
        return ''
    }
    return (($headers | ForEach-Object {
        if ([string]::IsNullOrWhiteSpace($_)) { '' } else { $_ }
    }) -join ' | ')
}

function Clear-ShellListCache {
    param(
        [hashtable]$Shell,
        [string]$CacheKey
    )

    Clear-ShellSingleSelectListCache -Shell $Shell -CacheKey $CacheKey
    Clear-ShellMultiSelectListCache -Shell $Shell -CacheKey $CacheKey
}
