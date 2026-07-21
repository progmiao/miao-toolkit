<script setup lang="ts">
/**
 * 任务控制台：顶部进度条 + 下方实时输出区。
 * - 进度条：整体任务进度（批量安装时由后端按任务数平分）。
 * - 上方文案：当前正在进行的任务。
 * - 同时有状态日志与 PowerShell 命令输出：左日志、右命令窗（或 stack 上下）。
 */
import { computed, nextTick, ref, watch } from 'vue'

const props = withDefaults(
  defineProps<{
    /** 0–100 整体进度 */
    progress: number
    /** 状态日志行（左栏 / 仅日志时整块） */
    logs: string[]
    /**
     * 命令窗口行（PowerShell 等）。
     * 未传则不启用命令通道：有日志时整块显示日志。
     * 传入后若同时有日志与命令内容，则左右分栏。
     */
    consoleLines?: string[]
    /** 是否忙碌 */
    busy?: boolean
    /** 命令窗空占位 */
    placeholder?: string
    /**
     * 分栏布局：
     * - horizontal（默认）：日志 | 命令窗 左右
     * - stack：进度下日志在上、命令窗在下（整列右侧用）
     */
    paneLayout?: 'horizontal' | 'stack'
    /** 空闲时是否仍显示（嵌入右侧栏时常开） */
    alwaysShow?: boolean
    /** 当前任务文案（进度条上方） */
    statusText?: string
  }>(),
  {
    busy: false,
    alwaysShow: false,
    statusText: '',
  },
)

const logEl = ref<HTMLElement | null>(null)
const cmdEl = ref<HTMLElement | null>(null)

const layoutStack = computed(() => props.paneLayout === 'stack')

/** 是否启用命令通道（父级传了 consoleLines）。 */
const commandEnabled = computed(() => props.consoleLines !== undefined)

/** 是否有状态日志内容。 */
const hasLogs = computed(() => props.logs.length > 0)

/** 是否有命令输出内容。 */
const hasConsole = computed(() => (props.consoleLines?.length ?? 0) > 0)

/**
 * 双栏：同时存在日志与命令输出（PowerShell 实时窗）。
 * stack 布局始终上下两块（可空）。
 */
const dualPane = computed(
  () => layoutStack.value || (hasLogs.value && hasConsole.value),
)

/** 展示左侧/整块日志面板。 */
const showLogPane = computed(
  () =>
    layoutStack.value ||
    dualPane.value ||
    (hasLogs.value && !hasConsole.value),
)

/** 展示右侧/整块命令面板。 */
const showCmdPane = computed(
  () =>
    layoutStack.value ||
    dualPane.value ||
    (!hasLogs.value && (hasConsole.value || commandEnabled.value)),
)

const consoleText = computed(() => {
  if (!commandEnabled.value) return ''
  const lines = props.consoleLines ?? []
  if (lines.length) return lines.join('\n')
  return props.placeholder || ''
})

const logText = computed(() => props.logs.join('\n'))

const visible = computed(
  () =>
    Boolean(props.alwaysShow) ||
    Boolean(props.busy) ||
    props.logs.length > 0 ||
    (props.consoleLines?.length ?? 0) > 0,
)

const labelText = computed(() => {
  const t = (props.statusText ?? '').trim()
  if (t) return t
  if (props.busy) return '执行中'
  return '就绪'
})

const fillWidth = computed(() => Math.min(100, Math.max(0, props.progress)))

async function scrollPanes() {
  await nextTick()
  if (logEl.value) logEl.value.scrollTop = logEl.value.scrollHeight
  if (cmdEl.value) cmdEl.value.scrollTop = cmdEl.value.scrollHeight
}

watch(
  () => [props.consoleLines?.length, props.logs.length, props.busy],
  () => {
    void scrollPanes()
  },
)
</script>

<template>
  <div v-if="visible" class="job-console">
    <div class="progress-wrap">
      <div class="progress-label">
        <span class="progress-status" :title="labelText">{{ labelText }}</span>
        <span v-if="busy || fillWidth > 0" class="progress-pct">{{ Math.round(fillWidth) }}%</span>
      </div>
      <div class="progress-track-row">
        <div
          class="progress-bar"
          :class="{ 'is-busy': busy, 'is-done': !busy && fillWidth >= 100 }"
          role="progressbar"
          :aria-valuenow="fillWidth"
          aria-valuemin="0"
          aria-valuemax="100"
          :aria-label="labelText"
        >
          <i class="progress-fill" :style="{ width: fillWidth + '%' }">
            <span class="progress-sheen" aria-hidden="true" />
          </i>
        </div>
      </div>
    </div>

    <div
      class="job-panes"
      :class="{
        'job-panes--dual': dualPane && !layoutStack,
        'job-panes--stack': layoutStack,
      }"
    >
      <div v-if="showLogPane" class="out-panel status-panel">
        <div class="out-title">实时日志</div>
        <pre ref="logEl" class="out-log status-log">{{ logText }}</pre>
      </div>

      <div v-if="showCmdPane" class="out-panel cmd-panel">
        <div class="out-title">命令窗口</div>
        <pre ref="cmdEl" class="out-log cmd-log">{{ consoleText }}</pre>
      </div>
    </div>
  </div>
</template>

