/**
 * 安装类工具 TTY 适配器：CLI 转圈 + winget/IWR/块状条 + git remote / uv / Playwright 下载。
 * 供 useJobConsole.onConsoleChunk 挂载；内核输出层不包含这些业务语义。
 */

import type { ConsoleChunkHandlers } from '@kernel/composables/useJobConsole'
import { scrubConsoleControls, stripLeadingClearResidue } from '@kernel/console/scrubControls'

export type InstallTtySink = {
  append: (text: string, tone?: 'plain' | 'dim' | 'ok' | 'warn' | 'err' | 'accent') => void
  upsert: (id: string, text: string, tone?: 'plain' | 'dim' | 'ok' | 'warn' | 'err' | 'accent') => void
  remove: (id: string) => void
}

export type InstallTtySession = {
  pending: string
  /** 当前转圈动画槽；每条正文后递增，保证下一段转圈是新行 */
  spinnerSlot: number
  /** 是否正在写当前槽的转圈帧 */
  inSpinner: boolean
  /** 是否已画出下载进度行 */
  hasDownloadLine: boolean
  /** uv Preparing packages 刷屏中：吞掉逐行包进度条 */
  inUvPrepare: boolean
  /** uv Installing packages（█░ [n/m] pkg）刷屏中 */
  inUvInstall: boolean
  /** Playwright 浏览器组件下载刷屏中 */
  inPlaywrightDownload: boolean
  /** 当前 Playwright 下载资源名（短） */
  playwrightAsset: string
  /** 下载进度条峰值（只升不降） */
  peakDownloadMapped: number
}

export type ApplyConsoleChunkResult = {
  /** 下载进度 0–100（由已下载/总大小推算） */
  downloadPct?: number
  /** 如 17.0 MB */
  downloaded?: string
  /** 如 79.4 MB */
  total?: string
}

/** 仅转圈字符的一行（可带空白）。 */
const SPINNER_ONLY_RE = /^\s*[-\\|\/]\s*$/

/** winget：`17.0 MB / 79.4 MB`（前可有进度块字符）。 */
const WINGET_SIZE_RE =
  /(\d+(?:\.\d+)?)\s*(B|KB|MB|GB|TB)\s*\/\s*(\d+(?:\.\d+)?)\s*(B|KB|MB|GB|TB)/i

/** PowerShell Invoke-WebRequest 进度（中/英）：应原地刷新，勿 append 刷屏。 */
const PSH_IWR_PROGRESS_RE =
  /(?:正在写入(?:\s*Web\s*)?请求|正在写入请求流|Writing\s+(?:web\s+)?request|Written\s+\d+\s+bytes|已写入字节数\s*[:：]?\s*\d+)/i

/** winget / 终端块状进度条：`████░░░░  28%`（含 \r 叠帧或粘连多帧）。 */
const BLOCK_PROGRESS_RE = /[█▉▊▋▌▍▎▏░▒▓]/

/**
 * git 进度（Hermes install 克隆等），可无换行粘连多帧；同阶段 upsert 一行。
 * - `remote: Counting objects:  33% (3158/9569)`
 * - `Receiving objects:   1% (96/9570), 548.00 KiB | 471.00 KiB/s`
 * - `Resolving deltas: …`
 */
const GIT_PROGRESS_PHASE =
  'Counting objects|Compressing objects|Receiving objects|Resolving deltas'
const GIT_PROGRESS_RE = new RegExp(
  String.raw`(?:remote:\s*)?(${GIT_PROGRESS_PHASE}):\s*(\d{1,3})%\s*(?:\(([^)]*)\))?(?:\s*,\s*done\.)?(?:\s*,\s*(\d[\d.]*\s*[KMGT]?i?B(?:\s*\|\s*[\d.]+\s*[KMGT]?i?B\/s)?))?`,
  'gi',
)

export const WINGET_DOWNLOAD_LINE_ID = 'winget:download'
export const PSH_IWR_PROGRESS_LINE_ID = 'psh:iwr-progress'
export const BLOCK_PROGRESS_LINE_ID = 'console:block-progress'
export const GIT_REMOTE_PROGRESS_LINE_PREFIX = 'git:remote:'
/** @deprecated 使用 GIT_REMOTE_PROGRESS_LINE_PREFIX；兼容旧名 */
export const GIT_PROGRESS_LINE_PREFIX = GIT_REMOTE_PROGRESS_LINE_PREFIX
export const UV_PREPARE_LINE_ID = 'uv:preparing-packages'
export const UV_INSTALL_LINE_ID = 'uv:installing-packages'
export const PLAYWRIGHT_DOWNLOAD_LINE_ID = 'playwright:download'

