# Shell Catalog 层：Title 与 Body 之间的固定单行（目录/上下文）

function Get-ToolkitShellCatalogRow {
    param([hashtable]$Shell)

    if (-not $Shell -or -not $Shell.Layout) { return -1 }
    $layout = $Shell.Layout
    if ($null -ne $layout.CatalogRow -and [int]$layout.CatalogRow -ge 0) {
        return [int]$layout.CatalogRow
    }
    return -1
}

function Write-ToolkitShellCatalogRow {
    param(
        [hashtable]$Shell = $null,
        [int]$CatalogRow = -1,
        [string]$Message = ''
    )

    if ($CatalogRow -lt 0 -and $Shell) {
        $CatalogRow = Get-ToolkitShellCatalogRow -Shell $Shell
    }
    if ($CatalogRow -lt 0) { return }

    if (-not [string]::IsNullOrWhiteSpace($Message)) {
        Write-FixedLine $CatalogRow " $Message" -Color Cyan
    }
    else {
        Write-FixedLine $CatalogRow '' -Color DarkCyan
    }
}

function Set-ToolkitShellBodyCatalogLine {
    param(
        [hashtable]$Shell,
        [string]$CatalogLine = ''
    )

    if (-not $Shell) { return }
    $Shell['BodyCatalogLine'] = [string]$CatalogLine
}

function Get-ToolkitShellBodyCatalogLine {
    param([hashtable]$Shell)

    if (-not $Shell) { return '' }
    if ($Shell.ContainsKey('BodyCatalogLine')) {
        return [string]$Shell.BodyCatalogLine
    }
    return ''
}

function Render-ToolkitShellCatalogRow {
    param([hashtable]$Shell)

    if (-not $Shell) { return }
    $line = Get-ToolkitShellBodyCatalogLine -Shell $Shell
    Write-ToolkitShellCatalogRow -Shell $Shell -Message $line
}
