<script setup lang="ts">
/**
 * 全局顶部居中 Toast：从顶边滑入，数秒后滑出消失。
 * 数据来自 bridge/toast；挂在 AppShell 根上，不占页面布局。
 */
import { onMounted, onUnmounted, ref } from 'vue'
import {
  dismissToast,
  subscribeToasts,
  type ToastItem,
} from '../../bridge/toast'
import './AppToast.css'

/** 当前可见提示列表。 */
const items = ref<ToastItem[]>([])

let unsub: (() => void) | undefined

onMounted(() => {
  unsub = subscribeToasts((list) => {
    items.value = list
  })
})

onUnmounted(() => {
  unsub?.()
})

/**
 * 用户点击关闭。
 * @param id - 提示 id
 */
function onClose(id: number) {
  dismissToast(id)
}
</script>

<template>
  <div class="app-toast-host" aria-live="polite" aria-relevant="additions text">
    <TransitionGroup name="app-toast">
      <div
        v-for="t in items"
        :key="t.id"
        class="app-toast"
        :class="`kind-${t.kind}`"
        role="status"
      >
        <span class="app-toast-text">{{ t.message }}</span>
        <button
          type="button"
          class="app-toast-close"
          aria-label="关闭提示"
          @click="onClose(t.id)"
        >
          ×
        </button>
      </div>
    </TransitionGroup>
  </div>
</template>
