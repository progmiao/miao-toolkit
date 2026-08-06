/**
 * 命令窗：CLI 转圈 + winget 下载进度（已下载 / 总大小）原地刷新。
 * 转圈结束后删除该行；下载进度 upsert 单行，避免 \r 刷屏与“卡住感”。
 */

export type SpinnerConsoleSink = {
  append: (text: string, tone?: 'plain' | 'dim' | 'ok' | 'warn' | 'err') => void
  upsert: (id: string, text: string, tone?: 'plain' | 'dim' | 'ok' | 'warn' | 'err') => void
  remove: (id: string) => void
}

export type SpinnerConsoleSession = {
  pending: string
  /** 当前转圈动画槽；每条正文后递增，保证下一段转圈是新行 */
  spinnerSlot: number
  /** 是否正在写当前槽的转圈帧 */
  inSpinner: boolean
  /** 是否已画出下载进度行 */
  hasDownloadLine: boolean
}

export type ApplyConsoleChunkResult = {
  /** 下载进度 0–100（由已下载/总大小推算） */
  downloadPct?: number
  /** 如 17.0 MB */
  downloaded?: string
  /** 如 79.4 MB */
  total?: string
}

/** 仅转圈字符的一行（可带空白）。 */
const SPINNER_ONLY_RE = /^\s*[-\\|\/]\s*$/

/** winget：`17.0 MB / 79.4 MB`（前可有进度块字符）。 */
const WINGET_SIZE_RE =
  /(\d+(?:\.\d+)?)\s*(B|KB|MB|GB|TB)\s*\/\s*(\d+(?:\.\d+)?)\s*(B|KB|MB|GB|TB)/i

export const WINGET_DOWNLOAD_LINE_ID = 'winget:download'

export function createSpinnerConsoleSession(): SpinnerConsoleSession {
  return { pending: '', spinnerSlot: 0, inSpinner: false, hasDownloadLine: false }
}

export function isSpinnerOnlyLine(line: string): boolean {
  return SPINNER_ONLY_RE.test(line)
}

