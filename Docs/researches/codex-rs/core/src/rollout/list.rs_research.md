# list.rs 研究文档

## 场景与职责

`list.rs` 是 Codex rollout 模块的核心列表和发现子模块，负责会话（线程）rollout 文件的遍历、分页、排序和查询。它位于 `codex-rs/core/src/rollout/list.rs`，是 Codex 会话历史管理的基础设施。

该模块的核心职责包括：
1. **文件发现**：按日期嵌套目录结构遍历 rollout 文件（`~/.codex/sessions/YYYY/MM/DD/`）
2. **分页查询**：支持基于游标的分页，稳定处理并发新会话创建
3. **多维度排序**：支持按创建时间（`CreatedAt`）和更新时间（`UpdatedAt`）排序
4. **元数据提取**：从 rollout 文件头部解析会话元数据（thread_id、git 信息、第一条用户消息等）
5. **线程查找**：通过 UUID 或名称查找特定会话文件

## 功能点目的

### 1. 线程分页列表 `get_threads` / `get_threads_in_root`

**目的**：提供高效的线程列表查询，支持大规模会话存储的分页访问

**关键特性**：
- 游标分页：使用 `(timestamp, uuid)` 作为分页锚点，保证分页稳定性
- 扫描上限：单次请求最多扫描 10,000 个文件，防止性能退化
- 双布局支持：`NestedByDate`（按日期分层）和 `Flat`（扁平存储）

### 2. 多维度排序

**CreatedAt 排序**：
- 基于文件名中的时间戳（`rollout-YYYY-MM-DDThh-mm-ss-<uuid>.jsonl`）
- 目录遍历天然按时间倒序，效率高

**UpdatedAt 排序**：
- 基于文件系统 `mtime`
- 需要收集所有文件后排序，性能开销较大
- 注释提到未来可缓存 updated_at 时间戳优化

### 3. 线程元数据提取 `read_head_summary`

**目的**：快速提取会话关键信息用于列表展示

**扫描策略**：
- 默认读取前 10 条记录（`HEAD_RECORD_LIMIT`）
- 若已找到 session_meta 但未找到 user_event，额外扫描 200 条（`USER_EVENT_SCAN_LIMIT`）
- 提前终止：找到 session_meta + user_event 后立即停止

### 4. 线程查找 `find_thread_path_by_id_str`

**目的**：通过 UUID 快速定位会话文件

**查找策略**：
1. 优先查询 SQLite state_db（如果可用）
2. 使用 `codex_file_search` 进行文件名匹配
3. 回退到文件系统遍历
4. 发现不一致时进行 read-repair

## 具体技术实现

### 关键数据结构

```rust
/// 分页结果
pub struct ThreadsPage {
    pub items: Vec<ThreadItem>,           // 线程摘要列表
    pub next_cursor: Option<Cursor>,      // 下一页游标
    pub num_scanned_files: usize,         // 扫描文件数
    pub reached_scan_cap: bool,           // 是否触及扫描上限
}

/// 线程摘要
pub struct ThreadItem {
    pub path: PathBuf,                    // 文件绝对路径
    pub thread_id: Option<ThreadId>,      // 线程 ID
    pub first_user_message: Option<String>, // 第一条用户消息
    pub cwd: Option<PathBuf>,             // 工作目录
    pub git_branch: Option<String>,       // Git 分支
    pub git_sha: Option<String>,          // Git commit
    pub git_origin_url: Option<String>,   // Git 远程地址
    pub source: Option<SessionSource>,    // 会话来源
    pub agent_nickname: Option<String>,   // 代理昵称
    pub agent_role: Option<String>,       // 代理角色
    pub model_provider: Option<String>,   // 模型提供商
    pub cli_version: Option<String>,      // CLI 版本
    pub created_at: Option<String>,       // 创建时间（RFC3339）
    pub updated_at: Option<String>,       // 更新时间（RFC3339）
}

/// 分页游标（序列化格式: "<ts>|<uuid>"）
pub struct Cursor {
    ts: OffsetDateTime,
    id: Uuid,
}

/// 分页锚点状态
struct AnchorState {
    ts: OffsetDateTime,
    id: Uuid,
    passed: bool,  // 是否已通过锚点
}
```

### 目录遍历算法

