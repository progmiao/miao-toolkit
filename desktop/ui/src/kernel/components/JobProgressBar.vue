<script setup lang="ts">
/**
 * 任务进度条（封闭）：只显示 statusText + 0～100 整数进度。
 * 右侧百分比列宽按「100%」固定，避免位数变化带动进度条宽度。
 */
import { computed } from 'vue'

const props = withDefaults(
  defineProps<{
    /** 0～100，组件内取整并钳制 */
    progress?: number
    /** 当前执行内容 / 状态文案 */
    statusText?: string
  }>(),
  {
    progress: 0,
    statusText: '',
  },
)

const pct = computed(() => {
  const n = Number(props.progress)
  if (!Number.isFinite(n)) return 0
  return Math.round(Math.min(100, Math.max(0, n)))
})

const labelText = computed(() => {
  const t = (props.statusText ?? '').trim()
  return t || '就绪'
})

const isRunning = computed(() => pct.value > 0 && pct.value < 100)
const isDone = computed(() => pct.value >= 100)
</script>

<template>
  <div class="progress-wrap">
    <div class="progress-label">
      <span class="progress-status" :title="labelText">{{ labelText }}</span>
    </div>
    <div class="progress-track-row">
      <div
        class="progress-bar"
        :class="{ 'is-busy': isRunning, 'is-done': isDone }"
        role="progressbar"
        :aria-valuenow="pct"
        aria-valuemin="0"
        aria-valuemax="100"
        :aria-label="labelText"
      >
        <i class="progress-fill" :style="{ width: pct + '%' }">
          <span class="progress-sheen" aria-hidden="true" />
        </i>
      </div>
      <span class="progress-pct">{{ pct }}%</span>
    </div>
  </div>
</template>

<style scoped>
.progress-wrap {
  flex: 0 0 auto;
  box-sizing: border-box;
  width: 100%;
  max-width: 100%;
  padding: 0.4rem 0.65rem 0.45rem;
  border-radius: 0.55rem;
  border: 1px solid color-mix(in srgb, var(--line) 80%, transparent);
  background: color-mix(in srgb, var(--panel) 42%, transparent);
  min-width: 0;
  overflow: hidden;
}

.progress-label {
  display: flex;
  align-items: center;
  margin-bottom: 0.28rem;
  min-height: 1em;
  min-width: 0;
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
  gap: 0.45rem;
  min-width: 0;
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

.progress-pct {
  flex: 0 0 4ch;
  flex-shrink: 0;
  width: 4ch;
  max-width: 4ch;
  box-sizing: content-box;
  text-align: right;
  font-size: 0.68rem;
  font-weight: 700;
  font-family: var(--font-mono);
  font-variant-numeric: tabular-nums;
  color: color-mix(in srgb, var(--accent) 85%, var(--ink));
  letter-spacing: 0;
  line-height: 1;
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
</style>
