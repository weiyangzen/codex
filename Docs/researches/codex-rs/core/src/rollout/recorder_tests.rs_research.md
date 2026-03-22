# RolloutRecorder 测试深度研究文档

## 1. 场景与职责

`recorder_tests.rs` 是 `RolloutRecorder` 模块的单元测试文件，位于 `codex-rs/core/src/rollout/recorder_tests.rs`。其职责包括：

- **验证延迟持久化行为**：确保 rollout 文件只在 `persist()` 调用后才创建
- **测试状态数据库集成**：验证 SQLite 状态同步的正确性
- **验证列表分页功能**：确保线程列表查询在各种配置下正常工作
- **测试数据回填机制**：验证从 rollout 文件到 SQLite 的数据迁移
- **验证 CWD 匹配逻辑**：测试会话恢复时的目录匹配功能

### 测试策略

测试采用 **Tokio 异步运行时** + **tempfile 临时目录** 的组合，确保：
- 测试隔离性：每个测试使用独立的临时目录
- 异步正确性：所有测试均为 `async fn`，使用真实异步 I/O
- 状态可验证：通过文件系统断言和数据库查询验证结果

---

## 2. 功能点目的

### 2.1 延迟持久化测试

验证核心设计决策：**rollout 文件不应在会话创建时立即创建，而应在首次 `persist()` 调用后创建**。

目的：
- 避免空会话产生无意义文件
- 允许缓冲早期事件
- 确保事件顺序正确性

### 2.2 状态数据库集成测试

验证 `RolloutRecorder` 与 `codex_state::StateRuntime` 的集成：
- 事件写入后是否正确更新 `updated_at`
- 元数据无关事件是否仅触发 `touch` 而非完整更新
- 缺失线程时的自动创建行为

### 2.3 列表查询测试

验证线程列表功能在两种存储模式下的行为：
- **SQLite 禁用模式**：纯文件系统扫描
- **SQLite 启用模式**：数据库优先，文件系统作为修复源

### 2.4 数据回填与修复测试

验证以下高级功能：
- **陈旧路径修复**：当 SQLite 中的路径与实际文件系统不匹配时自动修复
- **缺失路径删除**：当 SQLite 指向不存在的文件时自动清理

---

## 3. 具体技术实现

### 3.1 测试辅助函数

#### write_session_file

```rust
fn write_session_file(root: &Path, ts: &str, uuid: Uuid) -> std::io::Result<PathBuf> {
    let day_dir = root.join("sessions/2025/01/03");
    fs::create_dir_all(&day_dir)?;
    let path = day_dir.join(format!("rollout-{ts}-{uuid}.jsonl"));
    let mut file = File::create(&path)?;
    
    // 写入 SessionMeta
    let meta = serde_json::json!({
        "timestamp": ts,
        "type": "session_meta",
        "payload": { "id": uuid, ... }
    });
    writeln!(file, "{meta}")?;
    
    // 写入用户事件
    let user_event = serde_json::json!({...});
    writeln!(file, "{user_event}")?;
    Ok(path)
}
```

**设计要点**：
- 创建符合实际目录结构的路径 (`sessions/YYYY/MM/DD/`)
- 包含完整的 SessionMeta 和 UserMessage 事件
- 返回创建的文件路径供断言使用

### 3.2 核心测试用例分析

#### 3.2.1 recorder_materializes_only_after_explicit_persist

