<script setup lang="ts">
/**
 * 应用固定壳：左栏通高贴边，顶/底与左相接。
 * 底层 = 预制机甲壁纸（单一/轮播 crossfade）+ 科技光效。
 * 挂载全局 AppToast（顶部居中消息）。
 */
import { computed, onMounted, onUnmounted, ref, watch } from 'vue'
import { RouterLink, RouterView } from 'vue-router'
import asciiLogoRaw from './ascii-logo.txt?raw'
import { appShellContent as c } from './content'
import {
  activeThemeConfig,
  applyAppearanceToElement,
  commitAppearance,
  isWallpaperCarousel,
  loadAppearanceLocal,
  normalizeAppearance,
  resolveWallpaperPlaylist,
  subscribeAppearance,
  wallpaperSrc,
  type AppearanceState,
  type ThemeMode,
} from '../../bridge/appearance'
import { isBrowserMock, post, subscribe } from '../../bridge/bus'
import AppToast from '../AppToast'
import './AppShell.css'

/** 当前版本（优先宿主 app-info）。 */
const version = ref<string>(c.fallbackVersion)

/** 外观状态。 */
const appearance = ref<AppearanceState>(loadAppearanceLocal())

/** 当前主题模式。 */
const theme = computed(() => appearance.value.mode)

/** 浏览器 Mock 调试条。 */
const showMockBanner = computed(() => isBrowserMock())

/** ASCII logo 非空行。 */
const logoLines = computed(() =>
  asciiLogoRaw
    .replace(/^\uFEFF/, '')
    .split(/\r?\n/)
    .map((l) => l.replace(/\s+$/, ''))
    .filter((l) => /\S/.test(l)),
)

/** 底栏一行元数据。 */
const footerLine = computed(
  () =>
    `${c.versionLabel}：${version.value}　${c.releaseDateLabel}：${c.releaseDate}　${c.authorLabel}：${c.author}　${c.emailLabel}：${c.email}`,
)

const shellEl = ref<HTMLElement | null>(null)

/** 双层壁纸 crossfade。 */
const layerA = ref({ src: 'none', on: true })
const layerB = ref({ src: 'none', on: false })
/** 当前正面层。 */
const frontLayer = ref<'a' | 'b'>('a')
/** 播放列表下标（轮播）。 */
const playlistIndex = ref(0)

/** 应用磨砂等 CSS 变量。 */
function paintChrome() {
  if (shellEl.value) applyAppearanceToElement(shellEl.value, appearance.value)
}

/**
 * 交叉淡入到指定壁纸 id；若与当前正面层相同则跳过，避免无意义闪烁。
 * @param id - 壁纸 id（none 则清空）
 */
function crossfadeTo(id: string) {
  const path = wallpaperSrc(id)
  const css = path ? `url("${path}")` : 'none'
  const front = frontLayer.value === 'a' ? layerA.value : layerB.value
  if (front.src === css && front.on) return
  const next: 'a' | 'b' = frontLayer.value === 'a' ? 'b' : 'a'
  if (next === 'a') {
    layerA.value = { src: css, on: true }
    layerB.value = { ...layerB.value, on: false }
  } else {
    layerB.value = { src: css, on: true }
    layerA.value = { ...layerA.value, on: false }
  }
  frontLayer.value = next
}

/** 按当前配置刷新壁纸显示。 */
function syncWallpaperDisplay(resetIndex = false) {
  const list = resolveWallpaperPlaylist(appearance.value.wallpaper)
  if (resetIndex) playlistIndex.value = 0
  if (playlistIndex.value >= list.length) playlistIndex.value = 0
  crossfadeTo(list[playlistIndex.value] ?? 'mecha-01')
}

/** 轮播前进一帧。 */
function advanceCarousel() {
  const wp = appearance.value.wallpaper
  if (!isWallpaperCarousel(wp)) return
  const list = resolveWallpaperPlaylist(wp)
  if (list.length <= 1) return
  playlistIndex.value = (playlistIndex.value + 1) % list.length
  crossfadeTo(list[playlistIndex.value]!)
}

/** 切换白天/黑夜。 */
function toggleTheme() {
  const next: ThemeMode = appearance.value.mode === 'light' ? 'dark' : 'light'
  appearance.value = { ...appearance.value, mode: next }
  commitAppearance(appearance.value)
}

let unsubBus: (() => void) | undefined
let unsubAppearance: (() => void) | undefined
let carouselTimer: ReturnType<typeof setInterval> | undefined

/** 按配置启停轮播定时器。 */
function restartCarouselTimer() {
  if (carouselTimer) {
    clearInterval(carouselTimer)
    carouselTimer = undefined
  }
  const wp = appearance.value.wallpaper
  if (!isWallpaperCarousel(wp)) return
  const list = resolveWallpaperPlaylist(wp)
  if (list.length <= 1) return
  const ms = Math.max(5, wp.wallpaperIntervalSec) * 1000
  carouselTimer = setInterval(advanceCarousel, ms)
}

