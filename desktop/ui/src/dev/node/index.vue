<script setup lang="ts">
/**
 * Node.js 工作区：梯形 Tab + 左版本列表 + 右进度/日志/PowerShell。
 * 取消任务挂到父级 tool-overview「终止」。
 */
import { computed, inject, nextTick, onMounted, onUnmounted, ref, watch } from 'vue'
import JobConsole from '@kernel/components/JobConsole.vue'
import RegionLock from '@kernel/components/RegionLock.vue'
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

const props = defineProps<{
  /** 嵌在一级页 tool-workspace 时为 true。 */
  embedded?: boolean
}>()

useShellTitle(computed(() => (props.embedded ? '开发工具' : 'Node.js')))

const selectTool = inject(DEV_SELECT_TOOL_KEY, null)
const workspaceOwnsConsole = inject(DEV_WORKSPACE_OWNS_CONSOLE_KEY, null)

/** 功能 Tab。 */
type NodeTab = 'batch-install' | 'specify' | 'set-default' | 'batch-uninstall'

const tab = ref<NodeTab>('batch-install')
const versions = ref<VoltaVersion[]>([])
const selected = ref<Record<string, boolean>>({})
const defaultPick = ref<string | null>(null)
const specifyVersion = ref('')
/** 指定版本（pin）目标项目目录。 */
const projectPath = ref('')
/** 目录是否含 package.json，可执行 volta pin。 */
const projectCanPin = ref(false)
const filter = ref('')
const loading = ref(false)
const error = ref('')
const conflicts = ref<string[]>([])
const voltaAvailable = ref(true)

/** Volta 命令窗/进度会话（与显示组件分离）。 */
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

const tabs: { id: NodeTab; label: string }[] = [
  { id: 'batch-install', label: '批量安装' },
  { id: 'specify', label: '指定版本' },
  { id: 'set-default', label: '设置默认' },
  { id: 'batch-uninstall', label: '批量卸载' },
]

/** 版本列表骨架行数（按可视高度可容纳条数）。 */
const versionSkeletonRows = ref(8)
const verListEl = ref<HTMLElement | null>(null)
let verListResizeObs: ResizeObserver | undefined

/** 按版本列表高度 / 实测骨架行高，计算可完整放下的条数。 */
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

/** 去掉版本号中的点/空白，便于「265」匹配「26.5.0」。 */
function compactVersionKey(s: string) {
  return s.toLowerCase().replace(/[.\s_-]/g, '')
}

/**
 * 版本过滤：子串匹配，或忽略点号的紧凑匹配；LTS 名也可匹配。
 * @param version - 版本号
 * @param lts - LTS 代号
 * @param rawQuery - 用户输入
 */
function matchesVersionFilter(
  version: string,
  lts: string | null | undefined,
  rawQuery: string,
): boolean {
  const q = rawQuery.trim().toLowerCase()
  if (!q) return true
  const ver = version.toLowerCase()
  const ltsText = (lts ?? '').toLowerCase()
  if (ver.includes(q) || ltsText.includes(q)) return true
  const qCompact = compactVersionKey(q)
  if (!qCompact) return false
  return compactVersionKey(ver).includes(qCompact) || compactVersionKey(ltsText).includes(qCompact)
}

const listForTab = computed(() => {
  const q = filter.value
  return versions.value.filter((v) => {
    if (!matchesVersionFilter(v.version, v.lts, q)) return false
    if (tab.value === 'batch-install') return !v.installed
    if (tab.value === 'batch-uninstall') return v.installed
    // 指定版本 / 设置默认：已装 + 未装都显示
    return true
  })
})

/** 当前可操作的已勾选版本。 */
const selectedList = computed(() =>
  listForTab.value.filter((v) => selected.value[v.version]).map((v) => v.version),
)

/**
 * 拉取/刷新 Node 版本清单。
 * @param forceRemote - true 时强制与远程增量同步
 */
function requestList(forceRemote = true) {
  loading.value = true
  error.value = ''
  post({ type: 'volta.list', tool: 'node', ltsOnly: false, forceRemote })
}

function findVersionIndex(version: string): number {
  const ver = version.trim().replace(/^v/i, '')
  if (!ver) return -1
  return versions.value.findIndex(
    (x) => x.version.replace(/^v/i, '').toLowerCase() === ver.toLowerCase(),
  )
}

/** 安装成功：从「批量安装」列表移除（标为已装并取消勾选）。 */
function markNodeInstalled(version: string) {
  const idx = findVersionIndex(version)
  if (idx < 0) return
  const cur = versions.value[idx]!
  if (cur.installed) {
    selected.value[cur.version] = false
    return
  }
  versions.value.splice(idx, 1, { ...cur, installed: true })
  selected.value[cur.version] = false
}

