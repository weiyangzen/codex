# 0020_threads_model_reasoning_effort.sql 研究文档

## 场景与职责

本迁移为 `threads` 表添加 `model` 和 `reasoning_effort` 字段，用于记录会话使用的具体模型和推理努力程度。这支持更精细的会话分析和模型使用追踪。

## 功能点目的

### 1. 添加 model 字段
- **字段**: `model TEXT`
- **约束**: 可为空（NULL）
- **用途**: 记录使用的具体模型（如 "gpt-5", "o3" 等）

### 2. 添加 reasoning_effort 字段
- **字段**: `reasoning_effort TEXT`
- **约束**: 可为空（NULL）
- **用途**: 记录推理努力程度（"low", "medium", "high"）

### 使用场景
- **模型追踪**: 了解不同模型的使用情况
- **成本分析**: 基于模型和推理努力估算成本
- **性能分析**: 分析不同配置的效果
- **会话恢复**: 恢复会话时使用相同的模型配置

## 具体技术实现

### 关键流程

#### 从 TurnContext 提取
```rust
fn apply_turn_context(metadata: &mut ThreadMetadata, turn_ctx: &TurnContextItem) {
    metadata.model = Some(turn_ctx.model.clone());
    metadata.reasoning_effort = turn_ctx.effort;
    metadata.sandbox_policy = enum_to_string(&turn_ctx.sandbox_policy);
    metadata.approval_mode = enum_to_string(&turn_ctx.approval_policy);
}
```

#### 数据转换
```rust
pub struct ThreadRow {
    // ...
    model: Option<String>,
    reasoning_effort: Option<String>,
    // ...
}

impl TryFrom<ThreadRow> for ThreadMetadata {
    type Error = anyhow::Error;

    fn try_from(row: ThreadRow) -> std::result::Result<Self, Self::Error> {
        Ok(Self {
            // ...
            model,
            reasoning_effort: reasoning_effort
                .and_then(|value| value.parse::<ReasoningEffort>().ok()),
            // ...
        })
    }
}
```

#### 数据写入
```rust
pub async fn upsert_thread(&self, metadata: &crate::ThreadMetadata) -> anyhow::Result<()> {
    sqlx::query(
        r#"
INSERT INTO threads (
    // ...
    model,
    reasoning_effort,
    // ...
) VALUES (..., ?, ?, ...)
ON CONFLICT(id) DO UPDATE SET
    // ...
    model = excluded.model,
    reasoning_effort = excluded.reasoning_effort,
    // ...
        "#,
    )
    .bind(metadata.model.as_deref())
    .bind(
        metadata
            .reasoning_effort
            .as_ref()
            .map(crate::extract::enum_to_string),
    )
    // ...
}
```

### 代码映射
在 `codex-rs/state/src/model/thread_metadata.rs` 中：
```rust
pub struct ThreadMetadata {
    // ...
    /// The latest observed model for the thread.
    pub model: Option<String>,
    /// The latest observed reasoning effort for the thread.
    pub reasoning_effort: Option<ReasoningEffort>,
    // ...
}
```

在 `codex-protocol/src/openai_models.rs` 中：
```rust
pub enum ReasoningEffort {
    Low,
    Medium,
    High,
}
```

## 关键代码路径与文件引用

### 数据提取
- `codex-rs/state/src/extract.rs`:
  - `apply_turn_context()`: 从 TurnContext 提取模型和推理努力

### 模型定义
- `codex-rs/state/src/model/thread_metadata.rs`:
  - `ThreadMetadata`: 包含模型和推理努力字段
  - `ThreadRow`: 数据库行映射

### 数据写入
- `codex-rs/state/src/runtime/threads.rs`:
  - `upsert_thread()`: 写入模型和推理努力

### 协议定义
- `codex-protocol/src/protocol.rs`:
  - `TurnContextItem`: 包含 `model` 和 `effort` 字段
- `codex-protocol/src/openai_models.rs`:
  - `ReasoningEffort`: 推理努力枚举

## 依赖与外部交互

### 上游依赖
- `0001_threads.sql`: 基础 threads 表结构

### 下游依赖
- 无直接下游依赖

### 应用层交互
- 模型选择 UI 显示当前会话的模型
- 分析工具基于这些字段生成报告

## 风险、边界与改进建议

### 风险
1. **模型名称变化**: 模型名称可能随 API 变化
2. **枚举值扩展**: 新的推理努力级别需要代码更新

### 边界情况
1. **模型切换**: 会话中可能切换模型，只记录最新值
2. **不支持推理**: 某些模型不支持 reasoning_effort
3. **NULL 值**: 旧数据或某些场景下可能为 NULL

### 改进建议
1. 考虑添加模型版本字段（如果模型有版本）
2. 可为模型使用添加统计和监控
3. 考虑添加模型切换历史
4. 添加模型兼容性检查

## 测试覆盖
在 `codex-rs/state/src/model/thread_metadata.rs` 中有相关测试：
```rust
#[test]
fn thread_row_parses_reasoning_effort() {
    let metadata = ThreadMetadata::try_from(thread_row(Some("high")))
        .expect("thread metadata should parse");
    assert_eq!(
        metadata,
        expected_thread_metadata(Some(ReasoningEffort::High))
    );
}

#[test]
fn thread_row_ignores_unknown_reasoning_effort_values() {
    let metadata = ThreadMetadata::try_from(thread_row(Some("future")))
        .expect("thread metadata should parse");
    assert_eq!(metadata, expected_thread_metadata(None));
}
```
