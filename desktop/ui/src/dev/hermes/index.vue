<script setup lang="ts">
/**
 * Hermes 工作区：默认输出（装更卸记录）。
 */
import InstallOutputWorkspace from '../shared/InstallOutputWorkspace.vue'

defineProps<{ embedded?: boolean }>()
</script>

<template>
  <InstallOutputWorkspace
    :embedded="embedded"
    title="Hermes"
  />
</template>
