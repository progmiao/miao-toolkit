/**
 * 浏览器调试 Mock 宿主：无 WebView2 时应答 IPC，便于 Vite 直开调试。
 * 目录状态可随 run-job 变更，用于验证「先装 Volta」等前置条件流程。
 */
import type { HostMessage } from './bus'
import { MOCK_DAILY, MOCK_DEV } from './mockData'

type Emit = (msg: HostMessage) => void

let emit: Emit | null = null

type MockSilentTask = {
  id: string
  title: string
  status: 'pending' | 'running' | 'succeeded' | 'failed' | 'cancelled'
  progress: number
  detail?: string
  updatedAt: string
}

const mockSilentTasks: Record<string, MockSilentTask> = {}
let mockSilentStarted = false

function replySilentQueue() {
  const tasks = Object.values(mockSilentTasks).sort((a, b) =>
    a.updatedAt < b.updatedAt ? 1 : -1,
  )
  const activeCount = tasks.filter(
    (t) => t.status === 'pending' || t.status === 'running',
  ).length
  queueMicrotask(() =>
    emit?.({
      type: 'silent.queue',
      activeCount,
      totalQueued: activeCount,
      tasks,
    }),
  )
}

function emitSilentTask(task: MockSilentTask) {
  queueMicrotask(() => emit?.({ type: 'silent.task', task }))
}

/** 模拟进主壳后的 Node 版本目录同步。 */
function ensureMockSilentSync() {
  if (mockSilentStarted) return
  mockSilentStarted = true
  const id = 'cache.versions.node'
  const task: MockSilentTask = {
    id,
    title: '同步 Node.js 版本目录',
    status: 'pending',
    progress: 0,
    detail: '排队中',
    updatedAt: new Date().toISOString(),
  }
  mockSilentTasks[id] = task
  replySilentQueue()
  emitSilentTask(task)

  setTimeout(() => {
    const cur = mockSilentTasks[id]
    if (!cur || cur.status === 'cancelled') return
    const running: MockSilentTask = {
      ...cur,
      status: 'running',
      progress: 12,
      detail: '执行中',
      updatedAt: new Date().toISOString(),
    }
    mockSilentTasks[id] = running
    emitSilentTask(running)
    replySilentQueue()
  }, 200)

  setTimeout(() => {
    const cur = mockSilentTasks[id]
    if (!cur || cur.status === 'cancelled') return
    const mid: MockSilentTask = {
      ...cur,
      progress: 68,
      detail: '增量写入…',
      updatedAt: new Date().toISOString(),
    }
    mockSilentTasks[id] = mid
    emitSilentTask(mid)
  }, 700)

  setTimeout(() => {
    const cur = mockSilentTasks[id]
    if (!cur || cur.status === 'cancelled') return
    const done: MockSilentTask = {
      ...cur,
      status: 'succeeded',
      progress: 100,
      detail: '完成',
      updatedAt: new Date().toISOString(),
    }
    mockSilentTasks[id] = done
    emitSilentTask(done)
    replySilentQueue()
  }, 1400)
}

/**
 * 注册消息回传（由 bus 在无宿主时调用）。
 * @param fn - 将模拟宿主回传推给订阅者
 */
export function setMockEmitter(fn: Emit) {
  emit = fn
}

/**
 * 处理来自 UI 的请求并异步回传 Mock 数据。
 * @param message - 与真实 HostBridge 相同的 type 协议
 */
