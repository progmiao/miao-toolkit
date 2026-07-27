/**
 * Volta / Node 批量任务：把宿主 console 流转成命令窗 append/upsert，并辅助算进度。
 * 职责拆开，便于排查；组件本身不算进度、不解析业务流。
 *
 * 进度行（Fetching / Unpacking）按「阶段 + 包名」各自 upsert，互不覆盖：
 *   volta:progress:fetching:node@26.5.0
 *   volta:progress:unpacking:node@26.5.0
 */

export type CommandSink = {
  append: (text: string, tone?: 'plain' | 'dim' | 'ok' | 'warn' | 'err') => void
  upsert: (id: string, text: string, tone?: 'plain' | 'dim' | 'ok' | 'warn' | 'err') => void
  remove: (id: string) => void
}

/** @deprecated 旧单行 Fetching id；新逻辑用 per-pkg phase id。 */
export const VOLTA_FETCH_LINE_ID = 'volta:fetch'

/** Volta 命令窗进度阶段（可并存，勿互相替代）。 */
export type VoltaProgressPhase = 'fetching' | 'unpacking'

export type VoltaPhaseProgress = {
  phase: VoltaProgressPhase
  pkg: string
  pct: number
}

export type VoltaBatchProgressInput = {
  /** 当前任务序号 1-based；未知则 0 */
  taskIndex: number
  /** 任务总数 */
  taskTotal: number
  /** 当前任务内综合进度 0–100；无则 null */
  fetchPct: number | null
  /** 宿主 ##progress；作下限/回退 */
  hostPct: number
  /** 准备阶段是否已开始（有任务文案或首个进度） */
  started?: boolean
}

const PHASE_LINE_RE = /^(Fetching|Unpacking)\s+(\S+)/i
const PHASE_SPLIT_RE = /(?!^)(?=(?:Fetching|Unpacking)\s+\S+)/gi

/** 剥 CSI / OSC / 孤儿 [K [?25h 等（非编码问题）。勿误伤 [1/2]、[====>]。 */
function scrubConsoleControls(chunk: string): string {
  let text = chunk.replace(/\u001b\[[0-9;?]*[ -/]*[@-~]/g, '')
  // OSC：ESC ] … BEL 或 ESC ]
  text = text.replace(/\u001b\][^\u0007\u001b]*(?:\u0007|\u001b\\)?/g, '')
  // ESC 丢失后的残留：]0;…powershell.exe + BEL
  text = text.replace(/\]\d+;[^\r\n\u0007]*(?:\u0007)?/g, '')
  // ESC 丢失后的 CSI： [K  [?25h  [2J  [H  [m  [?9001h …
  text = text.replace(/\[\??[0-9;]*[A-Za-z]/g, '')
  text = text.replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, '')
  return text
}

/** 整行是否只是清屏/擦行噪声。 */
export function isConsoleControlNoiseLine(line: string): boolean {
  const t = scrubConsoleControls(line).trim()
  return t.length === 0
}

function formatBar(pct: number, width = 16): string {
  const p = Math.max(0, Math.min(100, Math.round(pct)))
  const filled = Math.round((p / 100) * width)
  const head = filled > 0 ? '='.repeat(Math.max(0, filled - 1)) + '>' : ''
  const rest = ' '.repeat(Math.max(0, width - head.length))
  return `[${head}${rest}]`
}

function canonicalPhaseLabel(phase: VoltaProgressPhase): string {
  return phase === 'unpacking' ? 'Unpacking' : 'Fetching'
}

function normalizePhase(raw: string): VoltaProgressPhase | null {
  const t = raw.trim().toLowerCase()
  if (t === 'fetching') return 'fetching'
  if (t === 'unpacking') return 'unpacking'
  return null
}

/** 每条安装进度行的稳定 id（同阶段+同包原位更新；不同安装互不覆盖）。 */
export function voltaProgressLineId(phase: VoltaProgressPhase, pkg: string): string {
  return `volta:progress:${phase}:${pkg}`
}

