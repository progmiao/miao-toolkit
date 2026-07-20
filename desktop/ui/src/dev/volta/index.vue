<script setup lang="ts">
/**
 * 开发工具 · Volta 独立页（入口 index.vue）。
 * 安装 / 更新 / 卸载 Volta 本体（WinGet）；Node / pnpm / Yarn 各自有独立管理页。
 * Host：generic.winget；种子：seeds/dev/volta/software.json
 */
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { RouterLink } from 'vue-router'
import JobConsole from '@kernel/components/JobConsole.vue'
import ToolLogo from '@kernel/catalog/ToolLogo.vue'
import { catalogStatusClass, catalogStatusLabel } from '@kernel/catalog/statusMeta'
import {
  showInstallAction,
  showUninstallAction,
  showUpdateAction,
} from '@kernel/catalog/toolMeta'
import { type CatalogItem, post, subscribe } from '@kernel/bridge/bus'
import { confirmDialog } from '@kernel/bridge/confirm'
import { useJobConsole } from '@kernel/composables/useJobConsole'
import { useShellTitle } from '@kernel/composables/useShellTitle'

/** 本页固定工具 id。 */
const TOOL_ID = 'volta'

useShellTitle('Volta')

const item = ref<CatalogItem | null>(null)
const loading = ref(true)

const {
  logs,
  consoleLines,
  progress,
  busy,
  consumeJobMessage,
  cancel,
} = useJobConsole({
  onFinished: () => requestStatus(),
  formatStarted: (msg) => `开始：${msg.action ?? '任务'}`,
})

const statusText = computed(() =>
  item.value ? catalogStatusLabel(item.value) : '…',
)
const statusClass = computed(() =>
  item.value ? catalogStatusClass(item.value) : 'status-unknown',
)

let unsub: (() => void) | undefined

/** 拉取目录中的 Volta 项以刷新安装状态。 */
function requestStatus() {
  loading.value = true
  post({ type: 'get-catalog', group: 'dev' })
}

onMounted(() => {
  unsub = subscribe((msg) => {
    if (msg.type === 'catalog' && msg.items) {
      if (msg.group && msg.group !== 'dev') return
      const list = msg.items as CatalogItem[]
      item.value = list.find((i) => i.id === TOOL_ID) ?? null
      loading.value = false
      return
    }
    consumeJobMessage(msg)
  })
  requestStatus()
})

onUnmounted(() => unsub?.())

/**
 * 执行安装 / 更新 / 卸载。
 * @param action - install | uninstall（更新也走 install）
 */
async function run(action: string) {
  if (action === 'uninstall') {
    const ok = await confirmDialog({
      title: '卸载确认',
      message:
        '确认卸载 Volta？卸载后 Node / pnpm / Yarn 将无法通过 Volta 管理。',
      confirmText: '卸载',
      cancelText: '取消',
      tone: 'danger',
    })
    if (!ok) return
  }
  const jobId = crypto.randomUUID().replaceAll('-', '')
  post({ type: 'run-job', jobId, toolId: TOOL_ID, action })
}
</script>

<template>
  <section class="page page--scroll volta-page">
    <header class="page-head row">
      <div>
        <p class="crumb">
          <RouterLink to="/dev">开发工具</RouterLink>
          <span>/</span>
          <span>Volta</span>
        </p>
        <p>JavaScript 工具链版本管理器；Node / pnpm / Yarn 的前置依赖。</p>
      </div>
      <div class="actions">
        <button type="button" class="btn secondary" :disabled="loading || busy" @click="requestStatus">
          刷新状态
        </button>
        <button type="button" class="btn danger" :disabled="!busy" @click="cancel">取消任务</button>
      </div>
    </header>

    <div class="volta-layout">
      <div class="info-panel hud-panel">
        <div class="info-head">
          <ToolLogo
            tool-id="volta"
            name="Volta"
            size="lg"
            :update-available="Boolean(item?.updateAvailable)"
          />
          <div>
            <h2 class="info-title">Volta</h2>
            <p class="info-status" :class="statusClass">
              {{ loading ? '检测中…' : statusText }}
            </p>
            <p v-if="item?.version && item.status === 'installed'" class="info-ver mono">
              {{ item.version }}
            </p>
          </div>
        </div>

        <p class="info-desc">
          通过 WinGet 安装 Volta 本体。安装完成后，可在各自页面管理 Node、Pnpm、Yarn 多版本。
        </p>

        <div class="info-actions">
          <button
            v-if="item && showInstallAction(item)"
            type="button"
            class="btn"
            :disabled="busy || !item"
            @click="run('install')"
          >
            安装
          </button>
          <button
            v-if="item && showUpdateAction(item)"
            type="button"
            class="btn"
            :disabled="busy || !item"
            @click="run('install')"
          >
            更新
          </button>
          <button
            v-if="item && showUninstallAction(item)"
            type="button"
            class="btn secondary"
            :disabled="busy || !item"
            @click="run('uninstall')"
          >
            卸载
          </button>
        </div>

        <div class="related">
          <span class="related-label">相关工具</span>
          <RouterLink class="btn ghost mini" to="/dev/node">Node.js</RouterLink>
          <RouterLink class="btn ghost mini" to="/dev/pnpm">Pnpm</RouterLink>
          <RouterLink class="btn ghost mini" to="/dev/yarn">Yarn</RouterLink>
        </div>
      </div>

      <aside class="job-panel">
        <JobConsole
          :progress="progress"
          :logs="logs"
          :console-lines="consoleLines"
          :busy="busy"
          placeholder="安装或卸载 Volta 时，输出显示在此…"
        />
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
.volta-layout {
  display: grid;
  grid-template-columns: 1.05fr 0.95fr;
  gap: 1rem;
  min-height: 420px;
}
.info-panel {
  display: flex;
  flex-direction: column;
  gap: 1rem;
  padding: 1.1rem 1.15rem;
}
.info-head {
  display: flex;
  align-items: center;
  gap: 0.85rem;
}
.info-title {
  margin: 0;
  font-size: 1.25rem;
}
.info-status {
  margin: 0.25rem 0 0;
  font-size: 0.9rem;
}
.info-ver {
  margin: 0.15rem 0 0;
  font-size: 0.85rem;
  color: var(--muted);
}
.info-desc {
  margin: 0;
  color: var(--muted);
  font-size: 0.92rem;
  line-height: 1.5;
}
.info-actions {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
}
.related {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.45rem;
  margin-top: auto;
  padding-top: 0.75rem;
  border-top: 1px solid var(--line);
}
.related-label {
  font-size: 0.8rem;
  color: var(--muted);
  margin-right: 0.25rem;
}
.btn.mini {
  padding: 0.25rem 0.55rem;
  font-size: 0.8rem;
}
.mono {
  font-family: var(--font-mono);
}
@media (max-width: 900px) {
  .volta-layout {
    grid-template-columns: 1fr;
  }
}
</style>
