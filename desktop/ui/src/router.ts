/**
 * 前端路由：按侧栏分区组装（sites / daily / dev / utilities）。
 * 开发工具 panel 不再使用二级页，旧路径重定向到 `/dev?tool={id}`。
 * `meta.shellTitle`：壳层顶栏中间标题。
 */
import { createRouter, createWebHashHistory, type RouteRecordRaw } from 'vue-router'
import HomePage from '@shell/home/index.vue'
import SettingsPage from '@shell/settings/index.vue'
import BootPage from '@shell/boot/index.vue'
import SitesPage from '@sites/index.vue'
import DailyPage from '@daily/index.vue'
import DevPage from '@dev/index.vue'
import UtilitiesPage from '@utilities/index.vue'

declare module 'vue-router' {
  interface RouteMeta {
    /** 壳层顶栏中间标题；缺省则保持上一页或默认「Miao 工具箱」 */
    shellTitle?: string
  }
}

/** 旧二级页 → 一级页 query。 */
function devToolRedirect(toolId: string) {
  return () => ({ path: '/dev', query: { tool: toolId } })
}

const routes: RouteRecordRaw[] = [
  {
    path: '/boot',
    name: 'boot',
    component: BootPage,
    meta: { shellTitle: '启动' },
  },
  { path: '/', name: 'home', component: HomePage, meta: { shellTitle: '首页' } },
  { path: '/sites', name: 'sites', component: SitesPage, meta: { shellTitle: '常用网站' } },
  { path: '/daily', name: 'daily', component: DailyPage, meta: { shellTitle: '日常工具' } },
  { path: '/dev', name: 'dev', component: DevPage, meta: { shellTitle: '开发工具' } },
  { path: '/dev/volta', redirect: devToolRedirect('volta') },
  { path: '/dev/node', redirect: devToolRedirect('node') },
  { path: '/dev/pnpm', redirect: devToolRedirect('pnpm') },
  { path: '/dev/yarn', redirect: devToolRedirect('yarn') },
  { path: '/dev/claude', redirect: devToolRedirect('claude-code') },
  {
    path: '/utilities',
    name: 'utilities',
    component: UtilitiesPage,
    meta: { shellTitle: '工具集' },
  },
  {
    path: '/settings',
    name: 'settings',
    component: SettingsPage,
    meta: { shellTitle: '设置' },
  },
  { path: '/toolbox', redirect: '/dev' },
]

export const router = createRouter({
  history: createWebHashHistory(),
  routes,
})
