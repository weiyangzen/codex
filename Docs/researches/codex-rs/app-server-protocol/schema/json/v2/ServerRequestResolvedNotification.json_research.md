# ServerRequestResolvedNotification.json 研究文档

## 场景与职责

`ServerRequestResolvedNotification` 是 Codex App-Server Protocol v2 API 中的服务器通知类型，用于通知客户端服务器发起的请求已被解决。该通知在服务器向客户端发送请求（如审批请求）并收到客户端响应后发送，标记请求生命周期的完成。

## 功能点目的

1. **请求完成通知**: 通知客户端服务器发起的请求已被处理完成
2. **状态同步**: 同步服务器端请求状态到客户端
3. **资源清理**: 标记可以清理相关请求资源
4. **超时处理**: 支持请求超时后的状态通知

## 具体技术实现

### 数据结构定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ServerRequestResolvedNotification {
    pub request_id: RequestId,
    pub thread_id: String,
}
```

### 字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `requestId` | RequestId | 是 | 已解决请求的唯一标识符 |
| `threadId` | string | 是 | 请求所属的线程 ID |

### RequestId 类型

RequestId 是一个联合类型，支持字符串或整数：
- `string`: 字符串形式的请求 ID
- `integer` (int64): 整数形式的请求 ID

```json
{
  "anyOf": [
    { "type": "string" },
    { "format": "int64", "type": "integer" }
  ]
}
```

### JSON Schema 结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "definitions": {
    "RequestId": {
      "anyOf": [
        { "type": "string" },
        { "format": "int64", "type": "integer" }
      ]
    }
  },
  "properties": {
    "requestId": { "$ref": "#/definitions/RequestId" },
    "threadId": { "type": "string" }
  },
  "required": ["requestId", "threadId"],
  "title": "ServerRequestResolvedNotification",
  "type": "object"
}
```

## 关键代码路径与文件引用

### 源文件位置
- **Rust 结构定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs`
  - `ServerRequestResolvedNotification`: 第 4942 行附近
  - `RequestId`: 定义在 `codex-rs/app-server-protocol/src/lib.rs`

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ServerRequestResolvedNotification {
    pub request_id: RequestId,
    pub thread_id: String,
}
```

### Schema 生成
- **生成工具**: `codex-rs/app-server-protocol/src/bin/write_schema_fixtures.rs`
- **生成函数**: `export_server_notification_schemas()` 在 `common.rs` 中定义

### 使用位置
- **ServerNotification 定义**: `codex-rs/app-server-protocol/src/protocol/common.rs` 第 905 行
```rust
ServerRequestResolved => "serverRequest/resolved" (v2::ServerRequestResolvedNotification),
```

### 关联服务器请求类型
在 `common.rs` 中定义的 `ServerRequest` 枚举：
- `CommandExecutionRequestApproval`: 命令执行审批请求
- `FileChangeRequestApproval`: 文件变更审批请求
- `ToolRequestUserInput`: 工具请求用户输入（实验性）
- `McpServerElicitationRequest`: MCP 服务器请求
- `PermissionsRequestApproval`: 权限请求审批
- `DynamicToolCall`: 动态工具调用
- `ChatgptAuthTokensRefresh`: ChatGPT 认证令牌刷新

## 依赖与外部交互

### 内部依赖
1. **RequestId**: 请求标识类型，支持字符串或整数
2. **schemars**: JSON Schema 生成
3. **ts_rs**: TypeScript 类型生成
4. **serde**: 序列化/反序列化

### 外部交互
1. **服务器请求系统**: 跟踪服务器发起的请求状态
2. **客户端请求处理**: 客户端处理完请求后触发此通知
3. **超时管理器**: 请求超时后也可能触发此通知

### 通知序列示例
```
Server -> Client: ServerRequest (e.g., CommandExecutionRequestApproval)
  -> Client processes request
    -> Client -> Server: Response
      -> Server processes response
        -> Server -> Client: ServerRequestResolvedNotification
```

### 客户端处理逻辑
```typescript
// 伪代码示例
const pendingRequests: Map<RequestId, PendingRequest> = new Map();

onServerRequest(request) {
  pendingRequests.set(request.id, { request, timestamp: Date.now() });
  // 处理请求...
}

onServerRequestResolved(notification) {
  const { requestId, threadId } = notification;
  const pending = pendingRequests.get(requestId);
  if (pending) {
    pending.resolve();
    pendingRequests.delete(requestId);
  }
}
```

## 风险、边界与改进建议

### 风险点
1. **通知丢失**: 如果通知丢失，客户端可能永远不知道请求已解决
2. **重复通知**: 网络重连可能导致重复收到解决通知
3. **乱序到达**: 在极端情况下，解决通知可能在请求之前到达
4. **ID 冲突**: 字符串和整数 ID 可能在某些场景下产生冲突

### 边界情况
1. **请求不存在**: 通知引用的请求 ID 在客户端不存在
2. **线程不匹配**: requestId 存在但 threadId 不匹配
3. **重复解决**: 同一请求被多次标记为已解决
4. **超时解决**: 请求因超时而解决，而非正常响应

### 改进建议
1. **添加解决原因**: 说明请求是如何被解决的：
   ```rust
   pub struct ServerRequestResolvedNotification {
       pub request_id: RequestId,
       pub thread_id: String,
       pub resolution: RequestResolution,  // 新增
   }
   
   pub enum RequestResolution {
       Completed,      // 正常完成
       TimedOut,       // 超时
       Cancelled,      // 被取消
       Superseded,     // 被新请求取代
   }
   ```

2. **添加时间戳**: 记录解决时间：
   ```rust
   pub struct ServerRequestResolvedNotification {
       // ... existing fields
       pub resolved_at: i64,  // Unix 时间戳（毫秒）
   }
   ```

3. **添加响应摘要**: 对于需要确认的请求，包含响应摘要：
   ```rust
   pub struct ServerRequestResolvedNotification {
       // ... existing fields
       pub response_summary: Option<ResponseSummary>,
   }
   ```

4. **批量通知**: 支持多个请求同时解决的场景：
   ```rust
   pub struct ServerRequestsResolvedNotification {
       pub resolutions: Vec<SingleResolution>,
   }
   ```

5. **确认机制**: 客户端收到通知后发送确认，防止重复处理
