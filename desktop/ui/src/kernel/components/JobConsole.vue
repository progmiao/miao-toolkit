<script setup lang="ts">
/**
 * 任务控制台壳：进度条 + 单轨「输出」面板（CommandPane）。
 */
import { computed } from 'vue'
import CommandPane from './CommandPane.vue'
import JobProgressBar from './JobProgressBar.vue'
import type { LogEntry } from '@kernel/console/logEntries'

const props = withDefaults(
  defineProps<{
    progress: number
    entries?: LogEntry[]
    busy?: boolean
    placeholder?: string
    alwaysShow?: boolean
    statusText?: string
    /** 操作按钮相对进度条：start=左，end=右 */
    actionsPlacement?: 'start' | 'end'
  }>(),
  {
    busy: false,
    alwaysShow: false,
    statusText: '',
    entries: () => [],
    placeholder: '执行操作时在此显示输出…',
    actionsPlacement: 'end',
  },
)

const visible = computed(
  () =>
    Boolean(props.alwaysShow) ||
    Boolean(props.busy) ||
    props.entries.length > 0,
)
</script>

<template>
  <div v-if="visible" class="job-console">
    <div class="job-progress-row">
      <div
        v-if="$slots.actions && actionsPlacement === 'start'"
        class="job-progress-side"
      >
        <slot name="actions" />
      </div>
      <JobProgressBar class="job-progress-main" :progress="progress" :status-text="statusText" />
      <div
        v-if="$slots.actions && actionsPlacement === 'end'"
        class="job-progress-side"
      >
        <slot name="actions" />
      </div>
    </div>

    <div class="job-panes job-panes--tabs">
      <div class="pane-tabs" role="tablist" aria-label="输出面板">
        <button
          type="button"
          role="tab"
          class="pane-tab active"
          aria-selected="true"
        >
          <span class="pane-tab-label">输出</span>
        </button>
      </div>

      <div class="pane-body">
        <div class="out-panel cmd-panel" role="tabpanel">
          <CommandPane :entries="entries" :placeholder="placeholder" />
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.job-console {
  display: flex;
  flex-direction: column;
  gap: 0.65rem;
  min-width: 0;
  min-height: 0;
  width: 100%;
  max-width: 100%;
  flex: 1;
}

.job-progress-row {
  display: flex;
  align-items: stretch;
  gap: 0.5rem;
  flex: 0 0 auto;
  min-width: 0;
}

.job-progress-main {
  flex: 1;
  min-width: 0;
}

.job-progress-side {
  flex: 0 0 auto;
  display: flex;
  align-items: stretch;
  gap: 0.5rem;
  min-width: 0;
}

.job-progress-side > :deep(.btn) {
  height: 100% !important;
  min-height: 0 !important;
  max-height: none !important;
  align-self: stretch;
  box-sizing: border-box;
  padding-top: 0 !important;
  padding-bottom: 0 !important;
}

.job-panes {
  flex: 1;
  min-height: 0;
  display: flex;
  flex-direction: column;
}

.job-panes--tabs {
  gap: 0;
}

.pane-tabs {
  display: flex;
  align-items: flex-end;
  gap: 0;
  padding: 0;
  margin: 0;
  flex: 0 0 auto;
  border-bottom: 1px solid color-mix(in srgb, var(--line) 85%, transparent);
}

.pane-tab {
  --tab-slant: 0.5rem;
  position: relative;
  margin: 0 0 -1px;
  padding: 0;
  border: none;
  background: transparent;
  cursor: default;
  color: var(--ink);
  font-weight: 650;
  font-size: 0.72rem;
  letter-spacing: 0.03em;
}

.pane-tab-label {
  display: block;
  padding: 0.28rem 0.78rem 0.24rem 0.62rem;
  background: color-mix(in srgb, var(--panel) 88%, transparent);
  border: 1px solid color-mix(in srgb, var(--accent) 40%, var(--line));
  border-bottom: none;
  clip-path: polygon(0 0, calc(100% - var(--tab-slant)) 0, 100% 100%, 0 100%);
  border-radius: 0.35rem 0.12rem 0 0;
  box-shadow: inset 0 2px 0 var(--accent);
}

.pane-body {
  flex: 1;
  min-height: 0;
  display: flex;
  flex-direction: column;
  position: relative;
}

.pane-body > .out-panel {
  flex: 1;
  min-height: 0;
  height: 100%;
}

.out-panel {
  min-height: 0;
  display: flex;
  flex-direction: column;
  border-radius: 0 0.65rem 0.65rem 0.65rem;
  overflow: hidden;
}

.cmd-panel {
  border: 1px solid color-mix(in srgb, var(--line) 70%, transparent);
  background: #0c0c0c;
}
</style>