/** uv「Preparing packages...(n/m)」多包进度条（TTY 整屏刷新）。 */
const UV_PREPARING_RE = /Preparing packages\.\.\.\s*\((\d+)\/(\d+)\)/gi
const UV_BUILDING_RE = /Building\s+\S+\s+@\s+file:\/\/\/[^\s\u00a0]+/gi
const UV_PKG_BAR_RE =
  /[a-zA-Z0-9_.+-]+\s+-{5,}\s+(?:[\d.]+\s*(?:B|KiB|MiB|GiB)|0\s*B)\s*\/\s*[\d.]+\s*(?:B|KiB|MiB|GiB)/g
const UV_SPINNER_RE = /[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]/g
const UV_PREPARED_RE = /Prepared\s+(\d+)\s+packages\s+in\s+[^\r\n]+/i
const UV_BUILT_RE = /Built\s+\S+\s+@\s+file:\/\/\/[^\s\u00a0]+/i
const UV_INSTALL_WHEELS_RE = /Installing wheels\.\.\./i
/** uv pip install：`█░░░░ [6/100] pyjwt==2.13.0`（可粘连多帧）。 */
const UV_INSTALL_FRAME_RE =
  /[█▉▊▋▌▍▎▏░▒▓]+\s*\[(\d+)\/(\d+)\]\s*([^\s\u00a0]+)/g
const UV_INSTALLED_RE = /Installed\s+(\d+)\s+packages\s+in\s+[^\r\n]+/i
const UV_PLUS_PKG_RE = /^\+\s+[a-zA-Z0-9_.+-]+(?:==\S+)?\s*$/m

/** Playwright：`Downloading … from https://…` / `|■■|  10% of 172.8 MiB` / `… downloaded to …` */
const PW_DOWNLOADING_RE = /Downloading\s+(.+?)\s+from\s+https?:\/\/\S+/gi
const PW_DOWNLOADED_RE = /^(.+?)\s+downloaded\s+to\s+\S+/i
const PW_PROGRESS_RE = /\|[^|\r\n]*\|\s*(\d{1,3})%\s+of\s+([\d.]+\s*[KMGT]?i?B)/gi

export function createInstallTtySession(): InstallTtySession {
  return {
    pending: '',
    spinnerSlot: 0,
    inSpinner: false,
    hasDownloadLine: false,
    inUvPrepare: false,
    inUvInstall: false,
    inPlaywrightDownload: false,
    playwrightAsset: '',
    peakDownloadMapped: 0,
  }
}

export function isSpinnerOnlyLine(line: string): boolean {
  return SPINNER_ONLY_RE.test(line)
}

/** ASCII 框线（uv/installer 进度装饰）：`+---------+` */
const ASCII_RULE_ONLY_RE = /^\+[-=+]{4,}\+$/

export const ASCII_RULE_LINE_ID = 'console:ascii-rule'

/**
 * 框线与正文粘连时拆开：`+----+K] Managed uv…` → 框线 + 第二行正文。
 * `K]` / `[K]` 为清行转义残留。
 */
export function splitAsciiRuleGluedLine(
  line: string,
): { rule: string; rest: string } | null {
  const m = /^(\+[-=+]{4,}\+)(?:\[?K\])?(.*)$/s.exec(line)
  if (!m) return null
  const rule = m[1]!
  const rest = (m[2] ?? '')
    .replace(/^\[?K\]/i, '')
    .replace(/^\s+/, '')
  return { rule, rest }
}

function isAsciiRuleOnlyLine(line: string): boolean {
  return ASCII_RULE_ONLY_RE.test(line.trim())
}

function emitAsciiRule(
  session: InstallTtySession,
  line: string,
  sink: InstallTtySink,
  mode: 'hard' | 'soft',
): boolean {
  if (!isAsciiRuleOnlyLine(line)) return false
  clearSpinnerLine(session, sink)
  const text = line.trim()
  if (mode === 'soft') {
    // \r 刷新的进度装饰：临时一行
    sink.upsert(ASCII_RULE_LINE_ID, text, 'dim')
    return true
  }
  // 换行写出的框线（安装横幅上下边）：永久保留
  sink.remove(ASCII_RULE_LINE_ID)
  sink.append(text, 'accent')
  session.spinnerSlot += 1
  return true
}

/** 安装器 ASCII/Unicode 横幅行（边框或 | 内容 |）。 */
function isInstallerBannerLine(line: string): boolean {
  const t = line.trimEnd()
  const s = t.trim()
  if (!s) return false
  if (ASCII_RULE_ONLY_RE.test(s)) return true
  if (/^\|.*\|$/.test(s)) return true
  if (/^[┌├└╔╠╚].*[┐┤┘╗╣╝]$/u.test(s)) return true
  if (/^[│║].*[│║]$/u.test(s)) return true
  return false
}

function spinnerLineId(slot: number): string {
  return `console:spinner:${slot}`
}

function formatSpinnerDisplay(line: string): string {
  const g = line.trim() || '-'
  return `   ${g}`
}

function unitToBytes(n: number, unit: string): number {
  const u = unit.toUpperCase()
  const mul =
    u === 'KB' ? 1024
    : u === 'MB' ? 1024 ** 2
    : u === 'GB' ? 1024 ** 3
    : u === 'TB' ? 1024 ** 4
    : 1
  return n * mul
}

