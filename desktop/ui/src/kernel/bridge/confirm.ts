/**
 * 全局确认对话框总线。
 * 任意页面调用 `confirmDialog`；由 AppShell 内的 AppConfirm 统一渲染。
 */
export type ConfirmTone = 'default' | 'danger'

/** 打开确认框时的参数。 */
export type ConfirmOptions = {
  /** 标题；默认「请确认」 */
  title?: string
  /** 正文说明 */
  message: string
  /** 确认按钮文案；默认「确认」 */
  confirmText?: string
  /** 取消按钮文案；默认「取消」 */
  cancelText?: string
  /** 危险操作（卸载/删除）用 danger 样式 */
  tone?: ConfirmTone
}

/** 当前展示中的请求（组件订阅）。 */
export type ConfirmRequest = Required<ConfirmOptions> & {
  id: number
}

type Resolver = (ok: boolean) => void
type Listener = (req: ConfirmRequest | null) => void

const listeners = new Set<Listener>()
let seq = 0
let current: ConfirmRequest | null = null
let resolveCurrent: Resolver | null = null

function emit() {
  const snap = current
  listeners.forEach((fn) => fn(snap))
}

/**
 * 订阅当前确认请求（AppConfirm 挂载时注册）。
 * @param fn - 收到当前请求或 null
 * @returns 取消订阅
 */
export function subscribeConfirm(fn: Listener): () => void {
  listeners.add(fn)
  fn(current)
  return () => listeners.delete(fn)
}

/**
 * 弹出确认框，等待用户选择。
 * @param options - 文案与样式
 * @returns Promise：确认 true / 取消或关闭 false
 */
export function confirmDialog(options: ConfirmOptions | string): Promise<boolean> {
  const opts: ConfirmOptions = typeof options === 'string' ? { message: options } : options
  // 若已有打开的确认，先按取消结束，再打开新的
  if (resolveCurrent) {
    resolveCurrent(false)
    resolveCurrent = null
  }
  const id = ++seq
  current = {
    id,
    title: opts.title?.trim() || '请确认',
    message: String(opts.message ?? '').trim() || '确定继续吗？',
    confirmText: opts.confirmText?.trim() || '确认',
    cancelText: opts.cancelText?.trim() || '取消',
    tone: opts.tone === 'danger' ? 'danger' : 'default',
  }
  emit()
  return new Promise<boolean>((resolve) => {
    resolveCurrent = resolve
  })
}

/**
 * 结束当前确认（由 AppConfirm 调用）。
 * @param ok - 是否确认
 */
export function resolveConfirm(ok: boolean): void {
  if (!resolveCurrent) {
    current = null
    emit()
    return
  }
  const r = resolveCurrent
  resolveCurrent = null
  current = null
  emit()
  r(ok)
}
