# ReviewStartResponse 研究文档

## 场景与职责

`ReviewStartResponse` 是 Codex App Server Protocol v2 中代码审查启动操作的响应结构体。它返回审查启动后的初始状态，包括创建的回合信息和审查线程 ID。

该类型是 `review/start` API 的响应格式，客户端通过此响应获取审查的初始状态，并根据 `review_thread_id` 跟踪审查进度。

## 功能点目的

1. **审查状态返回**：返回审查启动后的初始回合状态
2. **线程标识**：返回审查实际运行的线程 ID
3. **进度跟踪**：客户端使用返回的信息跟踪审查进度
4. **模式区分**：根据交付模式返回不同的线程 ID

## 具体技术实现

### 数据结构

```rust
// Rust 定义 (codex-rs/app-server-protocol/src/protocol/v2.rs)
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

```typescript
// TypeScript 生成类型 (schema/typescript/v2/ReviewStartResponse.ts)
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
| `turn` | `Turn` | 审查创建的回合信息 |
| `review_thread_id` | `String` | 审查实际运行的线程 ID |

### 交付模式与线程 ID 的关系

| 交付模式 | `review_thread_id` 值 | 说明 |
|----------|----------------------|------|
| `Inline` | 与原线程 ID 相同 | 审查在当前线程中执行 |
| `Detached` | 新创建的线程 ID | 审查在新线程中执行 |

### Turn 类型

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct Turn {
    pub id: String,
    /// Only populated on a `thread/resume` or `thread/fork` response.
    /// For all other responses and notifications returning a Turn,
    /// the items field will be an empty list.
    pub items: Vec<ThreadItem>,
    pub status: TurnStatus,
    /// Only populated when the Turn's status is failed.
    pub error: Option<TurnError>,
}
```

## 关键代码路径与文件引用

### 定义位置
- **Rust 定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 3895-3905)
- **TypeScript 生成**: `codex-rs/app-server-protocol/schema/typescript/v2/ReviewStartResponse.ts`

### 相关类型
- `ReviewStartParams`: 对应的请求参数类型
- `Turn`: 回合信息类型
- `TurnStatus`: 回合状态枚举（InProgress, Completed, Interrupted, Failed）

### 使用场景
- 服务器处理 `review/start` 请求后返回此响应
- 客户端解析响应以获取审查线程 ID
- 客户端使用线程 ID 订阅审查进度通知

## 依赖与外部交互

### 内部依赖
- `Turn`: 回合类型
- `TurnStatus`: 回合状态
- `TurnError`: 回合错误信息
- `serde`: 序列化/反序列化
- `schemars`: JSON Schema 生成
- `ts_rs`: TypeScript 类型生成

### 协议交互

**内联审查响应**:
```json
{
    "jsonrpc": "2.0",
    "id": 1,
    "result": {
        "turn": {
            "id": "turn-456",
            "items": [],
            "status": "inProgress",
            "error": null
        },
        "reviewThreadId": "thread-123"
    }
}
```

**分离审查响应**:
```json
{
    "jsonrpc": "2.0",
    "id": 1,
    "result": {
        "turn": {
            "id": "turn-789",
            "items": [],
            "status": "inProgress",
            "error": null
        },
        "reviewThreadId": "thread-new-456"
    }
}
```

### 消息流程

1. 客户端发送 `review/start` 请求
2. 服务器创建审查回合（可能创建新线程）
3. 服务器返回 `ReviewStartResponse`
4. 客户端根据 `review_thread_id` 订阅通知
5. 服务器发送 `turn/started` 通知
6. 服务器发送 `item/started` 通知（包含 `EnteredReviewMode`）
7. 审查进行中，服务器发送各种增量通知
8. 服务器发送 `item/completed` 通知（包含 `ExitedReviewMode`）
9. 服务器发送 `turn/completed` 通知

## 风险、边界与改进建议

### 当前限制
1. **items 为空**：响应中的 `turn.items` 通常为空列表，实际项目通过通知发送
2. **无审查 ID**：没有独立的审查标识符，依赖线程 ID 和回合 ID
3. **无预计时间**：没有审查预计完成时间

### 边界情况
1. **审查立即完成**：某些简单审查可能在响应返回前已完成
2. **审查启动失败**：错误通过 JSON-RPC error 返回，而非此响应
3. **线程创建失败**：分离模式下新线程创建失败的处理

### 测试覆盖

从 `review.rs` 测试文件可以看到响应验证：

```rust
let ReviewStartResponse {
    turn,
    review_thread_id,
} = to_response::<ReviewStartResponse>(review_resp)?;

// 内联模式：review_thread_id 应与原线程相同
assert_eq!(review_thread_id, thread_id.clone());

// 分离模式：review_thread_id 应是新线程
assert_ne!(review_thread_id, thread_id);

// 验证回合状态
assert_eq!(turn.status, TurnStatus::InProgress);
let turn_id = turn.id.clone();
```

### 改进建议

1. **添加审查 ID**：
   ```rust
   pub struct ReviewStartResponse {
       pub turn: Turn,
       pub review_thread_id: String,
       pub review_id: String,  // 新增：独立的审查标识符
   }
   ```

2. **添加预计时间**：
   ```rust
   pub struct ReviewStartResponse {
       // ...
       pub estimated_duration_seconds: Option<u64>,  // 新增：预计耗时
   }
   ```

3. **添加上下文信息**：
   ```rust
   pub struct ReviewStartResponse {
       // ...
       pub review_context: Option<ReviewContext>,  // 新增：审查上下文
   }
   
   pub struct ReviewContext {
       pub target_summary: String,  // 审查目标摘要
       pub files_count: u32,        // 涉及文件数
       pub lines_count: u32,        // 涉及行数
   }
   ```

4. **添加初始发现**：
   ```rust
   pub struct ReviewStartResponse {
       // ...
       pub initial_findings: Option<Vec<InitialFinding>>,  // 新增：初步发现
   }
   ```

### 兼容性注意
- 使用 `camelCase` 命名确保与 TypeScript 惯例一致
- `turn.items` 为空是设计行为，客户端应通过通知获取实际项目
- 未来添加字段时应使用 `Option<T>` 确保向后兼容

### 客户端处理建议

```typescript
async function startReview(params: ReviewStartParams): Promise<void> {
    const response = await sendRequest('review/start', params);
    const { turn, reviewThreadId } = response.result;
    
    // 订阅审查线程的通知
    subscribeToThread(reviewThreadId);
    
    // 等待审查完成
    await waitForTurnCompletion(reviewThreadId, turn.id);
    
    // 获取审查结果
    const reviewResult = await getReviewResult(reviewThreadId, turn.id);
    displayReviewResult(reviewResult);
}
```
