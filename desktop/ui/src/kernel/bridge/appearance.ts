/**
 * 外观配置：
 * - 壁纸选图与间隔全局统一（勾选 1 张固定，≥2 张轮播）。
 * - 磨砂、栏位色、透明度、光效等按白天/黑夜分别保存。
 */
import { post } from './bus'

/** 主题模式。 */
export type ThemeMode = 'light' | 'dark'

/**
 * 全局壁纸配置（白天/黑夜共用）。
 * 勾选数量决定行为：1 张固定，≥2 张按间隔轮播。
 */
export type WallpaperConfig = {
  /** 勾选的壁纸 id（至少 1 张） */
  wallpaperIds: string[]
  /** 轮播间隔（秒）；仅勾选 ≥2 张时生效 */
  wallpaperIntervalSec: number
}

/** 单一主题下的可调外观参数（不含壁纸选图）。 */
export type AppearanceThemeConfig = {
  /** 壁纸不透明度 0–1 */
  wallpaperOpacity: number
  /** 壁纸上的压暗/提亮罩 0–1 */
  overlayStrength: number
  /** 左/顶/底栏玻璃不透明度 0–1 */
  chromeOpacity: number
  /** 栏位底色 tint（hex） */
  chromeColor: string
  /** 磨砂模糊半径 px */
  frostBlur: number
  /** 磨砂饱和度倍率 */
  frostSaturation: number
  /** 磨砂内高光 tint（hex） */
  frostTint: string
  /** 科技光效强度 0–1 */
  fxIntensity: number
}

/** 完整外观状态。 */
export type AppearanceState = {
  mode: ThemeMode
  /** 全局壁纸（与 mode 无关） */
  wallpaper: WallpaperConfig
  light: AppearanceThemeConfig
  dark: AppearanceThemeConfig
}

/** 预制壁纸条目（打包在 public/wallpapers）。 */
export type WallpaperPreset = {
  id: string
  name: string
  src: string
}

/** 壁纸资源：原图导入后压缩为 JPEG（最长边 ≤2560，保持比例不裁切）。 */
export const WALLPAPER_PRESETS: WallpaperPreset[] = [
  { id: 'mecha-01', name: '机甲 01', src: '/wallpapers/mecha-01.jpg' },
  { id: 'mecha-02', name: '机甲 02', src: '/wallpapers/mecha-02.jpg' },
  { id: 'mecha-03', name: '机甲 03', src: '/wallpapers/mecha-03.jpg' },
  { id: 'mecha-04', name: '机甲 04', src: '/wallpapers/mecha-04.jpg' },
  { id: 'mecha-05', name: '机甲 05', src: '/wallpapers/mecha-05.jpg' },
  { id: 'mecha-06', name: '机甲 06', src: '/wallpapers/mecha-06.jpg' },
  { id: 'mecha-07', name: '机甲 07', src: '/wallpapers/mecha-07.jpg' },
  { id: 'mecha-08', name: '机甲 08', src: '/wallpapers/mecha-08.jpg' },
  { id: 'mecha-09', name: '机甲 09', src: '/wallpapers/mecha-09.jpg' },
  { id: 'mecha-10', name: '机甲 10', src: '/wallpapers/mecha-10.jpg' },
  { id: 'mecha-11', name: '机甲 11', src: '/wallpapers/mecha-11.jpg' },
  { id: 'mecha-12', name: '机甲 12', src: '/wallpapers/mecha-12.jpg' },
  { id: 'mecha-13', name: '机甲 13', src: '/wallpapers/mecha-13.jpg' },
  { id: 'mecha-14', name: '机甲 14', src: '/wallpapers/mecha-14.jpg' },
  { id: 'mecha-15', name: '机甲 15', src: '/wallpapers/mecha-15.jpg' },
  { id: 'mecha-16', name: '机甲 16', src: '/wallpapers/mecha-16.jpg' },
  { id: 'mecha-17', name: '机甲 17', src: '/wallpapers/mecha-17.jpg' },
  { id: 'mecha-18', name: '机甲 18', src: '/wallpapers/mecha-18.jpg' },
  { id: 'mecha-19', name: '机甲 19', src: '/wallpapers/mecha-19.jpg' },
  { id: 'mecha-20', name: '机甲 20', src: '/wallpapers/mecha-20.jpg' },
  { id: 'mecha-21', name: '机甲 21', src: '/wallpapers/mecha-21.jpg' },
  { id: 'mecha-22', name: '机甲 22', src: '/wallpapers/mecha-22.jpg' },
  { id: 'mecha-23', name: '机甲 23', src: '/wallpapers/mecha-23.jpg' },
  { id: 'mecha-24', name: '机甲 24', src: '/wallpapers/mecha-24.jpg' },
  { id: 'mecha-25', name: '机甲 25', src: '/wallpapers/mecha-25.jpg' },
]

