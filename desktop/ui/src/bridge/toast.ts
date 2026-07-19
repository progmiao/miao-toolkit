/**
 * 全局顶部消息提示（Toast）总线。
 * 任意页面调用 `showToast`；由 AppShell 内的 AppToast 统一渲染。
 */
export type ToastKind = 'info' | 'ok' | 'warn' | 'error'

/** 单条提示选项。 */
export type ToastOptions = {
  /** 语义色：info | ok | warn | error；默认 info */
  kind?: ToastKind
  /** 展示时长（毫秒）；默认 2800，最短 1200 */
  durationMs?: number
}

/** 队列中的一条提示。 */
export type ToastItem = {
  /** 唯一 id，用于关闭 */
  id: number
  /** 文案 */
  message: string
  /** 语义 */
  kind: ToastKind
  /** 自动消失时长 */
  durationMs: number
}

type Listener = (items: ToastItem[]) => void

const listeners = new Set<Listener>()
/** 当前可见队列（新消息追加到末尾，最多保留若干条）。 */
let queue: ToastItem[] = []
let seq = 0
const MAX_VISIBLE = 4
const timers = new Map<number, ReturnType<typeof setTimeout>>()

function emit() {
  const snapshot = queue.slice()
  listeners.forEach((fn) => fn(snapshot))
}

/**
 * 订阅队列变化（AppToast 挂载时注册）。
 * @param fn - 收到完整队列快照
 * @returns 取消订阅
 */
export function subscribeToasts(fn: Listener): () => void {
  listeners.add(fn)
  fn(queue.slice())
  return () => listeners.delete(fn)
}

/**
 * 显示顶部居中提示；几秒后自动消失。
 * 后续任意业务消息均应走此方法，勿在页面内再做 inline flash。
 * @param message - 提示文案（勿传空）
 * @param options - 可选 kind / 时长
 * @returns 提示 id；空文案时返回 -1
 */
export function showToast(message: string, options?: ToastOptions): number {
  const text = String(message ?? '').trim()
  if (!text) return -1
  const id = ++seq
  const kind = options?.kind ?? 'info'
  const rawDur = options?.durationMs ?? 2800
  const durationMs = Number.isFinite(rawDur) ? Math.max(1200, Math.round(rawDur)) : 2800
  const item: ToastItem = { id, message: text, kind, durationMs }
  queue = [...queue, item].slice(-MAX_VISIBLE)
  emit()
  const t = setTimeout(() => dismissToast(id), durationMs)
  timers.set(id, t)
  return id
}

/**
 * 手动关闭一条提示。
 * @param id - showToast 返回的 id
 */
export function dismissToast(id: number): void {
  const t = timers.get(id)
  if (t) {
    clearTimeout(t)
    timers.delete(id)
  }
  const next = queue.filter((x) => x.id !== id)
  if (next.length === queue.length) return
  queue = next
  emit()
}
