<script setup lang="ts">
/**
 * 壳层右侧顶栏标题（公共组件）。
 * - 标题在「内容区」水平居中（与 shell-content 同左右内边距）
 * - Oxanium / Noto Sans SC 科幻字重 + 切页入场
 * - 两侧机甲能量轨、括号节点、扫光与刻度动画
 */
defineProps<{
  /** 中间展示的标题文案（通常来自页面 useShellTitle / 路由 meta） */
  title: string
}>()
</script>

<template>
  <header class="shell-top" role="banner">
    <!-- 与 .shell-content 同宽的舞台，保证标题相对内容区居中 -->
    <div class="shell-top-stage">
      <span class="shell-top-rail shell-top-rail--left" aria-hidden="true">
        <i class="rail-ticks" />
        <i class="rail-glow" />
        <i class="rail-core" />
        <i class="rail-scan" />
        <i class="rail-chevron" />
        <i class="rail-node" />
      </span>

      <h1 :key="title" class="shell-top-title">
        <span class="title-text">{{ title }}</span>
      </h1>

      <span class="shell-top-rail shell-top-rail--right" aria-hidden="true">
        <i class="rail-ticks" />
        <i class="rail-glow" />
        <i class="rail-core" />
        <i class="rail-scan" />
        <i class="rail-chevron" />
        <i class="rail-node" />
      </span>
    </div>
  </header>
</template>

<style scoped>
.shell-top {
  flex: 0 0 auto;
  padding: 0.45rem 0 0;
  background: transparent;
  border: none;
  box-shadow: none;
  overflow: hidden;
}

/**
 * 水平内边距与 .shell-content（1.4rem）对齐，
 * 标题在 1fr / auto / 1fr 网格中相对「内容区」居中。
 */
.shell-top-stage {
  display: grid;
  grid-template-columns: minmax(0, 1fr) auto minmax(0, 1fr);
  align-items: center;
  gap: 0.85rem;
  min-height: 3.4rem;
  padding: 0 1.4rem;
  box-sizing: border-box;
}

/* —— 两侧科幻能量轨 —— */
.shell-top-rail {
  position: relative;
  display: block;
  height: 1.15rem;
  min-width: 0;
}

.rail-glow,
.rail-core,
.rail-scan,
.rail-ticks {
  position: absolute;
  left: 0;
  right: 0;
  top: 50%;
  transform: translateY(-50%);
  pointer-events: none;
  border-radius: 999px;
}

.rail-glow {
  height: 0.55rem;
  filter: blur(4px);
  opacity: 0.65;
  background: linear-gradient(
    90deg,
    transparent,
    color-mix(in srgb, var(--shell-cyan) 50%, transparent) 40%,
    color-mix(in srgb, var(--accent-2, var(--shell-cyan)) 55%, transparent) 60%,
    transparent
  );
  animation: rail-breathe 2.6s ease-in-out infinite;
}

.rail-core {
  height: 2px;
  background: linear-gradient(
    90deg,
    transparent 0%,
    color-mix(in srgb, var(--shell-cyan) 40%, transparent) 8%,
    var(--shell-cyan) 50%,
    color-mix(in srgb, var(--shell-cyan) 40%, transparent) 92%,
    transparent 100%
  );
  box-shadow:
    0 0 8px color-mix(in srgb, var(--shell-cyan) 85%, transparent),
    0 0 18px color-mix(in srgb, var(--shell-cyan) 45%, transparent);
}

