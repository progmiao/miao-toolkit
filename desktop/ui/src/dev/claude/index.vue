<script setup lang="ts">
/**
 * Claude Code 工作区：
 * - 未安装 / 安装·更新·卸载进行中：内容区整页为进度+输出（方案 B）
 * - 已安装且非生命周期任务：梯形 Tab（初始化 / API / 代理 / 插件）
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

type ClaudeTab = 'init' | 'api' | 'proxy' | 'plugin-install' | 'plugin-uninstall'
type LifecycleKind = 'install' | 'update' | 'uninstall'

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

type Plugin = { id: string; label: string; featured: boolean }

const workspaceOwnsConsole = inject(DEV_WORKSPACE_OWNS_CONSOLE_KEY, null)

const tab = ref<ClaudeTab>('init')
const status = ref<Status | null>(null)
const secrets = ref<Secrets | null>(null)
const plugins = ref<Plugin[]>([])
const selected = ref<Record<string, boolean>>({})
const customPlugin = ref('')
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
  { id: 'plugin-uninstall', label: '插件卸载' },
]

const {
  outputEntries,
  progress,
  statusText,
  busy,
  consumeJobMessage,
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

const featuredPlugins = computed(() => plugins.value.filter((p) => p.featured))
const otherPlugins = computed(() => plugins.value.filter((p) => !p.featured))

const selectedList = computed(() => {
  const ids = plugins.value.filter((p) => selected.value[p.id]).map((p) => p.id)
  if (customPlugin.value.trim()) ids.push(customPlugin.value.trim())
  return [...new Set(ids)]
})

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
  }
  // install / uninstall：等 claude.status 再收口，避免 catalog 与 status 短暂不一致闪屏
}

function settleLifecycleFromStatus() {
  if (busy.value || !lifecycleKind.value) return
  const kind = lifecycleKind.value
  if (kind === 'install' && isInstalled.value) {
    tab.value = 'init'
    lifecycleKind.value = null
  } else if (kind === 'uninstall' && !isInstalled.value) {
    lifecycleKind.value = null
  }
}

let unsub: (() => void) | undefined

onMounted(() => {
  if (workspaceOwnsConsole) workspaceOwnsConsole.value = true
  unsub = subscribe((msg) => {
    if (msg.type === 'claude.status') {
      status.value = msg.status as Status
      secrets.value = msg.secrets as Secrets
      plugins.value = (msg.plugins as Plugin[]) ?? []
      statusReady.value = true
      for (const p of plugins.value) {
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
  customPlugin.value = ''
})

function selectTab(id: ClaudeTab) {
  if (busy.value) return
  tab.value = id
}

function runJob(action: string, extra?: Record<string, unknown>) {
  if (busy.value) return
  const jobId = crypto.randomUUID().replaceAll('-', '')
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

function runPluginBatch(action: 'plugin-install' | 'plugin-uninstall') {
  const ids = selectedList.value
  if (!ids.length) {
    showToast('请先勾选或填写插件', { kind: 'warn' })
    return
  }
  runJob(action, { versions: ids, plugins: ids.join(',') })
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
    <!-- 方案 B：未安装 / 装更卸 → 整区仅进度+输出（操作在概览区） -->
    <template v-if="showLifecycleView">
      <div class="folder-body folder-body--lifecycle">
        <div class="volta-split volta-split--lifecycle">
          <JobConsole
            class="volta-job"
            always-show
            :progress="progress"
            :status-text="statusText"
            :entries="outputEntries"
            :busy="busy"
            placeholder="执行安装、更新或卸载后在此显示输出…"
          />
        </div>
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
        <div
          class="volta-split"
          :class="{
            'is-job-locked': busy,
            'volta-split--init': tab === 'init',
            'volta-split--form': tab === 'api' || tab === 'proxy',
            'volta-split--plugins': tab === 'plugin-install' || tab === 'plugin-uninstall',
          }"
        >
          <div
            v-if="busy && tab !== 'init'"
            class="volta-ops-lock"
            title="任务进行中，请先终止"
            aria-hidden="true"
          />

          <template v-if="tab === 'init'">
            <div class="ver-head claude-init-head">
              <button
                type="button"
                class="btn btn-install"
                :disabled="busy"
                title="执行初始化"
                @click="runJob('init')"
              >
                执行
              </button>
              <button
                type="button"
                class="btn secondary claude-head-btn"
                :disabled="busy"
                title="仅重置初始化设置"
                @click="runReset"
              >
                重置
              </button>
            </div>
          </template>

          <template v-else-if="tab === 'api'">
            <div class="ver-head">
              <button type="button" class="btn btn-install" :disabled="busy" @click="saveApi">
                保存
              </button>
            </div>
            <div class="claude-pane claude-pane--form">
              <p class="claude-hint">
                当前：{{ secrets?.apiMode || '未配置'
                }}<template v-if="secrets?.apiKeyMasked"> · Key {{ secrets.apiKeyMasked }}</template>
              </p>
              <div class="claude-form">
                <label>
                  模式
                  <select v-model="apiMode">
                    <option value="official">官方 API Key</option>
                    <option value="custom">自定义 Base URL + Token</option>
                    <option value="clear">清除</option>
                  </select>
                </label>
                <label v-if="apiMode === 'official'">
                  ANTHROPIC_API_KEY
                  <input v-model="apiKey" type="password" autocomplete="off" placeholder="sk-ant-…" />
                </label>
                <template v-if="apiMode === 'custom'">
                  <label>
                    Base URL
                    <input v-model="baseUrl" type="url" placeholder="https://…" />
                  </label>
                  <label>
                    Token
                    <input v-model="authToken" type="password" autocomplete="off" />
                  </label>
                </template>
              </div>
            </div>
          </template>

          <template v-else-if="tab === 'proxy'">
            <div class="ver-head">
              <button type="button" class="btn btn-install" :disabled="busy" @click="saveProxy('set')">
                保存
              </button>
              <button
                type="button"
                class="btn secondary claude-head-btn"
                :disabled="busy"
                @click="saveProxy('clear')"
              >
                清除
              </button>
            </div>
            <div class="claude-pane claude-pane--form">
              <div class="claude-form">
                <label>
                  HTTP_PROXY
                  <input v-model="httpProxy" placeholder="http://127.0.0.1:7890" />
                </label>
                <label>
                  HTTPS_PROXY
                  <input v-model="httpsProxy" placeholder="留空则同 HTTP" />
                </label>
              </div>
            </div>
          </template>

          <template v-else>
            <div class="ver-head">
              <input
                v-model="customPlugin"
                class="search"
                type="text"
                placeholder="自定义插件 id…"
                :aria-label="`自定义插件，已选 ${selectedList.length} 项`"
              />
              <button
                v-if="tab === 'plugin-install'"
                type="button"
                class="btn btn-install"
                :disabled="busy || !selectedList.length"
                :title="!selectedList.length ? '请先勾选插件' : '安装所选插件'"
                @click="runPluginBatch('plugin-install')"
              >
                安装
              </button>
              <button
                v-else
                type="button"
                class="btn btn-install"
                :disabled="busy || !selectedList.length"
                :title="!selectedList.length ? '请先勾选插件' : '卸载所选插件'"
                @click="runPluginBatch('plugin-uninstall')"
              >
                卸载
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
                  <span class="ver-num">{{ p.id }}</span>
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
                  <span class="ver-num">{{ p.id }}</span>
                </label>
              </li>
              <li v-if="!plugins.length" class="empty-hint">暂无插件清单</li>
            </ul>
          </template>

          <JobConsole
            class="volta-job"
            always-show
            :progress="progress"
            :status-text="statusText"
            :entries="outputEntries"
            :busy="busy"
            placeholder="执行操作后在此显示输出…"
          />
        </div>
      </div>
    </template>
  </section>
</template>

<style scoped>
.claude-page.embedded {
  display: flex;
  flex-direction: column;
  min-height: 0;
}

.folder-body--lifecycle {
  flex: 1;
  min-height: 0;
  border-top: 1px solid color-mix(in srgb, var(--line) 85%, transparent);
  border-radius: 0.65rem;
}

.volta-split--lifecycle {
  grid-template-columns: 1fr;
  grid-template-rows: auto minmax(0, 1fr);
  grid-template-areas:
    'prog'
    'panes';
}

.volta-split--form {
  --volta-list-w: minmax(14rem, 20rem);
}

.volta-split--plugins {
  --volta-list-w: minmax(12rem, 16rem);
}

.volta-split--init {
  grid-template-columns: 1fr;
  grid-template-rows: auto auto minmax(0, 1fr);
  grid-template-areas:
    'head'
    'prog'
    'panes';
}

.volta-split--init :deep(.progress-wrap) {
  margin-top: 0;
}

.claude-init-head {
  width: 100%;
  justify-content: flex-start;
}

.claude-pane {
  grid-area: list;
  min-height: 0;
  overflow: auto;
  padding: 0.55rem 0.45rem;
  border: 1px solid color-mix(in srgb, var(--line) 80%, transparent);
  border-radius: 0.5rem;
  background: color-mix(in srgb, var(--panel) 40%, transparent);
}

.claude-hint {
  margin: 0;
  font-size: 0.78rem;
  line-height: 1.45;
  color: var(--muted);
}

.claude-form {
  display: flex;
  flex-direction: column;
  gap: 0.65rem;
}

.claude-form label {
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
  font-size: 0.72rem;
  color: var(--muted);
}

.claude-form input,
.claude-form select {
  padding: 0.4rem 0.55rem;
  border: 1px solid var(--line);
  border-radius: 0.4rem;
  background: var(--panel-strong);
  color: var(--ink);
  font-family: var(--font-mono);
  font-size: 0.82rem;
}

.claude-head-btn {
  box-sizing: border-box;
  height: 100%;
  min-height: 0;
  margin: 0;
  padding: 0 0.7rem;
  line-height: 1;
  display: inline-flex;
  align-items: center;
  font-size: 0.74rem;
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
