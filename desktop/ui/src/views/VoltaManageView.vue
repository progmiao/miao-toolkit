<script setup lang="ts">
/**
 * Volta 多版本管理面板：node / pnpm / yarn 共用。
 * 支持多选安装、卸载、设默认、项目 pin。
 */
import { computed, onMounted, onUnmounted, ref, watch } from 'vue'
import { RouterLink } from 'vue-router'
import JobConsole from '../components/JobConsole.vue'
import { post, subscribe, type VoltaVersion } from '../bridge/bus'

const props = defineProps<{
  /** node | pnpm | yarn */
  toolId: string
  /** 页面标题 */
  title: string
}>()

const versions = ref<VoltaVersion[]>([])
const selected = ref<Record<string, boolean>>({})
const ltsOnly = ref(props.toolId === 'node')
const filter = ref('')
const loading = ref(false)
const logs = ref<string[]>([])
const progress = ref(0)
const busy = ref(false)
const currentJob = ref<string | null>(null)
const error = ref('')
const conflicts = ref<string[]>([])
const voltaAvailable = ref(true)
const projectPath = ref('')
const pendingPinVersion = ref<string | null>(null)

let unsub: (() => void) | undefined

const showLtsToggle = computed(() => props.toolId === 'node')

const filtered = computed(() => {
  const q = filter.value.trim().toLowerCase()
  return versions.value.filter((v) => {
    if (q && !v.version.includes(q) && !(v.lts ?? '').toLowerCase().includes(q)) return false
    return true
  })
})

const selectedList = computed(() =>
  filtered.value.filter((v) => selected.value[v.version]).map((v) => v.version),
)

function appendLog(line: string) {
  logs.value.push(line)
  if (logs.value.length > 500) logs.value.shift()
}

function requestList() {
  loading.value = true
  error.value = ''
  post({ type: 'volta.list', tool: props.toolId, ltsOnly: ltsOnly.value })
}

onMounted(() => {
  unsub = subscribe((msg) => {
    if (msg.type === 'volta.versions' && Array.isArray(msg.items)) {
      if (msg.tool && msg.tool !== props.toolId) return
      loading.value = false
      versions.value = msg.items as VoltaVersion[]
      voltaAvailable.value = msg.voltaAvailable !== false
      conflicts.value = (msg.conflicts as string[]) ?? []
      for (const v of versions.value) {
        if (selected.value[v.version] === undefined) selected.value[v.version] = false
      }
    }
    if (msg.type === 'dialog.folder' && pendingPinVersion.value) {
      if (msg.path) {
        projectPath.value = String(msg.path)
        run('pin', [pendingPinVersion.value], { projectPath: projectPath.value })
      } else {
        appendLog('已取消选择项目目录')
      }
      pendingPinVersion.value = null
    }
    if (msg.type === 'job-started') {
      busy.value = true
      currentJob.value = msg.jobId ?? null
      progress.value = 0
      appendLog(`—— 开始 ${msg.action ?? 'job'} ——`)
    }
    if (msg.type === 'job-event') {
      if (msg.kind === 'progress' && msg.message) {
        progress.value = Number(msg.message) || progress.value
      } else if (msg.message) {
        appendLog(msg.message)
      }
    }
    if (msg.type === 'job-finished') {
      busy.value = false
      progress.value = msg.ok ? 100 : progress.value
      appendLog(
        msg.ok
          ? `完成 (exit ${msg.exitCode})`
          : `失败 (exit ${msg.exitCode}) ${msg.detail ?? ''}`,
      )
      currentJob.value = null
      requestList()
    }
    if (msg.type === 'error' && msg.message) {
      error.value = msg.message
      loading.value = false
      busy.value = false
      appendLog(`[错误] ${msg.message}`)
    }
  })
  requestList()
})

watch(
  () => props.toolId,
  () => {
    versions.value = []
    selected.value = {}
    ltsOnly.value = props.toolId === 'node'
    requestList()
  },
)

onUnmounted(() => unsub?.())

function toggleAll(on: boolean) {
  for (const v of filtered.value) selected.value[v.version] = on
}

function run(action: string, versionsArg?: string[], extra?: Record<string, string>) {
  const list = versionsArg ?? selectedList.value
  if (!list.length && action !== 'pin') {
    appendLog('请先勾选版本')
    return
  }
  const jobId = crypto.randomUUID().replaceAll('-', '')
  post({
    type: 'run-job',
    jobId,
    toolId: props.toolId,
    action,
    versions: list,
    ...extra,
  })
}

function pinOne(ver: string) {
  pendingPinVersion.value = ver
  post({ type: 'dialog.pick-folder' })
}

