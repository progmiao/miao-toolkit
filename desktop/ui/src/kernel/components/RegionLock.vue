<script setup lang="ts">
/**
 * 片区锁定：盖一层遮罩挡住点击/焦点，子树不必逐个 disabled。
 */
withDefaults(
  defineProps<{
    active?: boolean
    /** 悬停提示 */
    title?: string
    /**
     * 遮罩样式：frost=半透明底（列表等）；clear=仅挡点击（概览按钮已有 disabled，避免长方形阴影）。
     */
    mask?: 'frost' | 'clear'
  }>(),
  {
    active: false,
    title: '任务进行中，请先终止',
    mask: 'frost',
  },
)
</script>

<template>
  <div class="region-lockable" :class="{ 'is-locked': active }">
    <div
      v-if="active"
      class="region-lock-mask"
      :class="{ 'region-lock-mask--clear': mask === 'clear' }"
      :title="title"
      aria-hidden="true"
    />
    <slot />
  </div>
</template>

<style scoped>
.region-lockable {
  position: relative;
  min-width: 0;
  min-height: 0;
}

.region-lock-mask {
  position: absolute;
  inset: 0;
  z-index: 30;
  cursor: not-allowed;
  border-radius: inherit;
  background: color-mix(in srgb, var(--panel, #1a1a1a) 22%, transparent);
}

.region-lock-mask--clear {
  background: transparent;
}
</style>
