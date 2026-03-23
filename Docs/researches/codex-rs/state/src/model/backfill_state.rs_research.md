# backfill_state.rs 研究文档

## 场景与职责

`backfill_state.rs` 是 Codex 状态管理模块中负责**Rollout 元数据回填状态管理**的数据模型文件。它定义了回填操作的生命周期状态，用于协调多个进程/实例之间对历史 rollout 文件的元数据提取工作。

### 核心职责
1. **回填状态跟踪**：记录 rollout 元数据回填的当前状态（Pending/Running/Complete）
2. **进度持久化**：保存最后处理的水印（watermark）和成功时间
3. **分布式协调**：通过数据库级别的状态检查和租约机制，确保只有一个工作进程执行回填

### 业务背景
当 Codex 升级或首次安装时，需要将历史 rollout 文件（JSONL 格式）中的元数据提取到 SQLite 数据库中。这个过程可能涉及大量文件，需要：
- 可中断/可恢复的执行
- 防止多个进程重复处理
- 记录处理进度以便增量回填

## 功能点目的

### 1. BackfillStatus - 回填状态枚举

```rust
pub enum BackfillStatus {
    Pending,   // 等待执行
    Running,   // 执行中
    Complete,  // 已完成
}
```

- **Pending**：初始状态，表示回填尚未开始或已重置
- **Running**：回填正在进行中
- **Complete**：所有历史 rollout 已处理完毕

### 2. BackfillState - 回填状态结构

```rust
pub struct BackfillState {
    pub status: BackfillStatus,                    // 当前状态
    pub last_watermark: Option<String>,            // 最后处理的 rollout 水印
    pub last_success_at: Option<DateTime<Utc>>,    // 最后成功完成时间
}
```

- **last_watermark**：通常是 rollout 文件的相对路径（如 `sessions/2026/01/27/rollout-a.jsonl`），用于断点续传
- **last_success_at**：记录最后一次成功完成回填的时间，用于监控和调试

### 3. Default 实现

```rust
impl Default for BackfillState {
    fn default() -> Self {
        Self {
            status: BackfillStatus::Pending,
            last_watermark: None,
            last_success_at: None,
        }
    }
}
```

确保新实例或重置后的状态一致。

## 具体技术实现

### 数据库行转换

```rust
impl BackfillState {
    pub(crate) fn try_from_row(row: &SqliteRow) -> Result<Self> {
        let status: String = row.try_get("status")?;
        let last_success_at = row
            .try_get::<Option<i64>, _>("last_success_at")?
            .map(epoch_seconds_to_datetime)
            .transpose()?;
        Ok(Self {
            status: BackfillStatus::parse(status.as_str())?,
            last_watermark: row.try_get("last_watermark")?,
            last_success_at,
        })
    }
}
```

### 状态解析

```rust
impl BackfillStatus {
    pub const fn as_str(self) -> &'static str {
        match self {
            BackfillStatus::Pending => "pending",
            BackfillStatus::Running => "running",
            BackfillStatus::Complete => "complete",
        }
    }

    pub fn parse(value: &str) -> Result<Self> {
        match value {
            "pending" => Ok(Self::Pending),
            "running" => Ok(Self::Running),
            "complete" => Ok(Self::Complete),
            _ => Err(anyhow::anyhow!("invalid backfill status: {value}")),
        }
    }
}
```

使用字符串存储状态，便于数据库查看和调试。

## 关键代码路径与文件引用

### 模型定义位置
- **文件**：`codex-rs/state/src/model/backfill_state.rs`（本文件）
- **导出**：`codex-rs/state/src/model/mod.rs` 通过 `pub use backfill_state::*` 导出

### 数据库操作实现
- **文件**：`codex-rs/state/src/runtime/backfill.rs`
- **核心方法**：
  - `get_backfill_state()` - 获取当前回填状态
  - `try_claim_backfill(lease_seconds)` - 尝试获取回填工作租约
  - `mark_backfill_running()` - 标记回填为运行中
  - `checkpoint_backfill(watermark)` - 保存进度检查点
  - `mark_backfill_complete(last_watermark)` - 标记回填完成

