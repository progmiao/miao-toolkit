/**
 * 前端路由：按侧栏分区组装（sites / daily / dev / utilities）。
 * 各分区入口为文件夹内 index.vue；专用面板页对应 seeds `ui.entry`。
 * `meta.shellTitle`：壳层顶栏中间标题。
 */
import { createRouter, createWebHashHistory, type RouteRecordRaw } from 'vue-router'
import HomePage from '@shell/home/index.vue'
import SettingsPage from '@shell/settings/index.vue'
import SitesPage from '@sites/index.vue'
import DailyPage from '@daily/index.vue'
import DevPage from '@dev/index.vue'
import NodePage from '@dev/node/index.vue'
import PnpmPage from '@dev/pnpm/index.vue'
import YarnPage from '@dev/yarn/index.vue'
import VoltaPage from '@dev/volta/index.vue'
import ClaudePage from '@dev/claude/index.vue'
import UtilitiesPage from '@utilities/index.vue'

declare module 'vue-router' {
  interface RouteMeta {
    /** 壳层顶栏中间标题；缺省则保持上一页或默认「Miao 工具箱」 */
    shellTitle?: string
  }
}

const routes: RouteRecordRaw[] = [
  { path: '/', name: 'home', component: HomePage, meta: { shellTitle: '首页' } },
  { path: '/sites', name: 'sites', component: SitesPage, meta: { shellTitle: '常用网站' } },
  { path: '/daily', name: 'daily', component: DailyPage, meta: { shellTitle: '日常工具' } },
  { path: '/dev', name: 'dev', component: DevPage, meta: { shellTitle: '开发工具' } },
  {
    path: '/dev/volta',
    name: 'volta',
    component: VoltaPage,
    meta: { shellTitle: 'Volta' },
  },
  {
    path: '/dev/node',
    name: 'node',
    component: NodePage,
    meta: { shellTitle: 'Node.js' },
  },
  {
    path: '/dev/pnpm',
    name: 'pnpm',
    component: PnpmPage,
    meta: { shellTitle: 'Pnpm' },
  },
  {
    path: '/dev/yarn',
    name: 'yarn',
    component: YarnPage,
    meta: { shellTitle: 'Yarn' },
  },
  {
    path: '/dev/claude',
    name: 'claude',
    component: ClaudePage,
    meta: { shellTitle: 'Claude Code' },
  },
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
