# metadata.rs 研究文档

## 场景与职责

`metadata.rs` 是 Codex rollout 模块的元数据提取和回填子模块，负责从 rollout 文件中提取会话元数据并同步到 SQLite 状态数据库。它位于 `codex-rs/core/src/rollout/metadata.rs`，是 Codex 状态管理迁移的核心组件。

该模块的核心职责包括：
1. **元数据提取**：从 rollout JSONL 文件中解析会话元数据（`SessionMetaLine`）
2. **元数据构建**：构建 `ThreadMetadataBuilder` 用于状态数据库写入
3. **状态回填**：将历史 rollout 文件批量导入 SQLite 状态数据库（backfill）
4. **动态工具持久化**：提取并持久化会话的动态工具配置

## 功能点目的

### 1. 元数据提取 `extract_metadata_from_rollout`

**目的**：从 rollout 文件中提取完整的会话元数据，用于状态数据库同步

**工作流程**：
1. 加载 rollout 文件中的所有 `RolloutItem`
2. 构建 `ThreadMetadataBuilder`（优先从 `SessionMetaLine`，否则从文件名）
3. 应用所有 rollout items 更新元数据（如 `apply_rollout_item`）
4. 获取文件 mtime 作为 `updated_at`
5. 返回 `ExtractionOutcome` 包含元数据、内存模式和解析错误数

### 2. 元数据构建器 `builder_from_session_meta` / `builder_from_items`

**目的**：从不同的数据源构建统一的 `ThreadMetadataBuilder`

**优先级**：
1. 优先从 `SessionMetaLine` 提取（包含完整的会话元数据）
2. 回退到文件名解析（仅包含时间戳和 UUID）

**包含字段**：
- `id`: 线程 ID
- `rollout_path`: rollout 文件路径
- `created_at`: 创建时间
- `source`: 会话来源
- `model_provider`: 模型提供商
- `agent_nickname` / `agent_role`: 代理信息
- `cwd`: 工作目录
- `cli_version`: CLI 版本
- `git_sha` / `git_branch` / `git_origin_url`: Git 信息
- `sandbox_policy`: 沙箱策略（默认只读）
- `approval_mode`: 审批模式（默认 OnRequest）

### 3. 状态回填 `backfill_sessions`

**目的**：将历史 rollout 文件批量迁移到 SQLite 状态数据库

**关键特性**：
- **租约机制**：使用 `try_claim_backfill` 防止多个进程同时回填
- **断点续传**：通过 `last_watermark` 记录进度，支持中断后恢复
- **批次处理**：每批处理 200 个文件（`BACKFILL_BATCH_SIZE`）
- **归档支持**：同时处理 `sessions` 和 `archived_sessions` 目录
- **Git 信息合并**：保留数据库中已存在的 Git 分支信息

**回填流程**：
```
1. 获取回填状态
2. 尝试获取回填租约（15分钟）
3. 收集所有 rollout 路径
4. 按 watermark 排序
5. 过滤已处理的文件
6. 批次处理：
   - 提取元数据
   - 归一化 cwd
   - 合并现有 Git 信息
   - 处理归档标记
   - upsert 到数据库
   - 恢复内存模式
   - 持久化动态工具
7. 检查点更新
8. 标记完成
```

## 具体技术实现

### 关键数据结构

```rust
/// 元数据提取结果
pub(crate) struct ExtractionOutcome {
    pub metadata: ThreadMetadata,      // 提取的元数据
    pub memory_mode: Option<String>,   // 内存模式（取最新的 SessionMeta）
    pub parse_errors: usize,           // 解析错误数
}

/// 回填路径封装
#[derive(Debug, Clone)]
struct BackfillRolloutPath {
    watermark: String,    // 用于排序和断点续传的标识
    path: PathBuf,        // rollout 文件路径
    archived: bool,       // 是否来自归档目录
}

/// 回填统计
struct BackfillStats {
    scanned: u32,    // 扫描数
    upserted: u32,   // 成功插入/更新数
    failed: u32,     // 失败数
}
```

### 时间戳解析

```rust
fn parse_timestamp_to_utc(ts: &str) -> Option<DateTime<Utc>> {
    const FILENAME_TS_FORMAT: &str = "%Y-%m-%dT%H-%M-%S";
    
    // 尝试文件名格式
    if let Ok(naive) = NaiveDateTime::parse_from_str(ts, FILENAME_TS_FORMAT) {
        let dt = DateTime::<Utc>::from_naive_utc_and_offset(naive, Utc);
        return dt.with_nanosecond(0);
    }
    
    // 尝试 RFC3339 格式
    if let Ok(dt) = DateTime::parse_from_rfc3339(ts) {
        return dt.with_timezone(&Utc).with_nanosecond(0);
    }
    
    None
}
```

### 元数据构建

