<script setup lang="ts">
/**
 * 开发工具一级页：左侧列表 + 右侧「工具概览 + 工具工作区 + JobConsole」。
 * panel 工具不再跳二级路由，内容嵌在 tool-workspace。
 */
import {
  computed,
  defineAsyncComponent,
  nextTick,
  onMounted,
  onUnmounted,
  provide,
  ref,
  watch,
  type Component,
} from 'vue'
import { useRoute, useRouter } from 'vue-router'
import JobConsole from '@kernel/components/JobConsole.vue'
import ToolLogo from '@kernel/catalog/ToolLogo.vue'
import { catalogStatusClass, catalogStatusLabel } from '@kernel/catalog/statusMeta'
import { type CatalogItem, post, subscribe } from '@kernel/bridge/bus'
import { confirmDialog } from '@kernel/bridge/confirm'
import { setForegroundJobBusy } from '@kernel/bridge/foregroundJob'
import RegionLock from '@kernel/components/RegionLock.vue'
import { useJobConsole } from '@kernel/composables/useJobConsole'
import { useShellTitle } from '@kernel/composables/useShellTitle'
import {
  buildTagFilters,
  isBlockedByNodePrereq,
  showInstallAction,
  showUninstallAction,
  showUpdateAction,
} from '@kernel/catalog/toolMeta'
import {
  DEV_JOB_KEY,
  DEV_OVERVIEW_EXTRA_KEY,
  DEV_SELECT_TOOL_KEY,
  DEV_WORKSPACE_OWNS_CONSOLE_KEY,
  type DevOverviewExtra,
} from './devPanelContext'

useShellTitle('开发工具')

const route = useRoute()
const router = useRouter()

const items = ref<CatalogItem[]>([])
const tagFilter = ref('all')
const activeId = ref<string | null>(null)
/** 工具列表是否正在向宿主拉取目录（首屏与刷新）。 */
const listLoading = ref(true)
/** 工具列表 DOM，用于按可视高度计算骨架行数。 */
const listEl = ref<HTMLElement | null>(null)
/** 骨架行数：与列表可视区可容纳的真实行数一致。 */
const skeletonRows = ref(6)

let listResizeObs: ResizeObserver | undefined

/** 按列表高度 / 实测行高，算出可完整放下的骨架条数。 */
function recalcSkeletonRows() {
  const el = listEl.value
  if (!el) return
  const styles = getComputedStyle(el)
  const padY =
    (Number.parseFloat(styles.paddingTop) || 0) + (Number.parseFloat(styles.paddingBottom) || 0)
  const available = Math.max(0, el.clientHeight - padY)
  const sample = el.querySelector('.skel-row, li:not(.empty-row)') as HTMLElement | null
  let rowH = Number.parseFloat(styles.getPropertyValue('--tool-row-h')) || 56
  if (sample) {
    const ms = getComputedStyle(sample)
    rowH = sample.offsetHeight + (Number.parseFloat(ms.marginBottom) || 0)
  }
  if (rowH <= 0) return
  skeletonRows.value = Math.max(1, Math.floor(available / rowH))
}

const jobApi = useJobConsole({
  onFinished: () => requestCatalog(),
  onError: () => {
    if (listLoading.value) listLoading.value = false
  },
  formatStarted: (msg) => `开始：${msg.action ?? '任务'}（${msg.toolId ?? ''}）`,
  formatFinished: (msg) =>
    msg.ok ? `完成（exit ${msg.exitCode}）` : `失败：${msg.detail ?? ''}`,
})

const {
  outputEntries,
  progress,
  statusText,
  busy,
  consumeJobMessage,
  resetWhenIdle,
  cancel,
} = jobApi

provide(DEV_JOB_KEY, jobApi)

const overviewExtra = ref<DevOverviewExtra | null>(null)
const workspaceOwnsConsole = ref(false)
provide(DEV_OVERVIEW_EXTRA_KEY, overviewExtra)
provide(DEV_WORKSPACE_OWNS_CONSOLE_KEY, workspaceOwnsConsole)

watch(
  busy,
  (on) => setForegroundJobBusy(on),
  { immediate: true },
)

watch(activeId, () => {
  overviewExtra.value = null
  workspaceOwnsConsole.value = false
  resetWhenIdle()
})

/** seeds `ui.entry` → 嵌入工作区组件（仅正文，无二级页壳）。 */
const panelLoaders: Record<string, () => Promise<Component>> = {
  volta: () => import('./volta/index.vue'),
  node: () => import('./node/index.vue'),
  pnpm: () => import('./pnpm/index.vue'),
  yarn: () => import('./yarn/index.vue'),
  claude: () => import('./claude/index.vue'),
  terminalBuddy: () => import('./terminalBuddy/index.vue'),
  ccSwitch: () => import('./ccSwitch/index.vue'),
  ccConnect: () => import('./ccConnect/index.vue'),
  hermes: () => import('./hermes/index.vue'),
}

