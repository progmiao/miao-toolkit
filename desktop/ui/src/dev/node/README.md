# Node.js 专用页

本目录仅服务 **Node.js** 工具页，不与 Pnpm / Yarn 共用模板。

- 页面：`index.vue`（Tab：批量安装 / 指定版本 / 设默认 / 批量卸载）
- 公共：`JobConsole` + `useJobConsole`（见 `desktop/DEVELOPMENT.md`）
- Host：`Miao.Software/Dev/Volta`
- 种子：`seeds/dev/node/software.json`（`ui.entry: "node"`）

新增类似运行时工具时：**复制本目录为新文件夹并改文案/逻辑**，不要抽成通用「Volta 包管理页」。
