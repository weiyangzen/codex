# legacy_notify.rs 研究文档

## 场景与职责

`legacy_notify.rs` 是 codex-hooks crate 中的遗留通知模块，负责实现向后兼容的钩子通知机制。它主要服务于 Codex CLI/TUI 的遗留通知需求，当 Agent 完成一轮对话（turn）后，通过外部命令触发通知（如桌面通知、声音提示等）。

该模块是 Codex 钩子系统中**遗留兼容性层**的一部分，与新的 Claude Hooks 引擎并存但独立运作。

## 功能点目的

### 1. 遗留通知钩子创建 (`notify_hook`)
- **目的**：创建一个可在 `AfterAgent` 事件后执行的钩子
- **输入**：命令行参数向量 `argv`（要执行的外部命令及其参数）
- **输出**：`Hook` 结构体，可被注册到 Hooks 注册表

### 2. JSON 通知负载生成 (`legacy_notify_json`)
- **目的**：将钩子事件负载序列化为特定格式的 JSON
- **支持的事件类型**：仅支持 `AfterAgent` 事件
- **序列化格式**：使用 kebab-case 命名规范，带 `type` 标签的枚举序列化

### 3. 通知数据结构 (`UserNotification`)
- **类型**：内部枚举，仅包含 `AgentTurnComplete` 变体
- **字段**：
  - `thread_id`: 会话线程 ID
  - `turn_id`: 当前轮次 ID
  - `cwd`: 当前工作目录
  - `client`: 客户端标识（可选）
  - `input_messages`: 用户输入消息列表
  - `last_assistant_message`: 助手最后回复（可选）

## 具体技术实现

### 关键流程

```
notify_hook(argv)
  │
  ├─> 创建 Hook 结构体
  │     ├─ name: "legacy_notify"
  │     └─ func: 异步闭包
  │
  └─> 执行时流程
        ├─> command_from_argv(&argv) 解析命令
        ├─> legacy_notify_json(payload) 生成 JSON 负载
        ├─> command.arg(notify_payload) 将 JSON 作为最后一个参数附加
        └─> command.spawn() 异步执行（fire-and-forget）
```

### 数据结构

```rust
// 内部枚举，序列化为带 type 标签的 JSON
#[derive(Serialize)]
#[serde(tag = "type", rename_all = "kebab-case")]
enum UserNotification {
    #[serde(rename_all = "kebab-case")]
    AgentTurnComplete {
        thread_id: String,
        turn_id: String,
        cwd: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        client: Option<String>,
        input_messages: Vec<String>,
        last_assistant_message: Option<String>,
    },
}
```

### 序列化示例

```json
{
  "type": "agent-turn-complete",
  "thread-id": "b5f6c1c2-1111-2222-3333-444455556666",
  "turn-id": "12345",
  "cwd": "/Users/example/project",
  "client": "codex-tui",
  "input-messages": ["Rename `foo` to `bar` and update the callsites."],
  "last-assistant-message": "Rename complete and verified `cargo build` succeeds."
}
```

### 命令执行特性

- **Stdio 处理**：所有标准输入/输出/错误都被重定向到 `Stdio::null()`
- **执行模式**：Fire-and-forget（不等待命令完成，不检查退出码）
- **错误处理**：命令启动失败返回 `HookResult::FailedContinue`，不影响后续钩子执行

## 关键代码路径与文件引用

### 当前文件内关键代码

| 行号 | 代码 | 说明 |
|------|------|------|
| 13-26 | `UserNotification` 枚举定义 | 通知数据结构，使用 kebab-case 序列化 |
| 28-44 | `legacy_notify_json` 函数 | JSON 负载生成，仅支持 AfterAgent 事件 |
| 46-73 | `notify_hook` 函数 | 钩子创建，返回可执行的 Hook 结构体 |
| 57-59 | 命令构建与空检查 | 使用 `command_from_argv` 解析命令行 |
| 61-69 | 命令配置 | 设置 stdio 为 null，实现 fire-and-forget |

### 跨文件引用

