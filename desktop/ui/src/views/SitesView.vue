<script setup lang="ts">
/**
 * 常用网站：一级分类 + 列表；系统项只读；用户可增删改；导入导出。
 */
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { post, subscribe, type HostMessage } from '../bridge/bus'
import { showToast } from '../bridge/toast'

interface SiteCategory {
  id: string
  name: string
  sort: number
  source: string
  editable: boolean
}

interface SiteItem {
  id: string
  categoryId: string
  title: string
  url: string
  sort: number
  source: string
  note?: string | null
  editable: boolean
}

const categories = ref<SiteCategory[]>([])
const sites = ref<SiteItem[]>([])
const activeCategoryId = ref<string>('')

const editingSite = ref<Partial<SiteItem> | null>(null)
const editingCategory = ref<Partial<SiteCategory> | null>(null)

const filteredSites = computed(() => {
  if (!activeCategoryId.value) return sites.value
  return sites.value.filter((s) => s.categoryId === activeCategoryId.value)
})

function applySites(msg: HostMessage) {
  if (msg.type !== 'sites') return
  categories.value = (msg.categories as SiteCategory[]) ?? []
  sites.value = (msg.sites as SiteItem[]) ?? []
  if (!activeCategoryId.value && categories.value.length) {
    activeCategoryId.value = categories.value[0].id
  }
}

let unsub: (() => void) | undefined

onMounted(() => {
  unsub = subscribe((msg) => {
    if (msg.type === 'error' && msg.message) {
      showToast(String(msg.message), { kind: 'error' })
      return
    }
    if (msg.type === 'sites') {
      applySites(msg)
    }
    if (msg.type === 'sites.export' && msg.json) {
      const blob = new Blob([String(msg.json)], { type: 'application/json' })
      const a = document.createElement('a')
      a.href = URL.createObjectURL(blob)
      a.download = 'miao-sites.json'
      a.click()
      URL.revokeObjectURL(a.href)
      showToast('已导出', { kind: 'ok' })
    }
  })
  post({ type: 'sites.list' })
})

onUnmounted(() => unsub?.())

function openSite(id: string) {
  post({ type: 'sites.open', id })
}

function startAddSite() {
  editingSite.value = {
    categoryId: activeCategoryId.value || categories.value[0]?.id || '',
    title: '',
    url: 'https://',
    sort: 100,
    note: '',
  }
}

function startEditSite(s: SiteItem) {
  if (!s.editable) return
  editingSite.value = { ...s }
}

function saveSite() {
  const s = editingSite.value
  if (!s) return
  post({
    type: 'sites.save',
    id: s.id,
    categoryId: s.categoryId,
    title: s.title,
    url: s.url,
    sort: s.sort ?? 100,
    note: s.note ?? '',
  })
  editingSite.value = null
}

function deleteSite(id: string) {
  if (!confirm('删除该网站？')) return
  post({ type: 'sites.delete', id })
}

function startAddCategory() {
  editingCategory.value = { name: '', sort: 100 }
}

function saveCategory() {
  const c = editingCategory.value
  if (!c) return
  post({ type: 'sites.save-category', id: c.id, name: c.name, sort: c.sort ?? 100 })
  editingCategory.value = null
}

function deleteCategory(id: string) {
  if (!confirm('删除该分类及其下用户网站？')) return
  post({ type: 'sites.delete-category', id })
}

function exportSites() {
  post({ type: 'sites.export' })
}

function onImportFile(ev: Event) {
  const input = ev.target as HTMLInputElement
  const file = input.files?.[0]
  if (!file) return
  const reader = new FileReader()
  reader.onload = () => {
    post({ type: 'sites.import', json: String(reader.result ?? '') })
    showToast('导入完成（仅用户项）', { kind: 'ok' })
  }
  reader.readAsText(file, 'utf-8')
  input.value = ''
}
</script>

