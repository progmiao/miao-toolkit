# Desktop 工程目录结构

按侧栏四大块用**标准英文**命名，打开目录即知对应哪块产品。  
**开发约定（如何新增工具、复用什么）→ [DEVELOPMENT.md](./DEVELOPMENT.md)。**

| 中文（侧栏） | 英文目录 | 说明 |
|--------------|----------|------|
| （壳） | `shell` | 窗口壳、导航、首页、设置 |
| （内核） | `kernel` | IPC、JobConsole、清单共用组件 |
| 常用网站 | `sites` | |
| 日常工具 | `daily` | |
| 开发工具 | `dev` | **不用 tools**，避免与「工具集」混淆 |
| 工具集 | `utilities` | |

入口页在分区/工具文件夹内统一为 `index.vue`（文件夹已区分身份，无需 `XxxView` 前缀）。

```text
desktop/
├── STRUCTURE.md
├── DEVELOPMENT.md            ← 开发约定（定稿）
├── src/
│   ├── Miao.App/             ← shell 宿主
│   ├── Miao.Common/ · Miao.Data/ ← kernel
│   ├── Miao.Software/
│   │   ├── Catalog/ · Jobs/ · Detect/
│   │   ├── Install/          ← 通用安装 Handler（日常+列表共用）
│   │   └── Dev/              ← 开发工具后端（Volta/Claude/…）
│   ├── Miao.Sites/           ← 常用网站后端
│   └── Miao.Utilities/       ← 工具集后端
│
├── ui/src/
│   ├── shell/
│   │   ├── home/index.vue
│   │   ├── settings/index.vue
│   │   └── components/       ← AppShell / Toast / Confirm / ShellTopTitle
│   ├── kernel/
│   │   ├── bridge/           ← IPC、外观、toast、confirm
│   │   ├── catalog/          ← ToolLogo、toolMeta、statusMeta
│   │   ├── components/       ← JobConsole
│   │   └── composables/      ← useJobConsole、useVoltaVersions、useShellTitle
│   ├── sites/index.vue
│   ├── daily/index.vue
│   ├── dev/
│   │   ├── index.vue         ← 开发工具列表（generic + 跳转 panel）
│   │   ├── volta/index.vue   ← Volta 本体安装页
│   │   ├── node/index.vue
│   │   ├── pnpm/index.vue
│   │   ├── yarn/index.vue
│   │   └── claude/index.vue
│   └── utilities/index.vue
│
└── seeds/
    ├── shell/                ← groups、i18n
    ├── sites/seed.json
    ├── daily/<id>/software.json
    ├── dev/<id>/software.json   ← ui.entry → /dev/{entry}
    └── utilities/registry.json
```

## Vite / TS 别名

- `@shell` → 壳  
- `@kernel` → 内核  
- `@sites` / `@daily` / `@dev` / `@utilities` → 四大内容区  

## 新增开发工具内某项（摘要）

完整步骤见 [DEVELOPMENT.md §3](./DEVELOPMENT.md)。要点：

1. `ui/src/dev/<entry>/index.vue`（panel 时）— **独立页，不抽通用工具页**  
2. `src/Miao.Software/Dev/<Id>/` 或复用 `Install/`  
3. `seeds/dev/<id>/software.json`（`ui.mode` + `ui.entry`）  
4. `router.ts` 注册 `/dev/<entry>`  

## 种子加载（SeedLoader）

1. 优先：`seeds/daily/**/software.json`、`seeds/dev/**/software.json`  
2. 兼容旧：`seeds/tools/**`、`seeds/software/{daily,dev}.json`（勿再新增）  
