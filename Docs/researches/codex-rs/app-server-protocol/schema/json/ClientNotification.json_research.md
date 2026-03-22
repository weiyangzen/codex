# ClientNotification.json 研究文档

## 场景与职责

`ClientNotification` 是 Codex App Server Protocol 中定义的**客户端通知**类型。与 `ServerNotification`（服务器向客户端发送）相反，ClientNotification 用于客户端向服务器发送异步通知，目前主要用于标识客户端已完成初始化。

**关键场景：**
- 客户端完成初始化后通知服务器
- 未来可能扩展用于客户端状态变更通知
- JSON-RPC 协议中的通知消息（无响应期望）

## 功能点目的

### 1. 初始化完成通知
当前唯一用途：客户端完成 `Initialize` 请求处理后，发送 `initialized` 通知确认已就绪。

### 2. 协议对称性
与 `ServerNotification` 形成对称，支持双向异步通信：
- Server → Client：事件流、状态更新、审批请求
- Client → Server：初始化确认、未来可能的心跳、配置变更

### 3. 未来扩展点
虽然当前仅支持 `initialized`，但架构预留了扩展能力：
- 客户端配置变更通知
- 客户端状态（在线/离线）通知
- 用户活动事件

## 具体技术实现

### 数据结构定义

**JSON Schema 结构：**
```json
{
  "oneOf": [
    {
      "properties": {
        "method": {
          "enum": ["initialized"],
          "title": "InitializedNotificationMethod",
          "type": "string"
        }
      },
      "required": ["method"],
      "title": "InitializedNotification",
      "type": "object"
    }
  ],
  "title": "ClientNotification"
}
```

**Rust 源码定义**（`codex-rs/app-server-protocol/src/protocol/common.rs`）：
```rust
client_notification_definitions! {
    Initialized,
}
```

展开后的实际定义：
```rust
#[derive(Serialize, Deserialize, Debug, Clone, JsonSchema, TS, Display)]
#[serde(tag = "method", content = "params", rename_all = "camelCase")]
#[strum(serialize_all = "camelCase")]
pub enum ClientNotification {
    Initialized,
}
```

**TypeScript 定义**：
```typescript
export type ClientNotification = { "method": "initialized" };
```

### 关键流程

**1. 宏展开**（`common.rs` 第 696-722 行）：
```rust
macro_rules! client_notification_definitions {
    (
        $(
            $(#[$variant_meta:meta])*
            $variant:ident $( ( $payload:ty ) )?
        ),* $(,)?
    ) => {
        #[derive(Serialize, Deserialize, Debug, Clone, JsonSchema, TS, Display)]
        #[serde(tag = "method", content = "params", rename_all = "camelCase")]
        #[strum(serialize_all = "camelCase")]
        pub enum ClientNotification {
            $(
                $(#[$variant_meta])*
                $variant $( ( $payload ) )?,
            )*
        }
        // ... schema 导出函数
    };
}
```

**2. 服务器处理**（`message_processor.rs` 第 390-401 行）：
```rust
pub(crate) async fn process_notification(&self, notification: JSONRPCNotification) {
    // Currently, we do not expect to receive any notifications from the
    // client, so we just log them.
    tracing::info!("<- notification: {:?}", notification);
}

/// Handles typed notifications from in-process clients.
pub(crate) async fn process_client_notification(&self, notification: ClientNotification) {
    // Currently, we do not expect to receive any typed notifications from
    // in-process clients, so we just log them.
    tracing::info!("<- typed notification: {:?}", notification);
}
```

**3. 客户端发送**（`debug-client/src/client.rs`）：
```rust
// 初始化完成后发送通知
async fn send_initialized(&mut self) {
    let notification = ClientNotification::Initialized;
    self.send_notification(notification).await;
}
```

### 与 ServerNotification 对比

| 特性 | ClientNotification | ServerNotification |
|------|-------------------|-------------------|
| 方向 | Client → Server | Server → Client |
| 当前变体数 | 1 (`Initialized`) | 40+ |
| 用途 | 初始化确认 | 事件流、审批请求、状态更新 |
| 处理方式 | 仅日志记录 | 完整业务逻辑处理 |

