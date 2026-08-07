<script setup lang="ts">
/**
 * Claude Code 工作区：
 * - 未安装 / 安装·更新·卸载进行中：内容区整页为进度+输出
 * - 已安装·初始化：第一行执行/重置，下方整宽进度+输出
 * - 已安装·其他 Tab：左操作 / 右共用进度+输出；空闲切 Tab 清空输出
 * 取消任务挂父级「终止」；状态读库，不提供刷新状态按钮。
 */
import { computed, inject, onMounted, onUnmounted, ref, watch } from 'vue'
import JobConsole from '@kernel/components/JobConsole.vue'
import RegionLock from '@kernel/components/RegionLock.vue'
import { post, subscribe } from '@kernel/bridge/bus'
import { confirmDialog } from '@kernel/bridge/confirm'
import { showToast } from '@kernel/bridge/toast'
import { useShellTitle } from '@kernel/composables/useShellTitle'
import { DEV_WORKSPACE_OWNS_CONSOLE_KEY } from '../devPanelContext'
import { useDevPanelJob } from '../useDevPanelJob'
import '../voltaShared/voltaPackageWorkspace.css'

const props = defineProps<{
  /** 嵌在一级页 tool-workspace 时为 true。 */
  embedded?: boolean
}>()

useShellTitle(computed(() => (props.embedded ? '开发工具' : 'Claude Code')))

type ClaudeTab = 'init' | 'api' | 'proxy' | 'plugin-install' | 'plugin-update' | 'plugin-uninstall'
type LifecycleKind = 'install' | 'update' | 'uninstall'
type PluginAction = 'plugin-install' | 'plugin-update' | 'plugin-uninstall'

type Status = {
  installed: boolean
  version?: string | null
  wingetManaged: boolean
  settingsExists: boolean
  apiMode?: string | null
  proxyMode?: string | null
  hasSecrets: boolean
}

type Secrets = {
  apiMode?: string | null
  apiKeyMasked?: string | null
  baseUrl?: string | null
  authTokenMasked?: string | null
  proxyMode?: string | null
  httpProxy?: string | null
  httpsProxy?: string | null
}

type Plugin = {
  id: string
  label: string
  featured: boolean
  description?: string | null
  installedVersion?: string | null
  remoteVersion?: string | null
  updateAvailable?: boolean
}

const workspaceOwnsConsole = inject(DEV_WORKSPACE_OWNS_CONSOLE_KEY, null)

const tab = ref<ClaudeTab>('init')
const status = ref<Status | null>(null)
const secrets = ref<Secrets | null>(null)
const pluginsInstall = ref<Plugin[]>([])
const pluginsUpdate = ref<Plugin[]>([])
const pluginsUninstall = ref<Plugin[]>([])
const selected = ref<Record<string, boolean>>({})
/** 插件列表过滤（安装 / 更新 / 卸载共用）。 */
const filter = ref('')
/** 已收到至少一次 claude.status，避免未装态闪 Tab。 */
const statusReady = ref(false)
/** 安装 / 更新 / 卸载；失败后保持直至成功或（已安装时）返回。 */
const lifecycleKind = ref<LifecycleKind | null>(null)
const tabBeforeLifecycle = ref<ClaudeTab>('init')

const apiMode = ref<'official' | 'custom' | 'clear'>('official')
const apiKey = ref('')
const baseUrl = ref('')
const authToken = ref('')
const httpProxy = ref('')
const httpsProxy = ref('')

const tabs: { id: ClaudeTab; label: string }[] = [
  { id: 'init', label: '初始化' },
  { id: 'api', label: 'API' },
  { id: 'proxy', label: '代理' },
  { id: 'plugin-install', label: '插件安装' },
  { id: 'plugin-update', label: '插件更新' },
  { id: 'plugin-uninstall', label: '插件卸载' },
]

const {
  outputEntries,
  progress,
  statusText,
  busy,
  beginJob,
  consumeJobMessage,
  resetWhenIdle,
  isShared,
} = useDevPanelJob({
  onFinished: () => post({ type: 'claude.status' }),
  formatStarted: (msg) => `开始：${msg.action ?? '任务'}`,
  formatFinished: (msg) => (msg.ok ? '完成' : `失败 ${msg.detail ?? ''}`),
})

