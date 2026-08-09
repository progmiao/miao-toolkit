/**
 * 终端输出清洗：去掉 CSI / OSC 等控制序列（含窗口标题 ESC]0;…BEL）。
 * ConPTY 常会吐出 `ESC]0;C:\…\powershell.exe BEL`，不是中文乱码。
 */
export function stripAnsiAndOsc(input: string): string {
  if (!input) return input
  let s = input
  // OSC：ESC ] … BEL 或 ESC ] … ESC \
  s = s.replace(/\u001b\][^\u0007\u001b]*(?:\u0007|\u001b\\)/g, '')
  // CSI：ESC [ … 最终字节
  s = s.replace(/\u001b\[[0-9;?]*[ -/]*[@-~]/g, '')
  // 其它短 ESC 序列（如 ESC =）
  s = s.replace(/\u001b./g, '')
  // 残留 BEL / 退格
  s = s.replace(/[\u0007\u0008]/g, '')
  return s
}
