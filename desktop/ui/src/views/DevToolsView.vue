<script setup lang="ts">
/**
 * 开发工具：左侧精简列表 + 右侧宽操作区；分类过滤（不含 Volta）；单选动画。
 * 列表与操作区为半透明磨砂面板；列表使用细渐变滚动条。
 */
import { computed, onMounted, onUnmounted, ref, watch } from 'vue'
import { RouterLink } from 'vue-router'
import JobConsole from '../components/JobConsole.vue'
import ToolLogo from '../components/ToolLogo.vue'
import { type CatalogItem, post, subscribe } from '../bridge/bus'
import {
  buildTagFilters,
  needsVolta,
  showInstallAction,
  showUninstallAction,
  showUpdateAction,
} from '../bridge/toolMeta'

const items = ref<CatalogItem[]>([])
const tagFilter = ref('all')
const activeId = ref<string | null>(null)
const logs = ref<string[]>([])
const progress = ref(0)
const busy = ref(false)
const currentJob = ref<string | null>(null)

const filters = computed(() => buildTagFilters(items.value))

const filtered = computed(() => {
  if (tagFilter.value === 'all') return items.value
  return items.value.filter((i) => i.tags.includes(tagFilter.value))
})

const activeItem = computed(
  () => filtered.value.find((i) => i.id === activeId.value)
    ?? items.value.find((i) => i.id === activeId.value)
    ?? null,
)

/** 目录中的 Volta 工具项（前置条件检测）。 */
const voltaItem = computed(() => items.value.find((i) => i.id === 'volta') ?? null)

const voltaInstalled = computed(() => voltaItem.value?.status === 'installed')

/** 当前选中工具需要 Volta 且尚未安装。 */
const showVoltaPrereq = computed(
  () => needsVolta(activeItem.value) && !voltaInstalled.value,
)

/**
 * 右侧唯一功能提示（不含前置：前置改为操作按钮「安装 Volta」）。
 * 当前仅 Hermes 安装后需额外说明。
 */
const featureTip = computed(() => {
  if (showVoltaPrereq.value) return null
  if (activeItem.value?.id === 'hermes') {
    return '安装后建议新开终端执行 hermes setup --portal。'
  }
  return null
})

const panelRoute: Record<string, string> = {
  node: '/dev/node',
  pnpm: '/dev/pnpm',
  yarn: '/dev/yarn',
  'claude-code': '/dev/claude',
}

/** 安装状态短文案（配合「状态：」前缀）。 */
function statusLabel(it: CatalogItem): string {
  if (it.status === 'installed' && it.updateAvailable) return '有更新'
  switch (it.status) {
    case 'installed':
      return '已安装'
    case 'missing':
      return '未安装'
    default:
      return '未知'
  }
}

function statusClass(it: CatalogItem): string {
  if (it.status === 'installed' && it.updateAvailable) return 'status-outdated'
  return 'status-' + it.status
}

function appendLog(line: string) {
  logs.value.push(line)
  if (logs.value.length > 500) logs.value.shift()
}

/** 切换工具时清空上一任务日志，避免空闲控制台残留。 */
function resetConsole() {
  if (busy.value) return
  logs.value = []
  progress.value = 0
}

function requestCatalog() {
  post({ type: 'get-catalog', group: 'dev' })
}

let unsub: (() => void) | undefined

onMounted(() => {
  unsub = subscribe((msg) => {
    if (msg.type === 'catalog' && msg.items) {
      if (msg.group && msg.group !== 'dev') return
      items.value = msg.items as CatalogItem[]
      if (!activeId.value && items.value[0]) activeId.value = items.value[0].id
      else if (activeId.value && !items.value.some((i) => i.id === activeId.value)) {
        activeId.value = items.value[0]?.id ?? null
      }
    }
    if (msg.type === 'job-started') {
      busy.value = true
      currentJob.value = msg.jobId ?? null
      progress.value = 0
      logs.value = []
      appendLog(`—— 开始任务 ——`)
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
      appendLog(msg.ok ? `完成 (exit ${msg.exitCode})` : `失败 ${msg.detail ?? ''}`)
      currentJob.value = null
      requestCatalog()
    }
    if (msg.type === 'error' && msg.message) {
      appendLog(`[错误] ${msg.message}`)
      busy.value = false
    }
  })
  requestCatalog()
})

