# ServerRequestResolvedNotification 研究文档

## 场景与职责

`ServerRequestResolvedNotification` 是 Codex app-server-protocol v2 协议中的服务器通知类型，用于通知客户端服务器请求已被解决或完成。该类型在服务器端处理完成某个请求后发送，让客户端可以清理相关状态或执行后续操作。

在 Codex 的请求-响应体系中，`ServerRequestResolvedNotification` 承担以下职责：
1. **请求完成通知**：告知客户端服务器请求已处理完成
2. **状态清理**：允许客户端清理等待响应的状态
3. **超时处理**：帮助客户端处理超时或取消的请求
4. **资源释放**：通知客户端可以释放相关资源

## 功能点目的

### 核心功能
- **请求标识**：通过 `requestId` 标识已完成的请求
- **线程关联**：通过 `threadId` 关联到具体线程
- **完成确认**：确认服务器端已处理完成

### 设计意图
- **异步通知**：支持异步通知客户端请求完成
- **资源管理**：帮助客户端管理等待中的请求状态
- **错误恢复**：在异常情况下通知客户端清理状态

## 具体技术实现

### 数据结构定义

**TypeScript 定义**（`ServerRequestResolvedNotification.ts`）：
```typescript
export type ServerRequestResolvedNotification = { 
  threadId: string, 
  requestId: RequestId, 
};
```

**Rust 定义**（`v2.rs` 行 4942-4945）：
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ServerRequestResolvedNotification {
    pub thread_id: String,
    pub request_id: RequestId,
}
```

### 关键字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `threadId` | `string` | 请求所属的线程 ID |
| `requestId` | `RequestId` | 已完成的请求 ID（可以是数字或字符串） |

### RequestId 类型

**TypeScript 定义**：
```typescript
export type RequestId = number | string;
```

**Rust 定义**：
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Hash, JsonSchema, TS)]
#[serde(untagged)]
pub enum RequestId {
    Integer(u64),
    String(String),
}
```

### 通知场景

1. **正常完成**：服务器请求正常处理完成后发送
2. **请求取消**：客户端取消请求后，服务器确认取消
3. **超时处理**：请求超时后，服务器通知客户端
4. **错误恢复**：发生错误后，通知客户端清理状态

### 处理流程

```
服务器处理请求
  ↓
请求完成/取消/超时
  ↓
构造 ServerRequestResolvedNotification
  ↓
ServerNotification::ServerRequestResolved
  ↓
通过 WebSocket 推送给客户端
  ↓
客户端清理等待状态
```

## 关键代码路径与文件引用

### 定义位置
- **Rust 定义**：`codex-rs/app-server-protocol/src/protocol/v2.rs` 行 4942-4945
- **TypeScript 生成**：`codex-rs/app-server-protocol/schema/typescript/v2/ServerRequestResolvedNotification.ts`
- **JSON Schema**：`codex-rs/app-server-protocol/schema/json/ServerNotification.json`

### 使用位置
- **ServerNotification 定义**：`common.rs` 行 905 - 注册为服务器通知
- **消息处理器**：`codex_message_processor.rs` 行 7371 - 发送通知
- **TUI 应用**：`tui_app_server/src/app.rs` 行 8017 - 处理通知

### 相关类型
- `RequestId`：请求标识符类型
- `ServerNotification`：服务器通知联合类型
- `ServerRequest`：服务器请求类型

### 发送示例

在 `codex_message_processor.rs` 行 7371：
```rust
self.send_notification(
    ServerNotification::ServerRequestResolved(ServerRequestResolvedNotification {
        thread_id: thread_id.to_string(),
        request_id: request_id.clone(),
    })
).await?;
```

### 处理示例

在 `tui_app_server/src/app.rs` 行 8017：
```rust
codex_app_server_protocol::ServerRequestResolvedNotification {
    thread_id,
    request_id,
} => {
    // 清理等待中的请求状态
    self.pending_requests.remove(&request_id);
}
```

## 依赖与外部交互

### 依赖项
- `RequestId`：请求标识符类型
- `serde`：序列化/反序列化支持
- `schemars`：JSON Schema 生成
- `ts-rs`：TypeScript 类型生成

### 上游依赖
- `ServerRequest`：服务器请求类型

### 下游使用
- `ServerNotification`：作为服务器通知的变体
- 客户端状态管理：清理等待中的请求

### 协议集成
- 通知方法名：`serverRequest/resolved`（`common.rs` 行 905）
- 方向：Server → Client
- 传输方式：WebSocket JSON-RPC 通知

## 风险、边界与改进建议

### 潜在风险
1. **通知丢失**：网络问题可能导致通知丢失
2. **重复通知**：服务器可能重复发送通知
3. **顺序问题**：通知可能与响应乱序到达
4. **状态不一致**：客户端和服务器状态可能不一致

### 边界情况
1. **未知请求**：`requestId` 指向客户端未知的请求
2. **已清理请求**：客户端已清理的请求收到通知
3. **并发通知**：多个请求同时完成
4. **连接断开**：通知发送时连接断开

### 改进建议
1. **可靠性增强**：
   - 添加序列号检测重复和乱序
   - 实现客户端去重机制
   - 添加确认机制

2. **信息扩展**：
   ```rust
   pub struct ServerRequestResolvedNotification {
       // 现有字段...
       /// 完成时间戳
       pub resolved_at: i64,
       /// 完成原因
       pub reason: ServerRequestResolvedReason,
       /// 结果摘要（成功/失败/取消）
       pub result_summary: Option<String>,
   }
   
   pub enum ServerRequestResolvedReason {
       Completed,
       Cancelled,
       Timeout,
       Error,
   }
   ```

3. **状态同步**：
   - 实现请求状态查询接口
   - 支持批量状态同步
   - 添加状态变更历史

4. **可观测性**：
   - 记录通知发送和接收
   - 监控通知延迟
   - 提供请求生命周期追踪

5. **错误处理**：
   - 添加重试机制
   - 实现离线通知队列
   - 支持通知回放

6. **性能优化**：
   - 批量发送通知
   - 压缩通知数据
   - 实现通知节流
