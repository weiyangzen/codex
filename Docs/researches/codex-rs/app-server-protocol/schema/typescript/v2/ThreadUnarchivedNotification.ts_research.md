# ThreadUnarchivedNotification Research Document

## 场景与职责 (Usage Scenarios and Responsibilities)

`ThreadUnarchivedNotification` 是服务器向客户端发送的异步通知，用于广播线程已从归档状态恢复的事件。这是线程生命周期事件系统的一部分，确保所有相关客户端都能及时获知线程状态的变化。

**核心使用场景：**
1. **多客户端同步**：当线程被解档时，通知所有已连接的客户端
2. **UI 状态更新**：更新线程列表，将线程从归档区域移回活跃区域
3. **协作场景**：在多用户环境中广播解档事件
4. **审计日志**：记录线程生命周期事件用于追踪

**职责范围：**
- 广播线程解档事件
- 标识被解档的线程
- 与 `ThreadUnarchiveResponse` 配合完成事件通知
- 支持客户端线程列表的实时更新

## 功能点目的 (Purpose of the Functionality)

**主要设计目标：**

1. **事件广播**
   - 采用发布-订阅模式，解耦解档操作与通知逻辑
   - 确保所有订阅者都能收到通知

2. **状态同步**
   - 确保所有客户端的线程列表状态一致
   - 及时反映线程从归档到活跃的变化

3. **生命周期追踪**
   - 作为线程生命周期的重要事件
   - 与 `ThreadArchivedNotification` 形成完整闭环

4. **轻量设计**
   - 仅包含线程 ID，减少网络开销
   - 客户端需要详细信息时可调用 `thread/read`

## 具体技术实现 (Technical Implementation Details)

### 数据结构定义

**Rust 源码**（`codex-rs/app-server-protocol/src/protocol/v2.rs` lines 4635-4640）：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadUnarchivedNotification {
    pub thread_id: String,
}
```

**TypeScript 生成类型**（`ThreadUnarchivedNotification.ts`）：

```typescript
export type ThreadUnarchivedNotification = { threadId: string };
```

### 字段详解

| 字段 | 类型 | 说明 |
|------|------|------|
| `threadId` | `string` | 被解档的线程唯一标识符 |

### 通知注册

**RPC 协议注册**（`codex-rs/app-server-protocol/src/protocol/common.rs` line 880）：

```rust
server_notification_definitions! {
    // ...
    ThreadUnarchived => "thread/unarchived" (v2::ThreadUnarchivedNotification),
    // ...
}
```

### ServerNotification 枚举

```rust
pub enum ServerNotification {
    // ...
    ThreadUnarchived(v2::ThreadUnarchivedNotification),
    // ...
}
```

### 对应的请求和响应

**请求**：`ThreadUnarchiveParams`
```rust
pub struct ThreadUnarchiveParams {
    pub thread_id: String,
}
```

**响应**：`ThreadUnarchiveResponse`
```rust
pub struct ThreadUnarchiveResponse {
    pub thread: Thread,
}
```

### 相关的归档通知

**ThreadArchivedNotification**（`codex-rs/app-server-protocol/src/protocol/v2.rs` lines 4628-4633）：

```rust
pub struct ThreadArchivedNotification {
    pub thread_id: String,
}
```

通知注册（`codex-rs/app-server-protocol/src/protocol/common.rs` line 879）：

```rust
ThreadArchived => "thread/archived" (v2::ThreadArchivedNotification),
```

### 序列化示例

```json
{
    "jsonrpc": "2.0",
    "method": "thread/unarchived",
    "params": {
        "threadId": "550e8400-e29b-41d4-a716-446655440000"
    }
}
```

## 关键代码路径与文件引用 (Key Code Paths and File References)

### 协议定义
- **`codex-rs/app-server-protocol/src/protocol/v2.rs`** (lines 4635-4640)
  - `ThreadUnarchivedNotification` 结构体定义

- **`codex-rs/app-server-protocol/src/protocol/common.rs`** (line 880)
  - 通知方法注册：`ThreadUnarchived => "thread/unarchived"`

### TypeScript 生成文件
- **`codex-rs/app-server-protocol/schema/typescript/v2/ThreadUnarchivedNotification.ts`**
- **`codex-rs/app-server-protocol/schema/json/v2/ThreadUnarchivedNotification.json`**

### 相关类型
- **`codex-rs/app-server-protocol/src/protocol/v2.rs`** (lines 2793-2795)
  - `ThreadUnarchiveParams` 请求参数

- **`codex-rs/app-server-protocol/src/protocol/v2.rs`** (lines 2857-2862)
  - `ThreadUnarchiveResponse` 响应类型

- **`codex-rs/app-server-protocol/src/protocol/v2.rs`** (lines 4628-4633)
  - `ThreadArchivedNotification` 归档通知

### 测试文件
- **`codex-rs/app-server/tests/suite/v2/thread_unarchive.rs`** (lines 128-138)
  - 测试通知的接收和验证
  - 验证通知中的 thread_id 与请求一致

### 服务器实现
- **`codex-rs/app-server/src/bespoke_event_handling.rs`**
  - 事件处理和通知分发逻辑

### 文档
- **`codex-rs/app-server/README.md`**
  - API 文档中关于 `thread/unarchived` 的说明

## 依赖与外部交互 (Dependencies and External Interactions)

### 内部依赖

| 依赖模块 | 用途 |
|---------|------|
| `ThreadUnarchiveParams` | 触发此通知的请求 |
| `ThreadUnarchiveResponse` | 配套的响应 |
| `ThreadArchivedNotification` | 对应的归档通知 |

### 通知流程

```
客户端 A 调用 thread/unarchive
        ↓
