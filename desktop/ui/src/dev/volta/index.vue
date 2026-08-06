<script setup lang="ts">
/**
 * Volta 工作区：嵌在开发工具一级页的 tool-workspace。
 * 安装/更新/卸载在父级 tool-overview；本区仅相关跳转与说明。
 * Host：generic.winget；种子：seeds/dev/volta/software.json
 */
import { inject, onMounted, onUnmounted } from 'vue'
import { post, subscribe } from '@kernel/bridge/bus'
import { DEV_SELECT_TOOL_KEY } from '../devPanelContext'
import { useDevPanelJob } from '../useDevPanelJob'

const props = defineProps<{
  /** 嵌在一级页工作区（无二级页壳）。 */
  embedded?: boolean
}>()

const selectTool = inject(DEV_SELECT_TOOL_KEY, null)

const { consumeJobMessage, isShared } = useDevPanelJob({
  onFinished: () => post({ type: 'get-catalog', group: 'dev' }),
})

let unsub: (() => void) | undefined

onMounted(() => {
  unsub = subscribe((msg) => {
    if (!isShared) consumeJobMessage(msg)
  })
})

onUnmounted(() => unsub?.())

/**
 * 切换到相关工具（仍在一级页）。
 * @param id - node | pnpm | yarn
 */
function goRelated(id: string) {
  selectTool?.(id)
}
</script>

<template>
  <div class="volta-workspace" :class="{ embedded: props.embedded }">
    <p class="hint">
      通过 WinGet 管理 Volta 本体。装好后可在下方相关工具中管理 Node / Pnpm / Yarn 多版本；
      安装进度与命令输出见本页底部共用输出区。
    </p>
    <div class="related">
      <span class="related-label">相关工具</span>
      <button type="button" class="btn ghost mini" @click="goRelated('node')">Node.js</button>
      <button type="button" class="btn ghost mini" @click="goRelated('pnpm')">Pnpm</button>
      <button type="button" class="btn ghost mini" @click="goRelated('yarn')">Yarn</button>
    </div>
  </div>
</template>

<style scoped>
.volta-workspace {
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
  padding: 0.15rem 0 0.35rem;
}
.hint {
  margin: 0;
  color: var(--muted);
  font-size: 0.88rem;
  line-height: 1.45;
}
.related {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.45rem;
}
.related-label {
  font-size: 0.8rem;
  color: var(--muted);
  margin-right: 0.15rem;
}
.btn.mini {
  padding: 0.25rem 0.55rem;
  font-size: 0.8rem;
}
</style>