export function parseWingetDownloadLine(
  line: string,
): { downloaded: string; total: string; pct: number } | null {
  const m = WINGET_SIZE_RE.exec(line)
  if (!m) return null
  const doneN = Number(m[1])
  const totalN = Number(m[3])
  if (!Number.isFinite(doneN) || !Number.isFinite(totalN) || totalN <= 0) return null
  const doneUnit = m[2]!
  const totalUnit = m[4]!
  const pct = Math.round(
    Math.min(
      100,
      Math.max(0, (unitToBytes(doneN, doneUnit) / unitToBytes(totalN, totalUnit)) * 100),
    ),
  )
  return {
    downloaded: `${m[1]} ${doneUnit.toUpperCase()}`,
    total: `${m[3]} ${totalUnit.toUpperCase()}`,
    pct,
  }
}

export type GitRemoteProgressFrame = {
  phase: string
  pct: number
  detail?: string
  /** 如 `300.00 KiB | 518.00 KiB/s` */
  transfer?: string
  /** 是否带 `remote:` 前缀 */
  remote?: boolean
}

/** 从一行（可粘连多帧）解析全部 git 进度帧（含 Receiving / Resolving）。 */
export function parseGitRemoteProgressFrames(line: string): GitRemoteProgressFrame[] {
  const frames: GitRemoteProgressFrame[] = []
  const re = new RegExp(GIT_PROGRESS_RE.source, 'gi')
  let m: RegExpExecArray | null
  while ((m = re.exec(line)) !== null) {
    const pct = Number(m[2])
    if (!Number.isFinite(pct) || pct < 0 || pct > 100) continue
    const phase = (m[1] ?? '').trim()
    if (!phase) continue
    const detail = (m[3] ?? '').trim()
    const transfer = (m[4] ?? '').trim()
    frames.push({
      phase,
      pct,
      detail: detail || undefined,
      transfer: transfer || undefined,
      remote: /^remote:/i.test(m[0] ?? ''),
    })
  }
  return frames
}

function gitRemotePhaseId(phase: string): string {
  const slug = phase.trim().toLowerCase().replace(/\s+/g, '-')
  return `${GIT_REMOTE_PROGRESS_LINE_PREFIX}${slug}`
}

function formatGitProgressLine(frame: GitRemoteProgressFrame): string {
  const prefix = frame.remote ? 'remote: ' : ''
  const detail = frame.detail ? ` (${frame.detail})` : ''
  const transfer = frame.transfer ? `, ${frame.transfer}` : ''
  return `${prefix}${frame.phase}: ${frame.pct}%${detail}${transfer}`
}

function formatBar(pct: number, width = 16): string {
  const p = Math.max(0, Math.min(100, Math.round(pct)))
  const filled = Math.round((p / 100) * width)
  const head = filled > 0 ? '='.repeat(Math.max(0, filled - 1)) + '>' : ''
  const rest = ' '.repeat(Math.max(0, width - head.length))
  return `[${head}${rest}]`
}

function formatDownloadLine(downloaded: string, total: string, pct: number): string {
  return `下载 ${downloaded} / ${total}  ${formatBar(pct)} ${String(pct).padStart(3, ' ')}%`
}

function clearSpinnerLine(session: InstallTtySession, sink: InstallTtySink) {
  if (!session.inSpinner) return
  sink.remove(spinnerLineId(session.spinnerSlot))
  session.inSpinner = false
}

function emitSpinner(session: InstallTtySession, line: string, sink: InstallTtySink) {
  // 已有下载进度时不再刷转圈，避免盖住有效信息
  if (session.hasDownloadLine) return
  session.inSpinner = true
  sink.upsert(spinnerLineId(session.spinnerSlot), formatSpinnerDisplay(line), 'dim')
}

function emitDownload(
  session: InstallTtySession,
  line: string,
  sink: InstallTtySink,
): ApplyConsoleChunkResult | null {
  const parsed = parseWingetDownloadLine(line)
  if (!parsed) return null
  clearSpinnerLine(session, sink)
  session.hasDownloadLine = true
  sink.upsert(
    WINGET_DOWNLOAD_LINE_ID,
    formatDownloadLine(parsed.downloaded, parsed.total, parsed.pct),
  )
  return {
    downloadPct: parsed.pct,
    downloaded: parsed.downloaded,
    total: parsed.total,
  }
}

