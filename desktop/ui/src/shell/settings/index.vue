<script setup lang="ts">
/**
 * 设置：左侧分类 + 右侧内容（同开发工具布局）。
 * - 常规：语言
 * - 外观：壁纸勾选（1=固定，≥2=轮播）+ 白天/黑夜磨砂参数
 * - 关于：版本说明
 */
import { computed, onMounted, onUnmounted, reactive, ref, watch } from 'vue'
import {
  WALLPAPER_PRESETS,
  commitAppearance,
  createDefaultAppearance,
  isWallpaperCarousel,
  loadAppearanceLocal,
  normalizeAppearance,
  resetThemeConfig,
  resetWallpaperConfig,
  sanitizeWallpaperIds,
  subscribeAppearance,
  type AppearanceState,
  type AppearanceThemeConfig,
  type ThemeMode,
  type WallpaperConfig,
} from '@kernel/bridge/appearance'
import { post, subscribe } from '@kernel/bridge/bus'
import { showToast } from '@kernel/bridge/toast'
import { useShellTitle } from '@kernel/composables/useShellTitle'

type SectionId = 'general' | 'appearance' | 'about'

useShellTitle('设置')

const sections: { id: SectionId; label: string }[] = [
  { id: 'general', label: '常规' },
  { id: 'appearance', label: '外观' },
  { id: 'about', label: '关于' },
]

const activeSection = ref<SectionId>('appearance')
const locale = ref('zh')
const appearance = reactive<AppearanceState>(loadAppearanceLocal())

/** 当前正在编辑的主题模式（仅影响磨砂等；可与全局 mode 同步）。 */
const editMode = ref<ThemeMode>(appearance.mode)

/** 当前主题的磨砂等参数。 */
const editing = computed(() =>
  editMode.value === 'dark' ? appearance.dark : appearance.light,
)

/** 全局壁纸（白天/黑夜共用）。 */
const wallpaper = computed(() => appearance.wallpaper)

/** 壁纸勾选列表（含「无壁纸」）。 */
const wallpaperPresets = WALLPAPER_PRESETS

/** 是否已全选全部壁纸。 */
const allImagesSelected = computed(() => {
  const set = new Set(appearance.wallpaper.wallpaperIds)
  return WALLPAPER_PRESETS.every((p) => set.has(p.id))
})

/** 勾选 ≥2 张时显示间隔。 */
const showInterval = computed(() => isWallpaperCarousel(appearance.wallpaper))

let unsubBus: (() => void) | undefined
let unsubApp: (() => void) | undefined
let saveTimer: ReturnType<typeof setTimeout> | undefined

onMounted(() => {
  unsubApp = subscribeAppearance((s) => {
    Object.assign(appearance, s)
    editMode.value = s.mode
  })
  unsubBus = subscribe((msg) => {
    if (msg.type === 'settings') {
      if (msg.locale) locale.value = msg.locale
      if (msg.appearance) Object.assign(appearance, normalizeAppearance(msg.appearance))
    }
  })
  post({ type: 'settings.get' })
})

onUnmounted(() => {
  unsubBus?.()
  unsubApp?.()
  if (saveTimer) clearTimeout(saveTimer)
})

watch(editMode, (m) => {
  if (appearance.mode !== m) {
    appearance.mode = m
    scheduleSave(true)
  }
})

/**
 * 深拷贝主题配置。
 * @param cfg - 源配置
 */
function cloneTheme(cfg: AppearanceThemeConfig): AppearanceThemeConfig {
  return { ...cfg }
}

/**
 * 深拷贝全局壁纸。
 * @param cfg - 源配置
 */
function cloneWallpaper(cfg: WallpaperConfig): WallpaperConfig {
  return { ...cfg, wallpaperIds: [...cfg.wallpaperIds] }
}

/**
 * 防抖提交；滑块拖动时降低宿主写入频率。
 * @param syncHost - 是否同步宿主
 */
function scheduleSave(syncHost = true) {
  const snapshot: AppearanceState = {
    mode: appearance.mode,
    wallpaper: cloneWallpaper(appearance.wallpaper),
    light: cloneTheme(appearance.light),
    dark: cloneTheme(appearance.dark),
  }
  commitAppearance(snapshot, false)
  if (saveTimer) clearTimeout(saveTimer)
  saveTimer = setTimeout(() => {
    commitAppearance(snapshot, syncHost)
  }, 280)
}