onUnmounted(() => unsub?.())

watch(filtered, (list) => {
  if (!list.length) return
  if (!list.some((i) => i.id === activeId.value)) activeId.value = list[0].id
})

watch(activeId, () => resetConsole())

function selectRow(it: CatalogItem) {
  activeId.value = it.id
}

/** 跳到 Volta 工具详情（在本页选中 Volta，由其完成安装）。 */
function goToVolta() {
  const v = voltaItem.value
  if (v) activeId.value = v.id
}

function runAction(action: string, id: string) {
  const jobId = crypto.randomUUID().replaceAll('-', '')
  post({ type: 'run-job', jobId, toolId: id, action })
}

function cancel() {
  if (currentJob.value) post({ type: 'cancel-job', jobId: currentJob.value })
}

function openDoc(which: 'gitee' | 'github') {
  const url =
    which === 'gitee'
      ? 'https://gitee.com/updateme/terminal-buddy'
      : 'https://github.com/updateme/terminal-buddy'
  post({ type: 'open-url', url })
}
</script>

<template>
  <section class="page dev-page">
    <header class="page-head">
      <h1>开发工具</h1>
    </header>

    <nav class="filter-bar" aria-label="分类过滤">
      <button
        v-for="f in filters"
        :key="f.id"
        type="button"
        class="filter-chip"
        :class="{ active: tagFilter === f.id }"
        @click="tagFilter = f.id"
      >
        {{ f.label }}
      </button>
    </nav>

    <div class="dev-layout">
      <ul class="dev-list dev-frost">
        <li
          v-for="it in filtered"
          :key="it.id"
          :class="{ active: activeId === it.id }"
          @click="selectRow(it)"
        >
          <ToolLogo :tool-id="it.id" :name="it.name" size="md" />
          <div class="tool-body">
            <span class="tool-name">{{ it.name }}</span>
            <div class="tool-meta">
              <span class="meta meta-status" :class="statusClass(it)">状态：{{ statusLabel(it) }}</span>
              <span v-if="needsVolta(it)" class="meta meta-prereq">前置：Volta</span>
            </div>
          </div>
        </li>
        <li v-if="!filtered.length" class="empty-row">该分类下暂无工具</li>
      </ul>

      <aside class="job-panel dev-frost">
        <div v-if="activeItem" class="panel-box">
          <div class="detail-head">
            <ToolLogo :tool-id="activeItem.id" :name="activeItem.name" size="md" />
            <div class="detail-text">
              <h2 class="panel-title">{{ activeItem.name }}</h2>
              <p v-if="activeItem.description" class="panel-desc">{{ activeItem.description }}</p>
            </div>
          </div>

          <div class="actions">
            <template v-if="panelRoute[activeItem.id]">
              <button
                v-if="showVoltaPrereq"
                type="button"
                class="btn"
                @click="goToVolta"
              >
                安装 Volta
              </button>
              <RouterLink
                v-else
                class="btn"
                :to="panelRoute[activeItem.id]"
              >
                打开控制台
              </RouterLink>
            </template>
            <template v-else>
              <button
                v-if="showInstallAction(activeItem)"
                type="button"
                class="btn"
                :disabled="busy"
                @click="runAction('install', activeItem.id)"
              >
                安装
              </button>
              <button
                v-if="showUpdateAction(activeItem)"
                type="button"
                class="btn"
                :disabled="busy"
                @click="runAction('install', activeItem.id)"
              >
                更新
              </button>
              <button
                v-if="showUninstallAction(activeItem)"
                type="button"
                class="btn secondary"
                :disabled="busy"
                @click="runAction('uninstall', activeItem.id)"
              >
                卸载
              </button>
              <button v-if="busy" type="button" class="btn danger" @click="cancel">取消</button>
              <template v-if="activeItem.id === 'terminal-buddy'">
                <button type="button" class="btn ghost" @click="openDoc('gitee')">Gitee 文档</button>
                <button type="button" class="btn ghost" @click="openDoc('github')">GitHub 文档</button>
              </template>
            </template>
          </div>

          <p v-if="featureTip" class="panel-tip tip-feature">{{ featureTip }}</p>
        </div>

        <JobConsole :progress="progress" :logs="logs" :busy="busy" />
      </aside>
    </div>
  </section>