<style scoped>
.job-console {
  display: flex;
  flex-direction: column;
  gap: 0.65rem;
  min-height: 0;
  flex: 1;
}

.progress-wrap {
  flex: 0 0 auto;
  padding: 0.4rem 0.65rem 0.45rem;
  border-radius: 0.55rem;
  border: 1px solid color-mix(in srgb, var(--line) 80%, transparent);
  background: color-mix(in srgb, var(--panel) 42%, transparent);
}

.progress-label {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  margin-bottom: 0.28rem;
  min-height: 1em;
}

.progress-status {
  min-width: 0;
  flex: 1;
  font-size: 0.72rem;
  letter-spacing: 0.04em;
  color: var(--muted);
  font-family: var(--font-mono);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.progress-pct {
  flex: 0 0 auto;
  font-size: 0.68rem;
  font-weight: 700;
  font-family: var(--font-mono);
  font-variant-numeric: tabular-nums;
  color: color-mix(in srgb, var(--accent) 85%, var(--ink));
  letter-spacing: 0.04em;
}

.progress-track-row {
  display: flex;
  align-items: center;
}

.progress-bar {
  position: relative;
  flex: 1;
  min-width: 0;
  height: 0.5rem;
  border-radius: 999px;
  background: color-mix(in srgb, var(--line) 50%, transparent);
  overflow: hidden;
  box-shadow: inset 0 1px 2px color-mix(in srgb, #000 18%, transparent);
}

.progress-fill {
  position: relative;
  display: block;
  height: 100%;
  border-radius: inherit;
  overflow: hidden;
  background: linear-gradient(
    90deg,
    color-mix(in srgb, var(--accent) 75%, #0ff),
    var(--accent),
    color-mix(in srgb, var(--accent-2, var(--accent)) 70%, var(--accent))
  );
  background-size: 200% 100%;
  box-shadow: 0 0 10px color-mix(in srgb, var(--glow, var(--accent)) 55%, transparent);
  transition: width 0.35s cubic-bezier(0.22, 1, 0.36, 1);
}

.progress-bar.is-busy .progress-fill {
  animation: progress-flow 1.6s linear infinite;
}

.progress-sheen {
  position: absolute;
  inset: 0;
  background: linear-gradient(
    105deg,
    transparent 0%,
    transparent 40%,
    color-mix(in srgb, #fff 45%, transparent) 50%,
    transparent 60%,
    transparent 100%
  );
  background-size: 220% 100%;
  opacity: 0;
  pointer-events: none;
}

.progress-bar.is-busy .progress-sheen {
  opacity: 1;
  animation: progress-sheen 1.4s ease-in-out infinite;
}

.progress-bar.is-done .progress-fill {
  animation: none;
  background-position: 0 0;
}

@keyframes progress-flow {
  to {
    background-position: 200% 0;
  }
}

@keyframes progress-sheen {
  0% {
    background-position: 100% 0;
  }
  100% {
    background-position: -100% 0;
  }
}

@media (prefers-reduced-motion: reduce) {
  .progress-fill {
    transition: none;
  }
  .progress-bar.is-busy .progress-fill,
  .progress-bar.is-busy .progress-sheen {
    animation: none;
  }
}

.job-panes {
  flex: 1;
  min-height: 0;
  display: grid;
  grid-template-columns: 1fr;
  gap: 0.65rem;
}

.job-panes--dual {
  grid-template-columns: 1fr 1fr;
}

.job-panes--stack {
  grid-template-columns: 1fr;
  grid-template-rows: minmax(0, 1fr) minmax(0, 1fr);
  height: 100%;
}

.job-panes--stack .out-panel {
  min-height: 0;
}

.job-panes--stack .out-log {
  min-height: 0;
}

.out-panel {
  min-height: 0;
  display: flex;
  flex-direction: column;
  border-radius: 0.65rem;
  overflow: hidden;
}

.status-panel {
  border: 1px solid color-mix(in srgb, var(--line) 80%, transparent);
  background: color-mix(in srgb, var(--panel) 38%, transparent);
}

.cmd-panel {
  border: 1px solid color-mix(in srgb, var(--accent) 28%, transparent);
  background: #05080f;
  box-shadow: inset 0 0 28px rgba(0, 40, 60, 0.35);
}

.out-title {
  flex: 0 0 auto;
  padding: 0.35rem 0.7rem;
  font-size: 0.68rem;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  font-family: var(--font-mono);
  border-bottom: 1px solid color-mix(in srgb, var(--line) 70%, transparent);
}

.status-panel .out-title {
  color: var(--muted);
  background: color-mix(in srgb, var(--panel) 50%, transparent);
}

.cmd-panel .out-title {
  color: color-mix(in srgb, #9fe8f0 70%, #fff);
  border-bottom-color: color-mix(in srgb, var(--accent) 22%, transparent);
  background: color-mix(in srgb, #0a1520 80%, transparent);
}

.out-log {
  flex: 1;
  min-height: 9rem;
  margin: 0;
  padding: 0.75rem 0.8rem;
  overflow: auto;
  font-family: var(--font-mono);
  font-size: 0.76rem;
  line-height: 1.45;
  white-space: pre-wrap;
  word-break: break-word;
}

.status-log {
  color: var(--ink);
}

.cmd-log {
  color: #9fe8f0;
}
</style>
