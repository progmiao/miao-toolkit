<script setup lang="ts">
/**
 * 首页：入口到日常工具 / 开发工具。
 */
import { RouterLink } from 'vue-router'
</script>

<template>
  <section class="page">
    <header class="page-head">
      <h1>开始</h1>
      <p>
        桌面版安装管理中心：按场景管理日常应用与开发工具，重装后勾选装齐即可。
      </p>
    </header>

    <div class="cards">
      <article class="card">
        <h2>日常工具</h2>
        <p>微信、向日葵等；下载安装包并拉起厂商向导，Miao 负责检测与卸载入口。</p>
        <RouterLink class="btn" to="/daily">打开</RouterLink>
      </article>
      <article class="card">
        <h2>开发工具</h2>
        <p>Node、TerminalBuddy、CC Switch / Connect 等开发向工具与配套。</p>
        <RouterLink class="btn secondary" to="/dev">打开</RouterLink>
      </article>
    </div>
  </section>
</template>
