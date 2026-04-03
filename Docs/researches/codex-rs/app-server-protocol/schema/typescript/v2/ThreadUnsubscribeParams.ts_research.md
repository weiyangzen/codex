# ThreadUnsubscribeParams Research Document

## 场景与职责 (Usage Scenarios and Responsibilities)

`ThreadUnsubscribeParams` 是 `thread/unsubscribe` RPC 方法的请求参数类型，用于客户端主动取消对特定线程的订阅。这是资源管理和连接生命周期管理的重要机制，支持客户端优雅地释放不再需要的线程资源。

**核心使用场景：**
1. **资源释放**：客户端不再需要某个线程时，主动释放服务器资源
2. **连接清理**：连接关闭前清理所有订阅的线程
3. **内存管理**：减少服务器端维护的活跃线程数量
4. **会话切换**：用户切换会话时清理旧会话的线程订阅

**职责范围：**
- 标识要取消订阅的线程
- 触发线程卸载流程
- 支持优雅的资源释放
- 与 `ThreadClosedNotification` 配合完成清理通知

## 功能点目的 (Purpose of the Functionality)

**主要设计目标：**

1. **资源管理**
   - 允许客户端主动释放不再需要的线程资源
   - 减少服务器端的内存和计算开销

2. **连接生命周期管理**
   - 支持连接关闭前的优雅清理
   - 防止资源泄漏

3. **并发控制**
   - 支持中断正在进行的操作
   - 测试显示可以在轮次进行中取消订阅

4. **状态同步**
   - 确保客户端和服务器对线程加载状态达成一致
   - 支持重新订阅后的状态恢复

## 具体技术实现 (Technical Implementation Details)

### 数据结构定义

**Rust 源码**（`codex-rs/app-server-protocol/src/protocol/v2.rs` lines 2719-2724）：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadUnsubscribeParams {
    pub thread_id: String,
}
```

**TypeScript 生成类型**（`ThreadUnsubscribeParams.ts`）：

```typescript
export type ThreadUnsubscribeParams = { threadId: string };
```

### 字段详解

| 字段 | 类型 | 说明 |
|------|------|------|
| `threadId` | `string` | 要取消订阅的线程唯一标识符 |

### RPC 方法注册

**协议注册**（`codex-rs/app-server-protocol/src/protocol/common.rs` lines 233-236）：

```rust
client_request_definitions! {
    // ...
    ThreadUnsubscribe => "thread/unsubscribe" {
        params: v2::ThreadUnsubscribeParams,
        response: v2::ThreadUnsubscribeResponse,
    },
    // ...
}
```

### 对应的响应类型

**ThreadUnsubscribeResponse**（`codex-rs/app-server-protocol/src/protocol/v2.rs` lines 2726-2731）：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadUnsubscribeResponse {
    pub status: ThreadUnsubscribeStatus,
}
```

**ThreadUnsubscribeStatus** 枚举：

```rust
pub enum ThreadUnsubscribeStatus {
    Unsubscribed,  // 成功取消订阅
    NotLoaded,     // 线程未加载
}
```

### 配套的通知

**ThreadClosedNotification**（`codex-rs/app-server-protocol/src/protocol/v2.rs` lines 4642-4647）：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadClosedNotification {
    pub thread_id: String,
}
```

通知注册（`codex-rs/app-server-protocol/src/protocol/common.rs` line 881）：

```rust
ThreadClosed => "thread/closed" (v2::ThreadClosedNotification),
```

**ThreadStatusChangedNotification**

取消订阅后，线程状态会变为 `NotLoaded`，触发状态变更通知。

### 序列化示例

**请求：**
```json
{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "thread/unsubscribe",
    "params": {
        "threadId": "thread-uuid"
    }
}
```

**响应（成功）：**
```json
{
    "jsonrpc": "2.0",
    "id": 1,
    "result": {
        "status": "unsubscribed"
    }
}
```

**响应（线程未加载）：**
```json
{
    "jsonrpc": "2.0",
    "id": 1,
    "result": {
        "status": "notLoaded"
    }
}
```

**通知（线程关闭）：**
```json
{
    "jsonrpc": "2.0",
    "method": "thread/closed",
    "params": {
        "threadId": "thread-uuid"
    }
}
```

**通知（状态变更）：**
```json
{
    "jsonrpc": "2.0",
    "method": "thread/status/changed",
    "params": {
        "threadId": "thread-uuid",
        "status": { "type": "notLoaded" }
    }
}
```

## 关键代码路径与文件引用 (Key Code Paths and File References)

### 协议定义
- **`codex-rs/app-server-protocol/src/protocol/v2.rs`** (lines 2719-2724)
  - `ThreadUnsubscribeParams` 结构体定义

- **`codex-rs/app-server-protocol/src/protocol/common.rs`** (lines 233-236)
  - RPC 方法注册

### TypeScript 生成文件
- **`codex-rs/app-server-protocol/schema/typescript/v2/ThreadUnsubscribeParams.ts`**
- **`codex-rs/app-server-protocol/schema/json/v2/ThreadUnsubscribeParams.json`**

### 相关类型
- **`codex-rs/app-server-protocol/src/protocol/v2.rs`** (lines 2726-2731)
  - `ThreadUnsubscribeResponse` 定义

- **`codex-rs/app-server-protocol/src/protocol/v2.rs`** (lines 2733-273?)
  - `ThreadUnsubscribeStatus` 枚举定义

- **`codex-rs/app-server-protocol/src/protocol/v2.rs`** (lines 4642-4647)
  - `ThreadClosedNotification` 定义

### 测试文件
- **`codex-rs/app-server/tests/suite/v2/thread_unsubscribe.rs`**
  - 完整的取消订阅功能测试
  - 测试正常取消订阅流程
  - 测试中途中断轮次
  - 测试重复取消订阅
  - 测试取消订阅后恢复

### 服务器实现
- **`codex-rs/app-server/src/bespoke_event_handling.rs`**
  - 取消订阅的处理逻辑

- **`codex-rs/app-server/src/codex_message_processor.rs`**
  - 消息处理和线程管理

### 客户端实现
- **`codex-rs/tui_app_server/src/app.rs`**
  - TUI 应用的取消订阅处理

## 依赖与外部交互 (Dependencies and External Interactions)

### 内部依赖

| 依赖模块 | 用途 |
|---------|------|
| `ThreadUnsubscribeResponse` | 对应的响应类型 |
| `ThreadUnsubscribeStatus` | 响应状态枚举 |
| `ThreadClosedNotification` | 线程关闭通知 |
| `ThreadStatusChangedNotification` | 状态变更通知 |
| `ThreadLoadedListResponse` | 验证线程已从加载列表移除 |

### 外部系统交互

1. **线程管理器**
   - 从活跃线程列表中移除线程
   - 触发线程资源的清理

2. **轮次执行器**
   - 中断正在进行的轮次（如果适用）
   - 测试显示可以在命令执行中取消订阅

3. **通知系统**
   - 发送 `thread/closed` 通知
   - 发送 `thread/status/changed` 通知

### 操作流程

```
客户端调用 thread/unsubscribe
        ↓
