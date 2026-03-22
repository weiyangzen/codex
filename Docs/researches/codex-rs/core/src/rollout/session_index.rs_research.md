# SessionIndex 深度研究文档

## 1. 场景与职责

`session_index.rs` 是 Codex 核心模块中负责**会话名称索引**的轻量级组件，位于 `codex-rs/core/src/rollout/session_index.rs`。其主要职责包括：

- **会话名称持久化**：将线程名称与线程 ID 的映射关系持久化到 JSONL 文件
- **名称到 ID 查询**：根据会话名称查找对应的线程 ID
- **ID 到名称查询**：根据线程 ID 查找最新的会话名称
- **批量名称查询**：支持批量查询多个线程 ID 的名称

### 核心使用场景

1. **用户重命名会话**：用户通过 UI 设置会话名称时，追加一条记录到索引
2. **按名称恢复会话**：用户通过名称而非 UUID 查找并恢复历史会话
3. **会话列表展示**：展示带有人类可读名称的会话列表

### 设计哲学

采用**追加写 (Append-Only)** 设计：
- 写入：始终追加新记录，不修改历史
- 读取：从文件末尾向前扫描，最新记录获胜
- 优势：写入性能高，天然支持历史追溯

---

## 2. 功能点目的

### 2.1 追加写索引

```rust
// 文件格式：session_index.jsonl
{"id":"uuid-1","thread_name":"Project Setup","updated_at":"2024-01-01T00:00:00Z"}
{"id":"uuid-1","thread_name":"Project Setup - Updated","updated_at":"2024-01-02T00:00:00Z"}
{"id":"uuid-2","thread_name":"Bug Fix","updated_at":"2024-01-03T00:00:00Z"}
```

**设计决策**：
- 不删除旧记录，而是追加新记录
- 读取时从后向前扫描，第一个匹配的记录即为最新
- 简化并发控制，避免文件锁定问题

### 2.2 反向扫描优化

```rust
fn scan_index_from_end<F>(
    path: &Path,
    mut predicate: F,
) -> std::io::Result<Option<SessionIndexEntry>>
where
    F: FnMut(&SessionIndexEntry) -> bool,
{
    let mut file = File::open(path)?;
    let mut remaining = file.metadata()?.len();
    let mut line_rev: Vec<u8> = Vec::new();
    let mut buf = vec![0u8; READ_CHUNK_SIZE];  // 8KB 缓冲区
    
    // 从文件末尾开始，分块向前读取
    while remaining > 0 {
        let read_size = usize::try_from(remaining.min(READ_CHUNK_SIZE as u64))?;
        remaining -= read_size as u64;
        file.seek(SeekFrom::Start(remaining))?;
        file.read_exact(&mut buf[..read_size])?;
        
        // 反向处理字节，构建行
        for &byte in buf[..read_size].iter().rev() {
            if byte == b'\n' {
                if let Some(entry) = parse_line_from_rev(&mut line_rev, &mut predicate)? {
                    return Ok(Some(entry));
                }
                continue;
            }
            line_rev.push(byte);
        }
    }
    ...
}
```

**优化点**：
- 8KB 分块读取，避免大文件全量加载
- 反向扫描，通常很快找到匹配记录
- 时间复杂度：O(文件大小)，但平均接近 O(1)

### 2.3 批量查询优化

```rust
pub async fn find_thread_names_by_ids(
    codex_home: &Path,
    thread_ids: &HashSet<ThreadId>,
) -> std::io::Result<HashMap<ThreadId, String>> {
    // 顺序读取整个文件，而非多次反向扫描
    let file = tokio::fs::File::open(&path).await?;
    let reader = tokio::io::BufReader::new(file);
    let mut lines = reader.lines();
    
    while let Some(line) = lines.next_line().await? {
        let Ok(entry) = serde_json::from_str::<SessionIndexEntry>(trimmed) else {
            continue;
        };
        if thread_ids.contains(&entry.id) {
            names.insert(entry.id, entry.thread_name.to_string());
        }
    }
    ...
}
```

**策略选择**：
- 单条查询：反向扫描 (快)
- 批量查询：顺序读取 (避免多次文件寻址)

---

