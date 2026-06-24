# 批量执行（Shell 公共组件）
#
# 官方名称：**批量执行** — 进度区（首行进度条 + 状态行）+ 可滚动日志区，用于多步/多项
# 连续执行并展示结果（node 批量安装、依赖操作、claude-code 初始化/插件等）。
#
# 实现文件（内部，勿在文档/对话中以此代称组件）：
#   - DepOperationView.ps1      — 绘制、进度条、日志
#   - ToolkitDepBatchOperation.ps1 — 会话壳、Initialize/WaitLoop
#
# 对外 API 请使用 `Initialize-ToolkitBatchExecutionView` 等 *BatchExecution* 命名；
# 旧名 *DepBatchOperation* / *DepOperation* 保留兼容，新代码优先用新名。

$script:BatchExecutionShellDir = $PSScriptRoot

. (Join-Path $script:BatchExecutionShellDir 'DepOperationView.ps1')
. (Join-Path $script:BatchExecutionShellDir 'ToolkitDepBatchOperation.ps1')

function Initialize-ToolkitBatchExecutionView {
    [CmdletBinding()]
    param(
        [hashtable]$Shell,
        [string]$SectionTitle,
        [int]$ProgressTotal,
        [string]$ReadyStatusText = '',
        $Log = $null,
        [scriptblock]$OnExitConfirmed = $null
    )

    return Initialize-ToolkitDepBatchOperationView @PSBoundParameters
}

function Invoke-ToolkitBatchExecutionWaitLoop {
    [CmdletBinding()]
    param(
        $Context,
        [string]$QuitNavAction = 'back'
    )

    return Invoke-ToolkitDepBatchOperationWaitLoop @PSBoundParameters
}

function Start-ToolkitBatchExecution {
    [CmdletBinding()]
    param($Ui)

    Start-ToolkitDepOperationBatch -Ui $Ui
}

function Clear-ToolkitBatchExecutionView {
    [CmdletBinding()]
    param($Context)

    Clear-ToolkitDepBatchOperationView -Context $Context
}

function Set-ToolkitBatchExecutionCompleteUi {
    [CmdletBinding()]
    param(
        $Ui,
        [ValidateSet('install', 'update', 'uninstall', 'init', 'configure')]
        [string]$Intent,
        [int]$TotalCount,
        [int]$SuccessCount,
        [int]$FailedCount,
        [int]$ProgressCurrent
    )

    Set-ToolkitDepOperationBatchCompleteUi @PSBoundParameters
}

function Invoke-ToolkitBatchExecutionRunWork {
    [CmdletBinding()]
    param(
        $Context,
        [scriptblock]$Work
    )

    Invoke-ToolkitDepBatchOperationRunWork -Context $Context -Work $Work
}

function Set-ToolkitBatchExecutionInFlightStatus {
    [CmdletBinding()]
    param(
        $Ui,
        [string]$MainText = '',
        [switch]$AdvanceSpinner
    )

    Set-ToolkitDepOperationInFlightStatus -Ui $Ui -MainText $MainText -AdvanceSpinner:$AdvanceSpinner
}

function Invoke-ToolkitBatchExecutionUiPump {
    [CmdletBinding()]
    param($Context)

    Invoke-ToolkitDepBatchOperationUiPump -Context $Context
}

function Draw-ToolkitBatchExecutionView {
    [CmdletBinding()]
    param(
        [hashtable]$Shell,
        $Log,
        [int]$ProgressCurrent,
        [int]$ProgressTotal,
        [string]$ProgressName,
        [string]$StatusText,
        [string]$StatusRightText = '',
        [int]$LogViewportRows,
        [int]$LogStartRow,
        [int]$ProgressItemSubPercent = -1,
        [switch]$ProgressItemInFlight,
        [switch]$StatusPlain,
        [array]$StatusSegments = $null,
        [switch]$ChromeOnly
    )

    Draw-ToolkitDepOperationView @PSBoundParameters
}