</template>

<style scoped>
.dev-page {
  position: relative;
  display: flex;
  flex-direction: column;
  min-height: 0;
  height: 100%;
  max-height: 100%;
  overflow: hidden;
  background: transparent;
}
.page-head {
  flex: 0 0 auto;
}
.filter-bar {
  display: flex;
  flex-wrap: wrap;
  gap: 0.45rem;
  margin: 0.35rem 0 1rem;
  flex: 0 0 auto;
  padding: 0.45rem 0.5rem;
  border-radius: 0.75rem;
  border: 1px solid color-mix(in srgb, var(--line) 80%, transparent);
  background: color-mix(in srgb, var(--panel) 42%, transparent);
  backdrop-filter: blur(16px) saturate(1.3);
  -webkit-backdrop-filter: blur(16px) saturate(1.3);
}
.filter-chip {
  border: 1px solid color-mix(in srgb, var(--line) 90%, transparent);
  background: color-mix(in srgb, var(--panel) 55%, transparent);
  color: var(--muted);
  padding: 0.35rem 0.85rem;
  border-radius: 999px;
  font-weight: 600;
  font-size: 0.88rem;
  letter-spacing: 0.04em;
  cursor: pointer;
  backdrop-filter: blur(8px);
  -webkit-backdrop-filter: blur(8px);
  transition:
    background 0.2s ease,
    border-color 0.2s ease,
    color 0.2s ease,
    transform 0.15s ease,
    box-shadow 0.2s ease;
}
.filter-chip:hover {
  color: var(--ink);
  border-color: color-mix(in srgb, var(--accent) 40%, var(--line));
  transform: translateY(-1px);
}
.filter-chip.active {
  color: var(--accent-ink);
  background: linear-gradient(135deg, var(--accent), color-mix(in srgb, var(--accent-2) 50%, var(--accent)));
  border-color: transparent;
  box-shadow: 0 0 14px var(--glow);
}
.dev-layout {
  flex: 1;
  min-height: 0;
  display: grid;
  /* 两行文案 + 大图标对齐；略加宽 */
  grid-template-columns: minmax(18.5rem, 20.5rem) minmax(0, 1fr);
  gap: 1rem;
  align-items: stretch;
}

