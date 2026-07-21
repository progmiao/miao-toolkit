/**
 * Job 控制台状态机：订阅宿主 `job-*` 消息，维护状态日志 / 命令窗 / 进度条。
 *
 * 各工具页**独立**，只复用本 composable + `JobConsole` 子组件，不要抽「通用工具页」。
 * 页面在自己的 `subscribe` 里先处理业务消息，再调用 `consumeJobMessage`。
 */
import { ref, type Ref } from 'vue'
import { post, type HostMessage } from '@kernel/bridge/bus'

/** 状态日志最大行数（左侧状态通道）。 */
const MAX_STATUS_LINES = 80
/** 命令窗最大行数（右侧 PowerShell 通道）。 */
const MAX_CONSOLE_LINES = 800

/** `useJobConsole` 可选回调与文案。 */
export type UseJobConsoleOptions = {
  /**
   * 任务结束（`job-finished`）后回调；用于刷新目录 / 版本列表等。
   * @param msg - 宿主结束消息
   */
  onFinished?: (msg: HostMessage) => void
  /**
   * 收到宿主 `error` 且本 composable 已清 busy 后回调。
   * @param message - 错误文案
   */
  onError?: (message: string) => void
  /**
   * 自定义「开始」状态行；缺省为 `开始：{action}`。
   * @param msg - `job-started` 消息
   */
  formatStarted?: (msg: HostMessage) => string
  /**
   * 自定义「结束」状态行；缺省含 exitCode / detail。
   * @param msg - `job-finished` 消息
   */
  formatFinished?: (msg: HostMessage) => string
}

/** `useJobConsole` 返回值：缓冲与消费入口。 */
export type JobConsoleApi = {
  /** 状态日志行（短摘要）。 */
  logs: Ref<string[]>
  /** 命令窗行（PowerShell 原始输出）。 */
  consoleLines: Ref<string[]>
  /** 0–100 单项任务进度。 */
  progress: Ref<number>
  /** 当前进行中的任务文案（进度条上方）。 */
  statusText: Ref<string>
  /** 集合进度：当前第几项（0 表示未开始）。 */
  batchCurrent: Ref<number>
  /** 集合进度：总项数（0 表示无集合信息）。 */
  batchTotal: Ref<number>
  /** 是否有任务在跑。 */
  busy: Ref<boolean>
  /** 当前 jobId；无任务时为 null。 */
  currentJob: Ref<string | null>
  /**
   * 追加状态日志一行。
   * @param line - 文案
   */
  appendStatus: (line: string) => void
  /**
   * 追加命令窗一行（自动过滤 `##progress` / `##task` / `##batch` / `##log`）。
   * @param line - 输出
   */
  appendConsole: (line: string) => void
  /**
   * 空闲时清空双通道与进度（切换工具时用）。
   * 任务进行中不操作，避免冲掉进行中输出。
   */
  resetWhenIdle: () => void
  /**
   * 消费与 Job 相关的宿主消息。
   * @param msg - 总线消息
   * @returns 是否已处理（调用方可跳过后续分支）
   */
  consumeJobMessage: (msg: HostMessage) => boolean
  /** 向宿主发送 `cancel-job`（无 currentJob 时为 no-op）。 */
  cancel: () => void
}

/**
 * 创建绑定到某一页面的 Job 控制台状态。
 * @param options - 结束/错误回调与文案
 * @returns 可直接绑到 `JobConsole` 的 refs 与方法
 */
export function useJobConsole(options: UseJobConsoleOptions = {}): JobConsoleApi {
  const logs = ref<string[]>([])
  const consoleLines = ref<string[]>([])
  const progress = ref(0)
  const statusText = ref('')
  const batchCurrent = ref(0)
  const batchTotal = ref(0)
  const busy = ref(false)
  const currentJob = ref<string | null>(null)

  function appendStatus(line: string) {
    logs.value.push(line)
    if (logs.value.length > MAX_STATUS_LINES) logs.value.shift()
  }

  function appendConsole(line: string) {
    if (/##(?:progress|task|batch|log)\b/i.test(line)) return
    consoleLines.value.push(line)
    if (consoleLines.value.length > MAX_CONSOLE_LINES) consoleLines.value.shift()
  }

  function clearBuffers() {
    logs.value = []
    consoleLines.value = []
    progress.value = 0
    statusText.value = ''
    batchCurrent.value = 0
    batchTotal.value = 0
  }

  function resetWhenIdle() {
    if (busy.value) return
    clearBuffers()
  }

  function defaultStarted(msg: HostMessage): string {
    const action = msg.action ?? '任务'
    return msg.toolId ? `开始：${action}（${msg.toolId}）` : `开始：${action}`
  }

  function defaultFinished(msg: HostMessage): string {
    return msg.ok
      ? `完成（exit ${msg.exitCode}）`
      : `失败（exit ${msg.exitCode}） ${msg.detail ?? ''}`
  }

  function consumeJobMessage(msg: HostMessage): boolean {
    if (msg.type === 'job-started') {
      busy.value = true
      currentJob.value = msg.jobId ?? null
      clearBuffers()
      const started = (options.formatStarted ?? defaultStarted)(msg)
      statusText.value = started
      appendStatus(started)
      return true
    }

    if (msg.type === 'job-event') {
      if (msg.kind === 'progress' && msg.message) {
        progress.value = Number(msg.message) || progress.value
      } else if (msg.kind === 'task' && msg.message) {
        statusText.value = msg.message
        // 任务切换也记入实时日志，保证每步可追溯
        appendStatus(msg.message)
      } else if (msg.kind === 'batch' && msg.message) {
        // 保留解析（兼容旧 Handler）；UI 不再展示 xx/xx
        const parts = msg.message.trim().split(/\s+/)
        const cur = Number(parts[0])
        const total = Number(parts[1])
        if (Number.isFinite(cur)) batchCurrent.value = Math.max(0, Math.floor(cur))
        if (Number.isFinite(total)) batchTotal.value = Math.max(0, Math.floor(total))
      } else if (msg.kind === 'console' && msg.message) {
        appendConsole(msg.message)
      } else if (msg.kind === 'log' && msg.message) {
        appendStatus(msg.message)
      } else if (msg.message) {
        // 兼容未区分 console/log 的旧 Handler：默认进命令窗
        appendConsole(msg.message)
      }
      return true
    }

    if (msg.type === 'job-finished') {
      busy.value = false
      progress.value = msg.ok ? 100 : progress.value
      if (batchTotal.value > 0) batchCurrent.value = batchTotal.value
      statusText.value = msg.ok ? '完成' : '失败'
      appendStatus((options.formatFinished ?? defaultFinished)(msg))
      currentJob.value = null
      options.onFinished?.(msg)
      return true
    }

    if (msg.type === 'error' && msg.message) {
      busy.value = false
      statusText.value = '错误'
      appendStatus(`[错误] ${msg.message}`)
      options.onError?.(msg.message)
      return true
    }

    return false
  }

  function cancel() {
    if (currentJob.value) post({ type: 'cancel-job', jobId: currentJob.value })
  }

  return {
    logs,
    consoleLines,
    progress,
    statusText,
    batchCurrent,
    batchTotal,
    busy,
    currentJob,
    appendStatus,
    appendConsole,
    resetWhenIdle,
    consumeJobMessage,
    cancel,
  }
}
