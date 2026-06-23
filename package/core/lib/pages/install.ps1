# 依赖安装/更新专页（Space 多选，Enter 确认，Esc 返回）

function Get-InstallPageTools {
    param(
        [array]$Tools,
        [string[]]$FocusToolIds = @()
    )

    $items = @(Get-ToolsWithExternalDeps -Tools $Tools -ToolIds @())
    if ($FocusToolIds.Count -eq 0) {
        return $items
    }

    $focusSet = @{}
    foreach ($id in $FocusToolIds) { $focusSet[[string]$id] = $true }

    $focused = @($items | Where-Object { $focusSet.ContainsKey([string]$_.command) })
    $rest = @($items | Where-Object { -not $focusSet.ContainsKey([string]$_.command) })
    return @($focused + $rest)
}

function Get-InstallPageToolStatusInfo {
    param($Tool)

    if (-not (Test-ToolDepInstalled $Tool)) {
        return @{
            needsAction = $true
            tag         = (Get-I18n -Key 'common.notInstalled')
            tagColor    = [System.ConsoleColor]::Red
        }
    }

    $recordedVersion = $null
    foreach ($dep in @(Get-ToolDependencyPackages -Tool $Tool)) {
        $depId = Get-DependencyRecordId -Dependency $dep
        $recordedVersion = Get-GlobalDepRecordedVersion -Fingerprint $depId
        if ($recordedVersion) { break }
    }

    $displayVersion = if ($recordedVersion) { "v$recordedVersion" } else { '' }

    if (Test-ToolDependencyNeedsUpgrade -Tool $Tool) {
        $latest = $null
        foreach ($dep in @(Get-ToolDependencyPackages -Tool $Tool)) {
            if (Test-DependencyVersionPolicyIsLatest -Dependency $dep) {
                if ($dep.install -and $dep.install.packageId) {
                    $latest = Get-WingetPackageLatestVersion -PackageId ([string]$dep.install.packageId)
                }
            }
            else {
                $latest = (Get-DependencyVersionPolicy -Dependency $dep).Trim()
            }
            if ($latest) { break }
        }

        $tag = if ($latest) {
            Get-I18n -Key 'page.install.pageStatusUpdateAvailable' -Vars @{
                current = $displayVersion
                latest  = "v$latest"
            }
        }
        else {
            Get-I18n -Key 'page.install.pageStatusUpdateAvailableShort'
        }

        return @{
            needsAction = $true
            tag         = $tag
            tagColor    = [System.ConsoleColor]::Yellow
        }
    }

    $tag = if ($displayVersion) {
        Get-I18n -Key 'page.install.pageStatusInstalled' -Vars @{ version = $displayVersion }
    }
    else {
        Get-I18n -Key 'common.installed'
    }

    return @{
        needsAction = $false
        tag         = $tag
        tagColor    = [System.ConsoleColor]::Green
    }
}

function Format-InstallToolLabel {
    param(
        $Tool,
        [bool]$Checked
    )

    $status = Get-InstallPageToolStatusInfo -Tool $Tool
    $mark = if ($Checked) { '[x]' } else { '[ ]' }
    $name = [string]$Tool.name
  return "$mark  $name  [$($status.tag)]"
}

