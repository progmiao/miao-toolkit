<script setup lang="ts">
/**
 * TerminalBuddy 工作区：文档入口 + 安装/更新/卸载输出。
 * 概览区保留安装操作；本区接管共用 JobConsole。
 */
import { inject, onMounted, onUnmounted } from 'vue'
import JobConsole from '@kernel/components/JobConsole.vue'
import { post, subscribe } from '@kernel/bridge/bus'
import { useShellTitle } from '@kernel/composables/useShellTitle'
import { DEV_WORKSPACE_OWNS_CONSOLE_KEY } from '../devPanelContext'
import { useDevPanelJob } from '../useDevPanelJob'

const props = defineProps<{
  /** 嵌在一级页 tool-workspace 时为 true。 */
  embedded?: boolean
}>()

useShellTitle(props.embedded ? '开发工具' : 'TerminalBuddy')

const workspaceOwnsConsole = inject(DEV_WORKSPACE_OWNS_CONSOLE_KEY, null)

const {
  outputEntries,
  progress,
  statusText,
  busy,
  consumeJobMessage,
  isShared,
} = useDevPanelJob({
  onFinished: () => post({ type: 'get-catalog', group: 'dev' }),
  formatStarted: (msg) => `开始：${msg.action ?? '任务'}`,
  formatFinished: (msg) =>
    msg.ok ? '完成' : `失败：${msg.detail ?? ''}`,
})

let unsub: (() => void) | undefined

onMounted(() => {
  if (workspaceOwnsConsole) workspaceOwnsConsole.value = true
  unsub = subscribe((msg) => {
    if (!isShared) consumeJobMessage(msg)
  })
})

onUnmounted(() => {
  unsub?.()
  if (workspaceOwnsConsole) workspaceOwnsConsole.value = false
})

function openDoc(which: 'gitee' | 'github') {
  const url =
    which === 'gitee'
      ? 'https://gitee.com/updateme/terminal-buddy'
      : 'https://github.com/updateme/terminal-buddy'
  post({ type: 'open-url', url })
}
</script>

<template>
  <div class="tb-workspace" :class="{ embedded: props.embedded }">
    <div class="docs-row">
      <span class="docs-row-label">文档</span>
      <button type="button" class="btn ghost mini" @click="openDoc('gitee')">
        <span class="btn-label">Gitee 文档</span>
      </button>
      <button type="button" class="btn ghost mini" @click="openDoc('github')">
        <span class="btn-label">GitHub 文档</span>
      </button>
    </div>

    <JobConsole
      class="tb-console"
      always-show
      :progress="progress"
      :status-text="statusText"
      :entries="outputEntries"
      :busy="busy"
    />
  </div>
</template>

<style scoped>
.tb-workspace {
  display: flex;
  flex-direction: column;
  gap: 0.65rem;
  min-height: 0;
  height: 100%;
  padding: 0.1rem 0 0;
}

.tb-console {
  flex: 1 1 auto;
  min-height: 0;
}
</style>
