/**
 * 页面级壳层顶栏标题：挂载时写入；卸载时仅在仍是本页标题时才恢复默认。
 * （避免路由切换时：新页已 setTitle → 旧页 onUnmounted 又清回「Miao 工具箱」的竞态。）
 * 标题可为静态字符串或响应式来源（ref / computed / getter）。
 */
import {
  onUnmounted,
  toValue,
  watch,
  type MaybeRefOrGetter,
} from 'vue'
import { getShellTitle, setShellTitle } from '@kernel/bridge/shellTitle'

/**
 * 规范化标题：去空白；空则视为「未声明」（卸载时不参与比较）。
 * @param raw - 原始标题
 */
function normalizeTitle(raw: string | null | undefined): string {
  return String(raw ?? '').trim()
}

/**
 * 将当前页标题同步到壳层顶栏中间位置（替换默认「Miao 工具箱」）。
 * @param title - 标题文案；支持 ref / computed / getter / 普通字符串
 */
export function useShellTitle(title: MaybeRefOrGetter<string>): void {
  watch(
    () => toValue(title),
    (t) => setShellTitle(t),
    { immediate: true },
  )
  onUnmounted(() => {
    const mine = normalizeTitle(toValue(title))
    if (!mine) return
    // 新页若已改写顶栏，则不要清掉
    if (getShellTitle() === mine) {
      setShellTitle(null)
    }
  })
}
