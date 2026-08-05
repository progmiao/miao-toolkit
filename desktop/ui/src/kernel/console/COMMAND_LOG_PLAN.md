# 任务输出（单轨）

- `useLogEntries` / `logEntries.ts`：条目缓冲与 upsert。
- `CommandPane`：封闭显示组件，只读 `entries`。
- `JobConsole`：进度条 + 梯形「输出」Tab + `CommandPane`。
- `useJobConsole`：`kind=log` / `kind=console` / 开始结束文案写入同一 `outputLog` 时间线。
