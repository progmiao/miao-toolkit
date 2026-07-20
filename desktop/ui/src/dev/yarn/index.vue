<script setup lang="ts">
/**
 * 开发工具 · Yarn 独立页（入口 index.vue）。
 * 经 Volta 管理多版本；与 Pnpm / Node 页面互不共用模板，仅复用 JobConsole 与 composable。
 * Host：Miao.Software/Dev/Volta；种子：seeds/dev/yarn/software.json
 */
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { RouterLink } from 'vue-router'
import JobConsole from '@kernel/components/JobConsole.vue'
import { post, subscribe } from '@kernel/bridge/bus'
import { showToast } from '@kernel/bridge/toast'
import { useJobConsole } from '@kernel/composables/useJobConsole'
import { useShellTitle } from '@kernel/composables/useShellTitle'
import { useVoltaVersions } from '@kernel/composables/useVoltaVersions'

/** 本页固定工具 id（勿与其它包页混用）。 */
const TOOL_ID = 'yarn'
const PAGE_TITLE = 'Yarn'

useShellTitle(PAGE_TITLE)

const {
  selected,
  filter,
  loading,
  error,
  conflicts,
  voltaAvailable,
  filteredByQuery,
  requestList,
  consumeVersionsMessage,
  toggleAll,
  setError,
} = useVoltaVersions({ toolId: TOOL_ID, ltsOnlyDefault: false })

const {
  logs,
  consoleLines,
  progress,
  busy,
  appendStatus,
  consumeJobMessage,
  cancel,
} = useJobConsole({
  onFinished: () => requestList(),
  onError: (message) => setError(message),
  formatStarted: (msg) => `开始：${msg.action ?? 'job'}`,
})

const projectPath = ref('')
const pendingPinVersion = ref<string | null>(null)

const selectedList = computed(() =>
  filteredByQuery.value.filter((v) => selected.value[v.version]).map((v) => v.version),
)

let unsub: (() => void) | undefined

onMounted(() => {
  unsub = subscribe((msg) => {
    if (consumeVersionsMessage(msg)) return
    if (msg.type === 'dialog.folder' && pendingPinVersion.value) {
      if (msg.path) {
        projectPath.value = String(msg.path)
        run('pin', [pendingPinVersion.value], { projectPath: projectPath.value })
      } else {
        appendStatus('已取消选择项目目录')
      }
      pendingPinVersion.value = null
      return
    }
    consumeJobMessage(msg)
  })
  requestList()
})

onUnmounted(() => unsub?.())

/**
 * 发起 Yarn 相关 Job。
 * @param action - install | uninstall | set-default | pin
 * @param versionsArg - 版本列表；缺省用多选
 * @param extra - 额外字段（如 projectPath）
 */
function run(action: string, versionsArg?: string[], extra?: Record<string, string>) {
  const list = versionsArg ?? selectedList.value
  if (!list.length && action !== 'pin') {
    showToast('请先勾选版本', { kind: 'warn' })
    return
  }
  const jobId = crypto.randomUUID().replaceAll('-', '')
  post({
    type: 'run-job',
    jobId,
    toolId: TOOL_ID,
    action,
    versions: list,
    ...extra,
  })
}

/**
 * 选择项目目录后 pin 指定版本。
 * @param ver - 版本号
 */
function pinOne(ver: string) {
  pendingPinVersion.value = ver
  post({ type: 'dialog.pick-folder' })
}

/** 安装 Volta 工具本体（非 yarn 包版本）。 */
function installVoltaTool() {
  const jobId = crypto.randomUUID().replaceAll('-', '')
  post({ type: 'run-job', jobId, toolId: 'volta', action: 'install' })
}
</script>

<template>
  <section class="page page--scroll yarn-page">
    <header class="page-head row">
      <div>
        <p class="crumb">
          <RouterLink to="/dev">开发工具</RouterLink>
          <span>/</span>
          <span>{{ PAGE_TITLE }}</span>
        </p>
        <p>经 Volta 管理 Yarn 多版本：浏览远程清单、批量安装 / 卸载、设默认、pin 到项目。</p>
      </div>
      <div class="actions">
        <button type="button" class="btn secondary" :disabled="loading || busy" @click="requestList()">
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

    <div v-if="voltaAvailable" class="pkg-layout">
      <div class="ver-panel hud-panel">
        <div class="ver-toolbar">
          <input v-model="filter" class="search" type="search" placeholder="过滤版本…" />
          <button type="button" class="btn ghost" @click="toggleAll(filteredByQuery, true)">全选</button>
          <button type="button" class="btn ghost" @click="toggleAll(filteredByQuery, false)">清空</button>
          <span class="hint">{{ loading ? '同步中…' : `${filteredByQuery.length} 项` }}</span>
        </div>
        <ul class="ver-list">
          <li v-for="v in filteredByQuery" :key="v.version">
            <label>
              <input v-model="selected[v.version]" type="checkbox" />
              <span class="ver-num">{{ v.version }}</span>
              <span v-if="v.lts" class="tag">{{ v.lts }}</span>
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
          <li v-if="!filteredByQuery.length && !loading" class="empty-hint">无匹配版本</li>
        </ul>
      </div>

      <aside class="job-panel">
        <JobConsole
          :progress="progress"
          :logs="logs"
          :console-lines="consoleLines"
          :busy="busy"
          placeholder="选择版本后执行操作…"
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
.pkg-layout {
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
  .pkg-layout {
    grid-template-columns: 1fr;
  }
}
</style>
