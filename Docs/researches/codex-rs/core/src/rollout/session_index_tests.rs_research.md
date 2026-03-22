# SessionIndex 测试深度研究文档

## 1. 场景与职责

`session_index_tests.rs` 是 `SessionIndex` 模块的单元测试文件，位于 `codex-rs/core/src/rollout/session_index_tests.rs`。其职责包括：

- **验证追加写语义**：确保最新记录优先，旧记录被正确覆盖
- **测试反向扫描算法**：验证从文件末尾向前扫描的正确性
- **验证批量查询**：确保批量 ID 查询返回正确结果
- **测试边界条件**：空文件、缺失记录、重复名称等场景

### 测试策略

测试采用 **同步测试** + **tempfile 临时目录** 的组合：
- 同步测试：因为核心逻辑使用 `spawn_blocking`，测试直接使用同步 I/O
- 临时目录：每个测试独立，避免相互影响
- 辅助函数：`write_index` 简化测试数据准备

---

## 2. 功能点目的

### 2.1 最新记录优先测试

验证核心设计决策：**当同一名称或 ID 有多个记录时，最新的 (文件末尾的) 记录应该被返回**。

### 2.2 反向扫描正确性测试

验证 `scan_index_from_end` 函数的正确性：
- 正确处理多行文件
- 正确处理文件开头没有换行符的情况
- 正确跳过不匹配的记录

### 2.3 批量查询测试

验证 `find_thread_names_by_ids` 的效率和正确性：
- 单次文件读取获取多个名称
- 正确处理部分 ID 不存在的情况

---

## 3. 具体技术实现

### 3.1 测试辅助函数

#### write_index

```rust
fn write_index(path: &Path, lines: &[SessionIndexEntry]) -> std::io::Result<()> {
    let mut out = String::new();
    for entry in lines {
        out.push_str(&serde_json::to_string(entry).unwrap());
        out.push('\n');
    }
    std::fs::write(path, out)
}
```

**设计要点**：
- 同步写入，简化测试代码
- 自动添加换行符，符合 JSONL 格式
- 批量写入，提高测试准备效率

### 3.2 核心测试用例分析

#### 3.2.1 find_thread_id_by_name_prefers_latest_entry

```rust
#[test]
fn find_thread_id_by_name_prefers_latest_entry() -> std::io::Result<()> {
    let temp = TempDir::new()?;
    let path = session_index_path(temp.path());
    
    // 创建两个不同的 ID，使用相同的名称
    let id1 = ThreadId::new();
    let id2 = ThreadId::new();
    
    let lines = vec![
        SessionIndexEntry {
            id: id1,
            thread_name: "same".to_string(),
            updated_at: "2024-01-01T00:00:00Z".to_string(),
        },
        SessionIndexEntry {
            id: id2,
            thread_name: "same".to_string(),
            updated_at: "2024-01-02T00:00:00Z".to_string(),
        },
    ];
    write_index(&path, &lines)?;

    // 验证：返回 id2 (文件中的第二个记录)
    let found = scan_index_from_end_by_name(&path, "same")?;
    assert_eq!(found.map(|entry| entry.id), Some(id2));
    
    Ok(())
}
```

**测试覆盖点**：
- ✅ 同名不同 ID 的情况
- ✅ 最新记录优先 (按文件位置，非 updated_at)
- ✅ 反向扫描正确性

**重要说明**：
> 分辨率基于追加顺序 (从末尾扫描)，而非 updated_at 字段。
> 这意味着即使 id1 的时间戳更新，如果它在文件中排在前面，也不会被返回。

#### 3.2.2 find_thread_name_by_id_prefers_latest_entry

```rust
#[test]
fn find_thread_name_by_id_prefers_latest_entry() -> std::io::Result<()> {
    let temp = TempDir::new()?;
    let path = session_index_path(temp.path());
    
    let id = ThreadId::new();
    let lines = vec![
        SessionIndexEntry {
            id,
            thread_name: "first".to_string(),
            updated_at: "2024-01-01T00:00:00Z".to_string(),
        },
        SessionIndexEntry {
            id,
            thread_name: "second".to_string(),
            updated_at: "2024-01-02T00:00:00Z".to_string(),
        },
    ];
    write_index(&path, &lines)?;

    // 验证：返回 "second"
    let found = scan_index_from_end_by_id(&path, &id)?;
    assert_eq!(
        found.map(|entry| entry.thread_name),
        Some("second".to_string())
    );
    
    Ok(())
}
```