服务器执行解档操作
        ↓
服务器发送 ThreadUnarchiveResponse 给客户端 A
        ↓
服务器广播 ThreadUnarchivedNotification 给所有订阅客户端
        ↓
客户端 A/B/C 接收通知并更新线程列表
```

### 与归档通知的对比

| 特性 | ThreadArchivedNotification | ThreadUnarchivedNotification |
|------|---------------------------|------------------------------|
| 方法名 | `thread/archived` | `thread/unarchived` |
| 触发时机 | 线程被归档后 | 线程被解档后 |
| 数据内容 | `{ threadId: string }` | `{ threadId: string }` |
| 生命周期 | 归档操作 | 解档操作 |

### 序列化格式

**JSON-RPC 2.0 通知格式：**

```json
{
    "jsonrpc": "2.0",
    "method": "thread/unarchived",
    "params": {
        "threadId": "thread-uuid"
    }
}
```

## 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### 已知风险

1. **通知顺序**
   - `ThreadUnarchiveResponse` 应在 `ThreadUnarchivedNotification` 之前到达调用者
   - 网络延迟可能导致顺序错乱

2. **轻量设计的局限**
   - 仅包含 thread_id，客户端需要额外调用获取详细信息
   - 可能增加客户端的复杂性

3. **重复通知**
   - 网络重连后可能收到重复通知
   - 客户端需要处理幂等性

### 边界情况

1. **并发解档**
   - 多个客户端同时解档同一线程
   - 可能产生多个通知

2. **解档后立即归档**
   - 快速连续的解档和归档操作
   - 通知顺序可能交错

3. **未订阅客户端**
   - 未订阅通知的客户端状态可能不同步
   - 需要通过 `thread/list` 定期同步

### 测试覆盖

测试文件 `thread_unarchive.rs` 验证了：
1. 通知在解档操作完成后发送
2. 通知中的 `thread_id` 与请求一致
3. 通知在 `ThreadUnarchiveResponse` 之后到达

### 改进建议

1. **添加时间戳**
   - 添加 `unarchived_at` 时间戳
   - 便于客户端排序和去重

2. **添加操作者信息**
   - 添加执行解档操作的客户端标识
   - 便于协作场景的追踪

3. **批量通知**
   - 支持批量解档的批量通知
   - 例如：`{ threadIds: string[] }`

4. **详细信息选项**
   - 考虑添加可选的线程摘要信息
   - 减少客户端的额外查询

5. **确认机制**
   - 考虑添加轻量级的接收确认
   - 确保重要通知被送达

6. **过滤机制**
   - 支持按线程属性过滤通知
   - 例如：只接收特定模型的线程通知

7. **历史查询**
   - 支持查询线程的归档/解档历史
   - 便于审计和追踪
