# slash_commands.md 研究文档

## 场景与职责

slash_commands.md 是 Codex CLI 项目中关于 Slash Commands（斜杠命令）功能的文档入口。该文档非常简洁，仅作为指向官方详细文档的链接入口。

**适用场景：**
- 用户需要了解可用的斜杠命令
- 开发者使用斜杠命令与 Codex 交互
- 自定义或扩展斜杠命令

## 功能点目的

### 1. 斜杠命令入口
- **目的**：提供斜杠命令文档的快速入口
- **方式**：链接到 OpenAI 开发者门户的详细文档

### 2. 命令功能指引
- 引导用户到官方文档获取斜杠命令的完整列表和说明
- 涵盖内置命令和自定义命令

## 具体技术实现

### 文档结构

```markdown
# Slash commands

For an overview of Codex CLI slash commands, see [this documentation](https://developers.openai.com/codex/cli/slash-commands).
```

### 链接目标

- **URL**: https://developers.openai.com/codex/cli/slash-commands
- **内容**：详细的斜杠命令文档

## 关键代码路径与文件引用

### 相关文件位置

| 文件路径 | 说明 |
|---------|------|
| `/home/sansha/Github/codex/docs/slash_commands.md` | 本文档 |
| `/home/sansha/Github/codex/codex-rs/tui/src/bottom_pane/slash_commands.rs` | 斜杠命令实现 |
| `/home/sansha/Github/codex/docs/tui-chat-composer.md` | 聊天编辑器文档（包含斜杠命令处理） |

### 已知斜杠命令（根据其他文档）

根据 `exit-confirmation-prompt-design.md`：
- `/quit` - 退出（shutdown-first）
- `/exit` - 退出（shutdown-first）
- `/logout` - 退出（shutdown-first）
- `/new` - 新会话（shutdown 不退出）

根据 `tui-chat-composer.md`：
- `/plan` - 计划模式
- `/review` - 审查模式
- `/prompts:` - 自定义提示

根据 `config.md`：
- `/apps` - 列出可用应用

### 斜杠命令处理（根据 `tui-chat-composer.md`）

**内置命令可用性**：
- 集中在 `codex-rs/tui/src/bottom_pane/slash_commands.rs`
- 由 composer 和命令弹出窗口重用

**配置控制**：
- `slash_commands_enabled` 配置标志
- 禁用时不将 `/...` 输入视为命令

## 依赖与外部交互

### 外部依赖

1. **OpenAI 开发者门户**
   - 详细斜杠命令文档

### 可能的斜杠命令功能（推测）

基于常见 CLI 工具模式和已知命令：

1. **会话管理**
   - `/new` - 新会话
   - `/quit`, `/exit`, `/logout` - 退出

2. **模式切换**
   - `/plan` - 计划模式
   - `/review` - 审查模式

3. **应用集成**
   - `/apps` - 列出应用
   - `$` - 插入 ChatGPT connector

4. **提示和技能**
   - `/prompts:` - 自定义提示
   - `/skill:` - 使用技能

5. **帮助和配置**
   - `/help` - 帮助（推测）
   - `/config` - 配置（推测）

## 风险、边界与改进建议

### 潜在风险

1. **文档过于简略**
   - 当前文档仅包含一个链接，离线时无法查看
   - 建议：添加基本的斜杠命令列表

2. **链接失效风险**
   - 外部链接可能变更
   - 建议：定期检查链接有效性

3. **命令发现困难**
   - 用户可能不了解所有可用命令
   - 建议：添加命令参考

### 边界情况

1. **命令冲突**
   - 自定义提示与内置命令的冲突
   - 命令名称解析优先级

2. **命令参数**
   - 参数解析规则
   - 特殊字符处理

3. **命令上下文**
   - 某些命令仅在特定模式下可用
   - 模态打开时的命令行为

### 改进建议

1. **本地命令参考**
   - 添加常用命令列表：
     ```markdown
     ## 常用斜杠命令
     
     | 命令 | 描述 |
     |-----|------|
     | /quit, /exit, /logout | 退出 Codex |
     | /new | 开始新会话 |
     | /plan | 进入计划模式 |
     | /review | 进入审查模式 |
     | /apps | 列出可用应用 |
     ```

2. **命令自动完成**
   - 在 TUI 中提供命令补全
   - 命令描述提示

3. **自定义命令**
   - 添加自定义命令的说明
   - 命令别名支持

4. **帮助系统**
   - `/help` 命令显示本地帮助
   - 命令特定帮助（如 `/help plan`）

5. **命令历史**
   - 记录命令使用历史
   - 快速重新执行

6. **命令别名**
   - 允许用户定义快捷方式
   - 常用命令的缩写
