/**
 * 前台任务忙碌态（全局可读；当前由开发工具 Job 写入）。
 * 用于片区锁定：侧栏、工具列表等，无需逐个改按钮。
 */
import { readonly, ref } from 'vue'

const busy = ref(false)

/** 由任务宿主写入（如开发工具 useJobConsole.busy）。 */
export function setForegroundJobBusy(on: boolean) {
  busy.value = Boolean(on)
}

/** 只读订阅。 */
export function useForegroundJobBusy() {
  return readonly(busy)
}
