/**
 * Vite 配置：Vue SFC、按侧栏英文分区的别名、固定 5173。
 *
 * 别名（与中文标题对应）：
 * - @shell      壳
 * - @kernel     内核
 * - @sites      常用网站
 * - @daily      日常工具
 * - @dev        开发工具
 * - @utilities  工具集
 */
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import { fileURLToPath, URL } from 'node:url'

const src = (p: string) => fileURLToPath(new URL(p, import.meta.url))

export default defineConfig(({ command }) => ({
  plugins: [vue()],
  // dev: absolute base for WebView2; build: relative for packaged wwwroot
  base: command === 'build' ? './' : '/',
  resolve: {
    alias: {
      '@': src('./src'),
      '@shell': src('./src/shell'),
      '@kernel': src('./src/kernel'),
      '@sites': src('./src/sites'),
      '@daily': src('./src/daily'),
      '@dev': src('./src/dev'),
      '@utilities': src('./src/utilities'),
    },
  },
  server: {
    host: '127.0.0.1',
    port: 5173,
    strictPort: true,
    open: false,
  },
  build: {
    outDir: 'dist',
    emptyOutDir: true,
  },
}))
