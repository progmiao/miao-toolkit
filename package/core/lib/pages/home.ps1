# 首页：工具列表（MenuSplit 底栏）

function Get-ToolStatusLabel {
    param([string]$Status)

    if ($Status -eq 'notInstalled') {
        return Get-I18n -Key 'common.status.notInstalled'
    }
    return Get-I18n -Key 'common.status.installed'
}

function Get-ToolStatusColor {
    param([string]$Status)

    if ($Status -eq 'notInstalled') {
        return [System.ConsoleColor]::Red
    }
    return [System.ConsoleColor]::Green
}

function Get-ToolkitHomeToolsKey {
    param([array]$Tools)

    if ($Tools.Count -eq 0) { return '' }
    return (($Tools | ForEach-Object { "$($_.id):$($_.number)" }) -join '|')
}

function Get-ToolkitHomeToolStatusMap {
    param(
        [hashtable]$Shell,
        [array]$Tools
    )

    $toolsKey = Get-ToolkitHomeToolsKey -Tools $Tools
    if ($Shell -and $Shell.HomeToolStatusMap -and $Shell.HomeToolStatusKey -eq $toolsKey) {
        return $Shell.HomeToolStatusMap
    }

    $map = @{}
    foreach ($t in $Tools) {
        $map[$t.id] = Get-ToolDependencyStatus -Tool $t
    }

    if ($Shell) {
        $Shell['HomeToolStatusMap'] = $map
        $Shell['HomeToolStatusKey'] = $toolsKey
    }

    return $map
}

function New-HomeToolRowBodySegments {
    param(
        [string]$Cmd,
        [string]$Gap,
        [string]$Name,
        [string]$Status,
        [System.ConsoleColor]$StatusColor,
        [string]$Summary,
        [System.ConsoleColor]$LineColor
    )

    return @(
        @{ Text = $Cmd; Color = $LineColor }
        @{ Text = $Gap; Color = $LineColor }
        @{ Text = $Name; Color = $LineColor }
        @{ Text = $Gap; Color = $LineColor }
        @{ Text = $Status; Color = $StatusColor }
        @{ Text = $Gap; Color = $LineColor }
        @{ Text = $Summary; Color = $LineColor }
    )
}

function Get-ToolkitHomeRowCache {
    param(
        [hashtable]$Shell,
        [array]$Tools,
        [hashtable]$StatusById
    )

    $locale = Get-CurrentLocale
    $toolsKey = Get-ToolkitHomeToolsKey -Tools $Tools
    if ($Shell -and $Shell.HomeRowCache -and $Shell.HomeRowCacheLocale -eq $locale `
        -and $Shell.HomeRowCacheToolsKey -eq $toolsKey) {
        return $Shell.HomeRowCache
    }

    $cols = Get-ToolListColumnWidths
    $colGap = ' ' * (Get-MenuColumnGap)
    $rowCache = New-Object 'object[]' $Tools.Count

    for ($i = 0; $i -lt $Tools.Count; $i++) {
        $tool = $Tools[$i]
        $status = $statusById[$tool.id]
        $lineColor = [System.ConsoleColor]::Gray
        $statusColor = Get-ToolStatusColor -Status $status

        $cmd = Format-MenuTableCell -Text (Get-ToolCommandName -Tool $tool) -Width $cols.command
        $name = Format-MenuTableCell -Text $(if ($tool.displayName) { [string]$tool.displayName } else { [string]$tool.id }) `
            -Width $cols.displayName
        $statusText = Format-MenuTableCell -Text (Get-ToolStatusLabel -Status $status) -Width $cols.status
        $summary = Format-MenuTableCell -Text $(if ($tool.summary) { [string]$tool.summary } else { '' }) `
            -Width $cols.summary

        $bodyPlain = "$cmd$colGap$name$colGap$statusText$colGap$summary"
        $bodySegments = New-HomeToolRowBodySegments -Cmd $cmd -Gap $colGap -Name $name `
            -Status $statusText -StatusColor $statusColor -Summary $summary -LineColor $lineColor

        $rowCache[$i] = [pscustomobject]@{
            Cmd          = $cmd
            Name         = $name
            Status       = $statusText
            StatusColor  = $statusColor
            Summary      = $summary
            BodyPlain    = $bodyPlain
            BodySegments = $bodySegments
            LineColor    = $lineColor
            Enabled      = $true
        }
    }

    if ($Shell) {
        $Shell['HomeRowCache'] = $rowCache
        $Shell['HomeRowCacheLocale'] = $locale
        $Shell['HomeRowCacheToolsKey'] = $toolsKey
        $Shell['HomeColGap'] = $colGap
    }

    return $rowCache
}

