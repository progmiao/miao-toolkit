<script setup lang="ts">
/**
 * 根组件：启动期全屏 Boot，完成后过渡到固定应用壳。
 */
import { onMounted, onUnmounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import AppShell from '@shell/components/AppShell'
import BootPage from '@shell/boot/index.vue'
import { isBrowserMock } from '@kernel/bridge/bus'

const route = useRoute()
const router = useRouter()

/** 浏览器直开且非 /boot：跳过启动页，避免 Mock 闪一下 */
const booting = ref(
  !(isBrowserMock() && typeof location !== 'undefined' && !location.hash.includes('/boot')),
)

async function finishBoot() {
  if (!booting.value) return
  if (route.path === '/boot' || route.name === 'boot') {
    await router.replace('/')
  }
  booting.value = false
}

function onBootComplete() {
  void finishBoot()
}

onMounted(() => {
  window.addEventListener('miao:boot-complete', onBootComplete)
})

onUnmounted(() => {
  window.removeEventListener('miao:boot-complete', onBootComplete)
})
</script>

<template>
  <Transition name="root-boot" mode="out-in">
    <BootPage v-if="booting" key="boot" />
    <AppShell v-else key="shell" />
  </Transition>
</template>

<style>
.root-boot-enter-active,
.root-boot-leave-active {
  transition: opacity 0.35s ease, transform 0.35s ease;
}
.root-boot-enter-from {
  opacity: 0;
  transform: translateY(12px);
}
.root-boot-leave-to {
  opacity: 0;
  transform: translateY(-8px);
}
</style>