/** 壁纸列表别名（全选等）。 */
export const CAROUSEL_WALLPAPERS = WALLPAPER_PRESETS

const STORAGE_KEY = 'miao-appearance'
const THEME_KEY = 'miao-theme'
const VALID_IDS = new Set(WALLPAPER_PRESETS.map((p) => p.id))
/** 空列表或非法 id 时的回落。 */
const FALLBACK_WALLPAPER_ID = 'mecha-01'

type Listener = (state: AppearanceState) => void
const listeners = new Set<Listener>()

/** 订阅外观变更。 */
export function subscribeAppearance(fn: Listener): () => void {
  listeners.add(fn)
  return () => listeners.delete(fn)
}

/**
 * 清洗勾选列表：去重、校验；过滤已废弃的 none；空则回落默认图。
 * @param ids - 原始 id 列表
 */
export function sanitizeWallpaperIds(ids: string[] | undefined): string[] {
  if (!Array.isArray(ids) || ids.length === 0) return [FALLBACK_WALLPAPER_ID]
  const seen = new Set<string>()
  const out: string[] = []
  for (const id of ids) {
    if (id === 'none' || !VALID_IDS.has(id) || seen.has(id)) continue
    seen.add(id)
    out.push(id)
  }
  return out.length > 0 ? out : [FALLBACK_WALLPAPER_ID]
}

/** 全局壁纸默认：单张固定。 */
export function defaultWallpaperConfig(): WallpaperConfig {
  return {
    wallpaperIds: ['mecha-01'],
    wallpaperIntervalSec: 30,
  }
}

/** 白天默认（磨砂等，不含壁纸选图）。 */
export function defaultLightTheme(): AppearanceThemeConfig {
  return {
    wallpaperOpacity: 0.72,
    overlayStrength: 0.28,
    chromeOpacity: 0.36,
    chromeColor: '#e8eef6',
    frostBlur: 26,
    frostSaturation: 1.45,
    frostTint: '#1a7a88',
    fxIntensity: 0.55,
  }
}

/** 黑夜默认（磨砂等，不含壁纸选图）。 */
export function defaultDarkTheme(): AppearanceThemeConfig {
  return {
    wallpaperOpacity: 0.85,
    overlayStrength: 0.42,
    chromeOpacity: 0.32,
    chromeColor: '#0a101c',
    frostBlur: 30,
    frostSaturation: 1.6,
    frostTint: '#6ec9d6',
    fxIntensity: 0.75,
  }
}

/** 工厂默认。 */
export function createDefaultAppearance(): AppearanceState {
  return {
    mode: 'light',
    wallpaper: defaultWallpaperConfig(),
    light: defaultLightTheme(),
    dark: defaultDarkTheme(),
  }
}

/**
 * 从旧版字段拼出 wallpaperIds。
 * @param raw - 可能含 wallpaperIds / Mode / Id / CarouselIds
 */
