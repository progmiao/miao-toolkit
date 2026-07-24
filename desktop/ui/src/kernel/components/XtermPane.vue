<script setup lang="ts">
/**
 * 命令窗 xterm：全文重绘；超长行不换行，容器底部横向滚动。
 * 空状态用 HTML 占位（不写进终端缓冲，避免中文折行/重复）。
 */
import { FitAddon } from '@xterm/addon-fit'
import { Terminal } from '@xterm/xterm'
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import '@xterm/xterm/css/xterm.css'

/** 过宽行保护：避免极端粘连文本拖垮渲染。 */
const MAX_COLS = 480

const props = withDefaults(
  defineProps<{
    chunks?: string[]
    placeholder?: string
    busy?: boolean
    coalesceFetchingProgress?: boolean
  }>(),
  {
    chunks: () => [],
    placeholder: '',
    busy: false,
    coalesceFetchingProgress: false,
  },
)

const hostEl = ref<HTMLElement | null>(null)
let term: Terminal | null = null
let fit: FitAddon | null = null
let ro: ResizeObserver | null = null
let lastKey: string | null = null
let hadSize = false

function contentText() {
  return (props.chunks ?? []).join('')
}

const showPlaceholder = computed(() => !contentText() && Boolean(props.placeholder))

function stripAnsi(s: string): string {
  return s.replace(/\u001b\[[0-9;?]*[ -/]*[@-~]/g, '')
}

/** 估算终端列宽（全角约 2 列）。 */
function visualCols(line: string): number {
  let n = 0
  for (const ch of line) {
    const cp = ch.codePointAt(0) ?? 0
    n += cp > 0xff ? 2 : 1
  }
  return n
}

function maxLineCols(text: string): number {
  let max = 0
  for (const line of stripAnsi(text).split(/\r?\n/)) {
    max = Math.max(max, visualCols(line))
  }
  return max
}

/**
 * 行数贴合可视高度；列数取「可视宽度」与「最长行」的较大值，避免换行。
 */
function fitAndWiden(forText?: string) {
  if (!term || !hostEl.value) return
  try {
    fit?.fit()
  } catch {
    /* ignore */
  }
  const viewCols = term.cols
  const viewRows = term.rows
  const text = forText ?? contentText()
  if (!text) return
  const need = Math.min(MAX_COLS, Math.max(viewCols, maxLineCols(text) || 1, 2))
  if (need !== viewCols) {
    try {
      term.resize(need, viewRows)
    } catch {
      /* ignore */
    }
  }
}

function paint(text: string, force = false) {
  if (!term) return
  const key = text ? `t:${text}` : 'empty'
  if (!force && key === lastKey) return
  term.reset()
  if (text) {
    fitAndWiden(text)
    term.write(text)
  } else {
    fitAndWiden()
  }
  lastKey = key
}

function sync(force = false) {
  paint(contentText(), force)
}

onMounted(async () => {
  await nextTick()
  if (!hostEl.value) return

  term = new Terminal({
    convertEol: true,
    disableStdin: true,
    cursorBlink: false,
    fontSize: 12,
    fontFamily: 'Cascadia Mono, Consolas, monospace',
    theme: {
      background: '#0c0c0c',
      foreground: '#cccccc',
      cursor: '#cccccc',
      selectionBackground: 'rgba(255,255,255,0.25)',
    },
    scrollback: 2000,
    allowProposedApi: true,
  })
  fit = new FitAddon()
  term.loadAddon(fit)
  term.open(hostEl.value)
  fitAndWiden()
  sync(true)

  ro = new ResizeObserver(() => {
    const el = hostEl.value
    const w = el?.clientWidth ?? 0
    const h = el?.clientHeight ?? 0
    const ready = w > 8 && h > 8
    const text = contentText()
    if (text) fitAndWiden(text)
    else fitAndWiden()
    if (ready && !hadSize) {
      hadSize = true
      sync(true)
    } else if (!ready) {
      hadSize = false
    }
  })
  ro.observe(hostEl.value)
})

onBeforeUnmount(() => {
  ro?.disconnect()
  ro = null
  term?.dispose()
  term = null
  fit = null
  lastKey = null
  hadSize = false
})

watch(
  () => props.chunks,
  () => sync(),
  { deep: true },
)
</script>

<template>
  <div class="xterm-wrap">
    <div ref="hostEl" class="xterm-host" :class="{ 'is-empty': showPlaceholder }" />
    <div v-if="showPlaceholder" class="xterm-placeholder" aria-hidden="true">
      {{ placeholder }}
    </div>
  </div>
</template>

<style scoped>
.xterm-wrap {
  position: relative;
  flex: 1;
  min-height: 0;
  width: 100%;
  height: 100%;
  background: #0c0c0c;
}

.xterm-host {
  width: 100%;
  height: 100%;
  padding: 0.35rem 0.5rem;
  overflow-x: auto;
  overflow-y: hidden;
  background: #0c0c0c;
  scrollbar-width: thin;
  scrollbar-color: color-mix(in srgb, var(--accent, #3dd6c6) 70%, #666) #1a1a1a;
}

.xterm-host.is-empty :deep(.xterm) {
  opacity: 0;
  pointer-events: none;
}

.xterm-placeholder {
  position: absolute;
  inset: 0;
  z-index: 1;
  padding: 0.35rem 0.5rem;
  color: #808080;
  font-size: 12px;
  font-family: Cascadia Mono, Consolas, monospace;
  line-height: 1.45;
  white-space: pre-wrap;
  word-break: break-word;
  pointer-events: none;
  user-select: none;
}

.xterm-host :deep(.xterm) {
  height: 100%;
}

.xterm-host :deep(.xterm-viewport) {
  overflow-y: auto !important;
  overflow-x: hidden !important;
  scrollbar-width: thin;
  scrollbar-color: color-mix(in srgb, var(--accent, #3dd6c6) 70%, #666) #1a1a1a;
}

.xterm-host::-webkit-scrollbar,
.xterm-host :deep(.xterm-viewport)::-webkit-scrollbar {
  width: var(--scroll-size, 7px);
  height: var(--scroll-size, 7px);
}

.xterm-host::-webkit-scrollbar-track,
.xterm-host :deep(.xterm-viewport)::-webkit-scrollbar-track {
  background: #1a1a1a;
  margin: 2px;
  border-radius: 999px;
}

.xterm-host::-webkit-scrollbar-thumb,
.xterm-host :deep(.xterm-viewport)::-webkit-scrollbar-thumb {
  border-radius: 999px;
  border: 2px solid transparent;
  background:
    linear-gradient(
      180deg,
      color-mix(in srgb, var(--accent) 88%, #fff 12%),
      color-mix(in srgb, var(--accent-2, var(--accent)) 55%, var(--accent))
    )
    padding-box,
    linear-gradient(
      165deg,
      color-mix(in srgb, #fff 28%, transparent),
      transparent 42%,
      color-mix(in srgb, var(--accent) 35%, transparent)
    )
    border-box;
  background-clip: padding-box, border-box;
  box-shadow:
    0 0 10px var(--scroll-glow, color-mix(in srgb, var(--accent) 45%, transparent)),
    inset 0 1px 0 color-mix(in srgb, #fff 35%, transparent);
}

.xterm-host::-webkit-scrollbar-thumb:hover,
.xterm-host :deep(.xterm-viewport)::-webkit-scrollbar-thumb:hover {
  background:
    linear-gradient(
      180deg,
      color-mix(in srgb, var(--accent) 95%, #fff 18%),
      color-mix(in srgb, var(--accent-2, var(--accent)) 70%, var(--accent))
    )
    padding-box,
    linear-gradient(
      165deg,
      color-mix(in srgb, #fff 40%, transparent),
      transparent 40%,
      color-mix(in srgb, var(--accent) 45%, transparent)
    )
    border-box;
  background-clip: padding-box, border-box;
}

.xterm-host::-webkit-scrollbar-corner,
.xterm-host :deep(.xterm-viewport)::-webkit-scrollbar-corner {
  background: #0c0c0c;
}
</style>
