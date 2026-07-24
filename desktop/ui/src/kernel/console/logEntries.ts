/**
 * 命令/日志共用的条目模型与纯函数（组件各自独立，只复用方法）。
 * - 无 id：追加新行（内部生成 id）
 * - 有 id：首次追加，再次同 id 则原位更新文案
 */

export type LogEntryTone = 'plain' | 'dim' | 'ok' | 'warn' | 'err'

export type LogEntry = {
  id: string
  text: string
  tone?: LogEntryTone
}

export type LogEntryInput = {
  id?: string
  text: string
  tone?: LogEntryTone
}

export type LogEntriesState = {
  entries: LogEntry[]
  /** 业务 id → 下标，仅含调用方传入的稳定 id */
  indexById: Map<string, number>
  seq: number
}

const DEFAULT_MAX = 2000

export function createLogEntriesState(): LogEntriesState {
  return { entries: [], indexById: new Map(), seq: 0 }
}

function nextAutoId(state: LogEntriesState): string {
  state.seq += 1
  return `__auto_${state.seq}`
}

/**
 * 追加或按 id 原位更新。
 * @returns 新的 entries 数组（便于赋给 ref）
 */
export function applyLogEntry(
  state: LogEntriesState,
  input: string | LogEntryInput,
  options?: { maxEntries?: number },
): LogEntry[] {
  const max = options?.maxEntries ?? DEFAULT_MAX
  const text = typeof input === 'string' ? input : input.text
  if (!text && text !== '') return state.entries

  const tone = typeof input === 'string' ? undefined : input.tone
  const businessId = typeof input === 'string' ? undefined : input.id?.trim()

  if (businessId) {
    const at = state.indexById.get(businessId)
    if (at !== undefined && state.entries[at]) {
      const prev = state.entries[at]!
      state.entries[at] = { ...prev, text, tone: tone ?? prev.tone }
      return state.entries.slice()
    }
    const entry: LogEntry = { id: businessId, text, tone }
    state.entries.push(entry)
    state.indexById.set(businessId, state.entries.length - 1)
  } else {
    state.entries.push({ id: nextAutoId(state), text, tone })
  }

  trimLogEntries(state, max)
  return state.entries.slice()
}

/** 淘汰最旧的自动行；尽量保留带业务 id 的行。 */
export function trimLogEntries(state: LogEntriesState, max: number): void {
  if (state.entries.length <= max) return
  const overflow = state.entries.length - max
  let removed = 0
  const next: LogEntry[] = []
  for (const e of state.entries) {
    if (removed < overflow && e.id.startsWith('__auto_')) {
      removed++
      continue
    }
    next.push(e)
  }
  while (next.length > max) next.shift()
  state.entries = next
  state.indexById.clear()
  state.entries.forEach((e, i) => {
    if (!e.id.startsWith('__auto_')) state.indexById.set(e.id, i)
  })
}

export function removeLogEntry(state: LogEntriesState, id: string): LogEntry[] {
  const at = state.indexById.get(id)
  if (at === undefined) return state.entries.slice()
  state.entries.splice(at, 1)
  state.indexById.clear()
  state.entries.forEach((e, i) => {
    if (!e.id.startsWith('__auto_')) state.indexById.set(e.id, i)
  })
  return state.entries.slice()
}

export function clearLogEntries(state: LogEntriesState): LogEntry[] {
  state.entries = []
  state.indexById.clear()
  state.seq = 0
  return []
}

export function logEntriesToText(entries: LogEntry[]): string {
  return entries.map((e) => e.text).join('\n')
}
