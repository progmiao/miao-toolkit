<script setup lang="ts">
/**
 * 首页：科幻控制台入口卡，导向网站 / 日常 / 开发 / 工具集。
 */
import { RouterLink } from 'vue-router'
</script>

<template>
  <section class="page page--scroll home">
    <header class="page-head hero">
      <p class="signal">SYSTEM ONLINE</p>
      <h1>Miao Console</h1>
      <p>个人工具百宝箱：网站收藏、软件安装管理，以及应用内小工具。</p>
    </header>

    <div class="cards">
      <article class="card">
        <h2>常用网站</h2>
        <p>一级分类收藏夹，点击用系统浏览器打开；可自行维护并导入导出。</p>
        <RouterLink class="btn" to="/sites">进入</RouterLink>
      </article>
      <article class="card">
        <h2>日常工具</h2>
        <p>微信、向日葵等；下载安装包并拉起厂商向导，Miao 负责检测与卸载入口。</p>
        <RouterLink class="btn" to="/daily">进入</RouterLink>
      </article>
      <article class="card">
        <h2>开发工具</h2>
        <p>Node / pnpm / Yarn、Claude Code、TerminalBuddy、CC Switch / Connect、Hermes。</p>
        <RouterLink class="btn secondary" to="/dev">进入</RouterLink>
      </article>
      <article class="card">
        <h2>工具集</h2>
        <p>GUID 批量生成等应用内小工具，无需额外安装。</p>
        <RouterLink class="btn secondary" to="/utilities">进入</RouterLink>
      </article>
    </div>
  </section>
</template>

<style scoped>
.hero .signal {
  margin: 0 0 0.35rem;
  font-family: var(--font-display);
  font-size: 0.72rem;
  letter-spacing: 0.22em;
  color: var(--accent);
  text-shadow: 0 0 12px var(--glow);
  animation: pulse-signal 2.4s ease-in-out infinite;
}
@keyframes pulse-signal {
  0%,
  100% {
    opacity: 0.65;
  }
  50% {
    opacity: 1;
  }
}
</style>
