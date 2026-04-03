# TurnStartResponse.ts Research

## 场景与职责

`TurnStartResponse` 是 App-Server Protocol v2 中 `turn/start` 方法的响应类型。当客户端发起回合启动请求后，服务器通过此响应返回新创建回合的基本信息，确认回合已成功创建并开始执行。

主要使用场景包括：
- **回合确认**：确认服务器已接收并处理回合启动请求
- **ID 获取**：客户端获取新回合的 ID，用于后续操作（如中断、查询状态）
- **状态同步**：获取回合的初始状态信息
- **流程控制**：客户端根据响应决定是否继续等待后续通知
- **测试验证**：测试框架验证回合启动的响应格式和内容

## 功能点目的

该类型的核心目的是：

1. **创建确认**：向客户端确认新回合已成功创建
2. **标识传递**：返回回合的唯一标识符，用于后续引用
3. **初始状态**：提供回合创建时的初始状态快照
4. **协议完整**：保持 JSON-RPC 请求-响应模式的完整性

与其他类型的关系：
- 与 `TurnStartParams` 配对，形成完整的请求-响应循环
- 返回的 `Turn` 对象与 `TurnCompletedNotification` 中的 `Turn` 类型相同
- 与 `TurnStartedNotification` 关联，响应后通常会收到开始通知

## 具体技术实现

### TypeScript 类型定义

```typescript
export type TurnStartResponse = { 
  turn: Turn, 
};
```

### Rust 源码定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct TurnStartResponse {
    pub turn: Turn,
}
```

### Turn 结构

```typescript
export type Turn = { 
  id: string, 
  /**
   * Only populated on a `thread/resume` or `thread/fork` response.
   * For all other responses and notifications returning a Turn,
   * the items field will be an empty list.
   */
  items: Array<ThreadItem>, 
  status: TurnStatus, 
  /**
   * Only populated when the Turn's status is failed.
   */
  error: TurnError | null, 
};
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `turn` | Turn | 新创建的回合对象，包含 ID、状态、项目列表和错误信息 |

### Turn 字段详情

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | string | 回合的唯一标识符，用于后续引用 |
| `items` | ThreadItem[] | 回合包含的项目列表，在 `turn/start` 响应中为空 |
| `status` | TurnStatus | 回合当前状态（通常为 `InProgress`） |
| `error` | TurnError \| null | 错误信息，仅在状态为 `Failed` 时填充 |

### TurnStatus 枚举

```typescript
export type TurnStatus = "completed" | "interrupted" | "failed" | "inProgress";
```

## 关键代码路径与文件引用

### 协议定义

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs:3934-3939` | Rust 结构体定义 |
| `codex-rs/app-server-protocol/schema/typescript/v2/TurnStartResponse.ts` | TypeScript 类型定义 |
| `codex-rs/app-server-protocol/schema/json/v2/TurnStartResponse.json` | JSON Schema 定义 |

### 方法注册

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/common.rs:351-355` | ClientRequest 枚举中的响应类型定义 |

### 服务器端处理

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server/src/bespoke_event_handling.rs` | 回合启动处理，构造响应 |
| `codex-rs/app-server/src/codex_message_processor.rs` | 消息处理器 |

### 客户端实现

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui_app_server/src/app_server_session.rs` | TUI App Server 响应处理 |
| `codex-rs/tui/src/app.rs` | TUI 客户端响应处理 |
| `codex-rs/app-server-client/src/lib.rs` | 客户端库 |

