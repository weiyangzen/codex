# ReviewDelivery.ts 研究文档

## 场景与职责

`ReviewDelivery.ts` 定义了代码审查交付方式的数据结构，用于指定代码审查应该在何处执行。这是 Codex 代码审查功能的一部分，支持内联审查和分离审查两种模式。

## 功能点目的

该类型用于：
1. **审查位置选择**：允许用户选择在当前线程或新线程中执行审查
2. **工作流灵活性**：支持不同的代码审查工作流需求
3. **上下文隔离**：分离审查可避免污染原始对话上下文
4. **用户体验优化**：根据场景选择最合适的审查展示方式

## 具体技术实现

### 数据结构定义

```typescript
export type ReviewDelivery = "inline" | "detached";
```

### 变体详解

| 值 | 说明 |
|----|------|
| "inline" | 在当前线程中内联执行审查，审查结果直接显示在原对话中 |
| "detached" | 在独立的新线程中执行审查，返回新的审查线程ID |

### Rust 协议定义

在 `codex-rs/protocol/src/protocol.rs` 中：

```rust
#[derive(
    Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Display, JsonSchema, TS,
)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
pub enum ReviewDelivery {
    Inline,   // 内联审查
    Detached, // 分离审查
}
```

在 `codex-rs/app-server-protocol/src/protocol/v2.rs` 中使用宏转换：

```rust
v2_enum_from_core!(
    pub enum ReviewDelivery from codex_protocol::protocol::ReviewDelivery {
        Inline, Detached
    }
);
```

### 使用场景

#### 内联审查 (Inline)

```typescript
const params: ReviewStartParams = {
  threadId: "thread-123",
  target: { type: "uncommittedChanges" },
  delivery: "inline"  // 在当前线程中审查
};
// 审查结果直接显示在 thread-123 中
```

#### 分离审查 (Detached)

```typescript
const params: ReviewStartParams = {
  threadId: "thread-123",
  target: { type: "uncommittedChanges" },
  delivery: "detached"  // 在新线程中审查
};
// 响应包含 reviewThreadId，指向新创建的审查线程
```

### ReviewStartResponse 中的体现

```typescript
export type ReviewStartResponse = { 
  turn: Turn,
  reviewThreadId: string,  // 对于 inline 是原线程ID，对于 detached 是新线程ID
};
```

## 关键代码路径与文件引用

### TypeScript 类型定义
- 文件：`codex-rs/app-server-protocol/schema/typescript/v2/ReviewDelivery.ts`

### Rust 协议定义
- 核心枚举：`codex-rs/protocol/src/protocol.rs`
- V2 API 封装：`codex-rs/app-server-protocol/src/protocol/v2.rs`

### 服务端实现
- 消息处理：`codex-rs/app-server/src/codex_message_processor.rs`

### 客户端使用
- Exec 模块：`codex-rs/exec/src/lib.rs`
- TUI 应用服务器：`codex-rs/tui_app_server/src/app_server_session.rs`

### 测试覆盖
- 审查测试：`codex-rs/app-server/tests/suite/v2/review.rs`

### 相关类型
- ReviewStartParams：`codex-rs/app-server-protocol/schema/typescript/v2/ReviewStartParams.ts`
- ReviewStartResponse：`codex-rs/app-server-protocol/schema/typescript/v2/ReviewStartResponse.ts`

## 依赖与外部交互

### 上游依赖
- 用户选择：通过 UI 或命令行参数指定交付方式
- 默认行为：如果不指定，默认为 "inline"

### 下游消费
- 线程管理：决定审查内容创建在哪个线程
- 响应构造：影响 ReviewStartResponse.reviewThreadId 的值

### 工作流影响

| 交付方式 | 线程创建 | 上下文隔离 | 适用场景 |
|---------|---------|-----------|---------|
| inline | 无 | 低 | 快速审查、小改动 |
| detached | 新线程 | 高 | 深度审查、大改动 |

## 风险、边界与改进建议

### 边界情况
1. **默认行为**：未指定时默认为 inline
2. **线程权限**：detached 模式需要创建新线程的权限
3. **资源消耗**：detached 模式消耗更多资源（新线程）

### 潜在风险
1. **上下文丢失**：detached 模式下原线程上下文可能不完全传递
2. **并发问题**：多个 detached 审查可能同时运行
3. **清理责任**：detached 线程需要明确的清理策略

### 改进建议
1. **智能默认**：根据审查目标大小自动选择交付方式
2. **线程命名**：为 detached 线程生成有意义的名称
3. **状态同步**：inline 和 detached 之间提供更好的状态同步
4. **批量审查**：支持一次启动多个审查（不同交付方式）
5. **审查历史**：跟踪审查历史，支持重新打开已关闭的审查
