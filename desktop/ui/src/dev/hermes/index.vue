<script setup lang="ts">
/**
 * Hermes 工作区：文档入口 + 装更卸输出。
 */
import InstallOutputWorkspace from '../shared/InstallOutputWorkspace.vue'

defineProps<{ embedded?: boolean }>()

const docs = [
  { label: '订阅', url: 'https://portal.nousresearch.com/' },
  { label: '官网', url: 'https://hermes-agent.nousresearch.com/' },
  { label: '源码', url: 'https://github.com/NousResearch/hermes-agent' },
]
</script>

<template>
  <InstallOutputWorkspace
    :embedded="embedded"
    title="Hermes"
    :docs="docs"
  />
</template>