## 3. 具体技术实现

### 3.1 核心数据结构

#### SessionIndexEntry

```rust
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct SessionIndexEntry {
    pub id: ThreadId,           // 线程唯一标识
    pub thread_name: String,    // 人类可读的会话名称
    pub updated_at: String,     // RFC3339 格式时间戳
}
```

#### 常量定义

```rust
const SESSION_INDEX_FILE: &str = "session_index.jsonl";
const READ_CHUNK_SIZE: usize = 8192;  // 8KB 读取缓冲区
```

### 3.2 关键流程

#### 3.2.1 追加线程名称

```rust
pub async fn append_thread_name(
    codex_home: &Path,
    thread_id: ThreadId,
    name: &str,
) -> std::io::Result<()> {
    // 1. 生成 RFC3339 时间戳
    let updated_at = OffsetDateTime::now_utc()
        .format(&Rfc3339)
        .unwrap_or_else(|_| "unknown".to_string());
    
    // 2. 构建条目
    let entry = SessionIndexEntry {
        id: thread_id,
        thread_name: name.to_string(),
        updated_at,
    };
    
    // 3. 追加到文件
    append_session_index_entry(codex_home, &entry).await
}
```

#### 3.2.2 追加条目实现

```rust
pub async fn append_session_index_entry(
    codex_home: &Path,
    entry: &SessionIndexEntry,
) -> std::io::Result<()> {
    let path = session_index_path(codex_home);
    
    // 1. 打开文件 (创建或追加)
    let mut file = tokio::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&path)
        .await?;
    
    // 2. 序列化为 JSON
    let mut line = serde_json::to_string(entry).map_err(std::io::Error::other)?;
    line.push('\n');
    
    // 3. 写入并刷新
    file.write_all(line.as_bytes()).await?;
    file.flush().await?;
    
    Ok(())
}
```

#### 3.2.3 反向扫描实现

```rust
fn scan_index_from_end<F>(
    path: &Path,
    mut predicate: F,
) -> std::io::Result<Option<SessionIndexEntry>>
where
    F: FnMut(&SessionIndexEntry) -> bool,
{
    let mut file = File::open(path)?;
    let mut remaining = file.metadata()?.len();
    let mut line_rev: Vec<u8> = Vec::new();
    let mut buf = vec![0u8; READ_CHUNK_SIZE];

    while remaining > 0 {
        // 计算本次读取大小
        let read_size = usize::try_from(remaining.min(READ_CHUNK_SIZE as u64))
            .map_err(std::io::Error::other)?;
        remaining -= read_size as u64;
        
        // 定位并读取
        file.seek(SeekFrom::Start(remaining))?;
        file.read_exact(&mut buf[..read_size])?;

        // 反向处理字节
        for &byte in buf[..read_size].iter().rev() {
            if byte == b'\n' {
                // 遇到换行，尝试解析当前行
                if let Some(entry) = parse_line_from_rev(&mut line_rev, &mut predicate)? {
                    return Ok(Some(entry));
                }
                continue;
            }
            line_rev.push(byte);
        }
    }

    // 处理文件开头可能的最后一行
    if let Some(entry) = parse_line_from_rev(&mut line_rev, &mut predicate)? {
        return Ok(Some(entry));
    }

    Ok(None)
}
```

#### 3.2.4 行解析

```rust
fn parse_line_from_rev<F>(
    line_rev: &mut Vec<u8>,
    predicate: &mut F,
) -> std::io::Result<Option<SessionIndexEntry>>
where
    F: FnMut(&SessionIndexEntry) -> bool,
{
    if line_rev.is_empty() {
        return Ok(None);
    }
    
    // 1. 反转字节恢复原始顺序
    line_rev.reverse();
    
    // 2. 转换为字符串
    let line = std::mem::take(line_rev);
    let Ok(mut line) = String::from_utf8(line) else {
        return Ok(None);  // 忽略无效 UTF-8
    };
    
    // 3. 处理 Windows 换行符
    if line.ends_with('\r') {
        line.pop();
    }
    
    // 4. 解析 JSON
    let trimmed = line.trim();
    if trimmed.is_empty() {
        return Ok(None);
    }
    let Ok(entry) = serde_json::from_str::<SessionIndexEntry>(trimmed) else {
        return Ok(None);  // 忽略无效 JSON
    };
    
    // 5. 应用谓词
    if predicate(&entry) {
        return Ok(Some(entry));
    }
    
    Ok(None)
}
```