/* 列表 / 操作区：半透明磨砂面板 */
.dev-frost {
  background: color-mix(in srgb, var(--panel) 42%, transparent);
  border: 1px solid color-mix(in srgb, var(--line) 85%, transparent);
  border-radius: 0.9rem;
  backdrop-filter: blur(22px) saturate(1.4);
  -webkit-backdrop-filter: blur(22px) saturate(1.4);
  box-shadow:
    inset 0 1px 0 color-mix(in srgb, #fff 28%, transparent),
    inset 0 0 36px color-mix(in srgb, var(--accent) 5%, transparent),
    0 10px 28px color-mix(in srgb, var(--ink) 5%, transparent);
}

.dev-list {
  list-style: none;
  margin: 0;
  padding: 0.45rem 0.35rem 0.45rem 0.4rem;
  min-height: 0;
  height: 100%;
  min-width: 0;
  /* 仅竖向滚动，禁止横向 */
  overflow-x: hidden;
  overflow-y: auto;
}

.dev-list li {
  display: flex;
  /* 图标与「名称+标签」整体等高垂直居中对齐 */
  align-items: center;
  gap: 0.65rem;
  padding: 0.65rem 0.55rem;
  margin-bottom: 0.25rem;
  border-radius: 0.55rem;
  cursor: pointer;
  min-width: 0;
  max-width: 100%;
  box-sizing: border-box;
  transition:
    background 0.2s ease,
    box-shadow 0.22s ease;
}
.dev-list li.empty-row {
  cursor: default;
  color: var(--muted);
  font-size: 0.85rem;
  justify-content: center;
  align-items: center;
  min-height: 2.75rem;
}
.dev-list li:not(.empty-row):hover {
  background: color-mix(in srgb, var(--accent) 10%, transparent);
}
.dev-list li.active {
  background: color-mix(in srgb, var(--accent) 16%, transparent);
  box-shadow:
    inset 3px 0 0 var(--accent),
    0 0 18px color-mix(in srgb, var(--glow) 55%, transparent);
}
/* 列表图标：与名称+标签总高度对齐（约 2.75rem） */
.dev-list :deep(.tool-logo.md) {
  width: 2.75rem;
  height: 2.75rem;
  font-size: 1.05rem;
  border-radius: 0.6rem;
}
.tool-body {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  justify-content: center;
  gap: 0.32rem;
  overflow: hidden;
  /* 与图标同高，保证行内对齐 */
  min-height: 2.75rem;
}
.tool-name {
  display: flex;
  align-items: center;
  font-weight: 700;
  font-size: 0.92rem;
  line-height: 1.2;
  min-height: 1.15rem;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.tool-meta {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.3rem;
  max-width: 100%;
  min-height: 1.28rem;
}
.meta {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  box-sizing: border-box;
  height: 1.28rem;
  padding: 0 0.42rem;
  font-size: 0.68rem;
  font-weight: 650;
  letter-spacing: 0.02em;
  line-height: 1;
  border-radius: 0.35rem;
  border: 1px solid transparent;
  white-space: nowrap;
  max-width: 100%;
  vertical-align: middle;
}
.meta-prereq {
  color: var(--warn);
  background: transparent;
  border-style: dashed;
  border-color: color-mix(in srgb, var(--warn) 55%, transparent);
}
.meta-status.status-installed {
  color: var(--ok);
  background: color-mix(in srgb, var(--ok) 14%, transparent);
  border-color: color-mix(in srgb, var(--ok) 28%, transparent);
}
.meta-status.status-outdated {
  color: var(--warn);
  background: color-mix(in srgb, var(--warn) 14%, transparent);
  border-color: color-mix(in srgb, var(--warn) 28%, transparent);
}
.meta-status.status-missing {
  color: var(--muted);
  background: color-mix(in srgb, var(--muted) 12%, transparent);
  border-color: color-mix(in srgb, var(--muted) 22%, transparent);
}
.meta-status.status-unknown {
  color: var(--muted);
  background: color-mix(in srgb, var(--muted) 10%, transparent);
  border-color: color-mix(in srgb, var(--muted) 20%, transparent);
}
.job-panel {
  min-height: 0;
  height: 100%;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
  padding: 0.95rem 1rem;
  overflow-x: hidden;
  overflow-y: auto;
}
.panel-box {
  flex: 0 0 auto;
  background: transparent;
  border: none;
  padding: 0;
  backdrop-filter: none;
  -webkit-backdrop-filter: none;
  box-shadow: none;
}
.detail-head {
  display: flex;
  gap: 0.75rem;
  align-items: flex-start;
  margin-bottom: 0.85rem;
}
.detail-text {
  flex: 1;
  min-width: 0;
}
.panel-title {
  margin: 0 0 0.4rem;
  font-family: var(--font-display);
  font-size: 0.95rem;
  letter-spacing: 0.06em;
  text-transform: uppercase;
}
.panel-desc {
  margin: 0;
  color: var(--muted);
  font-size: 0.88rem;
  line-height: 1.45;
}
.actions {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
}
.panel-tip {
  margin: 0.75rem 0 0;
  padding: 0.65rem 0.85rem;
  border-radius: 0.55rem;
  font-size: 0.88rem;
  line-height: 1.4;
  color: var(--ink);
  backdrop-filter: blur(10px);
  -webkit-backdrop-filter: blur(10px);
}
.tip-feature {
  border: 1px solid color-mix(in srgb, var(--accent) 35%, var(--line));
  background: color-mix(in srgb, var(--accent) 10%, transparent);
}
.job-panel :deep(.job-console) {
  flex: 1;
  min-height: 0;
}
.job-panel :deep(.progress-wrap),
.job-panel :deep(.log) {
  background: color-mix(in srgb, var(--panel) 40%, transparent);
  backdrop-filter: blur(10px);
  -webkit-backdrop-filter: blur(10px);
}
@media (max-width: 900px) {
  .dev-layout {
    grid-template-columns: 1fr;
  }
  .dev-list,
  .job-panel {
    height: auto;
    max-height: 360px;
  }
}
</style>