const isInstalled = computed(() => Boolean(status.value?.installed))

const showLifecycleView = computed(
  () =>
    !statusReady.value ||
    !isInstalled.value ||
    lifecycleKind.value != null,
)

const activePlugins = computed(() => {
  if (tab.value === 'plugin-update') return pluginsUpdate.value
  if (tab.value === 'plugin-uninstall') return pluginsUninstall.value
  return pluginsInstall.value
})

const filteredPlugins = computed(() => {
  const q = filter.value.trim().toLowerCase()
  if (!q) return activePlugins.value
  return activePlugins.value.filter((p) => {
    const hay = `${p.id} ${p.label} ${p.description ?? ''} ${p.installedVersion ?? ''} ${p.remoteVersion ?? ''}`
    return hay.toLowerCase().includes(q)
  })
})

const featuredPlugins = computed(() =>
  tab.value === 'plugin-install' ? filteredPlugins.value.filter((p) => p.featured) : [],
)
const otherPlugins = computed(() =>
  tab.value === 'plugin-install' ? filteredPlugins.value.filter((p) => !p.featured) : filteredPlugins.value,
)

const selectedList = computed(() =>
  filteredPlugins.value.filter((p) => selected.value[p.id]).map((p) => p.id),
)

const pluginEmptyHint = computed(() => {
  if (filter.value.trim() && activePlugins.value.length && !filteredPlugins.value.length) {
    return '无匹配的插件'
  }
  if (tab.value === 'plugin-update') return '暂无需要更新的已装插件'
  if (tab.value === 'plugin-uninstall') return '暂无已安装插件'
  return '暂无可安装插件（请先初始化 marketplace，或等待后台同步）'
})

const pluginActionLabel = computed(() => {
  if (tab.value === 'plugin-update') return '更新'
  if (tab.value === 'plugin-uninstall') return '卸载'
  return '安装'
})

const pluginAction = computed<PluginAction>(() => {
  if (tab.value === 'plugin-update') return 'plugin-update'
  if (tab.value === 'plugin-uninstall') return 'plugin-uninstall'
  return 'plugin-install'
})

function pluginRowLabel(p: Plugin) {
  if (tab.value === 'plugin-update') {
    const from = p.installedVersion || '?'
    const to = p.remoteVersion || '?'
    return `${p.label}（${from} → ${to}）`
  }
  if (tab.value === 'plugin-uninstall' && p.installedVersion) {
    return `${p.label}（${p.installedVersion}）`
  }
  return p.id
}

function enterLifecycle(kind: LifecycleKind) {
  if (!lifecycleKind.value) tabBeforeLifecycle.value = tab.value
  lifecycleKind.value = kind
}

function applyLifecycleFinished(ok: boolean) {
  const kind = lifecycleKind.value
  if (!kind) return
  if (!ok) return
  if (kind === 'update') {
    tab.value = tabBeforeLifecycle.value
    lifecycleKind.value = null
    // 回到功能区：清掉装/更输出，显示默认空控制台
    resetWhenIdle()
  }
  // install / uninstall：等 claude.status 再收口，避免 catalog 与 status 短暂不一致闪屏
}

function settleLifecycleFromStatus() {
  if (busy.value || !lifecycleKind.value) return
  const kind = lifecycleKind.value
  if (kind === 'install' && isInstalled.value) {
    tab.value = 'init'
    lifecycleKind.value = null
    resetWhenIdle()
  } else if (kind === 'uninstall' && !isInstalled.value) {
    lifecycleKind.value = null
    resetWhenIdle()
  }
}

let unsub: (() => void) | undefined

