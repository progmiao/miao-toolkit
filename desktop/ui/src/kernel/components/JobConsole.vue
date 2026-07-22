<script setup lang="ts">
/**
 * 任务控制台：顶部进度条 + 下方「命令 / 日志」Tab（占满区域，默认命令）。
 */
import { computed, nextTick, ref, watch } from 'vue'
import XtermPane from './XtermPane.vue'

type PaneTab = 'cmd' | 'log'

const props = withDefaults(
  defineProps<{
    /** 0–100 整体进度 */
    progress: number
    /** 状态日志行 */
    logs: string[]
    /**
     * 命令窗口文本块。
     * 传入后启用「命令 / 日志」双 Tab；未传则仅显示日志。
     */
    consoleLines?: string[]
    /** 是否忙碌 */
    busy?: boolean
    /** 命令窗空占位 */
    placeholder?: string
    /** 实时日志空占位 */
    logsPlaceholder?: string
    /**
     * @deprecated 已改为 Tab 布局，保留属性以免调用方报错。
     */
    paneLayout?: 'horizontal' | 'stack'
    /** 空闲时是否仍显示 */
    alwaysShow?: boolean
    /** 当前任务文案（进度条上方） */
    statusText?: string
    /**
     * 合并 Volta Fetching 进度为单行（Node 批量安装命令窗）。
     */
    coalesceFetchingProgress?: boolean
  }>(),
  {
    busy: false,
    alwaysShow: false,
    statusText: '',
    logsPlaceholder: '',
    coalesceFetchingProgress: false,
  },
)

const logEl = ref<HTMLElement | null>(null)
const paneTab = ref<PaneTab>('cmd')

const commandEnabled = computed(() => props.consoleLines !== undefined)

const hasLogs = computed(() => props.logs.length > 0)

const logText = computed(() => {
  if (props.logs.length) return props.logs.join('\n')
  return props.logsPlaceholder || ''
})

const visible = computed(
  () =>
    Boolean(props.alwaysShow) ||
    Boolean(props.busy) ||
    props.logs.length > 0 ||
    (props.consoleLines?.length ?? 0) > 0,
)

const labelText = computed(() => {
  const t = (props.statusText ?? '').trim()
  if (t) return t
  if (props.busy) return '执行中'
  return '就绪'
})

const fillWidth = computed(() => Math.min(100, Math.max(0, props.progress)))

const paneTabs = computed(() => {
  if (!commandEnabled.value) return [] as { id: PaneTab; label: string }[]
  return [
    { id: 'cmd' as const, label: '命令' },
    { id: 'log' as const, label: '日志' },
  ]
})

async function scrollLog() {
  await nextTick()
  if (logEl.value) logEl.value.scrollTop = logEl.value.scrollHeight
}

watch(
  () => [props.logs.length, props.busy, paneTab.value],
  () => {
    if (paneTab.value === 'log' || !commandEnabled.value) void scrollLog()
  },
)

watch(commandEnabled, (on) => {
  if (on) paneTab.value = 'cmd'
})
</script>

<template>
  <div v-if="visible" class="job-console">
    <div class="progress-wrap">
      <div class="progress-label">
        <span class="progress-status" :title="labelText">{{ labelText }}</span>
        <span v-if="busy || fillWidth > 0" class="progress-pct">{{ Math.round(fillWidth) }}%</span>
      </div>
      <div class="progress-track-row">
        <div
          class="progress-bar"
          :class="{ 'is-busy': busy, 'is-done': !busy && fillWidth >= 100 }"
          role="progressbar"
          :aria-valuenow="fillWidth"
          aria-valuemin="0"
          aria-valuemax="100"
          :aria-label="labelText"
        >
          <i class="progress-fill" :style="{ width: fillWidth + '%' }">
            <span class="progress-sheen" aria-hidden="true" />
          </i>
        </div>
      </div>
    </div>

    <!-- 命令通道开启：命令 / 日志 Tab，整块占满 -->
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
        <div
          v-show="paneTab === 'cmd'"
          class="out-panel cmd-panel"
          role="tabpanel"
        >
          <XtermPane
            class="cmd-xterm"
            :chunks="consoleLines ?? []"
            :placeholder="placeholder || ''"
            :busy="busy"
            :coalesce-fetching-progress="coalesceFetchingProgress"
          />
        </div>

        <div
          v-show="paneTab === 'log'"
          class="out-panel status-panel"
          role="tabpanel"
        >
          <pre ref="logEl" class="out-log status-log">{{ logText }}</pre>
        </div>
      </div>
    </div>

    <!-- 仅日志 -->
    <div v-else-if="hasLogs || alwaysShow" class="job-panes">
      <div class="out-panel status-panel">
        <div class="out-title">实时日志</div>
        <pre ref="logEl" class="out-log status-log">{{ logText }}</pre>
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