/** PowerShell IWR 进度：收成单行；能解析字节时推进度。 */
function emitPshIwrProgress(
  session: InstallTtySession,
  line: string,
  sink: InstallTtySink,
): ApplyConsoleChunkResult | null {
  if (!PSH_IWR_PROGRESS_RE.test(line)) return null
  clearSpinnerLine(session, sink)
  session.hasDownloadLine = true
  const m =
    /\(已写入字节数:\s*(\d+)\)/i.exec(line) ||
    /已写入字节数\s*[:：]?\s*(\d+)/i.exec(line) ||
    /Written\s+(\d+)\s+bytes/i.exec(line)
  const n = m ? Number(m[1]) : NaN
  let text = '下载中…'
  let downloadPct: number | undefined
  if (Number.isFinite(n) && n >= 0) {
    const mb = n / (1024 * 1024)
    text =
      mb >= 0.1
        ? `下载中… 已写入 ${mb.toFixed(1)} MB`
        : `下载中… 已写入 ${n} 字节`
    // 无总大小时只做缓慢爬升提示（上限 85，留给后续 ##progress）
    downloadPct = Math.min(85, Math.max(5, Math.round(Math.log10(n + 10) * 18)))
  }
  sink.upsert(PSH_IWR_PROGRESS_LINE_ID, text, 'dim')
  return downloadPct != null ? { downloadPct } : {}
}

/** 解析块状进度条中最后一个百分比（粘连多帧时取最新）。 */
export function parseBlockProgressPct(line: string): number | null {
  if (!BLOCK_PROGRESS_RE.test(line)) return null
  const matches = [...line.matchAll(/(\d{1,3})\s*%/g)]
  if (!matches.length) return null
  const pct = Number(matches[matches.length - 1]![1])
  if (!Number.isFinite(pct) || pct < 0 || pct > 100) return null
  return pct
}

function emitBlockProgress(
  session: InstallTtySession,
  line: string,
  sink: InstallTtySink,
): ApplyConsoleChunkResult | null {
  const pct = parseBlockProgressPct(line)
  if (pct == null) return null
  clearSpinnerLine(session, sink)
  session.hasDownloadLine = true
  sink.upsert(BLOCK_PROGRESS_LINE_ID, `下载进度  ${formatBar(pct)} ${String(pct).padStart(3, ' ')}%`, 'dim')
  return { downloadPct: pct }
}

/**
 * git 分阶段进度：同阶段原地刷新；Counting / Compressing / Receiving / Resolving 各占一行。
 * @returns 是否识别为纯 git 进度并已消费
 */
function emitGitRemoteProgress(
  session: InstallTtySession,
  line: string,
  sink: InstallTtySink,
): boolean {
  const frames = parseGitRemoteProgressFrames(line)
  if (!frames.length) return false

  // 去掉全部进度帧后若仍有正文，则不是纯进度行（交给 emitContent）
  const leftover = line
    .replace(new RegExp(GIT_PROGRESS_RE.source, 'gi'), '')
    .replace(/^[\s,;:.-]+|[\s,;:.-]+$/g, '')
    .trim()
  if (leftover) return false

  clearSpinnerLine(session, sink)
  const latestByPhase = new Map<string, GitRemoteProgressFrame>()
  for (const frame of frames) {
    latestByPhase.set(frame.phase.toLowerCase(), frame)
  }
  for (const frame of latestByPhase.values()) {
    sink.upsert(gitRemotePhaseId(frame.phase), formatGitProgressLine(frame), 'dim')
  }
  return true
}

/** 去掉 uv Preparing packages TTY 装饰后的残留正文。 */
function stripUvPrepareChrome(line: string): string {
  let t = line
  t = t.replace(UV_BUILDING_RE, '')
  t = t.replace(UV_SPINNER_RE, '')
  t = t.replace(UV_PREPARING_RE, '')
  t = t.replace(UV_PKG_BAR_RE, '')
  t = t.replace(/░+/g, '')
  t = t.replace(/[\u00a0 \t]+/g, ' ').trim()
  return t
}

/** 单行包进度 / Building… 等应在 Preparing 阶段吞掉的噪声。 */
function isUvPrepareNoiseLine(line: string): boolean {
  const t = line.trim()
  if (!t) return true
  if (UV_BUILDING_RE.test(t)) {
    UV_BUILDING_RE.lastIndex = 0
    return true
  }
  UV_PKG_BAR_RE.lastIndex = 0
  if (UV_PKG_BAR_RE.test(t)) {
    const alone = t.replace(UV_PKG_BAR_RE, '').replace(UV_SPINNER_RE, '').trim()
    UV_PKG_BAR_RE.lastIndex = 0
    if (!alone) return true
  }
  if (/^░+\s*(?:\[\d+\/\d+\])?/.test(t) && t.length < 80) return true
  return false
}

/**
 * uv Preparing packages 整屏刷新：收成单行进度；Built / Prepared 等里程碑另 append。
 */
