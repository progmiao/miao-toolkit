/**
 * Vite 配置：Vue SFC、`@` 别名、固定 5173、相对 base 以适配 WebView2 本地资源。
 */
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import { fileURLToPath, URL } from 'node:url'

export default defineConfig({
  plugins: [vue()],
  /** 使用相对路径，便于 file/虚拟主机下解析 assets */
  base: './',
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
    },
  },
  server: {
    /** 开发端口；与宿主探测、dev.ps1 打开浏览器的地址一致 */
    port: 5173,
    strictPort: true,
    /**
     * 启动 Vite 时自动打开系统浏览器，便于用 F12 调样式。
     * 与 WebView2 宿主并行：浏览器看样式，宿主测 IPC。
     */
    open: true,
  },
  build: {
    outDir: 'dist',
    emptyOutDir: true,
  },
})