/** 更新当前主题的磨砂等字段。 */
function patchEditing<K extends keyof AppearanceThemeConfig>(key: K, value: AppearanceThemeConfig[K]) {
  const target = editMode.value === 'dark' ? appearance.dark : appearance.light
  target[key] = value
  scheduleSave()
}

/** 更新全局壁纸某一字段。 */
function patchWallpaper<K extends keyof WallpaperConfig>(key: K, value: WallpaperConfig[K]) {
  appearance.wallpaper[key] = value
  scheduleSave()
}

/**
 * 写入勾选列表并保存。
 * @param ids - 勾选 id
 */
function setWallpaperIds(ids: string[]) {
  patchWallpaper('wallpaperIds', sanitizeWallpaperIds(ids))
}

/**
 * 勾选/取消某一壁纸；至少保留一张（取消最后一张时保持原样）。
 * @param id - 壁纸 id
 */
function toggleWallpaper(id: string) {
  const cur = [...appearance.wallpaper.wallpaperIds]
  const i = cur.indexOf(id)
  if (i >= 0) {
    if (cur.length <= 1) return
    cur.splice(i, 1)
  } else {
    cur.push(id)
  }
  setWallpaperIds(cur)
}

/**
 * 是否已勾选。
 * @param id - 壁纸 id
 */
function isWallpaperSelected(id: string): boolean {
  return appearance.wallpaper.wallpaperIds.includes(id)
}

/**
 * 全选 / 取消全选。
 * 已全选时回落为默认单张；否则勾选全部。
 */
function toggleSelectAll() {
  if (allImagesSelected.value) setWallpaperIds(['mecha-01'])
  else setWallpaperIds(WALLPAPER_PRESETS.map((p) => p.id))
}

function applyLocale(next: string) {
  locale.value = next
  post({ type: 'settings.set-locale', locale: next })
  showToast('语言已保存', { kind: 'ok' })
}

/** 仅重置当前主题的磨砂等，不改全局壁纸。 */
function resetCurrent() {
  const cfg = resetThemeConfig(editMode.value)
  if (editMode.value === 'dark') appearance.dark = cfg
  else appearance.light = cfg
  scheduleSave(true)
  showToast('已恢复当前主题默认外观', { kind: 'ok' })
}

/** 重置壁纸 + 两套主题。 */
function resetAll() {
  const d = createDefaultAppearance()
  appearance.mode = d.mode
  appearance.wallpaper = resetWallpaperConfig()
  appearance.light = d.light
  appearance.dark = d.dark
  editMode.value = d.mode
  scheduleSave(true)
  showToast('已恢复全部默认外观', { kind: 'ok' })
}
</script>

