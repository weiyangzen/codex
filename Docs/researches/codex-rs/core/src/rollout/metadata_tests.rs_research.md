# metadata_tests.rs 研究文档

## 场景与职责

`metadata_tests.rs` 是 Codex rollout 模块的元数据子模块测试文件，位于 `codex-rs/core/src/rollout/metadata_tests.rs`。它通过 `#[path = "metadata_tests.rs"]` 属性被 `metadata.rs` 引入，作为其内联测试模块。

该测试文件的核心职责包括：
1. 验证元数据提取逻辑的正确性
2. 测试从 rollout 文件解析 `SessionMeta` 的完整流程
3. 验证内存模式提取（取最新值）
4. 测试文件名回退机制（当 rollout 中没有 SessionMeta 时）
5. 验证状态回填的断点续传功能
6. 测试 Git 信息合并策略
7. 验证 cwd 归一化处理

## 功能点目的

### 1. 基本元数据提取测试 `extract_metadata_from_rollout_uses_session_meta`

**目的**：验证从包含有效 `SessionMetaLine` 的 rollout 文件中正确提取元数据

**测试流程**：
1. 创建临时目录
2. 生成 UUID 和线程 ID
3. 构建 `SessionMeta` 和 `SessionMetaLine`
4. 创建 rollout 文件并写入 JSONL
5. 调用 `extract_metadata_from_rollout`
6. 验证提取的元数据与预期一致

**验证点**：
- 元数据字段正确性
- 解析错误数为 0
- 内存模式为 None

### 2. 内存模式提取测试 `extract_metadata_from_rollout_returns_latest_memory_mode`

**目的**：验证当 rollout 中有多个 `SessionMeta` 时，提取最新的 `memory_mode`

**测试场景**：
- 第一个 `SessionMeta` 没有 `memory_mode`
- 第二个 `SessionMeta` 有 `memory_mode: "polluted"`
- 验证最终提取结果为 `"polluted"`

**实现细节**：
```rust
let memory_mode = items.iter().rev().find_map(|item| match item {
    RolloutItem::SessionMeta(meta_line) => meta_line.meta.memory_mode.clone(),
    _ => None,
});
```

### 3. 文件名回退测试 `builder_from_items_falls_back_to_filename`

**目的**：验证当 rollout 中没有 `SessionMeta` 时，能从文件名解析时间戳和 UUID

**测试场景**：
- rollout 只包含 `CompactedItem`
- 验证 `builder_from_items` 仍能从文件名成功构建 `ThreadMetadataBuilder`

**验证点**：
- 提取的时间戳与文件名一致
- UUID 正确解析
- 使用默认 `SessionSource`

### 4. 回填断点续传测试 `backfill_sessions_resumes_from_watermark_and_marks_complete`

**目的**：验证回填任务支持断点续传，不会重复处理已处理的文件

**测试流程**：
1. 创建两个 rollout 文件
2. 初始化 `StateRuntime`
3. 手动标记第一个文件已处理（设置 watermark）
4. 等待租约过期（测试中租约仅 1 秒）
5. 执行回填
6. 验证第一个文件未处理，第二个文件已处理

**关键配置**：
```rust
#[cfg(test)]
const BACKFILL_LEASE_SECONDS: i64 = 1;  // 测试中使用 1 秒租约
```

### 5. Git 信息合并测试 `backfill_sessions_preserves_existing_git_branch_and_fills_missing_git_fields`

**目的**：验证回填时保留数据库中已存在的 Git 分支，同时填充缺失的 Git 字段

**测试场景**：
- rollout 文件包含完整的 Git 信息（sha、branch、origin_url）
- 数据库中已有记录，但只有 `git_branch`（其他字段为空）
- 验证回填后：
  - `git_sha` 从 rollout 填充
  - `git_branch` 保留数据库中的值
  - `git_origin_url` 从 rollout 填充

### 6. CWD 归一化测试 `backfill_sessions_normalizes_cwd_before_upsert`

**目的**：验证回填前对 cwd 进行归一化处理（如去除 `.` 路径组件）

**测试场景**：
- 创建包含 `cwd: "/path/to/."` 的 rollout 文件
- 验证回填后存储的 cwd 已归一化为 `/path/to`

## 具体技术实现