/** 格式化阶段进度展示行。 */
export function formatVoltaPhaseLine(phase: VoltaProgressPhase, pkg: string, pct: number): string {
  const p = Math.max(0, Math.min(100, Math.round(pct)))
  return `${canonicalPhaseLabel(phase)} ${pkg}  ${formatBar(p)} ${String(p).padStart(3, ' ')}%`
}

/** @deprecated 请用 formatVoltaPhaseLine('fetching', …) */
export function formatVoltaFetchLine(pkg: string, pct: number): string {
  return formatVoltaPhaseLine('fetching', pkg, pct)
}

/**
 * 从一行文本解析 Fetching / Unpacking 进度。
 */
export function parseVoltaPhaseLine(line: string): VoltaPhaseProgress | null {
  const m = PHASE_LINE_RE.exec(line.trim())
  if (!m?.[1] || !m[2]) return null
  const phase = normalizePhase(m[1])
  if (!phase) return null
  const pm = /(\d{1,3})\s*%/.exec(line)
  return {
    phase,
    pkg: m[2],
    pct: pm ? Number.parseInt(pm[1]!, 10) : 0,
  }
}

/** @deprecated 请用 parseVoltaPhaseLine */
export function parseVoltaFetchLine(line: string): { pkg: string; pct: number } | null {
  const p = parseVoltaPhaseLine(line)
  if (!p || p.phase !== 'fetching') return null
  return { pkg: p.pkg, pct: p.pct }
}

/**
 * 是否为应丢弃的进度噪声（字节条、半截进度条等）。
 */
export function isVoltaProgressNoise(line: string): boolean {
  const t = line.trim()
  if (!t) return true
  if (PHASE_LINE_RE.test(t)) return false
  if (t.includes('\u2591') || t.includes('\u2588')) return true
  if (/^\d{1,3}\s*%$/.test(t)) return true
  if (/^\]/.test(t) && t.length < 20) return true
  if (/^\[[=>\s]*\]?$/.test(t)) return true
  if (/^[=>\-\s\]]+$/.test(t)) return true
  if (/\d+\s*\/\s*\d+/.test(t) && t.length > 40) return true
  return false
}

/**
 * 当前任务内：Fetching 约占前半，Unpacking 约占后半；仅有其一则用其自身比例。
 */
export function combineVoltaPhasePct(
  fetchingPct: number | null,
  unpackingPct: number | null,
): number | null {
  const hasFetch = fetchingPct != null
  const hasUnpack = unpackingPct != null
  if (!hasFetch && !hasUnpack) return null
  if (hasFetch && hasUnpack) {
    const f = Math.max(0, Math.min(100, fetchingPct!)) / 100
    const u = Math.max(0, Math.min(100, unpackingPct!)) / 100
    return Math.round(50 * f + 50 * u)
  }
  if (hasUnpack) return Math.max(0, Math.min(100, Math.round(unpackingPct!)))
  return Math.max(0, Math.min(100, Math.round(fetchingPct!)))
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
  /** 当前任务 Fetching 0–100 */
  fetchingPct: number | null
  /** 当前任务 Unpacking 0–100 */
  unpackingPct: number | null
  /** 综合后的任务内进度（供进度条） */
  fetchPct: number | null
  hostPct: number
  started: boolean
  /** 本任务出现过的进度行 id（结束时可清理） */
  progressLineIds: string[]
  /** 待拼的半行（无换行的流） */
  pending: string
}

export function createVoltaConsoleSession(): VoltaConsoleSession {
  return {
    taskIndex: 0,
    taskTotal: 0,
    fetchingPct: null,
    unpackingPct: null,
    fetchPct: null,
    hostPct: 0,
    started: false,
    progressLineIds: [],
    pending: '',
  }
}

function trackProgressId(session: VoltaConsoleSession, id: string) {
  if (!session.progressLineIds.includes(id)) session.progressLineIds.push(id)
}

