<script setup lang="ts">
/**
 * 任务控制台壳：进度条（只显示）+ 命令/日志 Tab。
 * 命令、日志为独立封闭组件；条目由外部写入。
 */
import { computed, ref, watch } from 'vue'
import CommandPane from './CommandPane.vue'
import JobProgressBar from './JobProgressBar.vue'
import LogPane from './LogPane.vue'
import type { LogEntry } from '@kernel/console/logEntries'

type PaneTab = 'cmd' | 'log'

const props = withDefaults(
  defineProps<{
    progress: number
    /** 日志条目（优先）；无则回退 logs 字符串 */
    logEntries?: LogEntry[]
    logs?: string[]
    /** 命令条目（优先）；传入则启用命令 Tab */
    commandEntries?: LogEntry[]
    /**
     * @deprecated 请传 commandEntries；字符串会合成临时条目
     */
    consoleLines?: string[]
    busy?: boolean
    placeholder?: string
    logsPlaceholder?: string
    paneLayout?: 'horizontal' | 'stack'
    alwaysShow?: boolean
    statusText?: string
    /** @deprecated 业务侧自行处理 Fetching */
    coalesceFetchingProgress?: boolean
  }>(),
  {
    busy: false,
    alwaysShow: false,
    statusText: '',
    logsPlaceholder: '',
    logs: () => [],
  },
)

const paneTab = ref<PaneTab>('cmd')

const commandEnabled = computed(
  () => props.commandEntries !== undefined || props.consoleLines !== undefined,
)

const resolvedCommandEntries = computed<LogEntry[]>(() => {
  if (props.commandEntries) return props.commandEntries
  if (!props.consoleLines?.length) return []
  return props.consoleLines.map((text, i) => ({ id: `__legacy_cmd_${i}`, text }))
})

const resolvedLogEntries = computed<LogEntry[]>(() => {
  if (props.logEntries) return props.logEntries
  if (!props.logs?.length) return []
  return props.logs.map((text, i) => ({ id: `__legacy_log_${i}`, text }))
})

const visible = computed(
  () =>
    Boolean(props.alwaysShow) ||
    Boolean(props.busy) ||
    resolvedLogEntries.value.length > 0 ||
    resolvedCommandEntries.value.length > 0,
)

const paneTabs = computed(() => {
  if (!commandEnabled.value) return [] as { id: PaneTab; label: string }[]
  return [
    { id: 'cmd' as const, label: '命令' },
    { id: 'log' as const, label: '日志' },
  ]
})

watch(commandEnabled, (on) => {
  if (on) paneTab.value = 'cmd'
})
</script>

<template>
  <div v-if="visible" class="job-console">
    <JobProgressBar :progress="progress" :status-text="statusText" :busy="busy" />

    <div v-if="commandEnabled" class="job-panes job-panes--tabs">
      <div class="pane-tabs" role="tablist" aria-label="输出面板">
        <button
          v-for="(t, i) in paneTabs"
          :key="t.id"
          type="button"
          role="tab"
          class="pane-tab"
          :class="{ active: paneTab === t.id }"
          :style="{ zIndex: paneTab === t.id ? paneTabs.length + 1 : paneTabs.length - i }"
          :aria-selected="paneTab === t.id"
          @click="paneTab = t.id"
        >
          <span class="pane-tab-label">{{ t.label }}</span>
        </button>
      </div>

      <div class="pane-body">
        <div v-show="paneTab === 'cmd'" class="out-panel cmd-panel" role="tabpanel">
          <CommandPane
            :entries="resolvedCommandEntries"
            :placeholder="placeholder || ''"
          />
        </div>
        <div v-show="paneTab === 'log'" class="out-panel status-panel" role="tabpanel">
          <LogPane
            :entries="resolvedLogEntries"
            :placeholder="logsPlaceholder || ''"
          />
        </div>
      </div>
    </div>

    <div v-else-if="resolvedLogEntries.length || alwaysShow" class="job-panes">
      <div class="out-panel status-panel">
        <div class="out-title">实时日志</div>
        <LogPane
          :entries="resolvedLogEntries"
          :placeholder="logsPlaceholder || ''"
        />
      </div>
    </div>
  </div>
</template>

<style scoped>
.job-console {
  display: flex;
  flex-direction: column;
  gap: 0.65rem;
  min-height: 0;
  flex: 1;
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
  position: relative;
  margin: 0 0 -1px;
  padding: 0;
  border: none;
  background: transparent;
  cursor: pointer;
  color: var(--muted);
  font-weight: 650;
  font-size: 0.72rem;
  letter-spacing: 0.03em;
}

.pane-tab + .pane-tab {
  margin-left: -0.5rem;
}

.pane-tab-label {
  display: block;
  padding: 0.28rem 0.78rem 0.24rem 0.62rem;
  background: color-mix(in srgb, var(--panel) 55%, transparent);
  border: 1px solid color-mix(in srgb, var(--line) 90%, transparent);
  border-bottom: none;
  clip-path: polygon(0 0, calc(100% - 0.55rem) 0, 100% 100%, 0 100%);
  border-radius: 0.35rem 0.12rem 0 0;
  transition:
    color 0.15s ease,
    background 0.15s ease,
    box-shadow 0.15s ease;
}

.pane-tab:hover .pane-tab-label {
  color: var(--ink);
  background: color-mix(in srgb, var(--panel) 72%, transparent);
}

.pane-tab.active {
  color: var(--ink);
}

.pane-tab.active .pane-tab-label {
  background: color-mix(in srgb, var(--panel) 88%, transparent);
  border-color: color-mix(in srgb, var(--accent) 40%, var(--line));
  box-shadow: inset 0 2px 0 var(--accent);
  color: var(--ink);
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

.status-panel {
  border: 1px solid color-mix(in srgb, var(--line) 80%, transparent);
  background: color-mix(in srgb, var(--panel) 38%, transparent);
}

.cmd-panel {
  border: 1px solid color-mix(in srgb, var(--line) 70%, transparent);
  background: #0c0c0c;
}

.out-title {
  flex: 0 0 auto;
  padding: 0.35rem 0.7rem;
  font-size: 0.68rem;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  font-family: var(--font-mono);
  border-bottom: 1px solid color-mix(in srgb, var(--line) 70%, transparent);
  color: var(--muted);
  background: color-mix(in srgb, var(--panel) 50%, transparent);
}
</style>