/* 刻度虚线层 */
.rail-ticks {
  height: 1px;
  top: calc(50% + 0.28rem);
  opacity: 0.75;
  background: repeating-linear-gradient(
    90deg,
    color-mix(in srgb, var(--shell-cyan) 85%, #fff) 0 2px,
    transparent 2px 6px
  );
  mask-image: linear-gradient(90deg, transparent, #000 18%, #000 82%, transparent);
  -webkit-mask-image: linear-gradient(90deg, transparent, #000 18%, #000 82%, transparent);
  animation: ticks-flow 1.6s linear infinite;
}

.shell-top-rail--right .rail-ticks {
  animation-direction: reverse;
}

/* 高速扫光 */
.rail-scan {
  height: 4px;
  background: linear-gradient(
    90deg,
    transparent 0%,
    transparent 42%,
    color-mix(in srgb, #fff 90%, var(--shell-cyan)) 50%,
    transparent 58%,
    transparent 100%
  );
  background-size: 240% 100%;
  mix-blend-mode: screen;
  opacity: 0.9;
}

.shell-top-rail--left .rail-scan {
  animation: scan-ltr 1.15s cubic-bezier(0.4, 0, 0.2, 1) infinite;
}

.shell-top-rail--right .rail-scan {
  animation: scan-rtl 1.15s cubic-bezier(0.4, 0, 0.2, 1) infinite;
  animation-delay: 0.08s;
}

/* 标题旁机甲折角 */
.rail-chevron {
  position: absolute;
  top: 50%;
  width: 0.72rem;
  height: 0.72rem;
  transform: translateY(-50%) rotate(45deg);
  border: 2px solid color-mix(in srgb, var(--shell-cyan) 85%, #fff);
  box-shadow:
    0 0 8px color-mix(in srgb, var(--shell-cyan) 70%, transparent),
    inset 0 0 6px color-mix(in srgb, var(--shell-cyan) 35%, transparent);
  background: color-mix(in srgb, var(--shell-cyan) 12%, transparent);
  animation: chevron-pulse 2s ease-in-out infinite;
}

.shell-top-rail--left .rail-chevron {
  right: 0.15rem;
  border-left: none;
  border-bottom: none;
}

.shell-top-rail--right .rail-chevron {
  left: 0.15rem;
  border-right: none;
  border-top: none;
  animation-delay: 0.4s;
}

.rail-node {
  position: absolute;
  top: 50%;
  width: 0.38rem;
  height: 0.38rem;
  border-radius: 50%;
  transform: translateY(-50%);
  background: radial-gradient(circle, #fff 0%, var(--shell-cyan) 48%, transparent 72%);
  box-shadow:
    0 0 10px var(--shell-cyan),
    0 0 22px color-mix(in srgb, var(--shell-cyan) 65%, transparent);
  animation: node-pulse 1.6s ease-in-out infinite;
}

.shell-top-rail--left .rail-node {
  right: 0.95rem;
}

.shell-top-rail--right .rail-node {
  left: 0.95rem;
  animation-delay: 0.3s;
}

/* —— 标题字：无外框；磨砂透明字色 + 阴影 + 强光晕动效 —— */
.shell-top-title {
  position: relative;
  z-index: 1;
  margin: 0;
  padding: 0.1rem 0.2rem;
  text-align: center;
  white-space: nowrap;
  background: none;
  border: none;
  box-shadow: none;
  backdrop-filter: none;
  -webkit-backdrop-filter: none;
  animation: title-in 0.55s cubic-bezier(0.22, 1, 0.36, 1) both;
}

.title-text {
  display: inline-block;
  font-family: var(--font-title);
  font-size: 1.42rem;
  font-weight: 800;
  letter-spacing: 0.22em;
  line-height: 1.2;
  text-indent: 0.22em;
  /* 半透明磨砂渐变字 */
  background: linear-gradient(
    115deg,
    color-mix(in srgb, #fff 50%, transparent) 0%,
    color-mix(in srgb, var(--shell-cyan) 70%, transparent) 40%,
    color-mix(in srgb, var(--accent-2, #7c9cff) 50%, transparent) 75%,
    color-mix(in srgb, #fff 38%, transparent) 100%
  );
  background-size: 220% 100%;
  -webkit-background-clip: text;
  background-clip: text;
  -webkit-text-fill-color: transparent;
  color: color-mix(in srgb, var(--shell-cyan) 65%, #fff);
  animation:
    title-shimmer 2.2s ease-in-out infinite,
    title-glow-pulse 1.6s ease-in-out infinite;
}

@keyframes title-in {
  from {
    opacity: 0;
    transform: scale(0.82) translateY(0.35rem);
    filter: blur(10px);
    letter-spacing: 0.5em;
  }
  to {
    opacity: 1;
    transform: scale(1) translateY(0);
    filter: blur(0);
    letter-spacing: normal;
  }
}

@keyframes title-shimmer {
  0%,
  100% {
    background-position: 0% 50%;
  }
  50% {
    background-position: 100% 50%;
  }
}

/* 无外框：光晕落在字形本身，呼吸更明显 */
@keyframes title-glow-pulse {
  0%,
  100% {
    filter:
      drop-shadow(0 3px 4px color-mix(in srgb, var(--shell-atm-base, #000) 50%, transparent))
      drop-shadow(0 0 4px color-mix(in srgb, var(--shell-cyan) 45%, transparent))
      drop-shadow(0 0 14px color-mix(in srgb, var(--shell-cyan) 35%, transparent))
      drop-shadow(0 0 28px color-mix(in srgb, var(--shell-cyan) 18%, transparent));
  }
  50% {
    filter:
      drop-shadow(0 3px 5px color-mix(in srgb, var(--shell-atm-base, #000) 55%, transparent))
      drop-shadow(0 0 8px color-mix(in srgb, #fff 55%, var(--shell-cyan)))
      drop-shadow(0 0 22px color-mix(in srgb, var(--shell-cyan) 75%, transparent))
      drop-shadow(0 0 42px color-mix(in srgb, var(--shell-cyan) 45%, transparent))
      drop-shadow(0 0 64px color-mix(in srgb, var(--accent-2, var(--shell-cyan)) 28%, transparent));
  }
}

@keyframes scan-ltr {
  0% {
    background-position: 130% 0;
    opacity: 0.15;
  }
  30% {
    opacity: 1;
  }
  100% {
    background-position: -130% 0;
    opacity: 0.15;
  }
}

@keyframes scan-rtl {
  0% {
    background-position: -130% 0;
    opacity: 0.15;
  }
  30% {
    opacity: 1;
  }
  100% {
    background-position: 130% 0;
    opacity: 0.15;
  }
}

@keyframes ticks-flow {
  from {
    background-position: 0 0;
  }
  to {
    background-position: 36px 0;
  }
}

@keyframes rail-breathe {
  0%,
  100% {
    opacity: 0.3;
    transform: translateY(-50%) scaleY(0.65);
  }
  50% {
    opacity: 1;
    transform: translateY(-50%) scaleY(1.55);
  }
}

@keyframes chevron-pulse {
  0%,
  100% {
    opacity: 0.45;
    transform: translateY(-50%) rotate(45deg) scale(0.85);
    box-shadow: 0 0 4px color-mix(in srgb, var(--shell-cyan) 40%, transparent);
  }
  50% {
    opacity: 1;
    transform: translateY(-50%) rotate(45deg) scale(1.2);
    box-shadow:
      0 0 14px color-mix(in srgb, var(--shell-cyan) 90%, transparent),
      0 0 28px color-mix(in srgb, var(--shell-cyan) 50%, transparent);
  }
}

@keyframes node-pulse {
  0%,
  100% {
    transform: translateY(-50%) scale(0.7);
    opacity: 0.5;
  }
  50% {
    transform: translateY(-50%) scale(1.45);
    opacity: 1;
  }
}

@media (prefers-reduced-motion: reduce) {
  .shell-top-title,
  .title-text,
  .rail-scan,
  .rail-glow,
  .rail-ticks,
  .rail-chevron,
  .rail-node {
    animation: none !important;
  }

  .shell-top-title {
    opacity: 1;
    filter: none;
    transform: none;
  }
}
</style>