function emitUvPrepareProgress(
  session: InstallTtySession,
  line: string,
  sink: InstallTtySink,
): ApplyConsoleChunkResult | null {
  const preparing = [...line.matchAll(new RegExp(UV_PREPARING_RE.source, 'gi'))]
  const pkgBars = line.match(UV_PKG_BAR_RE)?.length ?? 0
  const hasBuilding = UV_BUILDING_RE.test(line)
  UV_BUILDING_RE.lastIndex = 0

  const looksLikeUv =
    preparing.length > 0 ||
    (pkgBars >= 3 && hasBuilding) ||
    (pkgBars >= 5 && /KiB|MiB/i.test(line))

  if (!looksLikeUv) return null

  const leftover = stripUvPrepareChrome(line)
  const leftoverOk =
    !leftover ||
    UV_PREPARED_RE.test(leftover) ||
    UV_BUILT_RE.test(leftover) ||
    UV_INSTALL_WHEELS_RE.test(leftover) ||
    leftover.length <= 24
  // 明确的 Preparing 帧 / 大量包进度条：一律折叠，避免残留噪声导致刷屏
  if (!leftoverOk && preparing.length === 0 && pkgBars < 8) return null

  clearSpinnerLine(session, sink)
  session.hasDownloadLine = true
  session.inUvPrepare = true

  let downloadPct: number | undefined
  if (preparing.length) {
    const last = preparing[preparing.length - 1]!
    const cur = Number(last[1])
    const total = Number(last[2])
    if (Number.isFinite(cur) && Number.isFinite(total) && total > 0) {
      downloadPct = Math.round(Math.min(100, Math.max(0, (cur / total) * 100)))
      sink.upsert(
        UV_PREPARE_LINE_ID,
        `Preparing packages... (${cur}/${total})  ${formatBar(downloadPct)} ${String(downloadPct).padStart(3, ' ')}%`,
        'dim',
      )
    } else {
      sink.upsert(UV_PREPARE_LINE_ID, 'Preparing packages…', 'dim')
    }
  } else {
    sink.upsert(UV_PREPARE_LINE_ID, 'Preparing packages…', 'dim')
  }

  // 里程碑：从原始行里抽一次即可
  const built = UV_BUILT_RE.exec(line)
  if (built) sink.append(built[0]!, 'dim')
  const prepared = UV_PREPARED_RE.exec(line)
  if (prepared) {
    session.inUvPrepare = false
    sink.remove(UV_PREPARE_LINE_ID)
    sink.append(prepared[0]!, 'ok')
  }
  if (UV_INSTALL_WHEELS_RE.test(line)) {
    sink.upsert(UV_PREPARE_LINE_ID, 'Installing wheels…', 'dim')
    session.inUvPrepare = false
  }

  return downloadPct != null ? { downloadPct } : {}
}

function stripUvInstallChrome(line: string): string {
  let t = line
  t = t.replace(new RegExp(UV_INSTALL_FRAME_RE.source, 'g'), '')
  t = t.replace(/^\+\s+[a-zA-Z0-9_.+-]+(?:==\S+)?\s*$/gm, '')
  t = t.replace(/[█▉▊▋▌▍▎▏░▒▓]+/g, '')
  t = t.replace(/[\u00a0 \t]+/g, ' ').trim()
  return t
}

/**
 * uv pip install 块状进度：`█░ [n/m] pkg==ver` 收成单行；Installed 里程碑另 append。
 */
function emitUvInstallProgress(
  session: InstallTtySession,
  line: string,
  sink: InstallTtySink,
): ApplyConsoleChunkResult | null {
  const frames = [...line.matchAll(new RegExp(UV_INSTALL_FRAME_RE.source, 'g'))]
  const looksLike =
    frames.length > 0 ||
    (BLOCK_PROGRESS_RE.test(line) && /\[\d+\/\d+\]/.test(line) && /==/.test(line))
  if (!looksLike) return null

  const leftover = stripUvInstallChrome(line)
  const leftoverOk =
    !leftover ||
    UV_INSTALLED_RE.test(leftover) ||
    UV_PREPARED_RE.test(leftover) ||
    leftover.length <= 24
  if (!leftoverOk && frames.length < 2) return null

  clearSpinnerLine(session, sink)
  session.hasDownloadLine = true
  session.inUvInstall = true
  session.inUvPrepare = false

  let downloadPct: number | undefined
  if (frames.length) {
    const last = frames[frames.length - 1]!
    const cur = Number(last[1])
    const total = Number(last[2])
    const pkg = (last[3] ?? '').trim()
    if (Number.isFinite(cur) && Number.isFinite(total) && total > 0) {
      downloadPct = Math.round(Math.min(100, Math.max(0, (cur / total) * 100)))
      const pkgHint = pkg ? `  ${pkg}` : ''
      sink.upsert(
        UV_INSTALL_LINE_ID,
        `Installing packages... (${cur}/${total})  ${formatBar(downloadPct)} ${String(downloadPct).padStart(3, ' ')}%${pkgHint}`,
        'dim',
      )
    } else {
      sink.upsert(UV_INSTALL_LINE_ID, 'Installing packages…', 'dim')
    }
  } else {
    sink.upsert(UV_INSTALL_LINE_ID, 'Installing packages…', 'dim')
  }

  const prepared = UV_PREPARED_RE.exec(line)
  if (prepared) sink.append(prepared[0]!, 'ok')
  const installed = UV_INSTALLED_RE.exec(line)
  if (installed) {
    session.inUvInstall = false
    sink.remove(UV_INSTALL_LINE_ID)
    sink.append(installed[0]!, 'ok')
  }

  return downloadPct != null ? { downloadPct } : {}
}

