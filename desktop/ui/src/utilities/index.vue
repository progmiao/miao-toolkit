<script setup lang="ts">
/**
 * 工具集：注册表小工具；当前提供 GUID 批量生成（宿主生成，保证格式一致）。
 */
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { post, subscribe } from '@kernel/bridge/bus'
import { showToast } from '@kernel/bridge/toast'
import { useShellTitle } from '@kernel/composables/useShellTitle'

interface UtilityItem {
  id: string
  name: string
  description: string
}

const title = ref('工具集')
const body = ref('')
const items = ref<UtilityItem[]>([])
const activeId = ref('guid')

useShellTitle(title)

const count = ref(5)
const uppercase = ref(false)
const braces = ref(false)
const values = ref<string[]>([])

const active = computed(() => items.value.find((i) => i.id === activeId.value) ?? null)

let unsub: (() => void) | undefined

onMounted(() => {
  unsub = subscribe((msg) => {
    if (msg.type === 'utilities' && msg.data) {
      const d = msg.data as { title?: string; body?: string; items?: UtilityItem[] }
      if (d.title) title.value = d.title
      if (d.body) body.value = d.body
      items.value = d.items ?? []
      if (!items.value.some((i) => i.id === activeId.value) && items.value[0]) {
        activeId.value = items.value[0].id
      }
    }
    if (msg.type === 'utilities.guid' && msg.data) {
      const d = msg.data as { values?: string[] }
      values.value = d.values ?? []
      showToast(`已生成 ${values.value.length} 条`, { kind: 'ok' })
    }
  })
  post({ type: 'utilities.list' })
})

onUnmounted(() => unsub?.())

function generate() {
  post({
    type: 'utilities.guid',
    count: count.value,
    uppercase: uppercase.value,
    braces: braces.value,
  })
}

async function copyAll() {
  const text = values.value.join('\n')
  if (!text) return
  try {
    await navigator.clipboard.writeText(text)
    showToast('已复制到剪贴板', { kind: 'ok' })
  } catch {
    showToast('复制失败，请手动选择', { kind: 'error' })
  }
}
</script>

<template>
  <section class="page utilities-page">
    <header class="page-head">
      <p>{{ body }}</p>
    </header>

    <div class="util-layout">
      <ul class="util-nav hud-panel">
        <li
          v-for="it in items"
          :key="it.id"
          :class="{ active: it.id === activeId }"
          @click="activeId = it.id"
        >
          <span class="util-name">{{ it.name }}</span>
          <span class="util-desc">{{ it.description }}</span>
        </li>
        <li v-if="!items.length" class="empty-hint">暂无已注册小工具</li>
      </ul>

      <div v-if="activeId === 'guid'" class="util-body hud-panel">
        <h2 class="panel-title">{{ active?.name || 'GUID 生成' }}</h2>
        <p class="panel-hint">{{ active?.description }}</p>
        <div class="form-row">
          <label>
            数量
            <input v-model.number="count" type="number" min="1" max="100" />
          </label>
          <label class="check">
            <input v-model="uppercase" type="checkbox" />
            大写
          </label>
          <label class="check">
            <input v-model="braces" type="checkbox" />
            花括号
          </label>
          <button type="button" class="btn" @click="generate">生成</button>
          <button type="button" class="btn secondary" :disabled="!values.length" @click="copyAll">
            复制全部
          </button>
        </div>
        <pre class="guid-out">{{ values.join('\n') || '点击生成…' }}</pre>
      </div>
    </div>
  </section>
</template>

<style scoped>
.utilities-page {
  min-height: 0;
  height: 100%;
  overflow: hidden;
}
.utilities-page .page-head {
  flex: 0 0 auto;
}
.util-layout {
  flex: 1 1 auto;
  min-height: 0;
  display: grid;
  grid-template-columns: 14rem minmax(0, 1fr);
  gap: 1rem;
  margin-top: 0.5rem;
  align-items: stretch;
}
.util-nav {
  list-style: none;
  margin: 0;
  padding: 0.35rem;
  min-height: 0;
  overflow: auto;
}
.util-nav li {
  padding: 0.65rem 0.7rem;
  border-radius: 0.5rem;
  cursor: pointer;
  margin-bottom: 0.25rem;
  transition: background 0.2s ease;
}
.util-nav li:hover {
  background: color-mix(in srgb, var(--accent) 10%, transparent);
}
.util-nav li.active {
  background: color-mix(in srgb, var(--accent) 16%, transparent);
  box-shadow: inset 3px 0 0 var(--accent);
}
.util-name {
  display: block;
  font-weight: 700;
  letter-spacing: 0.04em;
}
.util-desc {
  display: block;
  font-size: 0.8rem;
  color: var(--muted);
  margin-top: 0.15rem;
}
.panel-title {
  margin: 0 0 0.35rem;
  font-family: var(--font-display);
  font-size: 0.95rem;
  letter-spacing: 0.06em;
  text-transform: uppercase;
}
.panel-hint {
  margin: 0 0 1rem;
  color: var(--muted);
  font-size: 0.9rem;
}
.util-body {
  min-height: 0;
  min-width: 0;
  overflow: auto;
}
.form-row {
  display: flex;
  flex-wrap: wrap;
  gap: 0.75rem;
  align-items: flex-end;
  margin-bottom: 0.75rem;
}
.form-row label {
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
  font-size: 0.85rem;
  color: var(--muted);
}
.form-row input[type='number'] {
  width: 5rem;
  padding: 0.35rem 0.5rem;
  border: 1px solid var(--line);
  border-radius: 0.35rem;
  background: var(--panel-strong);
  color: var(--ink);
  font-family: var(--font-mono);
}
.check {
  flex-direction: row !important;
  align-items: center;
  gap: 0.35rem !important;
  padding-bottom: 0.35rem;
}
.guid-out {
  margin: 0;
  padding: 0.9rem;
  min-height: 12rem;
  background: #05080f;
  color: #9fe8f0;
  border: 1px solid color-mix(in srgb, var(--accent) 25%, transparent);
  border-radius: 0.75rem;
  font-family: var(--font-mono);
  font-size: 0.85rem;
  white-space: pre-wrap;
  box-shadow: inset 0 0 30px rgba(0, 40, 60, 0.35);
}
@media (max-width: 800px) {
  .util-layout {
    grid-template-columns: 1fr;
  }
}
</style>
