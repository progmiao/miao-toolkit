/**
 * Vue 应用入口。
 * 挂载根组件、注册路由，并引入全局样式。
 */
import { createApp } from 'vue'
import App from './App.vue'
import { router } from './router'
import './styles.css'

createApp(App).use(router).mount('#app')
