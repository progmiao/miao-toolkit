/**
 * Volta 包版本列表的纯函数辅助（过滤、增量标记、日志解析）。
 * 不包含 Tab / 布局；由各工具页自行调用。
 */
import type { Ref } from 'vue'
import type { VoltaVersion } from '@kernel/bridge/bus'

/** 去掉版本号中的点/空白，便于「265」匹配「26.5.0」。 */
export function compactVersionKey(s: string) {
  return s.toLowerCase().replace(/[.\s_-]/g, '')
}

/**
 * 版本过滤：子串匹配，或忽略点号的紧凑匹配；LTS 名也可匹配。
 */
export function matchesVersionFilter(
  version: string,
  lts: string | null | undefined,
  rawQuery: string,
): boolean {
  const q = rawQuery.trim().toLowerCase()
  if (!q) return true
  const ver = version.toLowerCase()
  const ltsText = (lts ?? '').toLowerCase()
  if (ver.includes(q) || ltsText.includes(q)) return true
  const qCompact = compactVersionKey(q)
  if (!qCompact) return false
  return compactVersionKey(ver).includes(qCompact) || compactVersionKey(ltsText).includes(qCompact)
}

export function findVersionIndex(versions: VoltaVersion[], version: string): number {
  const ver = version.trim().replace(/^v/i, '')
  if (!ver) return -1
  return versions.findIndex(
    (x) => x.version.replace(/^v/i, '').toLowerCase() === ver.toLowerCase(),
  )
}

/**
 * 安装成功后就地更新清单。
 * @returns 是否改动了列表
 */
export function markToolInstalled(
  versions: Ref<VoltaVersion[]>,
  selected: Ref<Record<string, boolean>>,
  version: string,
): boolean {
  const idx = findVersionIndex(versions.value, version)
  if (idx < 0) return false
  const cur = versions.value[idx]!
  if (cur.installed) {
    selected.value[cur.version] = false
    return false
  }
  versions.value.splice(idx, 1, { ...cur, installed: true })
  selected.value[cur.version] = false
  return true
}

/**
 * 卸载成功后就地更新清单；若卸掉默认版本则回落 defaultPick。
 */
export function markToolUninstalled(
  versions: Ref<VoltaVersion[]>,
  selected: Ref<Record<string, boolean>>,
  defaultPick: Ref<string | null>,
  version: string,
): boolean {
  const idx = findVersionIndex(versions.value, version)
  if (idx < 0) return false
  const cur = versions.value[idx]!
  if (!cur.installed) {
    selected.value[cur.version] = false
    return false
  }
  const wasDefault =
    !!defaultPick.value &&
    defaultPick.value.replace(/^v/i, '').toLowerCase() ===
      cur.version.replace(/^v/i, '').toLowerCase()
  versions.value.splice(idx, 1, { ...cur, installed: false, isDefault: false })
  selected.value[cur.version] = false
  if (wasDefault || cur.isDefault) {
    defaultPick.value =
      versions.value.find((x) => x.isDefault)?.version ??
      versions.value.find((x) => x.installed)?.version ??
      null
  }
  return true
}

/**
 * 根据任务日志/命令输出，按条更新版本列表。
 * @param toolId - node | pnpm | yarn
 */
export function tryApplyVersionListFromMessage(
  toolId: string,
  message: string,
  versions: Ref<VoltaVersion[]>,
  selected: Ref<Record<string, boolean>>,
  defaultPick: Ref<string | null>,
): void {
  const pkg = toolId.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
  const done = new RegExp(
    `(?:^|\\s)version-done\\s+(install|uninstall)\\s+${pkg}@(\\S+)`,
    'i',
  ).exec(message)
  if (done?.[1] && done[2]) {
    if (done[1].toLowerCase() === 'uninstall') {
      markToolUninstalled(versions, selected, defaultPick, done[2])
    } else {
      markToolInstalled(versions, selected, done[2])
    }
    return
  }

  const installedLog = new RegExp(`安装成功\\s+${pkg}@(\\S+)`, 'i').exec(message)
  if (installedLog?.[1]) {
    markToolInstalled(versions, selected, installedLog[1])
    return
  }
  const installedConsole = new RegExp(
    `success:\\s*installed.*?${pkg}@([vV]?\\d[\\w.-]*)`,
    'i',
  ).exec(message)
  if (installedConsole?.[1]) {
    markToolInstalled(versions, selected, installedConsole[1])
    return
  }

  const removedLog = new RegExp(`已干净移除\\s+${pkg}@(\\S+)`, 'i').exec(message)
  if (removedLog?.[1]) markToolUninstalled(versions, selected, defaultPick, removedLog[1])
}