function Build-HomeToolListRowSpec {
    param(
        $RowCacheEntry,
        [bool]$Selected,
        [int]$NumWidth,
        [int]$DisplayNumber,
        [string]$Gap
    )

    $num = Format-ListDisplayNumber -Number $DisplayNumber -NumWidth $NumWidth
    $mark = if ($Selected) { '>' } else { ' ' }
    $prefix = " $mark $num$Gap"

    if ($Selected) {
        return @{
            Text       = $prefix + $RowCacheEntry.BodyPlain
            Foreground = [System.ConsoleColor]::Black
            Background = [System.ConsoleColor]::Cyan
        }
    }

    return @{
        Segments          = @(@{ Text = $prefix; Color = $RowCacheEntry.LineColor }) + @($RowCacheEntry.BodySegments)
        DefaultForeground = $RowCacheEntry.LineColor
    }
}

function Write-ToolkitToolListRow {
    param(
        [int]$ScreenRow,
        [int]$DisplayNumber,
        [int]$NumWidth,
        [string]$Gap,
        [bool]$Selected,
        [bool]$Enabled,
        [string]$Cmd,
        [string]$Name,
        [string]$Status,
        [System.ConsoleColor]$StatusColor,
        [string]$Summary,
        [hashtable]$RowSpec = $null
    )

    if (-not $RowSpec) {
        $lineColor = if ($Enabled) { [System.ConsoleColor]::Gray } else { [System.ConsoleColor]::DarkGray }
        $statusFg = if ($Enabled) { $StatusColor } else { [System.ConsoleColor]::DarkGray }
        $bodyPlain = "$Cmd$Gap$Name$Gap$Status$Gap$Summary"
        $RowSpec = Build-HomeToolListRowSpec -RowCacheEntry ([pscustomobject]@{
            BodyPlain    = $bodyPlain
            BodySegments = (New-HomeToolRowBodySegments -Cmd $Cmd -Gap $Gap -Name $Name -Status $Status `
                -StatusColor $statusFg -Summary $Summary -LineColor $lineColor)
            LineColor    = $lineColor
        }) -Selected $Selected -NumWidth $NumWidth -DisplayNumber $DisplayNumber -Gap $Gap
    }

    if (Test-UseConsoleListBufferDraw) {
        try {
            Write-ListRowFromSpec -ScreenRow $ScreenRow -Spec $RowSpec
            return
        }
        catch {
            # 回退 Write-Host
        }
    }

    Prepare-ConsoleRowWrite -Row $ScreenRow
    try { [Console]::SetCursorPosition(0, $ScreenRow) } catch { return }

    $width = Get-SafeWriteLineWidth -Row $ScreenRow
    if ($Selected) {
        $line = [string]$RowSpec.Text
        $lineWidth = Get-DisplayWidth $line
        if ($lineWidth -gt $width) {
            $line = Truncate-DisplayText $line $width
            $lineWidth = Get-DisplayWidth $line
        }
        $padded = $line + (' ' * ($width - $lineWidth))
        Write-Host $padded -NoNewline -ForegroundColor Black -BackgroundColor Cyan
        Set-ConsoleCursorAfterRowWrite -Row $ScreenRow
        return
    }

    $used = 0
    foreach ($seg in $RowSpec.Segments) {
        if ($used -ge $width) { break }
        $partWidth = Get-DisplayWidth $seg.Text
        $remaining = $width - $used
        $text = if ($partWidth -gt $remaining) { Truncate-DisplayText $seg.Text $remaining } else { $seg.Text }
        if ([string]::IsNullOrEmpty($text)) { break }
        Write-Host $text -NoNewline -ForegroundColor $seg.Color
        $used += Get-DisplayWidth $text
    }
    if ($used -lt $width) {
        Write-Host (' ' * ($width - $used)) -NoNewline
    }
    Set-ConsoleCursorAfterRowWrite -Row $ScreenRow
}

function Invoke-HomePage {
    param(
        [array]$Tools,
        [switch]$Preview,
        [hashtable]$Shell
    )

    if ($Shell) {
        $currentLocale = Get-CurrentLocale
        if (-not $Shell.HeaderLocale -or $Shell.HeaderLocale -ne $currentLocale) {
            Update-ToolkitShellBrandHeader -Shell $Shell
            $Shell['HomeRowCache'] = $null
            $Shell['HomeRowCacheLocale'] = $null
            $Shell['HomeRowCacheToolsKey'] = $null
        }

        Initialize-ToolkitShellBodyView -Shell $Shell `
            -SectionTitle (Get-I18n -Key 'page.home.toolList') `
            -FooterTemplate MenuSplit
    }

    $header = New-ToolkitMenuHeader -HideSectionTitle
    $settingsEntry = Get-ShellNavMarker -Action 'settings'
    $helpEntry = Get-ShellNavMarker -Action 'help'

    $statusById = Get-ToolkitHomeToolStatusMap -Shell $Shell -Tools $Tools
    $rowCache = Get-ToolkitHomeRowCache -Shell $Shell -Tools $Tools -StatusById $statusById
    $colGap = if ($Shell -and $Shell.HomeColGap) { $Shell.HomeColGap } else { ' ' * (Get-MenuColumnGap) }
    $numWidth = Get-ToolMenuNumberDisplayWidth -Tools $Tools

    $getDisplayNumber = {
        param($Tool, [int]$Index)
        return [int]$Tool.number
    }

    $resolveNumber = {
        param([array]$Items, [int]$Number)
        return Resolve-ToolMenuNumberIndex -Items $Items -Number $Number
    }

    $getLabel = {
        param($Tool, [int]$Index)
        $part = $rowCache[$Index]
        return "$($part.Cmd)$colGap$($part.Name)$colGap$($part.Status)$colGap$($part.Summary)"
    }

    $buildRowSpecFn = Get-Item -Path function:Build-HomeToolListRowSpec
    $writeListRowFn = Get-Item -Path function:Write-ToolkitToolListRow

    $getListRowSpec = {
        param(
            [int]$Index,
            [bool]$Selected,
            [int]$NumWidth,
            [int]$DisplayNumber,
            [bool]$Enabled
        )

        return (& $buildRowSpecFn -RowCacheEntry $rowCache[$Index] -Selected $Selected `
            -NumWidth $NumWidth -DisplayNumber $DisplayNumber -Gap $colGap)
    }.GetNewClosure()

    $drawListRow = {
        param(
            [int]$ScreenRow,
            $Tool,
            [int]$Index,
            [bool]$Selected,
            [int]$NumWidth,
            [int]$DisplayNumber,
            [bool]$Enabled
        )

        $part = $rowCache[$Index]
        $spec = & $buildRowSpecFn -RowCacheEntry $part -Selected $Selected `
            -NumWidth $NumWidth -DisplayNumber $DisplayNumber -Gap $colGap
        & $writeListRowFn -ScreenRow $ScreenRow -DisplayNumber $DisplayNumber `
            -NumWidth $NumWidth -Gap $colGap -Selected $Selected -Enabled $Enabled `
            -Cmd $part.Cmd -Name $part.Name -Status $part.Status -StatusColor $part.StatusColor `
            -Summary $part.Summary -RowSpec $spec
    }.GetNewClosure()

    return Show-PaginatedMenu -Header $header -Items $Tools -CountLabel (Get-I18n -Key 'common.unit.toolShort') `
        -GetItemLabel $getLabel `
        -LetterKeys @{ s = $settingsEntry; h = $helpEntry } `
        -HideColHeader -FooterLayout Split `
        -GetItemDisplayNumber $getDisplayNumber `
        -ResolveMenuNumber $resolveNumber `
        -NumberDisplayWidth $numWidth `
        -DrawListRow $drawListRow `
        -GetListRowSpec $getListRowSpec `
        -ToolkitShell $Shell
}

function Show-ToolkitMenu {
    param(
        [array]$Tools,
        [switch]$Preview,
        [hashtable]$ToolkitShell = $null
    )

    return Invoke-HomePage -Tools $Tools -Preview:$Preview -Shell $ToolkitShell
}

function Start-ToolkitSession {
    param(
        [array]$Tools,
        [switch]$Preview
    )

    return (Start-ToolkitShellSession -Tools $Tools -Preview:$Preview)
}
