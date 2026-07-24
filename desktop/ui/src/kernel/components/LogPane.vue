<script setup lang="ts">
/**
 * 日志窗（封闭）：只负责按条目显示；与 CommandPane 独立，样式偏面板日志。
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
  <div class="log-pane">
    <div ref="scroller" class="log-scroll">
      <div v-if="!entries.length && placeholder" class="log-placeholder">
        {{ placeholder }}
      </div>
      <div v-else class="log-lines" role="log" aria-live="polite">
        <div
          v-for="e in entries"
          :key="e.id"
          class="log-line"
          :class="e.tone ? `tone-${e.tone}` : undefined"
        >
          {{ e.text }}
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.log-pane {
  flex: 1;
  min-height: 0;
  display: flex;
  flex-direction: column;
  background: color-mix(in srgb, var(--panel) 38%, transparent);
}

.log-scroll {
  flex: 1;
  min-height: 9rem;
  overflow: auto;
  padding: 0.75rem 0.8rem;
}

.log-placeholder {
  color: var(--muted);
  font-size: 0.76rem;
  font-family: var(--font-mono);
  line-height: 1.45;
  white-space: pre-wrap;
  word-break: break-word;
  user-select: none;
}

.log-lines {
  font-family: var(--font-mono);
  font-size: 0.76rem;
  line-height: 1.45;
  color: var(--ink);
}

.log-line {
  white-space: pre-wrap;
  word-break: break-word;
  min-height: 1.45em;
}

.log-line.tone-dim {
  color: var(--muted);
}
.log-line.tone-ok {
  color: var(--ok, #3d9a5f);
}
.log-line.tone-warn {
  color: var(--warn);
}
.log-line.tone-err {
  color: var(--danger);
}
</style>