export function handleMockRequest(message: Record<string, unknown>) {
  const type = String(message.type ?? '')
  const reply = (msg: HostMessage) => {
    queueMicrotask(() => emit?.(msg))
  }

  switch (type) {
    case 'boot.ui-ready':
      // 宿主占位关闭；Mock 无层 A，忽略
      break

    case 'boot.subscribe':
      reply({
        type: 'boot.progress',
        stage: 'mock',
        message: 'Mock 启动…',
        percent: 40,
        phase: 'progress',
      })
      reply({ type: 'boot.log', message: '浏览器 Mock：跳过本地库初始化' })
      reply({
        type: 'boot.progress',
        stage: 'ready',
        message: '就绪',
        percent: 100,
        phase: 'progress',
      })
      reply({ type: 'boot.done', ok: true, fastPath: true })
      break

    case 'ping':
      reply({ type: 'pong', at: new Date().toISOString() })
      break

    case 'silent.list':
      replySilentQueue()
      ensureMockSilentSync()
      break

    case 'silent.cancel': {
      const id = String(message.id ?? '')
      if (id && mockSilentTasks[id]) {
        mockSilentTasks[id] = {
          ...mockSilentTasks[id],
          status: 'cancelled',
          detail: '已取消',
          progress: 0,
          updatedAt: new Date().toISOString(),
        }
      }
      reply({ type: 'silent.cancel.ok', id, ok: true })
      replySilentQueue()
      break
    }

    case 'get-app-info':
      reply({ type: 'app-info', name: 'Miao', version: '0.1.0-mock' })
      break

    case 'get-catalog': {
      const group = String(message.group ?? '')
      const items = group === 'daily' ? MOCK_DAILY : group === 'dev' ? MOCK_DEV : [...MOCK_DAILY, ...MOCK_DEV]
      reply({ type: 'catalog', group, items })
      break
    }

    case 'get-groups':
      reply({
        type: 'groups',
        groups: [
          { id: 'daily', name: '日常工具', sort: 10 },
          { id: 'dev', name: '开发工具', sort: 20 },
        ],
      })
      break

    case 'get-i18n':
    case 'settings.get':
    case 'get-i18n':
      reply({ type: 'settings', locale: 'zh' })
      reply({ type: 'i18n', locale: 'zh', map: {} })
      break

    case 'settings.set-locale':
      reply({ type: 'settings', locale: String(message.locale ?? 'zh') })
      break

    case 'settings.set-appearance':
      reply({ type: 'settings', locale: 'zh', appearance: message.appearance })
      break

    case 'sites.list':
      reply({
        type: 'sites',
        categories: [
          { id: 'c1', name: '常用', sort: 10, source: 'system', editable: false },
        ],
        sites: [
          {
            id: 's1',
            categoryId: 'c1',
            title: '示例站点',
            url: 'https://example.com',
            sort: 10,
            source: 'system',
            editable: false,
          },
        ],
      })
      break

    case 'utilities.list':
      reply({
        type: 'utilities',
        data: {
          title: '工具集',
          body: '浏览器 Mock：GUID 等小工具。',
          items: [
            { id: 'guid', name: 'GUID 生成', description: '批量生成 GUID' },
          ],
        },
      })
      break

    case 'utilities.guid': {
      const count = Math.min(100, Math.max(1, Number(message.count) || 1))
      const values = Array.from({ length: count }, () => crypto.randomUUID())
      reply({ type: 'utilities.guid', data: { values } })
      break
    }

    case 'volta.list':
    case 'node.list': {
      const tool = String(message.tool ?? 'node')
      const voltaOk = MOCK_DEV.find((i) => i.id === 'volta')?.status === 'installed'
      reply({
        type: 'volta.versions',
        tool,
        ltsOnly: message.ltsOnly !== false,
        /** 与目录中 Volta 工具状态一致，便于调试前置条件提示 */
        voltaAvailable: voltaOk,
        conflicts: [],
        items: voltaOk
          ? [
              {
                version: '22.14.0',
                lts: tool === 'node' ? 'Jod' : 'latest',
                installed: true,
                isDefault: true,
                isCurrent: true,
              },
              {
                version: '20.18.1',
                lts: tool === 'node' ? 'Iron' : null,
                installed: false,
                isDefault: false,
                isCurrent: false,
              },
              {
                version: '18.20.5',
                lts: tool === 'node' ? 'Hydrogen' : null,
                installed: false,
                isDefault: false,
                isCurrent: false,
              },
            ]
          : [],
      })
      break
    }

    case 'claude.status':
      reply({
        type: 'claude.status',
        status: {
          installed: false,
          version: null,
          wingetManaged: false,
          settingsExists: false,
          apiMode: null,
          proxyMode: null,
          hasSecrets: false,
        },
        secrets: {},
        plugins: [{ id: 'superpowers@superpowers-marketplace', label: 'superpowers', featured: true }],
      })
      break

    case 'run-job': {
      const jobId = String(message.jobId ?? 'mock-job')
      const toolId = String(message.toolId ?? '')
      const action = String(message.action ?? '')
      reply({ type: 'job-started', jobId, toolId, action })
      setTimeout(() => {
        reply({ type: 'job-event', jobId, kind: 'log', message: '[Mock] 浏览器调试模式：未真实执行安装' })
        reply({
          type: 'job-event',
          jobId,
          kind: 'console',
          message: '> powershell.exe -NoProfile -Command "(mock)"',
        })
        reply({ type: 'job-event', jobId, kind: 'console', message: '[Mock] skip real winget/volta' })
        reply({ type: 'job-event', jobId, kind: 'progress', message: '100' })
        // 同步更新 Mock 目录状态，便于「安装 Volta」后解锁 Node 等工具
        const all = [...MOCK_DAILY, ...MOCK_DEV]
        const item = all.find((i) => i.id === toolId)
        if (item) {
          if (action === 'install') {
            item.status = 'installed'
            item.updateAvailable = false
            if (!item.version) item.version = 'mock'
          } else if (action === 'uninstall') {
            item.status = 'missing'
            item.version = undefined
            item.updateAvailable = false
          }
        }
        reply({ type: 'job-finished', jobId, ok: true, exitCode: 0, detail: 'mock' })
      }, 400)
      break
    }

    case 'open-url':
      if (typeof message.url === 'string') window.open(message.url, '_blank')
      reply({ type: 'open-url.ok', url: String(message.url ?? '') })
      break

    case 'dialog.pick-folder':
      reply({ type: 'dialog.folder', path: '' })
      break

    default:
      console.info('[miao mock] 未模拟的消息', message)
      break
  }
}
