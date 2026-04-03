# TerminalInteractionNotification.json 研究文档

## 场景与职责

`TerminalInteractionNotification` 是 App-Server Protocol v2 中用于通知客户端终端交互事件的服务器通知。当命令执行需要用户输入（如密码提示）时，服务器发送此通知，客户端可以通过响应向终端发送输入。

该通知支持交互式命令执行，允许用户与需要输入的命令进行交互。

## 功能点目的

1. **交互式命令支持**: 支持需要用户输入的命令执行
2. **终端输入转发**: 将用户输入转发到正在执行的命令
3. **进程标识**: 通过 `processId` 标识特定的终端进程

## 具体技术实现

### 数据结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "properties": {
    "itemId": { "type": "string" },
    "processId": { "type": "string" },
    "stdin": { "type": "string" },
    "threadId": { "type": "string" },
    "turnId": { "type": "string" }
  },
  "required": ["itemId", "processId", "stdin", "threadId", "turnId"],
  "title": "TerminalInteractionNotification",
  "type": "object"
}
```

### 字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `itemId` | string | 是 | 命令执行项的唯一标识符 |
| `processId` | string | 是 | 终端进程标识符 |
| `stdin` | string | 是 | 需要发送到终端的输入内容 |
| `threadId` | string | 是 | 所属线程 ID |
| `turnId` | string | 是 | 所属回合 ID |

### 通知方法名

```
item/commandExecution/terminalInteraction
```

### 关联定义

```rust
// codex-rs/app-server-protocol/src/protocol/common.rs
server_notification_definitions! {
    // ...
    TerminalInteraction => "item/commandExecution/terminalInteraction" (v2::TerminalInteractionNotification),
    // ...
}
```

## 关键代码路径与文件引用

### Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct TerminalInteractionNotification {
    pub item_id: String,
    pub process_id: String,
    pub stdin: String,
    pub thread_id: String,
    pub turn_id: String,
}
```

### 发送代码

```rust
// codex-rs/app-server/src/bespoke_event_handling.rs
// 当命令执行需要用户输入时

outgoing.send_notification(
    ServerNotification::TerminalInteraction(TerminalInteractionNotification {
        item_id: command_item_id.to_string(),
        process_id: process_id.to_string(),
        stdin: input_data,
        thread_id: thread_id.to_string(),
        turn_id: turn_id.to_string(),
    })
).await;
```

### 相关文件

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 结构定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | ServerNotification 枚举定义 |
| `codex-rs/app-server/src/bespoke_event_handling.rs` | 事件处理和通知发送 |

## 依赖与外部交互

### 上游依赖

1. **PTY 进程**: 需要 PTY（伪终端）支持交互式命令
2. **命令执行**: 由 `CommandExecutionThreadItem` 表示的命令执行

### 下游交互

1. **用户输入 UI**: 客户端显示输入提示并收集用户输入
2. **输入转发**: 用户输入通过其他机制（如 `CommandExecWrite`）转发回服务器

### 协议版本

- **版本**: v2
- **稳定性**: 稳定 API (非实验性)

## 风险、边界与改进建议

### 风险点

1. **安全风险**: 敏感输入（如密码）需要安全处理
2. **超时处理**: 用户可能不及时响应输入请求
3. **编码问题**: 输入内容的编码需要正确处理

### 边界情况

1. **空输入**: `stdin` 为空字符串时的处理
2. **进程终止**: 进程在交互过程中终止
3. **多行输入**: 需要多行输入时的处理

### 改进建议

1. **添加输入类型**: 建议添加 `input_type: InputType` 字段（如 `password`、`text`、`confirm`）
2. **添加提示信息**: 建议添加 `prompt: String` 字段显示给用户的提示
3. **添加超时**: 建议添加 `timeout_ms: Option<u64>` 字段
4. **添加掩码**: 建议添加 `mask_input: bool` 字段控制是否显示输入内容

### 示例改进结构

```json
{
  "itemId": "cmd-123",
  "processId": "pty-456",
  "stdin": "",
  "threadId": "thread-789",
  "turnId": "turn-abc",
  "prompt": "Enter password:",
  "inputType": "password",
  "maskInput": true,
  "timeoutMs": 30000
}
```

### 测试覆盖

建议测试场景：
- 交互式命令执行
- 密码输入处理
- 超时处理