```rust
// 嵌套目录结构: sessions/YYYY/MM/DD/*.jsonl
async fn walk_rollout_files(
    root: &Path,
    scanned_files: &mut usize,
    visitor: &mut impl RolloutFileVisitor,
) -> io::Result<()> {
    // 1. 收集年份目录（降序）
    let year_dirs = collect_dirs_desc(root, |s| s.parse::<u16>().ok()).await?;
    
    // 2. 遍历年份 -> 月份 -> 日期
    for (_year, year_path) in year_dirs.iter() {
        let month_dirs = collect_dirs_desc(year_path, |s| s.parse::<u8>().ok()).await?;
        for (_month, month_path) in month_dirs.iter() {
            let day_dirs = collect_dirs_desc(month_path, |s| s.parse::<u8>().ok()).await?;
            for (_day, day_path) in day_dirs.iter() {
                let day_files = collect_rollout_day_files(day_path).await?;
                // 3. 对每个文件调用 visitor
                for (ts, id, path) in day_files.into_iter() {
                    if let ControlFlow::Break(()) = visitor.visit(ts, id, path, *scanned_files).await {
                        break 'outer;
                    }
                }
            }
        }
    }
}
```

### 文件名解析

```rust
// 格式: rollout-YYYY-MM-DDThh-mm-ss-<uuid>.jsonl
pub fn parse_timestamp_uuid_from_filename(name: &str) -> Option<(OffsetDateTime, Uuid)> {
    let core = name.strip_prefix("rollout-")?.strip_suffix(".jsonl")?;
    
    // 从右向左扫描，找到 UUID 分隔符
    let (sep_idx, uuid) = core
        .match_indices('-')
        .rev()
        .find_map(|(i, _)| Uuid::parse_str(&core[i + 1..]).ok().map(|u| (i, u)))?;
    
    let ts_str = &core[..sep_idx];
    let format = format_description!("[year]-[month]-[day]T[hour]-[minute]-[second]");
    let ts = PrimitiveDateTime::parse(ts_str, format).ok()?.assume_utc();
    Some((ts, uuid))
}
```

### 游标序列化

```rust
impl serde::Serialize for Cursor {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        let ts_str = self.ts.format(&Rfc3339)?;
        serializer.serialize_str(&format!("{ts_str}|{}", self.id))
    }
}

impl<'de> serde::Deserialize<'de> for Cursor {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error> {
        let s = String::deserialize(deserializer)?;
        parse_cursor(&s).ok_or_else(|| serde::de::Error::custom("invalid cursor"))
    }
}
```

### Provider 过滤

```rust
struct ProviderMatcher<'a> {
    filters: &'a [String],
    matches_default_provider: bool,
}

impl<'a> ProviderMatcher<'a> {
    fn matches(&self, session_provider: Option<&str>) -> bool {
        match session_provider {
            Some(provider) => self.filters.iter().any(|c| c == provider),
            None => self.matches_default_provider,  // 未指定时使用默认提供商
        }
    }
}
```

## 关键代码路径与文件引用

### 内部模块依赖

| 符号 | 定义位置 | 用途 |
|-----|---------|------|
| `SESSIONS_SUBDIR` | `mod.rs` | 会话存储子目录名 |
| `ARCHIVED_SESSIONS_SUBDIR` | `mod.rs` | 归档会话子目录名 |
| `RolloutRecorder` | `recorder.rs` | 加载 rollout items |
| `metadata::extract_metadata_from_rollout` | `metadata.rs` | 元数据提取 |

### 外部 crate 依赖

| crate | 用途 |
|-------|------|
| `time` / `chrono` | 时间解析和格式化 |
| `uuid` | UUID 解析 |
| `serde` | 序列化/反序列化 |
| `async-trait` | 异步 trait 支持 |
| `codex_protocol` | 协议类型（`ThreadId`, `SessionSource`, `RolloutItem` 等） |
| `codex_state` | State DB 集成（`Anchor` 转换） |
| `codex_file_search` | 文件名搜索 |
| `state_db` | SQLite 状态数据库 |

### 调用方

| 调用方 | 用途 |
|-------|------|
| `recorder.rs` | `RolloutRecorder::list_threads`, `find_latest_thread_path` |
| `metadata.rs` | `read_session_meta_line` 用于动态工具持久化 |
| `codex.rs` | 会话恢复时查找线程 |
| `thread_manager.rs` | 线程列表展示 |

## 依赖与外部交互

### 文件系统布局

