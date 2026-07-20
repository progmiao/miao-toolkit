<script setup lang="ts">
/**
 * 开发工具 · Node.js 独立页（入口 index.vue）。
 * Tab：批量安装 / 指定版本 / 设置默认 / 批量卸载；右侧 JobConsole。
 * Host：Miao.Software/Dev/Volta；种子：seeds/dev/node/software.json
 */
import { computed, onMounted, onUnmounted, ref, watch } from 'vue'
import { RouterLink } from 'vue-router'
import JobConsole from '@kernel/components/JobConsole.vue'
import { post, subscribe, type VoltaVersion } from '@kernel/bridge/bus'
import { showToast } from '@kernel/bridge/toast'
import { useJobConsole } from '@kernel/composables/useJobConsole'
import { useShellTitle } from '@kernel/composables/useShellTitle'

useShellTitle('Node.js')

/** 功能 Tab。 */
type NodeTab = 'batch-install' | 'specify' | 'set-default' | 'batch-uninstall'

const tab = ref<NodeTab>('batch-install')

const versions = ref<VoltaVersion[]>([])
const selected = ref<Record<string, boolean>>({})
/** 设默认：单选版本号。 */
const defaultPick = ref<string | null>(null)
/** 指定版本：手动输入。 */
const specifyVersion = ref('')
const ltsOnly = ref(true)
const filter = ref('')
const loading = ref(false)
const error = ref('')
const conflicts = ref<string[]>([])
const voltaAvailable = ref(true)

const {
  logs,
  consoleLines,
  progress,
  busy,
  consumeJobMessage,
  cancel,
} = useJobConsole({
  onFinished: () => requestList(),
  onError: (message) => {
    error.value = message
    loading.value = false
  },
  formatStarted: (msg) => `开始：${msg.action ?? '任务'}`,
})

const tabs: { id: NodeTab; label: string }[] = [
  { id: 'batch-install', label: '批量安装' },
  { id: 'specify', label: '指定版本' },
  { id: 'set-default', label: '设置默认' },
  { id: 'batch-uninstall', label: '批量卸载' },
]

let unsub: (() => void) | undefined

/** 按当前 Tab 过滤后的版本列表。 */
const listForTab = computed(() => {
  const q = filter.value.trim().toLowerCase()
  return versions.value.filter((v) => {
    if (q && !v.version.includes(q) && !(v.lts ?? '').toLowerCase().includes(q)) {
      return false
    }
    if (tab.value === 'batch-uninstall' || tab.value === 'set-default') {
      return v.installed
    }
    return true
  })
})

const selectedList = computed(() =>
  listForTab.value.filter((v) => selected.value[v.version]).map((v) => v.version),
)

/** 向宿主拉取 Node 版本清单。 */
function requestList() {
  loading.value = true
  error.value = ''
  post({ type: 'volta.list', tool: 'node', ltsOnly: ltsOnly.value })
}

onMounted(() => {
  unsub = subscribe((msg) => {
    if (msg.type === 'volta.versions' && Array.isArray(msg.items)) {
      if (msg.tool && msg.tool !== 'node') return
      loading.value = false
      versions.value = msg.items as VoltaVersion[]
      voltaAvailable.value = msg.voltaAvailable !== false
      conflicts.value = (msg.conflicts as string[]) ?? []
      for (const v of versions.value) {
        if (selected.value[v.version] === undefined) selected.value[v.version] = false
      }
      if (!defaultPick.value) {
        const d = versions.value.find((x) => x.isDefault) ?? versions.value.find((x) => x.installed)
        defaultPick.value = d?.version ?? null
      }
      return
    }
    consumeJobMessage(msg)
  })
  requestList()
})

onUnmounted(() => unsub?.())

watch(tab, () => {
  selected.value = {}
  filter.value = ''
})

watch(ltsOnly, () => requestList())

/**
 * 全选 / 清空当前 Tab 列表勾选。
 * @param on - true 全选
 */
function toggleAll(on: boolean) {
  for (const v of listForTab.value) selected.value[v.version] = on
}

/**
 * 发起 Node 相关 Job。
 * @param action - install | uninstall | set-default
 * @param versionsArg - 版本列表；缺省用多选
 */
function runJob(action: string, versionsArg?: string[]) {
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
  })
}

/** 批量安装当前勾选。 */
function runBatchInstall() {
  runJob('install')
}

