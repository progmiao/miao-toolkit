<script setup lang="ts">
/**
 * 装更卸型工具共用工作区：可选文档入口 + Job 输出（接管父级共用控制台）。
 */
import { inject, onMounted, onUnmounted } from 'vue'
import JobConsole from '@kernel/components/JobConsole.vue'
import { post, subscribe } from '@kernel/bridge/bus'
import { useShellTitle } from '@kernel/composables/useShellTitle'
import { DEV_WORKSPACE_OWNS_CONSOLE_KEY } from '../devPanelContext'
import { useDevPanelJob } from '../useDevPanelJob'

export type DocLink = {
  label: string
  url: string
}

const props = withDefaults(
  defineProps<{
    /** 嵌在一级页 tool-workspace。 */
    embedded?: boolean
    /** 独立打开时的壳标题。 */
    title?: string
    /** 内容区顶部文档按钮（浏览器打开）。 */
    docs?: DocLink[]
  }>(),
  {
    embedded: false,
    title: '开发工具',
    docs: () => [],
  },
)

useShellTitle(props.embedded ? '开发工具' : props.title)

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

function openDoc(url: string) {
  post({ type: 'open-url', url })
}
</script>

<template>
  <div class="install-output-workspace" :class="{ embedded: props.embedded }">
    <div v-if="props.docs.length" class="docs-row">
      <span class="docs-row-label">文档</span>
      <button
        v-for="d in props.docs"
        :key="d.url"
        type="button"
        class="btn ghost mini"
        :title="d.url"
        @click="openDoc(d.url)"
      >
        <span class="btn-label">{{ d.label }}</span>
      </button>
    </div>

    <JobConsole
      class="install-output-console"
      always-show
      :progress="progress"
      :status-text="statusText"
      :entries="outputEntries"
      :busy="busy"
    />
  </div>
</template>

<style scoped>
.install-output-workspace {
  display: flex;
  flex-direction: column;
  gap: 0.65rem;
  min-height: 0;
  height: 100%;
  padding: 0.1rem 0 0;
}

.install-output-console {
  flex: 1 1 auto;
  min-height: 0;
}
</style>
