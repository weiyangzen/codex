# 研究文档: codex-rs/core/src/memories/tests.rs

## 场景与职责

本文件是 Codex 核心库中 **Memory 子系统** 的集成测试模块，负责验证记忆系统的两阶段流水线（Phase 1 提取 + Phase 2 整合）的正确性。测试覆盖从底层存储操作到高层业务逻辑的完整链路，确保记忆功能在各种边界条件下表现正确。

### 核心职责
1. **存储层测试**: 验证记忆目录布局、文件同步、清理等基础操作
2. **Phase 1 测试**: 验证原始记忆提取的 schema 约束和输出格式
3. **Phase 2 测试**: 验证整合任务的调度、Agent 生命周期、错误恢复
4. **安全测试**: 验证符号链接防护等安全机制

---

## 功能点目的

### 1. 基础存储操作测试 (`memory_root_uses_shared_global_path`)
验证记忆根目录路径构造逻辑，确保 `memory_root()` 函数正确返回 `{codex_home}/memories` 路径。

### 2. Schema 约束测试 (`stage_one_output_schema_requires_rollout_slug_and_keeps_it_nullable`)
验证 Phase 1 输出的 JSON Schema 严格符合预期：
- 必须包含 `rollout_slug` 字段
- `rollout_slug` 类型必须是 `["null", "string"]`（可为 null）
- 必填字段为 `raw_memory`, `rollout_slug`, `rollout_summary`

### 3. 目录清理安全测试
- **`clear_memory_root_contents_preserves_root_directory`**: 验证清理操作保留根目录本身，仅清空内容
- **`clear_memory_root_contents_rejects_symlinked_root`** (Unix only): 关键安全测试，确保符号链接指向的目录不会被误删，防止目录遍历攻击

### 4. 文件同步测试 (`sync_rollout_summaries_and_raw_memories_file_keeps_latest_memories_only`)
验证 `sync_rollout_summaries_from_memories` 和 `rebuild_raw_memories_file_from_memories` 的协同工作：
- 仅保留最新的记忆（受 `max_raw_memories_for_consolidation` 限制）
- 自动清理过期的 rollout summary 文件
- 正确生成 `raw_memories.md` 文件格式

### 5. 文件名生成测试 (`sync_rollout_summaries_uses_timestamp_hash_and_sanitized_slug_filename`)
验证 rollout summary 文件名生成逻辑：
- 格式: `{timestamp}-{short_hash}-{slug}.md`
- 时间戳格式: `YYYY-MM-DDThh-mm-ss`
- short_hash: 4 字符字母数字混合
- slug: 最大 60 字符，小写+下划线，安全文件名

### 6. Phase 2 整合测试 (内嵌 `phase2` 模块)

#### 6.1 水位线计算测试
- `completion_watermark_never_regresses_below_claimed_input_watermark`: 确保完成水位线不会低于声明的输入水位线
- `completion_watermark_uses_claimed_watermark_when_there_are_no_memories`: 无记忆时使用声明的水位线
- `completion_watermark_uses_latest_memory_timestamp_when_it_is_newer`: 新记忆时间戳优先

#### 6.2 调度逻辑测试
- `dispatch_skips_when_global_job_is_not_dirty`: 无脏数据时跳过
- `dispatch_skips_when_global_job_is_already_running`: 避免重复运行
- `dispatch_reclaims_stale_global_lock_and_starts_consolidation`: 回收过期锁并启动整合

#### 6.3 空整合测试 (`dispatch_with_empty_stage1_outputs_rebuilds_local_artifacts`)
验证当没有 Stage 1 输出时：
- 清理所有过期的 rollout summaries
- 重置 `raw_memories.md` 为默认空状态
- 删除 `MEMORY.md`, `memory_summary.md`, skills 目录

#### 6.4 错误恢复测试
- `dispatch_marks_job_for_retry_when_sandbox_policy_cannot_be_overridden`: 沙箱策略冲突时标记重试
- `dispatch_marks_job_for_retry_when_syncing_artifacts_fails`: 文件同步失败时标记重试
- `dispatch_marks_job_for_retry_when_rebuilding_raw_memories_fails`: 重建失败时标记重试
- `dispatch_marks_job_for_retry_when_spawn_agent_fails`: Agent 启动失败时标记重试

---

## 具体技术实现

### 关键数据结构

