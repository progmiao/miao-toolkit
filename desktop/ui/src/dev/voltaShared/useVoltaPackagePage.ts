/**
 * Volta 包工具页共用逻辑（列表 / Tab / pin / Job 适配）。
 * 各工具保留独立 index.vue 模板与文案，仅复用本数据与操作层。
 */
import { computed, inject, nextTick, onMounted, onUnmounted, ref, watch } from 'vue'
import { post, subscribe, type VoltaVersion } from '@kernel/bridge/bus'
import { confirmDialog } from '@kernel/bridge/confirm'
import { normalizeSilentTask } from '@kernel/bridge/silentTasks'
import { showToast } from '@kernel/bridge/toast'
import { useShellTitle } from '@kernel/composables/useShellTitle'
import {
  DEV_SELECT_TOOL_KEY,
  DEV_WORKSPACE_OWNS_CONSOLE_KEY,
} from '../devPanelContext'
import { useDevPanelJob } from '../useDevPanelJob'
import {
  applyVoltaConsoleChunk,
  applyVoltaHostProgress,
  applyVoltaTaskLabel,
  createVoltaConsoleSession,
  VOLTA_FETCH_LINE_ID,
} from './voltaJobView'
import { matchesVersionFilter, tryApplyVersionListFromMessage } from './voltaVersionOps'

/** 功能 Tab（三工具一致）。 */
export type VoltaPackageTab = 'batch-install' | 'specify' | 'set-default' | 'batch-uninstall'

export type UseVoltaPackagePageOptions = {
  /** 宿主 toolId：node | pnpm | yarn */
  toolId: string
  /** 展示名：Node.js / pnpm / Yarn */
  displayName: string
  /** 嵌在一级页时为 true */
  embedded: boolean | (() => boolean)
  /** 静默缓存任务 id（仅 Node 目前有） */
  silentCacheTaskId?: string
}

const TABS: { id: VoltaPackageTab; label: string }[] = [
  { id: 'batch-install', label: '批量安装' },
  { id: 'specify', label: '指定版本' },
  { id: 'set-default', label: '设置默认' },
  { id: 'batch-uninstall', label: '批量卸载' },
]

/**
 * @param options - 工具身份与嵌入态
 */
