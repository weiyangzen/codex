# ThreadRealtimeClosedNotification.json 研究文档

## 场景与职责

`ThreadRealtimeClosedNotification` 是 Codex App-Server Protocol v2 中的实验性服务器推送通知，用于在实时对话（Realtime Conversation）传输层关闭时通知客户端。

**核心场景：**
1. **实时对话结束** - 当 WebSocket 连接关闭时通知客户端清理资源
2. **错误恢复** - 在发生错误导致连接中断时，携带关闭原因
3. **正常关闭确认** - 客户端调用 `thread/realtime/stop` 后的确认通知
4. **连接状态同步** - 确保客户端 UI 反映真实的连接状态

**典型使用流程：**
```
// 正常关闭流程
Client -> thread/realtime/stop -> Server
Server -> ThreadRealtimeClosedNotification { reason: "requested" } -> Client

// 错误关闭流程
Server (检测到错误) -> ThreadRealtimeClosedNotification { reason: "error" } -> Client
```

**实验性状态：**
- 标记为 `EXPERIMENTAL`，API 可能在未来版本中变更
- 需要启用 `realtime_conversation` 功能标志

## 功能点目的

### 1. 通知结构设计

```json
{
  "threadId": "thread-uuid-string",
  "reason": "error"
}
```

**设计意图：**
- **明确标识**：`threadId` 关联到具体的线程
- **关闭原因**：`reason` 字段解释关闭的上下文（可为 null）
- **资源清理信号**：客户端收到后应释放相关音频资源和 UI 状态

### 2. Reason 字段语义

| Reason 值 | 场景 |
|-----------|------|
| `"requested"` | 客户端主动调用 `thread/realtime/stop` |
| `"error"` | 发生错误（如 WebSocket 异常、协议错误） |
| `"transport_closed"` | 传输层意外关闭 |
| `null` | 原因未知或未指定 |

### 3. 与 ThreadRealtimeStartedNotification 的关系

```
ThreadRealtimeStartedNotification  <--->  ThreadRealtimeClosedNotification
        (连接建立)                              (连接关闭)
              │                                      │
              ▼                                      ▼
        客户端开始音频采集                      客户端停止音频采集
        启用实时 UI 状态                        清理实时 UI 状态
```

## 具体技术实现

### 1. Rust 源码定义

**文件路径：** `codex-rs/app-server-protocol/src/protocol/v2.rs:3803-3810`

```rust
/// EXPERIMENTAL - emitted when thread realtime transport closes.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadRealtimeClosedNotification {
    pub thread_id: String,
    pub reason: Option<String>,
}
```

**关键属性：**
- `#[serde(rename_all = "camelCase")]` - 字段使用 camelCase
- `pub reason: Option<String>` - 可选的关闭原因

### 2. 服务器通知注册

**文件路径：** `codex-rs/app-server-protocol/src/protocol/common.rs:929-930`

```rust
server_notification_definitions! {
    // ...
    #[experimental("thread/realtime/closed")]
    ThreadRealtimeClosed => "thread/realtime/closed" (v2::ThreadRealtimeClosedNotification),
    // ...
}
```

**Wire 格式：**
```json
{
  "method": "thread/realtime/closed",
  "params": {
    "threadId": "thread-uuid",
    "reason": "error"
  }
}
```

### 3. 服务器端发送逻辑

**文件路径：** `codex-rs/app-server/src/bespoke_event_handling.rs`

实时对话事件处理模块负责在以下场景发送通知：
1. WebSocket 连接关闭时
2. 发生错误时
3. 客户端请求停止时

```rust
// 伪代码示例
async fn handle_realtime_close(&mut self, thread_id: String, reason: Option<String>) {
    let notification = ThreadRealtimeClosedNotification {
        thread_id,
        reason,
    };
    self.outgoing
        .send_server_notification(ServerNotification::ThreadRealtimeClosed(notification))
        .await;
}
```

### 4. TypeScript 类型定义

**文件路径：** `codex-rs/app-server-protocol/schema/typescript/v2/ThreadRealtimeClosedNotification.ts`

```typescript
/**
 * EXPERIMENTAL - emitted when thread realtime transport closes.
 */
export type ThreadRealtimeClosedNotification = { 
  threadId: string, 
  reason: string | null, 
};
```

## 关键代码路径与文件引用

### 协议定义
| 文件 | 位置 | 说明 |
|------|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | 3803-3810 | Rust 结构体定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 929-930 | 通知注册 |

### 服务器实现
| 文件 | 位置 | 说明 |
|------|------|------|
| `codex-rs/app-server/src/bespoke_event_handling.rs` | - | 实时事件处理 |
| `codex-rs/app-server/src/codex_message_processor.rs` | 6270-6295 | realtime stop 处理 |

