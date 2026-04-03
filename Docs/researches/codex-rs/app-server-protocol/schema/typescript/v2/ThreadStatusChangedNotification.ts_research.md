# ThreadStatusChangedNotification Research Document

## 场景与职责 (Usage Scenarios and Responsibilities)

`ThreadStatusChangedNotification` 是服务器向客户端发送的异步通知，用于实时广播线程状态的变化。这是线程状态机的外部 observable 接口，使客户端能够及时响应线程状态变更。

**核心使用场景：**
1. **实时状态同步**：当线程状态变化时，立即通知所有订阅客户端
2. **UI 状态更新**：更新线程列表中的状态指示器、进度条等 UI 元素
3. **操作可用性控制**：根据新状态启用/禁用特定用户操作
4. **状态历史记录**：客户端可以追踪线程的完整状态历史

**职责范围：**
- 广播线程状态变更事件
- 提供变更后的新状态
- 标识发生变更的线程
- 支持客户端选择性接收（通过 `optOutNotificationMethods`）

## 功能点目的 (Purpose of the Functionality)

**主要设计目标：**

1. **实时反馈**
   - 用户操作后（如发送消息）立即获得状态反馈
   - 无需轮询即可获知线程状态

2. **解耦架构**
   - 状态变更逻辑与通知逻辑分离
   - 支持多个客户端独立接收通知

3. **资源优化**
   - 客户端可以选择退出不需要的通知
   - 减少不必要的网络和处理开销

4. **一致性保证**
   - 所有订阅客户端看到相同的状态序列
   - 与 `ThreadStatus` 枚举保持同步

## 具体技术实现 (Technical Implementation Details)

### 数据结构定义

**Rust 源码**（`codex-rs/app-server-protocol/src/protocol/v2.rs` lines 4620-4626）：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadStatusChangedNotification {
    pub thread_id: String,
    pub status: ThreadStatus,
}
```

**TypeScript 生成类型**（`ThreadStatusChangedNotification.ts`）：

```typescript
import type { ThreadStatus } from "./ThreadStatus";

export type ThreadStatusChangedNotification = { 
    threadId: string, 
    status: ThreadStatus, 
};
```

### 字段详解

| 字段 | 类型 | 说明 |
|------|------|------|
| `threadId` | `string` | 发生状态变更的线程唯一标识符 |
| `status` | `ThreadStatus` | 线程的新状态 |

### ThreadStatus 类型

```typescript
type ThreadStatus = 
    { "type": "notLoaded" } | 
    { "type": "idle" } | 
    { "type": "systemError" } | 
    { "type": "active", activeFlags: Array<ThreadActiveFlag> };
```

### 通知注册

**RPC 协议注册**（`codex-rs/app-server-protocol/src/protocol/common.rs` line 878）：

```rust
server_notification_definitions! {
    // ...
    ThreadStatusChanged => "thread/status/changed" (v2::ThreadStatusChangedNotification),
    // ...
}
```

### ServerNotification 枚举

```rust
pub enum ServerNotification {
    // ...
    ThreadStatusChanged(v2::ThreadStatusChangedNotification),
    // ...
}
```

### 序列化示例

```json
// 线程变为空闲
{
    "jsonrpc": "2.0",
    "method": "thread/status/changed",
    "params": {
        "threadId": "thread-uuid",
        "status": { "type": "idle" }
    }
}

// 线程变为活跃（等待审批）
{
    "jsonrpc": "2.0",
    "method": "thread/status/changed",
    "params": {
        "threadId": "thread-uuid",
        "status": { 
            "type": "active", 
            "activeFlags": ["waitingOnApproval"] 
        }
    }
}

