# Shell 内容行：标题栏与列表之间的固定单行

function Get-ToolkitShellContentRow {
    param([hashtable]$Shell)

    if (-not $Shell -or -not $Shell.Layout) { return -1 }
    $layout = $Shell.Layout
    if ($null -ne $layout.ContentRow -and [int]$layout.ContentRow -ge 0) {
        return [int]$layout.ContentRow
    }
    if ($null -ne $layout.SectionGapRow -and [int]$layout.SectionGapRow -ge 0) {
        return [int]$layout.SectionGapRow
    }
    return -1
}

function Write-ToolkitShellContentRow {
    param(
        [hashtable]$Shell = $null,
        [int]$ContentRow = -1,
        [string]$Message = ''
    )

    if ($ContentRow -lt 0 -and $Shell) {
        $ContentRow = Get-ToolkitShellContentRow -Shell $Shell
    }
    if ($ContentRow -lt 0) { return }

    if (-not [string]::IsNullOrWhiteSpace($Message)) {
        Write-FixedLine $ContentRow " $Message" -Color Cyan
    }
    else {
        Write-FixedLine $ContentRow '' -Color DarkCyan
    }
}

function Set-ToolkitShellBodyContentLine {
    param(
        [hashtable]$Shell,
        [string]$ContentLine = ''
    )

    if (-not $Shell) { return }
    $Shell['BodyContentLine'] = [string]$ContentLine
}

function Get-ToolkitShellBodyContentLine {
    param([hashtable]$Shell)

    if (-not $Shell) { return '' }
    if ($Shell.ContainsKey('BodyContentLine')) {
        return [string]$Shell.BodyContentLine
    }
    return ''
}

function Render-ToolkitShellContentRow {
    param([hashtable]$Shell)

    if (-not $Shell) { return }
    $line = Get-ToolkitShellBodyContentLine -Shell $Shell
    Write-ToolkitShellContentRow -Shell $Shell -Message $line
}