function scrubConsoleControls(chunk: string): string {
  let text = chunk.replace(/\u001b\[[0-9;?]*[ -/]*[@-~]/g, '')
  text = text.replace(/\[\??[0-9;]*[A-Za-z]/g, '')
  text = text.replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, '')
  return text
}

function spinnerLineId(slot: number): string {
  return `console:spinner:${slot}`
}

function formatSpinnerDisplay(line: string): string {
  const g = line.trim() || '-'
  return `   ${g}`
}

function unitToBytes(n: number, unit: string): number {
  const u = unit.toUpperCase()
  const mul =
    u === 'KB' ? 1024
    : u === 'MB' ? 1024 ** 2
    : u === 'GB' ? 1024 ** 3
    : u === 'TB' ? 1024 ** 4
    : 1
  return n * mul
}

export function parseWingetDownloadLine(
  line: string,
): { downloaded: string; total: string; pct: number } | null {
  const m = WINGET_SIZE_RE.exec(line)
  if (!m) return null
  const doneN = Number(m[1])
  const totalN = Number(m[3])
  if (!Number.isFinite(doneN) || !Number.isFinite(totalN) || totalN <= 0) return null
  const doneUnit = m[2]!
  const totalUnit = m[4]!
  const pct = Math.round(
    Math.min(
      100,
      Math.max(0, (unitToBytes(doneN, doneUnit) / unitToBytes(totalN, totalUnit)) * 100),
    ),
  )
  return {
    downloaded: `${m[1]} ${doneUnit.toUpperCase()}`,
    total: `${m[3]} ${totalUnit.toUpperCase()}`,
    pct,
  }
}

function formatBar(pct: number, width = 16): string {
  const p = Math.max(0, Math.min(100, Math.round(pct)))
  const filled = Math.round((p / 100) * width)
  const head = filled > 0 ? '='.repeat(Math.max(0, filled - 1)) + '>' : ''
  const rest = ' '.repeat(Math.max(0, width - head.length))
  return `[${head}${rest}]`
}

function formatDownloadLine(downloaded: string, total: string, pct: number): string {
  return `下载 ${downloaded} / ${total}  ${formatBar(pct)} ${String(pct).padStart(3, ' ')}%`
}

function clearSpinnerLine(session: SpinnerConsoleSession, sink: SpinnerConsoleSink) {
  if (!session.inSpinner) return
  sink.remove(spinnerLineId(session.spinnerSlot))
  session.inSpinner = false
}

function emitSpinner(session: SpinnerConsoleSession, line: string, sink: SpinnerConsoleSink) {
  // 已有下载进度时不再刷转圈，避免盖住有效信息
  if (session.hasDownloadLine) return
  session.inSpinner = true
  sink.upsert(spinnerLineId(session.spinnerSlot), formatSpinnerDisplay(line), 'dim')
}

function emitDownload(
  session: SpinnerConsoleSession,
  line: string,
  sink: SpinnerConsoleSink,
): ApplyConsoleChunkResult | null {
  const parsed = parseWingetDownloadLine(line)
  if (!parsed) return null
  clearSpinnerLine(session, sink)
  session.hasDownloadLine = true
  sink.upsert(
    WINGET_DOWNLOAD_LINE_ID,
    formatDownloadLine(parsed.downloaded, parsed.total, parsed.pct),
  )
  return {
    downloadPct: parsed.pct,
    downloaded: parsed.downloaded,
    total: parsed.total,
  }
}

function emitContent(session: SpinnerConsoleSession, line: string, sink: SpinnerConsoleSink) {
  clearSpinnerLine(session, sink)
  const text = line.replace(/\s+$/u, '')
  if (!text.trim()) return
  // 原始 winget 进度块行：已转成下载行，勿再 append
  if (parseWingetDownloadLine(text)) return
  sink.append(text)
  session.spinnerSlot += 1
}

/** 任务结束时清掉残留转圈行与半行缓冲。 */
export function finishSpinnerConsoleSession(
  session: SpinnerConsoleSession,
  sink: SpinnerConsoleSink,
): void {
  clearSpinnerLine(session, sink)
  session.pending = ''
}

/**
 * 处理一块 console：\r 原地刷新转圈/下载；正文 append；半行进 pending。
 */
export function applySpinnerConsoleChunk(
  session: SpinnerConsoleSession,
  chunk: string,
  sink: SpinnerConsoleSink,
): ApplyConsoleChunkResult | undefined {
  if (!chunk) return undefined

  let text = scrubConsoleControls(session.pending + chunk)
  session.pending = ''

  let buf = ''
  let i = 0
  let lastDownload: ApplyConsoleChunkResult | undefined

  while (i < text.length) {
    const c = text[i]!
    if (c === '\r') {
      if (i + 1 < text.length && text[i + 1] === '\n') {
        const r = flushBuffer(session, buf, sink, 'hard')
        if (r) lastDownload = r
        buf = ''
        i += 2
        continue
      }
      const r = flushBuffer(session, buf, sink, 'soft')
      if (r) lastDownload = r
      buf = ''
      i += 1
      continue
    }
    if (c === '\n') {
      const r = flushBuffer(session, buf, sink, 'hard')
      if (r) lastDownload = r
      buf = ''
      i += 1
      continue
    }
    buf += c
    i += 1
  }

  if (!buf) return lastDownload

  if (isSpinnerOnlyLine(buf)) {
    emitSpinner(session, buf, sink)
    return lastDownload
  }
  const half = emitDownload(session, buf, sink)
  if (half) return half
  session.pending = buf
  return lastDownload
}

function flushBuffer(
  session: SpinnerConsoleSession,
  buf: string,
  sink: SpinnerConsoleSink,
  mode: 'hard' | 'soft',
): ApplyConsoleChunkResult | undefined {
  if (!buf.length) return undefined
  if (isSpinnerOnlyLine(buf)) {
    emitSpinner(session, buf, sink)
    return undefined
  }
  const dl = emitDownload(session, buf, sink)
  if (dl) return dl
  // \r 刷未识别正文：软刷新不 append，避免半截进度块刷屏
  if (mode === 'soft') {
    session.pending = buf
    return undefined
  }
  emitContent(session, buf, sink)
  return undefined
}
