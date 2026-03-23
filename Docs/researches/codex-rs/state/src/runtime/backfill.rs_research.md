# Backfill Runtime 研究文档

## 文件信息
- **源文件**: `codex-rs/state/src/runtime/backfill.rs`
- **文件大小**: 10,032 bytes (311 行)
- **所属模块**: `codex-state` crate 的 runtime 子模块

---

## 一、场景与职责

### 1.1 核心定位
`backfill.rs` 实现了 Codex 状态管理系统的**历史数据回填机制**。它负责将磁盘上的历史 rollout 文件（JSONL 格式）扫描并提取元数据，同步到 SQLite 状态数据库中。这是 Codex 从文件系统向数据库架构迁移的关键组件。

### 1.2 主要使用场景
1. **首次启动回填**: 新安装或升级后，将现有 rollout 文件导入数据库
2. **增量同步**: 定期扫描新产生的 rollout 文件并同步
3. **多进程协调**: 确保只有一个进程执行回填（分布式锁机制）
4. **故障恢复**: 从中断点恢复回填，避免重复处理

### 1.3 架构位置
```
┌─────────────────────────────────────────────────────────────────────┐
│                         codex-core                                  │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │ rollout/metadata.rs                                           │  │
│  │ - backfill_sessions() 主入口                                  │  │
│  │ - extract_metadata_from_rollout() 元数据提取                   │  │
│  │ - collect_rollout_paths() 文件收集                            │  │
│  └───────────────────────┬───────────────────────────────────────┘  │
│                          │ 调用 StateRuntime API                     │
│                          ▼                                          │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │ codex-state                                                   │  │
│  │ ┌───────────────────────────────────────────────────────────┐ │  │
│  │ │ runtime/backfill.rs ◄── 本文件                             │ │  │
│  │ │ - 回填状态管理 (get_backfill_state)                        │ │  │
│  │ │ - 分布式锁 (try_claim_backfill)                            │ │  │
│  │ │ - 进度检查点 (checkpoint_backfill)                         │ │  │
│  │ └───────────────────────────────────────────────────────────┘ │  │
│  │ ┌───────────────────────────────────────────────────────────┐ │  │
│  │ │ model/backfill_state.rs                                    │ │  │
│  │ │ - BackfillState, BackfillStatus 数据结构                   │ │  │
│  │ └───────────────────────────────────────────────────────────┘ │  │
│  └───────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 二、功能点目的

### 2.1 功能概览

| 功能类别 | 方法名 | 目的 |
|---------|--------|------|
| **状态查询** | `get_backfill_state` | 获取当前回填状态 |
| **锁管理** | `try_claim_backfill` | 尝试获取回填执行权（分布式锁）|
| **状态流转** | `mark_backfill_running` | 标记回填为运行中 |
| | `mark_backfill_complete` | 标记回填为完成 |
| **进度管理** | `checkpoint_backfill` | 保存处理进度（水印）|
| **初始化** | `ensure_backfill_state_row` | 确保状态记录存在 |

### 2.2 回填状态机

```
                    ┌─────────────┐
         ┌─────────│   Pending   │
         │         └──────┬──────┘
         │                │ try_claim_backfill() 成功
         │                ▼
         │         ┌─────────────┐
         │    ┌───│   Running   │◄────┐
         │    │    └──────┬──────┘     │
         │    │           │            │
         │    │           │ checkpoint_backfill()
         │    │           ▼            │
         │    │    ┌─────────────┐     │
         │    │    │  Checkpoint │─────┘ (循环)
         │    │    └─────────────┘
         │    │           │
         │    │           │ mark_backfill_complete()
         │    │           ▼
         │    │    ┌─────────────┐
         │    └───►│  Complete   │
         │         └─────────────┘
         │
         └──────────────┘ (lease 过期后重新竞争)
```

### 2.3 分布式锁机制

```
┌─────────────┐         ┌─────────────┐         ┌─────────────┐
│  Process A  │         │  Process B  │         │  Process C  │
└──────┬──────┘         └──────┬──────┘         └──────┬──────┘
       │                       │                       │
       │ try_claim_backfill()  │                       │
       │ ─────────────────────►│                       │
       │ ◄── rows_affected=1   │                       │
       │ (获得锁)               │                       │
       │                       │ try_claim_backfill()  │
       │                       │ ─────────────────────►│
       │                       │ ◄── rows_affected=0   │
       │                       │ (未获得锁)             │
       │                       │                       │
       │ 定期更新 updated_at   │                       │
       │ (维持锁)               │                       │
       │                       │                       │
       │ mark_backfill_complete()                    │
       │ (释放锁)               │                       │
