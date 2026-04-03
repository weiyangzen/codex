# TerminalInteractionNotification 研究文档

## 1. 场景与职责

**TerminalInteractionNotification** 是 app-server-protocol v2 协议中用于通知客户端终端交互事件的服务器通知类型。该类型在以下场景中使用：

- **命令执行监控**：向客户端报告正在执行的命令的终端交互情况
- **实时输入显示**：显示发送到运行中命令的 stdin 输入
- **进程标识**：关联特定的进程 ID 以便客户端进行后续操作

## 2. 功能点目的

该类型的主要目的是：

1. **透明化终端交互**：让客户端能够看到发送到命令的输入
2. **支持交互式命令**：使客户端能够理解和展示交互式命令的行为
3. **进程跟踪**：通过 `processId` 关联特定的命令执行实例

### 与其他类型的关系

- **服务器通知**：作为 `ServerNotification` 枚举的一个变体
- **命令执行关联**：与 `CommandExecutionOutputDeltaNotification` 一起提供完整的命令执行视图
- **核心事件**：对应 `EventMsg::TerminalInteraction` 核心协议事件

## 3. 具体技术实现

### TypeScript 类型定义

```typescript
export type TerminalInteractionNotification = { 
    threadId: string, 
    turnId: string, 
    itemId: string, 
    processId: string, 
    stdin: string, 
};
```

### Rust 源码定义

```rust
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

位于：`codex-rs/app-server-protocol/src/protocol/v2.rs:4890-4897`

### 关键流程

1. **核心事件触发**：当命令执行过程中有终端交互时，核心协议触发 `EventMsg::TerminalInteraction`
2. **事件转换**：app-server 将核心事件转换为 `TerminalInteractionNotification`
3. **通知发送**：通过 `ServerNotification` 发送给客户端
4. **客户端展示**：客户端接收并展示终端交互信息

### 代码示例

```rust
// 在 bespoke_event_handling.rs 中处理终端交互事件
EventMsg::TerminalInteraction(terminal_event) => {
    let item_id = terminal_event.call_id.clone();

    let notification = TerminalInteractionNotification {
        thread_id: conversation_id.to_string(),
        turn_id: event_turn_id.clone(),
        item_id,
        process_id: terminal_event.process_id.clone(),
        stdin: terminal_event.stdin.clone(),
    };

    outgoing
        .send_server_notification(
            ServerNotification::TerminalInteraction(notification)
        )
        .await;
}
```

## 4. 关键代码路径与文件引用

### 协议定义
- **Rust 定义**：`codex-rs/app-server-protocol/src/protocol/v2.rs:4890-4897`
- **TypeScript 生成**：`codex-rs/app-server-protocol/schema/typescript/v2/TerminalInteractionNotification.ts`
- **JSON Schema**：`codex-rs/app-server-protocol/schema/json/v2/TerminalInteractionNotification.json`

### 服务端实现
- **事件处理**：`codex-rs/app-server/src/bespoke_event_handling.rs:1624-1638`

### 协议注册
- **ServerNotification 枚举**：`codex-rs/app-server-protocol/src/protocol/common.rs:903`
  ```rust
  TerminalInteraction => "item/commandExecution/terminalInteraction" (v2::TerminalInteractionNotification),
  ```

### 核心协议事件
- **EventMsg 定义**：`codex-rs/protocol/src/protocol.rs`
  ```rust
  pub enum EventMsg {
      // ...
      TerminalInteraction(TerminalInteractionEvent),
      // ...
  }
  ```

### 相关类型
- **ServerNotification**：`codex-rs/app-server-protocol/src/protocol/common.rs:874-941`
- **OutgoingMessageSender**：`codex-rs/app-server/src/outgoing_message.rs`

## 5. 依赖与外部交互

### 内部依赖

| 依赖项 | 用途 |
|--------|------|
| `serde` | 序列化/反序列化 |
| `schemars` | JSON Schema 生成 |
| `ts-rs` | TypeScript 类型生成 |
| `EventMsg::TerminalInteraction` | 核心协议事件 |

### 数据流

```
核心协议 (codex-protocol)
    │
    ├── 触发 EventMsg::TerminalInteraction
    │   └── TerminalInteractionEvent {
    │           call_id: String,
    │           process_id: String,
    │           stdin: String,
    │       }
    │
    ▼