onMounted(() => {
  if (workspaceOwnsConsole) workspaceOwnsConsole.value = true
  unsub = subscribe((msg) => {
    if (msg.type === 'claude.status') {
      status.value = msg.status as Status
      secrets.value = msg.secrets as Secrets
      pluginsInstall.value =
        (msg.pluginsInstall as Plugin[]) ?? (msg.plugins as Plugin[]) ?? []
      pluginsUpdate.value = (msg.pluginsUpdate as Plugin[]) ?? []
      pluginsUninstall.value = (msg.pluginsUninstall as Plugin[]) ?? []
      statusReady.value = true
      for (const p of [...pluginsInstall.value, ...pluginsUpdate.value, ...pluginsUninstall.value]) {
        if (selected.value[p.id] === undefined) selected.value[p.id] = false
      }
      if (secrets.value?.httpProxy) httpProxy.value = secrets.value.httpProxy
      if (secrets.value?.httpsProxy) httpsProxy.value = secrets.value.httpsProxy
      if (secrets.value?.baseUrl) baseUrl.value = secrets.value.baseUrl
      settleLifecycleFromStatus()
      return
    }
    if (msg.type === 'claude.saved') {
      showToast(`已保存（${msg.kind}）`, { kind: 'ok' })
      return
    }
    // 后台插件目录同步完成后拉取三态列表（Host 也会推送，此处兜底）
    if (msg.type === 'silent.task') {
      const task = msg.task as { id?: string; status?: string } | undefined
      if (task?.id === 'cache.claude.plugins' && task.status === 'succeeded') {
        post({ type: 'claude.status' })
      }
      return
    }
    if (msg.type === 'job-started' && msg.toolId === 'claude-code') {
      const action = msg.action ?? ''
      if (action === 'uninstall') enterLifecycle('uninstall')
      else if (action === 'install') {
        enterLifecycle(isInstalled.value ? 'update' : 'install')
      }
    }
    if (msg.type === 'job-finished') {
      post({ type: 'claude.status' })
      applyLifecycleFinished(Boolean(msg.ok))
    }
    if (!isShared) consumeJobMessage(msg)
  })
  post({ type: 'claude.status' })
})

onUnmounted(() => {
  unsub?.()
  if (workspaceOwnsConsole) workspaceOwnsConsole.value = false
})

watch(tab, () => {
  selected.value = {}
  filter.value = ''
  if (!busy.value) resetWhenIdle()
})

function selectTab(id: ClaudeTab) {
  if (busy.value) return
  tab.value = id
}

function runJob(action: string, extra?: Record<string, unknown>) {
  if (busy.value) return
  const jobId = crypto.randomUUID().replaceAll('-', '')
  beginJob(jobId, `开始：${action}`)
  post({ type: 'run-job', jobId, toolId: 'claude-code', action, ...extra })
}

function saveApi() {
  post({
    type: 'claude.set-api',
    mode: apiMode.value,
    apiKey: apiKey.value,
    baseUrl: baseUrl.value,
    authToken: authToken.value,
  })
}

function saveProxy(mode: 'set' | 'clear') {
  post({
    type: 'claude.set-proxy',
    mode,
    httpProxy: httpProxy.value,
    httpsProxy: httpsProxy.value,
  })
}

function runPluginBatch() {
  const ids = selectedList.value
  if (!ids.length) {
    showToast('请先勾选插件', { kind: 'warn' })
    return
  }
  runJob(pluginAction.value, { versions: ids, plugins: ids.join(',') })
}

async function runReset() {
  if (busy.value) return
  const ok = await confirmDialog({
    title: '重置确认',
    message:
      '将仅恢复初始化相关设置（DISABLE_LOGIN_COMMAND 与预设 marketplace）。\n不会修改 API、代理或已装插件。',
    confirmText: '重置',
    cancelText: '取消',
    tone: 'danger',
  })
  if (!ok) return
  runJob('reset')
}
</script>

