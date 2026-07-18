# 原型代码（开发前参考）

本目录存放 **node 工具开发前的原型**，不参与安装包发布。

| 文件 | 说明 |
|------|------|
| `node-menu.ps1` | 原 `volta-node-menu.ps1`，固定视口版本选择菜单 |
| `volta-node-menu.bat` | 旧启动方式，正式版由 `miao node` 替代 |

开发时：

1. 将 `node-menu.ps1` 迁移至 `lib/browse-install.ps1`（见 [DESIGN.md](../DESIGN.md)）
2. 入口为 `index.ps1`；功能列表见 `index.json` → `actions`
3. 本 `_prototype/` 保留作对照或删除
