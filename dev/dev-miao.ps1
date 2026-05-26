# 开发辅助：在未 winget 发版前从仓库运行 miao
#
# 在仓库根目录运行（与 dev/、package/ 同级）：
# 用法: .\dev\dev-miao.ps1 [miao 参数...]
# 示例: .\dev\dev-miao.ps1 list
#       .\dev\dev-miao.ps1 node -Install
#
# 路径由 $PSScriptRoot 解析，clone 到任意盘符均可。

param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$MiaoArgs
)

$ErrorActionPreference = 'Stop'
$env:MIAO_DEV = '1'
$env:MIAO_SKIP_DEPS = '1'

$RepoRoot = Split-Path $PSScriptRoot -Parent
$miaoPs1 = Join-Path $RepoRoot 'package\bin\miao.ps1'
if (-not (Test-Path $miaoPs1)) {
    throw '未找到 miao 入口。请在仓库根目录运行 .\dev\dev-miao.ps1（与 dev/、package/ 同级）。'
}

# 注意：@$null 会被当成一个空字符串参数，不能 splat 空变量
if ($MiaoArgs -and $MiaoArgs.Count -gt 0) {
    & $miaoPs1 @MiaoArgs
}
else {
    & $miaoPs1
}