### 3.3 查询函数

#### 3.3.1 根据名称查找 ID

```rust
pub async fn find_thread_id_by_name(
    codex_home: &Path,
    name: &str,
) -> std::io::Result<Option<ThreadId>> {
    if name.trim().is_empty() {
        return Ok(None);
    }
    
    let path = session_index_path(codex_home);
    if !path.exists() {
        return Ok(None);
    }
    
    // 使用 spawn_blocking 避免阻塞异步运行时
    let name = name.to_string();
    let entry = tokio::task::spawn_blocking(
        move || scan_index_from_end_by_name(&path, &name)
    ).await.map_err(std::io::Error::other)??;
    
    Ok(entry.map(|entry| entry.id))
}
```

#### 3.3.2 根据 ID 查找名称

```rust
pub async fn find_thread_name_by_id(
    codex_home: &Path,
    thread_id: &ThreadId,
) -> std::io::Result<Option<String>> {
    let path = session_index_path(codex_home);
    if !path.exists() {
        return Ok(None);
    }
    
    let id = *thread_id;
    let entry = tokio::task::spawn_blocking(
        move || scan_index_from_end_by_id(&path, &id)
    ).await.map_err(std::io::Error::other)??;
    
    Ok(entry.map(|entry| entry.thread_name))
}
```

#### 3.3.3 查找 rollout 路径

```rust
pub async fn find_thread_path_by_name_str(
    codex_home: &Path,
    name: &str,
) -> std::io::Result<Option<PathBuf>> {
    // 1. 先通过名称找到 ID
    let Some(thread_id) = find_thread_id_by_name(codex_home, name).await? else {
        return Ok(None);
    };
    
    // 2. 再通过 ID 找到 rollout 路径
    super::list::find_thread_path_by_id_str(codex_home, &thread_id.to_string()).await
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 文件结构

```
codex-rs/core/src/rollout/
├── session_index.rs        # 本文件
├── session_index_tests.rs  # 单元测试
├── list.rs                 # 线程路径查找 (依赖)
└── mod.rs                  # 模块导出
```

### 4.2 导出函数

```rust
// mod.rs 中的导出
pub use session_index::append_thread_name;
pub use session_index::find_thread_name_by_id;
pub use session_index::find_thread_path_by_name_str;
```

### 4.3 关键函数索引

| 函数名 | 行号 | 用途 |
|-------|------|------|
| `append_thread_name` | 28 | 公开 API：追加线程名称 |
| `append_session_index_entry` | 49 | 底层：追加条目到文件 |
| `find_thread_name_by_id` | 67 | 公开 API：ID 查名称 |
| `find_thread_names_by_ids` | 83 | 公开 API：批量 ID 查名称 |
| `find_thread_id_by_name` | 115 | 公开 API：名称查 ID |
| `find_thread_path_by_name_str` | 135 | 公开 API：名称查路径 |
| `scan_index_from_end` | 163 | 核心：反向扫描算法 |
| `parse_line_from_rev` | 200 | 辅助：解析反转的行 |

---

## 5. 依赖与外部交互

### 5.1 上游调用方

```
codex-rs/core/src/
├── codex_thread.rs
│   └── 处理 SetThreadName 操作
│       └── session_index::append_thread_name()
│
├── app_server/
│   └── 处理 thread 查询请求
│       └── session_index::find_thread_*()
│
└── tui/
    └── 会话列表/恢复 UI
        └── session_index::find_thread_path_by_name_str()
