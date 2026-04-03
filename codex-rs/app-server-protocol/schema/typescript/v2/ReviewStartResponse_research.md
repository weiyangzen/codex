# ReviewStartResponse 研究文档

## 1. 场景与职责

`ReviewStartResponse` 是 Codex app-server-protocol v2 协议中的代码审查启动响应类型，用于返回代码审查启动后的结果信息。该类型向客户端提供审查任务的标识信息，包括审查回合详情和审查线程 ID。

### 使用场景
- **审查启动确认**：确认代码审查请求已被接受并启动
- **线程导航**：分离模式下，客户端需要知道新创建的审查线程 ID
- **状态跟踪**：通过返回的 `Turn` 对象跟踪审查进度

## 2. 功能点目的

该类型的核心目的是：
1. **确认审查启动**：向客户端确认审查请求已成功处理
2. **提供导航信息**：告知客户端审查结果将在哪个线程显示
3. **状态同步**：返回初始回合信息，便于客户端同步状态

### 与相关类型的关系
- `ReviewStartParams`：对应的请求参数类型
- `Turn`：审查回合的详细信息
- `ReviewDelivery`：影响 `reviewThreadId` 的取值

## 3. 具体技术实现

### TypeScript 类型定义
```typescript
import type { Turn } from "./Turn";

export type ReviewStartResponse = { 
  turn: Turn, 
  /**
   * Identifies the thread where the review runs.
   *
   * For inline reviews, this is the original thread id.
   * For detached reviews, this is the id of the new review thread.
   */
  reviewThreadId: string, 
};
```

### 字段说明
| 字段 | 类型 | 说明 |
|------|------|------|
| `turn` | `Turn` | 审查回合的详细信息 |
| `reviewThreadId` | `string` | 审查运行的线程 ID（内联模式为原线程，分离模式为新线程） |

### Rust 源实现
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ReviewStartResponse {
    pub turn: Turn,
    /// Identifies the thread where the review runs.
    ///
    /// For inline reviews, this is the original thread id.
    /// For detached reviews, this is the id of the new review thread.
    pub review_thread_id: String,
}
```

## 4. 关键代码路径与文件引用

### 协议定义
- **Rust 源文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 3895-3905)
- **TypeScript 文件**: `codex-rs/app-server-protocol/schema/typescript/v2/ReviewStartResponse.ts`

### RPC 方法
- **方法**: `review/start`
- **请求**: `ReviewStartParams`
- **响应**: `ReviewStartResponse` (本类型)

### 使用位置

#### 消息处理器
- **文件**: `codex-rs/app-server/src/codex_message_processor.rs`
  - 构造并返回 `ReviewStartResponse`
  - 根据 `delivery` 模式设置 `review_thread_id`

#### 测试
- **文件**: `codex-rs/app-server/tests/suite/v2/review.rs`
  - 验证响应中的 `turn` 和 `reviewThreadId` 字段

### JSON Schema
- `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json`
- `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.schemas.json`

## 5. 依赖与外部交互

### 导入依赖
| 类型 | 来源 | 说明 |
|------|------|------|
| `Turn` | `./Turn` | 回合详细信息 |

### 被依赖类型
- `ClientResponse` - 作为 `review/start` 方法的响应类型

### 相关枚举
- `ReviewDelivery` - 决定 `reviewThreadId` 的取值逻辑

## 6. 风险、边界与改进建议

### 潜在风险
1. **线程 ID 混淆**：客户端可能混淆 `threadId`（请求参数）和 `reviewThreadId`（响应）
2. **状态同步延迟**：返回的 `Turn` 可能很快更新，客户端需要监听通知
3. **并发冲突**：多个审查同时启动时的线程管理

### 边界情况
- **内联模式**：`reviewThreadId` 等于请求中的 `threadId`
- **分离模式**：`reviewThreadId` 是新创建的线程 ID
- **启动失败**：响应结构可能不包含完整数据

### 实现逻辑
```rust
// 伪代码展示 review_thread_id 的赋值逻辑
let review_thread_id = match delivery {
    ReviewDelivery::Inline => params.thread_id,  // 原线程
    ReviewDelivery::Detached => create_new_thread().id,  // 新线程
};
```

### 改进建议
1. **添加审查 ID**：
   ```typescript
   reviewId: string;  // 全局唯一的审查标识
   ```

2. **添加状态字段**：
   ```typescript
   status: "queued" | "in_progress" | "completed" | "failed";
   ```

3. **添加预估时间**：
   ```typescript
   estimatedDuration?: number;  // 预估审查时间（秒）
   ```

4. **文档增强**：
   - 添加更多使用示例
   - 说明客户端如何根据 `reviewThreadId` 切换视图

5. **类型优化**：
   - 考虑使用联合类型区分内联和分离模式的响应

### 使用示例
```typescript
// 客户端处理响应
const response: ReviewStartResponse = await client.reviewStart(params);

// 导航到审查线程
if (params.delivery === "detached") {
  // 分离模式：切换到新线程
  ui.switchToThread(response.reviewThreadId);
} else {
  // 内联模式：保持在当前线程
  ui.scrollToTurn(response.turn.id);
}

// 监听审查进度
client.onNotification("turn/completed", (notification) => {
  if (notification.turn.id === response.turn.id) {
    showReviewComplete(notification.turn);
  }
});
```

### 相关类型关系
```
review/start
├── request: ReviewStartParams
│   ├── threadId: string
│   ├── target: ReviewTarget
│   └── delivery?: ReviewDelivery | null
│
└── response: ReviewStartResponse  <-- 本类型
    ├── turn: Turn
    │   ├── id: string
    │   ├── status: TurnStatus
    │   └── ...
    └── reviewThreadId: string
        // inline:  == threadId
        // detached: != threadId (new thread)
```