### 测试辅助函数

```rust
/// 在 sessions 目录下创建 rollout 文件
fn write_rollout_in_sessions(
    codex_home: &Path,
    filename_ts: &str,      // 文件名时间戳格式: "2026-01-27T12-34-56"
    event_ts: &str,         // 事件时间戳格式: "2026-01-27T12:34:56Z"
    thread_uuid: Uuid,
    git: Option<GitInfo>,
) -> PathBuf

/// 带自定义 cwd 的 rollout 文件创建
fn write_rollout_in_sessions_with_cwd(
    codex_home: &Path,
    filename_ts: &str,
    event_ts: &str,
    thread_uuid: Uuid,
    cwd: PathBuf,
    git: Option<GitInfo>,
) -> PathBuf
```

### 测试数据构建模式

```rust
// 标准测试数据模板
let session_meta = SessionMeta {
    id,                                    // ThreadId
    forked_from_id: None,
    timestamp: "2026-01-27T12:34:56Z".to_string(),
    cwd: dir.path().to_path_buf(),
    originator: "cli".to_string(),
    cli_version: "0.0.0".to_string(),
    source: SessionSource::default(),
    agent_nickname: None,
    agent_role: None,
    model_provider: Some("openai".to_string()),
    base_instructions: None,
    dynamic_tools: None,
    memory_mode: None,
};

let session_meta_line = SessionMetaLine {
    meta: session_meta,
    git: None,  // 或 Some(GitInfo { ... })
};

let rollout_line = RolloutLine {
    timestamp: "2026-01-27T12:34:56Z".to_string(),
    item: RolloutItem::SessionMeta(session_meta_line),
};
```

### 状态数据库测试初始化

```rust
let runtime = codex_state::StateRuntime::init(
    codex_home.clone(),
    "test-provider".to_string()
).await.expect("initialize runtime");
```

### 配置测试对象

```rust
let mut config = crate::config::test_config();
config.codex_home = codex_home.clone();
config.model_provider_id = "test-provider".to_string();
```

## 关键代码路径与文件引用

### 被测试的函数

| 函数 | 定义位置 | 测试覆盖 |
|-----|---------|---------|
| `extract_metadata_from_rollout` | `metadata.rs:95` | 2 个测试 |
| `builder_from_session_meta` | `metadata.rs:38` | 1 个测试（间接） |
| `builder_from_items` | `metadata.rs:64` | 1 个测试 |
| `backfill_sessions` | `metadata.rs:133` | 3 个测试 |
| `file_modified_time_utc` | `metadata.rs:369` | 1 个测试（间接） |
| `backfill_watermark_for_path` | `metadata.rs:362` | 1 个测试（间接） |

### 依赖类型

| 类型 | 来源 crate | 用途 |
|-----|-----------|------|
| `SessionMeta` | `codex_protocol::protocol` | 会话元数据 |
| `SessionMetaLine` | `codex_protocol::protocol` | 带 Git 信息的元数据行 |
| `RolloutLine` | `codex_protocol::protocol` | rollout 文件行格式 |
| `RolloutItem` | `codex_protocol::protocol` | rollout 项枚举 |
| `GitInfo` | `codex_protocol::protocol` | Git 信息 |
| `ThreadId` | `codex_protocol` | 线程 ID |
| `CompactedItem` | `codex_protocol::protocol` | 压缩项 |
| `BackfillStatus` | `codex_state` | 回填状态 |
| `ThreadMetadataBuilder` | `codex_state` | 元数据构建器 |

### 测试工具

| 工具 | 用途 |
|-----|------|
| `tempfile::tempdir()` | 创建临时测试目录 |
| `pretty_assertions::assert_eq` | 更好的断言输出 |
| `tokio::time::sleep` | 等待租约过期 |

## 依赖与外部交互

### 测试模块结构

```rust
// metadata.rs 末尾
#[cfg(test)]
#[path = "metadata_tests.rs"]
mod tests;
```

### 测试依赖关系

```
metadata_tests.rs
    ├── metadata.rs (被测试代码)
    ├── codex_protocol::protocol::* (协议类型)
    ├── codex_state::* (状态数据库)
    ├── chrono (时间处理)
    ├── tempfile (临时目录)
    ├── pretty_assertions (断言)
    └── uuid (UUID 生成)
```

