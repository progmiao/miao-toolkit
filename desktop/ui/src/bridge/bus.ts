/**
 * Vue ↔ 宿主消息总线。
 */
import { host } from './host'

/** 与 C# CatalogItemDto 对齐。 */
export type CatalogItem = {
  id: string
  name: string
  description: string
  group: string
  status: string
  version?: string | null
  actions: string[]
  /** generic | panel */
  uiMode: string
  tags: string[]
}

/** 一级分类。 */
export type CatalogGroup = {
  id: string
  name: string
  sort: number
}

export type JobEvent = {
  type: string
  jobId?: string
  kind?: string
  message?: string
  at?: string
  ok?: boolean
  exitCode?: number
  detail?: string
  items?: CatalogItem[]
  groups?: CatalogGroup[]
  group?: string
  name?: string
  version?: string
}

type Handler = (msg: JobEvent) => void
const handlers = new Set<Handler>()

function onMessage(event: MessageEvent) {
  try {
    const data =
      typeof event.data === 'string' ? JSON.parse(event.data) : event.data
    handlers.forEach((h) => h(data as JobEvent))
  } catch {
    /* ignore */
  }
}

let listening = false

/** 确保只注册一次宿主 message 监听。 */
export function ensureHostListener() {
  if (listening) return
  listening = true
  host.addMessageListener(onMessage)
}

/** 订阅宿主消息。 */
export function subscribe(handler: Handler) {
  ensureHostListener()
  handlers.add(handler)
  return () => handlers.delete(handler)
}

/** 向宿主发消息。 */
export function post(message: Record<string, unknown>) {
  ensureHostListener()
  host.post(message)
}