```rust
// 测试用的 Stage1Output 构造
struct Stage1Output {
    thread_id: ThreadId,
    source_updated_at: DateTime<Utc>,  // 记忆来源时间戳
    raw_memory: String,                 // 原始记忆内容（markdown）
    rollout_summary: String,            // Rollout 摘要
    rollout_slug: Option<String>,       // 可选的 URL 友好标识
    rollout_path: PathBuf,              // 原始 rollout 文件路径
    cwd: PathBuf,                       // 工作目录
    git_branch: Option<String>,         // Git 分支
    generated_at: DateTime<Utc>,        // 生成时间
}

// Phase 2 测试用的 Claim 结构
struct Claim {
    token: String,      // 所有权令牌
    watermark: i64,     // 输入水位线（Unix 时间戳）
}
```

### 关键流程

#### 1. 测试环境搭建 (`DispatchHarness`)
```rust
struct DispatchHarness {
    _codex_home: TempDir,           // 临时目录（自动清理）
    config: Arc<Config>,            // 测试配置
    session: Arc<Session>,          // 模拟会话
    manager: ThreadManager,         // 线程管理器
    state_db: Arc<StateRuntime>,    // 状态数据库
}
```

创建流程：
1. 创建临时 codex_home 目录
2. 初始化测试配置
3. 初始化 StateRuntime（SQLite 内存数据库）
4. 创建 ThreadManager（模拟 Agent 管理）
5. 构建 Session 并注入依赖

#### 2. Stage 1 输出种子数据 (`seed_stage1_output`)
```rust
async fn seed_stage1_output(&self, source_updated_at: i64) {
    // 1. 创建线程元数据
    // 2. 插入 threads 表
    // 3. 声明 Stage 1 作业
    // 4. 标记 Stage 1 成功（触发全局整合入队）
}
```

#### 3. Phase 2 执行流程验证
测试通过 `phase2::run()` 函数验证完整流程：

```rust
pub(super) async fn run(session: &Arc<Session>, config: Arc<Config>) {
    // 1. 声明全局作业
    // 2. 获取 Agent 配置
    // 3. 查询记忆数据
    // 4. 同步文件系统 artifacts
    // 5. 生成提示词
    // 6. 启动整合 Agent
    // 7. 监控 Agent 生命周期
    // 8. 上报指标
}
```

### 文件格式验证

#### raw_memories.md 结构
```markdown
# Raw Memories

Merged stage-1 raw memories (latest first):

## Thread `<thread_id>`
updated_at: <RFC3339 时间戳>
cwd: <工作目录>
rollout_path: <rollout 文件路径>
rollout_summary_file: <文件名>.md

<raw_memory 内容>
```

#### rollout_summaries 文件名格式
```
{YYYY-MM-DDThh-mm-ss}-{4char-hash}[-{slug}].md
```

示例: `2024-01-15T08-30-00-a7B2-memory-system-refactor.md`

---

## 关键代码路径与文件引用

### 被测试的主要函数

| 测试函数 | 被测函数 | 所在文件 |
|---------|---------|---------|
| `memory_root_uses_shared_global_path` | `memory_root()` | `mod.rs` |
| `stage_one_output_schema_requires_*` | `output_schema()` | `phase1.rs` |
| `clear_memory_root_contents_*` | `clear_memory_root_contents()` | `control.rs` |
| `sync_rollout_summaries_*` | `sync_rollout_summaries_from_memories()` | `storage.rs` |
| `rebuild_raw_memories_file_*` | `rebuild_raw_memories_file_from_memories()` | `storage.rs` |
| `completion_watermark_*` | `get_watermark()` | `phase2.rs` |
| `dispatch_*` | `phase2::run()` | `phase2.rs` |

### 依赖模块

```
tests.rs
├── 使用 super::storage::*          // storage.rs
├── 使用 crate::memories::*         // mod.rs
├── 使用 codex_state::Stage1Output  // codex-rs/state/src/model/memories.rs
├── 使用 codex_protocol::ThreadId   // codex-rs/protocol/src/lib.rs
└── phase2 子模块
    ├── 使用 crate::ThreadManager   // thread_manager.rs
    ├── 使用 crate::codex::Session  // codex.rs
    └── 使用 codex_state::*         // state runtime
```

### State DB 交互

测试通过 `StateRuntime` 与 SQLite 交互：

```rust
// 声明 Stage 1 作业
try_claim_stage1_job(thread_id, worker_id, source_updated_at, lease_seconds, max_running)

// 标记 Stage 1 成功（自动触发全局整合）
mark_stage1_job_succeeded(thread_id, token, source_updated_at, raw_memory, rollout_summary, slug)

// 声明 Phase 2 作业
try_claim_global_phase2_job(worker_id, lease_seconds)

// 心跳保活
heartbeat_global_phase2_job(token, lease_seconds)
```

---

## 依赖与外部交互

