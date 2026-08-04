# Volta 包工具共用层

供 **Node.js / pnpm / Yarn** 各自业务页复用，**不是**通用页面组件。

| 文件 | 职责 |
|------|------|
| `voltaJobView.ts` | 命令窗 Fetching/Unpacking 进度解析 |
| `voltaVersionOps.ts` | 版本过滤、装/卸就地更新、日志解析 |
| `useVoltaPackagePage.ts` | 列表 / Tab / pin / Job 适配逻辑 |
| `voltaPackageWorkspace.css` | 梯形 Tab + 左右分栏样式 |

各工具入口仍是 `dev/{node,pnpm,yarn}/index.vue`：独立文案与模板，可单独演进。
