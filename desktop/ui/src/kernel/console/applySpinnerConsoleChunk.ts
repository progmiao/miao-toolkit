/**
 * 命令窗：CLI 转圈（- \\ | /）按槽位 upsert，避免每帧 append。
 * 转圈结束后删除该行，不留下 `   \` 残留。
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
}

/** 仅转圈字符的一行（可带空白）。 */
const SPINNER_ONLY_RE = /^\s*[-\\|\/]\s*$/

export function createSpinnerConsoleSession(): SpinnerConsoleSession {
  return { pending: '', spinnerSlot: 0, inSpinner: false }
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

function clearSpinnerLine(session: SpinnerConsoleSession, sink: SpinnerConsoleSink) {
  if (!session.inSpinner) return
  sink.remove(spinnerLineId(session.spinnerSlot))
  session.inSpinner = false
}

function emitSpinner(session: SpinnerConsoleSession, line: string, sink: SpinnerConsoleSink) {
  session.inSpinner = true
  sink.upsert(spinnerLineId(session.spinnerSlot), formatSpinnerDisplay(line), 'dim')
}

function emitContent(session: SpinnerConsoleSession, line: string, sink: SpinnerConsoleSink) {
  clearSpinnerLine(session, sink)
  const text = line.replace(/\s+$/u, '')
  if (!text.trim()) return
  sink.append(text)
  // 正文之后的下一段转圈必须是新行
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
 * 处理一块 console：\r 原地刷新转圈；正文 append；半行进 pending。
 */
export function applySpinnerConsoleChunk(
  session: SpinnerConsoleSession,
  chunk: string,
  sink: SpinnerConsoleSink,
): void {
  if (!chunk) return

  let text = scrubConsoleControls(session.pending + chunk)
  session.pending = ''

  let buf = ''
  let i = 0
  while (i < text.length) {
    const c = text[i]!
    if (c === '\r') {
      if (i + 1 < text.length && text[i + 1] === '\n') {
        flushBuffer(session, buf, sink, 'hard')
        buf = ''
        i += 2
        continue
      }
      flushBuffer(session, buf, sink, 'soft')
      buf = ''
      i += 1
      continue
    }
    if (c === '\n') {
      flushBuffer(session, buf, sink, 'hard')
      buf = ''
      i += 1
      continue
    }
    buf += c
    i += 1
  }

  if (!buf) return

  // 半行：完整转圈可直接 upsert；其它内容暂存
  if (isSpinnerOnlyLine(buf)) {
    emitSpinner(session, buf, sink)
    return
  }
  session.pending = buf
}

function flushBuffer(
  session: SpinnerConsoleSession,
  buf: string,
  sink: SpinnerConsoleSink,
  mode: 'hard' | 'soft',
) {
  if (!buf.length) return
  if (isSpinnerOnlyLine(buf)) {
    emitSpinner(session, buf, sink)
    return
  }
  // \r 刷正文：仍作一行正文（少见）；\n 正常 append
  void mode
  emitContent(session, buf, sink)
}
