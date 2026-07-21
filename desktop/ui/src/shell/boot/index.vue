<script setup lang="ts">
/**
 * 启动页：S0 仅 ASCII → S1 同款 logo + 进度 + 无框日志 → 主壳。
 * logo 槽位与下方进度槽位尺寸固定，S0/S1 不跳动。
 */
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from 'vue'
import { post, subscribe, type HostMessage } from '@kernel/bridge/bus'
import asciiLogoRaw from '@shell/components/AppShell/ascii-logo.txt?raw'
import './boot.css'

export type BootPhase = 'loading' | 'progress' | 'error'

const phase = ref<BootPhase>('loading')
const percent = ref(0)
const status = ref('正在启动…')
const logs = ref<{ at: string; message: string }[]>([])
const errorMessage = ref('')
const finishing = ref(false)
const logEl = ref<HTMLElement | null>(null)

const logoLines = computed(() =>
  asciiLogoRaw
    .replace(/^\uFEFF/, '')
    .split(/\r?\n/)
    .map((l) => l.replace(/\s+$/, ''))
    .filter((l) => /\S/.test(l)),
)

const showProgressBody = computed(() => phase.value !== 'loading')

function pushLog(message: string, at?: string) {
  logs.value.push({
    at: at ?? new Date().toISOString(),
    message,
  })
  if (logs.value.length > 200) logs.value.splice(0, logs.value.length - 200)
  void nextTick(() => {
    if (logEl.value) logEl.value.scrollTop = logEl.value.scrollHeight
  })
}

function emitComplete(fastPath: boolean) {
  finishing.value = true
  const delay = fastPath ? 220 : 480
  window.setTimeout(() => {
    window.dispatchEvent(
      new CustomEvent('miao:boot-complete', {
        detail: { fastPath },
      }),
    )
  }, delay)
}

function onHost(msg: HostMessage) {
  switch (msg.type) {
    case 'boot.log':
      if (typeof msg.message === 'string' && msg.message) {
        pushLog(msg.message, msg.at)
      }
      break
    case 'boot.progress': {
      const p = typeof msg.percent === 'number' ? msg.percent : percent.value
      percent.value = Math.max(0, Math.min(100, p))
      if (typeof msg.message === 'string' && msg.message) status.value = msg.message
      if (msg.phase === 'progress' && phase.value === 'loading') {
        phase.value = 'progress'
      }
      break
    }
    case 'boot.error':
      phase.value = 'error'
      errorMessage.value = String(msg.message ?? '启动失败')
      pushLog(errorMessage.value, msg.at)
      break
    case 'boot.done':
      if (msg.ok === false) {
        phase.value = 'error'
        errorMessage.value = String(msg.message ?? '启动失败')
        return
      }
      if (phase.value === 'loading') phase.value = 'progress'
      percent.value = 100
      status.value = '即将进入…'
      pushLog(msg.degraded ? '启动完成（部分数据已跳过）' : '启动完成')
      emitComplete(!!msg.fastPath)
      break
    case 'boot.fatal':
      phase.value = 'error'
      errorMessage.value = String(msg.message ?? '启动失败，即将退出')
      pushLog(errorMessage.value, msg.at)
      break
    default:
      break
  }
}

let unsub: (() => void) | null = null

onMounted(() => {
  unsub = subscribe(onHost)
  post({ type: 'boot.ui-ready' })
  post({ type: 'boot.subscribe' })
})

onUnmounted(() => {
  unsub?.()
})

watch(phase, () => {
  void nextTick(() => {
    if (logEl.value) logEl.value.scrollTop = logEl.value.scrollHeight
  })
})
</script>

<template>
  <div class="boot-page" :class="{ 'is-finishing': finishing }">
    <div class="boot-atmosphere" aria-hidden="true">
      <div class="boot-orb boot-orb--a" />
      <div class="boot-orb boot-orb--b" />
      <div class="boot-orb boot-orb--c" />
      <div class="boot-grid" />
      <div class="boot-scan" />
    </div>

    <div class="boot-stage">
      <pre class="boot-ascii" aria-hidden="true">{{ logoLines.join('\n') }}</pre>

      <div class="boot-body-slot">
        <Transition name="boot-body">
          <div v-if="showProgressBody" class="boot-body">
            <p class="boot-status">{{ status }}</p>
            <div
              class="boot-bar"
              role="progressbar"
              :aria-valuenow="percent"
              aria-valuemin="0"
              aria-valuemax="100"
            >
              <div class="boot-bar__fill" :style="{ width: `${percent}%` }" />
              <div class="boot-bar__shine" />
            </div>
            <p class="boot-percent">{{ percent }}%</p>

            <div ref="logEl" class="boot-log" aria-live="polite">
              <div v-for="(line, i) in logs" :key="i" class="boot-log__line">
                <span class="boot-log__at">{{ line.at.slice(11, 19) }}</span>
                <span>{{ line.message }}</span>
              </div>
              <div v-if="!logs.length" class="boot-log__empty">等待进度…</div>
            </div>

            <div v-if="phase === 'error'" class="boot-error">
              <p>{{ errorMessage }}</p>
            </div>
          </div>
        </Transition>
      </div>
    </div>
  </div>
</template>
