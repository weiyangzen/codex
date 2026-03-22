# README.md 研究文档

## 场景与职责

该 README 文件提供了 `codex-chatgpt` crate 的高层级概述，明确了该 crate 的用途范围和维护责任。它是开发者了解该 crate 的第一入口点。

## 功能点目的

1. **范围界定**：明确该 crate 与 ChatGPT 官方 API 和产品的关系
2. **维护声明**：说明该 crate 主要由 OpenAI 内部维护，外部贡献需要联系维护者

## 具体技术实现

### 内容分析

```markdown
# ChatGPT

This crate pertains to first party ChatGPT APIs and products such as Codex agent.

This crate should be primarily built and maintained by OpenAI employees. 
Please reach out to a maintainer before making an external contribution.
```

### 关键信息提取

1. **用途**：与第一方 ChatGPT API 和产品交互（特别是 Codex Agent）
2. **维护模式**：OpenAI 内部优先维护
3. **贡献指南**：外部贡献者需要先联系维护者

## 关键代码路径与文件引用

### 相关实现文件

| 文件 | 功能 |
|------|------|
| `src/chatgpt_client.rs` | ChatGPT 后端 API HTTP 客户端 |
| `src/chatgpt_token.rs` | ChatGPT 认证 token 管理 |
| `src/get_task.rs` | 获取 Codex Agent 任务数据 |
| `src/apply_command.rs` | 应用 Codex Agent 生成的 diff |
| `src/connectors.rs` | MCP Connectors/Apps 列表管理 |

### 调用方

- `codex-rs/cli/src/main.rs` - CLI 的 `Apply` 子命令调用 `run_apply_command`
- `codex-rs/tui_app_server/src/chatwidget/skills.rs` - TUI 中使用 connectors 功能
- `codex-rs/app-server/src/codex_message_processor/plugin_app_helpers.rs` - App Server 中使用 connectors

## 依赖与外部交互

### API 端点

该 crate 通过 `chatgpt_client.rs` 与以下 ChatGPT 后端 API 交互：

1. **任务 API**：`/wham/tasks/{task_id}` - 获取 Codex Agent 任务详情
2. **连接器目录 API**：通过 `connectors.rs` 调用目录列表接口

### 认证机制

依赖 `codex-core` 的认证系统：
- 从 `auth.json` 读取 token
- 使用 JWT access_token 进行 Bearer 认证
- 需要 `chatgpt-account-id` header

## 风险、边界与改进建议

### 风险

1. **内部 API 变更**：由于使用第一方 ChatGPT API，API 契约可能随时变更
2. **访问限制**：某些功能可能需要特定类型的 ChatGPT 账户（Plus/Pro/Enterprise）
3. **维护壁垒**：外部贡献受限，可能导致社区参与度低

### 边界

1. **非公开 API**：该 crate 使用的 API 不是公开的 OpenAI API，可能有访问限制
2. **Codex Agent 专用**：功能专门针对 Codex Agent 任务，不适用于一般 ChatGPT 使用
3. **内部工具定位**：明确作为内部工具 crate 定位，API 稳定性不保证

### 改进建议

1. **文档扩展**：
   - 添加更多关于支持的具体 API 端点的文档
   - 说明需要的认证类型和账户权限
   - 提供使用示例

2. **错误处理文档**：
   - 说明常见的 API 错误和如何处理
   - 文档化 token 过期和刷新机制

3. **测试文档**：
   - 说明如何运行测试（需要特定的认证设置）
   - 提供 mock 测试的指导

4. **架构图**：
   - 添加该 crate 在整体架构中的位置图
   - 展示与 ChatGPT 后端、codex-core 等的交互关系
