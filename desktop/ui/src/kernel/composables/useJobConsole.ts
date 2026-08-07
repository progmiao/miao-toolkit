/**
 * Job 控制台状态：进度 + 单轨输出（原命令/日志合并为一条时间线）。
 * 默认把 console chunk 按行 append；业务可通过 onConsoleChunk 自行解析（如 Volta）。
 */
import { ref, type Ref } from 'vue'
import { post, type HostMessage } from '@kernel/bridge/bus'
import { confirmDialog } from '@kernel/bridge/confirm'
import { useLogEntries, type UseLogEntriesApi } from '@kernel/composables/useLogEntries'
import type { LogEntry, LogEntryInput, LogEntryTone } from '@kernel/console/logEntries'
import {
  applySpinnerConsoleChunk,
  createSpinnerConsoleSession,
  finishSpinnerConsoleSession,
  type SpinnerConsoleSession,
} from '@kernel/console/applySpinnerConsoleChunk'

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
   * 业务接管输出窗写入与进度（如 Node Volta）。
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
  outputEntries: Ref<LogEntry[]>
  progress: Ref<number>
  statusText: Ref<string>
  batchCurrent: Ref<number>
  batchTotal: Ref<number>
  busy: Ref<boolean>
  currentJob: Ref<string | null>
  /** 点击后立刻标忙碌（可选文案）；返回是否抢占成功。 */
  beginJob: (jobId: string, label?: string) => boolean
  /** 写入一行状态/摘要类输出（开始、结束、##log 等）。 */
  appendLine: (line: string, tone?: LogEntryTone) => void
  appendConsole: (chunk: string) => void
  resetWhenIdle: () => void
  consumeJobMessage: (msg: HostMessage) => boolean
  cancel: () => void
  /** 单轨输出缓冲（Volta 等可 remove/upsert）。 */
  outputLog: UseLogEntriesApi
  /** 运行时挂载/卸载业务视图适配器（嵌入共用 Job 时用）。 */
  setViewAdapters: (adapters: JobViewAdapters | null) => void
}

function clampProgress(pct: number): number {
  if (!Number.isFinite(pct)) return 0
  return Math.round(Math.min(100, Math.max(0, pct)))
}

function spinnerSink(outputLog: UseLogEntriesApi) {
  return {
    append: (text: string, tone?: LogEntryTone) => {
      outputLog.append(tone ? { text, tone } : text)
    },
    upsert: (id: string, text: string, tone?: LogEntryTone) => {
      outputLog.upsert({ id, text, tone })
    },
    remove: (id: string) => {
      outputLog.remove(id)
    },
  }
}

function defaultAppendConsoleLines(
  chunk: string,
  outputLog: UseLogEntriesApi,
  session: SpinnerConsoleSession,
  onDownload?: (info: {
    downloadPct: number
    downloaded: string
    total: string
  }) => void,
) {
  const result = applySpinnerConsoleChunk(session, chunk, spinnerSink(outputLog))
  if (
    result?.downloadPct != null &&
    result.downloaded &&
    result.total &&
    onDownload
  ) {
    onDownload({
      downloadPct: result.downloadPct,
      downloaded: result.downloaded,
      total: result.total,
    })
  }
}