```

### 5.2 下游依赖

| 依赖 | 用途 |
|-----|------|
| `tokio::fs` | 异步文件操作 |
| `serde_json` | JSON 序列化/反序列化 |
| `time::OffsetDateTime` | RFC3339 时间戳 |
| `codex_protocol::ThreadId` | 线程标识类型 |

### 5.3 文件系统布局

```
~/.codex/
├── session_index.jsonl     # 本模块管理的文件
├── sessions/
│   └── ...                 # rollout 文件
└── state.db                # SQLite 数据库
```

### 5.4 与 State DB 的关系

```
┌─────────────────────┐      ┌─────────────────────┐
│   session_index     │      │     state.db        │
│   (JSONL)           │      │   (SQLite)          │
├─────────────────────┤      ├─────────────────────┤
│ - thread_name       │      │ - thread metadata   │
│ - id                │◄────►│ - rollout_path      │
│ - updated_at        │      │ - updated_at        │
└─────────────────────┘      └─────────────────────┘
         │                              │
         │         ┌──────────┐         │
         └────────►│  互补使用 │◄────────┘
                   └──────────┘
```

**设计说明**：
- `session_index` 专门用于名称索引，轻量且简单
- `state.db` 用于完整的元数据管理
- 两者互补，不互相替代

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 文件无限增长

由于采用追加写策略，`session_index.jsonl` 会随着重命名操作不断增长。

**当前缓解**：
- 每次重命名只增加一行 (~100-200 字节)
- 正常使用下增长缓慢

**潜在问题**：
- 频繁重命名可能导致文件变大
- 反向扫描性能随文件大小线性下降

#### 6.1.2 数据不一致

如果 `session_index.jsonl` 被手动修改或损坏，可能导致：
- 名称与 ID 映射错误
- 无法找到正确的会话

**当前缓解**：
- 解析失败时静默跳过 (`continue`)
- 始终使用最新记录

#### 6.1.3 并发写入

当前实现**不处理并发写入**，如果多个进程同时追加：
- 可能导致行交错
- 数据损坏

**当前缓解**：
- 单进程架构 (Codex CLI) 下风险较低
- 每次写入后立即 `flush`

### 6.2 边界条件

| 场景 | 行为 |
|-----|------|
| 空名称 | 返回 `None`，不追加 |
| 索引文件不存在 | 返回 `None` 或创建新文件 |
| 无效 JSON 行 | 跳过，继续扫描 |
| 无效 UTF-8 | 跳过，继续扫描 |
| 空 ID 集合 (批量查询) | 返回空 HashMap |
| 超大索引文件 | 扫描变慢，但功能正常 |

### 6.3 改进建议

#### 6.3.1 定期压缩

```rust
pub async fn compact_index(codex_home: &Path) -> std::io::Result<()> {
    // 1. 读取所有记录，保留每个 ID 的最新记录
    // 2. 写入临时文件
    // 3. 原子替换原文件
}
```

**触发时机**：
- 启动时检查文件大小，超过阈值自动压缩
- 提供手动压缩 API

#### 6.3.2 写入锁定

```rust
use tokio::sync::Mutex;

static INDEX_WRITE_LOCK: Lazy<Mutex<()>> = Lazy::new(|| Mutex::new(()));

pub async fn append_thread_name(...) -> std::io::Result<()> {
    let _guard = INDEX_WRITE_LOCK.lock().await;
    // 执行写入
}
```

#### 6.3.3 缓存层

```rust
pub struct SessionIndexCache {
    name_to_id: RwLock<HashMap<String, ThreadId>>,
    id_to_name: RwLock<HashMap<ThreadId, String>>,
}
```

**优势**：
- 减少文件 I/O
- 提升查询性能

**挑战**：
- 需要处理缓存失效
- 多进程场景下缓存同步复杂

#### 6.3.4 与 State DB 合并

长期考虑，可以将名称索引合并到 SQLite：

```sql
-- 在 threads 表中添加 name 列
ALTER TABLE threads ADD COLUMN name TEXT;

-- 创建索引
CREATE INDEX idx_threads_name ON threads(name);
```

**优势**：
- 单一数据源
- 事务支持
- 更好的查询性能

**劣势**：
- 失去简单的追加写语义
- 需要迁移现有索引

### 6.4 测试覆盖

当前测试 (`session_index_tests.rs`) 覆盖：
- ✅ 基本读写功能
- ✅ 最新记录优先
- ✅ 缺失记录处理
- ✅ 批量查询
- ⚠️ 建议补充：并发写入、大文件性能、无效数据处理
