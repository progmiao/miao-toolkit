import { createInstallConsoleAdapter } from './src/dev/consoleAdapters/installTty.ts'

const lines: { id?: string; op: string; text: string; tone?: string }[] = []
const sink = {
  append: (t: string, tone?: string) => lines.push({ op: 'append', text: t, tone }),
  upsert: (id: string, t: string, tone?: string) => {
    const i = lines.findIndex((l) => l.id === id)
    const r = { id, op: 'upsert', text: t, tone }
    if (i >= 0) lines[i] = r
    else lines.push(r)
  },
  remove: (id: string) => {
    for (let i = lines.length - 1; i >= 0; i--) if (lines[i].id === id) lines.splice(i, 1)
  },
}
const a = createInstallConsoleAdapter()
const api = {
  append: sink.append,
  upsert: sink.upsert,
  remove: sink.remove,
  setProgress: () => {},
  setStatusText: () => {},
}
const chunk =
  'Prepared 1 package in 2.88s\n' +
  '█░░░░░░░░░░░░░░░░░░░ [6/100] pyjwt==2.13.0          ' +
  '█░░░░░░░░░░░░░░░░░░░ [9/100] termcolor==3.3.0        ' +
  '███████████████████░ [99/100] openai==2.24.0\n' +
  'Installed 100 packages in 978ms\n' +
  ' + agent-client-protocol==0.9.0\n' +
  ' + aiohttp==3.14.3\n'
a.onConsoleChunk(chunk, api)
console.log(JSON.stringify(lines, null, 2))