const panelComponents: Record<string, Component> = Object.fromEntries(
  Object.entries(panelLoaders).map(([k, loader]) => [k, defineAsyncComponent(loader)]),
)

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

/** 当前工具被 Node 18+ 闸门挡住（CC Switch / CC Connect）。 */
const nodePrereqBlocked = computed(() =>
  isBlockedByNodePrereq(activeItem.value, items.value),
)

/**
 * 当前选中工具的工作区入口（seeds ui.entry）；无则仅显示 JobConsole。
 */
const workspaceEntry = computed(() => {
  const it = activeItem.value
  if (!it || it.uiMode !== 'panel') return null
  const entry = (it.uiEntry ?? '').trim()
  return entry && panelComponents[entry] ? entry : null
})

const workspaceComponent = computed(() =>
  workspaceEntry.value ? panelComponents[workspaceEntry.value!] : null,
)

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
 * 按工具 id 选中列表项（供工作区内「相关工具」调用）。
 * @param toolId - 目录 id
 */
function selectToolById(toolId: string) {
  if (busy.value) return
  if (!items.value.some((i) => i.id === toolId)) return
  activeId.value = toolId
  void router.replace({ path: '/dev', query: { tool: toolId } })
}

provide(DEV_SELECT_TOOL_KEY, selectToolById)

/**
 * 选中列表项：只切换右侧概览/工作区，不跳二级页。
 * @param it - 目录项
 */
function selectRow(it: CatalogItem) {
  selectToolById(it.id)
}

/**
 * 向宿主请求开发工具目录；进入加载态直至收到 `catalog`。
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
      // 任务进行中禁止因目录刷新切换选中工具
      if (busy.value) return
      const q = typeof route.query.tool === 'string' ? route.query.tool : ''
      if (q && items.value.some((i) => i.id === q)) {
        activeId.value = q
      } else if (!activeId.value && items.value[0]) {
        activeId.value = items.value[0].id
      } else if (activeId.value && !items.value.some((i) => i.id === activeId.value)) {
        activeId.value = items.value[0]?.id ?? null
      }
      return
    }
    consumeJobMessage(msg)
  })
  requestCatalog()
  void nextTick(() => {
    if (!listEl.value) return
    recalcSkeletonRows()
    listResizeObs = new ResizeObserver(() => recalcSkeletonRows())
    listResizeObs.observe(listEl.value)
  })
})

onUnmounted(() => {
  unsub?.()
  listResizeObs?.disconnect()
  listResizeObs = undefined
  setForegroundJobBusy(false)
})

watch(listLoading, (loading) => {
  if (loading && !items.value.length) {
    void nextTick(() => recalcSkeletonRows())
  }
})

watch(filtered, (list) => {
  if (busy.value) return
  if (!list.length) return
  if (!list.some((i) => i.id === activeId.value)) activeId.value = list[0].id
})

/**
 * 概览安装 / 更新 / 卸载。更新与卸载均二次确认；宿主更新仍走 install。
 * @param action - install | update | uninstall（update 仅 UI 语义，下发为 install）
 */
