# Claude Code

通过 Miao 工具箱管理 Claude Code CLI：

- **安装 / 更新 / 卸载**：WinGet 包 `Anthropic.ClaudeCode`
- **初始化**：写入 `~/.claude/settings.json` 默认项（如 `DISABLE_LOGIN_COMMAND=1`）
- **配置 API / 代理**：敏感值存于 `%APPDATA%\Miao\claude-code.json`，合并写入 settings
- **插件**：添加市场、安装 / 卸载 / 更新插件（调用 `claude plugin` CLI）

推荐顺序：安装 → 初始化 → 配置 API →（可选）配置代理 → 安装插件。

可选配合 [cc-connect](https://github.com/chenhg5/cc-connect)（独立工具，若已提供）。
