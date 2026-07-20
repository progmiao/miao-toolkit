<script setup lang="ts">
/**
 * 任务控制台：上方进度 + 状态日志，下方嵌入式命令窗口（PowerShell 输出）。
 * 空闲且无内容时不渲染。
 */
import { computed, nextTick, ref, watch } from 'vue'

const props = defineProps<{
  /** 0–100 */
  progress: number
  /** 状态日志行（上） */
  logs: string[]
  /** 命令窗口行（下）；未传则与 logs 共用兼容旧调用 */
  consoleLines?: string[]
  /** 是否忙碌 */
  busy?: boolean
  /** 命令窗空占位 */
  placeholder?: string
}>()

const cmdEl = ref<HTMLElement | null>(null)

const consoleText = computed(() => {
  const lines = props.consoleLines ?? props.logs
  if (lines.length) return lines.join('\n')
  return props.placeholder || ''
})

const visible = computed(
  () =>
    Boolean(props.busy) ||
    props.logs.length > 0 ||
    (props.consoleLines?.length ?? 0) > 0,
)

watch(
  () => [props.consoleLines?.length, props.logs.length, props.busy],
  async () => {
    await nextTick()
    if (cmdEl.value) cmdEl.value.scrollTop = cmdEl.value.scrollHeight
  },
)
</script>

<template>
  <div v-if="visible" class="job-console">
    <div class="job-top">
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
      <pre v-if="logs.length" class="status-log">{{ logs.join('\n') }}</pre>
    </div>

    <div class="cmd-panel">
      <div class="cmd-title">命令窗口</div>
      <pre ref="cmdEl" class="cmd-log">{{ consoleText }}</pre>
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

.job-top {
  flex: 0 0 auto;
  display: flex;
  flex-direction: column;
  gap: 0.45rem;
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

.status-log {
  margin: 0;
  padding: 0.55rem 0.7rem;
  max-height: 5.5rem;
  overflow: auto;
  border-radius: 0.55rem;
  border: 1px solid color-mix(in srgb, var(--line) 80%, transparent);
  background: color-mix(in srgb, var(--panel) 38%, transparent);
  color: var(--ink);
  font-family: var(--font-mono);
  font-size: 0.75rem;
  line-height: 1.45;
  white-space: pre-wrap;
}

.cmd-panel {
  flex: 1;
  min-height: 0;
  display: flex;
  flex-direction: column;
  border-radius: 0.65rem;
  border: 1px solid color-mix(in srgb, var(--accent) 28%, transparent);
  background: #05080f;
  overflow: hidden;
  box-shadow: inset 0 0 28px rgba(0, 40, 60, 0.35);
}

.cmd-title {
  flex: 0 0 auto;
  padding: 0.35rem 0.7rem;
  font-size: 0.68rem;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  color: color-mix(in srgb, #9fe8f0 70%, #fff);
  border-bottom: 1px solid color-mix(in srgb, var(--accent) 22%, transparent);
  background: color-mix(in srgb, #0a1520 80%, transparent);
  font-family: var(--font-mono);
}

.cmd-log {
  flex: 1;
  min-height: 9rem;
  margin: 0;
  padding: 0.75rem 0.8rem;
  overflow: auto;
  color: #9fe8f0;
  font-family: var(--font-mono);
  font-size: 0.76rem;
  line-height: 1.45;
  white-space: pre-wrap;
  word-break: break-word;
}
</style>