.progress-wrap {
  flex: 0 0 auto;
  padding: 0.4rem 0.65rem 0.45rem;
  border-radius: 0.55rem;
  border: 1px solid color-mix(in srgb, var(--line) 80%, transparent);
  background: color-mix(in srgb, var(--panel) 42%, transparent);
}

.progress-label {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  margin-bottom: 0.28rem;
  min-height: 1em;
}

.progress-status {
  min-width: 0;
  flex: 1;
  font-size: 0.72rem;
  letter-spacing: 0.04em;
  color: var(--muted);
  font-family: var(--font-mono);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.progress-pct {
  flex: 0 0 auto;
  font-size: 0.68rem;
  font-weight: 700;
  font-family: var(--font-mono);
  font-variant-numeric: tabular-nums;
  color: color-mix(in srgb, var(--accent) 85%, var(--ink));
  letter-spacing: 0.04em;
}

.progress-track-row {
  display: flex;
  align-items: center;
}

.progress-bar {
  position: relative;
  flex: 1;
  min-width: 0;
  height: 0.5rem;
  border-radius: 999px;
  background: color-mix(in srgb, var(--line) 50%, transparent);
  overflow: hidden;
  box-shadow: inset 0 1px 2px color-mix(in srgb, #000 18%, transparent);
}

.progress-fill {
  position: relative;
  display: block;
  height: 100%;
  border-radius: inherit;
  overflow: hidden;
  background: linear-gradient(
    90deg,
    color-mix(in srgb, var(--accent) 75%, #0ff),
    var(--accent),
    color-mix(in srgb, var(--accent-2, var(--accent)) 70%, var(--accent))
  );
  background-size: 200% 100%;
  box-shadow: 0 0 10px color-mix(in srgb, var(--glow, var(--accent)) 55%, transparent);
  transition: width 0.35s cubic-bezier(0.22, 1, 0.36, 1);
}

.progress-bar.is-busy .progress-fill {
  animation: progress-flow 1.6s linear infinite;
}

.progress-sheen {
  position: absolute;
  inset: 0;
  background: linear-gradient(
    105deg,
    transparent 0%,
    transparent 40%,
    color-mix(in srgb, #fff 45%, transparent) 50%,
    transparent 60%,
    transparent 100%
  );
  background-size: 220% 100%;
  opacity: 0;
  pointer-events: none;
}

.progress-bar.is-busy .progress-sheen {
  opacity: 1;
  animation: progress-sheen 1.4s ease-in-out infinite;
}

.progress-bar.is-done .progress-fill {
  animation: none;
  background-position: 0 0;
}

@keyframes progress-flow {
  to {
    background-position: 200% 0;
  }
}

@keyframes progress-sheen {
  0% {
    background-position: 100% 0;
  }
  100% {
    background-position: -100% 0;
  }
}

@media (prefers-reduced-motion: reduce) {
  .progress-fill {
    transition: none;
  }
  .progress-bar.is-busy .progress-fill,
  .progress-bar.is-busy .progress-sheen {
    animation: none;
  }
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
  /* 与主 Tab 同形：左边垂直、右侧斜切，高度更小 */
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

.out-log {
  flex: 1;
  min-height: 9rem;
  margin: 0;
  padding: 0.75rem 0.8rem;
  overflow: auto;
  font-family: var(--font-mono);
  font-size: 0.76rem;
  line-height: 1.45;
  white-space: pre-wrap;
  word-break: break-word;
}

.status-log {
  color: var(--ink);
}

.cmd-xterm {
  flex: 1;
  min-height: 9rem;
}
</style>
