# ReviewDelivery 研究文档

## 1. 场景与职责

`ReviewDelivery` 是 Codex app-server-protocol v2 协议中的代码审查交付模式类型，用于指定代码审查结果的呈现方式。该类型定义了审查结果是在当前对话线程中内联显示，还是在独立的新线程中分离显示。

### 使用场景
- **代码审查工作流**：用户请求 AI 审查代码变更时选择结果展示方式
- **并行审查**：多个审查任务需要独立线程避免干扰
- **历史追溯**：分离模式便于后续查找特定审查记录

## 2. 功能点目的

该类型的核心目的是：
1. **灵活的审查体验**：根据用户需求选择最合适的审查结果展示方式
2. **上下文管理**：内联模式保持对话连贯性，分离模式保持审查独立性
3. **工作流支持**：支持不同的代码审查工作流模式

### 交付模式对比
| 模式 | 特点 | 适用场景 |
|------|------|----------|
| `inline` | 在当前线程显示审查结果 | 快速审查、保持对话上下文 |
| `detached` | 在新线程显示审查结果 | 深度审查、需要独立记录 |

## 3. 具体技术实现

### TypeScript 类型定义
```typescript
export type ReviewDelivery = "inline" | "detached";
```

### Rust 源实现
```rust
v2_enum_from_core!(
    pub enum ReviewDelivery from codex_protocol::protocol::ReviewDelivery {
        Inline, Detached
    }
);
```

### 核心协议定义
```rust
// codex-rs/protocol/src/protocol.rs (行 2521)
pub enum ReviewDelivery {
    Inline,
    Detached,
}
```

### 字段说明
| 值 | 说明 |
|----|------|
| `"inline"` | 在当前线程内联显示审查结果（默认） |
| `"detached"` | 在新线程中分离显示审查结果 |

## 4. 关键代码路径与文件引用

### 协议定义
- **Rust 源文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 327-331)
- **核心协议**: `codex-rs/protocol/src/protocol.rs` (行 2521)
- **TypeScript 文件**: `codex-rs/app-server-protocol/schema/typescript/v2/ReviewDelivery.ts`

### 使用位置

#### 审查启动参数
- **文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 3884-3893)
  ```rust
  pub struct ReviewStartParams {
      pub thread_id: String,
      pub target: ReviewTarget,
      #[serde(default)]
      #[ts(optional = nullable)]
      pub delivery: Option<ReviewDelivery>,
  }
  ```

#### 消息处理器
- **文件**: `codex-rs/app-server/src/codex_message_processor.rs`
  - 行 98: 导入 `ReviewDelivery`
  - 行 265: 导入核心协议的 `ReviewDelivery`
  - 行 6510-6530: 根据 `delivery` 值处理内联或分离模式

#### TUI 应用
- **文件**: `codex-rs/tui_app_server/src/app_server_session.rs` (行 565)
  - 默认使用 `ReviewDelivery::Inline`

### 测试覆盖
- **文件**: `codex-rs/app-server/tests/suite/v2/review.rs`
  - 行 15: 导入 `ReviewDelivery`
  - 行 69, 171, 241, 286, 349, 384: 测试用例中使用不同交付模式

### JSON Schema
- `codex-rs/app-server-protocol/schema/json/ClientRequest.json`
- `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json`
- `codex-rs/app-server-protocol/schema/json/v2/ReviewStartParams.json`

## 5. 依赖与外部交互

### 导入依赖
- 无直接导入的类型

### 被依赖类型
- `ReviewStartParams` - 包含 `delivery` 字段
- `ReviewStartResponse` - 响应中包含 `reviewThreadId`

### 核心协议映射
- `CoreReviewDelivery::Inline` ↔ `ReviewDelivery::Inline`
- `CoreReviewDelivery::Detached` ↔ `ReviewDelivery::Detached`

## 6. 风险、边界与改进建议

### 潜在风险
1. **默认行为歧义**：`null` 值默认使用 `inline`，需要在文档中明确
2. **线程管理**：分离模式需要额外的线程生命周期管理
3. **用户体验**：用户可能不清楚两种模式的区别

### 边界情况
- **未指定**：`delivery: null` 默认为 `inline`
- **无效值**：序列化时会验证，无效值会导致请求失败
- **线程冲突**：分离模式下需要确保新线程正确创建

### 实现细节
```rust
// 在 codex_message_processor.rs 中的处理逻辑
let delivery = delivery.unwrap_or(ApiReviewDelivery::Inline).to_core();
match delivery {
    CoreReviewDelivery::Inline => {
        // 在当前线程处理审查
    }
    CoreReviewDelivery::Detached => {
        // 创建新线程处理审查
        // 返回 review_thread_id
    }
}
```

### 改进建议
1. **UI 提示**：在客户端界面中解释两种模式的区别
2. **记忆偏好**：记住用户上次选择的交付模式
3. **智能推荐**：根据审查目标大小/复杂度推荐合适的模式
4. **批量审查**：支持一次请求多个审查，分别指定交付模式

### 相关类型关系
```
ReviewStartParams
├── threadId: string
├── target: ReviewTarget
└── delivery?: ReviewDelivery | null  <-- 本类型

ReviewStartResponse
├── turn: Turn
└── reviewThreadId: string  <-- 分离模式下指向新线程
```

### 测试建议
- 测试两种模式的完整流程
- 验证线程创建和清理
- 测试边界情况（如线程已满、权限不足等）