```rust
#[tokio::test]
async fn recorder_materializes_only_after_explicit_persist() -> std::io::Result<()> {
    // 1. 创建临时目录和配置
    let home = TempDir::new().expect("temp dir");
    let config = ConfigBuilder::default()
        .codex_home(home.path().to_path_buf())
        .build().await?;
    
    // 2. 创建 recorder (延迟模式)
    let recorder = RolloutRecorder::new(&config, RolloutRecorderParams::new(...), None, None).await?;
    let rollout_path = recorder.rollout_path().to_path_buf();
    
    // 3. 验证文件尚未创建
    assert!(!rollout_path.exists(), "rollout file should not exist before first user message");
    
    // 4. 记录事件并 flush
    recorder.record_items(&[RolloutItem::EventMsg(EventMsg::AgentMessage(...))]).await?;
    recorder.flush().await?;
    
    // 5. 验证文件仍未创建 (因为没有 persist)
    assert!(!rollout_path.exists(), "rollout file should remain deferred before first user message");
    
    // 6. 调用 persist
    recorder.persist().await?;
    recorder.persist().await?;  // 验证幂等性
    
    // 7. 验证文件已创建
    assert!(rollout_path.exists(), "rollout file should be materialized");
    
    // 8. 验证内容完整性
    let text = std::fs::read_to_string(&rollout_path)?;
    assert!(text.contains("\"type\":\"session_meta\""), "expected session metadata in rollout");
    
    // 9. 验证事件顺序
    let buffered_idx = text.find("buffered-event").expect("buffered event in rollout");
    let user_idx = text.find("first-user-message").expect("first user message in rollout");
    assert!(buffered_idx < user_idx, "buffered items should preserve ordering");
    
    // 10. 验证幂等性 (第二次 persist 不添加内容)
    let text_after_second_persist = std::fs::read_to_string(&rollout_path)?;
    assert_eq!(text_after_second_persist, text);
    
    recorder.shutdown().await?;
    Ok(())
}
```

**测试覆盖点**：
- ✅ 延迟文件创建行为
- ✅ 缓冲事件在 persist 后正确写入
- ✅ 事件顺序保持
- ✅ `persist()` 幂等性

#### 3.2.2 metadata_irrelevant_events_touch_state_db_updated_at

```rust
#[tokio::test]
async fn metadata_irrelevant_events_touch_state_db_updated_at() -> std::io::Result<()> {
    // 1. 启用 SQLite 功能
    let mut config = ConfigBuilder::default().codex_home(home.path().to_path_buf()).build().await?;
    config.features.enable(Feature::Sqlite).expect("test config should allow sqlite");
    
    // 2. 初始化 StateRuntime
    let state_db = StateRuntime::init(home.path().to_path_buf(), config.model_provider_id.clone())
        .await.expect("state db should initialize");
    state_db.mark_backfill_complete(None).await.expect("backfill should be complete");
    
    // 3. 创建带 state_db 的 recorder
    let recorder = RolloutRecorder::new(&config, RolloutRecorderParams::new(...), 
                                        Some(state_db.clone()), None).await?;
    
    // 4. 记录初始事件并 persist
    recorder.record_items(&[...]).await?;
    recorder.persist().await?;
    recorder.flush().await?;
    
    // 5. 获取初始状态
    let initial_thread = state_db.get_thread(thread_id).await?.expect("thread should exist");
    let initial_updated_at = initial_thread.updated_at;
    let initial_title = initial_thread.title.clone();
    
    // 6. 等待 1 秒确保时间戳变化
    tokio::time::sleep(Duration::from_secs(1)).await;
    
    // 7. 记录"元数据无关"事件 (AgentMessage)
    recorder.record_items(&[RolloutItem::EventMsg(EventMsg::AgentMessage(...))]).await?;
    recorder.flush().await?;
    
    // 8. 验证 updated_at 已更新，但 title 未变
    let updated_thread = state_db.get_thread(thread_id).await?.expect("thread should still exist");
    assert!(updated_thread.updated_at > initial_updated_at);
    assert_eq!(updated_thread.title, initial_title);  // 标题不应改变
    
    recorder.shutdown().await?;
    Ok(())
}
```

**关键概念**：
- **元数据相关事件**：会改变线程元数据的事件 (如 UserMessage 可能改变 title)
- **元数据无关事件**：仅更新 `updated_at` 时间戳的事件 (如 AgentMessage)

**测试目的**：验证优化路径 - 对于元数据无关事件，只需执行 `touch_thread_updated_at` 而非完整的元数据更新。

#### 3.2.3 list_threads_db_disabled_does_not_skip_paginated_items

