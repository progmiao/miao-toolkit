/**
 * Job 控制台：命令窗累积原文，每次生成清洗后的展示文本（单行 Fetching 进度）。
 */
import { ref, type Ref } from 'vue'
import { post, type HostMessage } from '@kernel/bridge/bus'
import { renderConsoleWithFetchProgress } from '@kernel/console/coalesceFetchProgress'

const MAX_STATUS_LINES = 80
const MAX_CONSOLE_RAW = 500_000

export type UseJobConsoleOptions = {
  onFinished?: (msg: HostMessage) => void
  onError?: (message: string) => void
  formatStarted?: (msg: HostMessage) => string
  formatFinished?: (msg: HostMessage) => string
}

export type JobConsoleApi = {
  logs: Ref<string[]>
  /** 清洗后的命令窗全文（0～1 段）。 */
  consoleLines: Ref<string[]>
  progress: Ref<number>
  statusText: Ref<string>
  batchCurrent: Ref<number>
  batchTotal: Ref<number>
  busy: Ref<boolean>
  currentJob: Ref<string | null>
  appendStatus: (line: string) => void
  appendConsole: (chunk: string) => void
  resetWhenIdle: () => void
  consumeJobMessage: (msg: HostMessage) => boolean
  cancel: () => void
}

export function useJobConsole(options: UseJobConsoleOptions = {}): JobConsoleApi {
  const logs = ref<string[]>([])
  const consoleLines = ref<string[]>([])
  let consoleRaw = ''
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

  function rebuildConsoleView() {
    const view = renderConsoleWithFetchProgress(consoleRaw)
    consoleLines.value = view ? [view] : []
  }

  function appendConsole(chunk: string) {
    if (!chunk) return
    const plain = chunk.replace(/\u001b\[[0-9;?]*[ -/]*[@-~]/g, '').trim()
    if (/^##(?:progress|task|batch|log)\b/i.test(plain)) return

    consoleRaw += chunk
    if (consoleRaw.length > MAX_CONSOLE_RAW) {
      consoleRaw = consoleRaw.slice(-MAX_CONSOLE_RAW)
    }
    rebuildConsoleView()
  }

  function clearBuffers() {
    logs.value = []
    consoleRaw = ''
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
      } else if (msg.kind === 'batch' && msg.message) {
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
        appendConsole(msg.message)
      }
      return true
    }

    if (msg.type === 'job-finished') {
      busy.value = false
      const cancelled =
        !msg.ok &&
        (String(msg.detail ?? '').toLowerCase().includes('cancelled') ||
          String(msg.detail ?? '').includes('已取消') ||
          msg.exitCode === -1)
      progress.value = msg.ok ? 100 : cancelled ? 0 : progress.value
      if (batchTotal.value > 0 && !cancelled) batchCurrent.value = batchTotal.value
      statusText.value = msg.ok ? '完成' : cancelled ? '已取消' : '失败'
      appendStatus(
        cancelled
          ? '任务已取消'
          : (options.formatFinished ?? defaultFinished)(msg),
      )
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
