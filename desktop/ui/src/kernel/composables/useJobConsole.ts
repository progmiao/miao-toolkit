/**
 * Job 控制台状态：进度数值 + 命令/日志条目（显示组件只读 entries）。
 * 默认把 console chunk 按行 append；业务可通过 onConsoleChunk 自行解析（如 Volta）。
 */
import { ref, type Ref } from 'vue'
import { post, type HostMessage } from '@kernel/bridge/bus'
import { confirmDialog } from '@kernel/bridge/confirm'
import { useLogEntries, type UseLogEntriesApi } from '@kernel/composables/useLogEntries'
import type { LogEntry, LogEntryInput, LogEntryTone } from '@kernel/console/logEntries'

export type ConsoleChunkHandlers = {
  append: (text: string, tone?: LogEntryTone) => void
  upsert: (id: string, text: string, tone?: LogEntryTone) => void
  remove: (id: string) => void
  setProgress: (pct: number) => void
  setStatusText: (text: string) => void
}

export type UseJobConsoleOptions = {
  onFinished?: (msg: HostMessage) => void
  onError?: (message: string) => void
  formatStarted?: (msg: HostMessage) => string
  formatFinished?: (msg: HostMessage) => string
  /**
   * 业务接管命令窗写入与进度（如 Node Volta）。
   * 未提供时：console 按行 append，进度用宿主 ##progress。
   * 也可运行时通过 setViewAdapters 挂载（嵌入共用 Job 时）。
   */
  onConsoleChunk?: (chunk: string, api: ConsoleChunkHandlers) => void
  /** 业务接管宿主 progress；返回值写入进度条，返回 undefined 则沿用默认。 */
  onHostProgress?: (pct: number, api: ConsoleChunkHandlers) => number | void
  /** 业务接管 ##task 文案。 */
  onTaskLabel?: (label: string, api: ConsoleChunkHandlers) => void
}

export type JobViewAdapters = {
  onConsoleChunk?: UseJobConsoleOptions['onConsoleChunk']
  onHostProgress?: UseJobConsoleOptions['onHostProgress']
  onTaskLabel?: UseJobConsoleOptions['onTaskLabel']
}

export type JobConsoleApi = {
  /** @deprecated 兼容旧调用；请用 logEntries */
  logs: Ref<string[]>
  logEntries: Ref<LogEntry[]>
  /** @deprecated 兼容旧调用；请用 commandEntries */
  consoleLines: Ref<string[]>
  commandEntries: Ref<LogEntry[]>
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
  commandLog: UseLogEntriesApi
  statusLog: UseLogEntriesApi
  /** 运行时挂载/卸载业务视图适配器（嵌入共用 Job 时用）。 */
  setViewAdapters: (adapters: JobViewAdapters | null) => void
}

function defaultAppendConsoleLines(chunk: string, commandLog: UseLogEntriesApi) {
  let plain = chunk.replace(/\u001b\[[0-9;?]*[ -/]*[@-~]/g, '')
  // ESC 丢失后的 CSI 残留（[K [?25h [2J …）；不误伤 [1/2]、[====>]
  plain = plain.replace(/\[\??[0-9;]*[A-Za-z]/g, '')
  const parts = plain.replace(/\r/g, '\n').split('\n')
  for (const part of parts) {
    const line = part.trimEnd()
    if (line.trim().length) commandLog.append(line)
  }
}

export function useJobConsole(options: UseJobConsoleOptions = {}): JobConsoleApi {
  const statusLog = useLogEntries()
  const commandLog = useLogEntries()
  const progress = ref(0)
  const statusText = ref('')
  const batchCurrent = ref(0)
  const batchTotal = ref(0)
  const busy = ref(false)
  const currentJob = ref<string | null>(null)

  /** 旧 API：字符串数组视图 */
  const logs = ref<string[]>([])
  const consoleLines = ref<string[]>([])

  let runtimeAdapters: JobViewAdapters = {}

  function resolveAdapters(): JobViewAdapters {
    return {
      onConsoleChunk: runtimeAdapters.onConsoleChunk ?? options.onConsoleChunk,
      onHostProgress: runtimeAdapters.onHostProgress ?? options.onHostProgress,
      onTaskLabel: runtimeAdapters.onTaskLabel ?? options.onTaskLabel,
    }
  }

  function setViewAdapters(adapters: JobViewAdapters | null) {
    runtimeAdapters = adapters ? { ...adapters } : {}
  }

  function syncLegacyViews() {
    logs.value = statusLog.entries.value.map((e) => e.text)
    consoleLines.value = commandLog.entries.value.map((e) => e.text)
  }

  function handlers(): ConsoleChunkHandlers {
    return {
      append: (text, tone) => {
        commandLog.append(tone ? { text, tone } : text)
        syncLegacyViews()
      },
      upsert: (id, text, tone) => {
        commandLog.upsert({ id, text, tone })
        syncLegacyViews()
      },
      remove: (id) => {
        commandLog.remove(id)
        syncLegacyViews()
      },
      setProgress: (pct) => {
        progress.value = Math.max(0, Math.min(100, pct))
      },
      setStatusText: (text) => {
        statusText.value = text
      },
    }
  }

  function appendStatus(line: string) {
    statusLog.append(line)
    syncLegacyViews()
  }

  function appendConsole(chunk: string) {
    if (!chunk) return
    const plain = chunk.replace(/\u001b\[[0-9;?]*[ -/]*[@-~]/g, '').trim()
    if (/^##(?:progress|task|batch|log)\b/i.test(plain)) return

    const adapters = resolveAdapters()
    if (adapters.onConsoleChunk) {
      adapters.onConsoleChunk(chunk, handlers())
    } else {
      defaultAppendConsoleLines(chunk, commandLog)
      syncLegacyViews()
    }
  }

  function clearBuffers() {
    statusLog.clear()
    commandLog.clear()
    progress.value = 0
    statusText.value = ''
    batchCurrent.value = 0
    batchTotal.value = 0
    syncLegacyViews()
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
        const pct = Number(msg.message) || 0
        const adapters = resolveAdapters()
        if (adapters.onHostProgress) {
          const next = adapters.onHostProgress(pct, handlers())
          if (typeof next === 'number') progress.value = next
          else progress.value = pct
        } else {
          progress.value = pct
        }
      } else if (msg.kind === 'task' && msg.message) {
        const adapters = resolveAdapters()
        if (adapters.onTaskLabel) adapters.onTaskLabel(msg.message, handlers())
        else statusText.value = msg.message
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
    if (!currentJob.value) return
    void (async () => {
      const jobId = currentJob.value
      if (!jobId) return
      const ok = await confirmDialog({
        title: '终止确认',
        message: '确认终止当前任务？进行中的操作将被中断。',
        confirmText: '终止',
        cancelText: '取消',
        tone: 'danger',
      })
      if (!ok) return
      // 确认期间任务可能已结束
      if (currentJob.value !== jobId) return
      post({ type: 'cancel-job', jobId })
    })()
  }

  return {
    logs,
    logEntries: statusLog.entries,
    consoleLines,
    commandEntries: commandLog.entries,
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
    commandLog,
    statusLog,
    setViewAdapters,
  }
}

export type { LogEntry, LogEntryInput, LogEntryTone }