function syncCombinedPct(session: VoltaConsoleSession) {
  session.fetchPct = combineVoltaPhasePct(session.fetchingPct, session.unpackingPct)
}

function resetTaskPhasePct(session: VoltaConsoleSession) {
  session.fetchingPct = null
  session.unpackingPct = null
  session.fetchPct = null
}

export type VoltaConsoleApplyResult = {
  /** 建议写入进度条的 0–100；null 表示本 chunk 不改进度 */
  progress: number | null
}

/**
 * 处理一块 console 原文：拆行、过滤噪声、Fetching/Unpacking upsert、正文 append。
 */
export function applyVoltaConsoleChunk(
  session: VoltaConsoleSession,
  chunk: string,
  sink: CommandSink,
): VoltaConsoleApplyResult {
  if (!chunk) return { progress: null }

  let text = scrubConsoleControls(chunk)
  text = text.replace(PHASE_SPLIT_RE, '\n')
  text = session.pending + text
  session.pending = ''

  const parts = text.split(/\r?\n/)
  // 末段无换行：可能是半行或 \r 进度，先当完整行处理；纯 \r 流用 \r 切
  const crParts = parts.length === 1 && text.includes('\r') ? text.split(/\r/) : null
  const lines = crParts ?? parts
  if (!crParts && !text.endsWith('\n') && !text.endsWith('\r') && lines.length > 0) {
    const last = lines[lines.length - 1] ?? ''
    if (last && !PHASE_LINE_RE.test(last) && !isVoltaProgressNoise(last)) {
      session.pending = last
      lines.pop()
    }
  }

  let progressDirty = false

  for (const raw of lines) {
    const line = raw.trim()
    if (!line) continue
    if (isConsoleControlNoiseLine(line)) continue

    if (/^\^C\b/i.test(line) || /任务已取消/.test(line)) {
      sink.append(/^\^C\b/i.test(line) ? line : '^C 任务已取消', 'warn')
      continue
    }

    const taskRef = parseVoltaTaskIndex(line)
    if (taskRef) {
      session.taskIndex = taskRef.index
      session.taskTotal = taskRef.total
      session.started = true
      resetTaskPhasePct(session)
      progressDirty = true
    }

    const phase = parseVoltaPhaseLine(line)
    if (phase) {
      if (phase.phase === 'fetching') session.fetchingPct = phase.pct
      else session.unpackingPct = phase.pct
      syncCombinedPct(session)
      session.started = true
      const id = voltaProgressLineId(phase.phase, phase.pkg)
      trackProgressId(session, id)
      sink.upsert(id, formatVoltaPhaseLine(phase.phase, phase.pkg, phase.pct), 'dim')
      progressDirty = true
      continue
    }

    if (isVoltaProgressNoise(line)) continue

    if (/^success:/i.test(line)) {
      sink.append(line, 'ok')
      if (session.unpackingPct != null) session.unpackingPct = 100
      else if (session.fetchingPct != null) session.fetchingPct = 100
      else session.fetchingPct = 100
      syncCombinedPct(session)
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
  resetTaskPhasePct(session)
  return computeVoltaBatchProgress({
    taskIndex: session.taskIndex,
    taskTotal: session.taskTotal,
    fetchPct: session.fetchPct,
    hostPct: session.hostPct,
    started: session.started,
  })
}

/** 任务结束时移除本会话产生的进度行（含旧 VOLTA_FETCH_LINE_ID）。 */
export function clearVoltaProgressLines(sink: CommandSink, session?: VoltaConsoleSession) {
  sink.remove(VOLTA_FETCH_LINE_ID)
  if (!session) return
  for (const id of session.progressLineIds) sink.remove(id)
  session.progressLineIds = []
}

/** @deprecated 请用 clearVoltaProgressLines */
export function clearVoltaFetchLine(sink: CommandSink) {
  clearVoltaProgressLines(sink)
}