app-server (bespoke_event_handling.rs)
    │
    ├── 接收 EventMsg::TerminalInteraction
    ├── 构造 TerminalInteractionNotification
    │   ├── thread_id (添加上下文)
    │   ├── turn_id (添加上下文)
    │   ├── item_id (来自 call_id)
    │   ├── process_id (透传)
    │   └── stdin (透传)
    │
    ▼
客户端 (VSCode/CLI)
    │
    └── 接收 ServerNotification::TerminalInteraction
        └── 展示终端交互信息
```

### 通知方法名

```rust
// 在 common.rs 中注册
TerminalInteraction => "item/commandExecution/terminalInteraction"
```

客户端通过此方法名识别通知类型。

## 6. 风险、边界与改进建议

### 潜在风险

1. **敏感信息泄露**：`stdin` 可能包含敏感信息（如密码）
2. **数据量过大**：大量终端交互可能导致通知风暴
3. **编码问题**：终端输入可能包含非 UTF-8 数据

### 边界情况

1. **空输入**：`stdin` 可能为空字符串
2. **特殊字符**：输入可能包含控制字符或转义序列
3. **长输入**：输入可能很长，需要截断处理

### 当前实现特点

1. **透传设计**：`stdin` 字段直接透传核心协议的数据
2. **上下文增强**：添加了 `thread_id` 和 `turn_id` 以便客户端关联
3. **进程跟踪**：通过 `process_id` 支持多进程场景

### 改进建议

1. **添加敏感信息标记**
   ```rust
   pub struct TerminalInteractionNotification {
       pub thread_id: String,
       pub turn_id: String,
       pub item_id: String,
       pub process_id: String,
       pub stdin: String,
       pub is_sensitive: Option<bool>, // 标记是否包含敏感信息
   }
   ```

2. **支持二进制数据**
   ```rust
   pub struct TerminalInteractionNotification {
       // ... 现有字段
       pub stdin_base64: Option<String>, // Base64 编码的二进制数据
       pub is_binary: bool,
   }
   ```

3. **添加时间戳**
   ```rust
   pub struct TerminalInteractionNotification {
       // ... 现有字段
       pub timestamp: i64, // Unix 时间戳（毫秒）
   }
   ```

4. **支持输入类型区分**
   ```rust
   pub enum StdinType {
       Text,     // 普通文本
       Password, // 密码（应隐藏）
       Control,  // 控制字符
   }
   
   pub struct TerminalInteractionNotification {
       // ... 现有字段
       pub stdin_type: StdinType,
   }
   ```

5. **添加序列号**：支持客户端检测丢失的通知
   ```rust
   pub struct TerminalInteractionNotification {
       // ... 现有字段
       pub sequence_number: u64,
   }
   ```

6. **支持部分传输**：对于大量数据，支持分片传输
   ```rust
   pub struct TerminalInteractionNotification {
       // ... 现有字段
       pub is_partial: bool,
       pub chunk_index: u32,
       pub total_chunks: u32,
   }
   ```

7. **添加字符编码信息**
   ```rust
   pub struct TerminalInteractionNotification {
       // ... 现有字段
       pub encoding: Option<String>, // 如 "utf-8", "latin-1"
   }
   ```

8. **支持输入确认**：允许客户端确认已接收和处理
   ```rust
   // 添加对应的客户端响应
   pub struct TerminalInteractionAck {
       pub item_id: String,
       pub sequence_number: u64,
   }
   ```