**测试覆盖点**：
- ✅ 同一 ID 多次重命名
- ✅ 返回最新名称

#### 3.2.3 scan_index_returns_none_when_entry_missing

```rust
#[test]
fn scan_index_returns_none_when_entry_missing() -> std::io::Result<()> {
    let temp = TempDir::new()?;
    let path = session_index_path(temp.path());
    let id = ThreadId::new();
    
    let lines = vec![SessionIndexEntry {
        id,
        thread_name: "present".to_string(),
        updated_at: "2024-01-01T00:00:00Z".to_string(),
    }];
    write_index(&path, &lines)?;

    // 验证：查询不存在的名称返回 None
    let missing_name = scan_index_from_end_by_name(&path, "missing")?;
    assert_eq!(missing_name, None);

    // 验证：查询不存在的 ID 返回 None
    let missing_id = scan_index_from_end_by_id(&path, &ThreadId::new())?;
    assert_eq!(missing_id, None);
    
    Ok(())
}
```

**测试覆盖点**：
- ✅ 缺失名称处理
- ✅ 缺失 ID 处理
- ✅ 不 panic，返回优雅的空值

#### 3.2.4 find_thread_names_by_ids_prefers_latest_entry

```rust
#[tokio::test]
async fn find_thread_names_by_ids_prefers_latest_entry() -> std::io::Result<()> {
    let temp = TempDir::new()?;
    let path = session_index_path(temp.path());
    
    let id1 = ThreadId::new();
    let id2 = ThreadId::new();
    let lines = vec![
        SessionIndexEntry {
            id: id1,
            thread_name: "first".to_string(),
            updated_at: "2024-01-01T00:00:00Z".to_string(),
        },
        SessionIndexEntry {
            id: id2,
            thread_name: "other".to_string(),
            updated_at: "2024-01-01T00:00:00Z".to_string(),
        },
        SessionIndexEntry {
            id: id1,
            thread_name: "latest".to_string(),  // id1 的最新名称
            updated_at: "2024-01-02T00:00:00Z".to_string(),
        },
    ];
    write_index(&path, &lines)?;

    // 构建查询集合
    let mut ids = HashSet::new();
    ids.insert(id1);
    ids.insert(id2);

    // 期望结果
    let mut expected = HashMap::new();
    expected.insert(id1, "latest".to_string());  // 不是 "first"
    expected.insert(id2, "other".to_string());

    // 验证
    let found = find_thread_names_by_ids(temp.path(), &ids).await?;
    assert_eq!(found, expected);
    
    Ok(())
}
```

**测试覆盖点**：
- ✅ 批量查询
- ✅ 每个 ID 返回最新名称
- ✅ 异步 API 测试

**实现细节**：
- 使用 `tokio::test` 因为被测函数是异步的
- 顺序读取整个文件，而非多次反向扫描
- 时间复杂度：O(N)，N = 文件行数

#### 3.2.5 scan_index_finds_latest_match_among_mixed_entries

```rust
#[test]
fn scan_index_finds_latest_match_among_mixed_entries() -> std::io::Result<()> {
    let temp = TempDir::new()?;
    let path = session_index_path(temp.path());
    
    let id_target = ThreadId::new();
    let id_other = ThreadId::new();
    
    let expected = SessionIndexEntry {
        id: id_target,
        thread_name: "target".to_string(),
        updated_at: "2024-01-03T00:00:00Z".to_string(),
    };
    let expected_other = SessionIndexEntry {
        id: id_other,
        thread_name: "target".to_string(),  // 同名不同 ID
        updated_at: "2024-01-02T00:00:00Z".to_string(),
    };
    
    // 注意：分辨率基于追加顺序，非 updated_at
    let lines = vec![
        SessionIndexEntry {
            id: id_target,
            thread_name: "target".to_string(),
            updated_at: "2024-01-01T00:00:00Z".to_string(),  // 时间戳最早
        },
        expected_other.clone(),  // id_other，文件位置中间
        expected.clone(),        // id_target，文件位置最新
        SessionIndexEntry {
            id: ThreadId::new(),
            thread_name: "another".to_string(),
            updated_at: "2024-01-04T00:00:00Z".to_string(),  // 时间戳最新但名称不同
        },
    ];
    write_index(&path, &lines)?;

    // 按名称查询：应返回 expected (id_target，文件位置最新)
    let found_by_name = scan_index_from_end_by_name(&path, "target")?;
    assert_eq!(found_by_name, Some(expected.clone()));

    // 按 ID 查询 id_target：应返回 expected
    let found_by_id = scan_index_from_end_by_id(&path, &id_target)?;
    assert_eq!(found_by_id, Some(expected));

    // 按 ID 查询 id_other：应返回 expected_other
    let found_other_by_id = scan_index_from_end_by_id(&path, &id_other)?;
    assert_eq!(found_other_by_id, Some(expected_other));
    
    Ok(())
}
```

