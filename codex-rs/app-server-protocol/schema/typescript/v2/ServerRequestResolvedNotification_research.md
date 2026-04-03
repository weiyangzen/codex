# ServerRequestResolvedNotification 研究文档

## 1. 场景与职责

`ServerRequestResolvedNotification` 是 Codex app-server-protocol v2 协议中的服务器通知类型，用于通知客户端服务器请求已被解决或完成。该类型在服务器端处理完成某个请求后发送，让客户端可以清理相关状态或执行后续操作。

### 使用场景
- **请求完成通知**：告知客户端服务器端请求处理已完成
- **资源清理**：客户端收到通知后可以释放相关资源
- **状态同步**：保持客户端和服务器端状态的一致性
- **超时处理**：配合超时机制，明确请求的最终状态

## 2. 功能点目的

该类型的核心目的是：
1. **生命周期管理**：明确服务器请求的生命周期结束点
2. **状态一致性**：确保客户端了解服务器端请求的最终状态
3. **资源管理**：允许客户端在请求完成后进行资源清理

### 与相关类型的关系
- `RequestId`：标识被解决的请求
- `ServerNotification`：作为服务器通知的一种变体

## 3. 具体技术实现

### TypeScript 类型定义
```typescript
import type { RequestId } from "../RequestId";

export type ServerRequestResolvedNotification = { 
  threadId: string, 
  requestId: RequestId, 
};
```

### 字段说明
| 字段 | 类型 | 说明 |
|------|------|------|
| `threadId` | `string` | 请求所属的线程 ID |
| `requestId` | `RequestId` | 被解决的请求的唯一标识符 |

### RequestId 类型
```typescript
// RequestId.ts
export type RequestId = string | number;
```

### Rust 源实现
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ServerRequestResolvedNotification {
    pub thread_id: String,
    pub request_id: RequestId,
}
```

## 4. 关键代码路径与文件引用

### 协议定义
- **Rust 源文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 4939-4945)
- **TypeScript 文件**: `codex-rs/app-server-protocol/schema/typescript/v2/ServerRequestResolvedNotification.ts`

### 通知注册
- **文件**: `codex-rs/app-server-protocol/src/protocol/common.rs` (行 905)
  ```rust
  ServerRequestResolved => "serverRequest/resolved" (v2::ServerRequestResolvedNotification)
  ```

### 使用位置

#### 客户端处理
- **文件**: `codex-rs/app-server-client/src/remote.rs`
  - 管理请求 ID 到响应通道的映射
  - 行 161: `HashMap::<RequestId, oneshot::Sender<IoResult<RequestResult>>>::new()`

#### 请求 ID 生成
- **文件**: `codex-rs/app-server-client/src/lib.rs`
  - 行 1003, 1016, 1040 等：生成和使用 `RequestId`

### JSON Schema
- `codex-rs/app-server-protocol/schema/json/ServerNotification.json`
- `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json`

## 5. 依赖与外部交互

### 导入依赖
| 类型 | 来源 | 说明 |
|------|------|------|
| `RequestId` | `../RequestId` | 请求标识符类型 |

### 被依赖类型
- `ServerNotification` - 包含此通知作为变体之一

### 通知方法名
- `serverRequest/resolved` - 在 `common.rs` 中注册的通知方法

## 6. 风险、边界与改进建议

### 潜在风险
1. **通知丢失**：如果通知丢失，客户端可能永远等待请求完成
2. **重复通知**：服务器可能发送重复的通知
3. **时序问题**：通知可能在客户端处理响应之前到达

### 边界情况
- **无效请求 ID**：通知中的请求 ID 可能不存在于客户端
- **已清理请求**：客户端可能已经清理了该请求的状态
- **并发通知**：多个请求同时完成时的通知顺序

### 改进建议
1. **添加结果状态**：
   ```typescript
   export type ServerRequestResolvedNotification = { 
     threadId: string, 
     requestId: RequestId,
     status: "success" | "error" | "cancelled",
     error?: string,
   };
   ```

2. **添加时间戳**：
   ```typescript
   resolvedAt: number;  // Unix 时间戳
   ```

3. **幂等性保证**：
   - 确保客户端可以安全地处理重复通知
   - 使用请求 ID 去重

4. **心跳机制**：
   - 对于长时间运行的请求，添加进度通知
   - 防止客户端认为连接已断开

### 使用示例
```typescript
// 客户端处理通知
client.onNotification("serverRequest/resolved", (notification) => {
  const { threadId, requestId } = notification;
  
  // 查找待处理的请求
  const pendingRequest = pendingRequests.get(requestId);
  if (pendingRequest) {
    // 标记为已完成
    pendingRequest.resolve();
    pendingRequests.delete(requestId);
  }
  
  // 清理相关资源
  cleanupRequestResources(threadId, requestId);
});

// 发送请求并等待解决
async function sendRequest(request: ClientRequest): Promise<void> {
  const requestId = generateRequestId();
  await client.sendRequest({ ...request, requestId });
  
  return new Promise((resolve) => {
    pendingRequests.set(requestId, { resolve });
    
    // 设置超时
    setTimeout(() => {
      if (pendingRequests.has(requestId)) {
        pendingRequests.delete(requestId);
        throw new Error("Request timeout");
      }
    }, 30000);
  });
}
```

### 相关类型关系
```
ServerNotification
└── ServerRequestResolved { params: ServerRequestResolvedNotification }
    ├── threadId: string
    └── requestId: RequestId  (string | number)

ClientRequest
├── requestId: RequestId  <-- 相同的 ID 类型
└── ...
```

### 注意事项
- 该通知表示服务器端请求处理完成，但不表示请求成功
- 客户端需要结合响应结果判断请求的实际结果
- 建议客户端实现超时机制，防止无限等待
