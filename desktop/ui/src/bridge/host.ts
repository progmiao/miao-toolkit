/**
 * WebView2 宿主探测；无宿主时走 Mock，便于浏览器调试。
 */
import { handleMockRequest } from './mockHost'

/** 取得 Edge WebView2 注入的 chrome.webview（非 WebView 环境为 undefined）。 */
function getWebView() {
  return window.chrome?.webview
}

export const host = {
  /**
   * @returns 当前是否运行在 WebView2 内（可与 C# 通信）
   */
  available(): boolean {
    return Boolean(getWebView())
  },

  /**
   * 是否为浏览器 Mock 调试模式（无 WebView2）。
   */
  isMock(): boolean {
    return !getWebView()
  },

  /**
   * 向 C# 宿主发送消息；无宿主时转交 Mock。
   * @param message - 任意可序列化载荷；通常含 `type` 字段
   */
  post(message: unknown) {
    const wv = getWebView()
    if (!wv) {
      handleMockRequest((message ?? {}) as Record<string, unknown>)
      return
    }
    wv.postMessage(JSON.stringify(message))
  },

  /**
   * 订阅宿主回传的 message 事件（Mock 模式由 bus 另接 emitter）。
   * @param listener - 标准 MessageEvent 回调
   */
  addMessageListener(listener: (event: MessageEvent) => void) {
    const wv = getWebView()
    if (!wv) return
    wv.addEventListener('message', listener)
  },
}