```rust
pub(crate) fn builder_from_session_meta(
    session_meta: &SessionMetaLine,
    rollout_path: &Path,
) -> Option<ThreadMetadataBuilder> {
    let created_at = parse_timestamp_to_utc(session_meta.meta.timestamp.as_str())?;
    let mut builder = ThreadMetadataBuilder::new(
        session_meta.meta.id,
        rollout_path.to_path_buf(),
        created_at,
        session_meta.meta.source.clone(),
    );
    
    // 填充可选字段
    builder.model_provider = session_meta.meta.model_provider.clone();
    builder.agent_nickname = session_meta.meta.agent_nickname.clone();
    builder.agent_role = session_meta.meta.agent_role.clone();
    builder.cwd = session_meta.meta.cwd.clone();
    builder.cli_version = Some(session_meta.meta.cli_version.clone());
    builder.sandbox_policy = SandboxPolicy::new_read_only_policy();
    builder.approval_mode = AskForApproval::OnRequest;
    
    // 填充 Git 信息
    if let Some(git) = session_meta.git.as_ref() {
        builder.git_sha = git.commit_hash.clone();
        builder.git_branch = git.branch.clone();
        builder.git_origin_url = git.repository_url.clone();
    }
    
    Some(builder)
}
```

### 文件路径收集

```rust
async fn collect_rollout_paths(root: &Path) -> std::io::Result<Vec<PathBuf>> {
    let mut stack = vec![root.to_path_buf()];
    let mut paths = Vec::new();
    
    while let Some(dir) = stack.pop() {
        let mut read_dir = tokio::fs::read_dir(&dir).await?;
        loop {
            let next_entry = read_dir.next_entry().await?;
            let Some(entry) = next_entry else { break };
            
            let path = entry.path();
            let file_type = entry.file_type().await?;
            
            if file_type.is_dir() {
                stack.push(path);  // 递归遍历子目录
            } else if file_type.is_file() {
                let name = entry.file_name();
                let Some(name) = name.to_str() else { continue };
                if name.starts_with(ROLLOUT_PREFIX) && name.ends_with(ROLLOUT_SUFFIX) {
                    paths.push(path);
                }
            }
        }
    }
    Ok(paths)
}
```

### Watermark 生成

```rust
fn backfill_watermark_for_path(codex_home: &Path, path: &Path) -> String {
    path.strip_prefix(codex_home)
        .unwrap_or(path)
        .to_string_lossy()
        .replace('\\', "/")  // 统一使用正斜杠
}

// 示例: ~/.codex/sessions/2026/03/23/rollout-xxx.jsonl
//       -> sessions/2026/03/23/rollout-xxx.jsonl
```

### Git 信息合并策略

```rust
// 在回填时，优先保留数据库中已存在的 Git 分支
if let Ok(Some(existing_metadata)) = runtime.get_thread(metadata.id).await {
    metadata.prefer_existing_git_info(&existing_metadata);
}

// prefer_existing_git_info 实现逻辑：
// - 如果 existing 有 git_branch 且 rollout 没有，保留 existing
// - 其他字段（git_sha, git_origin_url）使用 rollout 的值
```

## 关键代码路径与文件引用

### 内部模块依赖

| 符号 | 定义位置 | 用途 |
|-----|---------|------|
| `RolloutRecorder::load_rollout_items` | `recorder.rs` | 加载 rollout 文件内容 |
| `list::parse_timestamp_uuid_from_filename` | `list.rs` | 文件名时间戳解析 |
| `SESSIONS_SUBDIR` / `ARCHIVED_SESSIONS_SUBDIR` | `mod.rs` | 目录常量 |
| `state_db::normalize_cwd_for_state_db` | `state_db.rs` | cwd 归一化 |

### 外部 crate 依赖

| crate | 用途 |
|-------|------|
| `chrono` | 时间处理 |
| `codex_protocol` | 协议类型（`ThreadId`, `SessionMetaLine`, `RolloutItem` 等） |
| `codex_state` | 状态数据库接口（`StateRuntime`, `ThreadMetadataBuilder`, `BackfillState` 等） |
| `codex_otel` | 指标上报 |
| `tracing` | 日志记录 |

### 调用方

| 调用方 | 用途 |
|-------|------|
| `state_db.rs` | `init` 函数中触发回填（如果状态不是 Complete） |
| `recorder.rs` | `write_session_meta` 中构建元数据 |

## 依赖与外部交互

### 与 State DB 的交互

