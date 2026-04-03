# ThreadNameUpdatedNotification.json 研究文档

## 场景与职责

`ThreadNameUpdatedNotification` 是 Codex App-Server Protocol v2 中的服务器推送通知（Server Notification），用于在线程名称发生变更时主动通知所有相关客户端。

**核心场景：**
1. **用户重命名线程** - 当用户通过 `thread/name/set` 请求修改线程标题时，服务器广播此通知
2. **多客户端同步** - 确保所有连接到同一线程的客户端（如 VSCode 扩展 + TUI）看到一致的线程名称
3. **UI 实时更新** - 客户端无需轮询即可更新线程列表和标题显示

**典型使用流程：**
```
Client A -> thread/name/set (threadId, name) -> Server
Server -> ThreadNameUpdatedNotification { threadId, threadName } -> Client A
Server -> ThreadNameUpdatedNotification { threadId, threadName } -> Client B (if subscribed)
```

## 功能点目的

### 1. 通知结构设计

```json
{
  "threadId": "thread-uuid-string",
  "threadName": "New Thread Name"
}
```

**设计意图：**
- **最小有效信息**：仅包含线程 ID 和新名称，客户端自行定位更新
- **可选名称**：`threadName` 为可选字段，支持清除名称的场景
- **幂等性**：客户端可安全地多次接收和处理同一通知

### 2. 与 thread/name/set 的关系

```rust
// 服务器处理 thread/name/set 时
async fn thread_set_name(&mut self, request_id: ConnectionRequestId, params: ThreadSetNameParams) {
    // 1. 更新线程名称
    // 2. 发送成功响应
    self.outgoing.send_response(request_id, ThreadSetNameResponse {}).await;
    
    // 3. 广播通知给所有订阅者
    let notification = ThreadNameUpdatedNotification {
        thread_id: thread_id.to_string(),
        thread_name: Some(name),
    };
    self.outgoing.send_server_notification(
        ServerNotification::ThreadNameUpdated(notification)
    ).await;
}
```

### 3. 通知 vs 响应的区别

| 特性 | ThreadSetNameResponse | ThreadNameUpdatedNotification |
|------|----------------------|-------------------------------|
| 方向 | Server → Client (请求方) | Server → All Clients (广播) |
| 触发 | 响应特定请求 | 状态变更事件 |
| 内容 | 空结构 `{}` | 变更的元数据 |
| 接收者 | 仅请求客户端 | 所有订阅该线程的客户端 |

## 具体技术实现

### 1. Rust 源码定义

**文件路径：** `codex-rs/app-server-protocol/src/protocol/v2.rs:4661-4666`

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadNameUpdatedNotification {
    pub thread_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub thread_name: Option<String>,
}
```

**关键属性：**
- `#[serde(default, skip_serializing_if = "Option::is_none")]` - 名称为 None 时不序列化该字段
- `#[ts(optional)]` - TypeScript 中标记为可选属性

### 2. 服务器通知注册

**文件路径：** `codex-rs/app-server-protocol/src/protocol/common.rs:883`

```rust
server_notification_definitions! {
    // ...
    ThreadNameUpdated => "thread/name/updated" (v2::ThreadNameUpdatedNotification),
    // ...
}
```

**Wire 格式：**
```json
{
  "method": "thread/name/updated",
  "params": {
    "threadId": "thread-uuid",
    "threadName": "New Name"
  }
}
```

### 3. 服务器端发送逻辑

**文件路径：** `codex-rs/app-server/src/codex_message_processor.rs:2355-2365`

```rust
self.outgoing
    .send_response(request_id, ThreadSetNameResponse {})
    .await;

let notification = ThreadNameUpdatedNotification {
    thread_id: thread_id.to_string(),
    thread_name: Some(name),
};
self.outgoing
    .send_server_notification(ServerNotification::ThreadNameUpdated(notification))
    .await;
```

### 4. TypeScript 类型定义

**文件路径：** `codex-rs/app-server-protocol/schema/typescript/v2/ThreadNameUpdatedNotification.ts`

```typescript
export type ThreadNameUpdatedNotification = { 
  threadId: string, 
  threadName?: string, 
};
```

## 关键代码路径与文件引用

### 协议定义
| 文件 | 位置 | 说明 |
|------|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | 4661-4666 | Rust 结构体定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 883 | 通知注册 |

### 服务器实现
| 文件 | 位置 | 说明 |
|------|------|------|
| `codex-rs/app-server/src/codex_message_processor.rs` | 2355-2365 | 通知发送逻辑 |
| `codex-rs/app-server/src/codex_message_processor.rs` | 133 | 类型导入 |