| 引用目标 | 路径 | 用途 |
|----------|------|------|
| `Hook` | `types.rs` | 钩子结构体定义 |
| `HookEvent` | `types.rs` | 钩子事件枚举 |
| `HookPayload` | `types.rs` | 钩子负载结构 |
| `HookResult` | `types.rs` | 钩子执行结果枚举 |
| `command_from_argv` | `registry.rs` | 命令行解析工具函数 |

### 调用方

| 调用方 | 路径 | 调用方式 |
|--------|------|----------|
| `Hooks::new` | `registry.rs:40-46` | `config.legacy_notify_argv.map(crate::notify_hook)` |

### 配置来源

| 配置项 | 来源 | 说明 |
|--------|------|------|
| `notify` | `core/src/config.rs` | 配置文件中的 `notify` 字段，对应 `legacy_notify_argv` |

## 依赖与外部交互

### 内部依赖

```
legacy_notify.rs
  ├─> types.rs: Hook, HookEvent, HookPayload, HookResult
  ├─> registry.rs: command_from_argv
  └─> (lib.rs 导出: legacy_notify_json, notify_hook)
```

### 外部依赖（ crates ）

| Crate | 用途 |
|-------|------|
| `serde` | JSON 序列化 |
| `serde_json` | JSON 字符串生成 |
| `std::process::Stdio` | 进程 stdio 控制 |
| `std::sync::Arc` | 共享所有权 |

### 与 core crate 的交互

```
core/src/codex.rs
  ├─> 从 config.notify 读取配置
  ├─> 传递给 HooksConfig.legacy_notify_argv
  └─> registry.rs: Hooks::new() 创建钩子
```

## 风险、边界与改进建议

### 已知限制

1. **仅支持 AfterAgent 事件**
   - 代码中明确检查 `HookEvent::AfterAgent`，其他事件返回错误
   - 历史原因：遗留通知系统仅设计用于 Agent 完成时通知

2. **Fire-and-forget 执行模式**
   - 不等待命令完成，无法获知通知是否成功
   - 不处理命令输出或退出码
   - 可能导致僵尸进程（zombie processes）积累

3. **JSON 作为命令行参数**
   - 将整个 JSON 负载作为单个命令行参数传递
   - 可能触及操作系统命令行长度限制
   - 特殊字符转义依赖 shell 处理

4. **无超时控制**
   - 与新的 Claude Hooks 引擎不同，遗留通知无超时机制
   - 长时间运行的通知命令可能累积

### 边界情况

| 场景 | 行为 |
|------|------|
| `argv` 为空或首元素为空字符串 | 提前返回 `HookResult::Success`，不执行任何操作 |
| JSON 序列化失败 | 静默忽略，不附加参数直接执行命令 |
| 命令启动失败 | 返回 `HookResult::FailedContinue`，不影响其他钩子 |
| `AfterToolUse` 事件 | 返回序列化错误（不支持） |

### 安全风险

1. **命令注入风险**
   - `command_from_argv` 直接使用用户配置的命令行
   - 未对 `cwd`、`client` 等字段进行 shell 转义检查
   - 建议：确保配置来源可信，或添加参数校验

2. **信息泄露**
   - JSON 负载包含完整的用户输入和助手回复
   - 通过命令行参数传递给外部程序
   - 可能被系统日志（如 bash_history）记录

### 改进建议

1. **短期改进**
   - 添加进程收割（reaping）机制，避免僵尸进程
   - 添加超时控制，防止长时间挂起
   - 对敏感字段进行清理或哈希处理

2. **中期改进**
   - 考虑将 JSON 通过 stdin 传递而非命令行参数
   - 添加执行结果日志，便于调试
   - 支持 `AfterToolUse` 事件的通知

3. **长期规划**
   - 逐步迁移到新的 Claude Hooks 引擎
   - 废弃 `legacy_notify`，统一使用 `hooks.json` 配置
   - 提供迁移工具或自动转换脚本

### 测试覆盖

当前测试覆盖：
- `test_user_notification`: 验证序列化格式
- `legacy_notify_json_matches_historical_wire_shape`: 验证历史兼容性

建议增加：
- 命令执行失败场景测试
- 特殊字符转义测试
- 大负载边界测试