// 线程系统错误
{
    "jsonrpc": "2.0",
    "method": "thread/status/changed",
    "params": {
        "threadId": "thread-uuid",
        "status": { "type": "systemError" }
    }
}
```

## 关键代码路径与文件引用 (Key Code Paths and File References)

### 协议定义
- **`codex-rs/app-server-protocol/src/protocol/v2.rs`** (lines 4620-4626)
  - `ThreadStatusChangedNotification` 结构体定义

- **`codex-rs/app-server-protocol/src/protocol/common.rs`** (line 878)
  - 通知方法注册：`ThreadStatusChanged => "thread/status/changed"`

### TypeScript 生成文件
- **`codex-rs/app-server-protocol/schema/typescript/v2/ThreadStatusChangedNotification.ts`**
- **`codex-rs/app-server-protocol/schema/json/v2/ThreadStatusChangedNotification.json`**

### 服务器实现
- **`codex-rs/app-server/src/bespoke_event_handling.rs`**
  - 状态变更事件的处理和通知分发

- **`codex-rs/app-server/src/codex_message_processor.rs`**
  - 消息处理过程中的状态变更触发

### 测试文件
- **`codex-rs/app-server/tests/suite/v2/thread_status.rs`**
  - 完整的测试套件，验证状态变更通知
  - 测试状态序列：idle → active → idle
  - 测试通知退出机制（opt-out）

- **`codex-rs/app-server/tests/suite/v2/thread_unsubscribe.rs`**
  - 测试取消订阅后的状态变更通知
  - 验证 `NotLoaded` 状态的传播

### 客户端实现
- **`codex-rs/tui_app_server/src/app.rs`**
  - TUI 应用接收和处理状态变更通知

## 依赖与外部交互 (Dependencies and External Interactions)

### 内部依赖

| 依赖模块 | 用途 |
|---------|------|
| `ThreadStatus` | 状态值类型 |
| `ThreadActiveFlag` | 活跃状态的子状态 |
| `Thread` | 状态所属的线程 |

### 通知流程

```
用户发送消息 (turn/start)
        ↓
服务器处理请求
        ↓
状态变更: Idle → Active
        ↓
广播 ThreadStatusChangedNotification
        ↓
所有订阅客户端更新 UI
        ↓
操作完成
        ↓
状态变更: Active → Idle
        ↓
广播 ThreadStatusChangedNotification
```

### 选择性接收

客户端可以通过 `InitializeCapabilities` 选择退出此通知：

```rust
InitializeCapabilities {
    experimental_api: true,
    opt_out_notification_methods: Some(vec!["thread/status/changed".to_string()]),
}
```

### 状态转换序列示例

测试代码中的典型状态序列：

```rust
// 1. 初始状态
ThreadStatus::Idle

// 2. 开始处理
ThreadStatus::Active { active_flags: [...] }

// 3. 处理完成
ThreadStatus::Idle

// 或遇到错误
ThreadStatus::SystemError
```

## 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### 已知风险

1. **通知顺序**
   - 网络延迟可能导致通知乱序到达
   - 客户端需要处理过期的状态通知

2. **通知丢失**
   - 网络分区可能导致通知丢失
   - 客户端需要通过 `thread/read` 进行状态同步

3. **通知风暴**
   - 快速状态变化可能产生大量通知
   - 需要适当的节流（throttling）机制

### 边界情况

1. **重复状态**
   - 相同状态的重复通知是否合法？
   - 当前实现可能发送重复通知

2. **状态跳跃**
   - 如从 `Active` 直接到 `NotLoaded`（取消订阅时）
   - 客户端需要处理非连续的状态转换

3. **空活动标志**
   - `Active` 状态的活动标志列表为空时的语义
   - 测试代码显示这种情况被接受

### 改进建议

1. **序列号机制**
   - 添加单调递增的序列号，便于检测乱序和丢失
   - 客户端可以请求重传丢失的通知

2. **状态摘要**
   - 添加状态变更的原因或上下文
   - 例如：`{ status: { type: "active", ... }, reason: "turn_started" }`

3. **批量通知**
   - 支持多个线程的状态变更批量通知
   - 减少高频场景下的网络开销

4. **节流机制**
   - 对高频状态变更进行节流
   - 例如：合并短时间内多次 `Active` 状态更新

5. **状态差异**
   - 当前通知只包含新状态
   - 考虑添加旧状态或差异信息，便于客户端优化更新

6. **确认机制**
   - 对于关键状态变更，考虑添加客户端确认
   - 确保重要状态变更被正确接收

7. **历史查询**
   - 支持查询线程的状态历史
   - 便于调试和审计