### 生成的 Schema/类型
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/schema/json/v2/ThreadNameUpdatedNotification.json` | JSON Schema（本文件） |
| `codex-rs/app-server-protocol/schema/typescript/v2/ThreadNameUpdatedNotification.ts` | TypeScript 类型 |
| `codex-rs/app-server-protocol/schema/json/ServerNotification.json` | 合并的通知 Schema |
| `codex-rs/app-server-protocol/schema/typescript/ServerNotification.ts` | 合并的通知 TypeScript |

### 测试
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/tests/suite/v2/thread_read.rs` | 集成测试（验证通知接收） |
| `codex-rs/app-server/tests/suite/v2/thread_name_websocket.rs` | WebSocket 名称更新测试 |
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | TUI 客户端测试 |

## 依赖与外部交互

### 1. 上游依赖

```
ThreadNameUpdatedNotification
  └── ThreadSetNameParams (触发源)
       └── thread/name/set RPC 调用
```

### 2. 下游消费者

```
ThreadNameUpdatedNotification
  ├── VSCode Extension (via WebSocket)
  ├── TUI Client
  ├── CLI Client
  └── Other App-Server Clients
```

### 3. 数据流

```
┌─────────────────────────────────────────────────────────────────┐
│                           App Server                            │
│  ┌─────────────────┐    ┌──────────────────┐    ┌────────────┐ │
│  │ thread/name/set │───▶│ Update thread    │───▶│ Broadcast  │ │
│  │   handler       │    │ name in DB/file  │    │ notification│ │
│  └─────────────────┘    └──────────────────┘    └────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        ▼                     ▼                     ▼
┌───────────────┐    ┌───────────────┐    ┌───────────────┐
│   Client A    │    │   Client B    │    │   Client C    │
│  (发起者)      │    │  (订阅者)      │    │  (订阅者)      │
│               │    │               │    │               │
│ 收到 Response  │    │ 收到 Notification│   │ 收到 Notification│
│ + Notification │    │               │    │               │
└───────────────┘    └───────────────┘    └───────────────┘
```

### 4. 相关协议方法

| 方法 | 方向 | 说明 |
|------|------|------|
| `thread/name/set` | Client → Server | 设置/修改线程名称 |
| `thread/name/updated` | Server → Client | 名称变更通知（本通知） |
| `thread/read` | Client → Server | 读取线程信息（含名称） |

## 风险、边界与改进建议

### 1. 已知风险

**风险 1：通知丢失**
- **描述**：客户端在通知发送期间断开连接，可能错过更新
- **影响**：客户端显示的线程名称与服务器不一致
- **缓解**：
  - 客户端连接时主动调用 `thread/read` 同步状态
  - 实现客户端-服务器状态校验机制

**风险 2：重复通知**
- **描述**：网络延迟或重连可能导致客户端多次收到相同通知
- **影响**：UI 闪烁或不必要的重渲染
- **缓解**：客户端应实现幂等处理（相同 threadId + threadName 忽略）

**风险 3：跨客户端一致性**
- **描述**：不同客户端可能同时修改同一线程名称
- **影响**：后到达的更新覆盖先到达的，产生竞态条件
- **缓解**：当前无乐观锁，依赖最后写入者胜出

### 2. 边界情况

| 场景 | 行为 |
|------|------|
| 名称为空字符串 `""` | 合法，设置为空名称 |
| 名称为 null/undefined | 清除线程名称 |
| 不存在的 thread_id | `thread/name/set` 返回错误，无通知发送 |
| 无订阅者 | 通知发送但无客户端接收（正常行为） |
| 客户端未订阅该线程 | 不接收通知（基于线程作用域的订阅） |

### 3. 改进建议

**建议 1：添加时间戳**
```rust
pub struct ThreadNameUpdatedNotification {
    pub thread_id: String,
    pub thread_name: Option<String>,
    pub updated_at: i64, // 新增：服务器时间戳
}
```
- 帮助客户端判断通知顺序
- 支持冲突检测

**建议 2：添加更新者标识**
```rust
pub struct ThreadNameUpdatedNotification {
    pub thread_id: String,
    pub thread_name: Option<String>,
    pub updated_by: String, // 新增：客户端标识或会话 ID
}
```
- 客户端可识别自身发起的更新
- 支持显示"其他用户正在编辑"提示

**建议 3：批量通知**
```rust
pub struct ThreadNamesUpdatedNotification {
    pub updates: Vec<ThreadNameUpdate>, // 支持批量
}
```
- 减少高频更新时的网络开销

**建议 4：确认机制（QoS）**
- 对关键通知添加客户端确认
- 未确认时服务器重试发送

### 4. 测试缺口

| 缺口 | 优先级 | 说明 |
|------|--------|------|
| 多客户端并发更新 | 高 | 验证竞态条件下的行为 |
| 通知顺序保证 | 中 | 验证 FIFO 顺序 |
| 断线重连后状态同步 | 中 | 验证 missed notification 的恢复 |
| 性能测试（大量订阅者） | 低 | 验证广播性能 |
