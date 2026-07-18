function Invoke-Tool {
    param(
        $Tool,
        [string[]]$ToolArgs,
        [switch]$Direct,
        [hashtable]$ToolkitShell = $null
    )

    $entryName = if ($Tool.entry) { [string]$Tool.entry } else { 'index.ps1' }
    $root = if (Get-Command Resolve-ToolkitToolLiveRoot -ErrorAction SilentlyContinue) {
        Resolve-ToolkitToolLiveRoot -Tool $Tool
    }
    else {
        [string]$Tool._root
    }
    if ($root) {
        $Tool | Add-Member -NotePropertyName '_root' -NotePropertyValue $root -Force
    }

    $entry = if ($root) { Join-Path $root $entryName } else { '' }
    if (-not (Test-Path $entry)) {
        Write-Host (Get-I18n -Key 'message.toolMissingEntry' -Vars @{
                toolId = $Tool.id
                entry  = $entryName
            }) -ForegroundColor Red
        return 1
    }

    if ($ToolkitShell) {
        if ($ToolArgs -and $ToolArgs.Count -gt 0) {
            Write-Host 'Shell 内暂不支持带参数进入工具。' -ForegroundColor Yellow
            return 1
        }

        # dot-source：子脚本 & 调用会导致列表绘制闭包找不到 Console-Menu 辅助函数，只剩序号列
        return (. $entry -ToolkitShell $ToolkitShell)
    }

    # PS 5.1：字符串数组 splat 无法绑定 switch，嵌套 powershell 透传参数
    if ($ToolArgs -and $ToolArgs.Count -gt 0) {
        $psArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $entry) + $ToolArgs
        & powershell.exe @psArgs
    }
    else {
        & $entry
    }
    return $LASTEXITCODE
}
