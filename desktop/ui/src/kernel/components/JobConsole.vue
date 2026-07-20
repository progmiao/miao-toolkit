<script setup lang="ts">
/**
 * 任务控制台：顶部进度条 + 下方实时输出区。
 * - 同时有状态日志与 PowerShell 命令输出：左日志、右命令窗。
 * - 仅有日志：整块区域显示实时日志。
 * - 仅有命令输出：整块区域显示命令窗。
 * 空闲且无内容时不渲染。
 */
import { computed, nextTick, ref, watch } from 'vue'

const props = defineProps<{
  /** 0–100 */
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
}>()

const logEl = ref<HTMLElement | null>(null)
const cmdEl = ref<HTMLElement | null>(null)

/** 是否启用命令通道（父级传了 consoleLines）。 */
const commandEnabled = computed(() => props.consoleLines !== undefined)

/** 是否有状态日志内容。 */
const hasLogs = computed(() => props.logs.length > 0)

/** 是否有命令输出内容。 */
const hasConsole = computed(() => (props.consoleLines?.length ?? 0) > 0)

/**
 * 双栏：同时存在日志与命令输出（PowerShell 实时窗）。
 * 仅有日志时整块显示日志；仅有命令时整块显示命令窗。
 */
const dualPane = computed(() => hasLogs.value && hasConsole.value)

/** 展示左侧/整块日志面板。 */
const showLogPane = computed(() => dualPane.value || (hasLogs.value && !hasConsole.value))

/** 展示右侧/整块命令面板。 */
const showCmdPane = computed(
  () => dualPane.value || (!hasLogs.value && (hasConsole.value || commandEnabled.value)),
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
    Boolean(props.busy) ||
    props.logs.length > 0 ||
    (props.consoleLines?.length ?? 0) > 0,
)

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
        <span>{{ busy ? '执行中' : '完成' }}</span>
        <span>{{ Math.min(100, Math.max(0, progress)) }}%</span>
      </div>
      <div
        class="progress-bar"
        role="progressbar"
        :aria-valuenow="progress"
        aria-valuemin="0"
        aria-valuemax="100"
      >
        <i :style="{ width: Math.min(100, Math.max(0, progress)) + '%' }" />
      </div>
    </div>

    <div class="job-panes" :class="{ 'job-panes--dual': dualPane }">
      <!-- 双栏左侧 / 仅日志整块 -->
      <div v-if="showLogPane" class="out-panel status-panel">
        <div class="out-title">实时日志</div>
        <pre ref="logEl" class="out-log status-log">{{ logText }}</pre>
      </div>

      <!-- 双栏右侧 / 仅命令整块 -->
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
  padding: 0.55rem 0.7rem;
  border-radius: 0.55rem;
  border: 1px solid color-mix(in srgb, var(--line) 80%, transparent);
  background: color-mix(in srgb, var(--panel) 42%, transparent);
}

.progress-label {
  display: flex;
  justify-content: space-between;
  margin-bottom: 0.35rem;
  font-size: 0.72rem;
  letter-spacing: 0.06em;
  color: var(--muted);
  font-family: var(--font-mono);
}

.progress-bar {
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
