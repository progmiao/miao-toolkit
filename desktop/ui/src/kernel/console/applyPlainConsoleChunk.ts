/**
 * 通用 console chunk：控制符清洗、\r/\n 分帧、可选 CLI 转圈、正文 append。
 * 不含 winget / git / uv 等业务进度识别。
 */

import { scrubConsoleControls, stripLeadingClearResidue } from './scrubControls'

export type PlainConsoleSink = {
  append: (text: string, tone?: 'plain' | 'dim' | 'ok' | 'warn' | 'err' | 'accent') => void
  upsert: (id: string, text: string, tone?: 'plain' | 'dim' | 'ok' | 'warn' | 'err' | 'accent') => void
  remove: (id: string) => void
}

export type PlainConsoleSession = {
  pending: string
  spinnerSlot: number
  inSpinner: boolean
}

/** 仅转圈字符的一行（可带空白）。 */
const SPINNER_ONLY_RE = /^\s*[-\\|\/]\s*$/

export function createPlainConsoleSession(): PlainConsoleSession {
  return { pending: '', spinnerSlot: 0, inSpinner: false }
}

export function isSpinnerOnlyLine(line: string): boolean {
  return SPINNER_ONLY_RE.test(line)
}

function spinnerLineId(slot: number): string {
  return `console:spinner:${slot}`
}

function formatSpinnerDisplay(line: string): string {
  const g = line.trim() || '-'
  return `   ${g}`
}

function clearSpinnerLine(session: PlainConsoleSession, sink: PlainConsoleSink) {
  if (!session.inSpinner) return
  sink.remove(spinnerLineId(session.spinnerSlot))
  session.inSpinner = false
}

function emitSpinner(session: PlainConsoleSession, line: string, sink: PlainConsoleSink) {
  session.inSpinner = true
  sink.upsert(spinnerLineId(session.spinnerSlot), formatSpinnerDisplay(line), 'dim')
}

function emitContent(session: PlainConsoleSession, line: string, sink: PlainConsoleSink) {
  clearSpinnerLine(session, sink)
  let text = line.replace(/\s+$/u, '')
  text = stripLeadingClearResidue(text)
  if (!text.trim()) return
  // 协议行偶发漏进 console 时丢弃
  if (/^##(?:progress|task|batch|log)\b/i.test(text.trim())) return
  sink.append(text)
  session.spinnerSlot += 1
}

/** 任务结束时清掉残留转圈行与半行缓冲。 */
export function finishPlainConsoleSession(
  session: PlainConsoleSession,
  sink: PlainConsoleSink,
): void {
  clearSpinnerLine(session, sink)
  session.pending = ''
}

/**
 * 处理一块 console：\r 原地刷新转圈；正文 append；半行进 pending。
 */
export function applyPlainConsoleChunk(
  session: PlainConsoleSession,
  chunk: string,
  sink: PlainConsoleSink,
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

  if (isSpinnerOnlyLine(buf)) {
    emitSpinner(session, buf, sink)
    return
  }
  // 半行：软挂起，等后续 chunk
  session.pending = buf
}

function flushBuffer(
  session: PlainConsoleSession,
  buf: string,
  sink: PlainConsoleSink,
  mode: 'hard' | 'soft',
): void {
  if (!buf.length) return
  if (isSpinnerOnlyLine(buf)) {
    emitSpinner(session, buf, sink)
    return
  }
  // \r 刷未识别正文：软刷新不 append，避免半截刷屏
  if (mode === 'soft') {
    session.pending = buf
    return
  }
  emitContent(session, buf, sink)
}