/** 安装输入框中的指定版本。 */
function runSpecifyInstall() {
  const ver = specifyVersion.value.trim().replace(/^v/i, '')
  if (!ver) {
    showToast('请输入版本号，例如 22.23.1 或 lts', { kind: 'warn' })
    return
  }
  runJob('install', [ver])
}

/** 将单选版本设为默认。 */
function runSetDefault() {
  if (!defaultPick.value) {
    showToast('请选择要设为默认的已装版本', { kind: 'warn' })
    return
  }
  runJob('set-default', [defaultPick.value])
}

/** 批量卸载勾选的已装版本。 */
function runBatchUninstall() {
  runJob('uninstall')
}

/** 安装 Volta 本体（前置）。 */
function installVoltaTool() {
  const jobId = crypto.randomUUID().replaceAll('-', '')
  post({ type: 'run-job', jobId, toolId: 'volta', action: 'install' })
}
</script>

<template>
  <section class="page page--scroll node-page">
    <header class="page-head row">
      <div>
        <p class="crumb">
          <RouterLink to="/dev">开发工具</RouterLink>
          <span>/</span>
          <span>Node.js</span>
        </p>
        <p>经 Volta 管理 Node：批量安装、指定版本、设默认、批量卸载（本页专属，不与其它工具共用）。</p>
      </div>
      <div class="actions">
        <button type="button" class="btn secondary" :disabled="loading || busy" @click="requestList">
          刷新清单
        </button>
        <button type="button" class="btn danger" :disabled="!busy" @click="cancel">取消任务</button>
      </div>
    </header>

    <p v-if="!voltaAvailable" class="prereq-banner">
      未安装 Volta。请先安装后再管理 Node 版本。
      <span class="prereq-actions">
        <button type="button" class="btn" :disabled="busy" @click="installVoltaTool">安装 Volta</button>
        <RouterLink class="btn secondary" to="/dev">返回开发工具</RouterLink>
      </span>
    </p>
    <p v-else-if="conflicts.length" class="banner-warn">
      检测到可能冲突的版本管理器：{{ conflicts.join('、') }}。建议统一使用 Volta。
    </p>
    <p v-if="error" class="banner-err">{{ error }}</p>

    <template v-if="voltaAvailable">
      <nav class="tabs" aria-label="Node 功能">
        <button
          v-for="t in tabs"
          :key="t.id"
          type="button"
          :class="{ active: tab === t.id }"
          @click="tab = t.id"
        >
          {{ t.label }}
        </button>
      </nav>

      <div class="node-layout">
        <div class="hud-panel main">
          <!-- 批量安装 -->
          <template v-if="tab === 'batch-install'">
            <h2 class="sec">批量安装</h2>
            <p class="hint">从远程清单多选版本后安装；可仅看 LTS。</p>
            <div class="ver-toolbar">
              <label class="toggle">
                <input v-model="ltsOnly" type="checkbox" />
                仅 LTS
              </label>
              <input v-model="filter" class="search" type="search" placeholder="过滤版本…" />
              <button type="button" class="btn ghost" @click="toggleAll(true)">全选</button>
              <button type="button" class="btn ghost" @click="toggleAll(false)">清空</button>
              <span class="count">{{ loading ? '同步中…' : `${listForTab.length} 项` }}</span>
            </div>
            <ul class="ver-list">
              <li v-for="v in listForTab" :key="v.version">
                <label>
                  <input v-model="selected[v.version]" type="checkbox" />
                  <span class="ver-num">{{ v.version }}</span>
                  <span v-if="v.lts" class="tag">LTS · {{ v.lts }}</span>
                  <span v-if="v.installed" class="tag status-installed">已装</span>
                  <span v-if="v.isDefault" class="tag">默认</span>
                </label>
              </li>
              <li v-if="!listForTab.length && !loading" class="empty-hint">无匹配版本</li>
            </ul>
            <div class="tab-actions">
              <button type="button" class="btn" :disabled="busy" @click="runBatchInstall">
                安装所选（{{ selectedList.length }}）
              </button>
            </div>
          </template>

          <!-- 指定版本 -->
          <template v-else-if="tab === 'specify'">
            <h2 class="sec">指定版本</h2>
            <p class="hint">直接输入版本号（如 22.23.1）或 lts / latest，由 Volta 安装。</p>
            <div class="form-row">
              <label>
                版本
                <input
                  v-model="specifyVersion"
                  type="text"
                  class="ver-input"
                  placeholder="22.23.1 或 lts"
                  :disabled="busy"
                  @keyup.enter="runSpecifyInstall"
                />
              </label>
              <button type="button" class="btn" :disabled="busy" @click="runSpecifyInstall">
                安装此版本
              </button>
            </div>
            <p class="hint sub">也可从下方清单点选填入（当前 {{ ltsOnly ? '仅 LTS' : '全部' }}）。</p>
            <div class="ver-toolbar">
              <label class="toggle">
                <input v-model="ltsOnly" type="checkbox" />
                仅 LTS
              </label>
              <input v-model="filter" class="search" type="search" placeholder="过滤…" />
            </div>
            <ul class="ver-list ver-list--pick">
              <li v-for="v in listForTab" :key="v.version">
                <button type="button" class="pick-row" :disabled="busy" @click="specifyVersion = v.version">
                  <span class="ver-num">{{ v.version }}</span>
                  <span v-if="v.lts" class="tag">LTS · {{ v.lts }}</span>
                  <span v-if="v.installed" class="tag status-installed">已装</span>
                </button>
              </li>
              <li v-if="!listForTab.length && !loading" class="empty-hint">无匹配版本</li>
            </ul>
          </template>

          <!-- 设置默认 -->
          <template v-else-if="tab === 'set-default'">
            <h2 class="sec">设置默认</h2>
            <p class="hint">从已安装版本中选择一个设为 Volta 默认 Node。</p>
            <ul class="ver-list">
              <li v-for="v in listForTab" :key="v.version">
                <label>
                  <input v-model="defaultPick" type="radio" name="node-default" :value="v.version" />
                  <span class="ver-num">{{ v.version }}</span>
                  <span v-if="v.lts" class="tag">LTS · {{ v.lts }}</span>
                  <span v-if="v.isDefault" class="tag">当前默认</span>
                  <span v-if="v.isCurrent" class="tag">当前会话</span>
                </label>
              </li>
              <li v-if="!listForTab.length && !loading" class="empty-hint">暂无已安装版本，请先安装</li>
            </ul>
            <div class="tab-actions">
              <button type="button" class="btn" :disabled="busy || !defaultPick" @click="runSetDefault">
                设为默认
              </button>
            </div>
          </template>

          <!-- 批量卸载 -->
          <template v-else>
            <h2 class="sec">批量卸载</h2>
            <p class="hint">勾选已安装的 Node 版本后卸载（默认版本请先改默认再卸）。</p>
            <div class="ver-toolbar">
              <input v-model="filter" class="search" type="search" placeholder="过滤…" />
              <button type="button" class="btn ghost" @click="toggleAll(true)">全选</button>
              <button type="button" class="btn ghost" @click="toggleAll(false)">清空</button>
              <span class="count">{{ loading ? '同步中…' : `${listForTab.length} 项` }}</span>
            </div>
            <ul class="ver-list">
              <li v-for="v in listForTab" :key="v.version">
                <label>
                  <input v-model="selected[v.version]" type="checkbox" />
                  <span class="ver-num">{{ v.version }}</span>
                  <span v-if="v.lts" class="tag">LTS · {{ v.lts }}</span>
                  <span v-if="v.isDefault" class="tag">默认</span>
                </label>
              </li>
              <li v-if="!listForTab.length && !loading" class="empty-hint">暂无已安装版本</li>
            </ul>
            <div class="tab-actions">
              <button
                type="button"
                class="btn secondary"
                :disabled="busy || !selectedList.length"
                @click="runBatchUninstall"
              >
                卸载所选（{{ selectedList.length }}）
              </button>
            </div>
          </template>
        </div>

        <aside class="job-side">
          <JobConsole
            :progress="progress"
            :logs="logs"
            :console-lines="consoleLines"
            :busy="busy"
            placeholder="执行操作后在此显示日志与命令输出…"
          />
        </aside>
      </div>
    </template>
  </section>
