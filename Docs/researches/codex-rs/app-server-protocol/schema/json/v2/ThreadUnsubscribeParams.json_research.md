# ThreadUnsubscribeParams.json 研究文档

## 场景与职责

`ThreadUnsubscribeParams` 是 Codex App-Server Protocol v2 中定义的客户端请求参数类型，用于取消订阅特定 Thread（会话线程）的更新通知。这是订阅管理功能的重要组成部分，允许客户端在不再需要接收某个 Thread 的实时更新时取消订阅，优化网络资源和服务器负载。

典型使用场景：
- 用户关闭 Thread 标签页或导航离开
- 客户端应用切换到低功耗模式
- 清理不再关注的 Thread 订阅
- 应用退出前取消所有订阅

## 功能点目的

该参数类型的主要目的是：
1. **资源优化**：减少不必要的网络流量和服务器推送
2. **订阅管理**：提供完整的订阅生命周期管理（订阅/取消订阅）
3. **性能优化**：客户端可以专注于当前活跃的 Thread
4. **连接管理**：支持连接断开前的优雅清理

### Thread 订阅模型

```
订阅状态：
- notLoaded: Thread 未加载
- notSubscribed: Thread 已加载但未订阅通知
- unsubscribed: 已明确取消订阅

状态转换：
thread/start -> ThreadStartedNotification (自动订阅)
thread/resume -> ThreadResumeResponse (自动订阅)
thread/unsubscribe -> ThreadUnsubscribeResponse (取消订阅)
```

## 具体技术实现

### JSON Schema 结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "properties": {
    "threadId": { "type": "string" }
  },
  "required": ["threadId"]
}
```

### Rust 实现

位于 `codex-rs/app-server-protocol/src/protocol/v2.rs`（行 2722-2724）：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadUnsubscribeParams {
    pub thread_id: String,
}
```

### 对应的 Response 类型

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadUnsubscribeResponse {
    pub status: ThreadUnsubscribeStatus,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum ThreadUnsubscribeStatus {
    NotLoaded,
    NotSubscribed,
    Unsubscribed,
}
```

### 客户端请求定义

在 `codex-rs/app-server-protocol/src/protocol/common.rs` 中：

```rust
client_request_definitions! {
    ThreadUnsubscribe => "thread/unsubscribe" {
        params: v2::ThreadUnsubscribeParams,
        response: v2::ThreadUnsubscribeResponse,
    },
    // ...
}
```

## 关键代码路径与文件引用

### 核心定义文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/schema/json/v2/ThreadUnsubscribeParams.json` | JSON Schema 定义 |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 结构体定义（行 2722-2740） |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 客户端请求注册（行 233-236） |

### 服务端处理代码

位于 `codex-rs/app-server/src/codex_message_processor.rs`：
- 处理 `thread/unsubscribe` 请求
- 验证 Thread ID 和当前订阅状态
- 从订阅列表中移除客户端
- 返回适当的 `ThreadUnsubscribeStatus`

### 使用场景代码

位于 `codex-rs/exec/src/lib.rs`：
- Exec 模式下的客户端取消订阅处理

位于 `codex-rs/tui_app_server/src/app_server_session.rs`：
- TUI 应用服务器的订阅管理

### 测试文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server/tests/suite/v2/thread_unsubscribe.rs` | 取消订阅功能测试 |
| `codex-rs/app-server/tests/common/mcp_process.rs` | MCP 进程测试（包含订阅管理） |

## 依赖与外部交互

### 上游依赖

1. **订阅管理服务**：管理客户端与 Thread 的订阅关系
2. **WebSocket 连接管理**：跟踪哪些连接订阅了哪些 Thread

### 下游消费者

1. **通知广播服务**：根据订阅列表决定通知的发送目标
2. **资源管理服务**：释放不再需要的资源

### 相关类型

| 类型 | 说明 |
|------|------|
| `ThreadUnsubscribeResponse` | 取消订阅响应，包含状态 |
| `ThreadUnsubscribeStatus` | 取消订阅状态枚举 |
| `ThreadLoadedListResponse` | 获取已加载 Thread 列表 |

## 风险、边界与改进建议

### 潜在风险

1. **竞态条件**：取消订阅和通知发送之间的竞态条件
2. **内存泄漏**：订阅管理不当可能导致内存泄漏
3. **状态不一致**：客户端和服务器之间的订阅状态可能不一致

### 边界情况

1. **Thread 不存在**：请求的 Thread ID 不存在时返回 `NotLoaded`
2. **未订阅状态**：客户端未订阅该 Thread 时返回 `NotSubscribed`
3. **重复取消订阅**：多次取消订阅同一 Thread 应返回相同结果（幂等）
4. **连接断开**：连接断开时应自动取消所有订阅

### ThreadUnsubscribeStatus 详解

| 状态 | 含义 | 场景 |
|------|------|------|
| `NotLoaded` | Thread 未加载 | Thread ID 不存在或从未加载 |
| `NotSubscribed` | 未订阅 | Thread 已加载但客户端未订阅 |
| `Unsubscribed` | 已取消订阅 | 成功取消订阅 |

### 改进建议

1. **批量取消订阅**：支持一次取消多个 Thread 的订阅
2. **自动清理**：连接断开时自动取消所有订阅
3. **订阅查询**：支持查询当前订阅了哪些 Thread
4. **订阅超时**：支持设置订阅超时时间
5. **优先级订阅**：支持不同优先级的订阅级别

### 客户端最佳实践

```typescript
// 示例：客户端取消订阅处理
async function unsubscribeFromThread(threadId: string) {
    const response = await sendRequest('thread/unsubscribe', { threadId });
    
    switch (response.status) {
        case 'unsubscribed':
            console.log('成功取消订阅');
            removeFromSubscribedList(threadId);
            break;
        case 'notSubscribed':
            console.log('原本就没有订阅');
            break;
        case 'notLoaded':
            console.log('Thread 未加载');
            break;
    }
}

// 应用退出时清理
window.addEventListener('beforeunload', () => {
    subscribedThreads.forEach(threadId => {
        unsubscribeFromThread(threadId);
    });
});
```

### 版本兼容性

- 当前为 v2 API，使用 camelCase 命名
- 与 v1 API 不兼容
- 建议在应用生命周期管理中集成订阅管理
