function Invoke-Tool {
    param(
        $Tool,
        [string[]]$ToolArgs,
        [switch]$Direct,
        [switch]$Preview
    )

    $entry = Join-Path $Tool._root $Tool.entry
    if (-not (Test-Path $entry)) {
        Write-Host "工具 $($Tool.id) 缺少入口: $($Tool.entry)" -ForegroundColor Red
        return 1
    }

    if ($Preview) {
        Write-Host "[预览] miao $($Tool.id) $($ToolArgs -join ' ')" -ForegroundColor DarkGray
        Write-Host "       -> $entry" -ForegroundColor DarkGray
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