/** 卸载成功：从「批量卸载」列表移除（标为未装并取消勾选）。 */
function markNodeUninstalled(version: string) {
  const idx = findVersionIndex(version)
  if (idx < 0) return
  const cur = versions.value[idx]!
  if (!cur.installed) {
    selected.value[cur.version] = false
    return
  }
  const wasDefault =
    !!defaultPick.value &&
    defaultPick.value.replace(/^v/i, '').toLowerCase() ===
      cur.version.replace(/^v/i, '').toLowerCase()
  const next = { ...cur, installed: false, isDefault: false }
  versions.value.splice(idx, 1, next)
  selected.value[cur.version] = false
  if (wasDefault || cur.isDefault) {
    defaultPick.value =
      versions.value.find((x) => x.isDefault)?.version ??
      versions.value.find((x) => x.installed)?.version ??
      null
  }
}

/**
 * 根据任务日志/命令输出，按条更新版本列表（装完一个消一个、卸完一个消一个）。
 */
function tryApplyVersionListFromMessage(message: string) {
  const done = /(?:^|\s)version-done\s+(install|uninstall)\s+node@(\S+)/i.exec(message)
  if (done?.[1] && done[2]) {
    if (done[1].toLowerCase() === 'uninstall') markNodeUninstalled(done[2])
    else markNodeInstalled(done[2])
    return
  }

  const installedLog = /安装成功\s+node@(\S+)/i.exec(message)
  if (installedLog?.[1]) {
    markNodeInstalled(installedLog[1])
    return
  }
  const installedConsole = /success:\s*installed.*?node@([vV]?\d[\w.-]*)/i.exec(message)
  if (installedConsole?.[1]) {
    markNodeInstalled(installedConsole[1])
    return
  }

  const removedLog = /已干净移除\s+node@(\S+)/i.exec(message)
  if (removedLog?.[1]) markNodeUninstalled(removedLog[1])
}

