# TerminalInteractionNotification 研究文档

## 场景与职责

`TerminalInteractionNotification` 是 Codex App Server Protocol v2 API 中的服务器通知类型，用于向客户端报告终端交互事件。当 AI 代理执行的命令需要用户输入（stdin）时，服务器通过此通知将输入请求转发给客户端。

### 使用场景

1. **交互式命令执行**：AI 执行 `npm init`、`git commit` 等需要用户交互的命令时
2. **密码输入提示**：命令请求输入密码或敏感信息时
3. **确认提示**：命令执行过程中需要用户确认（Y/n）时
4. **实时输入转发**：将终端的输入请求实时转发给客户端 UI

## 功能点目的

### 核心功能

- **终端输入转发**：将执行中命令的 stdin 请求转发给客户端
- **会话上下文关联**：通过 `threadId`、`turnId`、`itemId` 精确定位交互来源
- **进程标识**：通过 `processId` 标识具体的终端进程
- **实时通知**：作为服务器通知（非请求-响应），支持实时推送

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `threadId` | `string` | 线程 ID，标识所属的会话 |
| `turnId` | `string` | 回合 ID，标识具体的交互回合 |
| `itemId` | `string` | 条目 ID，标识产生此通知的具体命令执行项 |
| `processId` | `string` | 进程 ID，标识请求输入的终端进程 |
| `stdin` | `string` | 请求的输入内容（通常是提示符或输入请求） |

## 具体技术实现

### Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs:4890-4896
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct TerminalInteractionNotification {
    pub thread_id: String,
    pub turn_id: String,
    pub item_id: String,
    pub process_id: String,
    pub stdin: String,
}
```

### 在 ServerNotification 中的注册

```rust
// codex-rs/app-server-protocol/src/protocol/common.rs:903
server_notification_definitions! {
    // ... other notifications
    TerminalInteraction => "item/commandExecution/terminalInteraction" (v2::TerminalInteractionNotification),
    // ...
}
```

### 关键处理流程

1. **事件触发**：核心协议层检测到终端交互事件
   ```rust
   // codex-rs/protocol/src/protocol.rs
   pub struct TerminalInteractionEvent {
       pub call_id: String,      // 映射到 item_id
       pub process_id: String,   // 终端进程 ID
       pub stdin: String,        // 输入请求内容
   }
   ```

2. **事件处理与转发**：`apply_bespoke_event_handling()`
   ```rust
   // codex-rs/app-server/src/bespoke_event_handling.rs:1624-1637
   EventMsg::TerminalInteraction(terminal_event) => {
       let item_id = terminal_event.call_id.clone();

       let notification = TerminalInteractionNotification {
           thread_id: conversation_id.to_string(),
           turn_id: event_turn_id.clone(),
           item_id,
           process_id: terminal_event.process_id,
           stdin: terminal_event.stdin,
       };
       outgoing
           .send_server_notification(ServerNotification::TerminalInteraction(notification))
           .await;
   }
   ```

3. **客户端处理**：
   - 客户端接收通知并识别交互来源
   - 在 UI 中显示输入提示（如密码输入框、确认对话框）
   - 用户输入后通过 `TurnSteer` 或其他机制将输入发送回服务器

### 生成的 TypeScript 类型

```typescript
// GENERATED CODE! DO NOT MODIFY BY HAND!
export type TerminalInteractionNotification = { 
    threadId: string, 
    turnId: string, 
    itemId: string, 
    processId: string, 
    stdin: string, 
};
```

### JSON Schema

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

## 关键代码路径与文件引用

### 协议定义

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs:4890-4896` | Rust 结构体定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs:903` | 服务器通知注册 |
| `codex-rs/app-server-protocol/schema/typescript/v2/TerminalInteractionNotification.ts` | 生成的 TypeScript 类型 |
| `codex-rs/app-server-protocol/schema/json/v2/TerminalInteractionNotification.json` | JSON Schema 定义 |

### 服务端实现

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/src/bespoke_event_handling.rs:1624-1637` | 事件处理与通知发送 |
| `codex-rs/app-server/src/bespoke_event_handling.rs:79` | 类型导入 |

### 核心协议定义

| 文件 | 说明 |
|------|------|
| `codex-rs/protocol/src/protocol.rs` | `TerminalInteractionEvent` 定义（推测） |

## 依赖与外部交互

### 上游依赖

