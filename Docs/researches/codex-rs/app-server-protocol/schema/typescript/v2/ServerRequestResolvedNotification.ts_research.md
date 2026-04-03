# ServerRequestResolvedNotification.ts 研究文档

## 场景与职责

`ServerRequestResolvedNotification.ts` 定义了服务器请求已解决通知的数据结构，用于通知客户端某个服务器请求（如需要用户批准的请求）已被处理。这是 Codex 交互式工作流的关键组件，确保客户端了解异步请求的状态变化。

## 功能点目的

该类型用于：
1. **请求状态同步**：通知客户端服务器请求已被解决
2. **UI 状态更新**：允许客户端关闭等待中的请求提示
3. **流程继续**：触发后续处理流程的继续执行
4. **超时处理**：支持请求超时或取消的通知

## 具体技术实现

### 数据结构定义

```typescript
import type { RequestId } from "../RequestId";

export type ServerRequestResolvedNotification = { 
  threadId: string,    // 请求所属的线程ID
  requestId: RequestId // 已解决的请求标识符
};
```

### 字段详解

| 字段 | 类型 | 说明 |
|------|------|------|
| threadId | string | 标识此请求所属的对话线程 |
| requestId | RequestId | 已解决的请求的唯一标识符 |

### RequestId 类型

RequestId 通常是一个字符串或结构化标识符，用于唯一标识服务器发出的请求。

### Rust 协议定义

在 `codex-rs/app-server-protocol/src/protocol/common.rs` 中：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ServerRequestResolvedNotification {
    pub thread_id: String,
    pub request_id: RequestId,
}
```

### 使用场景

#### 命令执行批准

```rust
// 1. 服务器发送批准请求
let request_id = send_approval_request(&thread_id, &command);

// 2. 客户端显示批准提示，等待用户响应

// 3. 用户做出决定后，客户端发送响应

// 4. 服务器处理响应后发送解决通知
let notification = ServerRequestResolvedNotification {
    thread_id: thread_id.to_string(),
    request_id,
};
send_server_notification(notification.into());
```

#### MCP 请求解决

```rust
// MCP 服务器发起请求
let mcp_request_id = mcp_server.send_request(...);

// 客户端处理并响应

// 服务器通知请求已解决
let notification = ServerRequestResolvedNotification {
    thread_id,
    request_id: RequestId::Mcp(mcp_request_id),
};
```

### 服务端发送逻辑

在 `codex-rs/app-server/src/codex_message_processor.rs` 中：

```rust
fn resolve_server_request(
    &mut self,
    thread_id: ThreadId,
    request_id: RequestId,
) {
    // 处理请求解决逻辑
    self.pending_requests.remove(&request_id);
    
    // 发送解决通知
    let notification = ServerRequestResolvedNotification {
        thread_id: thread_id.to_string(),
        request_id,
    };
    self.outgoing_messages.send(notification.into());
}
```

### 测试覆盖

在 `codex-rs/app-server/tests/suite/v2/` 中的测试：

```rust
// turn_start.rs
// turn_interrupt.rs
// request_user_input.rs
// request_permissions.rs
// mcp_server_elicitation.rs
```

这些测试文件都涉及服务器请求和解决通知的交互。

## 关键代码路径与文件引用

### TypeScript 类型定义
- 文件：`codex-rs/app-server-protocol/schema/typescript/v2/ServerRequestResolvedNotification.ts`

### Rust 协议定义
- V2 协议：`codex-rs/app-server-protocol/src/protocol/v2.rs`
- 通用协议：`codex-rs/app-server-protocol/src/protocol/common.rs`
- 导出模块：`codex-rs/app-server-protocol/src/export.rs`

### 服务端实现
- 消息处理：`codex-rs/app-server/src/codex_message_processor.rs`

### 客户端消费
- TUI 应用：`codex-rs/tui_app_server/src/app.rs`
- 待处理重播：`codex-rs/tui_app_server/src/app/pending_interactive_replay.rs`

### 父类型引用
- ServerNotification：`codex-rs/app-server-protocol/schema/typescript/ServerNotification.ts`

### 测试覆盖
- 回合启动测试：`codex-rs/app-server/tests/suite/v2/turn_start.rs`
- 回合中断测试：`codex-rs/app-server/tests/suite/v2/turn_interrupt.rs`
- 用户输入请求测试：`codex-rs/app-server/tests/suite/v2/request_user_input.rs`
- 权限请求测试：`codex-rs/app-server/tests/suite/v2/request_permissions.rs`
- MCP 服务器请求测试：`codex-rs/app-server/tests/suite/v2/mcp_server_elicitation.rs`

## 依赖与外部交互

### 上游依赖
- 服务器请求：由 ServerRequest 或 ElicitationRequest 触发
- 用户响应：客户端对请求的响应

### 下游消费
- UI 清理：关闭等待中的请求提示
- 状态更新：更新客户端的请求跟踪状态
- 流程继续：触发后续处理

### 请求生命周期

```
服务器发送请求
    ↓
客户端显示请求提示
    ↓
用户响应 / 超时 / 取消
    ↓
服务器处理响应
    ↓
发送 ServerRequestResolvedNotification
    ↓
客户端清理 UI 状态
```

## 风险、边界与改进建议

### 边界情况
1. **重复解决**：同一请求可能收到多次解决通知
2. **未知请求**：通知中的 requestId 可能已被客户端遗忘
3. **线程不匹配**：threadId 可能与客户端预期不符

### 潜在风险
1. **竞态条件**：通知和响应之间可能存在竞态
2. **网络延迟**：通知可能延迟到达或丢失
3. **状态不一致**：客户端和服务器状态可能不同步

### 改进建议
1. **幂等处理**：确保重复通知不会导致问题
2. **确认机制**：添加客户端确认接收的机制
3. **超时处理**：明确处理请求超时场景
4. **取消支持**：支持请求取消的明确通知
5. **原因说明**：添加解决原因（批准/拒绝/超时/取消）
6. **批处理**：支持批量解决多个请求的通知
