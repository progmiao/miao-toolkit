<script setup lang="ts">
/**
 * 工具 Logo：按工具 id 显示色块字标（卡片 / 列表共用）。
 */
import { computed } from 'vue'
import { TOOL_LOGOS } from '../bridge/toolMeta'

const props = defineProps<{
  /** 工具 id */
  toolId: string
  /** 可选显示名首字回退 */
  name?: string
  /** 尺寸：sm | md | lg */
  size?: 'sm' | 'md' | 'lg'
}>()

const meta = computed(() => {
  const hit = TOOL_LOGOS[props.toolId]
  if (hit) return hit
  const letter = (props.name ?? props.toolId).slice(0, 1).toUpperCase()
  let hue = 0
  for (let i = 0; i < props.toolId.length; i++) hue = (hue + props.toolId.charCodeAt(i) * 17) % 360
  return { letter, hue }
})

const sizeClass = computed(() => props.size ?? 'md')
</script>

<template>
  <span
    class="tool-logo"
    :class="sizeClass"
    :style="{ '--logo-hue': String(meta.hue) }"
    aria-hidden="true"
  >
    {{ meta.letter }}
  </span>
</template>

<style scoped>
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
.tool-logo.sm {
  width: 1.85rem;
  height: 1.85rem;
  font-size: 0.75rem;
  border-radius: 0.4rem;
}
.tool-logo.md {
  width: 2.75rem;
  height: 2.75rem;
  font-size: 1.1rem;
  border-radius: 0.65rem;
}
.tool-logo.lg {
  width: 3.4rem;
  height: 3.4rem;
  font-size: 1.35rem;
  border-radius: 0.75rem;
}
</style>
