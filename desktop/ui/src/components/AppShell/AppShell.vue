<script setup lang="ts">
/**
 * 应用固定壳：顶栏 + 左侧(Logo/欢迎/业务菜单/系统菜单) + 中间内容 + 底栏。
 * 主题同时作用于壳（顶/左/底）与内容区；切换为图标动画。
 */
import { computed, onMounted, onUnmounted, ref, watch } from 'vue'
import { RouterLink, RouterView } from 'vue-router'
import asciiLogoRaw from './ascii-logo.txt?raw'
import { appShellContent as c } from './content'
import { post, subscribe } from '../../bridge/bus'
import './AppShell.css'

const THEME_KEY = 'miao-theme'

/** 主题：light=白天 / dark=黑夜 */
type Theme = 'light' | 'dark'

/** 当前版本（优先宿主 app-info）。 */
const version = ref<string>(c.fallbackVersion)

/** 当前主题。 */
const theme = ref<Theme>('light')

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

/**
 * 把主题写到壳与 documentElement（内容区变量），并持久化。
 * @param next - light | dark
 */
function applyTheme(next: Theme) {
  theme.value = next
  document.documentElement.dataset.theme = next
  try {
    localStorage.setItem(THEME_KEY, next)
  } catch {
    /* 忽略隐私模式写失败 */
  }
}

/** 在白天 / 黑夜间切换。 */
function toggleTheme() {
  applyTheme(theme.value === 'light' ? 'dark' : 'light')
}

let unsubscribe: (() => void) | undefined

onMounted(() => {
  let initial: Theme = 'light'
  try {
    const saved = localStorage.getItem(THEME_KEY)
    if (saved === 'light' || saved === 'dark') initial = saved
  } catch {
    /* ignore */
  }
  applyTheme(initial)

  unsubscribe = subscribe((msg) => {
    if (msg.type === 'app-info' && msg.version) {
      version.value = msg.version.replace(/^v/i, '')
    }
  })
  post({ type: 'get-app-info' })
})

onUnmounted(() => unsubscribe?.())

watch(theme, (v) => {
  document.documentElement.dataset.theme = v
})
</script>

<template>
  <div class="app-shell" :data-theme="theme" aria-label="Miao 应用壳">
    <header class="shell-top" aria-hidden="true">
      <span class="shell-top-line" />
      <span class="shell-top-title">{{ c.title }}</span>
      <span class="shell-top-line" />
    </header>

    <div class="shell-mid">
      <aside class="shell-left">
        <div class="shell-brand">
          <pre class="shell-logo" aria-hidden="true">{{ logoLines.join('\n') }}</pre>
          <p class="shell-welcome">{{ c.welcomeLine }}</p>
        </div>

        <nav class="shell-nav" aria-label="业务菜单">
          <RouterLink to="/">首页</RouterLink>
          <RouterLink to="/daily">日常工具</RouterLink>
          <RouterLink to="/dev">开发工具</RouterLink>
        </nav>

        <div class="shell-system" aria-label="系统菜单">
          <p class="shell-system-label">系统</p>
          <button
            type="button"
            class="theme-toggle"
            :class="theme"
            :aria-label="theme === 'light' ? '切换为黑夜主题' : '切换为白天主题'"
            :title="theme === 'light' ? '黑夜' : '白天'"
            @click="toggleTheme"
          >
            <span class="theme-toggle-track" aria-hidden="true">
              <!-- 太阳：白天主题时显示（表示可切到夜） -->
              <svg class="theme-icon theme-icon-sun" viewBox="0 0 24 24" fill="none">
                <circle cx="12" cy="12" r="4" fill="currentColor" />
                <path
                  stroke="currentColor"
                  stroke-width="1.8"
                  stroke-linecap="round"
                  d="M12 2v2.2M12 19.8V22M4.2 12H2M22 12h-2.2M5.6 5.6l1.6 1.6M16.8 16.8l1.6 1.6M5.6 18.4l1.6-1.6M16.8 7.2l1.6-1.6"
                />
              </svg>
              <!-- 月亮：黑夜主题时显示 -->
              <svg class="theme-icon theme-icon-moon" viewBox="0 0 24 24" fill="currentColor">
                <path
                  d="M20.2 14.2A7.6 7.6 0 0 1 9.8 3.8 7.8 7.8 0 1 0 20.2 14.2Z"
                />
              </svg>
            </span>
          </button>
        </div>
      </aside>

      <main class="shell-content">
        <RouterView />
      </main>
    </div>

    <footer class="shell-bottom">
      <p class="shell-meta">{{ footerLine }}</p>
    </footer>
  </div>
</template>
