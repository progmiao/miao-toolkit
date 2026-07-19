<script setup lang="ts">
/**
 * 任务控制台：进度条 + 终端日志。
 * 空闲且无日志时不渲染，避免右侧常驻 IDLE / 占位块。
 */
import { computed } from 'vue'

const props = defineProps<{
  /** 0–100 */
  progress: number
  /** 日志行 */
  logs: string[]
  /** 是否忙碌 */
  busy?: boolean
  /** 有日志时的空行占位（通常不用） */
  placeholder?: string
}>()

/** 有任务进行中或已有日志时才显示。 */
const visible = computed(() => Boolean(props.busy) || props.logs.length > 0)
</script>

<template>
  <div v-if="visible" class="job-console">
    <div class="progress-wrap">
      <div class="progress-label">
        <span>{{ busy ? 'SYNC' : 'DONE' }}</span>
        <span>{{ Math.min(100, Math.max(0, progress)) }}%</span>
      </div>
      <div class="progress-bar" role="progressbar" :aria-valuenow="progress" aria-valuemin="0" aria-valuemax="100">
        <i :style="{ width: Math.min(100, Math.max(0, progress)) + '%' }" />
      </div>
    </div>
    <pre class="log">{{ logs.length ? logs.join('\n') : (placeholder || '') }}</pre>
  </div>
</template>

<style scoped>
.job-console {
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
  min-height: 0;
  flex: 1;
}
.progress-wrap {
  flex: 0 0 auto;
}
.log {
  flex: 1;
  min-height: 10rem;
}
</style>