<template>
  <section class="page settings-page">
    <div class="settings-layout">
      <ul class="settings-nav panel-frost panel-frost--flat">
        <li
          v-for="s in sections"
          :key="s.id"
          class="side-nav-item"
          :class="{ active: activeSection === s.id }"
          @click="activeSection = s.id"
        >
          <span class="nav-label">{{ s.label }}</span>
        </li>
      </ul>

      <aside class="settings-panel panel-frost panel-frost--flat">
        <div v-if="activeSection === 'general'" class="pane">
          <h2 class="sec-title">界面语言</h2>
          <p class="sec-hint">写入本地配置；切换后各页面文案按新语言刷新。</p>
          <div class="actions">
            <button type="button" class="btn" :class="{ secondary: locale !== 'zh' }" @click="applyLocale('zh')">
              简体中文
            </button>
            <button type="button" class="btn" :class="{ secondary: locale !== 'en' }" @click="applyLocale('en')">
              English
            </button>
          </div>
        </div>

        <div v-else-if="activeSection === 'appearance'" class="pane">
          <h2 class="sec-title">外观主题</h2>
          <p class="sec-hint">调整背景壁纸与白天 / 黑夜下的磨砂、透明度等视觉参数。</p>

          <h3 class="sub-title">背景壁纸</h3>
          <div class="wall-toolbar">
            <button
              type="button"
              class="btn secondary wall-select-all"
              @click="toggleSelectAll"
            >
              {{ allImagesSelected ? '取消全选' : '全选' }}
            </button>
            <label v-if="showInterval" class="field wall-interval">
              <span>切换间隔 {{ wallpaper.wallpaperIntervalSec }} 秒</span>
              <input
                type="range"
                min="5"
                max="300"
                step="1"
                :value="wallpaper.wallpaperIntervalSec"
                @input="
                  patchWallpaper(
                    'wallpaperIntervalSec',
                    Number(($event.target as HTMLInputElement).value),
                  )
                "
              />
            </label>
          </div>

          <div class="wall-row" role="group" aria-label="壁纸勾选">
            <button
              v-for="w in wallpaperPresets"
              :key="w.id"
              type="button"
              class="wall-card"
              :class="{ active: isWallpaperSelected(w.id) }"
              :aria-pressed="isWallpaperSelected(w.id)"
              @click="toggleWallpaper(w.id)"
            >
              <span class="wall-check" aria-hidden="true">{{
                isWallpaperSelected(w.id) ? '✓' : ''
              }}</span>
              <span class="wall-thumb" :style="{ backgroundImage: `url(${w.src})` }" />
              <span class="wall-name">{{ w.name }}</span>
            </button>
          </div>

          <h3 class="sub-title">白天 / 黑夜</h3>
          <div class="mode-tabs">
            <button
              type="button"
              class="btn"
              :class="{ secondary: editMode !== 'light' }"
              @click="editMode = 'light'"
            >
              白天
            </button>
            <button
              type="button"
              class="btn"
              :class="{ secondary: editMode !== 'dark' }"
              @click="editMode = 'dark'"
            >
              黑夜
            </button>
          </div>

          <label class="field">
            <span>壁纸透明度 {{ Math.round(editing.wallpaperOpacity * 100) }}%</span>
            <input
              type="range"
              min="0"
              max="100"
              :value="Math.round(editing.wallpaperOpacity * 100)"
              @input="patchEditing('wallpaperOpacity', Number(($event.target as HTMLInputElement).value) / 100)"
            />
          </label>
          <label class="field">
            <span>遮罩强度 {{ Math.round(editing.overlayStrength * 100) }}%</span>
            <input
              type="range"
              min="0"
              max="80"
              :value="Math.round(editing.overlayStrength * 100)"
              @input="patchEditing('overlayStrength', Number(($event.target as HTMLInputElement).value) / 100)"
            />
          </label>
          <label class="field">
            <span>科技光效 {{ Math.round(editing.fxIntensity * 100) }}%</span>
            <input
              type="range"
              min="0"
              max="100"
              :value="Math.round(editing.fxIntensity * 100)"
              @input="patchEditing('fxIntensity', Number(($event.target as HTMLInputElement).value) / 100)"
            />
          </label>

          <h3 class="sub-title">栏位磨砂（左 / 顶 / 底）</h3>
          <label class="field">
            <span>栏位颜色</span>
            <input
              type="color"
              :value="editing.chromeColor"
              @input="patchEditing('chromeColor', ($event.target as HTMLInputElement).value)"
            />
          </label>
          <label class="field">
            <span>栏位透明度 {{ Math.round(editing.chromeOpacity * 100) }}%</span>
            <input
              type="range"
              min="8"
              max="75"
              :value="Math.round(editing.chromeOpacity * 100)"
              @input="patchEditing('chromeOpacity', Number(($event.target as HTMLInputElement).value) / 100)"
            />
          </label>
          <label class="field">
            <span>磨砂模糊 {{ editing.frostBlur }}px</span>
            <input
              type="range"
              min="8"
              max="48"
              :value="editing.frostBlur"
              @input="patchEditing('frostBlur', Number(($event.target as HTMLInputElement).value))"
            />
          </label>
          <label class="field">
            <span>磨砂饱和 {{ Math.round(editing.frostSaturation * 100) }}%</span>
            <input
              type="range"
              min="100"
              max="200"
              :value="Math.round(editing.frostSaturation * 100)"
              @input="patchEditing('frostSaturation', Number(($event.target as HTMLInputElement).value) / 100)"
            />
          </label>
          <label class="field">
            <span>磨砂光晕色</span>
            <input
              type="color"
              :value="editing.frostTint"
              @input="patchEditing('frostTint', ($event.target as HTMLInputElement).value)"
            />
          </label>

          <div class="actions">
            <button type="button" class="btn secondary" @click="resetCurrent">重置当前主题</button>
            <button type="button" class="btn secondary" @click="resetAll">重置全部</button>
          </div>
        </div>

        <div v-else class="pane">
          <h2 class="sec-title">关于</h2>
          <p class="sec-hint">Miao 工具箱 · 桌面端。外观壁纸为打包预制资源，可在「外观」中切换。</p>
        </div>
      </aside>
    </div>
  </section>
