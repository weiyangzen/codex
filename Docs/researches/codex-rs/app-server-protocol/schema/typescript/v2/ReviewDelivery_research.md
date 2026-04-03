# ReviewDelivery 研究文档

## 场景与职责

`ReviewDelivery` 是 Codex app-server-protocol v2 协议中的代码审查交付模式类型，用于指定代码审查结果的呈现方式。该类型定义了审查结果是在当前对话线程中内联显示，还是在独立的新线程中分离显示。

在 Codex 的代码审查功能中，`ReviewDelivery` 承担以下职责：
1. **审查模式选择**：允许用户选择审查结果的展示方式
2. **线程管理**：控制审查执行的线程位置
3. **用户体验**：提供灵活的审查交互模式
4. **上下文隔离**：支持将审查与原始对话分离

## 功能点目的

### 核心功能
- **Inline 模式**：在当前线程内联显示审查结果
- **Detached 模式**：在独立的新线程中显示审查结果
- **默认行为**：默认为 `Inline` 模式
- **与核心协议映射**：与 `CoreReviewDelivery` 双向转换

### 设计意图
- **灵活性**：满足不同场景下的审查需求
- **向后兼容**：默认为内联模式，保持现有行为
- **清晰语义**：两种模式语义明确，易于理解

## 具体技术实现

### 数据结构定义

**TypeScript 定义**（`ReviewDelivery.ts`）：
```typescript
export type ReviewDelivery = "inline" | "detached";
```

**Rust 定义**（`v2.rs` 行 328）：
```rust
v2_enum_from_core!(
    pub enum ReviewDelivery from codex_protocol::protocol::ReviewDelivery {
        Inline, Detached
    }
);
```

展开后的定义：
```rust
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum ReviewDelivery {
    Inline,
    Detached,
}
```

### 关键值说明

| 值 | 说明 | 使用场景 |
|----|------|----------|
| `"inline"` | 在当前线程内联显示 | 快速审查、与当前对话紧密相关 |
| `"detached"` | 在独立新线程显示 | 详细审查、需要隔离上下文 |

### 与核心类型的映射

使用 `v2_enum_from_core!` 宏自动生成转换：

```rust
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

### 在 ReviewStartParams 中的使用

```rust
pub struct ReviewStartParams {
    pub thread_id: String,
    pub target: ReviewTarget,
    #[serde(default)]
    #[ts(optional = nullable)]
    pub delivery: Option<ReviewDelivery>,
}
```

### 处理逻辑

在 `codex_message_processor.rs` 行 6510-6530：
```rust
let delivery = delivery.unwrap_or(ApiReviewDelivery::Inline).to_core();
match delivery {
    CoreReviewDelivery::Inline => {
        // 在当前线程执行审查
        // review_thread_id = params.thread_id
    }
    CoreReviewDelivery::Detached => {
        // 创建新线程执行审查
        // review_thread_id = create_new_thread().id
    }
}
```

## 关键代码路径与文件引用

### 定义位置
- **Rust 定义**：`codex-rs/app-server-protocol/src/protocol/v2.rs` 行 328
- **TypeScript 生成**：`codex-rs/app-server-protocol/schema/typescript/v2/ReviewDelivery.ts`
- **JSON Schema**：`codex-rs/app-server-protocol/schema/json/v2/ReviewStartParams.json`

### 使用位置
- **ReviewStartParams**：`v2.rs` 行 3892 - 审查启动参数
- **消息处理器**：`codex_message_processor.rs` 行 98, 6510 - 处理审查请求
- **测试用例**：`tests/suite/v2/review.rs` - 测试不同交付模式

### 相关类型
- `ReviewStartParams`：包含 `delivery` 字段（行 3884-3893）
- `ReviewStartResponse`：返回 `review_thread_id`（行 3898-3905）
- `CoreReviewDelivery`：核心协议中的对应类型（`protocol/src/protocol.rs` 行 2521-2524）
- `ReviewTarget`：审查目标类型

### 响应差异

| 交付模式 | `reviewThreadId` 值 | 说明 |
|----------|---------------------|------|
| `Inline` | 原始线程 ID | 审查在当前线程执行 |
| `Detached` | 新创建的线程 ID | 审查在新线程执行 |

## 依赖与外部交互

### 依赖项
- `serde`：序列化/反序列化支持
- `schemars`：JSON Schema 生成
- `ts-rs`：TypeScript 类型生成

### 上游依赖
- `CoreReviewDelivery`（核心协议）：`protocol/src/protocol.rs`

### 下游使用
- `ReviewStartParams`：审查启动参数
- `tui_app_server`：TUI 应用服务器（`app_server_session.rs` 行 565）

### 协议集成
- 通过 `review/start` RPC 方法的 `delivery` 参数指定
- 影响 `ReviewStartResponse` 中的 `reviewThreadId` 值

## 风险、边界与改进建议

### 潜在风险
1. **线程泄漏**：`Detached` 模式可能创建大量线程
2. **上下文丢失**：`Detached` 模式下审查结果与原始对话隔离
3. **资源竞争**：多个审查同时执行时的资源竞争

### 边界情况
1. **无效线程**：指定的 `threadId` 不存在时的处理
2. **并发审查**：同一线程上同时发起多个审查
3. **模式切换**：审查执行过程中切换交付模式（不支持）

### 改进建议
1. **扩展交付模式**：
   ```rust
   pub enum ReviewDelivery {
       Inline,           // 当前线程内联
       Detached,         // 独立新线程
       Background,       // 后台执行，完成后通知
       Interactive,      // 交互式审查，需要用户输入
   }
   ```

2. **添加配置选项**：
   ```rust
   pub struct ReviewDeliveryConfig {
       /// 交付模式
       pub mode: ReviewDelivery,
       /// 是否自动归档 detached 线程
       pub auto_archive: Option<bool>,
       /// 审查超时时间（秒）
       pub timeout_seconds: Option<u32>,
   }
   ```

3. **线程管理**：
   - 限制 `Detached` 模式创建的线程数量
   - 实现线程池复用
   - 添加线程自动清理机制

4. **用户体验**：
   - 在 UI 中明确显示当前交付模式
   - 提供模式切换的快捷操作
   - 显示审查进度和状态

5. **可观测性**：
   - 记录审查交付模式的使用统计
   - 监控不同模式的性能指标
   - 提供审查历史追踪

6. **企业功能**：
   - 支持按项目设置默认交付模式
   - 实现审查审批工作流
   - 提供审查报告导出