</template>

<style scoped>
.crumb {
  display: flex;
  gap: 0.4rem;
  margin: 0 0 0.35rem;
  font-size: 0.8rem;
  color: var(--muted);
  letter-spacing: 0.06em;
  text-transform: uppercase;
  font-family: var(--font-display);
}
.crumb a {
  color: var(--accent);
  text-decoration: none;
}
.prereq-banner {
  margin: 0 0 1rem;
  padding: 0.9rem 1rem;
  border: 1px solid color-mix(in srgb, var(--warn) 45%, var(--line));
  border-radius: 0.75rem;
  background: color-mix(in srgb, var(--warn) 12%, var(--panel));
  color: var(--ink);
  font-size: 0.95rem;
}
.prereq-actions {
  display: flex;
  gap: 0.5rem;
  margin-top: 0.65rem;
}
.banner-err {
  color: var(--danger);
  margin: 0 0 0.75rem;
}
.banner-warn {
  color: var(--warn);
  margin: 0 0 0.5rem;
  font-size: 0.9rem;
}
.tabs {
  display: flex;
  flex-wrap: wrap;
  gap: 0.35rem;
  margin-bottom: 0.85rem;
}
.tabs button {
  border: 1px solid var(--line);
  background: color-mix(in srgb, var(--panel) 70%, transparent);
  color: var(--ink);
  padding: 0.45rem 0.9rem;
  border-radius: 0.45rem;
  cursor: pointer;
  font-weight: 600;
}
.tabs button.active {
  border-color: var(--accent);
  box-shadow: inset 0 -2px 0 var(--accent);
  color: var(--accent);
}
.node-layout {
  display: grid;
  grid-template-columns: 1.15fr 0.95fr;
  gap: 1rem;
  min-height: 420px;
  align-items: stretch;
}
.main {
  display: flex;
  flex-direction: column;
  min-height: 0;
  max-height: 560px;
  padding: 0.95rem 1rem;
}
.sec {
  margin: 0 0 0.4rem;
  font-family: var(--font-display);
  font-size: 0.9rem;
  letter-spacing: 0.08em;
  text-transform: uppercase;
}
.hint {
  color: var(--muted);
  font-size: 0.9rem;
  margin: 0 0 0.75rem;
}
.hint.sub {
  margin-top: 0.85rem;
}
.ver-toolbar {
  display: flex;
  flex-wrap: wrap;
  gap: 0.45rem;
  align-items: center;
  margin-bottom: 0.55rem;
}
.search {
  flex: 1;
  min-width: 8rem;
  padding: 0.4rem 0.65rem;
  border: 1px solid var(--line);
  border-radius: 0.4rem;
  background: var(--panel-strong);
  color: var(--ink);
  font-family: var(--font-mono);
  font-size: 0.85rem;
}
.toggle {
  display: inline-flex;
  align-items: center;
  gap: 0.35rem;
  font-size: 0.9rem;
  color: var(--muted);
}
.count {
  margin-left: auto;
  font-size: 0.8rem;
  color: var(--muted);
  font-family: var(--font-mono);
}
.ver-list {
  list-style: none;
  margin: 0;
  padding: 0;
  overflow: auto;
  flex: 1;
  min-height: 8rem;
  border-top: 1px solid var(--line);
}
.ver-list li {
  display: flex;
  align-items: center;
  gap: 0.35rem;
  border-bottom: 1px solid color-mix(in srgb, var(--line) 70%, transparent);
  padding: 0.35rem 0.15rem;
}
.ver-list li label {
  flex: 1;
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.35rem 0.5rem;
  cursor: pointer;
  min-width: 0;
}
.ver-num {
  font-family: var(--font-mono);
  font-weight: 600;
  min-width: 5.5rem;
}
.empty-hint {
  justify-content: center;
  color: var(--muted);
  font-size: 0.88rem;
  padding: 1rem !important;
}
.tab-actions {
  display: flex;
  gap: 0.5rem;
  margin-top: 0.75rem;
  flex: 0 0 auto;
}
.form-row {
  display: flex;
  flex-wrap: wrap;
  gap: 0.65rem;
  align-items: flex-end;
}
.form-row label {
  display: flex;
  flex-direction: column;
  gap: 0.35rem;
  font-size: 0.88rem;
  color: var(--muted);
  flex: 1;
  min-width: 12rem;
}
.ver-input {
  padding: 0.5rem 0.7rem;
  border: 1px solid var(--line);
  border-radius: 0.4rem;
  background: var(--panel-strong);
  color: var(--ink);
  font-family: var(--font-mono);
  font-size: 0.95rem;
}
.pick-row {
  width: 100%;
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.35rem 0.5rem;
  border: none;
  background: transparent;
  color: inherit;
  cursor: pointer;
  text-align: left;
  padding: 0.15rem 0;
}
.pick-row:hover {
  color: var(--accent);
}
.job-side {
  min-height: 0;
  display: flex;
  flex-direction: column;
}
@media (max-width: 900px) {
  .node-layout {
    grid-template-columns: 1fr;
  }
}
</style>