**测试覆盖点**：
- ✅ 混合条目场景
- ✅ 同名不同 ID 的正确区分
- ✅ 文件位置优先于时间戳
- ✅ 同时测试按名称和按 ID 查询

---

## 4. 关键代码路径与文件引用

### 4.1 测试文件结构

```
codex-rs/core/src/rollout/
├── session_index.rs         # 被测试的主模块
├── session_index_tests.rs   # 本测试文件
└── mod.rs                   # 模块导出
```

### 4.2 测试依赖

| 依赖 | 用途 |
|-----|------|
| `tempfile::TempDir` | 创建隔离的临时测试目录 |
| `pretty_assertions::assert_eq` | 更好的断言失败输出 |
| `std::collections::{HashMap, HashSet}` | 批量查询测试 |

### 4.3 关键测试函数索引

| 测试函数 | 行号 | 测试目标 |
|---------|------|---------|
| `find_thread_id_by_name_prefers_latest_entry` | 15 | 同名不同 ID，返回最新 |
| `find_thread_name_by_id_prefers_latest_entry` | 40 | 同一 ID 多次重命名 |
| `scan_index_returns_none_when_entry_missing` | 67 | 缺失记录处理 |
| `find_thread_names_by_ids_prefers_latest_entry` | 87 | 批量查询正确性 |
| `scan_index_finds_latest_match_among_mixed_entries` | 125 | 混合条目场景 |

---

## 5. 依赖与外部交互

### 5.1 测试基础设施

```rust
// Cargo.toml 中的测试依赖
[dev-dependencies]
tempfile = "3"
pretty_assertions = "1"
```

### 5.2 同步 vs 异步测试

| 测试函数 | 类型 | 原因 |
|---------|------|------|
| `find_thread_id_by_name_prefers_latest_entry` | `#[test]` | 直接测试同步的 `scan_index_from_end_by_name` |
| `find_thread_names_by_ids_prefers_latest_entry` | `#[tokio::test]` | 测试异步的 `find_thread_names_by_ids` |

### 5.3 被测函数映射

```rust
// 同步测试直接调用
scan_index_from_end_by_name(&path, "same")
scan_index_from_end_by_id(&path, &id)

// 异步测试通过 tokio 调用
find_thread_names_by_ids(temp.path(), &ids).await
```

---

## 6. 风险、边界与改进建议

### 6.1 当前测试覆盖分析

#### 已覆盖场景 ✅

| 场景 | 测试 |
|-----|------|
| 基本读写 | 所有测试 |
| 最新记录优先 | `prefers_latest_entry` 系列 |
| 同名不同 ID | `find_thread_id_by_name_prefers_latest_entry` |
| 同一 ID 多次更新 | `find_thread_name_by_id_prefers_latest_entry` |
| 缺失记录 | `scan_index_returns_none_when_entry_missing` |
| 批量查询 | `find_thread_names_by_ids_prefers_latest_entry` |
| 混合条目 | `scan_index_finds_latest_match_among_mixed_entries` |

#### 未覆盖场景 ⚠️

| 场景 | 风险等级 |
|-----|---------|
| 空索引文件 | 中 |
| 单条记录 (无换行符结尾) | 中 |
| 无效 JSON | 中 |
| 无效 UTF-8 | 中 |
| Windows 换行符 (\r\n) | 中 |
| 超大索引文件性能 | 低 |
| 并发追加写入 | 低 |

### 6.2 测试改进建议

#### 6.2.1 添加边界条件测试

