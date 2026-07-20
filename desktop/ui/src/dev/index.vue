<script setup lang="ts">
/**
 * 开发工具：左侧精简列表 + 右侧宽操作区；分类过滤（不含 Volta）；单选动画。
 * 前置条件只在右侧操作区展示；单纯安装类用等高大按钮；顶栏下有科幻分隔线。
 */
import { computed, onMounted, onUnmounted, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import JobConsole from '@kernel/components/JobConsole.vue'
import ToolLogo from '@kernel/catalog/ToolLogo.vue'
import { catalogStatusClass, catalogStatusLabel } from '@kernel/catalog/statusMeta'
import { type CatalogItem, post, subscribe } from '@kernel/bridge/bus'
import { confirmDialog } from '@kernel/bridge/confirm'
import { useJobConsole } from '@kernel/composables/useJobConsole'
import { useShellTitle } from '@kernel/composables/useShellTitle'
import {
  buildTagFilters,
  showInstallAction,
  showUninstallAction,
  showUpdateAction,
} from '@kernel/catalog/toolMeta'

useShellTitle('开发工具')

const router = useRouter()

const items = ref<CatalogItem[]>([])
const tagFilter = ref('all')
const activeId = ref<string | null>(null)
/** 工具列表是否正在向宿主拉取目录（首屏与刷新）。 */
const listLoading = ref(true)
/** 骨架行数量（与常见列表密度接近，仅视觉占位）。 */
const skeletonRows = 6

const {
  logs,
  consoleLines,
  progress,
  busy,
  consumeJobMessage,
  resetWhenIdle,
  cancel,
} = useJobConsole({
  onFinished: () => requestCatalog(),
  onError: () => {
    if (listLoading.value) listLoading.value = false
  },
  formatStarted: (msg) => `开始：${msg.action ?? '任务'}（${msg.toolId ?? ''}）`,
  formatFinished: (msg) =>
    msg.ok ? `完成（exit ${msg.exitCode}）` : `失败：${msg.detail ?? ''}`,
})

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

/**
 * 单纯安装/更新/卸载时用等高大按钮。
 * 已有独立页的工具点列表即进入，不用大按钮。
 */
const useTallActions = computed(() => {
  const it = activeItem.value
  if (!it) return false
  if (panelRoute(it)) return false
  return true
})

/**
 * 右侧唯一功能提示。
 * 当前仅 Hermes 安装后需额外说明。
 */
const featureTip = computed(() => {
  if (activeItem.value?.id === 'hermes') {
    return '安装后建议新开终端执行 hermes setup --portal。'
  }
  return null
})

/**
 * 解析专用面板路由：优先 seeds `ui.entry` → `/dev/{entry}`。
 * @param it - 目录项
 * @returns 路由 path；无独立页时 null
 */
function panelRoute(it: CatalogItem): string | null {
  if (it.uiMode !== 'panel') return null
  const entry = (it.uiEntry ?? '').trim()
  if (!entry) return null
  return `/dev/${entry}`
}

/**
 * 选中列表项：有独立管理页的工具直接进入该页（不再经「打开控制台」）。
 * @param it - 目录项
 */
function selectRow(it: CatalogItem) {
  const route = panelRoute(it)
  if (route) {
    void router.push(route)
    return
  }
  activeId.value = it.id
}

/**
 * 向宿主请求开发工具目录；进入加载态直至收到 `catalog`。
 * 任务结束后刷新也会走此路径。
 */
function requestCatalog() {
  listLoading.value = true
  post({ type: 'get-catalog', group: 'dev' })
}

let unsub: (() => void) | undefined

onMounted(() => {
  unsub = subscribe((msg) => {
    if (msg.type === 'catalog' && msg.items) {
      if (msg.group && msg.group !== 'dev') return
      items.value = msg.items as CatalogItem[]
      listLoading.value = false
      if (!activeId.value && items.value[0]) activeId.value = items.value[0].id
      else if (activeId.value && !items.value.some((i) => i.id === activeId.value)) {
        activeId.value = items.value[0]?.id ?? null
      }
      return
    }
    consumeJobMessage(msg)
  })
  requestCatalog()
})

onUnmounted(() => unsub?.())

watch(filtered, (list) => {
  if (!list.length) return
  if (!list.some((i) => i.id === activeId.value)) activeId.value = list[0].id
})

watch(activeId, () => resetWhenIdle())

async function runAction(action: string, id: string) {
  if (action === 'uninstall') {
    const name = items.value.find((i) => i.id === id)?.name ?? id
    const message =
      id === 'volta'
        ? `确认卸载 ${name}？卸载后 Node / pnpm / Yarn 将无法通过 Volta 管理。`
        : `确认卸载 ${name}？`
    const ok = await confirmDialog({
      title: '卸载确认',
      message,
      confirmText: '卸载',
      cancelText: '取消',
      tone: 'danger',
    })
    if (!ok) return
  }
  const jobId = crypto.randomUUID().replaceAll('-', '')
  post({ type: 'run-job', jobId, toolId: id, action })
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
      <ul
        class="dev-list dev-frost"
        :class="{ 'dev-list--loading': listLoading }"
        :aria-busy="listLoading"
        aria-label="工具列表"
      >
        <template v-if="listLoading && !items.length">
          <li
            v-for="n in skeletonRows"
            :key="'sk-' + n"
            class="skel-row"
            aria-hidden="true"
          >
            <span class="skel-logo" />
            <span class="skel-body">
              <span class="skel-line skel-line--name" />
              <span class="skel-line skel-line--meta" />
            </span>
          </li>
          <li class="list-loading-hint" role="status">
            <span class="list-spinner" aria-hidden="true" />
            <span>加载工具列表…</span>
          </li>
        </template>
        <template v-else>
          <li
            v-for="it in filtered"
            :key="it.id"
            :class="{ active: activeId === it.id }"
            @click="selectRow(it)"
          >
            <ToolLogo
              :tool-id="it.id"
              :name="it.name"
              size="md"
              :update-available="Boolean(it.updateAvailable)"
            />
            <div class="tool-body">
              <span class="tool-name">{{ it.name }}</span>
              <div class="tool-meta">
                <span class="meta meta-status" :class="catalogStatusClass(it)">{{ catalogStatusLabel(it) }}</span>
              </div>
            </div>
          </li>
          <li v-if="listLoading" class="list-loading-bar" role="status" aria-live="polite">
            <span class="list-spinner list-spinner--sm" aria-hidden="true" />
            <span>刷新中…</span>
          </li>
          <li v-else-if="!filtered.length" class="empty-row">该分类下暂无工具</li>
        </template>
      </ul>

      <aside class="job-panel dev-frost">
        <div v-if="activeItem" class="panel-box">
          <div class="detail-row">
            <div class="detail-head">
              <ToolLogo
                :tool-id="activeItem.id"
                :name="activeItem.name"
                size="md"
                :update-available="Boolean(activeItem.updateAvailable)"
              />
              <div class="detail-text">
                <h2 class="panel-title">{{ activeItem.name }}</h2>
                <p v-if="activeItem.description" class="panel-desc">{{ activeItem.description }}</p>
                <p v-if="featureTip" class="panel-tip tip-feature">{{ featureTip }}</p>
              </div>
            </div>

            <div class="actions" :class="{ 'actions--tall': useTallActions }">
              <template v-if="!panelRoute(activeItem)">
                <button
                  v-if="showInstallAction(activeItem)"
                  type="button"
                  class="btn action-btn"
                  :disabled="busy"
                  @click="runAction('install', activeItem.id)"
                >
                  安装
                </button>
                <button
                  v-if="showUpdateAction(activeItem)"
                  type="button"
                  class="btn action-btn"
                  :disabled="busy"
                  @click="runAction('install', activeItem.id)"
                >
                  更新
                </button>
                <button
                  v-if="showUninstallAction(activeItem)"
                  type="button"
                  class="btn secondary action-btn"
                  :disabled="busy"
                  @click="runAction('uninstall', activeItem.id)"
                >
                  卸载
                </button>
                <button
                  v-if="busy"
                  type="button"
                  class="btn danger action-btn"
                  @click="cancel"
                >
                  取消
                </button>
                <template v-if="activeItem.id === 'terminal-buddy'">
                  <button type="button" class="btn ghost" @click="openDoc('gitee')">Gitee 文档</button>
                  <button type="button" class="btn ghost" @click="openDoc('github')">GitHub 文档</button>
                </template>
              </template>
            </div>
          </div>
          <div class="panel-sep" aria-hidden="true">
            <span class="panel-sep-line" />
            <span class="panel-sep-core" />
            <span class="panel-sep-line" />
          </div>
        </div>

        <JobConsole
          :progress="progress"
          :logs="logs"
          :console-lines="consoleLines"
          :busy="busy"
        />
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
.filter-bar {
  display: flex;
  flex-wrap: wrap;
  gap: 0.45rem;
  margin: 0 0 0.65rem;
  flex: 0 0 auto;
  padding: 0.4rem 0.5rem;
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
  /* 去掉前置标签后进一步收窄列表 */
  grid-template-columns: minmax(10.5rem, 11.75rem) minmax(0, 1fr);
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
  display: grid;
  grid-template-columns: auto minmax(0, 1fr);
  align-items: stretch;
  column-gap: 0.5rem;
  padding: 0.55rem 0.45rem;
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
  display: flex;
  cursor: default;
  color: var(--muted);
  font-size: 0.85rem;
  justify-content: center;
  align-items: center;
  min-height: 2.75rem;
}
.dev-list li:not(.empty-row):not(.skel-row):not(.list-loading-hint):not(.list-loading-bar):hover {
  background: color-mix(in srgb, var(--accent) 10%, transparent);
}
.dev-list li.active {
  background: color-mix(in srgb, var(--accent) 16%, transparent);
  box-shadow:
    inset 3px 0 0 var(--accent),
    0 0 18px color-mix(in srgb, var(--glow) 55%, transparent);
}

/* —— 列表加载：骨架 + 旋转环 —— */
.dev-list--loading {
  position: relative;
}

.skel-row {
  pointer-events: none;
  cursor: default !important;
  opacity: 0.85;
}

.skel-logo {
  width: 2.35rem;
  aspect-ratio: 1;
  border-radius: 0.5rem;
  background: linear-gradient(
    110deg,
    color-mix(in srgb, var(--panel) 70%, var(--line)) 25%,
    color-mix(in srgb, var(--accent) 18%, var(--panel)) 45%,
    color-mix(in srgb, var(--panel) 70%, var(--line)) 65%
  );
  background-size: 200% 100%;
  animation: list-shimmer 1.35s ease-in-out infinite;
}

.skel-body {
  display: flex;
  flex-direction: column;
  justify-content: center;
  gap: 0.35rem;
  min-width: 0;
}

.skel-line {
  display: block;
  height: 0.55rem;
  border-radius: 999px;
  background: linear-gradient(
    110deg,
    color-mix(in srgb, var(--panel) 65%, var(--line)) 25%,
    color-mix(in srgb, var(--accent) 22%, var(--panel)) 50%,
    color-mix(in srgb, var(--panel) 65%, var(--line)) 75%
  );
  background-size: 200% 100%;
  animation: list-shimmer 1.35s ease-in-out infinite;
}

.skel-line--name {
  width: 72%;
}

.skel-line--meta {
  width: 42%;
  height: 0.42rem;
  animation-delay: 0.12s;
}

.list-loading-hint,
.list-loading-bar {
  display: flex !important;
  align-items: center;
  justify-content: center;
  gap: 0.55rem;
  cursor: default !important;
  pointer-events: none;
  color: var(--muted);
  font-size: 0.78rem;
  letter-spacing: 0.06em;
  font-family: var(--font-mono);
  min-height: 2.4rem;
  margin-top: 0.15rem;
}

.list-loading-bar {
  position: sticky;
  bottom: 0;
  margin-bottom: 0;
  padding: 0.45rem 0.5rem;
  border-radius: 0.45rem;
  background: color-mix(in srgb, var(--panel) 72%, transparent);
  border: 1px solid color-mix(in srgb, var(--accent) 22%, transparent);
  backdrop-filter: blur(10px);
  -webkit-backdrop-filter: blur(10px);
}

.list-spinner {
  width: 1.05rem;
  height: 1.05rem;
  border-radius: 50%;
  border: 2px solid color-mix(in srgb, var(--accent) 25%, transparent);
  border-top-color: var(--accent);
  box-shadow: 0 0 10px color-mix(in srgb, var(--glow) 50%, transparent);
  animation: list-spin 0.75s linear infinite;
}

.list-spinner--sm {
  width: 0.85rem;
  height: 0.85rem;
  border-width: 1.5px;
}

@keyframes list-shimmer {
  0% {
    background-position: 120% 0;
  }
  100% {
    background-position: -120% 0;
  }
}

@keyframes list-spin {
  to {
    transform: rotate(360deg);
  }
}

@media (prefers-reduced-motion: reduce) {
  .skel-logo,
  .skel-line,
  .list-spinner {
    animation: none;
  }
}
/**
 * Logo 正方形，高度 = 右侧「名称 + 版本」总高。
 */
.dev-list :deep(.tool-logo-wrap.md) {
  display: block;
  box-sizing: border-box;
  width: auto;
  height: 100%;
  min-height: 0;
  aspect-ratio: 1 / 1;
  justify-self: start;
}
.dev-list :deep(.tool-logo-wrap.md .tool-logo) {
  display: grid;
  place-items: center;
  width: 100%;
  height: 100%;
  font-size: clamp(0.8rem, 38%, 1.1rem);
  border-radius: 0.5rem;
}
.tool-body {
  min-width: 0;
  display: flex;
  flex-direction: column;
  justify-content: center;
  gap: 0;
  overflow: hidden;
}
.tool-name {
  display: block;
  font-weight: 700;
  font-size: 0.88rem;
  line-height: 1.2;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.tool-meta {
  display: flex;
  flex-wrap: nowrap;
  align-items: center;
  gap: 0.25rem;
  max-width: 100%;
  margin-top: 0.05rem;
}
.meta {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  box-sizing: border-box;
  height: 1.1rem;
  padding: 0 0.38rem;
  font-size: 0.65rem;
  font-weight: 650;
  letter-spacing: 0.02em;
  line-height: 1;
  border-radius: 0.3rem;
  border: 1px solid transparent;
  white-space: nowrap;
  max-width: 100%;
  vertical-align: middle;
}
.meta-status.status-installed {
  color: var(--ok);
  background: color-mix(in srgb, var(--ok) 14%, transparent);
  border-color: color-mix(in srgb, var(--ok) 28%, transparent);
  font-variant-numeric: tabular-nums;
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
/**
 * 右侧工具信息 + 操作一行（非固定吸顶；随面板内容排列）。
 * 标题+描述间距收紧，与 Logo 同高对齐；略增高以容纳描述。
 */
.detail-row {
  --detail-logo: 3.25rem;
  display: flex;
  align-items: stretch;
  justify-content: space-between;
  gap: 0.9rem 1.15rem;
  padding: 0.15rem 0 0.1rem;
}
.detail-head {
  display: flex;
  gap: 0.7rem;
  align-items: center;
  flex: 1 1 auto;
  min-width: 0;
}
.detail-head :deep(.tool-logo-wrap.md) {
  width: var(--detail-logo);
  height: var(--detail-logo);
}
.detail-head :deep(.tool-logo-wrap.md .tool-logo) {
  width: var(--detail-logo);
  height: var(--detail-logo);
  font-size: 1.05rem;
  border-radius: 0.6rem;
}
.detail-text {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  justify-content: center;
  gap: 0.12rem;
  min-height: var(--detail-logo);
}
.panel-title {
  margin: 0;
  font-family: var(--font-display);
  font-size: 0.92rem;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  line-height: 1.25;
}
.panel-desc {
  margin: 0;
  color: var(--muted);
  font-size: 0.82rem;
  line-height: 1.3;
}
.actions {
  display: flex;
  flex-wrap: wrap;
  justify-content: flex-end;
  align-items: center;
  gap: 0.5rem;
  flex: 0 0 auto;
  max-width: 100%;
}
/** 安装 / 更新 / 卸载：大按钮，高度贴齐左侧信息块 */
.actions--tall {
  align-items: stretch;
  align-self: stretch;
}
.actions--tall .action-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-height: 100%;
  min-width: 4.6rem;
  padding: 0.65rem 1.15rem;
  font-size: 0.95rem;
  font-weight: 700;
  letter-spacing: 0.04em;
  border-radius: 0.55rem;
}
.prereq-chip {
  display: inline-flex;
  align-items: center;
  align-self: center;
  height: 1.45rem;
  padding: 0 0.55rem;
  font-size: 0.72rem;
  font-weight: 700;
  letter-spacing: 0.04em;
  color: var(--warn);
  border: 1px dashed color-mix(in srgb, var(--warn) 55%, transparent);
  border-radius: 0.35rem;
  background: color-mix(in srgb, var(--warn) 10%, transparent);
  white-space: nowrap;
}
.actions--tall .prereq-chip {
  align-self: center;
}
/**
 * 顶栏与下方命令区的科幻分隔线。
 */
.panel-sep {
  display: flex;
  align-items: center;
  gap: 0.55rem;
  margin: 0.85rem 0 0.15rem;
  pointer-events: none;
}
.panel-sep-line {
  flex: 1;
  height: 1px;
  background: linear-gradient(
    90deg,
    transparent,
    color-mix(in srgb, var(--accent) 55%, transparent),
    color-mix(in srgb, var(--accent-2) 35%, transparent),
    transparent
  );
  box-shadow: 0 0 10px color-mix(in srgb, var(--glow) 50%, transparent);
}
.panel-sep-core {
  flex: 0 0 auto;
  width: 0.45rem;
  height: 0.45rem;
  border-radius: 0.08rem;
  transform: rotate(45deg);
  background: linear-gradient(135deg, var(--accent), var(--accent-2));
  box-shadow:
    0 0 12px var(--glow),
    inset 0 0 0 1px color-mix(in srgb, #fff 35%, transparent);
  animation: panel-sep-pulse 2.8s ease-in-out infinite;
}
@keyframes panel-sep-pulse {
  0%,
  100% {
    opacity: 0.75;
    box-shadow: 0 0 8px var(--glow);
  }
  50% {
    opacity: 1;
    box-shadow: 0 0 16px var(--glow);
  }
}
.panel-tip {
  margin: 0.35rem 0 0;
  padding: 0.4rem 0.6rem;
  border-radius: 0.45rem;
  font-size: 0.8rem;
  line-height: 1.35;
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
.job-panel :deep(.status-log) {
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
  .detail-row {
    flex-direction: column;
    align-items: stretch;
  }
  .actions {
    justify-content: flex-start;
  }
  .actions--tall .action-btn {
    min-height: 2.75rem;
  }
}
@media (prefers-reduced-motion: reduce) {
  .panel-sep-core {
    animation: none;
  }
}
</style>
