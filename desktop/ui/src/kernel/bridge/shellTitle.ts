/**
 * 壳层顶栏中间标题总线。
 * 各内容页通过 `setShellTitle` / `useShellTitle` 传入当前页标题，替换默认「Miao 工具箱」。
 * 由 AppShell 内的 ShellTopTitle 订阅并渲染。
 */

/** 未设置页面标题时的默认文案。 */
export const DEFAULT_SHELL_TITLE = 'Miao 工具箱'

type Listener = (title: string) => void

const listeners = new Set<Listener>()
/** 当前顶栏标题；空串视为回退默认。 */
let currentTitle = DEFAULT_SHELL_TITLE

function emit() {
  const snap = currentTitle
  listeners.forEach((fn) => fn(snap))
}

/**
 * 订阅顶栏标题变化（ShellTopTitle 挂载时注册）。
 * @param fn - 收到最新标题文案
 * @returns 取消订阅
 */
export function subscribeShellTitle(fn: Listener): () => void {
  listeners.add(fn)
  fn(currentTitle)
  return () => listeners.delete(fn)
}

/**
 * 设置壳层顶栏中间标题。
 * @param title - 页面标题；传空 / null / undefined 时恢复默认「Miao 工具箱」
 */
export function setShellTitle(title: string | null | undefined): void {
  const next = String(title ?? '').trim() || DEFAULT_SHELL_TITLE
  if (next === currentTitle) return
  currentTitle = next
  emit()
}

/**
 * 读取当前顶栏标题（一般仅调试用；UI 请订阅）。
 */
export function getShellTitle(): string {
  return currentTitle
}
