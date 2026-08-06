/**
 * Vue ↔ 宿主消息总线；无 WebView2 时挂接 Mock 回传。
 */
import { host } from './host'
import { setMockEmitter } from './mockHost'

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
  /**
   * panel 工作区键：与 seeds `ui.entry` 一致；一级页嵌入 `dev/{uiEntry}`。
   * 深链用 `/dev?tool={目录 id}`。generic 可空。
   */
  uiEntry?: string | null
  tags: string[]
  /** 已安装且有可用更新时为 true */
  updateAvailable?: boolean
}

/** 一级分类。 */
export type CatalogGroup = {
  id: string
  name: string
  sort: number
}

/** Volta / Node 版本行。 */
export type VoltaVersion = {
  version: string
  lts?: string | null
  date?: string | null
  installed: boolean
  isDefault: boolean
  isCurrent: boolean
}

/** @deprecated 使用 VoltaVersion */
export type NodeVersion = VoltaVersion

/** 宿主回传消息（字段按 `type` 选用；未用字段可忽略）。 */
export type HostMessage = {
  /** 消息类型，如 `catalog` / `job-started` / `job-event` / `job-finished` / `error` */
  type: string
  /** 任务 id（job-*） */
  jobId?: string
  /** job-event 子类型：progress | task | batch | console | log */
  kind?: string
  /** 日志/进度/错误文案 */
  message?: string
  at?: string
  /** job-finished：是否成功 */
  ok?: boolean
  exitCode?: number
  detail?: string
  items?: CatalogItem[] | VoltaVersion[]
  groups?: CatalogGroup[]
  /** 目录分组过滤回显：daily | dev */
  group?: string
  /** volta.versions 对应工具 */
  tool?: string
  name?: string
  version?: string
  locale?: string
  /** 外观配置（settings / appearance） */
  appearance?: unknown
  map?: Record<string, string>
  ltsOnly?: boolean
  voltaAvailable?: boolean
  conflicts?: string[]
  categories?: unknown[]
  sites?: unknown[]
  json?: string
  data?: unknown
  toolId?: string
  action?: string
  versions?: string[]
  path?: string
  /** dialog.folder：所选目录是否含 package.json（pin 前置校验） */
  hasPackageJson?: boolean
  url?: string
  status?: unknown
  secrets?: unknown
  plugins?: unknown
  pluginsInstall?: unknown
  pluginsUpdate?: unknown
  pluginsUninstall?: unknown
  /** boot.progress */
  stage?: string
  percent?: number
  phase?: string
  /** boot.done */
  fastPath?: boolean
  degraded?: boolean
  /** silent.queue / silent.task */
  activeCount?: number
  totalQueued?: number
  tasks?: unknown[]
  task?: unknown
  id?: string
}

/** @deprecated 使用 HostMessage */
export type JobEvent = HostMessage

type Handler = (msg: HostMessage) => void
const handlers = new Set<Handler>()

function dispatch(msg: HostMessage) {
  handlers.forEach((h) => h(msg))
}

function onMessage(event: MessageEvent) {
  try {
    const data =
      typeof event.data === 'string' ? JSON.parse(event.data) : event.data
    dispatch(data as HostMessage)
  } catch {
    /* ignore */
  }
}

let listening = false

/** 确保只注册一次宿主 message / Mock 监听。 */
export function ensureHostListener() {
  if (listening) return
  listening = true
  if (host.isMock()) {
    setMockEmitter(dispatch)
    console.info('[miao] 浏览器 Mock 模式：使用本地示例数据调试')
  } else {
    host.addMessageListener(onMessage)
  }
}

/** 订阅宿主消息。 */
export function subscribe(handler: Handler) {
  ensureHostListener()
  handlers.add(handler)
  return () => handlers.delete(handler)
}

/** 向宿主发消息（Mock 模式下由 mockHost 应答）。 */
export function post(message: Record<string, unknown>) {
  ensureHostListener()
  host.post(message)
}

/** 是否处于浏览器 Mock 调试。 */
export function isBrowserMock() {
  return host.isMock()
}
