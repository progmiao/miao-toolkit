/**
 * 前端路由：网站 / 日常 / 开发 / Volta / Claude / 工具集 / 设置。
 */
import { createRouter, createWebHashHistory } from 'vue-router'
import HomeView from './views/HomeView.vue'
import DailyToolsView from './views/DailyToolsView.vue'
import DevToolsView from './views/DevToolsView.vue'
import VoltaManageView from './views/VoltaManageView.vue'
import ClaudeCodeView from './views/ClaudeCodeView.vue'
import SitesView from './views/SitesView.vue'
import UtilitiesView from './views/UtilitiesView.vue'
import SettingsView from './views/SettingsView.vue'

export const router = createRouter({
  history: createWebHashHistory(),
  routes: [
    { path: '/', name: 'home', component: HomeView },
    { path: '/sites', name: 'sites', component: SitesView },
    { path: '/daily', name: 'daily', component: DailyToolsView },
    { path: '/dev', name: 'dev', component: DevToolsView },
    {
      path: '/dev/node',
      name: 'node',
      component: VoltaManageView,
      props: { toolId: 'node', title: 'Node.js' },
    },
    {
      path: '/dev/pnpm',
      name: 'pnpm',
      component: VoltaManageView,
      props: { toolId: 'pnpm', title: 'Pnpm' },
    },
    {
      path: '/dev/yarn',
      name: 'yarn',
      component: VoltaManageView,
      props: { toolId: 'yarn', title: 'Yarn' },
    },
    { path: '/dev/claude', name: 'claude', component: ClaudeCodeView },
    { path: '/utilities', name: 'utilities', component: UtilitiesView },
    { path: '/settings', name: 'settings', component: SettingsView },
    { path: '/toolbox', redirect: '/dev' },
  ],
})