### 测试覆盖

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server/tests/suite/v2/turn_start.rs` | 回合启动测试，验证响应 |
| `codex-rs/app-server/tests/suite/v2/turn_interrupt.rs:89` | 从响应中提取 turn ID |
| `codex-rs/app-server/tests/suite/v2/plan_item.rs` | 计划项测试 |

## 依赖与外部交互

### 内部依赖

```
TurnStartResponse
├── turn: Turn
│   ├── id: String
│   ├── items: Vec<ThreadItem> (在 start 响应中为空)
│   ├── status: TurnStatus
│   │   ├── Completed
│   │   ├── Interrupted
│   │   ├── Failed
│   │   └── InProgress (start 响应中的典型值)
│   └── error: Option<TurnError>
├── serde (Serialize, Deserialize)
├── schemars (JsonSchema)
└── ts_rs (TS)
```

### 协议集成

- **JSON-RPC 方法**：`turn/start`
- **请求类型**：`TurnStartParams`
- **响应类型**：`TurnStartResponse`
- **典型响应状态**：`turn.status` 通常为 `"inProgress"`

### 请求-响应流程

```
┌─────────┐                              ┌─────────┐
│ Client  │                              │ Server  │
└────┬────┘                              └────┬────┘
     │                                        │
     │──── turn/start ──────────────────────>│
     │    (TurnStartParams)                   │
     │         │                              │
     │         │  1. 验证参数                  │
     │         │  2. 创建 Turn                 │
     │         │  3. 启动处理                  │
     │         │                              │
     │<─── TurnStartResponse ─────────────────│
     │    { turn: { id, items: [],            │
     │            status: "inProgress",       │
     │            error: null } }             │
     │                                        │
     │<─── turn/started ──────────────────────│
     │    (TurnStartedNotification)           │
     │                                        │
     │    [异步执行中...]                       │
     │                                        │
     │<─── turn/completed ────────────────────│
     │    (TurnCompletedNotification)         │
     │                                        │
```

### 响应与通知的区别

| 特性 | TurnStartResponse | TurnStartedNotification |
|------|-------------------|------------------------|
| 类型 | JSON-RPC 响应 | JSON-RPC 通知 |
| 触发 | 客户端请求 | 服务器主动发送 |
| 目的 | 确认请求处理 | 通知状态变更 |
| 必须性 | 必须 | 可能（取决于实现） |
| 内容 | 初始 Turn 状态 | 可能包含额外信息 |

## 风险、边界与改进建议

### 潜在风险

1. **items 为空**：响应中的 `items` 字段始终为空，可能让期望看到初始项目的客户端困惑
2. **状态竞态**：响应返回后，回合状态可能立即变更（如快速失败）
3. **ID 复用**：极端情况下，如果 ID 生成有问题，可能导致 ID 冲突
4. **响应延迟**：如果服务器负载高，响应可能延迟，客户端需要合理设置超时

### 边界情况

| 场景 | 行为 |
|------|------|
| 请求参数无效 | 返回 JSON-RPC 错误，不创建回合 |
| 线程不存在 | 返回错误，指示无效的 threadId |
| 线程已有活跃回合 | 返回错误，需等待或中断当前回合 |
| 服务器过载 | 可能延迟响应或返回错误 |
| 创建后立即失败 | 响应中 status 可能为 Failed，error 填充 |

### 改进建议

1. **添加创建时间戳**：在响应中添加 `createdAt` 时间戳，便于调试和监控
2. **预估完成时间**：如可能，添加预估完成时间或复杂度指标
3. **队列位置**：如果服务器繁忙，返回在队列中的位置
4. **items 说明**：在文档中明确说明 items 为空的原因，避免困惑
5. **响应缓存**：考虑客户端是否需要缓存响应中的 turn 信息

### 与 TurnStartedNotification 的整合

当前设计同时存在响应和通知，可能存在冗余。考虑以下优化方向：

1. **合并信息**：将 `TurnStartedNotification` 的关键信息合并到响应中
2. **明确分工**：
   - 响应：确认创建，提供 ID
   - 通知：传递动态信息（如实际开始执行时间）
3. **可选通知**：如果客户端已收到响应，通知可简化为仅包含 ID

### 监控指标建议

- 回合创建成功率
- 从请求到响应的延迟
- 创建后立即失败的比率
- 平均响应大小
- 并发回合创建数量