```

---

## 三、具体技术实现

### 3.1 数据库 Schema

#### backfill_state 表
```sql
CREATE TABLE backfill_state (
    id INTEGER PRIMARY KEY CHECK (id = 1),  -- 单例模式，强制 id=1
    status TEXT NOT NULL,                    -- pending/running/complete
    last_watermark TEXT,                     -- 最后处理的文件路径水印
    last_success_at INTEGER,                 -- 上次成功完成时间
    updated_at INTEGER NOT NULL              -- 最后更新时间（用于锁超时）
);

-- 初始化数据
INSERT INTO backfill_state (id, status, last_watermark, last_success_at, updated_at)
VALUES (1, 'pending', NULL, NULL, CAST(strftime('%s', 'now') AS INTEGER))
ON CONFLICT(id) DO NOTHING;
```

### 3.2 核心算法

#### 3.2.1 分布式锁实现（Lease 机制）

```rust
pub async fn try_claim_backfill(&self, lease_seconds: i64) -> anyhow::Result<bool> {
    self.ensure_backfill_state_row().await?;
    let now = Utc::now().timestamp();
    // 计算锁过期时间点
    let lease_cutoff = now.saturating_sub(lease_seconds.max(0));
    
    let result = sqlx::query(
        r#"
UPDATE backfill_state
SET status = ?, updated_at = ?
WHERE id = 1
  AND status != ?           -- 不能是已完成状态
  AND (status != ?          -- 或者是非运行状态
       OR updated_at <= ?)  -- 或者是运行但锁已过期
        "#,
    )
    .bind(BackfillStatus::Running.as_str())
    .bind(now)
    .bind(BackfillStatus::Complete.as_str())
    .bind(BackfillStatus::Running.as_str())
    .bind(lease_cutoff)
    .execute(self.pool.as_ref())
    .await?;
    
    Ok(result.rows_affected() == 1)
}
```

**锁竞争条件分析：**
- ✅ 状态为 `Pending` → 可以获得锁
- ✅ 状态为 `Running` 但 `updated_at` 已过期 → 可以获得锁（故障转移）
- ❌ 状态为 `Running` 且 `updated_at` 未过期 → 不能获得锁
- ❌ 状态为 `Complete` → 不能获得锁（幂等保护）

#### 3.2.2 进度检查点

```rust
pub async fn checkpoint_backfill(&self, watermark: &str) -> anyhow::Result<()> {
    self.ensure_backfill_state_row().await?;
    sqlx::query(
        r#"
UPDATE backfill_state
SET status = ?, last_watermark = ?, updated_at = ?
WHERE id = 1
        "#,
    )
    .bind(BackfillStatus::Running.as_str())
    .bind(watermark)
    .bind(Utc::now().timestamp())
    .execute(self.pool.as_ref())
    .await?;
    Ok(())
}
```

**水印设计：**
- 使用文件路径作为水印（如 `sessions/2026/01/27/rollout-a.jsonl`）
- 按字典序排序和比较
- 支持增量回填（从上次水印继续）

### 3.3 关键数据结构

#### BackfillState
```rust
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BackfillState {
    pub status: BackfillStatus,              // Pending/Running/Complete
    pub last_watermark: Option<String>,      // 进度水印
    pub last_success_at: Option<DateTime<Utc>>, // 上次成功时间
}
```

#### BackfillStatus
```rust
pub enum BackfillStatus {
    Pending,   // 待处理
    Running,   // 运行中
    Complete,  // 已完成
}
```

---

## 四、关键代码路径与文件引用

### 4.1 内部依赖

| 文件路径 | 用途 |
|---------|------|
| `model/backfill_state.rs` | BackfillState, BackfillStatus 定义 |
| `model/mod.rs` | 模块导出 |
| `migrations/0008_backfill_state.sql` | 表结构和初始数据 |

### 4.2 外部调用方

| 文件路径 | 调用方式 | 用途 |
|---------|---------|------|
| `core/src/rollout/metadata.rs` | `runtime.get_backfill_state()` | 查询回填状态 |
| | `runtime.try_claim_backfill()` | 获取执行锁 |
| | `runtime.checkpoint_backfill()` | 保存进度 |
| | `runtime.mark_backfill_complete()` | 标记完成 |

### 4.3 关键代码片段

#### 4.3.1 分布式锁实现（行 23-44）
```rust
pub async fn try_claim_backfill(&self, lease_seconds: i64) -> anyhow::Result<bool> {
    self.ensure_backfill_state_row().await?;
    let now = Utc::now().timestamp();
    let lease_cutoff = now.saturating_sub(lease_seconds.max(0));
    let result = sqlx::query(
        r#"
UPDATE backfill_state
SET status = ?, updated_at = ?
WHERE id = 1
  AND status != ?
  AND (status != ? OR updated_at <= ?)
        "#,
    )
    .bind(crate::BackfillStatus::Running.as_str())
    .bind(now)
    .bind(crate::BackfillStatus::Complete.as_str())
    .bind(crate::BackfillStatus::Running.as_str())
    .bind(lease_cutoff)
    .execute(self.pool.as_ref())
    .await?;
    Ok(result.rows_affected() == 1)
}
```

#### 4.3.2 确保状态记录存在（行 105-119）
```rust
async fn ensure_backfill_state_row(&self) -> anyhow::Result<()> {
    sqlx::query(
        r#"
INSERT INTO backfill_state (id, status, last_watermark, last_success_at, updated_at)
VALUES (?, ?, NULL, NULL, ?)
ON CONFLICT(id) DO NOTHING
        "#,
    )
    .bind(1_i64)
    .bind(crate::BackfillStatus::Pending.as_str())
    .bind(Utc::now().timestamp())
    .execute(self.pool.as_ref())
    .await?;
    Ok(())
}
```

#### 4.3.3 完成回填（行 82-103）
```rust
pub async fn mark_backfill_complete(
    &self,
    last_watermark: Option<&str>,
) -> anyhow::Result<()> {
    self.ensure_backfill_state_row().await?;
    let now = Utc::now().timestamp();
    sqlx::query(
        r#"
UPDATE backfill_state
SET
    status = ?,
    last_watermark = COALESCE(?, last_watermark),
    last_success_at = ?,
    updated_at = ?
WHERE id = 1
        "#,
    )
    .bind(crate::BackfillStatus::Complete.as_str())
    .bind(last_watermark)
    .bind(now)
    .bind(now)
    .execute(self.pool.as_ref())
    .await?;
    Ok(())
}
```

---

## 五、依赖与外部交互

### 5.1 直接依赖

| 依赖 | 用途 |
|-----|------|
| `sqlx` | SQLite 异步操作 |
| `chrono` | 时间戳处理 |
| `anyhow` | 错误处理 |

### 5.2 数据库交互

```
┌─────────────────────────────────────────────────────────────┐
│              SQLite DB (state.db)                           │
│  ┌───────────────────────────────────────────────────────┐  │
│  │              backfill_state                           │  │
│  ├───────────────────────────────────────────────────────┤  │
│  │ id: INTEGER PK CHECK(id = 1)  ← 单例设计              │  │
│  │ status: TEXT (pending/running/complete)               │  │
│  │ last_watermark: TEXT                                  │  │
│  │ last_success_at: INTEGER (unix timestamp)             │  │
│  │ updated_at: INTEGER (unix timestamp)                  │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### 5.3 与 core 模块的交互流程

