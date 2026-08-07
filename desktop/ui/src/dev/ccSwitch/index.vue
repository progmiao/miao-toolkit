<script setup lang="ts">
/**
 * CC Switch 工作区：使用文档 + 装更卸输出。
 * 概览区：安装 / 更新 / 卸载。
 */
import InstallOutputWorkspace from '../shared/InstallOutputWorkspace.vue'

defineProps<{ embedded?: boolean }>()

const docs = [
  {
    label: '安装指南',
    url: 'https://github.com/farion1231/cc-switch/blob/main/docs/user-manual/zh/1-getting-started/1.2-installation.md',
  },
  {
    label: '使用文档',
    url: 'https://github.com/farion1231/cc-switch/blob/main/docs/user-manual/zh/README.md',
  },
]
</script>

<template>
  <InstallOutputWorkspace
    :embedded="embedded"
    title="CC Switch"
    :docs="docs"
  />
</template>