<template>
  <section class="page page--scroll sites-page">
    <header class="page-head">
      <h1>常用网站</h1>
      <p>一级分类收藏；点击用系统浏览器打开。系统项只读，可自行新增。</p>
      <div class="toolbar">
        <button type="button" class="btn" @click="startAddCategory">新建分类</button>
        <button type="button" class="btn" @click="startAddSite">新建网站</button>
        <button type="button" class="btn secondary" @click="exportSites">导出</button>
        <label class="btn secondary file-btn">
          导入
          <input type="file" accept="application/json,.json" hidden @change="onImportFile" />
        </label>
      </div>
    </header>

    <div class="sites-layout">
      <aside class="cat-list">
        <button
          v-for="c in categories"
          :key="c.id"
          type="button"
          class="cat-item"
          :class="{ active: c.id === activeCategoryId }"
          @click="activeCategoryId = c.id"
        >
          <span>{{ c.name }}</span>
          <span class="tag">{{ c.source === 'system' ? '系统' : '我的' }}</span>
          <button
            v-if="c.editable"
            type="button"
            class="link danger"
            @click.stop="deleteCategory(c.id)"
          >
            删
          </button>
        </button>
      </aside>

      <div class="site-list">
        <article v-for="s in filteredSites" :key="s.id" class="site-card">
          <div class="site-main">
            <button type="button" class="site-title" @click="openSite(s.id)">{{ s.title }}</button>
            <p class="site-url">{{ s.url }}</p>
            <p v-if="s.note" class="site-note">{{ s.note }}</p>
          </div>
          <div class="site-actions">
            <span class="tag">{{ s.source === 'system' ? '系统' : '我的' }}</span>
            <button v-if="s.editable" type="button" class="link" @click="startEditSite(s)">编辑</button>
            <button v-if="s.editable" type="button" class="link danger" @click="deleteSite(s.id)">
              删除
            </button>
          </div>
        </article>
        <p v-if="!filteredSites.length" class="empty">此分类下暂无网站</p>
      </div>
    </div>

    <div v-if="editingSite" class="modal" @click.self="editingSite = null">
      <form class="panel" @submit.prevent="saveSite">
        <h3>{{ editingSite.id ? '编辑网站' : '新建网站' }}</h3>
        <label>
          分类
          <select v-model="editingSite.categoryId" required>
            <option v-for="c in categories" :key="c.id" :value="c.id">{{ c.name }}</option>
          </select>
        </label>
        <label>
          标题
          <input v-model="editingSite.title" required />
        </label>
        <label>
          网址
          <input v-model="editingSite.url" required />
        </label>
        <label>
          备注
          <input v-model="editingSite.note" />
        </label>
        <div class="row">
          <button type="submit" class="btn">保存</button>
          <button type="button" class="btn secondary" @click="editingSite = null">取消</button>
        </div>
      </form>
    </div>

    <div v-if="editingCategory" class="modal" @click.self="editingCategory = null">
      <form class="panel" @submit.prevent="saveCategory">
        <h3>新建分类</h3>
        <label>
          名称
          <input v-model="editingCategory.name" required />
        </label>
        <div class="row">
          <button type="submit" class="btn">保存</button>
          <button type="button" class="btn secondary" @click="editingCategory = null">取消</button>
        </div>
      </form>
    </div>
  </section>
</template>

<style scoped>
.toolbar {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
  margin-top: 0.75rem;
}
.file-btn {
  cursor: pointer;
}
.sites-layout {
  display: grid;
  grid-template-columns: 13rem 1fr;
  gap: 1rem;
  margin-top: 1rem;
}
.cat-list {
  display: flex;
  flex-direction: column;
  gap: 0.35rem;
}
.cat-item {
  display: flex;
  align-items: center;
  gap: 0.35rem;
  text-align: left;
  padding: 0.55rem 0.65rem;
  border: 1px solid var(--line);
  background: var(--panel);
  border-radius: 0.5rem;
  cursor: pointer;
  color: inherit;
  transition: border-color 0.2s ease, box-shadow 0.2s ease, background 0.2s ease;
}
.cat-item:hover {
  border-color: color-mix(in srgb, var(--accent) 40%, var(--line));
}
.cat-item.active {
  border-color: color-mix(in srgb, var(--accent) 55%, transparent);
  background: color-mix(in srgb, var(--accent) 12%, var(--panel));
  box-shadow: inset 3px 0 0 var(--accent);
}
.site-list {
  background: var(--panel);
  border: 1px solid var(--line);
  border-radius: 0.85rem;
  padding: 0.35rem 0.85rem;
  backdrop-filter: blur(12px);
}
.site-card {
  display: flex;
  justify-content: space-between;
  gap: 1rem;
  padding: 0.85rem 0.15rem;
  border-bottom: 1px solid var(--line);
}
.site-card:last-child {
  border-bottom: none;
}
.site-title {
  border: 0;
  background: none;
  color: var(--accent);
  font-size: 1.05rem;
  font-weight: 700;
  letter-spacing: 0.02em;
  cursor: pointer;
  padding: 0;
  text-shadow: 0 0 12px color-mix(in srgb, var(--glow) 40%, transparent);
}
.site-url,
.site-note {
  margin: 0.25rem 0 0;
  font-size: 0.85rem;
  color: var(--muted);
  font-family: var(--font-mono);
}
.site-actions {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}
.link {
  border: 0;
  background: none;
  color: var(--accent);
  cursor: pointer;
  font-weight: 600;
}
.link.danger {
  color: var(--danger);
}
.empty {
  color: var(--muted);
  padding: 1rem 0;
}
.modal {
  position: fixed;
  inset: 0;
  background: rgba(4, 10, 20, 0.55);
  backdrop-filter: blur(6px);
  display: grid;
  place-items: center;
  z-index: 20;
}
.panel {
  width: min(28rem, 92vw);
  background: var(--panel-strong);
  border: 1px solid var(--line);
  color: inherit;
  padding: 1.25rem;
  border-radius: 0.85rem;
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
  box-shadow: 0 0 40px color-mix(in srgb, var(--glow) 35%, transparent);
}
.panel h3 {
  margin: 0;
  font-family: var(--font-display);
  letter-spacing: 0.08em;
  text-transform: uppercase;
  font-size: 0.9rem;
}
.panel label {
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
  font-size: 0.9rem;
  color: var(--muted);
}
.panel input,
.panel select {
  padding: 0.45rem 0.55rem;
  border: 1px solid var(--line);
  border-radius: 0.4rem;
  background: var(--panel);
  color: var(--ink);
}
.row {
  display: flex;
  gap: 0.5rem;
}
@media (max-width: 800px) {
  .sites-layout {
    grid-template-columns: 1fr;
  }
}
</style>
