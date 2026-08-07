<script setup lang="ts">
/**
 * 根组件：启动期全屏 Boot，完成后过渡到固定应用壳。
 * 主壳在 Boot 仍盖住时预挂载，再只淡出 Boot，避免中间空帧。
 */
import { nextTick, onMounted, onUnmounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import AppShell from '@shell/components/AppShell'
import BootPage from '@shell/boot/index.vue'
import { isBrowserMock } from '@kernel/bridge/bus'

const route = useRoute()
const router = useRouter()

const skipBoot =
  isBrowserMock() && typeof location !== 'undefined' && !location.hash.includes('/boot')

/** 浏览器直开且非 /boot：跳过启动页，避免 Mock 闪一下 */
const booting = ref(!skipBoot)

/** 主壳是否已挂载（启动结束前可先挂在 Boot 下方）。 */
const shellReady = ref(skipBoot)

function removeHtmlSplash() {
  document.getElementById('boot-splash')?.remove()
}

async function finishBoot() {
  if (!booting.value) return
  if (route.path === '/boot' || route.name === 'boot') {
    await router.replace('/')
  }
  // 先挂主壳并等一帧绘制，再淡出 Boot，两层紧挨交叉
  shellReady.value = true
  await nextTick()
  await new Promise<void>((resolve) => {
    requestAnimationFrame(() => requestAnimationFrame(() => resolve()))
  })
  booting.value = false
}

function onBootComplete() {
  void finishBoot()
}

onMounted(() => {
  window.addEventListener('miao:boot-complete', onBootComplete)
  if (skipBoot) removeHtmlSplash()
})

onUnmounted(() => {
  window.removeEventListener('miao:boot-complete', onBootComplete)
})
</script>

<template>
  <!-- 固定底色盖住切换空隙 -->
  <div class="root-stage">
    <AppShell v-if="shellReady" key="shell" class="root-layer root-layer--shell" />
    <Transition name="boot-exit" @after-leave="removeHtmlSplash">
      <BootPage v-if="booting" key="boot" class="root-layer root-layer--boot" />
    </Transition>
  </div>
</template>

<style>
.root-stage {
  position: fixed;
  inset: 0;
  background: #060a12;
}

.root-layer {
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
  min-height: 0;
}

.root-layer--shell {
  z-index: 1;
}

.root-layer--boot {
  z-index: 2;
}

/* 仅淡出 Boot：主壳已在下方就绪，交叉无空档 */
.boot-exit-leave-active {
  transition: opacity 0.5s cubic-bezier(0.4, 0, 0.2, 1);
  z-index: 2;
}
.boot-exit-leave-to {
  opacity: 0;
}

/* 主壳在 Boot 仍盖住时已挂载；露出时轻微提亮，与淡出叠合 */
.root-layer--shell {
  animation: shell-under-reveal 0.55s cubic-bezier(0.4, 0, 0.2, 1) both;
}
@keyframes shell-under-reveal {
  from {
    opacity: 0.92;
    filter: saturate(0.92) brightness(0.96);
  }
  to {
    opacity: 1;
    filter: none;
  }
}
</style>
