/// <reference types="vite/client" />

declare module '*.vue' {
  import type { DefineComponent } from 'vue'
  const component: DefineComponent<object, object, unknown>
  export default component
}

declare module '*.txt?raw' {
  const content: string
  export default content
}

interface Window {
  chrome?: {
    webview?: {
      postMessage: (message: unknown) => void
      addEventListener: (
        type: string,
        listener: (event: MessageEvent) => void,
      ) => void
      removeEventListener: (
        type: string,
        listener: (event: MessageEvent) => void,
      ) => void
    }
  }
}
