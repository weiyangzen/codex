# ReviewStartResponse.ts 研究文档

## 场景与职责

`ReviewStartResponse.ts` 定义了代码审查启动响应的数据结构，用于服务器向客户端返回审查启动的结果。这是 `review/start` RPC 方法的响应类型，包含审查回合信息和审查线程标识。

## 功能点目的

该类型用于：
1. **审查确认**：确认审查请求已成功处理
2. **线程标识**：告知客户端审查实际执行的线程
3. **回合信息**：提供审查回合的初始状态
4. **导航支持**：客户端使用返回信息导航到审查界面

## 具体技术实现

### 数据结构定义

```typescript
import type { Turn } from "./Turn";

export type ReviewStartResponse = { 
  turn: Turn,              // 审查回合信息
  /**
   * Identifies the thread where the review runs.
   *
   * For inline reviews, this is the original thread id.
   * For detached reviews, this is the id of the new review thread.
   */
  reviewThreadId: string,  // 审查线程ID
};
```

### 字段详解

| 字段 | 类型 | 说明 |
|------|------|------|
| turn | Turn | 审查回合的初始状态，包含回合ID、状态等信息 |
| reviewThreadId | string | 审查实际执行的线程标识符 |

### reviewThreadId 的行为

| 交付方式 | reviewThreadId 值 | 说明 |
|---------|-------------------|------|
| inline | 原线程ID | 审查在发起线程中执行 |
| detached | 新线程ID | 审查在新创建的线程中执行 |

### Rust 协议定义

在 `codex-rs/app-server-protocol/src/protocol/common.rs` 中：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ReviewStartResponse {
    pub turn: Turn,
    pub review_thread_id: String,
}
```

### Turn 类型

Turn 类型包含回合的基本信息：

```rust
pub struct Turn {
    pub id: String,
    pub status: TurnStatus,
    // ... 其他字段
}
```

### 服务端构造逻辑

在 `codex-rs/app-server/src/codex_message_processor.rs` 中：

```rust
async fn handle_review_start(
    &self,
    params: ReviewStartParams,
) -> Result<ReviewStartResponse, Error> {
    // 1. 验证 target 有效性
    let target = self.validate_review_target(&params.target).await?;
    
    // 2. 确定线程（inline 使用原线程，detached 创建新线程）
    let review_thread_id = match params.delivery {
        Some(ReviewDelivery::Detached) | None => {
            self.create_review_thread(&params.thread_id).await?
        }
        Some(ReviewDelivery::Inline) => params.thread_id.clone(),
    };
    
    // 3. 启动审查回合
    let turn = self.start_review_turn(&review_thread_id, target).await?;
    
    Ok(ReviewStartResponse {
        turn,
        review_thread_id,
    })
}
```

### 客户端处理

在 `codex-rs/tui_app_server/src/app_server_session.rs` 中：

```rust
match response {
    ReviewStartResponse { turn, review_thread_id } => {
        // 导航到审查线程
        self.switch_to_thread(&review_thread_id);
        
        // 显示审查回合
        self.display_turn(&turn);
    }
}
```

## 关键代码路径与文件引用

### TypeScript 类型定义
- 文件：`codex-rs/app-server-protocol/schema/typescript/v2/ReviewStartResponse.ts`

### Rust 协议定义
- V2 协议：`codex-rs/app-server-protocol/src/protocol/v2.rs`
- 通用协议：`codex-rs/app-server-protocol/src/protocol/common.rs`

### 服务端实现
- 消息处理：`codex-rs/app-server/src/codex_message_processor.rs`

### 客户端使用
- Exec 模块：`codex-rs/exec/src/lib.rs`
- TUI 应用服务器：`codex-rs/tui_app_server/src/app_server_session.rs`

### 测试覆盖
- 审查测试：`codex-rs/app-server/tests/suite/v2/review.rs`

### 相关类型
- Turn：`codex-rs/app-server-protocol/schema/typescript/v2/Turn.ts`
- ReviewStartParams：`codex-rs/app-server-protocol/schema/typescript/v2/ReviewStartParams.ts`

## 依赖与外部交互

### 上游依赖
- ReviewStartParams：作为 review/start 请求的响应
- 线程管理：需要创建或获取线程信息
- 回合管理：需要启动新的审查回合

### 下游消费
- UI 导航：客户端使用 reviewThreadId 切换视图
- 状态管理：更新客户端的线程和回合状态

### RPC 流程

```
客户端                         服务器
  |                              |
  |---- ReviewStartParams ----->|
  |                              |
  |<--- ReviewStartResponse ----|
  |    { turn, reviewThreadId }  |
```

## 风险、边界与改进建议

### 边界情况
1. **线程创建失败**：detached 模式下新线程创建可能失败
2. **回合启动失败**：审查回合可能因权限或其他原因无法启动
3. **Turn 为空**：某些错误情况下 turn 可能不完整

### 潜在风险
1. **线程泄漏**：创建的审查线程可能无法正确清理
2. **状态不一致**：客户端和服务器状态可能不同步
3. **并发冲突**：多个审查同时启动可能导致冲突

### 改进建议
1. **错误详情**：在失败时提供更详细的错误信息
2. **进度指示**：对于长时间启动的审查提供进度反馈
3. **预览模式**：添加预览选项，不实际启动审查
4. **审查队列**：支持排队多个审查请求
5. **取消支持**：允许客户端取消正在启动的审查
6. **审查链接**：提供可分享的审查链接