async function runAction(action: string, id: string) {
  if (busy.value) return
  const item = items.value.find((i) => i.id === id)
  const name = item?.name ?? id
  const hostAction = action === 'update' ? 'install' : action

  if (
    (action === 'install' || action === 'update') &&
    isBlockedByNodePrereq(item, items.value)
  ) {
    return
  }

  if (action === 'update') {
    const ok = await confirmDialog({
      title: '更新确认',
      message: `确认更新 ${name}？`,
      confirmText: '更新',
      cancelText: '取消',
    })
    if (!ok) return
  } else if (action === 'uninstall') {
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
  post({ type: 'run-job', jobId, toolId: id, action: hostAction })
}
</script>

<template>
  <section class="page dev-page">
    <RegionLock :active="busy" title="任务进行中，请先终止">
      <nav class="filter-bar filter-bar--compact" aria-label="分类过滤">
        <button
          v-for="f in filters"
          :key="f.id"
          type="button"
          class="filter-chip"
          :class="{ active: tagFilter === f.id }"
          :tabindex="busy ? -1 : undefined"
          @click="tagFilter = f.id"
        >
          {{ f.label }}
        </button>
      </nav>
    </RegionLock>

    <div class="dev-layout">
      <RegionLock class="dev-list-lock" :active="busy" title="任务进行中，请先终止">
        <ul
          ref="listEl"
          class="dev-list panel-frost"
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
          </template>
          <template v-else>
            <li
              v-for="it in filtered"
              :key="it.id"
              class="side-nav-item"
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
                <span class="tool-name" :title="it.name">{{ it.name }}</span>
                <div class="tool-meta">
                  <span class="meta meta-status" :class="catalogStatusClass(it)">{{ catalogStatusLabel(it) }}</span>
                </div>
              </div>
            </li>
            <li v-if="!listLoading && !filtered.length" class="empty-row">该分类下暂无工具</li>
          </template>
        </ul>
      </RegionLock>

      <aside class="job-panel panel-frost" :class="{ 'job-panel--fill': workspaceOwnsConsole }">
        <div v-if="activeItem" class="panel-box">
          <!-- 工具概览：Logo + 名称 + 说明 + 安装/更新/卸载 -->
          <div class="tool-overview" aria-label="工具概览">
            <div class="tool-overview-main">
              <ToolLogo
                :tool-id="activeItem.id"
                :name="activeItem.name"
                size="md"
                :update-available="Boolean(activeItem.updateAvailable)"
              />
              <div class="tool-overview-text">
                <h2 class="panel-title">
                  {{ activeItem.name }}
                  <span class="panel-title-meta">
                    <template v-if="activeItem.status === 'installed'">
                      <template v-if="activeItem.version"> · 已安装 {{ activeItem.version }}</template>
                      <template v-else> · 已安装</template>
                      <span
                        v-if="activeItem.updateAvailable"
                        class="panel-title-update"
                      >
                        <template v-if="activeItem.latestVersion">
                          · 可更新 {{ activeItem.latestVersion }}
                        </template>
                        <template v-else> · 有更新</template>
                      </span>
                    </template>
                    <template v-else-if="activeItem.status === 'missing'"> · 未安装</template>
                  </span>
                </h2>
                <p v-if="activeItem.description" class="panel-desc">{{ activeItem.description }}</p>
                <p v-if="featureTip" class="panel-tip tip-feature">{{ featureTip }}</p>
                <p v-if="nodePrereqBlocked" class="prereq-banner-inline">
                  <span>缺少前置：Node.js 18+</span>
                  <button
                    type="button"
                    class="btn secondary prereq-go"
                    :disabled="busy"
                    @click="selectToolById('node')"
                  >
                    前往 Node.js
                  </button>
                </p>
              </div>
            </div>

            <div class="tool-overview-actions actions--tall">
              <RegionLock
                class="overview-actions-lock"
                :active="busy"
                title="任务进行中，请先终止"
              >
                <div class="overview-actions-group">
                  <button
                    v-if="showInstallAction(activeItem)"
                    type="button"
                    class="btn btn-overview"
                    :disabled="busy || nodePrereqBlocked"
                    :title="nodePrereqBlocked ? '请先安装 Node.js 18+' : undefined"
                    @click="runAction('install', activeItem.id)"
                  >
                    安装
                  </button>
                  <button
                    v-if="showUpdateAction(activeItem)"
                    type="button"
                    class="btn btn-overview"
                    :disabled="busy || nodePrereqBlocked"
                    :title="nodePrereqBlocked ? '请先安装 Node.js 18+' : undefined"
                    @click="runAction('update', activeItem.id)"
                  >
                    更新
                  </button>
                  <button
                    v-if="showUninstallAction(activeItem)"
                    type="button"
                    class="btn secondary btn-overview"
                    :disabled="busy"
                    @click="runAction('uninstall', activeItem.id)"
                  >
                    卸载
                  </button>
                  <button
                    v-if="overviewExtra?.refresh"
                    type="button"
                    class="btn secondary btn-overview"
                    :disabled="busy || overviewExtra.refreshing"
                    @click="overviewExtra.refresh?.()"
                  >
                    {{ overviewExtra.refreshLabel || '刷新清单' }}
                  </button>
                </div>
              </RegionLock>
              <button
                type="button"
                class="btn danger btn-overview"
                :disabled="!busy"
                title="终止当前任务"
                @click="cancel"
              >
                终止
              </button>
            </div>
          </div>

          <div class="panel-sep" aria-hidden="true">
            <span class="panel-sep-line" />
            <span class="panel-sep-core" />
            <span class="panel-sep-line" />
          </div>
        </div>

        <!-- 工具工作区：自带命令窗的 panel（如 Node）自行片区锁定；其余整块锁定 -->
        <RegionLock
          v-if="workspaceComponent"
          class="tool-workspace"
          :active="busy && !workspaceOwnsConsole"
          title="任务进行中，请先终止"
          aria-label="工具工作区"
        >
          <component :is="workspaceComponent" embedded />
        </RegionLock>

        <JobConsole
          v-if="!workspaceOwnsConsole"
          :progress="progress"
          :status-text="statusText"
          :entries="outputEntries"
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
.dev-layout {
  flex: 1;
  min-height: 0;
  display: grid;
  /* 名称过长省略；列宽够显示常见短名即可 */
  grid-template-columns: minmax(9.25rem, 10.25rem) minmax(0, 1fr);
  /* 列表与右侧间距 = 列表内图标左侧留白 */
  gap: 0.5rem;
  align-items: stretch;
}

.dev-list-lock {
  min-height: 0;
  height: 100%;
  display: flex;
  flex-direction: column;
}

.dev-list {
  /* 仅供骨架条数估算；真实行高由内容自然撑开 */
  --tool-row-h: 3.55rem;
  list-style: none;
  margin: 0;
  padding: 0.45rem 0.4rem;
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
  box-sizing: border-box;
  padding: 0.55rem 0.4rem;
  margin-bottom: 0.25rem;
  border-radius: 0.55rem;
  cursor: pointer;
  min-width: 0;
  max-width: 100%;
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

/* —— 列表加载：骨架与真实行同结构/同内边距 —— */
.dev-list--loading {
  position: relative;
}

.skel-row {
  pointer-events: none;
  cursor: default !important;
  opacity: 0.85;
  align-items: center;
}

.skel-logo {
  width: 2.35rem;
  aspect-ratio: 1;
  flex: 0 0 auto;
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

@keyframes list-shimmer {
  0% {
    background-position: 120% 0;
  }
  100% {
    background-position: -120% 0;
  }
}

@media (prefers-reduced-motion: reduce) {
  .skel-logo,
  .skel-line {
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
  max-width: 100%;
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
/* 状态 .meta 见 styles/status.css */
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
/** 工作区自带控制台时：整栏跟窗高，不由右侧整体出滚动条 */
.job-panel--fill {
  overflow: hidden;
}
.tool-workspace {
  flex: 0 1 auto;
  min-height: 0;
  min-width: 0;
}
.job-panel--fill .tool-workspace {
  flex: 1 1 auto;
  display: flex;
  flex-direction: column;
  overflow: hidden;
}
.job-panel--fill .tool-workspace > * {
  flex: 1 1 auto;
  min-height: 0;
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
 * 工具概览（tool-overview）：Logo + 名称 + 说明 + 安装/更新/卸载。
 * 下方「工具工作区」以 panel-sep 分隔。
 */
.tool-overview {
  --overview-logo: 3.25rem;
  display: flex;
  align-items: stretch;
  justify-content: space-between;
  gap: 0.9rem 1.15rem;
  padding: 0.15rem 0 0.1rem;
}
.tool-overview-main {
  display: flex;
  gap: 0.7rem;
  align-items: center;
  flex: 1 1 auto;
  min-width: 0;
}
.tool-overview-main :deep(.tool-logo-wrap.md) {
  width: var(--overview-logo);
  height: var(--overview-logo);
}
.tool-overview-main :deep(.tool-logo-wrap.md .tool-logo) {
  width: var(--overview-logo);
  height: var(--overview-logo);
  font-size: 1.05rem;
  border-radius: 0.6rem;
}
.tool-overview-text {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  justify-content: center;
  gap: 0.12rem;
  min-height: var(--overview-logo);
}
.panel-title {
  margin: 0;
  font-family: var(--font-display);
  font-size: 0.92rem;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  line-height: 1.25;
}
.panel-title-meta {
  font-family: var(--font-mono);
  font-size: 0.78rem;
  font-weight: 550;
  letter-spacing: 0.02em;
  text-transform: none;
  color: var(--muted);
}
.panel-title-update {
  color: var(--accent);
  font-weight: 700;
}
.panel-desc {
  margin: 0;
  color: var(--muted);
  font-size: 0.82rem;
  line-height: 1.3;
}
.tool-overview-actions {
  display: flex;
  flex-wrap: wrap;
  justify-content: flex-end;
  align-items: center;
  gap: 0.5rem;
  flex: 0 0 auto;
  max-width: 100%;
}

.overview-actions-lock {
  display: flex;
  flex-wrap: wrap;
  justify-content: flex-end;
  align-items: stretch;
  gap: 0.5rem;
  min-width: 0;
}

.overview-actions-group {
  display: flex;
  flex-wrap: wrap;
  justify-content: flex-end;
  align-items: stretch;
  gap: 0.5rem;
}
/** 安装 / 更新 / 卸载 / 终止：高度贴齐左侧信息块（尺寸见 buttons.css .btn-overview） */
.actions--tall {
  align-items: stretch;
  align-self: stretch;
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
  .tool-overview {
    flex-direction: column;
    align-items: stretch;
  }
  .tool-overview-actions {
    justify-content: flex-start;
  }
  .actions--tall .btn-overview {
    min-height: 2.75rem;
  }
}
@media (prefers-reduced-motion: reduce) {
  .panel-sep-core {
    animation: none;
  }
}
</style>