### 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `tempfile::tempdir` | 创建隔离的测试目录 |
| `chrono::Utc` | 时间戳处理 |
| `pretty_assertions::assert_eq` | 友好的测试失败输出 |
| `serde_json::Value` | JSON Schema 验证 |
| `tokio::fs` | 异步文件操作 |

### 内部模块依赖

```
codex-core
├── memories/
│   ├── mod.rs          (基础路径函数)
│   ├── storage.rs      (文件同步)
│   ├── phase1.rs       (Schema)
│   ├── phase2.rs       (整合逻辑)
│   └── control.rs      (目录清理)
├── codex.rs            (Session)
├── thread_manager.rs   (ThreadManager)
└── config.rs           (Config)

codex-state
├── model/memories.rs   (Stage1Output, Phase2InputSelection)
└── runtime/memories.rs (StateRuntime DB 操作)

codex-protocol
└── ThreadId
```

### 测试夹具 (Fixtures)

#### 内联测试数据
```rust
// 典型的 Stage1Output 测试数据
Stage1Output {
    thread_id: ThreadId::new(),
    source_updated_at: Utc.timestamp_opt(100, 0).single().expect("timestamp"),
    raw_memory: "raw memory".to_string(),
    rollout_summary: "short summary".to_string(),
    rollout_slug: Some("Unsafe Slug/With Spaces".to_string()),
    rollout_path: PathBuf::from("/tmp/rollout-100.jsonl"),
    cwd: PathBuf::from("/tmp/workspace"),
    git_branch: Some("feature/memory-branch".to_string()),
    generated_at: Utc.timestamp_opt(101, 0).single().expect("timestamp"),
}
```

---

## 风险、边界与改进建议

### 当前风险点

1. **平台特定代码**
   - `clear_memory_root_contents_rejects_symlinked_root` 仅在 Unix 平台编译
   - Windows 平台的符号链接防护未在测试中覆盖

2. **时间敏感性**
   - 多个测试依赖 `Utc::now()` 和相对时间计算
   - 在极慢的测试运行器中可能出现 flaky

3. **硬编码常量**
   - 测试中使用 `DEFAULT_MEMORIES_MAX_RAW_MEMORIES_FOR_CONSOLIDATION`（默认值 64）
   - 如果默认值改变，测试行为可能变化

4. **并发假设**
   - `DispatchHarness` 假设单线程测试环境
   - 并行测试可能导致端口/资源冲突

### 边界情况

| 边界场景 | 测试覆盖 | 说明 |
|---------|---------|------|
| 空记忆列表 | ✅ | `dispatch_with_empty_stage1_outputs_*` |
| 最大记忆限制 | ✅ | 通过 `max_raw_memories_for_consolidation` 参数 |
| 符号链接攻击 | ✅ (Unix) | `clear_memory_root_contents_rejects_symlinked_root` |
| 过期锁回收 | ✅ | `dispatch_reclaims_stale_global_lock_*` |
| 沙箱策略冲突 | ✅ | `dispatch_marks_job_for_retry_when_sandbox_policy_*` |
| 文件系统错误 | ✅ | 多个错误恢复测试 |
| 特殊字符 slug | ✅ | 包含空格、符号、超长 slug 的测试 |

### 改进建议

1. **增加 Windows 符号链接测试**
   ```rust
   #[cfg(windows)]
   #[tokio::test]
   async fn clear_memory_root_contents_rejects_symlinked_root_windows() {
       // Windows 符号链接防护测试
   }
   ```

2. **提取测试常量为参数化**
   使用 `rstest` 或类似工具参数化测试：
   ```rust
   #[rstest]
   #[case(0)]
   #[case(1)]
   #[case(64)]
   async fn test_with_various_memory_limits(#[case] limit: usize) {
       // 测试不同限制值
   }
   ```

3. **增加并发测试**
   验证多个线程同时尝试声明全局锁时的行为

4. **增加大文件测试**
   测试当 `raw_memory` 内容极大时的内存和性能表现

5. **增加持久化测试**
   验证数据库重启后状态恢复的正确性

6. **改进错误消息断言**
   当前测试主要检查状态码，可增加对具体错误消息的验证

### 维护注意事项

1. **模板文件变更同步**
   - 测试中的预期输出格式（如 `raw_memories.md` 结构）必须与模板文件保持一致
   - 修改 `templates/memories/*.md` 时需要同步更新测试

2. **State DB Schema 变更**
   - 如果 `stage1_outputs` 或 `jobs` 表结构变更，需要更新测试中的 SQL 相关断言

3. **配置项变更**
   - `MemoriesConfig` 新增字段时，需要在 `DispatchHarness` 中正确初始化