```rust
#[tokio::test]
async fn list_threads_db_disabled_does_not_skip_paginated_items() -> std::io::Result<()> {
    // 1. 禁用 SQLite
    let mut config = ConfigBuilder::default().codex_home(home.path().to_path_buf()).build().await?;
    config.features.disable(Feature::Sqlite).expect("test config should allow sqlite to be disabled");
    
    // 2. 创建三个测试文件 (不同时间)
    let newest = write_session_file(home.path(), "2025-01-03T12-00-00", Uuid::from_u128(9001))?;
    let middle = write_session_file(home.path(), "2025-01-02T12-00-00", Uuid::from_u128(9002))?;
    let _oldest = write_session_file(home.path(), "2025-01-01T12-00-00", Uuid::from_u128(9003))?;
    
    // 3. 查询第一页 (page_size = 1)
    let page1 = RolloutRecorder::list_threads(&config, 1, None, ThreadSortKey::CreatedAt, ...).await?;
    assert_eq!(page1.items.len(), 1);
    assert_eq!(page1.items[0].path, newest);
    let cursor = page1.next_cursor.clone().expect("cursor should be present");
    
    // 4. 使用 cursor 查询第二页
    let page2 = RolloutRecorder::list_threads(&config, 1, Some(&cursor), ThreadSortKey::CreatedAt, ...).await?;
    assert_eq!(page2.items.len(), 1);
    assert_eq!(page2.items[0].path, middle);
    
    Ok(())
}
```

**测试重点**：
- 验证纯文件系统模式下的分页正确性
- 验证 cursor 机制工作正常
- 确保按创建时间降序排列

#### 3.2.4 list_threads_db_enabled_drops_missing_rollout_paths

```rust
#[tokio::test]
async fn list_threads_db_enabled_drops_missing_rollout_paths() -> std::io::Result<()> {
    // 1. 启用 SQLite
    config.features.enable(Feature::Sqlite).expect("test config should allow sqlite");
    
    // 2. 创建 StateRuntime
    let runtime = codex_state::StateRuntime::init(home.path().to_path_buf(), ...).await?;
    runtime.mark_backfill_complete(None).await?;
    
    // 3. 手动插入一条指向不存在路径的元数据
    let stale_path = home.path().join("sessions/2099/01/01/rollout-2099-01-01T00-00-00-{uuid}.jsonl");
    let mut builder = codex_state::ThreadMetadataBuilder::new(thread_id, stale_path, ...);
    let mut metadata = builder.build(config.model_provider_id.as_str());
    runtime.upsert_thread(&metadata).await?;
    
    // 4. 查询列表
    let page = RolloutRecorder::list_threads(&config, 10, None, ThreadSortKey::CreatedAt, ...).await?;
    
    // 5. 验证结果：返回空列表，且数据库中的陈旧记录被删除
    assert_eq!(page.items.len(), 0);
    let stored_path = runtime.find_rollout_path_by_id(thread_id, Some(false)).await?;
    assert_eq!(stored_path, None);
    
    Ok(())
}
```

**测试场景**：数据库中存在指向已删除文件的记录。

**预期行为**：
1. 查询时检测到文件不存在
2. 从返回结果中排除该记录
3. 从数据库中删除该记录

#### 3.2.5 list_threads_db_enabled_repairs_stale_rollout_paths

```rust
#[tokio::test]
async fn list_threads_db_enabled_repairs_stale_rollout_paths() -> std::io::Result<()> {
    // ... 类似 setup ...
    
    // 1. 创建实际文件
    let real_path = write_session_file(home.path(), "2025-01-03T13-00-00", uuid)?;
    
    // 2. 在数据库中插入指向错误路径的记录
    let stale_path = home.path().join("sessions/2099/01/01/rollout-2099-01-01T00-00-00-{uuid}.jsonl");
    let mut builder = codex_state::ThreadMetadataBuilder::new(thread_id, stale_path, ...);
    runtime.upsert_thread(&builder.build(...)).await?;
    
    // 3. 查询列表
    let page = RolloutRecorder::list_threads(&config, 1, None, ThreadSortKey::CreatedAt, ...).await?;
    
    // 4. 验证：返回正确的路径，且数据库已修复
    assert_eq!(page.items.len(), 1);
    assert_eq!(page.items[0].path, real_path);
    
    let repaired_path = runtime.find_rollout_path_by_id(thread_id, Some(false)).await?;
    assert_eq!(repaired_path, Some(real_path));
    
    Ok(())
}
```