## 关键代码路径与文件引用

### 核心定义文件
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 宏定义与枚举生成（第 696-722, 943-945 行） |
| `codex-rs/app-server-protocol/src/lib.rs` | 公开导出 |

### 服务器处理
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server/src/message_processor.rs` | 通知处理（第 390-401 行） |
| `codex-rs/mcp-server/src/message_processor.rs` | MCP Server 通知处理 |

### 客户端实现
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/debug-client/src/client.rs` | Debug 客户端通知发送 |
| `codex-rs/app-server-client/src/remote.rs` | 远程客户端通知支持 |
| `codex-rs/rmcp-client/src/rmcp_client.rs` | RMCP 客户端通知 |

### 生成文件
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/schema/typescript/ClientNotification.ts` | TypeScript 类型定义 |
| `codex-rs/app-server-protocol/schema/typescript/index.ts` | 类型导出 |

## 依赖与外部交互

### 上游依赖
1. **JSONRPCNotification** - 底层 JSON-RPC 通知封装
2. **ts-rs** - TypeScript 类型生成
3. **strum_macros::Display** - 字符串表示派生

### 下游消费者
- 当前无实际业务逻辑消费者，仅日志记录

### 相关类型
- `ServerNotification` - 服务器向客户端发送的通知（40+ 变体）
- `InitializedNotification` - 初始化完成通知（Server → Client 的对应通知）

## 风险、边界与改进建议

### 已知限制
1. **未实际使用**：当前服务器仅记录日志，不执行任何业务逻辑
2. **单一变体**：仅支持 `Initialized`，扩展性受限
3. **无响应确认**：JSON-RPC 通知无响应，客户端无法确认服务器已接收

### 潜在问题
1. **初始化顺序**：客户端可能在服务器准备好前发送 `initialized`，导致通知丢失
2. **重复发送**：无去重机制，客户端可能多次发送相同通知
3. **网络分区**：通知丢失后无重试机制

### 改进建议

#### 短期改进
1. **添加处理逻辑**：服务器实际处理 `Initialized` 通知，如：
   - 标记连接状态为 "已就绪"
   - 触发延迟发送的队列消息
   - 更新客户端会话状态

2. **添加验证**：
   ```rust
   pub(crate) async fn process_client_notification(&self, notification: ClientNotification) {
       match notification {
           ClientNotification::Initialized => {
               tracing::info!("client initialized");
               self.mark_connection_ready().await;
           }
       }
   }
   ```

#### 中期扩展
1. **心跳机制**：添加 `Heartbeat` 通知，用于检测连接活性
   ```rust
   client_notification_definitions! {
       Initialized,
       Heartbeat { timestamp: i64 },
   }
   ```

2. **配置变更通知**：
   ```rust
   ConfigChanged { key: String, value: Option<JsonValue> },
   ```

3. **用户活动通知**：
   ```rust
   UserActivity { kind: UserActivityKind },
   ```

#### 长期架构
1. **双向流对称**：ClientNotification 和 ServerNotification 应支持相同的高级特性：
   - 批量通知
   - 通知确认（ack）
   - 通知历史/回放

2. **类型安全**：考虑使用 `#[serde(tag = "method", content = "params")]` 的变体，而非空变体

### 测试覆盖
- 当前测试覆盖有限，建议添加：
  - 通知序列化/反序列化测试
  - 服务器接收处理测试
  - 并发通知处理测试

### 与 LSP 的对比
Language Server Protocol (LSP) 也使用 `initialized` 通知：
```json
// LSP: Client → Server
{ "jsonrpc": "2.0", "method": "initialized", "params": {} }
```

Codex 的实现与之类似，但 LSP 的 `initialized` 会触发服务器发送待处理的工作区诊断等操作，而 Codex 当前无对应逻辑。

### 结论
`ClientNotification` 是一个为 future-proofing 设计的协议扩展点，当前功能极简但架构正确。建议在需要客户端主动通知服务器的场景（如配置热更新、用户活动追踪）时逐步扩展。