### 生成的 Schema/类型
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/schema/json/v2/ThreadRealtimeClosedNotification.json` | JSON Schema（本文件） |
| `codex-rs/app-server-protocol/schema/typescript/v2/ThreadRealtimeClosedNotification.ts` | TypeScript 类型 |
| `codex-rs/app-server-protocol/schema/json/ServerNotification.json` | 合并的通知 Schema |

### 测试
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/tests/suite/v2/realtime_conversation.rs` | 集成测试 |

## 依赖与外部交互

### 1. 上游依赖

```
ThreadRealtimeClosedNotification
  └── WebSocket 连接状态
       ├── thread/realtime/stop 请求
       ├── 网络异常
       ├── 协议错误
       └── 服务器内部错误
```

### 2. 下游消费者

```
ThreadRealtimeClosedNotification
  ├── VSCode Extension (Realtime UI)
  ├── TUI Client (音频采集停止)
  └── 其他支持实时对话的客户端
```

### 3. 实时对话状态机

```
                    thread/realtime/start
                           │
                           ▼
              ┌────────────────────────┐
              │   Starting             │
              │   (等待后端确认)        │
              └────────────────────────┘
                           │
              ThreadRealtimeStartedNotification
                           │
                           ▼
              ┌────────────────────────┐
              │   Active               │
              │   (音频双向传输)        │
              └────────────────────────┘
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
        ▼                  ▼                  ▼
   thread/realtime/    网络错误/        协议错误
        stop           连接中断
        │                  │                  │
        ▼                  ▼                  ▼
   reason:           reason:           reason:
   "requested"       "transport_        "error"
                     closed"
        │                  │                  │
        └──────────────────┼──────────────────┘
                           │
                           ▼
              ThreadRealtimeClosedNotification
                           │
                           ▼
                     资源清理
```

### 4. 相关协议方法

| 方法/通知 | 方向 | 说明 |
|-----------|------|------|
| `thread/realtime/start` | Client → Server | 启动实时对话 |
| `thread/realtime/started` | Server → Client | 实时对话启动通知 |
| `thread/realtime/stop` | Client → Server | 停止实时对话 |
| `thread/realtime/closed` | Server → Client | 实时对话关闭通知（本通知） |
| `thread/realtime/error` | Server → Client | 实时对话错误通知 |

## 风险、边界与改进建议

### 1. 已知风险

**风险 1：实验性 API 的不稳定性**
- **描述**：API 标记为 EXPERIMENTAL，可能在未来版本中变更或移除
- **影响**：客户端需要准备应对 breaking changes
- **缓解**：
  - 客户端应实现优雅降级
  - 关注版本更新日志

**风险 2：通知丢失**
- **描述**：连接关闭时，最后的通知可能无法送达
- **影响**：客户端可能永远处于"连接中"状态
- **缓解**：
  - 客户端实现超时机制
  - 定期心跳检测

**风险 3：Reason 字符串的非标准化**
- **描述**：`reason` 是自由字符串，非枚举类型
- **影响**：客户端难以程序化地响应特定原因
- **缓解**：当前依赖文档约定，建议未来改为枚举

### 2. 边界情况

| 场景 | 行为 |
|------|------|
| 未启动实时对话时收到 | 忽略（不应发生） |
| 重复收到关闭通知 | 幂等处理，第二次忽略 |
| Reason 为 null | 客户端显示通用关闭消息 |
| 不存在的 thread_id | 通知仍发送，客户端验证 |

### 3. 改进建议

**建议 1：标准化 Reason 枚举**
```rust
pub enum ThreadRealtimeCloseReason {
    Requested,       // 客户端请求
    TransportClosed, // 传输层关闭
    Error { code: String, message: String }, // 错误详情
    Timeout,         // 超时
}

pub struct ThreadRealtimeClosedNotification {
    pub thread_id: String,
    pub reason: ThreadRealtimeCloseReason,
}
```

**建议 2：添加时间戳**
```rust
pub struct ThreadRealtimeClosedNotification {
    pub thread_id: String,
    pub reason: Option<String>,
    pub closed_at: i64, // Unix 时间戳
}
```

**建议 3：会话统计**
```rust
pub struct ThreadRealtimeClosedNotification {
    pub thread_id: String,
    pub reason: Option<String>,
    pub stats: RealtimeSessionStats, // 会话时长、传输字节数等
}
```

**建议 4：重连建议**
```rust
pub struct ThreadRealtimeClosedNotification {
    pub thread_id: String,
    pub reason: Option<String>,
    pub reconnectable: bool, // 是否可重连
    pub reconnect_after_ms: Option<u64>, // 建议重连延迟
}
```

### 4. 测试缺口

| 缺口 | 优先级 | 说明 |
|------|--------|------|
| 网络分区场景 | 高 | 验证连接丢失时的通知行为 |
| 重复关闭通知 | 中 | 验证幂等性 |
| 高并发关闭 | 低 | 大量线程同时关闭的性能 |
