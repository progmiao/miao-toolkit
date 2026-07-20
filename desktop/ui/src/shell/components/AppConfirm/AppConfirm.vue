<script setup lang="ts">
/**
 * 全局确认对话框：磨砂机甲风格，与壳层 UI 统一。
 * 数据来自 bridge/confirm；挂在 AppShell 根上。
 */
import { computed, onMounted, onUnmounted, ref } from 'vue'
import {
  resolveConfirm,
  subscribeConfirm,
  type ConfirmRequest,
} from '@kernel/bridge/confirm'
import './AppConfirm.css'

/** 当前请求；null 表示关闭。 */
const request = ref<ConfirmRequest | null>(null)
/** 入场动画开关。 */
const visible = ref(false)

let unsub: (() => void) | undefined
let hideTimer: ReturnType<typeof setTimeout> | undefined
let showTimer: ReturnType<typeof setTimeout> | undefined

/**
 * 键盘：Esc 取消，Enter 确认。
 * @param e - 键盘事件
 */
function onKeydown(e: KeyboardEvent) {
  if (!visible.value || !request.value) return
  if (e.key === 'Escape') {
    e.preventDefault()
    onCancel()
  } else if (e.key === 'Enter') {
    e.preventDefault()
    onConfirm()
  }
}

onMounted(() => {
  window.addEventListener('keydown', onKeydown)
  unsub = subscribeConfirm((req) => {
    if (hideTimer) {
      clearTimeout(hideTimer)
      hideTimer = undefined
    }
    if (showTimer) {
      clearTimeout(showTimer)
      showTimer = undefined
    }
    if (req) {
      request.value = req
      showTimer = setTimeout(() => {
        visible.value = true
      }, 16)
    } else {
      visible.value = false
      hideTimer = setTimeout(() => {
        request.value = null
      }, 220)
    }
  })
})

onUnmounted(() => {
  window.removeEventListener('keydown', onKeydown)
  unsub?.()
  if (hideTimer) clearTimeout(hideTimer)
  if (showTimer) clearTimeout(showTimer)
})

const toneClass = computed(() =>
  request.value?.tone === 'danger' ? 'tone-danger' : 'tone-default',
)

/** 确认。 */
function onConfirm() {
  resolveConfirm(true)
}

/** 取消 / 关闭。 */
function onCancel() {
  resolveConfirm(false)
}

/**
 * 点击遮罩关闭。
 * @param ev - 鼠标事件
 */
function onMaskClick(ev: MouseEvent) {
  if (ev.target === ev.currentTarget) onCancel()
}
</script>

<template>
  <Teleport to="body">
    <Transition name="app-confirm">
      <div
        v-if="request && visible"
        class="app-confirm-mask"
        role="presentation"
        @click="onMaskClick"
      >
        <div
          class="app-confirm"
          :class="toneClass"
          role="alertdialog"
          aria-modal="true"
          :aria-labelledby="`confirm-title-${request.id}`"
          :aria-describedby="`confirm-msg-${request.id}`"
          @click.stop
        >
          <div class="app-confirm-beam" aria-hidden="true" />
          <header class="app-confirm-head">
            <span class="app-confirm-mark" aria-hidden="true" />
            <h2 :id="`confirm-title-${request.id}`" class="app-confirm-title">
              {{ request.title }}
            </h2>
          </header>
          <p :id="`confirm-msg-${request.id}`" class="app-confirm-msg">
            {{ request.message }}
          </p>
          <div class="app-confirm-actions">
            <button type="button" class="btn secondary" @click="onCancel">
              {{ request.cancelText }}
            </button>
            <button
              type="button"
              class="btn"
              :class="{ danger: request.tone === 'danger' }"
              @click="onConfirm"
            >
              {{ request.confirmText }}
            </button>
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>
