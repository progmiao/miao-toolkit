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

export default defineConfig({
  plugins: [vue()],
  base: './',
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
    port: 5173,
    strictPort: true,
    open: true,
  },
  build: {
    outDir: 'dist',
    emptyOutDir: true,
  },
})
