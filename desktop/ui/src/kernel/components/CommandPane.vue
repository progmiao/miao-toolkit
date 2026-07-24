<script setup lang="ts">
/**
 * 命令窗（封闭）：只负责按条目显示；append/upsert 由外部写入 entries。
 * 与 LogPane 独立组件，仅样式不同；共用 logEntries 模型。
 */
import { nextTick, ref, watch } from 'vue'
import type { LogEntry } from '@kernel/console/logEntries'

const props = withDefaults(
  defineProps<{
    entries?: LogEntry[]
    placeholder?: string
  }>(),
  {
    entries: () => [],
    placeholder: '',
  },
)

const scroller = ref<HTMLElement | null>(null)

async function scrollToBottom() {
  await nextTick()
  const el = scroller.value
  if (el) el.scrollTop = el.scrollHeight
}

watch(
  () => props.entries.map((e) => `${e.id}:${e.text}`).join('\n'),
  () => {
    void scrollToBottom()
  },
)
</script>

<template>
  <div class="command-pane">
    <div ref="scroller" class="command-scroll">
      <div v-if="!entries.length && placeholder" class="command-placeholder">
        {{ placeholder }}
      </div>
      <div v-else class="command-lines" role="log" aria-live="polite">
        <div
          v-for="e in entries"
          :key="e.id"
          class="command-line"
          :class="e.tone ? `tone-${e.tone}` : undefined"
        >
          {{ e.text }}
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.command-pane {
  flex: 1;
  min-height: 0;
  display: flex;
  flex-direction: column;
  background: #0c0c0c;
}

.command-scroll {
  flex: 1;
  min-height: 9rem;
  overflow: auto;
  padding: 0.35rem 0.5rem;
  scrollbar-width: thin;
  scrollbar-color: color-mix(in srgb, var(--accent, #3dd6c6) 70%, #666) #1a1a1a;
}

.command-placeholder {
  color: #808080;
  font-size: 12px;
  font-family: Cascadia Mono, Consolas, monospace;
  line-height: 1.45;
  white-space: pre-wrap;
  word-break: break-word;
  user-select: none;
}

.command-lines {
  font-family: Cascadia Mono, Consolas, monospace;
  font-size: 12px;
  line-height: 1.45;
  color: #cccccc;
}

.command-line {
  white-space: pre;
  min-height: 1.45em;
}

.command-line.tone-dim {
  color: #808080;
}
.command-line.tone-ok {
  color: #6a9955;
}
.command-line.tone-warn {
  color: #d7ba7d;
}
.command-line.tone-err {
  color: #f48771;
}

.command-scroll::-webkit-scrollbar {
  width: var(--scroll-size, 7px);
  height: var(--scroll-size, 7px);
}
.command-scroll::-webkit-scrollbar-track {
  background: #1a1a1a;
  margin: 2px;
  border-radius: 999px;
}
.command-scroll::-webkit-scrollbar-thumb {
  border-radius: 999px;
  background: color-mix(in srgb, var(--accent, #3dd6c6) 70%, #444);
}
.command-scroll::-webkit-scrollbar-corner {
  background: #0c0c0c;
}
</style>
