/**
 * 进主壳后的静默任务状态（宿主 SilentTaskRunner ↔ 底栏 UI）。
 */
import { post, subscribe, type HostMessage } from './bus'

/** 与宿主 SilentTaskStatus 对齐（小写）。 */
export type SilentTaskStatus =
  | 'pending'
  | 'running'
  | 'succeeded'
  | 'failed'
  | 'cancelled'

/** 单条静默任务。 */
export type SilentTask = {
  id: string
  title: string
  status: SilentTaskStatus
  progress: number
  detail?: string | null
  updatedAt?: string
}

/** 队列快照。 */
export type SilentQueueSnapshot = {
  activeCount: number
  totalQueued: number
  tasks: SilentTask[]
}

type Listener = (snap: SilentQueueSnapshot) => void

const listeners = new Set<Listener>()
let snap: SilentQueueSnapshot = { activeCount: 0, totalQueued: 0, tasks: [] }
let busHooked = false

/**
 * 规范化宿主回传的任务对象（兼容 camel / Pascal）。
 * @param raw - 原始对象
 */
export function normalizeSilentTask(raw: unknown): SilentTask | null {
  if (!raw || typeof raw !== 'object') return null
  const o = raw as Record<string, unknown>
  const id = String(o.id ?? o.Id ?? '').trim()
  if (!id) return null
  const statusRaw = String(o.status ?? o.Status ?? 'pending').toLowerCase()
  const status = (
    ['pending', 'running', 'succeeded', 'failed', 'cancelled'].includes(statusRaw)
      ? statusRaw
      : 'pending'
  ) as SilentTaskStatus
  const progress = Math.max(0, Math.min(100, Number(o.progress ?? o.Progress ?? 0) || 0))
  return {
    id,
    title: String(o.title ?? o.Title ?? id),
    status,
    progress,
    detail: (o.detail ?? o.Detail) as string | null | undefined,
    updatedAt: (o.updatedAt ?? o.UpdatedAt) as string | undefined,
  }
}

function emit() {
  const copy: SilentQueueSnapshot = {
    activeCount: snap.activeCount,
    totalQueued: snap.totalQueued,
    tasks: snap.tasks.slice(),
  }
  listeners.forEach((fn) => fn(copy))
}

function applyQueue(msg: HostMessage) {
  const tasksRaw = Array.isArray(msg.tasks) ? msg.tasks : []
  const tasks = tasksRaw
    .map((t) => normalizeSilentTask(t))
    .filter((t): t is SilentTask => t != null)
  snap = {
    activeCount: Number(msg.activeCount ?? 0) || 0,
    totalQueued: Number(msg.totalQueued ?? msg.activeCount ?? 0) || 0,
    tasks,
  }
  emit()
}

function upsertTask(task: SilentTask) {
  const rest = snap.tasks.filter((t) => t.id !== task.id)
  const activeStatuses: SilentTaskStatus[] = ['pending', 'running']
  const next = [task, ...rest]
  const active = next.filter((t) => activeStatuses.includes(t.status))
  snap = {
    activeCount: active.length,
    totalQueued: active.length,
    tasks: next,
  }
  emit()
}

function onBus(msg: HostMessage) {
  if (msg.type === 'silent.queue') {
    applyQueue(msg)
    return
  }
  if (msg.type === 'silent.task') {
    const task = normalizeSilentTask(msg.task)
    if (task) upsertTask(task)
  }
}

/** 确保只挂接一次宿主消息。 */
function ensureBus() {
  if (busHooked) return
  busHooked = true
  subscribe(onBus)
}

/**
 * 订阅静默队列快照。
 * @param fn - 收到完整快照
 */
export function subscribeSilentTasks(fn: Listener): () => void {
  ensureBus()
  listeners.add(fn)
  fn({
    activeCount: snap.activeCount,
    totalQueued: snap.totalQueued,
    tasks: snap.tasks.slice(),
  })
  return () => listeners.delete(fn)
}

/** 向宿主请求当前队列。 */
export function requestSilentList() {
  ensureBus()
  post({ type: 'silent.list' })
}

/**
 * 取消指定静默任务。
 * @param id - 任务 id
 */
export function cancelSilentTask(id: string) {
  const sid = String(id ?? '').trim()
  if (!sid) return
  post({ type: 'silent.cancel', id: sid })
}

/** 当前进行中的任务（pending/running），用于底栏摘要。 */
export function pickActiveTask(tasks: SilentTask[]): SilentTask | null {
  return (
    tasks.find((t) => t.status === 'running') ??
    tasks.find((t) => t.status === 'pending') ??
    null
  )
}