### 数据库 Schema
- **迁移文件**：`codex-rs/state/migrations/0008_backfill_state.sql`

```sql
CREATE TABLE backfill_state (
    id INTEGER PRIMARY KEY CHECK (id = 1),  -- 单例模式，强制 id=1
    status TEXT NOT NULL,
    last_watermark TEXT,
    last_success_at INTEGER,
    updated_at INTEGER NOT NULL
);

-- 初始化默认值
INSERT INTO backfill_state (id, status, last_watermark, last_success_at, updated_at)
VALUES (
    1,
    'pending',
    NULL,
    NULL,
    CAST(strftime('%s', 'now') AS INTEGER)
)
ON CONFLICT(id) DO NOTHING;
```

**设计要点**：
- `CHECK (id = 1)` 确保表中只有一行记录（单例模式）
- `ON CONFLICT DO NOTHING` 防止重复初始化

### 调用方
- **Rollout 元数据模块**：`codex-rs/core/src/rollout/metadata.rs` - 回填协调逻辑
- **状态数据库**：`codex-rs/core/src/state_db.rs` - 状态数据库接口

### 测试
- **单元测试**：`codex-rs/state/src/runtime/backfill.rs` 底部包含测试模块
  - `backfill_state_persists_progress_and_completion` - 测试状态持久化
  - `backfill_claim_is_singleton_until_stale_and_blocked_when_complete` - 测试分布式锁

## 依赖与外部交互

### 外部依赖
| 依赖 | 用途 |
|------|------|
| `anyhow` | 错误处理 |
| `chrono` | 时间戳处理（DateTime<Utc>） |
| `sqlx::Row` | 数据库行访问 |
| `sqlx::sqlite::SqliteRow` | SQLite 特定行类型 |

### 内部模块交互
```
backfill_state.rs (模型定义)
    ↓
mod.rs (统一导出)
    ↓
runtime/backfill.rs (数据库操作实现)
    ↓
lib.rs (公开 API: BackfillState, BackfillStatus)
    ↓
codex-core/rollout/metadata.rs (回填协调)
```

## 风险、边界与改进建议

### 风险点

1. **单点故障**
   - 单例表设计意味着如果回填进程崩溃，状态可能停留在 Running
   - **缓解**：`try_claim_backfill` 实现了租约过期机制（`lease_seconds`）

2. **水印格式不一致**
   - `last_watermark` 是字符串类型，格式由调用方决定
   - **风险**：如果格式变更，可能导致断点续传失效
   - **缓解**：使用路径作为水印，保持格式稳定

3. **并发冲突**
   - 多个进程同时调用 `try_claim_backfill` 时可能产生竞争
   - **缓解**：使用 `BEGIN IMMEDIATE` 事务和原子 UPDATE 语句

### 边界情况

1. **回填重置**
   - 如果需要重新回填，需要手动将状态重置为 Pending
   - 当前没有自动重置机制

2. **部分完成**
   - 回填可能在处理一批文件后中断
   - `checkpoint_backfill` 允许增量保存进度

3. **空历史**
   - 如果没有历史 rollout 文件，回填会立即标记为 Complete

### 改进建议

1. **自动租约续期**
   - 当前租约过期后需要重新竞争
   - 建议：Running 状态的进程可以定期续期租约

2. **失败重试机制**
   - 当前只有 Pending/Running/Complete 三种状态
   - 建议：增加 Failed 状态和自动重试逻辑

3. **进度百分比**
   - 当前只记录 last_watermark，不记录总体进度
   - 建议：如果可能，计算并存储回填百分比

4. **并发回填**
   - 当前设计是单进程回填
   - 建议：考虑分片机制，允许多进程并发处理不同时间段的 rollout

5. **监控指标**
   - 当前只有 `last_success_at` 用于监控
   - 建议：增加回填速度、剩余文件数等指标

### 代码质量

1. **时间戳处理重复**
   - `epoch_seconds_to_datetime` 函数在多个文件中重复定义
   - 建议：提取到公共工具模块

2. **状态字符串硬编码**
   - "pending", "running", "complete" 在多处硬编码
   - 建议：使用常量定义，虽然 `as_str()` 已经提供了统一入口