export function useVoltaPackagePage(options: UseVoltaPackagePageOptions) {
  const { toolId, displayName, silentCacheTaskId } = options

  function isEmbedded() {
    return typeof options.embedded === 'function' ? options.embedded() : options.embedded
  }

  useShellTitle(computed(() => (isEmbedded() ? '开发工具' : displayName)))

  const selectTool = inject(DEV_SELECT_TOOL_KEY, null)
  const workspaceOwnsConsole = inject(DEV_WORKSPACE_OWNS_CONSOLE_KEY, null)

  const tab = ref<VoltaPackageTab>('batch-install')
  const versions = ref<VoltaVersion[]>([])
  const selected = ref<Record<string, boolean>>({})
  const defaultPick = ref<string | null>(null)
  const specifyVersion = ref('')
  const projectPath = ref('')
  const projectCanPin = ref(false)
  const filter = ref('')
  const loading = ref(false)
  const error = ref('')
  const conflicts = ref<string[]>([])
  const voltaAvailable = ref(true)

  let voltaSession = createVoltaConsoleSession()

  const {
    logEntries,
    commandEntries,
    progress,
    statusText,
    busy,
    consumeJobMessage,
    cancel,
    isShared,
    setViewAdapters,
    commandLog,
  } = useDevPanelJob({
    onFinished: () => {
      commandLog.remove(VOLTA_FETCH_LINE_ID)
      requestList(false)
    },
    onError: (message) => {
      error.value = message
      loading.value = false
    },
    formatStarted: (msg) => `开始：${msg.action ?? '任务'}`,
    onConsoleChunk: (chunk, api) => {
      const result = applyVoltaConsoleChunk(voltaSession, chunk, api)
      if (result.progress != null) api.setProgress(result.progress)
    },
    onHostProgress: (pct) => applyVoltaHostProgress(voltaSession, pct),
    onTaskLabel: (label, api) => {
      api.setStatusText(label)
      const next = applyVoltaTaskLabel(voltaSession, label)
      if (next != null) api.setProgress(next)
    },
  })

  function bindVoltaViewAdapters() {
    setViewAdapters({
      onConsoleChunk: (chunk, api) => {
        const result = applyVoltaConsoleChunk(voltaSession, chunk, api)
        if (result.progress != null) api.setProgress(result.progress)
      },
      onHostProgress: (pct) => applyVoltaHostProgress(voltaSession, pct),
      onTaskLabel: (label, api) => {
        api.setStatusText(label)
        const next = applyVoltaTaskLabel(voltaSession, label)
        if (next != null) api.setProgress(next)
      },
    })
  }

  watch(busy, (on, was) => {
    if (on && !was) voltaSession = createVoltaConsoleSession()
  })

  const versionSkeletonRows = ref(8)
  const verListEl = ref<HTMLElement | null>(null)
  let verListResizeObs: ResizeObserver | undefined

  /** 模板 `:ref` 回调，驱动骨架行数估算。 */
  function bindVerListEl(el: unknown) {
    const node =
      el && typeof el === 'object' && '$el' in el
        ? (el as { $el?: unknown }).$el
        : el
    verListEl.value = node instanceof HTMLElement ? node : null
  }

  function recalcVersionSkeletonRows() {
    const el = verListEl.value
    if (!el) return
    const styles = getComputedStyle(el)
    const padY =
      (Number.parseFloat(styles.paddingTop) || 0) + (Number.parseFloat(styles.paddingBottom) || 0)
    const available = Math.max(0, el.clientHeight - padY)
    const sample = el.querySelector('.ver-row') as HTMLElement | null
    let rowH = Number.parseFloat(styles.getPropertyValue('--ver-row-h')) || 38
    if (sample) {
      const ms = getComputedStyle(sample)
      rowH = sample.offsetHeight + (Number.parseFloat(ms.marginBottom) || 0)
    }
    if (rowH <= 0) return
    versionSkeletonRows.value = Math.max(1, Math.floor(available / rowH))
  }

  let unsub: (() => void) | undefined

  const listForTab = computed(() => {
    const q = filter.value
    return versions.value.filter((v) => {
      if (!matchesVersionFilter(v.version, v.lts, q)) return false
      if (tab.value === 'batch-install') return !v.installed
      if (tab.value === 'batch-uninstall') return v.installed
      return true
    })
  })

  const selectedList = computed(() =>
    listForTab.value.filter((v) => selected.value[v.version]).map((v) => v.version),
  )

  function requestList(forceRemote = true) {
    loading.value = true
    error.value = ''
    post({ type: 'volta.list', tool: toolId, ltsOnly: false, forceRemote })
  }

  onMounted(() => {
    if (workspaceOwnsConsole) workspaceOwnsConsole.value = true
    bindVoltaViewAdapters()

    unsub = subscribe((msg) => {
      if (msg.type === 'volta.versions' && Array.isArray(msg.items)) {
        if (msg.tool && msg.tool !== toolId) return
        loading.value = false
        versions.value = msg.items as VoltaVersion[]
        voltaAvailable.value = msg.voltaAvailable !== false
        conflicts.value = (msg.conflicts as string[]) ?? []
        for (const v of versions.value) {
          if (v.installed) {
            selected.value[v.version] = false
          } else if (selected.value[v.version] === undefined) {
            selected.value[v.version] = false
          }
        }
        if (!defaultPick.value) {
          const d =
            versions.value.find((x) => x.isDefault) ?? versions.value.find((x) => x.installed)
          defaultPick.value = d?.version ?? null
        }
        return
      }
      if (silentCacheTaskId && msg.type === 'silent.task') {
        const task = normalizeSilentTask(msg.task)
        if (task?.id === silentCacheTaskId && task.status === 'succeeded') {
          requestList(false)
        }
      }
      if (msg.type === 'dialog.folder') {
        const path = typeof msg.path === 'string' ? msg.path.trim() : ''
        projectPath.value = path
        projectCanPin.value = path.length > 0 && msg.hasPackageJson === true
        if (path && !projectCanPin.value) {
          showToast('所选目录缺少 package.json，无法指定版本', { kind: 'warn' })
        }
        return
      }
      if (msg.type === 'job-event' && msg.message) {
        tryApplyVersionListFromMessage(
          toolId,
          msg.message,
          versions,
          selected,
          defaultPick,
        )
      }
      if (msg.type === 'job-finished') {
        commandLog.remove(VOLTA_FETCH_LINE_ID)
        requestList(false)
      }
      if (!isShared) consumeJobMessage(msg)
    })
    requestList(false)
  })

  watch(verListEl, (el) => {
    verListResizeObs?.disconnect()
    verListResizeObs = undefined
    if (!el) return
    void nextTick(() => {
      recalcVersionSkeletonRows()
      verListResizeObs = new ResizeObserver(() => recalcVersionSkeletonRows())
      verListResizeObs.observe(el)
    })
  })

  watch(loading, (on) => {
    if (on && !versions.value.length) {
      void nextTick(() => recalcVersionSkeletonRows())
    }
  })

  onUnmounted(() => {
    unsub?.()
    setViewAdapters(null)
    verListResizeObs?.disconnect()
    verListResizeObs = undefined
    if (workspaceOwnsConsole) workspaceOwnsConsole.value = false
  })

  watch(tab, () => {
    selected.value = {}
    filter.value = ''
  })

  function selectTab(id: VoltaPackageTab) {
    if (busy.value) return
    tab.value = id
  }

  function runJob(action: string, versionsArg?: string[], extra?: Record<string, string>) {
    if (busy.value) return
    const list = versionsArg ?? selectedList.value
    if (!list.length) {
      showToast('请先选择或填写版本', { kind: 'warn' })
      return
    }
    const jobId = crypto.randomUUID().replaceAll('-', '')
    post({
      type: 'run-job',
      jobId,
      toolId,
      action,
      versions: list,
      ...extra,
    })
  }

  function runBatchInstall() {
    runJob('install')
  }

  function pickProjectDir() {
    if (busy.value) return
    post({ type: 'dialog.pick-folder' })
  }

  function runSpecifyPin() {
    const ver = (specifyVersion.value || '').trim().replace(/^v/i, '')
    if (!projectPath.value) {
      showToast('请先选择项目目录', { kind: 'warn' })
      return
    }
    if (!projectCanPin.value) {
      showToast('当前目录无法指定版本（需要 package.json）', { kind: 'warn' })
      return
    }
    if (!ver) {
      showToast('请选择版本号', { kind: 'warn' })
      return
    }
    runJob('pin', [ver], { projectPath: projectPath.value })
  }

  function runSetDefault() {
    if (!defaultPick.value) {
      showToast('请选择要设为默认的版本', { kind: 'warn' })
      return
    }
    runJob('set-default', [defaultPick.value])
  }

  const projectPinHint = computed(() => {
    if (!projectPath.value) return '请选择含 package.json 的项目目录后再指定版本'
    if (!projectCanPin.value) return '当前目录缺少 package.json，无法指定版本'
    return '可以指定版本（volta pin）'
  })

  const canRunSpecify = computed(
    () =>
      !!projectPath.value &&
      projectCanPin.value &&
      !!specifyVersion.value.trim() &&
      !busy.value &&
      !loading.value,
  )

  async function runBatchUninstall() {
    if (busy.value) return
    const list = selectedList.value
    if (!list.length) {
      showToast('请先选择或填写版本', { kind: 'warn' })
      return
    }
    const preview =
      list.length <= 5 ? list.join('、') : `${list.slice(0, 5).join('、')} 等 ${list.length} 个`
    const ok = await confirmDialog({
      title: '卸载确认',
      message: `确认卸载已选 ${displayName} 版本？\n${preview}`,
      confirmText: '卸载',
      cancelText: '取消',
      tone: 'danger',
    })
    if (!ok) return
    runJob('uninstall', list)
  }

  function installVoltaTool() {
    if (selectTool) {
      selectTool('volta')
      return
    }
    const jobId = crypto.randomUUID().replaceAll('-', '')
    post({ type: 'run-job', jobId, toolId: 'volta', action: 'install' })
  }

  // 独立页兜底：取消仍可用
  void cancel

  return {
    toolId,
    displayName,
    tabs: TABS,
    tab,
    versions,
    selected,
    defaultPick,
    specifyVersion,
    projectPath,
    projectCanPin,
    filter,
    loading,
    error,
    conflicts,
    voltaAvailable,
    listForTab,
    selectedList,
    versionSkeletonRows,
    bindVerListEl,
    logEntries,
    commandEntries,
    progress,
    statusText,
    busy,
    selectTool,
    projectPinHint,
    canRunSpecify,
    selectTab,
    requestList,
    runBatchInstall,
    pickProjectDir,
    runSpecifyPin,
    runSetDefault,
    runBatchUninstall,
    installVoltaTool,
  }
}
