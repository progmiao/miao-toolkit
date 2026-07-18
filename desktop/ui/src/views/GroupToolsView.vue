<script setup lang="ts">
/**
 * 分组工具页：按 daily / dev 拉目录；generic 与 panel（Node）共用 Job 区。
 */
import { computed, onMounted, onUnmounted, ref, watch } from 'vue'
import { type CatalogItem, post, subscribe } from '../bridge/bus'

const props = defineProps<{
  /** 插件分组 id：daily | dev */
  group: string
  /** 页面标题 */
  title: string
  /** 副标题 */
  subtitle: string
}>()

const items = ref<CatalogItem[]>([])
const selected = ref<Record<string, boolean>>({})
const activeId = ref<string | null>(null)
const logs = ref<string[]>([])
const progress = ref(0)
const busy = ref(false)
const currentJob = ref<string | null>(null)

let unsubscribe: (() => void) | undefined

const selectedIds = computed(() =>
  items.value.filter((i) => selected.value[i.id]).map((i) => i.id),
)

const activeItem = computed(
  () => items.value.find((i) => i.id === activeId.value) ?? null,
)

function statusLabel(status: string): string {
  switch (status) {
    case 'installed':
      return '已安装'
    case 'missing':
      return '未安装'
    default:
      return '未知'
  }
}

function appendLog(line: string) {
  logs.value.push(line)
  if (logs.value.length > 500) logs.value.shift()
}

function requestCatalog() {
  post({ type: 'get-catalog', group: props.group })
}

onMounted(() => {
  unsubscribe = subscribe((msg) => {
    if (msg.type === 'catalog' && msg.items) {
      if (msg.group && msg.group !== props.group) return
      items.value = msg.items
      for (const it of msg.items) {
        if (selected.value[it.id] === undefined) selected.value[it.id] = false
      }
      if (!activeId.value && msg.items[0]) activeId.value = msg.items[0].id
    }
    if (msg.type === 'job-started') {
      busy.value = true
      currentJob.value = msg.jobId ?? null
      progress.value = 0
      appendLog(`—— 开始任务 ${msg.jobId} ——`)
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
      requestCatalog()
    }
    if (msg.type === 'error' && msg.message) {
      appendLog(`[错误] ${msg.message}`)
      busy.value = false
    }
  })
  requestCatalog()
})

watch(
  () => props.group,
  () => {
    items.value = []
    activeId.value = null
    requestCatalog()
  },
)

onUnmounted(() => unsubscribe?.())

function toggleAll(on: boolean) {
  for (const it of items.value) selected.value[it.id] = on
}

function runAction(action: string, ids?: string[]) {
  const list = ids ?? selectedIds.value
  if (!list.length) {
    appendLog('请先勾选工具')
    return
  }
  for (const id of list) {
    const jobId = crypto.randomUUID().replaceAll('-', '')
    post({ type: 'run-job', jobId, toolId: id, action })
  }
}

function runInstall() {
  runAction('install')
}

function runUninstall() {
  runAction('uninstall')
}

function cancel() {
  if (currentJob.value) post({ type: 'cancel-job', jobId: currentJob.value })
}

function selectRow(it: CatalogItem) {
  activeId.value = it.id
}
</script>

<template>
  <section class="page">
    <header class="page-head row">
      <div>
        <h1>{{ title }}</h1>
        <p>{{ subtitle }}</p>
      </div>
      <div class="actions">
        <button type="button" class="btn secondary" @click="toggleAll(true)">全选</button>
        <button type="button" class="btn secondary" @click="toggleAll(false)">清空</button>
        <button type="button" class="btn" :disabled="busy" @click="runInstall">安装所选</button>
        <button type="button" class="btn secondary" :disabled="busy" @click="runUninstall">
          卸载所选
        </button>
        <button type="button" class="btn danger" :disabled="!busy" @click="cancel">取消</button>
      </div>
    </header>

    <div class="toolbox-layout">
      <ul class="tool-list">
        <li
          v-for="it in items"
          :key="it.id"
          :class="{ active: activeId === it.id }"
          @click="selectRow(it)"
        >
          <label @click.stop>
            <input v-model="selected[it.id]" type="checkbox" />
            <span class="tool-name">{{ it.name }}</span>
            <span class="tool-desc">{{ it.description }}</span>
            <span class="tool-meta">
              <span class="tag" :class="'status-' + it.status">
                {{ statusLabel(it.status) }}
                <template v-if="it.version"> · v{{ it.version }}</template>
              </span>
              <span v-if="it.uiMode === 'panel'" class="tag">面板</span>
            </span>
          </label>
        </li>
      </ul>

      <aside class="job-panel">
        <div v-if="activeItem?.uiMode === 'panel' && activeItem.id === 'node'" class="panel-box">
          <h2 class="panel-title">{{ activeItem.name }}</h2>
          <p class="panel-hint">经 Volta 安装 Node LTS；更多版本/pin 能力后续扩展。</p>
          <button
            type="button"
            class="btn"
            :disabled="busy"
            @click="runAction('install', [activeItem.id])"
          >
            安装 Node（LTS）
          </button>
        </div>
        <div v-else-if="activeItem" class="panel-box">
          <h2 class="panel-title">{{ activeItem.name }}</h2>
          <p class="panel-hint">{{ activeItem.description }}</p>
          <div class="actions">
            <button
              v-if="activeItem.actions.includes('install')"
              type="button"
              class="btn"
              :disabled="busy"
              @click="runAction('install', [activeItem.id])"
            >
              安装
            </button>
            <button
              v-if="activeItem.actions.includes('uninstall')"
              type="button"
              class="btn secondary"
              :disabled="busy"
              @click="runAction('uninstall', [activeItem.id])"
            >
              卸载
            </button>
          </div>
        </div>

        <div class="progress-wrap">
          <div class="progress-label">进度 {{ progress }}%</div>
          <div class="progress-bar">
            <i :style="{ width: progress + '%' }" />
          </div>
        </div>
        <pre class="log">{{ logs.join('\n') || '等待任务…' }}</pre>
      </aside>
    </div>
  </section>
</template>

<style scoped>
.tool-list li.active {
  background: color-mix(in srgb, var(--accent) 12%, transparent);
}
.panel-box {
  margin-bottom: 0.75rem;
}
.panel-title {
  margin: 0 0 0.35rem;
  font-size: 1.05rem;
}
.panel-hint {
  margin: 0 0 0.75rem;
  color: var(--muted);
  font-size: 0.85rem;
}
</style>
