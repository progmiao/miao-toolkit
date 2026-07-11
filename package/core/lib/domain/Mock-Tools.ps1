# 主菜单工具列表（开发/正式环境均仅展示真实工具）

function Get-ToolkitMenuTools {
    param([array]$RealTools)

    return @($RealTools | Sort-Object { [int]$_.no })
}

function Test-IsMockTool {
    param($Tool)
    return ($Tool -and $Tool._mock -eq $true)
}