```
core/src/rollout/metadata.rs
    │
    ├──► get_backfill_state()
    │    └── 检查是否需要回填
    │
    ├──► try_claim_backfill(BACKFILL_LEASE_SECONDS)
    │    └── 竞争执行权
    │        ├── 生产环境: 900 秒 (15 分钟)
    │        └── 测试环境: 1 秒
    │
    ├──► collect_rollout_paths()
    │    └── 扫描 sessions/ 和 archived_sessions/
    │
    ├──► extract_metadata_from_rollout()
    │    └── 解析 rollout JSONL 文件
    │
    ├──► runtime.upsert_thread()
    │    └── 写入线程元数据
    │
    ├──► checkpoint_backfill(watermark)
    │    └── 每 BATCH_SIZE (200) 个文件保存进度
    │
    └──► mark_backfill_complete()
         └── 标记完成，释放锁
```

---

## 六、风险、边界与改进建议

### 6.1 已知风险

| 风险类别 | 描述 | 严重程度 |
|---------|------|---------|
| **锁过期** | 如果回填进程在 lease 期间卡住，其他进程可能抢占锁导致重复处理 | 中 |
| **时钟漂移** | 依赖系统时钟判断锁过期，时钟回拨可能导致误判 | 低 |
| **单点故障** | 单例设计 (id=1) 意味着只有一个回填任务可以执行 | 低（设计如此）|
| **水印冲突** | 如果文件路径命名不规范，可能导致水印比较错误 | 低 |

### 6.2 边界条件

