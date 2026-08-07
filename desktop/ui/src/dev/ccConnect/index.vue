<script setup lang="ts">
/**
 * CC Connect 工作区：使用文档 + 装更卸输出。
 * 概览区：安装 / 更新 / 卸载。
 */
import InstallOutputWorkspace from '../shared/InstallOutputWorkspace.vue'

defineProps<{ embedded?: boolean }>()

const docs = [
  {
    label: '使用文档',
    url: 'https://github.com/chenhg5/cc-connect/blob/main/docs/usage.md',
  },
]
</script>

<template>
  <InstallOutputWorkspace
    :embedded="embedded"
    title="CC Connect"
    :docs="docs"
  />
</template>