```
~/.codex/
├── sessions/
│   ├── 2026/
│   │   ├── 03/
│   │   │   ├── 23/
│   │   │   │   ├── rollout-2026-03-23T07-31-26-<uuid>.jsonl
│   │   │   │   └── ...
│   │   │   └── ...
│   │   └── ...
│   └── ...
└── archived_sessions/  # 归档会话（扁平结构）
    ├── rollout-2026-03-22T10-20-30-<uuid>.jsonl
    └── ...
```

### 与 State DB 的交互

```rust
// 优先使用 SQLite 查询
let state_db_ctx = state_db::open_if_present(codex_home, "").await;
if let Some(state_db_ctx) = state_db_ctx.as_deref() {
    if let Some(db_path) = state_db::find_rollout_path_by_id(...).await {
        if tokio::fs::try_exists(&db_path).await.unwrap_or(false) {
            return Ok(Some(db_path));  // 数据库命中
        }
        // 数据库返回过期路径，记录不一致
        tracing::error!("state db returned stale rollout path");
    }
}

// 回退到文件搜索
let results = file_search::run(id_str, vec![root], options, None)?;

// 发现不一致时进行 read-repair
state_db::read_repair_rollout_path(state_db_ctx.as_deref(), thread_id, archived_only, found_path).await;
```

## 风险、边界与改进建议

### 当前风险

1. **UpdatedAt 排序性能**：需要扫描所有文件后按 mtime 排序，时间复杂度 O(N log N)
2. **文件名解析脆弱性**：依赖特定文件名格式，格式变更会导致解析失败
3. **时区处理**：文件名使用本地时间，但存储使用 UTC，可能存在时区混淆
4. **并发安全**：游标分页在极端并发下可能出现重复或遗漏

### 边界情况

1. **空目录**：返回空列表而非错误
2. **损坏的 rollout 文件**：解析错误被记录但继续处理其他文件
3. **非 UTF-8 文件名**：被过滤掉，不会导致 panic
4. **扫描上限**：达到 10,000 文件后停止，设置 `reached_scan_cap` 标志
5. **游标过期**：使用旧游标查询时，新会话可能出现在结果中

### 性能瓶颈

| 操作 | 复杂度 | 瓶颈 |
|-----|-------|------|
| CreatedAt 遍历 | O(N) 其中 N=page_size | 文件系统遍历 |
| UpdatedAt 遍历 | O(M log M) 其中 M=总文件数 | 全量扫描+排序 |
| 元数据提取 | O(HEAD_RECORD_LIMIT) | JSON 解析 |
| UUID 查找 | O(1)（DB）/ O(N)（文件搜索）| 数据库可用性 |

### 改进建议

1. **UpdatedAt 索引**：
   ```rust
   // 建议：维护一个 updated_at 索引文件
   struct UpdatedAtIndex {
       path: PathBuf,
       updated_at: OffsetDateTime,
   }
   // 定期重建或增量更新
   ```

2. **并发优化**：
   ```rust
   // 建议：并行遍历目录层级
   let year_dirs = collect_dirs_desc(root, ...).await?;
   let month_futures: Vec<_> = year_dirs.iter()
       .map(|(_, path)| collect_dirs_desc(path, ...))
       .collect();
   let months = join_all(month_futures).await;
   ```

3. **缓存层**：
   ```rust
   // 建议：在内存中缓存最近访问的元数据
   struct ThreadMetadataCache {
       entries: LruCache<PathBuf, ThreadItem>,
       ttl: Duration,
   }
   ```

4. **文件名版本控制**：
   ```rust
   // 建议：在文件名中包含版本信息
   // rollout-v1-2026-03-23T07-31-26-<uuid>.jsonl
   ```

5. **增强监控**：
   - 记录扫描时间、命中率等指标
   - 对慢查询进行告警
   - 跟踪 State DB 和文件系统的不一致率

6. **批量元数据提取**：
   ```rust
   // 建议：支持批量读取多个文件的头部
   async fn read_heads_batch(paths: &[PathBuf]) -> Vec<HeadTailSummary>
   ```

### 测试覆盖

当前测试位于 `recorder_tests.rs`，建议增加：
- 大规模文件（>10,000）的性能测试
- 并发创建/删除场景下的分页稳定性测试
- 各种损坏文件名格式的容错测试
- 时区边界情况测试（跨天时区变更）