```rust
#[test]
fn empty_index_file_returns_none() -> std::io::Result<()> {
    let temp = TempDir::new()?;
    let path = session_index_path(temp.path());
    
    // 创建空文件
    std::fs::File::create(&path)?;
    
    let result = scan_index_from_end_by_name(&path, "any")?;
    assert_eq!(result, None);
    
    Ok(())
}

#[test]
fn single_entry_without_newline() -> std::io::Result<()> {
    let temp = TempDir::new()?;
    let path = session_index_path(temp.path());
    
    // 写入不带换行符的单个条目
    let entry = SessionIndexEntry { ... };
    let json = serde_json::to_string(&entry)?;
    std::fs::write(&path, json)?;  // 无 \n
    
    let result = scan_index_from_end_by_id(&path, &entry.id)?;
    assert_eq!(result.map(|e| e.thread_name), Some(entry.thread_name));
    
    Ok(())
}

#[test]
fn invalid_json_lines_are_skipped() -> std::io::Result<()> {
    let temp = TempDir::new()?;
    let path = session_index_path(temp.path());
    
    let mut content = String::new();
    content.push_str("{invalid json}\n");
    content.push_str(&serde_json::to_string(&valid_entry)?);
    content.push('\n');
    std::fs::write(&path, content)?;
    
    let result = scan_index_from_end_by_id(&path, &valid_entry.id)?;
    assert_eq!(result.map(|e| e.id), Some(valid_entry.id));
    
    Ok(())
}
```

#### 6.2.2 添加性能基准测试

```rust
#[test]
fn large_index_performance() -> std::io::Result<()> {
    let temp = TempDir::new()?;
    let path = session_index_path(temp.path());
    
    // 创建 10万 条记录的索引
    let mut entries = Vec::new();
    for i in 0..100_000 {
        entries.push(SessionIndexEntry {
            id: ThreadId::new(),
            thread_name: format!("thread-{}", i),
            updated_at: "2024-01-01T00:00:00Z".to_string(),
        });
    }
    write_index(&path, &entries)?;
    
    // 测量查询时间
    let start = std::time::Instant::now();
    let result = scan_index_from_end_by_name(&path, "thread-99999")?;
    let elapsed = start.elapsed();
    
    assert!(result.is_some());
    assert!(elapsed < Duration::from_millis(100), "Query too slow: {:?}", elapsed);
    
    Ok(())
}
```

#### 6.2.3 添加并发测试

```rust
#[tokio::test]
async fn concurrent_appends_are_safe() -> std::io::Result<()> {
    let temp = TempDir::new()?;
    let codex_home = temp.path().to_path_buf();
    
    let mut handles = vec![];
    for i in 0..10 {
        let home = codex_home.clone();
        handles.push(tokio::spawn(async move {
            for j in 0..100 {
                append_thread_name(&home, ThreadId::new(), &format!("thread-{}-{}", i, j))
                    .await?;
            }
            Ok::<_, std::io::Error>(())
        }));
    }
    
    for handle in handles {
        handle.await??;
    }
    
    // 验证所有记录都可读
    let path = session_index_path(&codex_home);
    let content = std::fs::read_to_string(&path)?;
    let lines: Vec<_> = content.lines().collect();
    assert_eq!(lines.len(), 1000);
    
    Ok(())
}
```

### 6.3 测试可维护性建议

#### 6.3.1 提取公共 Setup

```rust
struct IndexTestContext {
    temp_dir: TempDir,
    index_path: PathBuf,
}

impl IndexTestContext {
    fn new() -> Self {
        let temp_dir = TempDir::new().unwrap();
        let index_path = session_index_path(temp_dir.path());
        Self { temp_dir, index_path }
    }
    
    fn write_entries(&self, entries: &[SessionIndexEntry]) -> std::io::Result<()> {
        write_index(&self.index_path, entries)
    }
    
    fn scan_by_name(&self, name: &str) -> std::io::Result<Option<SessionIndexEntry>> {
        scan_index_from_end_by_name(&self.index_path, name)
    }
}
```

#### 6.3.2 使用参数化测试

```rust
#[test_case("empty", vec![], None)]
#[test_case("single", vec![entry1.clone()], Some(entry1))]
#[test_case("multiple", vec![entry1.clone(), entry2.clone()], Some(entry2))]
fn scan_by_name_scenarios(
    _name: &str,
    entries: Vec<SessionIndexEntry>,
    expected: Option<SessionIndexEntry>,
) -> std::io::Result<()> {
    let ctx = IndexTestContext::new();
    ctx.write_entries(&entries)?;
    let result = ctx.scan_by_name("test")?;
    assert_eq!(result, expected);
    Ok(())
}
```

### 6.4 已知测试局限性

1. **时间戳字段未验证**：测试中的 `updated_at` 仅用于文档目的，实际解析不使用该字段。

2. **文件系统依赖**：测试依赖实际文件系统，某些 CI 环境可能需要特殊配置。

3. **平台差异**：Windows 和 Unix 的文件系统行为可能有细微差异 (如换行符处理)。

4. **无内存压力测试**：未测试在内存受限环境下的行为。