onMounted(() => {
  if (workspaceOwnsConsole) workspaceOwnsConsole.value = true
  bindVoltaViewAdapters()

  unsub = subscribe((msg) => {
    if (msg.type === 'volta.versions' && Array.isArray(msg.items)) {
      if (msg.tool && msg.tool !== 'node') return
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
    if (msg.type === 'silent.task') {
      const task = normalizeSilentTask(msg.task)
      if (task?.id === 'cache.versions.node' && task.status === 'succeeded') {
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
      tryApplyVersionListFromMessage(msg.message)
    }
    if (msg.type === 'job-finished') {
      commandLog.remove(VOLTA_FETCH_LINE_ID)
      requestList(false)
    }
    if (!isShared) consumeJobMessage(msg)
  })
  // 默认读本地缓存；远端增量由进主壳后的静默任务负责
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

function selectNodeTab(id: NodeTab) {
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
    toolId: 'node',
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
    message: `确认卸载已选 Node.js 版本？\n${preview}`,
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
</script>

<template>
  <section class="node-page" :class="{ embedded: props.embedded }">
    <p v-if="!voltaAvailable" class="prereq-banner">
      未安装 Volta。请先安装后再管理 Node 版本。
      <span class="prereq-actions">
        <button type="button" class="btn" :disabled="busy" @click="installVoltaTool">
          {{ selectTool ? '前往 Volta' : '安装 Volta' }}
        </button>
      </span>
    </p>
    <p v-else-if="conflicts.length" class="banner-warn">
      检测到可能冲突的版本管理器：{{ conflicts.join('、') }}。建议统一使用 Volta。
    </p>
    <p v-if="error" class="banner-err">{{ error }}</p>

    <template v-if="voltaAvailable">
      <RegionLock :active="busy" title="任务进行中，请先终止">
        <div class="folder-tabs" role="tablist" aria-label="Node 功能">
          <button
            v-for="(t, i) in tabs"
            :key="t.id"
            type="button"
            role="tab"
            class="folder-tab"
            :class="{ active: tab === t.id }"
            :style="{ zIndex: tab === t.id ? tabs.length + 1 : tabs.length - i }"
            :aria-selected="tab === t.id"
            :tabindex="busy ? -1 : undefined"
            @click="selectNodeTab(t.id)"
          >
            <span class="folder-tab-label">{{ t.label }}</span>
          </button>
        </div>
      </RegionLock>

      <div class="folder-body">
        <div class="node-split" :class="{ 'is-job-locked': busy }">
          <div
            v-if="busy"
            class="node-ops-lock"
            title="任务进行中，请先终止"
            aria-hidden="true"
          />
          <!-- 批量安装 -->
          <template v-if="tab === 'batch-install'">
            <div class="ver-head">
              <input
                v-model="filter"
                class="search"
                type="search"
                placeholder="过滤版本…"
                :aria-label="`过滤版本，共 ${listForTab.length} 项`"
              />
              <button
                type="button"
                class="btn btn-install"
                :disabled="busy || loading || !selectedList.length"
                :title="!selectedList.length ? '请先勾选要安装的版本' : '安装所选版本'"
                @click="runBatchInstall"
              >
                安装
              </button>
            </div>
            <ul
              ref="verListEl"
              class="ver-list ver-list--install"
              :class="{ 'ver-list--loading': loading && !versions.length }"
              :aria-busy="loading"
              aria-label="Node 版本列表"
            >
              <template v-if="loading && !versions.length">
                <li
                  v-for="n in versionSkeletonRows"
                  :key="'vsk-' + n"
                  class="ver-row is-skel"
                  aria-hidden="true"
                >
                  <div class="ver-row-label">
                    <span class="ver-lead">
                      <span class="ver-skel-swatch ver-skel-swatch--check" />
                    </span>
                    <span class="ver-skel-swatch ver-skel-swatch--ver" />
                    <span class="ver-skel-swatch ver-skel-swatch--tag" />
                  </div>
                </li>
              </template>
              <template v-else>
                <li
                  v-for="v in listForTab"
                  :key="v.version"
                  class="ver-row"
                  :class="{ 'is-checked': selected[v.version] }"
                >
                  <label class="ver-row-label">
                    <span class="ver-lead">
                      <input
                        v-model="selected[v.version]"
                        class="ver-check"
                        type="checkbox"
                        :disabled="busy"
                      />
                    </span>
                    <span class="ver-num">{{ v.version }}</span>
                    <span v-if="v.lts" class="tag">LTS · {{ v.lts }}</span>
                  </label>
                </li>
                <li v-if="!listForTab.length && !loading" class="empty-hint">无匹配版本</li>
              </template>
            </ul>
          </template>

          <!-- 指定版本：目录 + pin；单选；已装/未装都显示；默认用框样式 -->
          <template v-else-if="tab === 'specify'">
            <div class="ver-aside">
              <div class="ver-project">
                <div class="ver-project-main">
                  <span class="ver-project-label">当前目录</span>
                  <span
                    class="ver-project-path"
                    :class="{ empty: !projectPath }"
                    :title="projectPath || undefined"
                  >
                    {{ projectPath || '未选择' }}
                  </span>
                </div>
                <button
                  type="button"
                  class="btn btn-install"
                  :disabled="busy"
                  title="选择含 package.json 的项目目录"
                  @click="pickProjectDir"
                >
                  选择
                </button>
              </div>
              <p
                class="ver-project-hint"
                :class="{
                  ok: projectCanPin,
                  bad: !!projectPath && !projectCanPin,
                }"
              >
                {{ projectPinHint }}
              </p>
              <div class="ver-head">
                <input
                  v-model="filter"
                  class="search"
                  type="search"
                  placeholder="过滤版本…"
                  :aria-label="`过滤版本，共 ${listForTab.length} 项`"
                />
                <button
                  type="button"
                  class="btn btn-install"
                  :disabled="!canRunSpecify"
                  :title="
                    !projectCanPin
                      ? '请先选择有效项目目录'
                      : !specifyVersion
                        ? '请先选择版本'
                        : 'Pin 所选版本到项目'
                  "
                  @click="runSpecifyPin"
                >
                  指定
                </button>
              </div>
              <ul
                class="ver-list ver-list--install"
                :class="{ 'ver-list--loading': loading && !versions.length }"
                :aria-busy="loading"
                aria-label="Node 版本列表"
              >
                <li
                  v-for="v in listForTab"
                  :key="v.version"
                  class="ver-row"
                  :class="{
                    'is-checked': specifyVersion === v.version,
                    'is-default': v.isDefault,
                    'is-installed': v.installed && !v.isDefault,
                  }"
                >
                  <label class="ver-row-label">
                    <span class="ver-lead">
                      <input
                        v-model="specifyVersion"
                        class="ver-radio"
                        type="radio"
                        name="node-specify"
                        :value="v.version"
                        :disabled="busy || !projectCanPin"
                      />
                    </span>
                    <span class="ver-num">{{ v.version }}</span>
                    <span v-if="v.lts" class="tag">LTS · {{ v.lts }}</span>
                  </label>
                </li>
                <li v-if="!listForTab.length && !loading" class="empty-hint">无匹配版本</li>
              </ul>
            </div>
          </template>

          <!-- 设置默认：布局同批量安装；单选；已装/未装都显示；默认用框样式 -->
          <template v-else-if="tab === 'set-default'">
            <div class="ver-head">
              <input
                v-model="filter"
                class="search"
                type="search"
                placeholder="过滤版本…"
                :aria-label="`过滤版本，共 ${listForTab.length} 项`"
              />
              <button
                type="button"
                class="btn btn-install"
                :disabled="busy || loading || !defaultPick"
                :title="!defaultPick ? '请先选择版本' : '设为默认'"
                @click="runSetDefault"
              >
                设置
              </button>
            </div>
            <ul
              class="ver-list ver-list--install"
              :class="{ 'ver-list--loading': loading && !versions.length }"
              :aria-busy="loading"
              aria-label="Node 版本列表"
            >
              <li
                v-for="v in listForTab"
                :key="v.version"
                class="ver-row"
                :class="{
                  'is-checked': defaultPick === v.version,
                  'is-default': v.isDefault,
                  'is-installed': v.installed && !v.isDefault,
                }"
              >
                <label class="ver-row-label">
                  <span class="ver-lead">
                    <input
                      v-model="defaultPick"
                      class="ver-radio"
                      type="radio"
                      name="node-default"
                      :value="v.version"
                      :disabled="busy"
                    />
                  </span>
                  <span class="ver-num">{{ v.version }}</span>
                  <span v-if="v.lts" class="tag">LTS · {{ v.lts }}</span>
                </label>
              </li>
              <li v-if="!listForTab.length && !loading" class="empty-hint">无匹配版本</li>
            </ul>
          </template>

          <!-- 批量卸载 -->
          <template v-else-if="tab === 'batch-uninstall'">
            <div class="ver-head">
              <input
                v-model="filter"
                class="search"
                type="search"
                placeholder="过滤版本…"
                :aria-label="`过滤版本，共 ${listForTab.length} 项`"
              />
              <button
                type="button"
                class="btn btn-install"
                :disabled="busy || loading || !selectedList.length"
                :title="!selectedList.length ? '请先勾选要卸载的版本' : '卸载所选版本'"
                @click="runBatchUninstall"
              >
                卸载
              </button>
            </div>
            <ul
              class="ver-list ver-list--install"
              :class="{ 'ver-list--loading': loading && !versions.length }"
              :aria-busy="loading"
              aria-label="已安装 Node 版本"
            >
              <li
                v-for="v in listForTab"
                :key="v.version"
                class="ver-row"
                :class="{
                  'is-checked': selected[v.version],
                  'is-default': v.isDefault,
                }"
              >
                <label class="ver-row-label">
                  <span class="ver-lead">
                    <input
                      v-model="selected[v.version]"
                      class="ver-check"
                      type="checkbox"
                      :disabled="busy"
                    />
                  </span>
                  <span class="ver-num">{{ v.version }}</span>
                  <span v-if="v.lts" class="tag">LTS · {{ v.lts }}</span>
                </label>
              </li>
              <li v-if="!listForTab.length && !loading" class="empty-hint">暂无已安装版本</li>
            </ul>
          </template>

          <JobConsole
            class="node-job"
            always-show
            :progress="progress"
            :status-text="statusText"
            :log-entries="logEntries"
            :command-entries="commandEntries"
            :busy="busy"
            logs-placeholder="执行操作后在此显示 日志 输出…"
            placeholder="执行操作后在此显示 PowerShell 输出…"
          />
        </div>
      </div>
    </template>
  </section>
</template>

<style scoped>
.node-page {
  display: flex;
  flex-direction: column;
  min-height: 0;
  flex: 1;
  height: 100%;
  overflow: hidden;
}
.prereq-banner {
  margin: 0 0 0.75rem;
  padding: 0.75rem 0.9rem;
  border: 1px solid color-mix(in srgb, var(--warn) 45%, var(--line));
  border-radius: 0.65rem;
  background: color-mix(in srgb, var(--warn) 12%, var(--panel));
  font-size: 0.9rem;
  flex: 0 0 auto;
}
.prereq-actions {
  display: flex;
  gap: 0.5rem;
  margin-top: 0.55rem;
}
.banner-err {
  color: var(--danger);
  margin: 0 0 0.65rem;
  flex: 0 0 auto;
}
.banner-warn {
  color: var(--warn);
  margin: 0 0 0.5rem;
  font-size: 0.88rem;
  flex: 0 0 auto;
}

/* —— 文件夹式梯形 Tab：以下底边贴齐（上沿斜切开缝） —— */
.folder-tabs {
  display: flex;
  align-items: flex-end;
  gap: 0;
  padding: 0;
  margin: 0;
  flex: 0 0 auto;
  border-bottom: 1px solid color-mix(in srgb, var(--line) 85%, transparent);
}
.folder-tab {
  --tab-slant: 0.7rem;
  position: relative;
  margin: 0 0 -1px;
  padding: 0;
  border: none;
  background: transparent;
  cursor: pointer;
  color: var(--muted);
  font-weight: 650;
  font-size: 0.82rem;
  letter-spacing: 0.03em;
}
.folder-tab + .folder-tab {
  /* 只消双边框，不按顶边回拉——以下底边紧挨 */
  margin-left: -1px;
}
.folder-tab-label {
  display: block;
  padding: 0.48rem 1rem 0.42rem 0.85rem;
  background: color-mix(in srgb, var(--panel) 55%, transparent);
  border: 1px solid color-mix(in srgb, var(--line) 90%, transparent);
  border-bottom: none;
  /* 上窄下宽：底边 100% 相邻贴齐；顶边右收形成斜腰 */
  clip-path: polygon(0 0, calc(100% - var(--tab-slant)) 0, 100% 100%, 0 100%);
  border-radius: 0.45rem 0.15rem 0 0;
  transition:
    color 0.15s ease,
    background 0.15s ease,
    box-shadow 0.15s ease;
}
.folder-tab:hover .folder-tab-label {
  color: var(--ink);
  background: color-mix(in srgb, var(--panel) 72%, transparent);
}
.folder-tab.active {
  color: var(--ink);
}
.folder-tab.active .folder-tab-label {
  background: color-mix(in srgb, var(--panel) 88%, transparent);
  border-color: color-mix(in srgb, var(--accent) 40%, var(--line));
  box-shadow: inset 0 2px 0 var(--accent);
  color: var(--ink);
}

.folder-body {
  flex: 1;
  min-height: 0;
  display: flex;
  flex-direction: column;
  border: 1px solid color-mix(in srgb, var(--line) 85%, transparent);
  border-top: none;
  border-radius: 0 0 0.65rem 0.65rem;
  background: color-mix(in srgb, var(--panel) 28%, transparent);
  padding: 0.75rem;
  overflow: hidden;
}

/**
 * 左顶栏 | 右进度
 * 左列表 | 右日志+命令（平分进度条下方）
 * 列表顶与日志顶齐平。
 */
.node-split {
  /* 左列：checkbox + 版本号 + LTS 紧凑宽 */
  --node-list-w: 13.75rem;
  /* 与右侧进度区（任务文案 + 条）对齐；搜索与操作按钮同高 */
  --node-head-h: 1.85rem;
  --ver-check-size: 1rem;
  flex: 1;
  min-height: 0;
  display: grid;
  grid-template-columns: var(--node-list-w) minmax(0, 1fr);
  grid-template-rows: auto minmax(0, 1fr);
  grid-template-areas:
    'head prog'
    'list panes';
  gap: 0.65rem 0.75rem;
  align-items: stretch;
  overflow: hidden;
  position: relative;
}

/** 任务中：只锁左侧操作区，右侧进度/命令/日志可点 */
.node-ops-lock {
  position: absolute;
  z-index: 25;
  left: 0;
  top: 0;
  bottom: 0;
  width: var(--node-list-w);
  cursor: not-allowed;
  border-radius: 0.4rem;
  background: color-mix(in srgb, var(--panel) 22%, transparent);
}

.ver-head {
  grid-area: head;
  display: flex;
  flex-wrap: nowrap;
  gap: 0.4rem;
  align-items: stretch;
  min-width: 0;
  height: var(--node-head-h);
  align-self: start;
}

/* 指定版本：左栏合并 head+list，顶部为项目目录 */
.ver-aside {
  grid-column: 1;
  grid-row: 1 / span 2;
  display: flex;
  flex-direction: column;
  gap: 0.4rem;
  min-width: 0;
  min-height: 0;
  align-self: stretch;
}

.ver-aside .ver-head {
  grid-area: unset;
  flex: 0 0 auto;
  height: var(--node-head-h);
}

.ver-aside .ver-list {
  grid-area: unset;
  flex: 1 1 auto;
  min-height: 0;
}

.ver-project {
  display: flex;
  flex-wrap: nowrap;
  gap: 0.4rem;
  align-items: stretch;
  min-width: 0;
  height: var(--node-head-h);
  flex: 0 0 auto;
}

.ver-project-main {
  flex: 1;
  min-width: 0;
  display: flex;
  align-items: center;
  gap: 0.35rem;
  padding: 0 0.45rem;
  border: 1px solid var(--line);
  border-radius: 0.4rem;
  background: var(--panel-strong);
}

.ver-project-label {
  flex: 0 0 auto;
  font-size: 0.72rem;
  color: var(--muted);
  white-space: nowrap;
}

.ver-project-path {
  flex: 1;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-family: var(--font-mono);
  font-size: 0.72rem;
  color: var(--ink);
}

.ver-project-path.empty {
  color: var(--muted);
}

.ver-project > .btn {
  box-sizing: border-box;
  height: 100%;
  min-height: 0;
  margin: 0;
  padding-top: 0;
  padding-bottom: 0;
  line-height: 1;
  display: inline-flex;
  align-items: center;
  align-self: stretch;
}

.ver-project-hint {
  margin: 0;
  padding: 0 0.1rem;
  font-size: 0.68rem;
  line-height: 1.3;
  color: var(--muted);
  flex: 0 0 auto;
}

.ver-project-hint.ok {
  color: color-mix(in srgb, var(--ok) 85%, var(--ink));
}

.ver-project-hint.bad {
  color: color-mix(in srgb, var(--danger, #e85d5d) 90%, var(--ink));
}

.ver-head--wrap {
  flex-wrap: wrap;
  height: auto;
  align-items: center;
}

.ver-head .search,
.ver-head > .btn {
  box-sizing: border-box;
  height: 100%;
  min-height: 0;
  margin: 0;
  padding-top: 0;
  padding-bottom: 0;
  line-height: 1;
  display: inline-flex;
  align-items: center;
  align-self: stretch;
}

.ver-head .search {
  flex: 1;
  min-width: 0;
  padding-left: 0.55rem;
  padding-right: 0.55rem;
  border: 1px solid var(--line);
  border-radius: 0.4rem;
  background: var(--panel-strong);
  color: var(--ink);
  font-family: var(--font-mono);
  font-size: 0.82rem;
}

.ver-head > .btn {
  flex: 0 0 auto;
  padding-left: 0.85rem;
  padding-right: 0.85rem;
  font-size: 0.82rem;
}

/* 批量安装 / 卸载：主按钮与搜索同高，避免 hover 撑破对齐行 */
.ver-head > .btn.btn-install {
  padding: 0 0.7rem;
  font-size: 0.74rem;
  font-weight: 650;
  letter-spacing: 0.06em;
  box-shadow: 0 0 8px color-mix(in srgb, var(--glow) 35%, transparent);
  transform: none;
}
.ver-head > .btn.btn-install:hover:not(:disabled) {
  transform: none;
  filter: brightness(1.06);
}

.node-split :deep(.node-job.job-console),
.node-split :deep(.job-console) {
  display: contents;
}

.node-split :deep(.progress-wrap) {
  grid-area: prog;
  box-sizing: border-box;
  height: var(--node-head-h);
  min-height: var(--node-head-h);
  max-height: var(--node-head-h);
  align-self: start;
  display: flex;
  flex-direction: column;
  justify-content: center;
  gap: 0.14rem;
  padding: 0.18rem 0.55rem;
  border-radius: 0.4rem;
}

.node-split :deep(.progress-label) {
  margin-bottom: 0;
  min-height: 0;
}

.node-split :deep(.progress-status) {
  font-size: 0.65rem;
  line-height: 1.1;
  letter-spacing: 0.04em;
}

.node-split :deep(.progress-track-row) {
  gap: 0.4rem;
}

.node-split :deep(.progress-bar) {
  height: 0.28rem;
}

.node-split :deep(.progress-pct) {
  font-size: 0.62rem;
}

.node-split :deep(.job-panes) {
  grid-area: panes;
  min-height: 0;
  height: 100%;
}

.search {
  flex: 1;
  min-width: 0;
  padding: 0.35rem 0.55rem;
  border: 1px solid var(--line);
  border-radius: 0.4rem;
  background: var(--panel-strong);
  color: var(--ink);
  font-family: var(--font-mono);
  font-size: 0.82rem;
}
.search--full {
  flex: 1 1 100%;
  height: auto;
  min-height: 2.55rem;
}

.ver-list {
  /* 仅供骨架条数估算；真实行高由内容自然撑开 */
  --ver-row-h: 2.35rem;
  grid-area: list;
  list-style: none;
  margin: 0;
  padding: 0.28rem;
  overflow: auto;
  min-height: 0;
  border: 1px solid color-mix(in srgb, var(--line) 80%, transparent);
  border-radius: 0.5rem;
  background: color-mix(in srgb, var(--panel) 40%, transparent);
}

.ver-list li.ver-row {
  border: 1px solid transparent;
  border-radius: 0.4rem;
  padding: 0;
  margin: 0 0 0.22rem;
  background: transparent;
  transition:
    border-color 0.15s ease,
    background 0.15s ease,
    box-shadow 0.15s ease;
}

.ver-list li.ver-row:last-child {
  margin-bottom: 0;
}

/* 骨架：复用 ver-row / ver-row-label 结构，高度与真实行一致 */
.ver-list li.ver-row.is-skel {
  pointer-events: none;
  cursor: default;
  opacity: 0.92;
  border-color: color-mix(in srgb, var(--line) 70%, transparent);
  background: color-mix(in srgb, var(--panel) 32%, transparent);
}

.ver-skel-swatch {
  display: block;
  flex: 0 0 auto;
  border-radius: 0.28rem;
  background: linear-gradient(
    110deg,
    color-mix(in srgb, var(--panel) 58%, var(--line)) 22%,
    color-mix(in srgb, var(--accent) 24%, var(--panel)) 48%,
    color-mix(in srgb, var(--panel) 58%, var(--line)) 74%
  );
  background-size: 200% 100%;
  animation: ver-skel-shimmer 1.35s ease-in-out infinite;
}

.ver-skel-swatch--check {
  width: var(--ver-check-size, 1rem);
  height: var(--ver-check-size, 1rem);
}

.ver-skel-swatch--ver {
  width: 4.8rem;
  height: 0.85rem;
  border-radius: 999px;
}

.ver-skel-swatch--tag {
  width: 5.6rem;
  height: 0.85rem;
  animation-delay: 0.1s;
}

@keyframes ver-skel-shimmer {
  0% {
    background-position: 120% 0;
  }
  100% {
    background-position: -120% 0;
  }
}

@media (prefers-reduced-motion: reduce) {
  .ver-skel-swatch {
    animation: none;
  }
}

/* 未框住：悬停轻提示 */
.ver-list--install li.ver-row:not(.is-installed):not(.is-checked):not(.is-default):hover {
  border-color: color-mix(in srgb, var(--accent) 40%, var(--line));
  background: color-mix(in srgb, var(--accent) 8%, transparent);
}

/* 勾选 / 单选选中：accent-2 框 */
.ver-list--install li.ver-row.is-checked {
  border-color: color-mix(in srgb, var(--accent-2) 55%, var(--line));
  background: color-mix(in srgb, var(--accent-2) 16%, var(--panel));
  box-shadow:
    inset 0 0 0 1px color-mix(in srgb, var(--accent-2) 22%, transparent),
    0 0 12px color-mix(in srgb, var(--accent-2) 14%, transparent);
}

/* 已安装（非默认）：绿色框，无文字标签 */
.ver-list--install li.ver-row.is-installed {
  border-color: color-mix(in srgb, var(--ok) 55%, var(--line));
  background: color-mix(in srgb, var(--ok) 14%, var(--panel));
  box-shadow:
    inset 0 0 0 1px color-mix(in srgb, var(--ok) 22%, transparent),
    0 0 12px color-mix(in srgb, var(--ok) 12%, transparent);
}

/* 默认版本：琥珀色框（不用「默认」标签） */
.ver-list--install li.ver-row.is-default {
  border-color: color-mix(in srgb, #d4a017 62%, var(--line));
  background: color-mix(in srgb, #e8b84a 16%, var(--panel));
  box-shadow:
    inset 0 0 0 1px color-mix(in srgb, #e8b84a 28%, transparent),
    0 0 12px color-mix(in srgb, #d4a017 16%, transparent);
}

.ver-list--install li.ver-row.is-default.is-checked {
  border-color: color-mix(in srgb, #d4a017 70%, var(--accent-2));
  box-shadow:
    inset 0 0 0 1px color-mix(in srgb, #e8b84a 30%, transparent),
    0 0 12px color-mix(in srgb, var(--accent-2) 14%, transparent);
}

.ver-row-label {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.35rem 0.45rem;
  width: 100%;
  cursor: pointer;
  text-align: left;
  border: none;
  background: transparent;
  color: inherit;
  padding: 0.38rem 0.45rem;
  font: inherit;
  box-sizing: border-box;
}

/* 批量安装：版本 + LTS 同排；默认标识占复选框槽位 */
.ver-list--install .ver-row-label {
  flex-wrap: nowrap;
}

.ver-list--install .ver-num {
  flex: 0 0 auto;
}

.ver-list--install .tag {
  flex: 0 0 auto;
  white-space: nowrap;
}

.ver-lead {
  flex: 0 0 var(--ver-check-size);
  width: var(--ver-check-size);
  height: var(--ver-check-size);
  display: inline-flex;
  align-items: center;
  justify-content: center;
  position: relative;
}

.ver-row-label.is-disabled {
  cursor: default;
  opacity: 0.92;
}

.ver-check,
.ver-radio {
  appearance: none;
  -webkit-appearance: none;
  flex: 0 0 auto;
  box-sizing: border-box;
  width: var(--ver-check-size, 1rem);
  height: var(--ver-check-size, 1rem);
  margin: 0;
  border: 1.5px solid color-mix(in srgb, var(--line) 90%, var(--accent));
  border-radius: 0.28rem;
  background: color-mix(in srgb, var(--panel-strong) 88%, transparent);
  cursor: pointer;
  position: relative;
  transition:
    border-color 0.15s ease,
    background 0.15s ease,
    box-shadow 0.15s ease;
}

.ver-radio {
  border-radius: 50%;
}

.ver-check:hover:not(:disabled),
.ver-radio:hover:not(:disabled) {
  border-color: color-mix(in srgb, var(--accent) 65%, var(--line));
  box-shadow: 0 0 0 2px color-mix(in srgb, var(--accent) 16%, transparent);
}

.ver-check:checked,
.ver-radio:checked {
  border-color: color-mix(in srgb, var(--accent-2) 70%, transparent);
  background: linear-gradient(
    135deg,
    var(--accent-2),
    color-mix(in srgb, var(--accent) 45%, var(--accent-2))
  );
  box-shadow: 0 0 10px color-mix(in srgb, var(--accent-2) 28%, transparent);
}

.ver-check:checked::after {
  content: '';
  position: absolute;
  left: 0.28rem;
  top: 0.08rem;
  width: 0.28rem;
  height: 0.5rem;
  border: solid var(--accent-ink, #041018);
  border-width: 0 1.5px 1.5px 0;
  transform: rotate(45deg);
}

.ver-radio:checked::after {
  content: '';
  position: absolute;
  left: 50%;
  top: 50%;
  width: 0.38rem;
  height: 0.38rem;
  border-radius: 50%;
  background: var(--accent-ink, #041018);
  transform: translate(-50%, -50%);
  border: none;
}

/* 任务进行中：未勾选弱化；已勾选保留勾选貌，只降对比（勿看起来像没选） */
.ver-check:disabled,
.ver-radio:disabled {
  cursor: not-allowed;
}

.ver-check:disabled:not(:checked),
.ver-radio:disabled:not(:checked) {
  opacity: 0.48;
  border-color: color-mix(in srgb, var(--line) 75%, transparent);
  background: color-mix(in srgb, var(--muted) 12%, var(--panel));
  box-shadow: none;
}

.ver-check:disabled:checked,
.ver-radio:disabled:checked {
  opacity: 0.72;
  border-color: color-mix(in srgb, var(--accent-2) 55%, var(--line));
  background: linear-gradient(
    135deg,
    color-mix(in srgb, var(--accent-2) 72%, var(--panel)),
    color-mix(in srgb, var(--accent) 40%, var(--accent-2))
  );
  box-shadow: 0 0 7px color-mix(in srgb, var(--accent-2) 18%, transparent);
}

.ver-check:disabled:checked::after,
.ver-radio:disabled:checked::after {
  opacity: 0.9;
  border-color: color-mix(in srgb, var(--accent-ink, #041018) 82%, transparent);
}

/* 任务锁定期：勾选行整体弱化，仍保持「已选」框色 */
.node-split.is-job-locked .ver-list--install li.ver-row.is-checked {
  opacity: 0.78;
  border-color: color-mix(in srgb, var(--accent-2) 38%, var(--line));
  background: color-mix(in srgb, var(--accent-2) 11%, var(--panel));
  box-shadow:
    inset 0 0 0 1px color-mix(in srgb, var(--accent-2) 14%, transparent),
    0 0 8px color-mix(in srgb, var(--accent-2) 8%, transparent);
}

.node-split.is-job-locked .ver-list--install li.ver-row.is-default:not(.is-checked) {
  opacity: 0.82;
}

.node-split.is-job-locked .ver-list--install li.ver-row:not(.is-checked):not(.is-default) {
  opacity: 0.55;
}

.ver-check:focus-visible,
.ver-radio:focus-visible {
  outline: none;
  box-shadow: 0 0 0 2px color-mix(in srgb, var(--accent) 35%, transparent);
}

.ver-num {
  font-family: var(--font-mono);
  font-weight: 650;
  min-width: 3.6rem;
}

.tag {
  font-size: 0.68rem;
  padding: 0.08rem 0.35rem;
  border-radius: 0.28rem;
  border: 1px solid color-mix(in srgb, var(--line) 80%, transparent);
  color: var(--muted);
}

.empty-hint {
  padding: 0.85rem !important;
  color: var(--muted);
  font-size: 0.85rem;
  border: none !important;
  background: transparent !important;
  box-shadow: none !important;
}
.ver-field {
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
  font-size: 0.8rem;
  color: var(--muted);
  flex: 1;
  min-width: 8rem;
}
.ver-input {
  padding: 0.4rem 0.55rem;
  border: 1px solid var(--line);
  border-radius: 0.4rem;
  background: var(--panel-strong);
  color: var(--ink);
  font-family: var(--font-mono);
}

@media (max-width: 900px) {
  .node-split {
    grid-template-columns: 1fr;
    grid-template-rows: auto auto minmax(10rem, 1fr) minmax(12rem, 1.1fr);
    grid-template-areas:
      'head'
      'prog'
      'list'
      'panes';
  }

  .node-split {
    --node-list-w: 100%;
  }

  .ver-aside {
    grid-column: 1;
    grid-row: 1 / span 3;
  }
}
</style>