function Show-InstallMultiSelectMenu {
    param(
        [hashtable]$Shell,
        [array]$Tools,
        [string[]]$FocusToolIds = @(),
        [switch]$SelectAll
    )

    $items = @(Get-InstallPageTools -Tools $Tools -FocusToolIds $FocusToolIds)
    if ($items.Count -eq 0) {
        Write-FixedLine $Shell.Layout.ListStartRow (Get-I18n -Key 'page.install.noTargets') -Color DarkGray
        Start-Sleep -Milliseconds 600
        return (Get-ShellNavMarker -Action 'back')
    }

    $layout = $Shell.Layout
    $pageSize = $layout.ListViewportHeight
    if ($pageSize -le 0) { $pageSize = Get-MenuPageSize }

    $selectedSet = New-Object 'System.Collections.Generic.HashSet[int]'
    $pageIndex = 0
    $selectedIndex = 0
    $listScrollOffset = 0
    $flashMessage = ''
    $pageCount = [Math]::Max(1, [Math]::Ceiling($items.Count / [double]$pageSize))
    $numWidth = Get-MenuNumberWidth -TotalCount $items.Count

    if ($SelectAll) {
        for ($i = 0; $i -lt $items.Count; $i++) {
            $null = $selectedSet.Add($i)
        }
    }
    elseif ($FocusToolIds.Count -gt 0) {
        $focusId = [string]$FocusToolIds[0]
        for ($i = 0; $i -lt $items.Count; $i++) {
            if ([string]$items[$i].command -eq $focusId) {
                $selectedIndex = $i
                $pageIndex = [Math]::Floor($i / [double]$pageSize)
                break
            }
        }
    }

    $header = New-ToolkitMenuHeader -SectionTitle (Get-I18n -Key 'page.toolboxDeps.install.pageTitle') -HideSectionTitle
    $renderFooter = New-ShellSystemToolbarFooterRenderer -Shell $Shell `
        -ToolbarConfig (New-ShellSystemToolbarConfig -HideSystem)

    function Redraw-InstallList {
        param([int]$OldIndex = -1)

        $pageStart = $pageIndex * $pageSize
        $visibleCount = [Math]::Min($pageSize, $items.Count - $pageStart)
        $firstVisible = $pageStart + $listScrollOffset
        $lastVisible = [Math]::Min($pageStart + $visibleCount - 1, $items.Count - 1)

        for ($row = 0; $row -lt $visibleCount; $row++) {
            $idx = $pageStart + $listScrollOffset + $row
            if ($idx -gt $lastVisible) { break }
            if ($idx -lt 0 -or $idx -ge $items.Count) { continue }

            $tool = $items[$idx]
            $checked = $selectedSet.Contains($idx)
            $label = Format-InstallToolLabel -Tool $tool -Checked $checked
            $status = Get-InstallPageToolStatusInfo -Tool $tool
            $lineColor = if ($idx -eq $selectedIndex) { [System.ConsoleColor]::White } else { [System.ConsoleColor]::Gray }
            $num = ('{0,#' + "$numWidth" + '}' -f ($idx + 1))
            $prefix = if ($idx -eq $selectedIndex) { '>' } else { ' ' }
            $line = "$prefix$num  $label"

            Write-FixedLine ($layout.ListStartRow + $row) $line -Color $lineColor
        }
    }

    Set-MenuListScrollOffset -ScrollOffset ([ref]$listScrollOffset) `
        -SelectedIndex $selectedIndex -PageIndex $pageIndex -PageSize $pageSize `
        -ItemCount $items.Count -ViewportHeight $layout.ListViewportHeight

    Enter-ConsoleDrawBatch
    Redraw-InstallList
    & $renderFooter @{ FlashMessage = (Get-InstallPageFooterHint) }
    Complete-ConsoleDrawBatch -ToolkitShell $Shell

    try {
        while ($true) {
            $confirmResult = Read-ShellExitIfActive -Shell $Shell
            if ($confirmResult -eq 'exitCancel') { continue }
            if ($confirmResult -eq 'exitConfirmed') {
                return (Get-ShellNavMarker -Action 'quit')
            }

            $oldIndex = $selectedIndex
            $oldPage = $pageIndex
            $oldScroll = $listScrollOffset
            $flashMessage = ''

            $key = [Console]::ReadKey($true)

            if ($key.KeyChar -match '^[qQ]$') {
                return (Get-ShellNavMarker -Action 'back')
            }
            else {
                switch ($key.Key) {
                    'LeftArrow' {
                        if ($pageCount -gt 1) {
                            if ($pageIndex -gt 0) { $pageIndex-- }
                            else { $pageIndex = $pageCount - 1 }
                            $selectedIndex = [Math]::Min($pageIndex * $pageSize, $items.Count - 1)
                            $listScrollOffset = 0
                            Set-MenuListScrollOffset -ScrollOffset ([ref]$listScrollOffset) `
                                -SelectedIndex $selectedIndex -PageIndex $pageIndex -PageSize $pageSize `
                                -ItemCount $items.Count -ViewportHeight $layout.ListViewportHeight
                        }
                    }
                    'RightArrow' {
                        if ($pageCount -gt 1) {
                            if ($pageIndex -lt ($pageCount - 1)) { $pageIndex++ }
                            else { $pageIndex = 0 }
                            $selectedIndex = [Math]::Min($pageIndex * $pageSize, $items.Count - 1)
                            $listScrollOffset = 0
                            Set-MenuListScrollOffset -ScrollOffset ([ref]$listScrollOffset) `
                                -SelectedIndex $selectedIndex -PageIndex $pageIndex -PageSize $pageSize `
                                -ItemCount $items.Count -ViewportHeight $layout.ListViewportHeight
                        }
                    }
                    'UpArrow' {
                        if ($selectedIndex -gt 0) {
                            $selectedIndex--
                            $newPage = [Math]::Floor($selectedIndex / [double]$pageSize)
                            if ($newPage -ne $pageIndex) {
                                $pageIndex = $newPage
                                $listScrollOffset = 0
                            }
                            Set-MenuListScrollOffset -ScrollOffset ([ref]$listScrollOffset) `
                                -SelectedIndex $selectedIndex -PageIndex $pageIndex -PageSize $pageSize `
                                -ItemCount $items.Count -ViewportHeight $layout.ListViewportHeight
                        }
                    }
                    'DownArrow' {
                        if ($selectedIndex -lt ($items.Count - 1)) {
                            $selectedIndex++
                            $newPage = [Math]::Floor($selectedIndex / [double]$pageSize)
                            if ($newPage -ne $pageIndex) {
                                $pageIndex = $newPage
                                $listScrollOffset = 0
                            }
                            Set-MenuListScrollOffset -ScrollOffset ([ref]$listScrollOffset) `
                                -SelectedIndex $selectedIndex -PageIndex $pageIndex -PageSize $pageSize `
                                -ItemCount $items.Count -ViewportHeight $layout.ListViewportHeight
                        }
                    }
                    'Spacebar' {
                        if ($selectedSet.Contains($selectedIndex)) {
                            [void]$selectedSet.Remove($selectedIndex)
                        }
                        else {
                            [void]$selectedSet.Add($selectedIndex)
                        }
                    }
                    'Enter' {
                        $targetIndexes = @()
                        if ($selectedSet.Count -gt 0) {
                            $targetIndexes = @($selectedSet | Sort-Object)
                        }
                        else {
                            $targetIndexes = @($selectedIndex)
                        }

                        $actionable = @()
                        foreach ($idx in $targetIndexes) {
                            $tool = $items[$idx]
                            $info = Get-InstallPageToolStatusInfo -Tool $tool
                            if ($info.needsAction) {
                                $actionable += $tool
                            }
                        }

                        if ($actionable.Count -eq 0) {
                            $flashMessage = Get-I18n -Key 'page.install.pageNothingToDo'
                            break
                        }

                        $batch = Start-ToolkitDepBatchOperation -Tools $actionable -Shell $Shell `
                            -Intent install
                        if (Test-ShellNavMarker $batch) {
                            return $batch
                        }
                        $failed = @($batch.FailedToolIds)

                        [void]$selectedSet.Clear()
                        Clear-DepsStateCache
                        Initialize-ToolkitShellBodyView -Shell $Shell `
                            -SectionTitle (Get-I18n -Key 'page.install.pageTitle') `
                            -FooterTemplate SystemToolbarOnly
                        $flashMessage = if ($failed.Count -gt 0) {
                            Get-I18n -Key 'page.install.batchFailed' -Vars @{ tools = ($failed -join ', ') }
                        }
                        else {
                            Get-I18n -Key 'page.install.batchComplete'
                        }

                        Enter-ConsoleDrawBatch
                        Redraw-InstallList
                        & $renderFooter @{ FlashMessage = $flashMessage }
                        Complete-ConsoleDrawBatch -ToolkitShell $Shell
                        continue
                    }
                    'Escape' {
                        Request-ShellExit -Shell $Shell
                        continue
                    }
                }
            }

            $pageChanged = ($oldPage -ne $pageIndex)
            $scrollChanged = ($oldScroll -ne $listScrollOffset)
            $selectionChanged = ($oldIndex -ne $selectedIndex)

            if ($pageChanged -or $scrollChanged -or $selectionChanged -or $flashMessage) {
                Enter-ConsoleDrawBatch
                if ($pageChanged -or $scrollChanged) {
                    Redraw-InstallList
                }
                elseif ($selectionChanged -or ($key.Key -eq 'Spacebar')) {
                    Redraw-InstallList
                }
                $hint = if ($flashMessage) { $flashMessage } else { (Get-InstallPageFooterHint) }
                & $renderFooter @{ FlashMessage = $hint }
                Complete-ConsoleDrawBatch -ToolkitShell $Shell
            }
        }
    }
    finally {
        Set-CursorVisible $false
    }
}

function Invoke-InstallPage {
    param(
        [hashtable]$Shell,
        [array]$Tools,
        [string[]]$FocusToolIds = @(),
        [switch]$SelectAll
    )

    Initialize-ToolkitShellBodyView -Shell $Shell `
        -SectionTitle (Get-I18n -Key 'page.toolboxDeps.install.pageTitle') `
        -FooterTemplate SystemToolbarOnly

    return Show-InstallMultiSelectMenu -Shell $Shell -Tools $Tools `
        -FocusToolIds $FocusToolIds -SelectAll:$SelectAll
}

function Start-ToolboxDepInstallSession {
    param(
        [array]$Tools,
        [switch]$SelectAll
    )

    return (Start-ToolkitShellSession -Tools $Tools `
        -InitialView Install -ToolboxDepSelectAll:($SelectAll.IsPresent))
}