function cancel() {
  if (currentJob.value) post({ type: 'cancel-job', jobId: currentJob.value })
}

/** 安装 Volta 工具本体（非包版本）。 */
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
          <span>{{ title }}</span>
        </p>
        <h1>{{ title }}</h1>
        <p>经 Volta 管理多版本：浏览远程清单、批量安装 / 卸载、设默认、pin 到项目。</p>
      </div>
      <div class="actions">
        <label v-if="showLtsToggle" class="toggle">
          <input v-model="ltsOnly" type="checkbox" @change="requestList" />
          仅 LTS
        </label>
        <button type="button" class="btn secondary" :disabled="loading || busy" @click="requestList">
          刷新
        </button>
        <button type="button" class="btn" :disabled="busy" @click="run('install')">安装所选</button>
        <button type="button" class="btn secondary" :disabled="busy" @click="run('uninstall')">
          卸载所选
        </button>
        <button type="button" class="btn danger" :disabled="!busy" @click="cancel">取消</button>
      </div>
    </header>

    <p v-if="!voltaAvailable" class="prereq-banner">
      未安装 Volta。请先安装「Volta」工具后再管理版本。
      <span class="actions" style="margin-top: 0.65rem; display: flex; gap: 0.5rem">
        <button type="button" class="btn" :disabled="busy" @click="installVoltaTool">安装 Volta</button>
        <RouterLink class="btn secondary" to="/dev">返回开发工具</RouterLink>
      </span>
    </p>
    <p v-else-if="conflicts.length" class="banner-warn">
      检测到可能冲突的版本管理器：{{ conflicts.join('、') }}。建议统一使用 Volta。
    </p>
    <p v-if="error" class="banner-err">{{ error }}</p>

    <div v-if="voltaAvailable" class="node-layout">
      <div class="ver-panel hud-panel">
        <div class="ver-toolbar">
          <input v-model="filter" class="search" type="search" placeholder="过滤版本…" />
          <button type="button" class="btn ghost" @click="toggleAll(true)">全选</button>
          <button type="button" class="btn ghost" @click="toggleAll(false)">清空</button>
          <span class="hint">{{ loading ? '同步中…' : `${filtered.length} 项` }}</span>
        </div>
        <ul class="ver-list">
          <li v-for="v in filtered" :key="v.version">
            <label>
              <input v-model="selected[v.version]" type="checkbox" />
              <span class="ver-num">{{ v.version }}</span>
              <span v-if="v.lts" class="tag">{{ toolId === 'node' ? `LTS · ${v.lts}` : v.lts }}</span>
              <span v-if="v.installed" class="tag status-installed">已装</span>
              <span v-if="v.isDefault" class="tag">默认</span>
              <span v-if="v.isCurrent" class="tag">当前</span>
            </label>
            <button
              v-if="v.installed && !v.isDefault"
              type="button"
              class="btn ghost mini"
              :disabled="busy"
              @click="run('set-default', [v.version])"
            >
              设默认
            </button>
            <button
              type="button"
              class="btn ghost mini"
              :disabled="busy"
              @click="pinOne(v.version)"
            >
              Pin
            </button>
          </li>
          <li v-if="!filtered.length && !loading" class="empty-hint">无匹配版本</li>
        </ul>
      </div>

      <aside class="job-panel">
        <JobConsole :progress="progress" :logs="logs" :busy="busy" placeholder="选择版本后执行操作…" />
      </aside>
    </div>
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
.banner-err {
  color: var(--danger);
  margin: 0 0 0.75rem;
}
.banner-warn {
  color: var(--warn);
  margin: 0 0 0.5rem;
  font-size: 0.9rem;
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
.node-layout {
  display: grid;
  grid-template-columns: 1.15fr 0.95fr;
  gap: 1rem;
  min-height: 440px;
}
.ver-panel {
  display: flex;
  flex-direction: column;
  min-height: 0;
  max-height: 560px;
}
.ver-toolbar {
  display: flex;
  flex-wrap: wrap;
  gap: 0.45rem;
  align-items: center;
  margin-bottom: 0.65rem;
}
.search {
  flex: 1;
  min-width: 10rem;
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
.hint {
  margin-left: auto;
  font-size: 0.8rem;
  color: var(--muted);
  font-family: var(--font-display);
  letter-spacing: 0.06em;
}
.ver-list {
  list-style: none;
  margin: 0;
  padding: 0;
  overflow: auto;
  flex: 1;
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
.btn.mini {
  padding: 0.25rem 0.45rem;
  font-size: 0.75rem;
}
@media (max-width: 900px) {
  .node-layout {
    grid-template-columns: 1fr;
  }
}
</style>