function shortPlaywrightAsset(name: string): string {
  const t = name.trim()
  if (/Chrome for Testing/i.test(t)) return 'Chrome for Testing'
  if (/Chrome Headless Shell/i.test(t)) return 'Chrome Headless Shell'
  if (/FFmpeg/i.test(t)) return 'FFmpeg'
  if (/Winldd/i.test(t)) return 'Winldd'
  if (/playwright\s+(\S+)/i.test(t)) return RegExp.$1
  return t.length > 48 ? `${t.slice(0, 45)}…` : t
}

/**
 * Playwright 浏览器组件下载：进度条收成单行；Downloading / downloaded 里程碑保留。
 */
function emitPlaywrightDownloadProgress(
  session: InstallTtySession,
  line: string,
  sink: InstallTtySink,
): ApplyConsoleChunkResult | null {
  const downloading = [...line.matchAll(new RegExp(PW_DOWNLOADING_RE.source, 'gi'))]
  const progress = [...line.matchAll(new RegExp(PW_PROGRESS_RE.source, 'gi'))]
  const downloadedLine = PW_DOWNLOADED_RE.exec(line.trim())
  PW_DOWNLOADED_RE.lastIndex = 0

  const looksLike =
    downloading.length > 0 ||
    progress.length > 0 ||
    (session.inPlaywrightDownload && !!downloadedLine) ||
    (!!downloadedLine && /playwright|chromium|ffmpeg|winldd|ms-playwright/i.test(line))

  if (!looksLike) return null

  // 纯「downloaded to」且不在下载中：当里程碑（可能单独一行）
  if (downloadedLine && downloading.length === 0 && progress.length === 0) {
    clearSpinnerLine(session, sink)
    session.inPlaywrightDownload = false
    sink.remove(PLAYWRIGHT_DOWNLOAD_LINE_ID)
    sink.append(line.trim(), 'ok')
    session.spinnerSlot += 1
    return {}
  }

  clearSpinnerLine(session, sink)
  session.hasDownloadLine = true
  session.inPlaywrightDownload = true

  if (downloading.length) {
    const lastDl = downloading[downloading.length - 1]!
    session.playwrightAsset = shortPlaywrightAsset(lastDl[1] ?? 'Playwright asset')
  }

  let downloadPct: number | undefined
  let sizeHint = ''
  if (progress.length) {
    const last = progress[progress.length - 1]!
    const pct = Number(last[1])
    if (Number.isFinite(pct) && pct >= 0 && pct <= 100) {
      downloadPct = pct
      sizeHint = (last[2] ?? '').trim()
    }
  }

  const asset = session.playwrightAsset || 'Playwright'
  if (downloadPct != null) {
    const size = sizeHint ? ` of ${sizeHint}` : ''
    sink.upsert(
      PLAYWRIGHT_DOWNLOAD_LINE_ID,
      `Downloading ${asset}…  ${formatBar(downloadPct)} ${String(downloadPct).padStart(3, ' ')}%${size}`,
      'dim',
    )
  } else {
    sink.upsert(PLAYWRIGHT_DOWNLOAD_LINE_ID, `Downloading ${asset}…`, 'dim')
  }

  // 同块里若已完成某一资源
  const done = [...line.matchAll(/^.+?\s+downloaded\s+to\s+\S+/gim)]
  if (done.length) {
    const lastDone = done[done.length - 1]![0]!.trim()
    sink.remove(PLAYWRIGHT_DOWNLOAD_LINE_ID)
    sink.append(lastDone, 'ok')
    session.inPlaywrightDownload = false
    session.playwrightAsset = ''
  }

  return downloadPct != null ? { downloadPct } : {}
}

