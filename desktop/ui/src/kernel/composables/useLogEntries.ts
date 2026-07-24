/**
 * 命令/日志条目缓冲：供独立 CommandPane / LogPane 使用。
 */
import { ref, type Ref } from 'vue'
import {
  applyLogEntry,
  clearLogEntries,
  createLogEntriesState,
  logEntriesToText,
  removeLogEntry,
  type LogEntry,
  type LogEntryInput,
  type LogEntriesState,
} from '@kernel/console/logEntries'

export type UseLogEntriesApi = {
  entries: Ref<LogEntry[]>
  append: (input: string | LogEntryInput) => void
  upsert: (input: LogEntryInput & { id: string }) => void
  remove: (id: string) => void
  clear: () => void
  toText: () => string
  _state: LogEntriesState
}

export function useLogEntries(options?: { maxEntries?: number }): UseLogEntriesApi {
  const state = createLogEntriesState()
  const entries = ref<LogEntry[]>([])
  const maxEntries = options?.maxEntries

  function sync() {
    entries.value = state.entries.slice()
  }

  function append(input: string | LogEntryInput) {
    applyLogEntry(state, input, { maxEntries })
    sync()
  }

  function upsert(input: LogEntryInput & { id: string }) {
    applyLogEntry(state, { ...input, id: input.id }, { maxEntries })
    sync()
  }

  function remove(id: string) {
    removeLogEntry(state, id)
    sync()
  }

  function clear() {
    clearLogEntries(state)
    sync()
  }

  function toText() {
    return logEntriesToText(entries.value)
  }

  return { entries, append, upsert, remove, clear, toText, _state: state }
}