**测试场景**：数据库中的路径与实际文件位置不匹配 (可能是由于文件被手动移动)。

**修复机制**：
1. 文件系统扫描找到实际文件
2. 检测到路径不匹配
3. 更新数据库中的路径记录

#### 3.2.6 resume_candidate_matches_cwd_reads_latest_turn_context

```rust
#[tokio::test]
async fn resume_candidate_matches_cwd_reads_latest_turn_context() -> std::io::Result<()> {
    // 1. 创建两个不同的 CWD
    let stale_cwd = home.path().join("stale");
    let latest_cwd = home.path().join("latest");
    fs::create_dir_all(&stale_cwd)?;
    fs::create_dir_all(&latest_cwd)?;
    
    // 2. 创建会话文件
    let path = write_session_file(home.path(), "2025-01-03T13-00-00", Uuid::from_u128(9012))?;
    
    // 3. 追加 TurnContext 事件 (包含 latest_cwd)
    let mut file = std::fs::OpenOptions::new().append(true).open(&path)?;
    let turn_context = RolloutLine {
        timestamp: "2025-01-03T13:00:01Z".to_string(),
        item: RolloutItem::TurnContext(TurnContextItem {
            cwd: latest_cwd.clone(),
            ...
        }),
    };
    writeln!(file, "{}", serde_json::to_string(&turn_context)?)?;
    
    // 4. 验证：即使 SessionMeta 中的 CWD 是 stale_cwd，
    //    也能通过读取 TurnContext 匹配到 latest_cwd
    assert!(resume_candidate_matches_cwd(
        path.as_path(),
        Some(stale_cwd.as_path()),  // 缓存的 CWD (过时)
        latest_cwd.as_path(),        // 目标 CWD
        "test-provider",
    ).await);
    
    Ok(())
}
```

**测试重点**：验证 CWD 匹配的回退机制：
1. 首先检查缓存的 CWD
2. 然后读取 rollout 文件中的最新 `TurnContext`
3. 最后回退到 `SessionMeta` 中的 CWD

---

## 4. 关键代码路径与文件引用

### 4.1 测试文件结构

```
codex-rs/core/src/rollout/
├── recorder.rs           # 被测试的主模块
├── recorder_tests.rs     # 本测试文件
├── list.rs               # 列表查询实现
├── metadata.rs           # 元数据提取
└── session_index.rs      # 会话名称索引
```

### 4.2 测试依赖

| 依赖 | 用途 |
|-----|------|
| `tempfile::TempDir` | 创建隔离的临时测试目录 |
| `tokio::test` | 异步测试运行时 |
| `pretty_assertions::assert_eq` | 更好的断言失败输出 |
| `codex_state::StateRuntime` | SQLite 状态数据库 |

### 4.3 关键测试函数索引

| 测试函数 | 行号 | 测试目标 |
|---------|------|---------|
| `recorder_materializes_only_after_explicit_persist` | 54 | 延迟持久化 |
| `metadata_irrelevant_events_touch_state_db_updated_at` | 141 | 状态数据库更新优化 |
| `metadata_irrelevant_events_fall_back_to_upsert_when_thread_missing` | 228 | 缺失线程自动创建 |
| `list_threads_db_disabled_does_not_skip_paginated_items` | 280 | 纯文件系统分页 |
| `list_threads_db_enabled_drops_missing_rollout_paths` | 328 | 陈旧路径清理 |
| `list_threads_db_enabled_repairs_stale_rollout_paths` | 396 | 路径修复 |
| `resume_candidate_matches_cwd_reads_latest_turn_context` | 467 | CWD 匹配回退 |

---

## 5. 依赖与外部交互

### 5.1 测试基础设施

```rust
// Cargo.toml 中的测试依赖
[dev-dependencies]
tempfile = "3"
pretty_assertions = "1"
```

### 5.2 异步运行时配置

```rust
#[tokio::test]
async fn test_name() -> std::io::Result<()> {
    // 使用默认 Tokio 运行时
    // 多线程运行时确保测试更接近生产环境
}
```

### 5.3 状态数据库测试配置

