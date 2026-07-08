# Shell 列表：统一单选/多选入口

function Invoke-ToolkitShellList {
    param(
        [Parameter(Mandatory, Position = 0)]
        [hashtable]$Config
    )

    if (-not $Config -or $Config.Count -lt 1) {
        throw 'Invoke-ToolkitShellList requires a config hashtable.'
    }

    foreach ($requiredKey in @('Mode', 'Shell', 'SectionTitle', 'CacheKey', 'Rows')) {
        if (-not $Config.ContainsKey($requiredKey)) {
            throw "Invoke-ToolkitShellList requires Config.$requiredKey."
        }
    }

    $Mode = [string]$Config['Mode']
    $Shell = $Config['Shell']
    $SectionTitle = [string]$Config['SectionTitle']
    $CacheKey = [string]$Config['CacheKey']
    $Rows = @($Config['Rows'])
    $Layout = if ($Config.ContainsKey('Layout')) { $Config['Layout'] } else { $null }
    $Toolbar = if ($Config.ContainsKey('Toolbar')) { $Config['Toolbar'] } else { $null }
    $CountLabel = if ($Config.ContainsKey('CountLabel')) { [string]$Config['CountLabel'] } else { '' }
    $KeyColumn = if ($Config.ContainsKey('KeyColumn')) { [string]$Config['KeyColumn'] } else { 'Number' }
    $SearchKeyWidth = if ($Config.ContainsKey('SearchKeyWidth')) { [int]$Config['SearchKeyWidth'] } else { 0 }
    $Search = if ($Config.ContainsKey('Search')) { $Config['Search'] } else { $null }
    $SkipBodyInit = [bool]($Config.ContainsKey('SkipBodyInit') -and $Config['SkipBodyInit'])
    $InitialCatalogLine = if ($Config.ContainsKey('InitialCatalogLine')) { [string]$Config['InitialCatalogLine'] } else { '' }
    $InitialFlashMessage = if ($Config.ContainsKey('InitialFlashMessage')) { [string]$Config['InitialFlashMessage'] } else { '' }
    $FlashKeys = if ($Config.ContainsKey('FlashKeys')) { $Config['FlashKeys'] } else { $null }
    $LoadingProgress = if ($Config.ContainsKey('LoadingProgress')) { $Config['LoadingProgress'] } else { $null }

    if ($Mode -notin @('Single', 'Multi')) {
        throw "Invoke-ToolkitShellList Config.Mode must be Single or Multi (got: $Mode)."
    }

    if (-not $Toolbar) {
        $Toolbar = New-ShellSystemToolbarConfig
    }
    if (-not $Layout) {
        $Layout = New-ShellListLayout
    }
    if ([string]::IsNullOrWhiteSpace($CountLabel)) {
        $CountLabel = Get-I18n -Key 'common.piece'
    }

    $flashNothingSelectedKey = if ($FlashKeys -and $FlashKeys.NothingSelected) {
        [string]$FlashKeys.NothingSelected
    }
    else { 'common.nothingSelected' }
    $flashItemDisabledKey = if ($FlashKeys -and $FlashKeys.ItemDisabled) {
        [string]$FlashKeys.ItemDisabled
    }
    else { 'message.disabledItem' }

    Sync-MiaoLocaleFromShell -Shell $Shell

    $hideNumberColumn = ($Mode -eq 'Multi')
    $numWidthPreview = 0
    if (-not $hideNumberColumn) {
        $maxNumberPreview = 0
        for ($i = 0; $i -lt $Rows.Count; $i++) {
            $n = [int](Get-ShellListRowDisplayNumber -Row $Rows[$i] -Index $i)
            if ($n -gt $maxNumberPreview) { $maxNumberPreview = $n }
        }
        if ($maxNumberPreview -lt $Rows.Count) { $maxNumberPreview = $Rows.Count }
        if ($maxNumberPreview -lt 1) { $maxNumberPreview = 1 }
        $numWidthPreview = Get-ListNumberDisplayWidth -MaxNumber $maxNumberPreview
    }

    $resolvedLayout = Resolve-ShellListLayout -Shell $Shell -Layout $Layout -NumWidth $numWidthPreview `
        -Mode $Mode -KeyColumn $KeyColumn -SearchKeyWidth $SearchKeyWidth -HideNumberColumn:$hideNumberColumn
    $columnLayout = Resolve-ShellListLayoutColumnLayout -Layout $resolvedLayout
    $listScrollConfig = Resolve-ShellListScrollConfig -Layout $resolvedLayout
    $normalized = @(Normalize-ShellListRows -Rows $Rows -Layout $resolvedLayout)

    $onCacheProgress = $null
    if ($LoadingProgress) {
        $progressRef = $LoadingProgress
        $onCacheProgress = {
            param([int]$Index, [int]$Total)
            $cap = [Math]::Max(1, $Total - 1)
            $pct = 88 + [int](7 * $Index / $cap)
            if (Get-Command Update-ToolkitShellListLoadingProgress -ErrorAction SilentlyContinue) {
                Update-ToolkitShellListLoadingProgress -Shell $Shell -Progress $progressRef -TargetPercent $pct
            }
        }.GetNewClosure()
        if (Get-Command Update-ToolkitShellListLoadingProgress -ErrorAction SilentlyContinue) {
            Update-ToolkitShellListLoadingProgress -Shell $Shell -Progress $LoadingProgress -TargetPercent 82
        }
        if ($Mode -eq 'Multi') {
            Initialize-ShellMultiSelectListDependencies
            $null = Get-ShellMultiSelectListRowCache -Shell $Shell -CacheKey $CacheKey `
                -Rows $normalized -ColumnLayout $columnLayout -OnProgress $onCacheProgress
        }
        else {
            $null = Get-ShellSingleSelectListRowCache -Shell $Shell -CacheKey $CacheKey `
                -Rows $normalized -ColumnLayout $columnLayout -OnProgress $onCacheProgress
        }
        if (Get-Command Update-ToolkitShellListLoadingProgress -ErrorAction SilentlyContinue) {
            Update-ToolkitShellListLoadingProgress -Shell $Shell -Progress $LoadingProgress -TargetPercent 96
        }
    }

    $catalogLine = [string]$InitialCatalogLine
    if ([string]::IsNullOrWhiteSpace($catalogLine)) {
        $headerLine = Format-ShellListCatalogHeaders -Layout $resolvedLayout
        if (-not [string]::IsNullOrWhiteSpace($headerLine)) {
            $catalogLine = $headerLine
        }
    }

    if (-not $SkipBodyInit) {
        Set-ToolkitShellBodyCatalogLine -Shell $Shell -CatalogLine $catalogLine
        Initialize-ToolkitShellBodyView -Shell $Shell -SectionTitle $SectionTitle `
            -FooterTemplate ListWithToolbar
    }
    else {
        Set-ToolkitShellBodyCatalogLine -Shell $Shell -CatalogLine $catalogLine
        Render-ToolkitShellCatalogRow -Shell $Shell
    }

    if ($LoadingProgress -and (Get-Command Update-ToolkitShellListLoadingProgress -ErrorAction SilentlyContinue)) {
        Update-ToolkitShellListLoadingProgress -Shell $Shell -Progress $LoadingProgress -TargetPercent 98
    }

    if ($Mode -eq 'Single') {
        $raw = Invoke-ToolkitShellListSingleCore -Shell $Shell -CacheKey $CacheKey `
            -NormalizedRows $normalized -ColumnLayout $columnLayout -ToolbarConfig $Toolbar `
            -CountLabel $CountLabel -InitialCatalogLine $catalogLine `
            -InitialFlashMessage $InitialFlashMessage -SearchConfig $Search `
            -ListScrollConfig $listScrollConfig
        return (ConvertTo-ShellListSelectResult -RawResult $raw -Mode Single)
    }

    Initialize-ShellMultiSelectListDependencies
    $raw = Invoke-ToolkitShellListMultiCore -Shell $Shell -CacheKey $CacheKey `
        -NormalizedRows $normalized -ColumnLayout $columnLayout -ToolbarConfig $Toolbar `
        -CountLabel $CountLabel -KeyColumn $KeyColumn -SearchKeyWidth $SearchKeyWidth `
        -SearchConfig $Search -FlashNothingSelectedKey $flashNothingSelectedKey `
        -FlashItemDisabledKey $flashItemDisabledKey -HideNumberColumn:$hideNumberColumn `
        -ListScrollConfig $listScrollConfig
    return (ConvertTo-ShellListSelectResult -RawResult $raw -Mode Multi)
}

function Invoke-ToolkitShellListSingleCore {
    param(
        [hashtable]$Shell,
        [string]$CacheKey,
        [array]$NormalizedRows,
        [hashtable]$ColumnLayout,
        [hashtable]$ToolbarConfig,
        [string]$CountLabel,
        [string]$InitialCatalogLine,
        [string]$InitialFlashMessage,
        [hashtable]$SearchConfig = $null,
        [hashtable]$ListScrollConfig = $null
    )

    $header = New-ToolkitMenuHeader -HideSectionTitle
    $built = Get-ShellSingleSelectListRowCache -Shell $Shell -CacheKey $CacheKey `
        -Rows $NormalizedRows -ColumnLayout $ColumnLayout
    $rowCache = $built.RowCache
    $gapField = "${CacheKey}ListColGap"
    $colGap = if ($Shell[$gapField]) { $Shell[$gapField] } else { $built.ColGap }

    $maxNumber = 0
    for ($i = 0; $i -lt $NormalizedRows.Count; $i++) {
        $n = [int](Get-ShellListRowDisplayNumber -Row $NormalizedRows[$i] -Index $i)
        if ($n -gt $maxNumber) { $maxNumber = $n }
    }
    if ($maxNumber -lt 1) { $maxNumber = $NormalizedRows.Count }
    $numWidth = Get-ListNumberDisplayWidth -MaxNumber $maxNumber

    $contentMetrics = Get-ToolkitShellLayoutLineMetrics -Shell $Shell
    $scrollConfig = if ($ListScrollConfig) { $ListScrollConfig } else { Resolve-ShellListScrollConfig -Layout $null }
    $marqueeOffset = 0
    $marqueeLastTick = [Environment]::TickCount
    $getMarqueeOffset = { return $marqueeOffset }.GetNewClosure()
    $handlers = New-ShellSingleSelectListDrawHandlers -RowCache $rowCache -ColGap $colGap `
        -LayoutLineWidth ([int]$contentMetrics.EndColumn) `
        -LayoutStartColumn ([int]$contentMetrics.StartColumn) `
        -ScrollColumn ([int]$scrollConfig.ScrollColumn) -GetMarqueeOffset $getMarqueeOffset
    if (-not $handlers['GetLabel'] -or -not $handlers['DrawListRow']) {
        throw 'Invoke-ToolkitShellList: single list draw handlers are not available.'
    }

    $getDisplayNumber = {
        param($Row, [int]$Index)
        Get-ShellListRowDisplayNumber -Row $Row -Index $Index
    }.GetNewClosure()

    $resolveMenuNumber = {
        param([array]$Items, [int]$Number)
        Resolve-ShellListRowNumberIndex -Rows $Items -Number $Number
    }.GetNewClosure()

    $testRowEnabled = {
        param($Row, [int]$Index)
        Test-ShellListRowEnabled -Row $Row -Index $Index
    }.GetNewClosure()

    $letterKeys = if ($ToolbarConfig.LetterKeys) { $ToolbarConfig.LetterKeys } else { @{} }

    return Show-PaginatedMenu -Header $header -Items $NormalizedRows -CountLabel $CountLabel `
        -GetItemLabel $handlers['GetLabel'] `
        -TestItemEnabled $testRowEnabled `
        -HideColHeader -FooterLayout Split `
        -GetItemDisplayNumber $getDisplayNumber `
        -ResolveMenuNumber $resolveMenuNumber `
        -NumberDisplayWidth $numWidth `
        -DrawListRow $handlers['DrawListRow'] `
        -GetListRowSpec $handlers['GetListRowSpec'] `
        -MenuSplitActionSegments @($ToolbarConfig.Segments) `
        -LetterKeys $letterKeys `
        -ToolkitShell $Shell `
        -AllowBack:($ToolbarConfig.AllowBack) `
        -CompactNavStatus `
        -AllowSpaceConfirm `
        -InitialCatalogLine $InitialCatalogLine `
        -InitialFlashMessage $InitialFlashMessage -SearchConfig $SearchConfig `
        -ListScrollConfig $scrollConfig -MarqueeOffset ([ref]$marqueeOffset) `
        -MarqueeLastTick ([ref]$marqueeLastTick) -MarqueeRowCache $rowCache
}

function Invoke-ToolkitShellListMultiCore {
    param(
        [hashtable]$Shell,
        [string]$CacheKey,
        [array]$NormalizedRows,
        [hashtable]$ColumnLayout,
        [hashtable]$ToolbarConfig,
        [string]$CountLabel,
        [ValidateSet('Number', 'SearchKey')]
        [string]$KeyColumn,
        [int]$SearchKeyWidth,
        [string]$FlashNothingSelectedKey,
        [string]$FlashItemDisabledKey,
        [hashtable]$SearchConfig = $null,
        [switch]$HideNumberColumn,
        [hashtable]$ListScrollConfig = $null
    )

    $header = New-ToolkitMenuHeader -HideSectionTitle
    $built = Get-ShellMultiSelectListRowCache -Shell $Shell -CacheKey $CacheKey `
        -Rows $NormalizedRows -ColumnLayout $ColumnLayout
    $rowCache = $built.RowCache
    $gapField = "${CacheKey}MultiListColGap"
    $colGap = if ($Shell[$gapField]) { $Shell[$gapField] } else { $built.ColGap }

    $null = Get-ShellMultiSelectCheckedSet -Shell $Shell -CacheKey $CacheKey

    $getDisplayNumber = {
        param($Row, [int]$Index)
        Get-ShellListRowDisplayNumber -Row $Row -Index $Index
    }.GetNewClosure()

    $getSearchKey = {
        param($Row, [int]$Index)
        Get-ShellListRowSearchKey -Row $Row -Index $Index
    }.GetNewClosure()

    $resolveMenuNumber = {
        param([array]$Items, [int]$Number)
        Resolve-ShellListRowNumberIndex -Rows $Items -Number $Number
    }.GetNewClosure()

    $testRowEnabled = {
        param($Row, [int]$Index)
        Test-ShellListRowEnabled -Row $Row -Index $Index
    }.GetNewClosure()

    $letterKeys = if ($ToolbarConfig.LetterKeys) { $ToolbarConfig.LetterKeys } else { @{} }

    $numberWidth = 0
    if (-not $HideNumberColumn) {
        $maxNumber = 0
        for ($i = 0; $i -lt $NormalizedRows.Count; $i++) {
            $n = [int](Get-ShellListRowDisplayNumber -Row $NormalizedRows[$i] -Index $i)
            if ($n -gt $maxNumber) { $maxNumber = $n }
        }
        if ($maxNumber -lt 1) { $maxNumber = $NormalizedRows.Count }
        $numberWidth = Get-ListNumberDisplayWidth -MaxNumber $maxNumber
    }

    $picked = Show-ShellMultiSelectListMenu -Header $header -Items $NormalizedRows -CountLabel $CountLabel `
        -TestItemEnabled $testRowEnabled -GetItemDisplayNumber $getDisplayNumber `
        -ResolveMenuNumber $resolveMenuNumber -NumberDisplayWidth $numberWidth `
        -RowCache $rowCache -ColGap $colGap -CheckedCacheKey $CacheKey `
        -MenuSplitActionSegments @($ToolbarConfig.Segments) -LetterKeys $letterKeys `
        -ToolkitShell $Shell -AllowBack:($ToolbarConfig.AllowBack) `
        -FlashNothingSelectedKey $FlashNothingSelectedKey -FlashItemDisabledKey $flashItemDisabledKey `
        -SearchConfig $SearchConfig -HideNumberColumn:$HideNumberColumn

    if (Test-ShellNavMarker $picked) { return $picked }
    if ($null -eq $picked) { return $null }
    return @($picked)
}