```rust
// 1. 获取回填状态
let backfill_state = runtime.get_backfill_state().await?;

// 2. 尝试获取租约（防止并发回填）
let claimed = runtime.try_claim_backfill(BACKFILL_LEASE_SECONDS).await?;

// 3. 提取元数据并 upsert
let outcome = extract_metadata_from_rollout(&rollout.path, default_provider).await?;
let mut metadata = outcome.metadata;
metadata.cwd = normalize_cwd_for_state_db(&metadata.cwd);
runtime.upsert_thread(&metadata).await?;

// 4. 恢复内存模式
runtime.set_thread_memory_mode(metadata.id, memory_mode.as_str()).await?;

// 5. 持久化动态工具
runtime.persist_dynamic_tools(meta_line.meta.id, meta_line.meta.dynamic_tools.as_deref()).await?;

// 6. 检查点更新
runtime.checkpoint_backfill(last_entry.watermark.as_str()).await?;

// 7. 标记完成
runtime.mark_backfill_complete(last_watermark.as_deref()).await?;
```

### 指标上报

```rust
// 回填持续时间计时器
let timer = metric_client
    .as_ref()
    .and_then(|otel| otel.start_timer(DB_METRIC_BACKFILL_DURATION_MS, &[]).ok());

// 解析错误计数
if outcome.parse_errors > 0 {
    let _ = metric_client.counter(
        DB_ERROR_METRIC,
        outcome.parse_errors as i64,
        &[("stage", "backfill_sessions")],
    );
}

// 成功/失败计数
let _ = metric_client.counter(DB_METRIC_BACKFILL, stats.upserted as i64, &[("status", "upserted")]);
let _ = metric_client.counter(DB_METRIC_BACKFILL, stats.failed as i64, &[("status", "failed")]);

// 持续时间记录
let status = if stats.failed == 0 { "success" } 
             else if stats.upserted == 0 { "failed" } 
             else { "partial_failure" };
let _ = timer.record(&[("status", status)]);
```

## 风险、边界与改进建议

### 当前风险

1. **租约过期**：租约 15 分钟后过期，长回填可能中断
2. **内存使用**：收集所有路径到内存，大量文件时可能 OOM
3. **Git 信息丢失**：如果 rollout 文件中没有 Git 信息，且数据库中没有现有记录，Git 字段将为空
4. **解析错误静默**：JSON 解析错误被记录但不阻止回填继续

### 边界情况

1. **空 rollout 文件**：返回错误 "empty session file"
2. **缺少 SessionMeta**：尝试从文件名解析，失败则返回 None
3. **无效时间戳**：解析失败返回 None，可能导致元数据构建失败
4. **并发回填**：租约机制防止，但租约过期后可能产生竞争
5. **归档文件处理**：使用文件 mtime 作为 archived_at 回退

### 改进建议

1. **流式处理**：
   ```rust
   // 建议：使用流式处理避免全量加载
   let rollout_stream = tokio::fs::read_dir(root)
       .try_filter(|entry| is_rollout_file(entry))
       .map(|entry| extract_metadata(entry.path()));
   
   rollout_stream
       .buffer_unordered(BACKFILL_BATCH_SIZE)
       .for_each(|result| async { /* 处理结果 */ })
       .await;
   ```

2. **增量回填**：
   ```rust
   // 建议：基于文件系统通知的增量回填
   struct IncrementalBackfill {
       last_scan_time: DateTime<Utc>,
       watcher: notify::RecommendedWatcher,
   }
   ```

3. **回填进度持久化**：
   ```rust
   // 建议：更细粒度的进度跟踪
   struct BackfillProgress {
       total_files: usize,
       processed_files: usize,
       current_watermark: String,
       estimated_remaining: Duration,
   }
   ```

4. **错误隔离**：
   ```rust
   // 建议：单个文件失败不中断整个批次
   let results: Vec<Result<_, _>> = join_all(batch.iter().map(|path| {
       extract_and_upsert(path).catch_unwind()  // 捕获 panic
   })).await;
   ```

5. **动态租约续期**：
   ```rust
   // 建议：长时间回填自动续期租约
   let lease_renewal = tokio::spawn(async {
       loop {
           tokio::time::sleep(LEASE_RENEWAL_INTERVAL).await;
           runtime.renew_backfill_lease().await?;
       }
   });
   ```

6. **回填验证**：
   ```rust
   // 建议：回填完成后验证数据完整性
   async fn verify_backfill(runtime: &StateRuntime, paths: &[PathBuf]) -> VerificationResult {
       let db_count = runtime.count_threads().await?;
       let expected_count = paths.len();
       // 对比、抽样验证等
   }
   ```

### 测试覆盖

测试位于 `metadata_tests.rs`，覆盖：
- `extract_metadata_from_rollout_uses_session_meta`：基本提取流程
- `extract_metadata_from_rollout_returns_latest_memory_mode`：内存模式提取
- `builder_from_items_falls_back_to_filename`：文件名回退
- `backfill_sessions_resumes_from_watermark_and_marks_complete`：断点续传
- `backfill_sessions_preserves_existing_git_branch_and_fills_missing_git_fields`：Git 合并
- `backfill_sessions_normalizes_cwd_before_upsert`：cwd 归一化

建议增加：
- 大规模回填性能测试
- 租约竞争场景测试
- 损坏 rollout 文件容错测试
- 并发回填测试
