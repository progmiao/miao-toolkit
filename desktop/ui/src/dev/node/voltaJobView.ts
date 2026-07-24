/**
 * Volta / Node 批量任务：把宿主 console 流转成命令窗 append/upsert，并辅助算进度。
 * 职责拆开，便于排查；组件本身不算进度、不解析业务流。
 */

export type CommandSink = {
  append: (text: string, tone?: 'plain' | 'dim' | 'ok' | 'warn' | 'err') => void
  upsert: (id: string, text: string, tone?: 'plain' | 'dim' | 'ok' | 'warn' | 'err') => void
  remove: (id: string) => void
}

/** 当前下载进度行的稳定 id（同 id 原位更新）。 */
export const VOLTA_FETCH_LINE_ID = 'volta:fetch'

export type VoltaFetchProgress = {
  pkg: string
  pct: number
}

export type VoltaBatchProgressInput = {
  /** 当前任务序号 1-based；未知则 0 */
  taskIndex: number
  /** 任务总数 */
  taskTotal: number
  /** 当前任务内下载 0–100；无则 null */
  fetchPct: number | null
  /** 宿主 ##progress；作下限/回退 */
  hostPct: number
  /** 准备阶段是否已开始（有任务文案或首个进度） */
  started?: boolean
}

function formatBar(pct: number, width = 16): string {
  const p = Math.max(0, Math.min(100, Math.round(pct)))
  const filled = Math.round((p / 100) * width)
  const head = filled > 0 ? '='.repeat(Math.max(0, filled - 1)) + '>' : ''
  const rest = ' '.repeat(Math.max(0, width - head.length))
  return `[${head}${rest}]`
}

/** 格式化 Fetching 展示行。 */
export function formatVoltaFetchLine(pkg: string, pct: number): string {
  const p = Math.max(0, Math.min(100, Math.round(pct)))
  return `Fetching ${pkg}  ${formatBar(p)} ${String(p).padStart(3, ' ')}%`
}

/**
 * 从一行文本解析 Fetching 进度。
 */
export function parseVoltaFetchLine(line: string): VoltaFetchProgress | null {
  const fetch = /Fetching\s+(\S+)/i.exec(line)
  if (!fetch?.[1]) return null
  const pm = /(\d{1,3})\s*%/.exec(line)
  return {
    pkg: fetch[1],
    pct: pm ? Number.parseInt(pm[1]!, 10) : 0,
  }
}

/**
 * 是否为应丢弃的进度噪声（字节条、半截进度条等）。
 */
export function isVoltaProgressNoise(line: string): boolean {
  const t = line.trim()
  if (!t) return true
  if (t.includes('\u2591') || t.includes('\u2588')) return true
  if (/^\d{1,3}\s*%$/.test(t)) return true
  if (/^\]/.test(t) && t.length < 20) return true
  if (/^\[[=>\s]*\]?$/.test(t)) return true
  if (/^[=>\-\s\]]+$/.test(t)) return true
  if (/\d+\s*\/\s*\d+/.test(t) && t.length > 40 && !/Fetching/i.test(t)) return true
  return false
}

/**
 * 按任务均分整段进度，当前任务内用 fetchPct 插值；宿主 pct 作下限。
 * 准备阶段（尚无 taskIndex）占 0–2%。
 */
export function computeVoltaBatchProgress(input: VoltaBatchProgressInput): number {
  const total = Math.max(0, Math.floor(input.taskTotal))
  const host = Math.max(0, Math.min(100, input.hostPct))
  if (total <= 0) return host

  const idx = Math.max(0, Math.floor(input.taskIndex))
  if (idx <= 0) {
    return Math.max(host, input.started ? 2 : 0)
  }

  const i = Math.min(idx, total) - 1
  const slice = 100 / total
  const base = i * slice
  const fetch =
    input.fetchPct == null ? 0 : Math.max(0, Math.min(100, input.fetchPct)) / 100
  const within = slice * fetch
  const computed = Math.min(100, base + within)
  return Math.max(host, Math.round(computed))
}

/**
 * 从 `##task [n/N] …` 或 `[n/N] volta install` 解析任务序号。
 */
export function parseVoltaTaskIndex(text: string): { index: number; total: number } | null {
  const m = /\[(\d+)\s*\/\s*(\d+)\]/.exec(text)
  if (!m) return null
  const index = Number.parseInt(m[1]!, 10)
  const total = Number.parseInt(m[2]!, 10)
  if (!Number.isFinite(index) || !Number.isFinite(total) || total <= 0) return null
  return { index, total }
}

