# ServerRequestResolvedNotification 研究文档

## 场景与职责

`ServerRequestResolvedNotification` 是 Codex App Server Protocol v2 中用于通知客户端服务器请求已解决的通知类型。当服务器向客户端发送请求（如权限请求、用户输入请求等）并收到客户端的响应后，服务器发送此通知表示请求已完成处理。

该类型在服务器-客户端请求-响应流程中扮演重要角色，用于清理请求状态和同步双方状态。

## 功能点目的

1. **请求状态同步**：通知客户端服务器已处理完请求
2. **资源清理**：客户端可以清理与该请求相关的资源
3. **流程控制**：确保请求-响应周期的完整性
4. **超时处理**：支持请求超时后的状态清理

## 具体技术实现

### 数据结构

```rust
// Rust 定义 (codex-rs/app-server-protocol/src/protocol/v2.rs)
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ServerRequestResolvedNotification {
    pub thread_id: String,
    pub request_id: RequestId,
}
```

```typescript
// TypeScript 生成类型 (schema/typescript/v2/ServerRequestResolvedNotification.ts)
import type { RequestId } from "../RequestId";

export type ServerRequestResolvedNotification = { 
    threadId: string, 
    requestId: RequestId, 
};
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `thread_id` | `String` | 请求所属的线程 ID |
| `request_id` | `RequestId` | 已解决的服务器请求 ID |

### RequestId 类型

```rust
// RequestId 定义在 lib.rs
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Hash, JsonSchema, TS)]
#[serde(untagged)]
#[ts(export_to = "v2/")]
pub enum RequestId {
    String(String),
    Integer(i64),
}
```

```typescript
// TypeScript 中 RequestId 是 string | number
export type RequestId = string | number;
```

## 关键代码路径与文件引用

### 定义位置
- **Rust 定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 4939-4945)
- **TypeScript 生成**: `codex-rs/app-server-protocol/schema/typescript/v2/ServerRequestResolvedNotification.ts`

### 相关类型
- `RequestId`: 请求 ID 类型
- `ServerRequest`: 服务器请求枚举
- `CommandExecutionRequestApprovalParams`: 命令执行请求审批参数
- `FileChangeRequestApprovalParams`: 文件变更请求审批参数

### 使用场景
- 服务器发送请求后收到客户端响应
- 服务器请求超时或被取消
- 请求处理完成后的状态同步

## 依赖与外部交互

### 内部依赖
- `RequestId`: 请求标识符类型
- `serde`: 序列化/反序列化
- `schemars`: JSON Schema 生成
- `ts_rs`: TypeScript 类型生成

### 协议交互

**典型流程示例**（命令执行审批）：

1. 服务器发送请求：
```json
{
    "jsonrpc": "2.0",
    "id": "server-req-123",
    "method": "item/commandExecution/requestApproval",
    "params": {
        "threadId": "thread-456",
        "turnId": "turn-789",
        "itemId": "item-abc",
        "command": "rm -rf /",
        "cwd": "/home/user"
    }
}
```

2. 客户端发送响应：
```json
{
    "jsonrpc": "2.0",
    "id": "server-req-123",
    "result": {
        "decision": "decline"
    }
}
```

3. 服务器发送解决通知：
```json
{
    "jsonrpc": "2.0",
    "method": "serverRequestResolved",
    "params": {
        "threadId": "thread-456",
        "requestId": "server-req-123"
    }
}
```

### 消息流程

```
┌─────────┐                    ┌─────────┐
│ Server  │ ── Server Request ─▶│ Client  │
│         │                    │         │
│         │ ◀── Client Response│         │
│         │                    │         │
│         │ ── Resolved Notif ─▶│         │
└─────────┘                    └─────────┘
```

## 风险、边界与改进建议

### 当前限制
1. **无结果信息**：通知不包含请求的处理结果
2. **无时间戳**：不包含请求解决的时间信息
3. **无原因说明**：不包含请求解决的原因（正常完成/超时/取消）

### 边界情况
1. **重复通知**：同一请求 ID 可能多次发送解决通知
2. **乱序到达**：通知可能在客户端响应之前到达
3. **未知请求**：客户端可能收到未识别的请求 ID 的解决通知

### 改进建议

1. **添加结果信息**：
   ```rust
   pub struct ServerRequestResolvedNotification {
       pub thread_id: String,
       pub request_id: RequestId,
       pub result: Option<RequestResult>,  // 新增
   }
   
   pub enum RequestResult {
       Completed,
       Cancelled,
       TimedOut,
       Error(String),
   }
   ```

2. **添加时间戳**：
   ```rust
   pub struct ServerRequestResolvedNotification {
       pub thread_id: String,
       pub request_id: RequestId,
       pub resolved_at: i64,  // 新增：Unix 时间戳
   }
   ```

3. **添加请求类型**：
   ```rust
   pub struct ServerRequestResolvedNotification {
       pub thread_id: String,
       pub request_id: RequestId,
       pub request_type: String,  // 新增：请求类型标识
   }
   ```

### 兼容性注意
- 使用 `camelCase` 命名确保与 TypeScript 惯例一致
- `RequestId` 支持字符串和整数两种格式
- 未来添加字段时应使用 `Option<T>` 确保向后兼容

### 客户端处理建议

```typescript
class RequestManager {
    private pendingRequests: Map<string, PendingRequest> = new Map();

    handleServerRequest(request: ServerRequest): void {
        this.pendingRequests.set(request.id, {
            id: request.id,
            timestamp: Date.now(),
            // ...
        });
    }

    handleServerResponse(response: ClientResponse): void {
        // 发送响应给服务器
        this.send(response);
    }

    handleResolvedNotification(notification: ServerRequestResolvedNotification): void {
        const request = this.pendingRequests.get(notification.requestId);
        if (request) {
            // 清理资源
            this.pendingRequests.delete(notification.requestId);
            // 触发回调
            request.resolve();
        }
    }

    // 超时清理
    checkTimeouts(): void {
        const now = Date.now();
        for (const [id, request] of this.pendingRequests) {
            if (now - request.timestamp > REQUEST_TIMEOUT) {
                this.pendingRequests.delete(id);
                request.reject(new Error("Request timeout"));
            }
        }
    }
}
```

### 相关服务器请求类型

| 请求方法 | 描述 | 响应类型 |
|----------|------|----------|
| `item/commandExecution/requestApproval` | 命令执行审批请求 | `CommandExecutionRequestApprovalResponse` |
| `item/fileChange/requestApproval` | 文件变更审批请求 | `FileChangeRequestApprovalResponse` |
| `permissions/requestApproval` | 权限请求 | `PermissionsRequestApprovalResponse` |
| `toolRequestUserInput` | 工具用户输入请求 | `ToolRequestUserInputResponse` |

### 使用场景总结

1. **审批流程**：用户审批命令执行或文件变更后
2. **权限授予**：用户授予额外权限后
3. **用户输入**：用户提供工具所需的输入后
4. **超时处理**：服务器请求超时时
5. **取消操作**：用户取消待处理的请求时