/** Preparing 阶段的单行里程碑 / 噪声。 */
function emitUvPrepareLineExtras(
  session: InstallTtySession,
  line: string,
  sink: InstallTtySink,
): boolean {
  const t = line.trim()
  if (!t) return false

  if (UV_BUILT_RE.test(t)) {
    clearSpinnerLine(session, sink)
    sink.append(t, 'dim')
    session.spinnerSlot += 1
    return true
  }
  if (UV_PREPARED_RE.test(t)) {
    clearSpinnerLine(session, sink)
    session.inUvPrepare = false
    sink.remove(UV_PREPARE_LINE_ID)
    sink.append(t, 'ok')
    session.spinnerSlot += 1
    return true
  }
  if (UV_INSTALLED_RE.test(t)) {
    clearSpinnerLine(session, sink)
    session.inUvInstall = false
    sink.remove(UV_INSTALL_LINE_ID)
    sink.append(t, 'ok')
    session.spinnerSlot += 1
    return true
  }
  if (UV_INSTALL_WHEELS_RE.test(t) && t.length < 48) {
    clearSpinnerLine(session, sink)
    session.inUvPrepare = false
    sink.upsert(UV_PREPARE_LINE_ID, 'Installing wheels…', 'dim')
    return true
  }
  // 单帧安装进度 / +pkg 列表噪声
  UV_INSTALL_FRAME_RE.lastIndex = 0
  if (UV_INSTALL_FRAME_RE.test(t)) {
    UV_INSTALL_FRAME_RE.lastIndex = 0
    const alone = stripUvInstallChrome(t)
    if (!alone) {
      emitUvInstallProgress(session, t, sink)
      return true
    }
  }
  if (UV_PLUS_PKG_RE.test(t)) return true
  if (session.inUvInstall && /^[█▉▊▋▌▍▎▏░▒▓]/.test(t)) return true
  // Playwright 进度条单行
  PW_PROGRESS_RE.lastIndex = 0
  if (PW_PROGRESS_RE.test(t)) {
    PW_PROGRESS_RE.lastIndex = 0
    emitPlaywrightDownloadProgress(session, t, sink)
    return true
  }
  PW_DOWNLOADING_RE.lastIndex = 0
  if (PW_DOWNLOADING_RE.test(t)) {
    PW_DOWNLOADING_RE.lastIndex = 0
    emitPlaywrightDownloadProgress(session, t, sink)
    return true
  }
  if (session.inUvPrepare && isUvPrepareNoiseLine(t)) return true
  // Building @ file:///… 即使尚未进入 Preparing，也是 uv 本地构建 TTY 噪声
  if (UV_BUILDING_RE.test(t)) {
    UV_BUILDING_RE.lastIndex = 0
    return true
  }
  return false
}

