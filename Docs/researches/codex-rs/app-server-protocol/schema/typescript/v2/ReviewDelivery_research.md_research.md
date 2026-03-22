# ReviewDelivery 研究文档

## 场景与职责

`ReviewDelivery` 是 Codex App Server Protocol v2 中用于定义代码审查交付模式的枚举类型。它决定了代码审查是在当前线程中内联执行（inline），还是在独立的新线程中分离执行（detached）。

该类型在 `ReviewStartParams` 中使用，允许用户根据审查场景选择不同的执行模式，以平衡审查的独立性和上下文的连续性。

## 功能点目的

1. **执行模式选择**：支持内联和分离两种审查执行模式
2. **上下文控制**：控制审查是否影响当前对话上下文
3. **资源隔离**：分离模式提供独立的审查环境
4. **用户体验优化**：根据场景选择最合适的审查方式

## 具体技术实现

### 数据结构

```rust
// Rust 定义 (codex-rs/app-server-protocol/src/protocol/v2.rs)
// 使用 v2_enum_from_core! 宏定义
v2_enum_from_core!(
    pub enum ReviewDelivery from codex_protocol::protocol::ReviewDelivery {
        Inline, Detached
    }
);
```

```typescript
// TypeScript 生成类型 (schema/typescript/v2/ReviewDelivery.ts)
export type ReviewDelivery = "inline" | "detached";
```

### 宏展开后的实际定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum ReviewDelivery {
    Inline,
    Detached,
}

impl ReviewDelivery {
    pub fn to_core(self) -> codex_protocol::protocol::ReviewDelivery {
        match self {
            ReviewDelivery::Inline => codex_protocol::protocol::ReviewDelivery::Inline,
            ReviewDelivery::Detached => codex_protocol::protocol::ReviewDelivery::Detached,
        }
    }
}

impl From<codex_protocol::protocol::ReviewDelivery> for ReviewDelivery {
    fn from(value: codex_protocol::protocol::ReviewDelivery) -> Self {
        match value {
            codex_protocol::protocol::ReviewDelivery::Inline => ReviewDelivery::Inline,
            codex_protocol::protocol::ReviewDelivery::Detached => ReviewDelivery::Detached,
        }
    }
}
```

### 变体说明

| 变体 | 值 | 说明 |
|------|-----|------|
| `Inline` | `"inline"` | 在当前线程中执行审查，审查结果直接融入当前对话 |
| `Detached` | `"detached"` | 在新线程中执行审查，审查独立进行不影响当前对话 |

### 使用上下文

```rust
// 在 ReviewStartParams 中使用
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ReviewStartParams {
    pub thread_id: String,
    pub target: ReviewTarget,
    /// Where to run the review: inline (default) on the current thread or
    /// detached on a new thread (returned in `reviewThreadId`).
    #[serde(default)]
    #[ts(optional = nullable)]
    pub delivery: Option<ReviewDelivery>,
}
```

## 关键代码路径与文件引用

### 定义位置
- **Rust 定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 327-330，通过宏定义)
- **TypeScript 生成**: `codex-rs/app-server-protocol/schema/typescript/v2/ReviewDelivery.ts`

### 相关类型
- `ReviewStartParams`: 包含 `delivery` 字段
- `ReviewStartResponse`: 响应中包含 `review_thread_id`
- `ReviewTarget`: 审查目标类型

### 使用场景
- `review/start` API 调用时指定交付模式
- 测试用例中验证两种模式的行为差异

## 依赖与外部交互

### 内部依赖
- `codex_protocol::protocol::ReviewDelivery`: 核心协议类型
- `serde`: 序列化/反序列化（使用 `camelCase` 命名）
- `schemars`: JSON Schema 生成
- `ts_rs`: TypeScript 类型生成

### 协议交互

**内联审查请求**:
```json
{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "review/start",
    "params": {
        "threadId": "thread-123",
        "target": {
            "type": "commit",
            "sha": "abc123",
            "title": "Fix bug"
        },
        "delivery": "inline"
    }
}
```

**分离审查请求**:
```json
{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "review/start",
    "params": {
        "threadId": "thread-123",
        "target": {
            "type": "uncommittedChanges"
        },
        "delivery": "detached"
    }
}
```

**分离审查响应**:
```json
{
    "jsonrpc": "2.0",
    "id": 1,
    "result": {
        "turn": { /* ... */ },
        "reviewThreadId": "thread-new-456"
    }
}
```

## 风险、边界与改进建议

### 当前限制
1. **二元选择**：只有两种模式，无法细粒度控制
2. **无默认说明**：虽然代码中 `Inline` 是默认行为，但文档说明不够明确
3. **无状态共享**：分离模式下，原线程的上下文无法自动共享给新线程

### 边界情况
1. **默认行为**：`delivery` 为 `null` 时，默认为 `Inline`
2. **线程生命周期**：分离审查线程的生命周期管理
3. **资源限制**：大量分离审查可能消耗过多资源

### 测试覆盖

从 `review.rs` 测试文件可以看到两种模式的测试：

```rust
// 内联审查测试
let review_req = mcp
    .send_review_start_request(ReviewStartParams {
        thread_id: thread_id.clone(),
        delivery: Some(ReviewDelivery::Inline),
        target: ReviewTarget::Commit { /* ... */ },
    })
    .await?;

// 分离审查测试
let review_req = mcp
    .send_review_start_request(ReviewStartParams {
        thread_id: thread_id.clone(),
        delivery: Some(ReviewDelivery::Detached),
        target: ReviewTarget::Custom { /* ... */ },
    })
    .await?;
```

### 改进建议

1. **添加更多模式**：
   ```rust
   pub enum ReviewDelivery {
       Inline,
       Detached,
       Background,  // 后台执行，不阻塞当前线程
       Interactive, // 交互式审查，需要用户实时参与
   }
   ```

2. **添加上下文共享选项**：
   ```rust
   pub struct ReviewStartParams {
       // ...
       pub delivery: Option<ReviewDelivery>,
       pub share_context: Option<bool>,  // 是否共享原线程上下文
   }
   ```

3. **添加审查后行为**：
   ```rust
   pub enum ReviewDelivery {
       Inline,
       Detached,
       DetachedWithMerge,  // 分离审查后合并结果
   }
   ```

### 兼容性注意
- 使用 `camelCase` 命名确保与 TypeScript 惯例一致
- `Option<ReviewDelivery>` 配合 `#[serde(default)]` 确保向后兼容
- 测试用例覆盖两种模式的差异

### 使用建议

| 场景 | 推荐模式 | 原因 |
|------|----------|------|
| 快速代码检查 | `Inline` | 保持上下文连续，快速反馈 |
| 深度代码审查 | `Detached` | 独立环境，不影响当前工作 |
| 多文件审查 | `Detached` | 避免污染当前线程历史 |
| 审查后讨论 | `Inline` | 审查结果直接融入对话 |