onMounted(() => {
  paintChrome()
  // 首帧直接设一层，避免无意义淡入
  const list = resolveWallpaperPlaylist(appearance.value.wallpaper)
  const first = list[0] ?? 'mecha-01'
  const path = wallpaperSrc(first)
  layerA.value = { src: path ? `url("${path}")` : 'none', on: true }
  layerB.value = { src: 'none', on: false }
  frontLayer.value = 'a'
  playlistIndex.value = 0
  restartCarouselTimer()

  unsubAppearance = subscribeAppearance((s) => {
    appearance.value = s
    paintChrome()
    syncWallpaperDisplay(true)
    restartCarouselTimer()
  })
  unsubBus = subscribe((msg) => {
    if (msg.type === 'app-info' && msg.version) {
      version.value = msg.version.replace(/^v/i, '')
    }
    if (msg.type === 'settings' && msg.appearance) {
      appearance.value = normalizeAppearance(msg.appearance)
      paintChrome()
      syncWallpaperDisplay(true)
      restartCarouselTimer()
    }
  })
  post({ type: 'get-app-info' })
  post({ type: 'settings.get' })
})

onUnmounted(() => {
  unsubBus?.()
  unsubAppearance?.()
  if (carouselTimer) clearInterval(carouselTimer)
})

watch(
  () => [
    appearance.value.wallpaper.wallpaperIds,
    appearance.value.wallpaper.wallpaperIntervalSec,
  ],
  () => {
    syncWallpaperDisplay(true)
    restartCarouselTimer()
  },
)

watch(
  () => {
    const cfg = activeThemeConfig(appearance.value)
    return [
      appearance.value.mode,
      cfg.wallpaperOpacity,
      cfg.overlayStrength,
      cfg.chromeOpacity,
      cfg.chromeColor,
      cfg.frostBlur,
      cfg.frostSaturation,
      cfg.frostTint,
      cfg.fxIntensity,
    ]
  },
  () => paintChrome(),
)
</script>

<template>
  <div ref="shellEl" class="app-shell" :data-theme="theme" aria-label="Miao 应用壳">
    <AppToast />
    <p v-if="showMockBanner" class="mock-banner" role="status">
      浏览器调试模式 · 使用 Mock 数据（安装任务不会真实执行）
    </p>
    <div class="shell-atmosphere" aria-hidden="true">
      <div class="shell-atmosphere-fallback" />
      <div
        class="shell-atmosphere-wallpaper"
        :class="{ on: layerA.on }"
        :style="{ backgroundImage: layerA.src }"
      />
      <div
        class="shell-atmosphere-wallpaper"
        :class="{ on: layerB.on }"
        :style="{ backgroundImage: layerB.src }"
      />
      <div class="shell-atmosphere-overlay" />
      <div class="shell-atmosphere-hex" />
      <div class="shell-atmosphere-beam" />
      <div class="shell-atmosphere-orbs" />
      <div class="shell-atmosphere-scan" />
      <div class="shell-atmosphere-vignette" />
    </div>

    <aside class="shell-left shell-frost">
      <div class="shell-brand">
        <pre class="shell-logo" aria-hidden="true">{{ logoLines.join('\n') }}</pre>
        <p class="shell-welcome">{{ c.welcomeLine }}</p>
      </div>

      <nav class="shell-nav" aria-label="业务菜单">
        <RouterLink to="/sites">常用网站</RouterLink>
        <RouterLink to="/daily">日常工具</RouterLink>
        <RouterLink to="/dev">开发工具</RouterLink>
        <RouterLink to="/utilities">工具集</RouterLink>
      </nav>

      <div class="shell-dock" aria-label="主题与设置">
        <button
          type="button"
          class="theme-switch"
          :class="theme"
          role="switch"
          :aria-checked="theme === 'dark'"
          :aria-label="theme === 'light' ? '切换为黑夜主题' : '切换为白天主题'"
          :title="theme === 'light' ? '黑夜' : '白天'"
          @click="toggleTheme"
        >
          <span class="theme-switch-track" aria-hidden="true">
            <span class="theme-switch-thumb">
              <svg class="theme-icon theme-icon-sun" viewBox="0 0 24 24" fill="none">
                <circle cx="12" cy="12" r="3.6" fill="currentColor" />
                <path
                  stroke="currentColor"
                  stroke-width="1.8"
                  stroke-linecap="round"
                  d="M12 2.8v1.8M12 19.4v1.8M4.6 12H2.8M21.2 12h-1.8M5.9 5.9l1.3 1.3M16.8 16.8l1.3 1.3M5.9 18.1l1.3-1.3M16.8 7.2l1.3-1.3"
                />
              </svg>
              <svg class="theme-icon theme-icon-moon" viewBox="0 0 24 24" fill="currentColor">
                <path d="M20.2 14.2A7.6 7.6 0 0 1 9.8 3.8 7.8 7.8 0 1 0 20.2 14.2Z" />
              </svg>
            </span>
          </span>
        </button>
        <RouterLink class="shell-settings-btn" to="/settings" aria-label="设置" title="设置">
          <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
            <circle cx="12" cy="12" r="3" stroke="currentColor" stroke-width="1.7" />
            <path
              stroke="currentColor"
              stroke-width="1.7"
              stroke-linecap="round"
              d="M12 3.5v1.6M12 18.9v1.6M3.5 12h1.6M18.9 12h1.6M6.05 6.05l1.13 1.13M16.82 16.82l1.13 1.13M6.05 17.95l1.13-1.13M16.82 7.18l1.13-1.13"
            />
          </svg>
        </RouterLink>
      </div>
    </aside>

    <div class="shell-main">
      <header class="shell-top shell-frost" aria-hidden="true">
        <span class="shell-top-line" />
        <span class="shell-top-title">{{ c.title }}</span>
        <span class="shell-top-line" />
      </header>

      <main class="shell-content">
        <div class="shell-view">
          <RouterView />
        </div>
      </main>

      <footer class="shell-bottom shell-frost">
        <p class="shell-meta">{{ footerLine }}</p>
      </footer>
    </div>
  </div>
</template>