</template>

<style scoped>
.settings-page {
  display: flex;
  flex-direction: column;
  min-height: 0;
  height: 100%;
  max-height: 100%;
  overflow: hidden;
}
.settings-layout {
  flex: 1;
  min-height: 0;
  display: grid;
  grid-template-columns: minmax(10rem, 12rem) minmax(0, 1fr);
  gap: 1rem;
  align-items: stretch;
}
.settings-nav {
  list-style: none;
  margin: 0;
  padding: 0.45rem;
  overflow: auto;
  min-height: 0;
  height: 100%;
}
.settings-nav .side-nav-item {
  display: flex;
  align-items: center;
  min-height: 2.75rem;
  padding: 0.65rem 0.7rem;
  margin-bottom: 0.25rem;
  border-radius: 0.55rem;
  cursor: pointer;
  font-weight: 700;
  font-size: 0.92rem;
}
.settings-panel {
  min-height: 0;
  height: 100%;
  overflow: auto;
  padding: 1rem 1.1rem;
}
.sec-title {
  margin: 0 0 0.35rem;
  font-family: var(--font-display);
  font-size: 0.9rem;
  letter-spacing: 0.08em;
  text-transform: uppercase;
}
.sub-title {
  margin: 1.1rem 0 0.55rem;
  font-size: 0.85rem;
  font-weight: 700;
  color: var(--muted);
}
.mode-tabs {
  display: flex;
  gap: 0.5rem;
  margin-bottom: 0.85rem;
}
.wall-toolbar {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.75rem 1rem;
  margin-bottom: 0.55rem;
}
.wall-select-all {
  flex: 0 0 auto;
}
.wall-interval {
  flex: 1 1 14rem;
  margin: 0;
}
.wall-row {
  display: flex;
  flex-wrap: nowrap;
  gap: 0.55rem;
  margin-bottom: 0.85rem;
  padding: 0.15rem 0.1rem 0.45rem;
  overflow-x: auto;
  overflow-y: hidden;
}
.wall-card {
  position: relative;
  flex: 0 0 auto;
  width: 7.2rem;
  display: flex;
  flex-direction: column;
  gap: 0.35rem;
  padding: 0.35rem;
  border: 1px solid var(--line);
  border-radius: 0.55rem;
  background: color-mix(in srgb, var(--panel) 50%, transparent);
  cursor: pointer;
  color: inherit;
  transition: border-color 0.2s ease, box-shadow 0.22s ease;
}
.wall-card.active {
  border-color: var(--accent);
  box-shadow: 0 0 0 1px color-mix(in srgb, var(--accent) 50%, transparent);
}
.wall-check {
  position: absolute;
  top: 0.45rem;
  right: 0.45rem;
  z-index: 1;
  width: 1.15rem;
  height: 1.15rem;
  display: grid;
  place-items: center;
  border-radius: 0.25rem;
  font-size: 0.72rem;
  font-weight: 800;
  line-height: 1;
  color: #fff;
  background: color-mix(in srgb, var(--accent) 88%, #000);
  box-shadow: 0 0 0 1px color-mix(in srgb, var(--accent) 40%, transparent);
}
.wall-card:not(.active) .wall-check {
  background: color-mix(in srgb, var(--panel) 70%, transparent);
  color: transparent;
  box-shadow: inset 0 0 0 1px var(--line);
}
.wall-thumb {
  display: block;
  height: 3.6rem;
  border-radius: 0.35rem;
  background-size: cover;
  background-position: center;
}
.wall-name {
  font-size: 0.72rem;
  text-align: center;
  line-height: 1.2;
}
.field {
  display: grid;
  grid-template-columns: 1fr auto;
  align-items: center;
  gap: 0.75rem;
  margin: 0.55rem 0;
  font-size: 0.88rem;
}
.field input[type='range'] {
  width: 11rem;
  accent-color: var(--accent);
}
.field input[type='color'] {
  width: 2.5rem;
  height: 1.6rem;
  padding: 0;
  border: 1px solid var(--line);
  border-radius: 0.35rem;
  background: transparent;
}
.actions {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
  margin-top: 1rem;
}
@media (max-width: 900px) {
  .settings-layout {
    grid-template-columns: 1fr;
  }
  .settings-nav {
    height: auto;
    max-height: 10rem;
  }
}
</style>
