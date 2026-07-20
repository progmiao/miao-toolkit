<script setup lang="ts">
/**
 * 工具 Logo：按工具 id 显示色块字标（卡片 / 列表共用）。
 * 可选「有更新」角标：右上角脉冲光点特效。
 */
import { computed } from 'vue'
import { TOOL_LOGOS } from './toolMeta'

const props = withDefaults(
  defineProps<{
    /** 工具 id */
    toolId: string
    /** 可选显示名首字回退 */
    name?: string
    /** 尺寸：sm | md | lg */
    size?: 'sm' | 'md' | 'lg'
    /** 是否有更新：右上角动画角标 */
    updateAvailable?: boolean
  }>(),
  {
    size: 'md',
    updateAvailable: false,
  },
)

const meta = computed(() => {
  const hit = TOOL_LOGOS[props.toolId]
  if (hit) return hit
  const letter = (props.name ?? props.toolId).slice(0, 1).toUpperCase()
  let hue = 0
  for (let i = 0; i < props.toolId.length; i++) hue = (hue + props.toolId.charCodeAt(i) * 17) % 360
  return { letter, hue }
})

const sizeClass = computed(() => props.size)
</script>

<template>
  <span
    class="tool-logo-wrap"
    :class="sizeClass"
    :aria-label="updateAvailable ? '有可用更新' : undefined"
  >
    <span
      class="tool-logo"
      :class="sizeClass"
      :style="{ '--logo-hue': String(meta.hue) }"
      aria-hidden="true"
    >
      {{ meta.letter }}
    </span>
    <span
      v-if="updateAvailable"
      class="tool-logo-update"
      aria-hidden="true"
      title="有更新"
    >
      <span class="tool-logo-update-ring" />
      <span class="tool-logo-update-core" />
    </span>
  </span>
</template>

<style scoped>
.tool-logo-wrap {
  position: relative;
  display: inline-flex;
  flex-shrink: 0;
  vertical-align: middle;
}

.tool-logo {
  --logo-hue: 180;
  display: inline-grid;
  place-items: center;
  flex-shrink: 0;
  font-family: var(--font-display);
  font-weight: 700;
  letter-spacing: 0;
  color: #fff;
  background: linear-gradient(
    145deg,
    hsl(var(--logo-hue) 72% 42%),
    hsl(calc(var(--logo-hue) + 28) 68% 32%)
  );
  border: 1px solid color-mix(in srgb, hsl(var(--logo-hue) 70% 55%) 50%, transparent);
  box-shadow:
    0 0 16px color-mix(in srgb, hsl(var(--logo-hue) 80% 50%) 35%, transparent),
    inset 0 1px 0 rgba(255, 255, 255, 0.25);
  user-select: none;
}
.tool-logo.sm,
.tool-logo-wrap.sm .tool-logo {
  width: 1.85rem;
  height: 1.85rem;
  font-size: 0.75rem;
  border-radius: 0.4rem;
}
.tool-logo.md,
.tool-logo-wrap.md .tool-logo {
  width: 2.75rem;
  height: 2.75rem;
  font-size: 1.1rem;
  border-radius: 0.65rem;
}
.tool-logo.lg,
.tool-logo-wrap.lg .tool-logo {
  width: 3.4rem;
  height: 3.4rem;
  font-size: 1.35rem;
  border-radius: 0.75rem;
}

/**
 * 「有更新」角标：右上角霓虹脉冲点。
 */
.tool-logo-update {
  position: absolute;
  top: -0.12rem;
  right: -0.12rem;
  z-index: 2;
  width: 0.72rem;
  height: 0.72rem;
  pointer-events: none;
}
.tool-logo-wrap.sm .tool-logo-update {
  width: 0.58rem;
  height: 0.58rem;
  top: -0.08rem;
  right: -0.08rem;
}
.tool-logo-wrap.lg .tool-logo-update {
  width: 0.82rem;
  height: 0.82rem;
  top: -0.14rem;
  right: -0.14rem;
}
.tool-logo-update-ring,
.tool-logo-update-core {
  position: absolute;
  inset: 0;
  border-radius: 50%;
}
.tool-logo-update-ring {
  border: 1.5px solid color-mix(in srgb, var(--warn, #d97706) 85%, #fff);
  box-shadow: 0 0 8px color-mix(in srgb, var(--warn, #d97706) 70%, transparent);
  animation: logo-update-ring 1.8s ease-out infinite;
}
.tool-logo-update-core {
  inset: 18%;
  background: radial-gradient(
    circle at 35% 30%,
    #fff 0%,
    var(--warn, #fbbf24) 45%,
    color-mix(in srgb, var(--warn, #d97706) 90%, #b45309) 100%
  );
  box-shadow:
    0 0 10px color-mix(in srgb, var(--warn, #d97706) 75%, transparent),
    inset 0 1px 0 color-mix(in srgb, #fff 55%, transparent);
  animation: logo-update-core 1.4s ease-in-out infinite;
}
@keyframes logo-update-ring {
  0% {
    transform: scale(0.85);
    opacity: 0.95;
  }
  70% {
    transform: scale(1.85);
    opacity: 0;
  }
  100% {
    transform: scale(1.85);
    opacity: 0;
  }
}
@keyframes logo-update-core {
  0%,
  100% {
    transform: scale(1);
    filter: brightness(1);
  }
  50% {
    transform: scale(1.12);
    filter: brightness(1.2);
  }
}
@media (prefers-reduced-motion: reduce) {
  .tool-logo-update-ring,
  .tool-logo-update-core {
    animation: none;
  }
  .tool-logo-update-ring {
    opacity: 0.55;
    transform: scale(1.15);
  }
}
</style>
