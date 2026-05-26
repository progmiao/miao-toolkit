# 依赖安装/更新专页（Space 多选，Enter 确认，Esc 返回）

function Get-InstallDepsPageTools {
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

    $focused = @($items | Where-Object { $focusSet.ContainsKey([string]$_.id) })
    $rest = @($items | Where-Object { -not $focusSet.ContainsKey([string]$_.id) })
    return @($focused + $rest)
}

function Get-InstallPageToolStatusInfo {
    param($Tool)

    if (-not (Test-ToolDepInstalled $Tool)) {
        return @{
            needsAction = $true
            tag         = (Get-I18n -Key 'install.pageStatusNotInstalled')
            tagColor    = [System.ConsoleColor]::Red
        }
    }

    $recordedVersion = $null
    foreach ($dep in @($Tool.dependencies)) {
        $depId = Get-DependencyRecordId -Dependency $dep
        $recordedVersion = Get-ToolDepRecordedVersion -ToolId $Tool.id -DependencyId $depId
        if ($recordedVersion) { break }
    }

    $displayVersion = if ($recordedVersion) { "v$recordedVersion" } else { '' }

    if (Test-ToolDependencyNeedsUpgrade -Tool $Tool) {
        $latest = $null
        foreach ($dep in @($Tool.dependencies)) {
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
            Get-I18n -Key 'install.pageStatusUpdateAvailable' -Vars @{
                current = $displayVersion
                latest  = "v$latest"
            }
        }
        else {
            Get-I18n -Key 'install.pageStatusUpdateAvailableShort'
        }

        return @{
            needsAction = $true
            tag         = $tag
            tagColor    = [System.ConsoleColor]::Yellow
        }
    }

    $tag = if ($displayVersion) {
        Get-I18n -Key 'install.pageStatusInstalled' -Vars @{ version = $displayVersion }
    }
    else {
        Get-I18n -Key 'menu.toolStatusInstalled'
    }

    return @{
        needsAction = $false
        tag         = $tag
        tagColor    = [System.ConsoleColor]::Green
    }
}

function Format-InstallDepsToolLabel {
    param(
        $Tool,
        [bool]$Checked
    )

    $status = Get-InstallPageToolStatusInfo -Tool $Tool
    $mark = if ($Checked) { '[x]' } else { '[ ]' }
    $name = [string]$Tool.displayName
  return "$mark  $name  [$($status.tag)]"
}

function Show-InstallDepsMultiSelectMenu {
    param(
        [hashtable]$Shell,
        [array]$Tools,
        [string[]]$FocusToolIds = @(),
        [switch]$Preview
    )

    $items = @(Get-InstallDepsPageTools -Tools $Tools -FocusToolIds $FocusToolIds)
    if ($items.Count -eq 0) {
        Write-FixedLine $Shell.Layout.ListStartRow (Get-I18n -Key 'install.noTargets') -Color DarkGray
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

    if ($FocusToolIds.Count -gt 0) {
        $focusId = [string]$FocusToolIds[0]
        for ($i = 0; $i -lt $items.Count; $i++) {
            if ([string]$items[$i].id -eq $focusId) {
                $selectedIndex = $i
                $pageIndex = [Math]::Floor($i / [double]$pageSize)
                break
            }
        }
    }

    $header = New-ToolkitMenuHeader -SectionTitle (Get-I18n -Key 'install.pageTitle') -HideSectionTitle
    $renderFooter = New-ShellDefaultFooterRenderer -Shell $Shell -ShowHelp -ShowBack

    function Redraw-InstallDepsList {
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
            $label = Format-InstallDepsToolLabel -Tool $tool -Checked $checked
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
    Redraw-InstallDepsList
    & $renderFooter @{ FlashMessage = (Get-I18n -Key 'install.pageFooterHint') }
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
                            $flashMessage = Get-I18n -Key 'install.pageNothingToDo'
                            break
                        }

                        Set-CursorVisible $true
                        Clear-Host
                        $failed = @()
                        foreach ($tool in $actionable) {
                            $info = Get-InstallPageToolStatusInfo -Tool $tool
                            $label = if (-not (Test-ToolDepInstalled $tool)) {
                                (Get-I18n -Key 'install.statusInstalling')
                            }
                            else {
                                (Get-I18n -Key 'install.statusUpdating')
                            }
                            Write-Host " $($tool.displayName)  $label" -ForegroundColor Cyan
                            $ok = Invoke-ToolInstall -Tool $tool -Preview:$Preview
                            if (-not $ok) {
                                $failed += $tool.id
                                Write-Host "       $(Get-I18n -Key 'install.statusFailed')" -ForegroundColor Red
                            }
                            else {
                                Write-Host "       $(Get-I18n -Key 'install.statusDone')" -ForegroundColor Green
                            }
                        }

                        Write-Host ''
                        if ($failed.Count -gt 0) {
                            Write-Host (Get-I18n -Key 'install.batchFailed' -Vars @{ tools = ($failed -join ', ') }) -ForegroundColor Red
                        }
                        else {
                            Write-Host (Get-I18n -Key 'install.batchComplete') -ForegroundColor Green
                        }
                        Write-Host ''
                        Read-Host (Get-I18n -Key 'install.pagePressEnterToBack')

                        [void]$selectedSet.Clear()
                        Clear-DepsStateCache
                        Initialize-ToolkitShellBodyView -Shell $Shell `
                            -SectionTitle (Get-I18n -Key 'install.pageTitle') `
                            -FooterTemplate DefaultBar
                        Enter-ConsoleDrawBatch
                        Redraw-InstallDepsList
                        & $renderFooter @{ FlashMessage = (Get-I18n -Key 'install.pageFooterHint') }
                        Complete-ConsoleDrawBatch -ToolkitShell $Shell
                        continue
                    }
                    'Escape' {
                        return (Get-ShellNavMarker -Action 'back')
                    }
                }
            }

            $pageChanged = ($oldPage -ne $pageIndex)
            $scrollChanged = ($oldScroll -ne $listScrollOffset)
            $selectionChanged = ($oldIndex -ne $selectedIndex)

            if ($pageChanged -or $scrollChanged -or $selectionChanged -or $flashMessage) {
                Enter-ConsoleDrawBatch
                if ($pageChanged -or $scrollChanged) {
                    Redraw-InstallDepsList
                }
                elseif ($selectionChanged -or ($key.Key -eq 'Spacebar')) {
                    Redraw-InstallDepsList
                }
                $hint = if ($flashMessage) { $flashMessage } else { (Get-I18n -Key 'install.pageFooterHint') }
                & $renderFooter @{ FlashMessage = $hint }
                Complete-ConsoleDrawBatch -ToolkitShell $Shell
            }
        }
    }
    finally {
        Set-CursorVisible $false
    }
}

function Invoke-InstallDepsPage {
    param(
        [hashtable]$Shell,
        [array]$Tools,
        [string[]]$FocusToolIds = @(),
        [switch]$Preview
    )

    Initialize-ToolkitShellBodyView -Shell $Shell `
        -SectionTitle (Get-I18n -Key 'install.pageTitle') `
        -FooterTemplate DefaultBar

    return Show-InstallDepsMultiSelectMenu -Shell $Shell -Tools $Tools `
        -FocusToolIds $FocusToolIds -Preview:$Preview
}

function Start-InstallDepsSession {
    param(
        [array]$Tools,
        [string[]]$FocusToolIds = @(),
        [switch]$Preview
    )

    return (Start-ToolkitShellSession -Tools $Tools -Preview:$Preview `
        -InitialView Install -FocusToolIds $FocusToolIds)
}
