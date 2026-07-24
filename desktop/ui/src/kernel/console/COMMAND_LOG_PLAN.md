# 命令 / 日志显示组件实施方案（已落地要点）

## 组件边界

- `CommandPane` / `LogPane`：独立封闭组件，只显示 `entries`；样子不同，共用 `logEntries` 纯函数。
- `JobProgressBar`：只显示 `progress` / `statusText`，不算进度。
- `JobConsole`：壳（进度 + Tab），组装上述组件。

## 条目语义

- 无 id → append
- 有 id → 首次 append，再次同 id 原位更新
- 新 job → `clear()`

## 业务职责（Node 示例）

- `voltaJobView.ts`：解析 Fetching、算整段进度、写入 append/upsert（方法拆分）。
- 通过 `setViewAdapters` / `useJobConsole` 选项挂到 Job，不进显示组件。

## 实施时优化清单

1. 行数上限与淘汰自动行
2. tone：dim/ok/warn/err
3. 空态 HTML 占位
4. 超长行不折行 + 横滚（命令窗）
5. 去掉全文 reset 闪烁路径（已用条目模型）
6. 嵌入共用 Job：`setViewAdapters` 运行时挂载
7. 任务结束业务移除 Fetching 行 id