function migrateWallpaperIds(raw: Record<string, unknown>): string[] | undefined {
  if (Array.isArray(raw.wallpaperIds)) return raw.wallpaperIds as string[]
  const mode = raw.wallpaperMode === 'carousel' ? 'carousel' : 'single'
  if (mode === 'carousel' && Array.isArray(raw.wallpaperCarouselIds)) {
    return raw.wallpaperCarouselIds as string[]
  }
  if (typeof raw.wallpaperId === 'string' && raw.wallpaperId) {
    return [raw.wallpaperId]
  }
  if (Array.isArray(raw.wallpaperCarouselIds) && (raw.wallpaperCarouselIds as string[]).length) {
    return raw.wallpaperCarouselIds as string[]
  }
  return undefined
}

/**
 * 规范化全局壁纸。
 * @param partial - 部分字段（兼容旧版 mode/id/carousel）
 * @param fallback - 缺省
 */
function normalizeWallpaper(
  partial: Record<string, unknown> | Partial<WallpaperConfig> | undefined,
  fallback: WallpaperConfig,
): WallpaperConfig {
  const src = (partial ?? {}) as Record<string, unknown>
  const ids = sanitizeWallpaperIds(migrateWallpaperIds(src) ?? fallback.wallpaperIds)
  const sec = Number(src.wallpaperIntervalSec ?? fallback.wallpaperIntervalSec)
  return {
    wallpaperIds: ids,
    wallpaperIntervalSec: Number.isFinite(sec) ? Math.min(600, Math.max(5, Math.round(sec))) : 30,
  }
}

/**
 * 从旧版「写在 light/dark 里的壁纸字段」迁移为全局 wallpaper。
 * @param o - 原始 JSON 对象
 * @param fallback - 默认壁纸
 */
function migrateWallpaperFromLegacy(
  o: Record<string, unknown>,
  fallback: WallpaperConfig,
): WallpaperConfig {
  const top = o.wallpaper
  if (top && typeof top === 'object') {
    return normalizeWallpaper(top as Record<string, unknown>, fallback)
  }
  const mode = o.mode === 'dark' ? 'dark' : 'light'
  const themeRaw = (mode === 'dark' ? o.dark : o.light) as Record<string, unknown> | undefined
  const lightRaw = o.light as Record<string, unknown> | undefined
  const src = themeRaw ?? lightRaw
  if (!src) return { ...fallback, wallpaperIds: [...fallback.wallpaperIds] }
  return normalizeWallpaper(src, fallback)
}

/** 规范化单主题配置（忽略遗留壁纸字段）。 */
function normalizeTheme(
  partial: Partial<AppearanceThemeConfig> | undefined,
  fallback: AppearanceThemeConfig,
): AppearanceThemeConfig {
  const src = partial ?? {}
  return {
    wallpaperOpacity:
      typeof src.wallpaperOpacity === 'number' ? src.wallpaperOpacity : fallback.wallpaperOpacity,
    overlayStrength:
      typeof src.overlayStrength === 'number' ? src.overlayStrength : fallback.overlayStrength,
    chromeOpacity: typeof src.chromeOpacity === 'number' ? src.chromeOpacity : fallback.chromeOpacity,
    chromeColor: typeof src.chromeColor === 'string' ? src.chromeColor : fallback.chromeColor,
    frostBlur: typeof src.frostBlur === 'number' ? src.frostBlur : fallback.frostBlur,
    frostSaturation:
      typeof src.frostSaturation === 'number' ? src.frostSaturation : fallback.frostSaturation,
    frostTint: typeof src.frostTint === 'string' ? src.frostTint : fallback.frostTint,
    fxIntensity: typeof src.fxIntensity === 'number' ? src.fxIntensity : fallback.fxIntensity,
  }
}

