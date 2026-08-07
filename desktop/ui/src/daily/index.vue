<script setup lang="ts">
/**
 * 日常工具：卡片网格；分类过滤；名称 + 状态 + 联动按钮（安装 / 更新 / 卸载）。
 */
import { computed, onMounted, onUnmounted, ref } from 'vue'
import ToolLogo from '@kernel/catalog/ToolLogo.vue'
import { catalogStatusClass, catalogStatusLabel } from '@kernel/catalog/statusMeta'
import { type CatalogItem, post, subscribe } from '@kernel/bridge/bus'
import { confirmDialog } from '@kernel/bridge/confirm'
import { showToast } from '@kernel/bridge/toast'
import { useShellTitle } from '@kernel/composables/useShellTitle'
import {
  buildTagFilters,
  showInstallAction,
  showUninstallAction,
  showUpdateAction,
} from '@kernel/catalog/toolMeta'

useShellTitle('日常工具')

const items = ref<CatalogItem[]>([])
const tagFilter = ref('all')
const busyId = ref<string | null>(null)

const filters = computed(() => buildTagFilters(items.value))

const filtered = computed(() => {
  if (tagFilter.value === 'all') return items.value
  return items.value.filter((i) => i.tags.includes(tagFilter.value))
})

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

/** 安装与更新均走 install 动作（Handler 内同步/升级）；更新/卸载二次确认。 */
async function run(it: CatalogItem, action: string) {
  const hostAction = action === 'update' ? 'install' : action
  if (action === 'update') {
    const ok = await confirmDialog({
      title: '更新确认',
      message: `确认更新 ${it.name}？`,
      confirmText: '更新',
      cancelText: '取消',
    })
    if (!ok) return
  } else if (action === 'uninstall') {
    const ok = await confirmDialog({
      title: '卸载确认',
      message: `确认卸载 ${it.name}？`,
      confirmText: '卸载',
      cancelText: '取消',
      tone: 'danger',
    })
    if (!ok) return
  }
  const jobId = crypto.randomUUID().replaceAll('-', '')
  post({ type: 'run-job', jobId, toolId: it.id, action: hostAction })
}
</script>

<template>
  <section class="page page--scroll daily-page">
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
          <ToolLogo
            :tool-id="it.id"
            :name="it.name"
            size="lg"
            :update-available="Boolean(it.updateAvailable)"
          />
          <div class="card-titles">
            <h2>{{ it.name }}</h2>
            <span class="tag" :class="catalogStatusClass(it)">
              {{ catalogStatusLabel(it) }}
            </span>
          </div>
        </div>
        <div class="actions">
          <button
            v-if="showInstallAction(it)"
            type="button"
            class="btn btn-overview"
            :disabled="busyId === it.id"
            @click="run(it, 'install')"
          >
            安装
          </button>
          <button
            v-if="showUpdateAction(it)"
            type="button"
            class="btn btn-overview"
            :disabled="busyId === it.id"
            @click="run(it, 'update')"
          >
            更新
          </button>
          <button
            v-if="showUninstallAction(it)"
            type="button"
            class="btn secondary btn-overview"
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
  overflow: visible;
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
  /* 给 Logo「有更新」角标留出外溢空间 */
  padding: 0.12rem 0.12rem 0 0;
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
