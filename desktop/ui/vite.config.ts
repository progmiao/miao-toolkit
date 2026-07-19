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
    /** 开发端口；与宿主 MainWindow 探测地址一致 */
    port: 5173,
    strictPort: true,
    /**
     * 启动 Vite 时自动打开系统浏览器，便于用 F12 调样式。
     * 宿主 WebView2 另开窗口联调 IPC；dev.ps1 不再重复打开浏览器。
     */
    open: true,
  },
  build: {
    outDir: 'dist',
    emptyOutDir: true,
  },
})