export type VoltaConsoleSession = {
  taskIndex: number
  taskTotal: number
  fetchPct: number | null
  hostPct: number
  started: boolean
  /** 待拼的半行（无换行的流） */
  pending: string
}

export function createVoltaConsoleSession(): VoltaConsoleSession {
  return {
    taskIndex: 0,
    taskTotal: 0,
    fetchPct: null,
    hostPct: 0,
    started: false,
    pending: '',
  }
}

export type VoltaConsoleApplyResult = {
  /** 建议写入进度条的 0–100；null 表示本 chunk 不改进度 */
  progress: number | null
}

/**
 * 处理一块 console 原文：拆行、过滤噪声、Fetching upsert、正文 append。
 */
export function applyVoltaConsoleChunk(
  session: VoltaConsoleSession,
  chunk: string,
  sink: CommandSink,
): VoltaConsoleApplyResult {
  if (!chunk) return { progress: null }

  let text = chunk.replace(/\u001b\[[0-9;?]*[ -/]*[@-~]/g, '')
  text = text.replace(/(?!^)(?=Fetching\s+\S+)/gi, '\n')
  text = session.pending + text
  session.pending = ''

  const parts = text.split(/\r?\n/)
  // 末段无换行：可能是半行或 \r 进度，先当完整行处理；纯 \r 流用 \r 切
  const crParts = parts.length === 1 && text.includes('\r') ? text.split(/\r/) : null
  const lines = crParts ?? parts
  if (!crParts && !text.endsWith('\n') && !text.endsWith('\r') && lines.length > 0) {
    const last = lines[lines.length - 1] ?? ''
    if (last && !/Fetching/i.test(last) && !isVoltaProgressNoise(last)) {
      session.pending = last
      lines.pop()
    }
  }

  let progressDirty = false

  for (const raw of lines) {
    const line = raw.trim()
    if (!line) continue

    if (/^\^C\b/i.test(line) || /任务已取消/.test(line)) {
      sink.append(line, 'warn')
      continue
    }

    const taskRef = parseVoltaTaskIndex(line)
    if (taskRef) {
      session.taskIndex = taskRef.index
      session.taskTotal = taskRef.total
      session.started = true
      session.fetchPct = null
      progressDirty = true
    }

    const fetch = parseVoltaFetchLine(line)
    if (fetch) {
      session.fetchPct = fetch.pct
      session.started = true
      sink.upsert(VOLTA_FETCH_LINE_ID, formatVoltaFetchLine(fetch.pkg, fetch.pct), 'dim')
      progressDirty = true
      continue
    }

    if (isVoltaProgressNoise(line)) continue

    if (/^success:/i.test(line)) {
      sink.append(line, 'ok')
      session.fetchPct = 100
      progressDirty = true
      continue
    }

    if (/volta install|volta uninstall|当前 node:/i.test(line) || /^\[\d+\s*\/\s*\d+\]/.test(line)) {
      sink.append(line)
      continue
    }

    sink.append(line)
  }

  if (!progressDirty) return { progress: null }
  return {
    progress: computeVoltaBatchProgress({
      taskIndex: session.taskIndex,
      taskTotal: session.taskTotal,
      fetchPct: session.fetchPct,
      hostPct: session.hostPct,
      started: session.started,
    }),
  }
}

/** 宿主 ##progress 更新时合并进会话并重算。 */
export function applyVoltaHostProgress(
  session: VoltaConsoleSession,
  hostPct: number,
): number {
  session.hostPct = Math.max(0, Math.min(100, hostPct))
  session.started = true
  return computeVoltaBatchProgress({
    taskIndex: session.taskIndex,
    taskTotal: session.taskTotal,
    fetchPct: session.fetchPct,
    hostPct: session.hostPct,
    started: session.started,
  })
}

/** 任务文案里带 [n/N] 时同步会话。 */
export function applyVoltaTaskLabel(session: VoltaConsoleSession, label: string): number | null {
  const taskRef = parseVoltaTaskIndex(label)
  if (!taskRef) return null
  session.taskIndex = taskRef.index
  session.taskTotal = taskRef.total
  session.started = true
  session.fetchPct = null
  return computeVoltaBatchProgress({
    taskIndex: session.taskIndex,
    taskTotal: session.taskTotal,
    fetchPct: session.fetchPct,
    hostPct: session.hostPct,
    started: session.started,
  })
}

/** 任务结束时移除 Fetching 进度行。 */
export function clearVoltaFetchLine(sink: CommandSink) {
  sink.remove(VOLTA_FETCH_LINE_ID)
}