服务器验证 thread_id
        ↓
从活跃线程列表中移除
        ↓
中断正在进行的操作（如有）
        ↓
清理线程资源
        ↓
返回 ThreadUnsubscribeResponse
        ↓
发送 thread/closed 通知
        ↓
发送 thread/status/changed 通知（NotLoaded）
```

### 状态转换

取消订阅后的状态变化：
- **线程状态**：从 `Idle`/`Active`/`SystemError` 变为 `NotLoaded`
- **加载列表**：线程从 `thread/loaded/list` 结果中移除
- **资源状态**：服务器释放相关资源

## 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### 已知风险

1. **操作中断**
   - 取消订阅会中断正在进行的轮次
   - 可能导致数据不一致或操作不完整

2. **重复取消订阅**
   - 对同一线程多次调用取消订阅
   - 第二次及以后返回 `NotLoaded` 状态

3. **竞态条件**
   - 取消订阅与新的操作启动可能产生竞态
   - 需要适当的同步机制

### 边界情况

1. **轮次进行中取消订阅**
   - 测试 `thread_unsubscribe_during_turn_interrupts_turn_and_emits_thread_closed` 验证了此场景
   - 命令执行会被中断
   - 模型 API 调用会被取消

2. **错误状态线程**
   - 测试 `thread_unsubscribe_clears_cached_status_before_resume` 验证了此场景
   - 取消订阅会清除缓存的错误状态
   - 重新订阅后状态为 `Idle`

3. **重复取消订阅**
   - 测试 `thread_unsubscribe_reports_not_loaded_after_thread_is_unloaded` 验证了此场景
   - 第一次返回 `Unsubscribed`
   - 第二次返回 `NotLoaded`

4. **未加载线程**
   - 尝试取消订阅未加载的线程
   - 返回 `NotLoaded` 状态

### 测试覆盖

测试文件 `thread_unsubscribe.rs` 包含以下测试：

1. **`thread_unsubscribe_unloads_thread_and_emits_thread_closed_notification`**
   - 验证正常取消订阅流程
   - 验证 `thread/closed` 通知
   - 验证线程从加载列表移除

2. **`thread_unsubscribe_during_turn_interrupts_turn_and_emits_thread_closed`**
   - 验证轮次进行中取消订阅
   - 验证命令执行被中断
   - 验证模型 API 调用被取消

3. **`thread_unsubscribe_clears_cached_status_before_resume`**
   - 验证错误状态被清除
   - 验证重新订阅后状态恢复为 `Idle`

4. **`thread_unsubscribe_reports_not_loaded_after_thread_is_unloaded`**
   - 验证重复取消订阅的行为
   - 验证 `NotLoaded` 状态返回

### 改进建议

1. **优雅关闭选项**
   - 添加 `force` 参数控制是否强制中断
   - 支持等待当前操作完成后再取消订阅

2. **原因说明**
   - 添加 `reason` 字段说明取消订阅的原因
   - 便于日志记录和调试

3. **批量操作**
   - 支持批量取消订阅多个线程
   - 减少多次 RPC 调用

4. **超时控制**
   - 添加超时参数控制资源清理的最长时间
   - 防止清理操作挂起

5. **回调钩子**
   - 支持注册取消订阅的回调函数
   - 便于客户端执行清理操作

6. **状态保留选项**
   - 添加选项控制是否保留状态缓存
   - 某些场景可能需要保留错误状态

7. **通知合并**
   - 考虑合并 `thread/closed` 和 `thread/status/changed` 通知
   - 减少通知数量

8. **审计日志**
   - 记录取消订阅操作的历史
   - 支持追踪和调试