/** 合并缺省字段（兼容旧版把壁纸写在 light/dark 内）。 */
export function normalizeAppearance(raw: unknown): AppearanceState {
  const base = createDefaultAppearance()
  if (!raw || typeof raw !== 'object') return base
  const o = raw as Record<string, unknown>
  const mode = o.mode === 'dark' ? 'dark' : 'light'
  return {
    mode,
    wallpaper: migrateWallpaperFromLegacy(o, base.wallpaper),
    light: normalizeTheme(o.light as Partial<AppearanceThemeConfig> | undefined, base.light),
    dark: normalizeTheme(o.dark as Partial<AppearanceThemeConfig> | undefined, base.dark),
  }
}

/** 当前模式的磨砂等配置。 */
export function activeThemeConfig(state: AppearanceState): AppearanceThemeConfig {
  return state.mode === 'dark' ? state.dark : state.light
}

/** 壁纸路径。 */
export function wallpaperSrc(id: string): string {
  return WALLPAPER_PRESETS.find((p) => p.id === id)?.src ?? ''
}

/**
 * 解析当前应播放的壁纸队列（至少 1 张）。
 * 勾选 1 张固定；≥2 张按列表轮播。
 * @param wallpaper - 全局壁纸配置
 */
export function resolveWallpaperPlaylist(wallpaper: WallpaperConfig): string[] {
  return sanitizeWallpaperIds(wallpaper.wallpaperIds)
}

/**
 * 是否处于轮播（勾选 ≥2 张）。
 * @param wallpaper - 全局壁纸
 */
export function isWallpaperCarousel(wallpaper: WallpaperConfig): boolean {
  return resolveWallpaperPlaylist(wallpaper).length >= 2
}

/**
 * 写 CSS 变量（不含当前壁纸图，由图层 crossfade 控制）。
 * @param el - 壳元素
 * @param state - 外观状态
 */
export function applyAppearanceToElement(el: HTMLElement, state: AppearanceState) {
  const cfg = activeThemeConfig(state)
  el.dataset.theme = state.mode
  el.style.setProperty('--wallpaper-opacity', String(cfg.wallpaperOpacity))
  el.style.setProperty('--overlay-strength', String(cfg.overlayStrength))
  el.style.setProperty('--chrome-opacity', String(cfg.chromeOpacity))
  el.style.setProperty('--chrome-color', cfg.chromeColor)
  el.style.setProperty('--frost-blur', `${cfg.frostBlur}px`)
  el.style.setProperty('--frost-sat', String(cfg.frostSaturation))
  el.style.setProperty('--frost-tint', cfg.frostTint)
  el.style.setProperty('--fx-intensity', String(cfg.fxIntensity))
  document.documentElement.dataset.theme = state.mode
}

/** localStorage 读取。 */
export function loadAppearanceLocal(): AppearanceState {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (raw) return normalizeAppearance(JSON.parse(raw))
    const legacy = localStorage.getItem(THEME_KEY)
    const state = createDefaultAppearance()
    if (legacy === 'dark' || legacy === 'light') state.mode = legacy
    return state
  } catch {
    return createDefaultAppearance()
  }
}

/**
 * 持久化并广播。
 * @param state - 完整外观
 * @param syncHost - 是否推送宿主
 */
export function commitAppearance(state: AppearanceState, syncHost = true) {
  const normalized = normalizeAppearance(state)
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(normalized))
    localStorage.setItem(THEME_KEY, normalized.mode)
  } catch {
    /* ignore */
  }
  listeners.forEach((fn) => fn(normalized))
  if (syncHost) {
    post({ type: 'settings.set-appearance', appearance: normalized })
  }
}

/** 重置某一模式的磨砂等（不改全局壁纸）。 */
export function resetThemeConfig(mode: ThemeMode): AppearanceThemeConfig {
  return mode === 'dark' ? defaultDarkTheme() : defaultLightTheme()
}

/** 重置全局壁纸为默认。 */
export function resetWallpaperConfig(): WallpaperConfig {
  return defaultWallpaperConfig()
}