export function useJobConsole(options: UseJobConsoleOptions = {}): JobConsoleApi {
  const outputLog = useLogEntries()
  const progress = ref(0)
  const statusText = ref('')
  const batchCurrent = ref(0)
  const batchTotal = ref(0)
  const busy = ref(false)
  const currentJob = ref<string | null>(null)

  let runtimeAdapters: JobViewAdapters = {}
  let spinnerSession = createSpinnerConsoleSession()

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

  function handlers(): ConsoleChunkHandlers {
    return {
      append: (text, tone) => {
        outputLog.append(tone ? { text, tone } : text)
      },
      upsert: (id, text, tone) => {
        outputLog.upsert({ id, text, tone })
      },
      remove: (id) => {
        outputLog.remove(id)
      },
      setProgress: (pct) => {
        progress.value = clampProgress(pct)
      },
      setStatusText: (text) => {
        statusText.value = text
      },
    }
  }

  function appendLine(line: string, tone?: LogEntryTone) {
    outputLog.append(tone ? { text: line, tone } : line)
  }

  function applyDownloadProgress(info: {
    downloadPct: number
    downloaded: string
    total: string
  }) {
    // 下载阶段映射到总进度约 30–85，且只升不降（保留宿主 ##progress 下限）
    const mapped = clampProgress(30 + (info.downloadPct / 100) * 55)
    if (mapped > progress.value) progress.value = mapped
    statusText.value = `下载 ${info.downloaded} / ${info.total}`
  }

  function appendConsole(chunk: string) {
    if (!chunk) return
    // 去掉偶发夹在 console 流里的协议行，避免 ##progress 出现在输出窗
    const cleaned = chunk
      .replace(/\u001b\[[0-9;?]*[ -/]*[@-~]/g, '')
      .replace(/(?:^|\r?\n)##(?:progress|task|batch|log)\b[^\r\n]*/gi, '')
    const plain = cleaned.trim()
    if (!plain) return
    if (/^##(?:progress|task|batch|log)\b/i.test(plain)) return

    const adapters = resolveAdapters()
    if (adapters.onConsoleChunk) {
      adapters.onConsoleChunk(cleaned, handlers())
    } else {
      defaultAppendConsoleLines(cleaned, outputLog, spinnerSession, applyDownloadProgress)
    }
  }

  function clearBuffers() {
    outputLog.clear()
    progress.value = 0
    statusText.value = ''
    batchCurrent.value = 0
    batchTotal.value = 0
    spinnerSession = createSpinnerConsoleSession()
  }

  function resetWhenIdle() {
    if (busy.value) return
    clearBuffers()
  }

  /**
   * 点击后立刻进入忙碌态（不必等宿主 job-started），避免同步任务堵 UI 时按钮仍可点。
   * 随后 job-started 会再清缓冲并写入正式开始行。
   */
  function beginJob(jobId: string, label?: string) {
    if (busy.value) return false
    busy.value = true
    currentJob.value = jobId
    const text = label?.trim() || '任务已提交…'
    statusText.value = text
    appendLine(text)
    return true
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
      appendLine(started)
      return true
    }

    if (msg.type === 'job-event') {
      if (msg.kind === 'progress' && msg.message) {
        const pct = clampProgress(Number(msg.message) || 0)
        const adapters = resolveAdapters()
        if (adapters.onHostProgress) {
          const next = adapters.onHostProgress(pct, handlers())
          if (typeof next === 'number') progress.value = clampProgress(next)
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
        appendLine(msg.message)
      } else if (msg.message) {
        appendConsole(msg.message)
      }
      return true
    }

    if (msg.type === 'job-finished') {
      busy.value = false
      finishSpinnerConsoleSession(spinnerSession, spinnerSink(outputLog))
      const cancelled =
        !msg.ok &&
        (String(msg.detail ?? '').toLowerCase().includes('cancelled') ||
          String(msg.detail ?? '').includes('已取消') ||
          msg.exitCode === -1)
      progress.value = msg.ok ? 100 : 0
      if (batchTotal.value > 0 && msg.ok) batchCurrent.value = batchTotal.value
      statusText.value = msg.ok ? '完成' : cancelled ? '已取消' : '失败'
      appendLine(
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
      finishSpinnerConsoleSession(spinnerSession, spinnerSink(outputLog))
      progress.value = 0
      statusText.value = '错误'
      appendLine(`[错误] ${msg.message}`, 'err')
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
      if (currentJob.value !== jobId) return
      post({ type: 'cancel-job', jobId })
    })()
  }

  return {
    outputEntries: outputLog.entries,
    progress,
    statusText,
    batchCurrent,
    batchTotal,
    busy,
    currentJob,
    beginJob,
    appendLine,
    appendConsole,
    resetWhenIdle,
    consumeJobMessage,
    cancel,
    outputLog,
    setViewAdapters,
  }
}

export type { LogEntry, LogEntryInput, LogEntryTone }
