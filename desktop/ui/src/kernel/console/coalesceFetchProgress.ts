/**
 * 命令窗展示清洗：正文 + 最多一行 Fetching 进度（无空行、无 ░ 字节条、无粘连）。
 */

function stripAnsi(s: string): string {
  return s.replace(/\u001b\[[0-9;?]*[ -/]*[@-~]/g, '')
}

function formatBar(pct: number, width = 16): string {
  const p = Math.max(0, Math.min(100, Math.round(pct)))
  const filled = Math.round((p / 100) * width)
  const head = filled > 0 ? '='.repeat(Math.max(0, filled - 1)) + '>' : ''
  const rest = ' '.repeat(Math.max(0, width - head.length))
  return `[${head}${rest}]`
}

export function formatFetchLine(pkg: string, pct: number): string {
  const p = Math.max(0, Math.min(100, Math.round(pct)))
  return `Fetching ${pkg}  ${formatBar(p)} ${String(p).padStart(3, ' ')}%`
}

function isFetchDebris(t: string): boolean {
  if (!t) return false
  if (/^\d{1,3}\s*%$/.test(t)) return true
  if (/^\]/.test(t) && t.length < 20) return true
  if (/^\[[=>\s]*\]?$/.test(t)) return true
  if (/^[=>\-\s\]]+$/.test(t)) return true
  return false
}

/** Volta 下载字节条 / 纯进度碎片，不进正文。 */
function isProgressNoise(t: string): boolean {
  if (t.includes('\u2591') || t.includes('\u2588')) return true
  if (/\d+\s*\/\s*\d+/.test(t) && t.length > 40 && !/Fetching/i.test(t)) return true
  return isFetchDebris(t)
}

/**
 * @param raw - 命令窗累积原文（可含粘连的 Fetching）
 */
export function renderConsoleWithFetchProgress(raw: string): string {
  if (!raw) return ''

  let text = stripAnsi(raw)
  // 无 \r 时多次 Fetching 粘在一行 → 强制拆开
  text = text.replace(/(?!^)(?=Fetching\s+\S+)/gi, '\n')
  text = text.replace(/\r/g, '\n')

  const body: string[] = []
  /** 取消/中断提示等，始终排在 Fetching 之后。 */
  const trailers: string[] = []
  let pkg = ''
  let pct: number | null = null

  for (const line of text.split(/\n/)) {
    const trimmed = line.trim()
    if (!trimmed) continue

    if (/^\^C\b/i.test(trimmed) || /任务已取消/.test(trimmed)) {
      trailers.push(trimmed)
      continue
    }

    const fetch = /Fetching\s+(\S+)/i.exec(trimmed)
    if (fetch) {
      pkg = fetch[1] ?? pkg
      const pm = /(\d{1,3})\s*%/.exec(trimmed)
      if (pm) pct = Number.parseInt(pm[1]!, 10)
      continue
    }

    if (isProgressNoise(trimmed)) {
      const pm = /^(\d{1,3})\s*%$/.exec(trimmed)
      if (pm && pkg) pct = Number.parseInt(pm[1]!, 10)
      continue
    }

    body.push(trimmed)
  }

  const parts: string[] = []
  if (body.length) parts.push(body.join('\n'))
  if (pkg) parts.push(formatFetchLine(pkg, pct ?? 0))
  if (trailers.length) parts.push(trailers.join('\n'))
  return parts.join('\n')
}
