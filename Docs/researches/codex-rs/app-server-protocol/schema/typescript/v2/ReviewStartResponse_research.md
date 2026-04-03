# ReviewStartResponse 研究文档

## 场景与职责

`ReviewStartResponse` 是 Codex app-server-protocol v2 协议中 `review/start` 方法的响应类型，用于返回代码审查启动后的结果信息。该类型向客户端提供审查任务的标识信息，包括审查回合详情和审查线程 ID。

在 Codex 的代码审查功能中，`ReviewStartResponse` 承担以下职责：
1. **审查确认**：确认审查请求已成功处理
2. **线程标识**：告知客户端审查实际执行的线程 ID
3. **回合信息**：提供创建的审查回合详情
4. **后续操作**：为客户端提供追踪审查所需的标识符

## 功能点目的

### 核心功能
- **回合返回**：返回创建的 `Turn` 对象
- **线程标识**：返回 `reviewThreadId` 用于追踪审查
- **模式适配**：根据 `delivery` 模式返回不同的线程 ID
- **类型安全**：提供强类型的响应结构

### 设计意图
- **信息完整**：包含审查追踪所需的全部标识信息
- **灵活线程**：`reviewThreadId` 可能不同于请求的 `threadId`
- **扩展预留**：结构可扩展以支持更多审查元数据

## 具体技术实现

### 数据结构定义

**TypeScript 定义**（`ReviewStartResponse.ts`）：
```typescript
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

**Rust 定义**（`v2.rs` 行 3898-3905）：
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

### 关键字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `turn` | `Turn` | 创建的审查回合对象，包含回合 ID、状态、项目列表等 |
| `reviewThreadId` | `string` | 审查实际执行的线程 ID，根据 `delivery` 模式可能不同 |

### reviewThreadId 逻辑

根据 `ReviewStartParams.delivery` 的值：

| delivery 值 | reviewThreadId 值 | 说明 |
|-------------|-------------------|------|
| `inline` (默认) | 请求的 `threadId` | 审查在当前线程执行 |
| `detached` | 新生成的线程 ID | 审查在新创建的线程执行 |

### 处理逻辑

在 `codex_message_processor.rs` 行 6329-6340：
```rust
let response = ReviewStartResponse {
    turn: Turn {
        id: turn_id.to_string(),
        items: vec![],
        status: TurnStatus::InProgress,
        error: None,
    },
    review_thread_id: review_thread_id.to_string(),
};
self.send_response(request_id, response).await?;
```

## 关键代码路径与文件引用

### 定义位置
- **Rust 定义**：`codex-rs/app-server-protocol/src/protocol/v2.rs` 行 3898-3905
- **TypeScript 生成**：`codex-rs/app-server-protocol/schema/typescript/v2/ReviewStartResponse.ts`
- **JSON Schema**：`codex-rs/app-server-protocol/schema/json/v2/ReviewStartResponse.json`

### 使用位置
- **ClientRequest 定义**：`common.rs` 行 385-386 - 注册为 RPC 方法响应
- **消息处理器**：`codex_message_processor.rs` 行 6329 - 构造响应
- **测试用例**：`tests/suite/v2/review.rs` 行 81, 183, 297 - 验证响应

### 相关类型
- `ReviewStartParams`：对应的请求参数（行 3884-3893）
- `Turn`：回合对象（行 3583-3592）
- `TurnStatus`：回合状态枚举（行 3815-3820）
- `ReviewDelivery`：影响 `reviewThreadId` 的交付模式

### 响应构造流程

```rust
// codex_message_processor.rs::review_start() 行 6488+
async fn review_start(&mut self, request_id: ConnectionRequestId, params: ReviewStartParams) {
    let ReviewStartParams { thread_id, target, delivery } = params;
    
    // 确定 review_thread_id
    let review_thread_id = match delivery {
        Some(ReviewDelivery::Detached) => create_new_thread().id,
        _ => thread_id,
    };
    
    // 创建审查回合
    let turn_id = create_turn(review_thread_id, target);
    
    // 构造响应
    let response = ReviewStartResponse {
        turn: Turn {
            id: turn_id,
            items: vec![],
            status: TurnStatus::InProgress,
            error: None,
        },
        review_thread_id,
    };
    
    self.send_response(request_id, response).await;
}
```

## 依赖与外部交互

### 依赖项
- `Turn`：回合类型
- `serde`：序列化/反序列化支持
- `schemars`：JSON Schema 生成
- `ts-rs`：TypeScript 类型生成

### 上游依赖
- `ReviewStartParams`：对应的请求类型
- `CoreReviewTarget`：核心协议中的审查目标

### 下游使用
- `ClientRequest::ReviewStart`：作为该 RPC 方法的响应
- 客户端 UI：使用 `reviewThreadId` 订阅审查更新

### 协议集成
- RPC 方法名：`review/start`（`common.rs` 行 385-386）
- 响应方向：Server → Client
- 成功响应：`ReviewStartResponse`
- 错误响应：JSON-RPC 错误对象

## 风险、边界与改进建议

### 潜在风险
1. **线程 ID 混淆**：客户端可能混淆 `threadId` 和 `reviewThreadId`
2. **状态不同步**：响应返回时回合状态可能已经变化
3. **空项目列表**：初始响应中 `turn.items` 为空，需要后续通知填充

### 边界情况
1. **立即完成**：审查立即完成时的响应
2. **启动失败**：审查启动失败但响应已发送的情况
3. **线程创建失败**：`detached` 模式下线程创建失败

### 改进建议
1. **添加元数据字段**：
   ```rust
   pub struct ReviewStartResponse {
       // 现有字段...
       /// 审查启动时间戳
       pub started_at: i64,
       /// 预计审查时间（秒）
       pub estimated_duration_seconds: Option<u32>,
       /// 审查目标描述
       pub target_description: String,
       /// 是否为增量审查
       pub is_incremental: bool,
   }
   ```

2. **状态同步**：
   - 添加初始项目快照（如果立即可用）
   - 提供状态订阅机制
   - 支持长轮询获取更新

3. **错误处理改进**：
   - 添加警告字段（非致命问题）
   - 提供故障排除建议
   - 支持部分成功场景

4. **可观测性**：
   - 添加审查追踪 ID
   - 提供审查日志链接
   - 支持审查回放

5. **协作功能**：
   - 添加审查会话 ID 支持多人协作
   - 提供分享链接
   - 支持评论和讨论

6. **性能优化**：
   - 支持响应压缩
   - 实现增量更新
   - 添加缓存控制头
