# 列表 UI 默认布局（编号规则、列宽、间距；非 manifest 配置）

$script:ListNumberMinDisplayWidth = 2
$script:ListPageNumberMinDisplayWidth = 2
$script:ToolkitListColumnGap = 2
$script:ToolkitCliCommandPrefix = 'miao'
$script:ToolkitBrandSeparatorExtra = 8
$script:ToolkitToolListColumnWidths = @{
    command     = 12
    name        = 18
    description = 32
}
$script:ShellSingleSelectListLeadingSpaces = 2

function Get-ShellSingleSelectListLeadingSpaces {
    $n = [int]$script:ShellSingleSelectListLeadingSpaces
    if ($n -lt 1) { return 1 }
    return $n
}

function Get-ListNumberDisplayWidth {
    param(
        [int]$TotalCount = 0,
        [int]$MaxNumber = 0
    )

    $value = if ($MaxNumber -gt 0) { $MaxNumber } elseif ($TotalCount -gt 0) { $TotalCount } else { 1 }
    $countDigits = ([string]$value).Length
    return [Math]::Max($script:ListNumberMinDisplayWidth, $countDigits)
}

function Format-ListDisplayNumber {
    param(
        [int]$Number,
        [int]$NumWidth
    )

    if ($NumWidth -lt 1) { $NumWidth = $script:ListNumberMinDisplayWidth }
    return $Number.ToString().PadLeft($NumWidth, '0')
}

function Format-ListTotalCountDisplay {
    param([int]$Count)

    $width = Get-ListNumberDisplayWidth -TotalCount $Count -MaxNumber $Count
    return $Count.ToString().PadLeft($width, '0')
}

function Resolve-ListNumberIndexDefault {
    param(
        [array]$Items,
        [int]$Number
    )

    if ($Number -lt 1) { return -1 }
    $idx = $Number - 1
    if ($idx -ge $Items.Count) { return -1 }
    return $idx
}

function Get-ListItemDisplayNumberDefault {
    param(
        $Item,
        [int]$Index
    )

    return $Index + 1
}
