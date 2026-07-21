<script setup lang="ts">
/**
 * 底栏静默任务：单行摘要 + 图标角标；点击弹出进行中 / 最近完成列表。
 */
import { computed, onMounted, onUnmounted, ref } from 'vue'
import {
  cancelSilentTask,
  pickActiveTask,
  requestSilentList,
  subscribeSilentTasks,
  type SilentTask,
  type SilentQueueSnapshot,
} from '@kernel/bridge/silentTasks'
import './SilentTasksPanel.css'

const snap = ref<SilentQueueSnapshot>({
  activeCount: 0,
  totalQueued: 0,
  tasks: [],
})
const open = ref(false)
const rootEl = ref<HTMLElement | null>(null)

let unsub: (() => void) | undefined

const active = computed(() => pickActiveTask(snap.value.tasks))
const badge = computed(() => snap.value.activeCount)

const activeTasks = computed(() =>
  snap.value.tasks.filter((t) => t.status === 'pending' || t.status === 'running'),
)
const recentTasks = computed(() =>
  snap.value.tasks.filter(
    (t) => t.status === 'succeeded' || t.status === 'failed' || t.status === 'cancelled',
  ),
)

const summary = computed(() => {
  const t = active.value
  if (!t) return ''
  const pct = t.status === 'running' && t.progress > 0 ? ` ${t.progress}%` : ''
  return `${t.title}${pct}`
})

const statusLabel: Record<SilentTask['status'], string> = {
  pending: '排队',
  running: '进行中',
  succeeded: '完成',
  failed: '失败',
  cancelled: '已取消',
}

onMounted(() => {
  unsub = subscribeSilentTasks((s) => {
    snap.value = s
  })
  requestSilentList()
})

onUnmounted(() => {
  unsub?.()
  document.removeEventListener('pointerdown', onDocPointer, true)
})

function toggle() {
  open.value = !open.value
  if (open.value) {
    requestSilentList()
    document.addEventListener('pointerdown', onDocPointer, true)
  } else {
    document.removeEventListener('pointerdown', onDocPointer, true)
  }
}

function onDocPointer(ev: PointerEvent) {
  const el = rootEl.value
  if (!el) return
  if (ev.target instanceof Node && el.contains(ev.target)) return
  open.value = false
  document.removeEventListener('pointerdown', onDocPointer, true)
}

function onCancel(id: string) {
  cancelSilentTask(id)
}
</script>

<template>
  <div ref="rootEl" class="silent-tasks" :data-open="open ? '1' : '0'">
    <p v-if="summary" class="silent-tasks-summary" :title="summary">{{ summary }}</p>
    <button
      type="button"
      class="silent-tasks-btn"
      :aria-expanded="open"
      aria-haspopup="dialog"
      :aria-label="badge > 0 ? `后台任务 ${badge} 项` : '后台任务'"
      :title="badge > 0 ? `后台任务（${badge}）` : '后台任务'"
      @click="toggle"
    >
      <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
        <path
          stroke="currentColor"
          stroke-width="1.7"
          stroke-linecap="round"
          stroke-linejoin="round"
          d="M4 7h16M4 12h10M4 17h7"
        />
        <circle cx="18.5" cy="12" r="2.2" fill="currentColor" />
        <circle cx="15.5" cy="17" r="2.2" fill="currentColor" />
      </svg>
      <span v-if="badge > 0" class="silent-tasks-badge">{{ badge > 9 ? '9+' : badge }}</span>
    </button>

    <div v-if="open" class="silent-tasks-panel" role="dialog" aria-label="后台任务">
      <header class="silent-tasks-panel-head">
        <strong>后台任务</strong>
        <span class="silent-tasks-panel-count">
          {{ badge > 0 ? `${badge} 进行中` : '空闲' }}
        </span>
      </header>

      <section v-if="activeTasks.length" class="silent-tasks-section">
        <h4>进行中</h4>
        <ul>
          <li v-for="t in activeTasks" :key="t.id" class="silent-tasks-row">
            <div class="silent-tasks-row-main">
              <span class="silent-tasks-row-title">{{ t.title }}</span>
              <span class="silent-tasks-row-meta">{{ statusLabel[t.status] }}</span>
            </div>
            <div class="silent-tasks-bar" aria-hidden="true">
              <i :style="{ width: `${t.progress}%` }" />
            </div>
            <p v-if="t.detail" class="silent-tasks-row-detail">{{ t.detail }}</p>
            <button
              v-if="t.status === 'pending' || t.status === 'running'"
              type="button"
              class="silent-tasks-cancel"
              @click="onCancel(t.id)"
            >
              取消
            </button>
          </li>
        </ul>
      </section>

      <section v-if="recentTasks.length" class="silent-tasks-section">
        <h4>最近</h4>
        <ul>
          <li v-for="t in recentTasks" :key="t.id" class="silent-tasks-row is-done">
            <div class="silent-tasks-row-main">
              <span class="silent-tasks-row-title">{{ t.title }}</span>
              <span
                class="silent-tasks-row-meta"
                :data-status="t.status"
              >{{ statusLabel[t.status] }}</span>
            </div>
            <p v-if="t.detail" class="silent-tasks-row-detail">{{ t.detail }}</p>
          </li>
        </ul>
      </section>

      <p v-if="!activeTasks.length && !recentTasks.length" class="silent-tasks-empty">
        暂无后台任务
      </p>
    </div>
  </div>
</template>
