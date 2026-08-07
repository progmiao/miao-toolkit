/**
 * 工具展示元数据：分类标签中文、Logo 字标（UI 与 Mock 共用）。
 */
import type { CatalogItem } from '@kernel/bridge/bus'

/** 标签 id → 中文分类名（过滤条用）。 */
export const TAG_LABELS: Record<string, string> = {
  chat: '通讯',
  remote: '远程',
  runtime: '运行时',
  ai: 'AI',
  cli: 'CLI',
  terminal: '终端',
}

/**
 * 不参与顶部分类过滤的 tag（前置条件标记等）。
 */
export const FILTER_EXCLUDE_TAGS = new Set(['needs-volta', 'volta', 'needs-node'])

/** 前置条件：需要已安装 Volta 工具。 */
export const TAG_NEEDS_VOLTA = 'needs-volta'

/** 前置条件：需要已安装 Node.js 18+。 */
export const TAG_NEEDS_NODE = 'needs-node'

/**
 * 工具是否标注需要 Volta。
 * @param it - 目录项
 */
export function needsVolta(it: CatalogItem | null | undefined): boolean {
  return Boolean(it?.tags.includes(TAG_NEEDS_VOLTA))
}

/**
 * 工具是否标注需要 Node.js。
 * @param it - 目录项
 */
export function needsNode(it: CatalogItem | null | undefined): boolean {
  return Boolean(it?.tags.includes(TAG_NEEDS_NODE))
}

/**
 * 从版本字符串取主版本号；无法解析时返回 null。
 * @param version - 如 18.20.0 / v20.11.1
 */
export function parseNodeMajor(version: string | null | undefined): number | null {
  if (!version) return null
  const m = /^v?(\d+)/i.exec(version.trim())
  if (!m) return null
  const n = Number(m[1])
  return Number.isFinite(n) ? n : null
}

/**
 * 目录中 Node.js 是否满足 ≥18（供 needs-node 闸门）。
 * @param items - 开发工具目录
 */
export function isNodePrereqMet(items: CatalogItem[]): boolean {
  const node = items.find((i) => i.id === 'node')
  if (!node || node.status !== 'installed') return false
  const major = parseNodeMajor(node.version)
  // 已安装但版本未知：放行（宿主 Handler 仍会再校验）
  if (major == null) return true
  return major >= 18
}

/**
 * needs-node 工具在缺少 Node 18+ 时阻塞安装/更新。
 * @param it - 当前工具
 * @param items - 完整目录
 */
export function isBlockedByNodePrereq(
  it: CatalogItem | null | undefined,
  items: CatalogItem[],
): boolean {
  if (!it || !needsNode(it)) return false
  return !isNodePrereqMet(items)
}

/** 工具 id → 卡片 Logo 字与色相。 */
export const TOOL_LOGOS: Record<string, { letter: string; hue: number }> = {
  wechat: { letter: '微', hue: 142 },
  sunlogin: { letter: '葵', hue: 28 },
  node: { letter: 'N', hue: 145 },
  pnpm: { letter: 'P', hue: 210 },
  yarn: { letter: 'Y', hue: 265 },
  'claude-code': { letter: 'C', hue: 25 },
  'terminal-buddy': { letter: 'T', hue: 190 },
  'cc-switch': { letter: 'S', hue: 220 },
  'cc-connect': { letter: '连', hue: 300 },
  hermes: { letter: 'H', hue: 48 },
  volta: { letter: 'V', hue: 175 },
}

/**
 * 从条目集合推导过滤分类（全部 + 出现过的业务 tag，排除基础设施 tag）。
 * @param items - 目录项
 */
export function buildTagFilters(items: CatalogItem[]): { id: string; label: string }[] {
  const seen = new Set<string>()
  const filters: { id: string; label: string }[] = [{ id: 'all', label: '全部' }]
  for (const it of items) {
    for (const tag of it.tags) {
      if (FILTER_EXCLUDE_TAGS.has(tag) || seen.has(tag)) continue
      seen.add(tag)
      filters.push({ id: tag, label: TAG_LABELS[tag] ?? tag })
    }
  }
  return filters
}

/**
 * 是否显示「安装」：未安装 / 未知。
 * pnpm / yarn 由面板批量安装自管，概览不提供。
 * @param it - 目录项
 */
export function showInstallAction(it: CatalogItem): boolean {
  if (it.id === 'pnpm' || it.id === 'yarn') return false
  return it.actions.includes('install') && it.status !== 'installed'
}

/**
 * 是否显示「更新」：已安装、有更新标记，且非 node/pnpm/yarn（多版本面板自管）。
 * @param it - 目录项
 */
export function showUpdateAction(it: CatalogItem): boolean {
  if (it.id === 'node' || it.id === 'pnpm' || it.id === 'yarn') return false
  return it.actions.includes('install') && it.status === 'installed' && Boolean(it.updateAvailable)
}

/**
 * 是否显示「卸载」：已安装；node/pnpm/yarn 由 Volta 面板批量自管，概览不提供。
 * @param it - 目录项
 */
export function showUninstallAction(it: CatalogItem): boolean {
  if (it.id === 'node' || it.id === 'pnpm' || it.id === 'yarn') return false
  return it.actions.includes('uninstall') && it.status === 'installed'
}
