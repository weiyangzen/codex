# ThreadUnarchiveParams.json 研究文档

## 场景与职责

`ThreadUnarchiveParams` 是 Codex App-Server Protocol v2 中定义的客户端请求参数类型，用于将已归档的 Thread（会话线程）恢复到活跃状态。这是 Thread 生命周期管理的重要组成部分，允许用户重新访问和继续之前归档的对话。

典型使用场景：
- 用户从归档列表中恢复之前的对话
- 客户端应用启动时自动恢复上次会话
- 搜索归档 Thread 后选择恢复特定对话
- 从备份或导出文件中恢复 Thread

## 功能点目的

该参数类型的主要目的是：
1. **归档管理**：支持 Thread 的归档/解归档生命周期管理
2. **资源优化**：允许用户归档不常用的 Thread 以清理界面
3. **数据持久化**：确保重要对话可以被长期保存并在需要时恢复
4. **用户体验**：提供类似邮件客户端的归档/恢复功能

### ThreadUnarchive 流程

```
Client -> Server: thread/unarchive (ThreadUnarchiveParams)
Server -> Client: ThreadUnarchiveResponse
Server -> Client: ThreadUnarchivedNotification (广播给所有订阅者)
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

位于 `codex-rs/app-server-protocol/src/protocol/v2.rs`（行 2793-2795）：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadUnarchiveParams {
    pub thread_id: String,
}
```

### 对应的 Response 类型

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadUnarchiveResponse {
    pub thread: Thread,
}
```

### 客户端请求定义

在 `codex-rs/app-server-protocol/src/protocol/common.rs` 中注册为客户端请求：

```rust
client_request_definitions! {
    ThreadUnarchive => "thread/unarchive" {
        params: v2::ThreadUnarchiveParams,
        response: v2::ThreadUnarchiveResponse,
    },
    // ...
}
```

### 对应的服务器通知

```rust
server_notification_definitions! {
    ThreadUnarchived => "thread/unarchived" (v2::ThreadUnarchivedNotification),
    // ...
}
```

## 关键代码路径与文件引用

### 核心定义文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/schema/json/v2/ThreadUnarchiveParams.json` | JSON Schema 定义 |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 结构体定义（行 2793-2795） |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 客户端请求注册（行 262-265） |

### 服务端处理代码

位于 `codex-rs/app-server/src/codex_message_processor.rs`：
- 处理 `thread/unarchive` 请求
- 验证 Thread ID 和归档状态
- 更新 Thread 的归档标记
- 发送响应和通知

### 测试文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server/tests/suite/v2/thread_unarchive.rs` | Thread 解归档功能测试 |
| `codex-rs/app-server/tests/suite/v2/thread_archive.rs` | Thread 归档功能测试（相关） |

## 依赖与外部交互

### 上游依赖

1. **Thread 存储系统**：需要访问持久化的 Thread 数据
2. **归档索引**：可能需要更新归档状态的索引

### 下游消费者

1. **Thread 管理服务**：处理解归档的业务逻辑
2. **通知广播服务**：向订阅者广播 `ThreadUnarchivedNotification`

### 相关类型

| 类型 | 说明 |
|------|------|
| `ThreadArchiveParams` | 归档请求的参数类型（相反操作） |
| `ThreadUnarchiveResponse` | 解归档响应，包含完整的 Thread 对象 |
| `ThreadUnarchivedNotification` | 解归档完成后的服务器通知 |

## 风险、边界与改进建议

### 潜在风险

1. **并发冲突**：多个客户端同时尝试解归档同一个 Thread
2. **权限问题**：需要验证客户端是否有权限解归档特定 Thread
3. **存储损坏**：归档数据损坏时解归档可能失败

### 边界情况

1. **Thread 不存在**：请求的 Thread ID 不存在时应返回明确错误
2. **Thread 未归档**：对未归档的 Thread 调用解归档应返回错误或静默成功
3. **Thread 已删除**：物理删除的 Thread 无法解归档
4. **网络中断**：解归档过程中网络中断可能导致状态不一致

### 改进建议

1. **幂等性保证**：确保多次调用解归档同一 Thread 不会产生副作用
2. **批量操作**：支持批量解归档多个 Thread
3. **条件解归档**：支持基于条件的解归档（如仅在特定时间后）
4. **解归档原因**：添加可选的解归档原因字段用于审计
5. **自动解归档**：支持设置规则自动解归档符合条件的 Thread

### 版本兼容性

- 当前为 v2 API，使用 camelCase 命名
- 与 v1 API 不兼容，v1 可能使用不同的归档模型
- 建议客户端在解归档后调用 `thread/read` 获取最新状态