1. **Lease 时长**: 
   - 生产环境: 900 秒（15 分钟）
   - 测试环境: 1 秒（便于测试）

2. **批次大小**: 
   - `BACKFILL_BATCH_SIZE = 200` 个文件
   - 每批次保存一次检查点

3. **状态转换约束**:
   - `Pending` → `Running`: 通过 `try_claim_backfill`
   - `Running` → `Complete`: 通过 `mark_backfill_complete`
   - `Complete` → 任何状态: ❌ 不允许（幂等保护）

### 6.3 改进建议

#### 6.3.1 短期改进

1. **添加心跳机制**
   ```rust
   // 建议：在长时间回填时定期更新 updated_at
   pub async fn heartbeat_backfill(&self) -> anyhow::Result<bool> {
       let result = sqlx::query(
           "UPDATE backfill_state SET updated_at = ? 
            WHERE id = 1 AND status = ?"
       )
       .bind(Utc::now().timestamp())
       .bind(BackfillStatus::Running.as_str())
       .execute(self.pool.as_ref()).await?;
       Ok(result.rows_affected() > 0)
   }
   ```

2. **支持强制重置**
   ```rust
   // 建议：允许管理员强制重置回填状态
   pub async fn force_reset_backfill(&self) -> anyhow::Result<()> {
       sqlx::query(
           "UPDATE backfill_state 
            SET status = 'pending', last_watermark = NULL 
            WHERE id = 1"
       )
       .execute(self.pool.as_ref()).await?;
       Ok(())
   }
   ```

3. **添加回填统计**
   ```rust
   // 建议：记录处理的文件数量
   pub struct BackfillStats {
       pub files_scanned: u64,
       pub files_upserted: u64,
       pub files_failed: u64,
   }
   ```

#### 6.3.2 长期改进

1. **支持并发回填**: 按时间范围分区，多个进程并发处理不同时间段
2. **断点续传优化**: 记录更细粒度的进度（如最后处理的文件偏移）
3. **回填历史记录**: 添加 backfill_history 表记录每次回填的详情
4. **自动触发机制**: 支持定时自动触发回填（如每天凌晨）

### 6.4 测试覆盖

当前测试（行 122-311）覆盖：
- ✅ 旧版本数据库文件清理
- ✅ 状态持久化和进度保存
- ✅ 锁竞争和过期处理

建议补充：
- ⬜ 时钟回拨场景测试
- ⬜ 高并发锁竞争测试
- ⬜ 大规模文件回填性能测试
- ⬜ 数据库连接断开恢复测试

---

## 七、附录

### 7.1 相关常量

```rust
// core/src/rollout/metadata.rs
const BACKFILL_BATCH_SIZE: usize = 200;
const BACKFILL_LEASE_SECONDS: i64 = 900;  // 生产环境
const BACKFILL_LEASE_SECONDS: i64 = 1;    // 测试环境 (cfg(test))
```

### 7.2 监控指标

| 指标名 | 类型 | 标签 | 说明 |
|-------|------|------|------|
| `codex.db.backfill` | Counter | status=upserted/failed | 回填统计 |
| `codex.db.backfill.duration_ms` | Timer | status=success/partial_failure/failed | 回填耗时 |
| `codex.db.error` | Counter | stage=backfill_sessions | 错误统计 |

### 7.3 版本历史

| 版本 | 文件 | 变更 |
|-----|------|------|
| 0008 | `migrations/0008_backfill_state.sql` | 初始表结构 |

### 7.4 调用时序图

```
Process A (获得锁)                    Process B (未获得锁)
    │                                      │
    ▼                                      ▼
┌─────────────┐                    ┌─────────────┐
│ get_backfill│                    │ get_backfill│
│ _state()    │                    │ _state()    │
└──────┬──────┘                    └──────┬──────┘
       │ status=Pending                   │ status=Running
       ▼                                  ▼
┌─────────────┐                    ┌─────────────┐
│ try_claim_  │                    │ try_claim_  │
│ backfill()  │                    │ backfill()  │
│ ──► rows=1  │                    │ ──► rows=0  │
└──────┬──────┘                    └──────┬──────┘
       │                                  │
       ▼                                  ▼
┌─────────────┐                    ┌─────────────┐
│ 执行回填    │                    │ 跳过回填    │
│ ...         │                    │ (已有其他   │
│ checkpoint_ │                    │ 进程执行)   │
│ backfill()  │                    └─────────────┘
│ ...         │
│ mark_       │
│ backfill_   │
│ complete()  │
└─────────────┘
```
