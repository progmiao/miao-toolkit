# AI 工具首次配置使用说明

本文记录安装 **Claude Code、CC Switch、CC Connect、Hermes** 之后，实际走过的配置步骤，便于下次复用或换机对照。

适用前提：上述工具已通过喵工具箱安装完成；本机已有可用的第三方 API（Base URL + Key）。

---

## 1. 先配 CC Switch（给 Claude Code 用）

CC Switch 管理的是 Claude Code 等 CLI 的供应商配置，写入用户目录下的 Claude 配置，**不会**自动同步给 Hermes。

### 1.1 你需要准备的材料

| 项目 | 是否必需 | 说明 |
|------|----------|------|
| API 密钥 | 是 | 服务商提供的 Key / Token |
| API 端点（Base URL） | 第三方必填 | 如 `http://主机:端口`；官方 Anthropic 常可走预设 |
| API 格式 | 第三方常要 | Anthropic 兼容代理选 Messages |
| 目标应用 | 是 | 先选 **Claude Code** 再添加供应商 |

### 1.2 操作步骤

1. 打开本机 **CC Switch**。
2. 左侧切到 **Claude Code**。
3. 添加供应商：
   - 有预设：选对应预设，填 API Key 即可；
   - 无预设 / 中转：选 **自定义配置**，粘贴服务商给出的 JSON。
4. 自定义 JSON 形态示例（把占位符换成你的真实值）：

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "env": {
    "ANTHROPIC_BASE_URL": "http://你的主机:端口",
    "ANTHROPIC_AUTH_TOKEN": "你的密钥",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
    "CLAUDE_CODE_ATTRIBUTION_HEADER": "0"
  }
}
```

说明：

- 有的服务商用 `ANTHROPIC_API_KEY`，有的用 `ANTHROPIC_AUTH_TOKEN`，以服务商文档为准。
- 额外的 `CLAUDE_CODE_*` 变量若服务商要求，一并保留。

5. 保存后点 **启用**（写入 `%USERPROFILE%\.claude\settings.json`）。
6. Claude Code 一般即时生效；新开终端执行 `claude` 试一句即可验证。

### 1.3 不必再做的事

已通过 CC Switch 启用配置后，**不必**再在 PowerShell 里手动执行 `$env:ANTHROPIC_...`，除非你只想做一次性临时会话覆盖。

---

## 2. 再配 Hermes（独立配置）

Hermes 使用自己的配置目录（如 `~/.hermes/`），与 Claude Code / CC Switch **互不替代**。  
即使 CC Switch 已配好，首次运行 `hermes` 仍可能提示未配置推理供应商。

### 2.1 首次提示

```text
No inference provider is configured yet — let's fix that.
Set up a provider now? [Y/n]:
```

**选 `Y`。**

选 `n` 会跳过；之后仍无法正常对话，需再跑 setup / `hermes model`。

### 2.2 填写自定义 API

按你当时的实际选择：

| 步骤 | 填写 / 选择 |
|------|-------------|
| API base URL | 与 Claude 相同的中转地址，例如 `http://主机:端口`（一般**不要**多加 `/v1`，除非服务商明确要求） |
| API key | 同一套密钥（可填；提示为 optional 时也建议填） |
| API compatibility mode | **`4. Anthropic Messages`** |
| 可用模型 | 列表里选模型；日常代理任务优先更强档（例如 `*-pro`），要更快更省可选 `*-flash` |
| Context length | **直接回车留空**（auto-detect） |
| Display name | 任意好认名称，或回车用默认（主机:端口） |

兼容模式说明（对照）：

| 选项 | 何时选 |
|------|--------|
| 1 Auto-detect | 标准 OpenAI 兼容端点、不确定时才用；你这种 Anthropic 中转**不要选** |
| 2 Chat Completions | OpenAI `/chat/completions` |
| 3 Responses / Codex | Codex `/responses` |
| **4 Anthropic Messages** | **Claude / Anthropic 兼容代理（本说明采用）** |

### 2.3 可选：Nous Portal

若你有 Nous Portal 订阅，也可在供应商步骤走 **Portal OAuth**（浏览器登录），不必手填 Key。  
本说明按「已有第三方 Anthropic 兼容 API」路径记录。

### 2.4 验证

配置完成后，在终端运行：

```powershell
hermes
```

能正常对话即表示推理供应商已生效。

---

## 3. 两套配置的关系（易错点）

```text
CC Switch  →  ~/.claude/settings.json   →  Claude Code
Hermes 交互配置 →  ~/.hermes/…            →  Hermes CLI
```

- 只配 CC Switch：**Claude Code 可用，Hermes 仍可能无 provider**。
- 只配 Hermes：**Hermes 可用，Claude Code 不受影响**。
- 两边可填**同一** Base URL + Key，但是各自启用一次。

---

## 4. 安全与维护建议

1. **不要把含密钥的 JSON / 截图提交到 Git 或发到公开群。** 密钥一旦暴露，到服务商后台轮换。
2. Hermes 安装/更新前，按产品提示开启科学上网的 **TUN 模式**（与本机代理策略有关）。
3. 换模型：Hermes 可再跑 `hermes model`；Claude 侧在 CC Switch 切换供应商并启用。
4. CC Connect：安装后按该工具自身文档连接即可；供应商密钥仍以 CC Switch / 各 CLI 配置为准。

---

## 5. 速查清单

安装完成后最少做两件事：

1. **CC Switch**：Claude Code → 自定义/预设 → 填 Base URL + Key → **启用** → `claude` 验证。  
2. **Hermes**：`hermes` → 设 provider 选 **Y** → 填同一套 URL/Key → 兼容模式选 **4** → 选模型 → Context 留空 → 起显示名 → 对话验证。

全部通过后即可日常使用。
