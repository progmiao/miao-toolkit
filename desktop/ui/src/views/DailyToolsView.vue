<script setup lang="ts">
/**
 * 日常工具：卡片网格；分类过滤；名称 + 状态 + 联动按钮（安装 / 更新 / 卸载）。
 */
import { computed, onMounted, onUnmounted, ref } from 'vue'
import ToolLogo from '../components/ToolLogo.vue'
import { type CatalogItem, post, subscribe } from '../bridge/bus'
import { showToast } from '../bridge/toast'
import {
  buildTagFilters,
  showInstallAction,
  showUninstallAction,
  showUpdateAction,
} from '../bridge/toolMeta'

const items = ref<CatalogItem[]>([])
const tagFilter = ref('all')
const busyId = ref<string | null>(null)

const filters = computed(() => buildTagFilters(items.value))

const filtered = computed(() => {
  if (tagFilter.value === 'all') return items.value
  return items.value.filter((i) => i.tags.includes(tagFilter.value))
})

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

let unsub: (() => void) | undefined

onMounted(() => {
  unsub = subscribe((msg) => {
    if (msg.type === 'catalog' && msg.items) {
      if (msg.group && msg.group !== 'daily') return
      items.value = msg.items as CatalogItem[]
    }
    if (msg.type === 'job-started' && msg.toolId) {
      busyId.value = msg.toolId
    }
    if (msg.type === 'job-finished') {
      busyId.value = null
      if (msg.ok) showToast('操作完成', { kind: 'ok' })
      else showToast(`失败：${msg.detail ?? ''}`, { kind: 'error' })
      post({ type: 'get-catalog', group: 'daily' })
    }
    if (msg.type === 'error' && msg.message) {
      busyId.value = null
      showToast(msg.message, { kind: 'error' })
    }
  })
  post({ type: 'get-catalog', group: 'daily' })
})

onUnmounted(() => unsub?.())

/** 安装与更新均走 install 动作（Handler 内同步/升级）。 */
function run(it: CatalogItem, action: string) {
  const jobId = crypto.randomUUID().replaceAll('-', '')
  post({ type: 'run-job', jobId, toolId: it.id, action })
}
</script>

<template>
  <section class="page page--scroll daily-page">
    <header class="page-head">
      <h1>日常工具</h1>
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

    <div class="daily-grid">
      <article
        v-for="it in filtered"
        :key="it.id"
        class="daily-card"
        :class="{ busy: busyId === it.id }"
      >
        <div class="card-top">
          <ToolLogo :tool-id="it.id" :name="it.name" size="lg" />
          <div class="card-titles">
            <h2>{{ it.name }}</h2>
            <span class="tag" :class="statusClass(it)">
              {{ statusLabel(it) }}
              <template v-if="it.version"> · v{{ it.version }}</template>
            </span>
          </div>
        </div>
        <div class="actions">
          <button
            v-if="showInstallAction(it)"
            type="button"
            class="btn"
            :disabled="busyId === it.id"
            @click="run(it, 'install')"
          >
            安装
          </button>
          <button
            v-if="showUpdateAction(it)"
            type="button"
            class="btn"
            :disabled="busyId === it.id"
            @click="run(it, 'install')"
          >
            更新
          </button>
          <button
            v-if="showUninstallAction(it)"
            type="button"
            class="btn secondary"
            :disabled="busyId === it.id"
            @click="run(it, 'uninstall')"
          >
            卸载
          </button>
        </div>
      </article>
    </div>

    <p v-if="!filtered.length" class="empty-hint">该分类下暂无工具</p>
  </section>
</template>

<style scoped>
.filter-bar {
  display: flex;
  flex-wrap: wrap;
  gap: 0.45rem;
  margin: 0.35rem 0 1.1rem;
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
.daily-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(240px, 1fr));
  gap: 1rem;
}
.daily-card {
  position: relative;
  display: flex;
  flex-direction: column;
  gap: 0.95rem;
  padding: 1.15rem 1.2rem;
  background: color-mix(in srgb, var(--panel) 45%, transparent);
  border: 1px solid color-mix(in srgb, var(--line) 85%, transparent);
  border-radius: 0.95rem;
  backdrop-filter: blur(18px) saturate(1.35);
  -webkit-backdrop-filter: blur(18px) saturate(1.35);
  overflow: hidden;
  transition:
    transform 0.25s ease,
    box-shadow 0.25s ease,
    border-color 0.25s ease;
  animation: card-in 0.4s ease both;
}
@keyframes card-in {
  from {
    opacity: 0;
    transform: translateY(10px) scale(0.98);
  }
  to {
    opacity: 1;
    transform: none;
  }
}
.daily-card::before {
  content: "";
  position: absolute;
  inset: 0 0 auto 0;
  height: 2px;
  background: linear-gradient(90deg, transparent, var(--accent), var(--accent-2), transparent);
}
.daily-card:hover {
  transform: translateY(-3px);
  border-color: color-mix(in srgb, var(--accent) 45%, var(--line));
  box-shadow: 0 0 28px var(--glow);
}
.daily-card.busy {
  border-color: var(--accent);
  box-shadow: 0 0 24px var(--glow);
}
.card-top {
  display: flex;
  gap: 0.85rem;
  align-items: center;
}
.card-titles {
  display: flex;
  flex-direction: column;
  gap: 0.4rem;
  min-width: 0;
}
.card-titles h2 {
  margin: 0;
  font-size: 1.1rem;
  font-weight: 700;
  line-height: 1.25;
}
.card-titles .tag {
  align-self: flex-start;
}
.actions {
  margin-top: auto;
}
</style>
