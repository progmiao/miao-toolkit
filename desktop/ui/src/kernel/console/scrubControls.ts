/**
 * 终端控制序列清洗（通用，无业务语义）。
 */

export function scrubConsoleControls(chunk: string): string {
  let text = chunk
  // CSI（含 ESC[K / ESC[2K 清行）
  text = text.replace(/\u001b\[[0-9;?]*[ -/]*[@-~]/g, '')
  text = text.replace(/\u009b[0-9;?]*[ -/]*[@-~]/g, '')
  // ESC 已丢：残留 [K] / [2K] 等
  text = text.replace(/\[[\??0-9;]*[A-Za-z]/g, '')
  text = text.replace(/\[K\]/gi, '')
  // 清行拆残后常见的行首 / 粘连 K]（无业务含义）
  text = text.replace(/(^|[\r\n])K\]+/gm, '$1')
  text = text.replace(/K\]+/g, '')
  text = text.replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, '')
  return text
}

/** 写出前再剥一层行首清行残留。 */
export function stripLeadingClearResidue(line: string): string {
  return line.replace(/^[\s]*K\]+/i, '').replace(/^\]+/, '')
}