### 测试数据流

```
1. 创建临时目录 (tempdir)
       │
       ▼
2. 生成测试数据 (SessionMeta, RolloutLine)
       │
       ▼
3. 写入 rollout 文件 (std::fs::File)
       │
       ▼
4. 初始化 StateRuntime (codex_state)
       │
       ▼
5. 执行被测试函数
       │
       ▼
6. 验证结果 (assert_eq!)
```

## 风险、边界与改进建议

### 当前风险

1. **租约等待时间**：`backfill_sessions_resumes_from_watermark_and_marks_complete` 中硬编码 2 秒等待租约过期，可能在不稳定的 CI 环境中失败
2. **时间依赖**：测试依赖文件系统 mtime，在特定文件系统（如 FAT）上可能精度不足
3. **并发测试**：如果多个测试同时运行，可能竞争 SQLite 数据库

### 边界情况

当前测试未覆盖：
1. **空 rollout 文件**：`extract_metadata_from_rollout` 对空文件返回错误
2. **损坏的 JSON**：解析错误计数 > 0 的场景
3. **无效 UUID**：文件名中包含无效 UUID
4. **权限错误**：无法读取 rollout 文件
5. **并发回填**：多个进程同时尝试回填
6. **大规模回填**：数千个文件的性能测试

### 改进建议

1. **消除硬编码等待**：
   ```rust
   // 建议：使用条件变量或回调替代 sleep
   let lease_expired = Arc::new(Notify::new());
   // 回填完成后通知
   lease_expired.notified().await;
   ```

2. **参数化测试**：
   ```rust
   // 建议：使用 rstest 进行参数化测试
   #[rstest]
   #[case("2026-01-27T12-34-56", "2026-01-27T12:34:56Z")]
   #[case("2026-12-31T23-59-59", "2026-12-31T23:59:59Z")]
   async fn test_various_timestamps(#[case] filename_ts: &str, #[case] event_ts: &str) {
       // 测试多种时间戳格式
   }
   ```

3. **错误场景测试**：
   ```rust
   #[tokio::test]
   async fn extract_metadata_from_empty_rollout_fails() {
       let dir = tempdir().expect("tempdir");
       let path = dir.path().join("rollout-empty.jsonl");
       File::create(&path).expect("create empty file");
       
       let result = extract_metadata_from_rollout(&path, "openai").await;
       assert!(result.is_err());
       assert!(result.unwrap_err().to_string().contains("empty"));
   }
   ```

4. **性能基准测试**：
   ```rust
   #[tokio::test]
   async fn backfill_large_number_of_files() {
       let dir = tempdir().expect("tempdir");
       // 创建 1000 个 rollout 文件
       // 测量回填时间
       // 验证内存使用
   }
   ```

5. **并发安全测试**：
   ```rust
   #[tokio::test]
   async fn concurrent_backfill_is_safe() {
       // 启动两个并发回填任务
       // 验证只有一个成功获取租约
       // 验证最终数据一致性
   }
   ```

6. **Mock 时间**：
   ```rust
   // 建议：使用 mock 时间替代真实时间
   #[cfg(test)]
   static MOCK_TIME: AtomicI64 = AtomicI64::new(0);
   
   fn now_utc() -> DateTime<Utc> {
       #[cfg(test)]
       return DateTime::from_timestamp(MOCK_TIME.load(Ordering::SeqCst), 0).unwrap();
       #[cfg(not(test))]
       return Utc::now();
   }
   ```

### 测试覆盖率分析

| 功能 | 覆盖状态 | 建议 |
|-----|---------|------|
| 基本元数据提取 | ✅ 完整 | - |
| 内存模式提取 | ✅ 完整 | - |
| 文件名回退 | ✅ 完整 | - |
| 回填断点续传 | ✅ 完整 | 消除 sleep |
| Git 信息合并 | ✅ 完整 | - |
| cwd 归一化 | ✅ 完整 | - |
| 错误处理 | ❌ 缺失 | 添加负面测试 |
| 并发安全 | ❌ 缺失 | 添加并发测试 |
| 性能基准 | ❌ 缺失 | 添加性能测试 |
| 大规模数据 | ❌ 缺失 | 添加压力测试 |
