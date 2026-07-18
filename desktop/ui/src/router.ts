/**
 * 前端路由：首页 / 日常工具 / 开发工具（Hash 模式）。
 */
import { createRouter, createWebHashHistory } from 'vue-router'
import HomeView from './views/HomeView.vue'
import GroupToolsView from './views/GroupToolsView.vue'

export const router = createRouter({
  history: createWebHashHistory(),
  routes: [
    { path: '/', name: 'home', component: HomeView },
    {
      path: '/daily',
      name: 'daily',
      component: GroupToolsView,
      props: {
        group: 'daily',
        title: '日常工具',
        subtitle: '通讯、远程等日常应用；多数为下载安装包并拉起厂商向导。',
      },
    },
    {
      path: '/dev',
      name: 'dev',
      component: GroupToolsView,
      props: {
        group: 'dev',
        title: '开发工具',
        subtitle: '编辑器/终端、运行时、AI 编码及配套（如 CC Switch）。',
      },
    },
    { path: '/toolbox', redirect: '/dev' },
  ],
})
