/**
 * 目录项安装状态的展示文案与 CSS class。
 * 日常工具卡片与开发工具列表共用，避免两处文案漂移。
 */
import type { CatalogItem } from '@kernel/bridge/bus'

/**
 * 列表/卡片上的状态短标签。
 * 已安装优先显示版本号；「有更新」由 Logo 角标表达，不写进本标签。
 * @param it - 目录项
 * @returns 如 `v20.11.0` / `已安装` / `未安装` / `未知`
 */
export function catalogStatusLabel(it: CatalogItem): string {
  if (it.status === 'installed') {
    return it.version ? `v${it.version}` : '已安装'
  }
  if (it.status === 'missing') return '未安装'
  return '未知'
}

/**
 * 状态样式 class（与全局 `.status-installed` 等约定一致）。
 * @param it - 目录项
 * @returns 如 `status-installed`
 */
export function catalogStatusClass(it: CatalogItem): string {
  return 'status-' + it.status
}
