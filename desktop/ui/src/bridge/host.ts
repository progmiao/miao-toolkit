/**
 * WebView2 宿主探测与原始 postMessage 封装。
 * 浏览器里直接打开 Vite 时 host 不可用，post 会 console.warn，便于纯前端调试。
 */

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
   * 向 C# 宿主发送一条消息（对象会被 JSON.stringify）。
   * @param message - 任意可序列化载荷；通常含 `type` 字段
   */
  post(message: unknown) {
    const wv = getWebView()
    if (!wv) {
      console.warn('[miao] host unavailable', message)
      return
    }
    wv.postMessage(JSON.stringify(message))
  },

  /**
   * 订阅宿主回传的 message 事件。
   * @param listener - 标准 MessageEvent 回调；data 多为 JSON 字符串
   */
  addMessageListener(listener: (event: MessageEvent) => void) {
    const wv = getWebView()
    if (!wv) return
    wv.addEventListener('message', listener)
  },
}