function emitContent(session: InstallTtySession, line: string, sink: InstallTtySink) {
  clearSpinnerLine(session, sink)
  let text = line.replace(/\s+$/u, '')
  text = stripLeadingClearResidue(text)
  if (!text.trim()) return
  // 原始进度行：已转成下载行，勿再 append
  if (parseWingetDownloadLine(text)) return
  if (PSH_IWR_PROGRESS_RE.test(text)) return
  if (emitPlaywrightDownloadProgress(session, text, sink)) return
  if (emitUvInstallProgress(session, text, sink)) return
  if (parseBlockProgressPct(text) != null) return
  if (emitGitRemoteProgress(session, text, sink)) return
  if (emitUvPrepareProgress(session, text, sink)) return
  if (emitUvPrepareLineExtras(session, text, sink)) return
  // 协议行偶发漏进 console 时丢弃
  if (/^##(?:progress|task|batch|log)\b/i.test(text.trim())) return

  // 框线与正文粘连：框线永久保留一行，正文换第二行
  const glued = splitAsciiRuleGluedLine(text)
  if (glued && glued.rest) {
    sink.remove(ASCII_RULE_LINE_ID)
    sink.append(glued.rule, 'accent')
    const rest = stripLeadingClearResidue(glued.rest)
    if (rest) {
      sink.append(rest, isInstallerBannerLine(rest) ? 'accent' : undefined)
    }
    session.spinnerSlot += 1
    return
  }

  // 安装横幅：+---+ / | … | 保留并着色（勿当临时进度删掉）
  if (isInstallerBannerLine(text)) {
    sink.remove(ASCII_RULE_LINE_ID)
    sink.append(text.trimEnd(), 'accent')
    session.spinnerSlot += 1
    return
  }

  sink.append(text)
  session.spinnerSlot += 1
}

/** 任务结束时清掉残留转圈行与半行缓冲。 */
export function finishInstallTtySession(
  session: InstallTtySession,
  sink: InstallTtySink,
): void {
  clearSpinnerLine(session, sink)
  session.pending = ''
  session.inUvPrepare = false
  session.inUvInstall = false
  session.inPlaywrightDownload = false
  session.playwrightAsset = ''
  session.peakDownloadMapped = 0
}

/**
 * 处理一块 console：\r 原地刷新转圈/下载；正文 append；半行进 pending。
 */
export function applyInstallTtyChunk(
  session: InstallTtySession,
  chunk: string,
  sink: InstallTtySink,
): ApplyConsoleChunkResult | undefined {
  if (!chunk) return undefined

  let text = scrubConsoleControls(session.pending + chunk)
  session.pending = ''

  let buf = ''
  let i = 0
  let lastDownload: ApplyConsoleChunkResult | undefined

  while (i < text.length) {
    const c = text[i]!
    if (c === '\r') {
      if (i + 1 < text.length && text[i + 1] === '\n') {
        const r = flushBuffer(session, buf, sink, 'hard')
        if (r) lastDownload = r
        buf = ''
        i += 2
        continue
      }
      const r = flushBuffer(session, buf, sink, 'soft')
      if (r) lastDownload = r
      buf = ''
      i += 1
      continue
    }
    if (c === '\n') {
      const r = flushBuffer(session, buf, sink, 'hard')
      if (r) lastDownload = r
      buf = ''
      i += 1
      continue
    }
    buf += c
    i += 1
  }

  if (!buf) return lastDownload

  if (isSpinnerOnlyLine(buf)) {
    emitSpinner(session, buf, sink)
    return lastDownload
  }
  const half = emitDownload(session, buf, sink)
  if (half) return half
  const iwr = emitPshIwrProgress(session, buf, sink)
  if (iwr) return iwr
  const pwHalf = emitPlaywrightDownloadProgress(session, buf, sink)
  if (pwHalf) return { ...lastDownload, ...pwHalf }
  const uvInstHalf = emitUvInstallProgress(session, buf, sink)
  if (uvInstHalf) return { ...lastDownload, ...uvInstHalf }
  const bar = emitBlockProgress(session, buf, sink)
  if (bar) return bar
  if (emitGitRemoteProgress(session, buf, sink)) return lastDownload
  const uvHalf = emitUvPrepareProgress(session, buf, sink)
  if (uvHalf) return { ...lastDownload, ...uvHalf }
  if (emitUvPrepareLineExtras(session, buf, sink)) return lastDownload
  if (emitAsciiRule(session, buf, sink, 'soft')) return lastDownload
  // 半行已是「框线+正文」粘连：拆开写出，勿继续 pending
  const gluedHalf = splitAsciiRuleGluedLine(buf)
  if (gluedHalf?.rest) {
    emitContent(session, buf, sink)
    return lastDownload
  }
  session.pending = buf
  return lastDownload
}

function flushBuffer(
  session: InstallTtySession,
  buf: string,
  sink: InstallTtySink,
  mode: 'hard' | 'soft',
): ApplyConsoleChunkResult | undefined {
  if (!buf.length) return undefined
  if (isSpinnerOnlyLine(buf)) {
    emitSpinner(session, buf, sink)
    return undefined
  }
  const dl = emitDownload(session, buf, sink)
  if (dl) return dl
  const iwr = emitPshIwrProgress(session, buf, sink)
  if (iwr) return iwr
  const pw = emitPlaywrightDownloadProgress(session, buf, sink)
  if (pw) return pw
  const uvInst = emitUvInstallProgress(session, buf, sink)
  if (uvInst) return uvInst
  const bar = emitBlockProgress(session, buf, sink)
  if (bar) return bar
  if (emitGitRemoteProgress(session, buf, sink)) return undefined
  const uv = emitUvPrepareProgress(session, buf, sink)
  if (uv) return uv
  if (emitUvPrepareLineExtras(session, buf, sink)) return undefined
  if (emitAsciiRule(session, buf, sink, mode)) return undefined
  // \r 刷未识别正文：软刷新不 append，避免半截进度块刷屏
  if (mode === 'soft') {
    const softGlued = splitAsciiRuleGluedLine(buf)
    if (softGlued?.rest) {
      emitContent(session, buf, sink)
      return undefined
    }
    session.pending = buf
    return undefined
  }
  emitContent(session, buf, sink)
  return undefined
}

function clampPct(pct: number): number {
  if (!Number.isFinite(pct)) return 0
  return Math.round(Math.min(100, Math.max(0, pct)))
}

function applyDownloadMappedProgress(
  session: InstallTtySession,
  api: ConsoleChunkHandlers,
  info: { downloadPct: number; downloaded: string; total: string },
) {
  // 下载阶段映射到总进度约 30–85，且只升不降（保留宿主 ##progress 下限由宿主覆盖）
  const mapped = clampPct(30 + (info.downloadPct / 100) * 55)
  if (mapped > session.peakDownloadMapped) {
    session.peakDownloadMapped = mapped
    api.setProgress(mapped)
    api.setStatusText(`下载 ${info.downloaded} / ${info.total}`)
  }
}

export type InstallConsoleAdapter = {
  onConsoleChunk: (chunk: string, api: ConsoleChunkHandlers) => void
  reset: () => void
}

/** 自持 session 的安装 TTY 适配器（挂到 useJobConsole options / setViewAdapters）。 */
export function createInstallConsoleAdapter(): InstallConsoleAdapter {
  let session = createInstallTtySession()
  return {
    reset() {
      session = createInstallTtySession()
    },
    onConsoleChunk(chunk, api) {
      const result = applyInstallTtyChunk(session, chunk, {
        append: api.append,
        upsert: api.upsert,
        remove: api.remove,
      })
      if (
        result?.downloadPct != null &&
        result.downloaded &&
        result.total
      ) {
        applyDownloadMappedProgress(session, api, {
          downloadPct: result.downloadPct,
          downloaded: result.downloaded,
          total: result.total,
        })
      }
    },
  }
}

/** 便捷：展开为 useJobConsole 的 onConsoleChunk + onConsoleReset。 */
export function installConsoleJobOptions(): {
  onConsoleChunk: InstallConsoleAdapter['onConsoleChunk']
  onConsoleReset: () => void
} {
  const adapter = createInstallConsoleAdapter()
  return {
    onConsoleChunk: adapter.onConsoleChunk,
    onConsoleReset: adapter.reset,
  }
}
