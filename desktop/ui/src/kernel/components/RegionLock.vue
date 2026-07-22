<script setup lang="ts">
/**
 * 片区锁定：盖一层遮罩挡住点击/焦点，子树不必逐个 disabled。
 */
withDefaults(
  defineProps<{
    active?: boolean
    /** 悬停提示 */
    title?: string
  }>(),
  {
    active: false,
    title: '任务进行中，请先终止',
  },
)
</script>

<template>
  <div class="region-lockable" :class="{ 'is-locked': active }">
    <div
      v-if="active"
      class="region-lock-mask"
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
</style>
