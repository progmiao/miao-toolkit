<script setup lang="ts">
/**
 * 任务控制台：顶部进度条 + 下方实时输出区。
 * - 进度条：当前单项任务进度。
 * - 右侧 xx/xx：整个任务集合进度（两位补零）。
 * - 上方文案：当前正在进行的任务。
 * - 同时有状态日志与 PowerShell 命令输出：左日志、右命令窗（或 stack 上下）。
 */
import { computed, nextTick, ref, watch } from 'vue'

const props = withDefaults(
  defineProps<{
    /** 0–100 单项进度 */
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
    /** 集合进度：当前项（从 0/1 起） */
    batchCurrent?: number
    /** 集合进度：总项数；0 表示不显示 xx/xx */
    batchTotal?: number
  }>(),
  {
    busy: false,
    alwaysShow: false,
    statusText: '',
    batchCurrent: 0,
    batchTotal: 0,
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

const showBatch = computed(() => (props.batchTotal ?? 0) > 0)

/** 两位补零（超过两位原样显示）。 */
function pad2(n: number) {
  const v = Math.max(0, Math.floor(n))
  return String(v).padStart(2, '0')
}

const batchLabel = computed(() => {
  if (!showBatch.value) return ''
  return `${pad2(props.batchCurrent ?? 0)}/${pad2(props.batchTotal ?? 0)}`
})

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
      </div>
      <div class="progress-track-row">
        <div
          class="progress-bar"
          role="progressbar"
          :aria-valuenow="progress"
          aria-valuemin="0"
          aria-valuemax="100"
          :aria-label="labelText"
        >
          <i :style="{ width: Math.min(100, Math.max(0, progress)) + '%' }" />
        </div>
        <span v-if="showBatch" class="progress-batch" :title="`集合进度 ${batchLabel}`">
          {{ batchLabel }}
        </span>
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

.progress-track-row {
  display: flex;
  align-items: center;
  gap: 0.55rem;
}

.progress-bar {
  flex: 1;
  min-width: 0;
  height: 0.45rem;
  border-radius: 999px;
  background: color-mix(in srgb, var(--line) 55%, transparent);
  overflow: hidden;
}

.progress-bar i {
  display: block;
  height: 100%;
  border-radius: inherit;
  background: linear-gradient(
    90deg,
    color-mix(in srgb, var(--accent) 70%, #0ff),
    var(--accent)
  );
  transition: width 0.2s ease;
}

.progress-batch {
  flex: 0 0 auto;
  font-size: 0.72rem;
  font-weight: 700;
  letter-spacing: 0.06em;
  font-family: var(--font-mono);
  font-variant-numeric: tabular-nums;
  color: var(--ink);
  min-width: 2.75rem;
  text-align: right;
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