<template>
  <section class="claude-page volta-page" :class="{ embedded: props.embedded }">
    <!-- 未安装 / CLI 装更卸：整区仅进度+输出 -->
    <template v-if="showLifecycleView">
      <div class="folder-body folder-body--lifecycle">
        <JobConsole
          class="claude-lifecycle-job"
          always-show
          :progress="progress"
          :status-text="statusText"
          :entries="outputEntries"
          :busy="busy"
        />
      </div>
    </template>

    <template v-else>
      <RegionLock :active="busy" title="任务进行中，请先终止">
        <div class="folder-tabs" role="tablist" aria-label="Claude Code 功能">
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
            @click="selectTab(t.id)"
          >
            <span class="folder-tab-label">{{ t.label }}</span>
          </button>
        </div>
      </RegionLock>

      <div class="folder-body">
        <!-- 初始化：第一行按钮，下方整宽进度+输出 -->
        <div
          v-if="tab === 'init'"
          class="claude-init-layout"
          :class="{ 'is-job-locked': busy }"
        >
          <div class="tool-ops claude-init-ops">
            <div
              v-if="busy"
              class="tool-ops-lock"
              title="任务进行中，请先终止"
              aria-hidden="true"
            />
            <div class="ver-head claude-init-head">
              <button
                type="button"
                class="btn btn-ops"
                :disabled="busy"
                title="执行初始化"
                @click="runJob('init')"
              >
                <span class="btn-label">执行</span>
              </button>
              <button
                type="button"
                class="btn secondary btn-ops"
                :disabled="busy"
                title="仅重置初始化设置"
                @click="runReset"
              >
                <span class="btn-label">重置</span>
              </button>
            </div>
          </div>
          <JobConsole
            class="tool-console claude-init-console"
            always-show
            :progress="progress"
            :status-text="statusText"
            :entries="outputEntries"
            :busy="busy"
          />
        </div>

        <div
          v-else
          class="tool-stack"
          :class="{
            'is-job-locked': busy,
            'tool-stack--wide':
              tab === 'api' ||
              tab === 'proxy' ||
              tab === 'plugin-install' ||
              tab === 'plugin-update' ||
              tab === 'plugin-uninstall',
          }"
        >
          <div class="tool-ops">
            <div
              v-if="busy"
              class="tool-ops-lock"
              title="任务进行中，请先终止"
              aria-hidden="true"
            />

          <template v-if="tab === 'api'">
            <div class="ver-head">
              <button type="button" class="btn btn-ops" :disabled="busy" @click="saveApi">
                <span class="btn-label">保存</span>
              </button>
            </div>
            <div class="claude-pane claude-pane--form">
              <p class="claude-hint">
                当前：{{ secrets?.apiMode || '未配置'
                }}<template v-if="secrets?.apiKeyMasked"> · Key {{ secrets.apiKeyMasked }}</template>
              </p>
              <div class="form-stack">
                <label class="field-stack field-stack--sm">
                  模式
                  <select v-model="apiMode">
                    <option value="official">官方 API Key</option>
                    <option value="custom">自定义 Base URL + Token</option>
                    <option value="clear">清除</option>
                  </select>
                </label>
                <label v-if="apiMode === 'official'" class="field-stack field-stack--sm">
                  ANTHROPIC_API_KEY
                  <input v-model="apiKey" type="password" autocomplete="off" placeholder="sk-ant-…" />
                </label>
                <template v-if="apiMode === 'custom'">
                  <label class="field-stack field-stack--sm">
                    Base URL
                    <input v-model="baseUrl" type="url" placeholder="https://…" />
                  </label>
                  <label class="field-stack field-stack--sm">
                    Token
                    <input v-model="authToken" type="password" autocomplete="off" />
                  </label>
                </template>
              </div>
            </div>
          </template>

          <template v-else-if="tab === 'proxy'">
            <div class="ver-head">
              <button type="button" class="btn btn-ops" :disabled="busy" @click="saveProxy('set')">
                <span class="btn-label">保存</span>
              </button>
              <button
                type="button"
                class="btn secondary btn-ops"
                :disabled="busy"
                @click="saveProxy('clear')"
              >
                <span class="btn-label">清除</span>
              </button>
            </div>
            <div class="claude-pane claude-pane--form">
              <div class="form-stack">
                <label class="field-stack field-stack--sm">
                  HTTP_PROXY
                  <input v-model="httpProxy" placeholder="http://127.0.0.1:7890" />
                </label>
                <label class="field-stack field-stack--sm">
                  HTTPS_PROXY
                  <input v-model="httpsProxy" placeholder="留空则同 HTTP" />
                </label>
              </div>
            </div>
          </template>

          <template v-else>
            <div class="ver-head">
              <input
                v-model="filter"
                class="search"
                type="search"
                placeholder="过滤插件…"
                :aria-label="`过滤插件，已选 ${selectedList.length} 项`"
              />
              <button
                type="button"
                class="btn btn-ops"
                :disabled="busy || !selectedList.length"
                :title="!selectedList.length ? '请先勾选插件' : `${pluginActionLabel}所选插件`"
                @click="runPluginBatch()"
              >
                <span class="btn-label">{{ pluginActionLabel }}</span>
              </button>
            </div>
            <ul class="ver-list ver-list--install" aria-label="插件列表">
              <li v-if="featuredPlugins.length" class="claude-list-label">推荐</li>
              <li
                v-for="p in featuredPlugins"
                :key="'f-' + p.id"
                class="ver-row"
                :class="{ 'is-checked': selected[p.id] }"
              >
                <label class="ver-row-label">
                  <span class="ver-lead">
                    <input
                      v-model="selected[p.id]"
                      class="ver-check"
                      type="checkbox"
                      :disabled="busy"
                    />
                  </span>
                  <span class="ver-num" :title="p.description || p.id">{{ pluginRowLabel(p) }}</span>
                </label>
              </li>
              <li v-if="otherPlugins.length && featuredPlugins.length" class="claude-list-label">
                其他
              </li>
              <li
                v-for="p in otherPlugins"
                :key="'o-' + p.id"
                class="ver-row"
                :class="{ 'is-checked': selected[p.id] }"
              >
                <label class="ver-row-label">
                  <span class="ver-lead">
                    <input
                      v-model="selected[p.id]"
                      class="ver-check"
                      type="checkbox"
                      :disabled="busy"
                    />
                  </span>
                  <span class="ver-num" :title="p.description || p.id">{{ pluginRowLabel(p) }}</span>
                </label>
              </li>
              <li v-if="!filteredPlugins.length" class="empty-hint">{{ pluginEmptyHint }}</li>
            </ul>
          </template>
          </div>

          <JobConsole
            class="tool-console"
            always-show
            :progress="progress"
            :status-text="statusText"
            :entries="outputEntries"
            :busy="busy"
          />
        </div>
      </div>
    </template>
  </section>