```rust
// 启用 SQLite 功能
config.features.enable(Feature::Sqlite).expect("test config should allow sqlite");

// 初始化 StateRuntime
let state_db = StateRuntime::init(home.path().to_path_buf(), provider).await?;

// 标记回填完成 (否则查询会回退到文件系统)
state_db.mark_backfill_complete(None).await?;
```

---

## 6. 风险、边界与改进建议

### 6.1 当前测试覆盖分析

#### 已覆盖场景 ✅

| 场景 | 测试 |
|-----|------|
| 延迟持久化 | `recorder_materializes_only_after_explicit_persist` |
| 事件顺序保持 | 同上 |
| persist 幂等性 | 同上 |
| 状态数据库集成 | `metadata_irrelevant_events_*` |
| 文件系统分页 | `list_threads_db_disabled_*` |
| 数据库分页 | `list_threads_db_enabled_*` |
| 陈旧路径处理 | `list_threads_db_enabled_drops_missing_rollout_paths` |
| 路径修复 | `list_threads_db_enabled_repairs_stale_rollout_paths` |
| CWD 匹配 | `resume_candidate_matches_cwd_reads_latest_turn_context` |

#### 未覆盖场景 ⚠️

| 场景 | 风险等级 |
|-----|---------|
| 磁盘满错误处理 | 高 |
| 文件权限拒绝 | 高 |
| 并发写入竞争 | 中 |
| 超大事件 (>10KB) 截断 | 中 |
| 网络文件系统 (NFS) 行为 | 中 |
| 文件名编码问题 (非 UTF-8) | 低 |
| 系统时间回拨 | 低 |

### 6.2 测试改进建议

#### 6.2.1 添加错误场景测试

```rust
#[tokio::test]
async fn recorder_handles_disk_full() -> std::io::Result<()> {
    // 使用 tempfs 或模拟来测试磁盘满场景
    // 验证适当的错误返回
}

#[tokio::test]
async fn recorder_handles_permission_denied() -> std::io::Result<()> {
    // 创建只读目录
    // 验证权限错误处理
}
```

#### 6.2.2 添加并发测试

```rust
#[tokio::test]
async fn concurrent_record_items_is_safe() -> std::io::Result<()> {
    // 创建多个任务同时调用 record_items
    // 验证数据完整性
}
```

#### 6.2.3 添加性能基准测试

```rust
#[tokio::test]
async fn large_rollout_file_performance() -> std::io::Result<()> {
    // 创建包含 10万 条事件的 rollout 文件
    // 测量列表查询和恢复性能
}
```

#### 6.2.4 添加模糊测试

```rust
// 使用 proptest 或类似工具
proptest! {
    #[test]
    fn arbitrary_rollout_items_dont_panic(items: Vec<RolloutItem>) {
        // 验证任意输入不会导致 panic
    }
}
```

### 6.3 测试可维护性建议

#### 6.3.1 提取公共 Setup 代码

当前测试中有大量重复的 setup 代码，建议提取：

```rust
struct TestContext {
    temp_dir: TempDir,
    config: Config,
    state_db: Option<StateRuntime>,
}

impl TestContext {
    async fn new() -> Self { ... }
    async fn with_sqlite() -> Self { ... }
    fn write_session_file(&self, ...) -> PathBuf { ... }
}
```

#### 6.3.2 使用参数化测试

对于相似的数据库启用/禁用测试，可以使用参数化：

```rust
#[test_case(true)]  // SQLite enabled
#[test_case(false)] // SQLite disabled
#[tokio::test]
async fn list_threads_pagination(sqlite_enabled: bool) -> std::io::Result<()> {
    // 共享的测试逻辑
}
```

### 6.4 已知测试局限性

1. **时间敏感性**：`metadata_irrelevant_events_touch_state_db_updated_at` 使用 `sleep(1s)` 来确保时间戳变化，这增加了测试运行时间。

2. **平台依赖**：测试使用文件系统元数据 (mtime)，在 Windows 和 Unix 上行为可能略有不同。

3. **环境依赖**：测试依赖 `tempfile` 创建的实际文件系统，某些 CI 环境可能需要特殊配置。