1. **核心事件**：`EventMsg::TerminalInteraction` 触发通知
2. **会话上下文**：`conversation_id` 和 `event_turn_id` 提供上下文
3. **终端进程**：`process_id` 标识具体的终端会话

### 下游影响

1. **客户端 UI**：客户端需要显示输入提示界面
2. **用户输入**：用户响应后需要通过其他 API 将输入发送回服务器
3. **命令执行**：输入最终传递给执行中的命令

### 交互流程

```
用户命令执行
    ↓
命令请求输入 (stdin)
    ↓
核心层: TerminalInteractionEvent
    ↓
App Server: TerminalInteractionNotification
    ↓
客户端: 显示输入提示
    ↓
用户: 输入内容
    ↓
客户端: TurnSteer / 其他 API
    ↓
服务器: 将输入转发给命令
    ↓
命令: 继续执行
```

## 风险、边界与改进建议

### 潜在风险

1. **安全风险**：
   - `stdin` 字段可能包含敏感信息（如密码提示）
   - 通知通过 WebSocket 传输，需要确保连接安全
   - 客户端需要妥善处理敏感输入的显示（如密码遮罩）

2. **超时风险**：
   - 如果客户端未及时响应，命令可能超时
   - 需要明确的超时处理机制

3. **并发冲突**：
   - 多个命令同时请求输入时，需要正确路由响应

### 边界情况

1. **空 stdin**：某些情况下 `stdin` 可能为空字符串
2. **进程已终止**：通知发送时进程可能已结束
3. **客户端离线**：通知发送时客户端可能已断开连接
4. **重复通知**：同一输入请求可能产生多个通知

### 改进建议

1. **添加输入类型标记**：区分密码输入、普通输入等
   ```rust
   pub struct TerminalInteractionNotification {
       // ... existing fields
       pub input_type: InputType,  // Password, Text, Confirmation, etc.
   }
   ```

2. **添加超时信息**：告知客户端响应截止时间
   ```rust
   pub struct TerminalInteractionNotification {
       // ... existing fields
       pub timeout_ms: Option<u64>,  // 响应超时时间
   }
   ```

3. **支持多行输入**：当前仅支持单行字符串
   ```rust
   pub struct TerminalInteractionNotification {
       // ... existing fields
       pub stdin: String,
       pub multiline: bool,  // 是否支持多行输入
   }
   ```

4. **添加输入验证提示**：提供输入格式要求
   ```rust
   pub struct TerminalInteractionNotification {
       // ... existing fields
       pub validation_pattern: Option<String>,  // 正则验证模式
       pub validation_message: Option<String>,  // 验证失败提示
   }
   ```

5. **响应确认机制**：添加客户端确认接收通知的机制
   ```rust
   // 新增确认通知
   pub struct TerminalInteractionAckNotification {
       pub thread_id: String,
       pub turn_id: String,
       pub item_id: String,
       pub process_id: String,
       pub acknowledged_at: i64,
   }
   ```

6. **历史记录控制**：标记敏感输入不应被记录
   ```rust
   pub struct TerminalInteractionNotification {
       // ... existing fields
       pub sensitive: bool,  // 是否敏感（不应记录在历史中）
   }
   ```

7. **批量输入支持**：支持一次请求多个输入
   ```rust
   pub struct TerminalInteractionNotification {
       // ... existing fields
       pub batch_id: Option<String>,  // 批量输入标识
       pub batch_index: Option<usize>, // 在批量中的索引
       pub batch_total: Option<usize>, // 批量总数
   }
   ```

8. **输入建议**：提供自动完成建议
   ```rust
   pub struct TerminalInteractionNotification {
       // ... existing fields
       pub suggestions: Option<Vec<String>>,  // 输入建议列表
   }
   ```

### 相关类型对比

| 类型 | 用途 | 方向 |
|------|------|------|
| `TerminalInteractionNotification` | 命令请求用户输入 | 服务器 → 客户端 |
| `CommandExecutionOutputDeltaNotification` | 命令输出流 | 服务器 → 客户端 |
| `TurnSteerParams` | 用户向回合发送输入 | 客户端 → 服务器 |
| `CommandExecWriteParams` | 向执行中的命令写入数据 | 客户端 → 服务器 |

### 安全注意事项

1. **输入验证**：服务器应对客户端返回的输入进行验证，防止注入攻击
2. **敏感数据处理**：密码等敏感输入不应记录在日志中
3. **传输安全**：确保 WebSocket 连接使用 TLS 加密
4. **超时控制**：设置合理的超时时间，防止命令无限等待