</template>

<style scoped>
.claude-page {
  /* 初始化区在 tool-stack 外，与公共 ops 行高对齐 */
  --tool-head-h: var(--btn-ops-h, 1.85rem);
  --tool-ops-w: 13.75rem;
  --ver-check-size: 1rem;
}

.claude-page.embedded {
  display: flex;
  flex-direction: column;
  min-height: 0;
}

.folder-body--lifecycle {
  flex: 1;
  min-width: 0;
  min-height: 0;
  display: flex;
  flex-direction: column;
  border-top: 1px solid color-mix(in srgb, var(--line) 85%, transparent);
  border-radius: 0.65rem;
}

.claude-lifecycle-job {
  flex: 1;
  min-width: 0;
  min-height: 0;
  width: 100%;
}

.claude-init-layout {
  flex: 1;
  min-width: 0;
  min-height: 0;
  display: flex;
  flex-direction: column;
  gap: 0.55rem;
  overflow: hidden;
}

.claude-init-ops {
  position: relative;
  flex: 0 0 auto;
  width: 100%;
  max-width: min(22rem, 100%);
  min-height: 0;
}

.claude-init-head {
  width: 100%;
  min-width: 0;
  height: var(--tool-head-h);
  justify-content: flex-start;
}

.claude-init-console {
  flex: 1 1 auto;
  min-height: 0;
  width: 100%;
}

/* 顶栏按钮尺寸/居中：公共 .btn-ops / .ver-head > .btn（buttons.css） */

.claude-pane {
  min-height: 0;
  flex: 1 1 auto;
  overflow: auto;
  padding: 0.55rem 0.45rem;
  border: 1px solid color-mix(in srgb, var(--line) 80%, transparent);
  border-radius: 0.5rem;
  background: color-mix(in srgb, var(--panel) 40%, transparent);
}

.claude-list-label {
  list-style: none;
  margin: 0.15rem 0 0.35rem;
  padding: 0.2rem 0.45rem 0;
  font-size: 0.68rem;
  letter-spacing: 0.06em;
  color: var(--muted);
  border: none !important;
  background: transparent !important;
  box-shadow: none !important;
  pointer-events: none;
}

.ver-list--install .ver-num {
  min-width: 0;
  flex: 1;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 0.72rem;
}
</style>
