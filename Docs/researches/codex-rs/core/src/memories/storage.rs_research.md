# storage.rs - 研究文档

## 场景与职责

`storage.rs` 模块负责管理记忆文件系统工件的存储和同步。它是记忆系统的持久化层，确保数据库中的记忆数据与文件系统保持一致。

### 核心职责

1. **raw_memories.md 重建**: 从数据库 stage-1 输出重建合并的记忆文件
2. **rollout_summaries 同步**: 同步 rollout 摘要文件
3. **文件命名**: 生成规范的文件名（时间戳 + 哈希 + slug）
4. **清理**: 移除不再需要的陈旧文件

## 功能点目的

### 主要函数

#### 1. `rebuild_raw_memories_file_from_memories`

**目的**: 从数据库 stage-1 输出重建 `raw_memories.md` 文件

**实现**:
```rust
pub(super) async fn rebuild_raw_memories_file_from_memories(
    root: &Path,
    memories: &[Stage1Output],
    max_raw_memories_for_consolidation: usize,
) -> std::io::Result<()> {
    ensure_layout(root).await?;
    rebuild_raw_memories_file(root, memories, max_raw_memories_for_consolidation).await
}

async fn rebuild_raw_memories_file(
    root: &Path,
    memories: &[Stage1Output],
    max_raw_memories_for_consolidation: usize,
) -> std::io::Result<()> {
    let retained = retained_memories(memories, max_raw_memories_for_consolidation);
    let mut body = String::from("# Raw Memories\n\n");

    if retained.is_empty() {
        body.push_str("No raw memories yet.\n");
        return tokio::fs::write(raw_memories_file(root), body).await;
    }

    body.push_str("Merged stage-1 raw memories (latest first):\n\n");
    for memory in retained {
        writeln!(body, "## Thread `{}`", memory.thread_id)?;
        writeln!(body, "updated_at: {}", memory.source_updated_at.to_rfc3339())?;
        writeln!(body, "cwd: {}", memory.cwd.display())?;
        writeln!(body, "rollout_path: {}", memory.rollout_path.display())?;
        let rollout_summary_file = format!("{}.md", rollout_summary_file_stem(memory));
        writeln!(body, "rollout_summary_file: {rollout_summary_file}")?;
        writeln!(body)?;
        body.push_str(memory.raw_memory.trim());
        body.push_str("\n\n");
    }

    tokio::fs::write(raw_memories_file(root), body).await
}
```

**输出格式**:
```markdown
# Raw Memories

Merged stage-1 raw memories (latest first):

## Thread `0194f5a6-...`
updated_at: 2025-02-11T15:35:19+00:00
cwd: /tmp/workspace
rollout_path: /tmp/rollout.jsonl
rollout_summary_file: 2025-02-11T15-35-19-jqmb-migration_test.md

---
description: ...
...
```

#### 2. `sync_rollout_summaries_from_memories`

**目的**: 同步 rollout 摘要文件与数据库状态

**实现**:
```rust
pub(super) async fn sync_rollout_summaries_from_memories(
    root: &Path,
    memories: &[Stage1Output],
    max_raw_memories_for_consolidation: usize,
) -> std::io::Result<()> {
    ensure_layout(root).await?;

    // 1. 确定保留的文件
    let retained = retained_memories(memories, max_raw_memories_for_consolidation);
    let keep = retained.iter().map(rollout_summary_file_stem).collect::<HashSet<_>>();
    
    // 2. 清理陈旧的摘要文件
    prune_rollout_summaries(root, &keep).await?;

    // 3. 写入新的摘要文件
    for memory in retained {
        write_rollout_summary_for_thread(root, memory).await?;
    }

    // 4. 如果没有保留的记忆，清理其他工件
    if retained.is_empty() {
        for file_name in ["MEMORY.md", "memory_summary.md"] {
            let path = root.join(file_name);
            if let Err(err) = tokio::fs::remove_file(path).await
                && err.kind() != std::io::ErrorKind::NotFound
            {
                return Err(err);
            }
        }
        let skills_dir = root.join("skills");
        if let Err(err) = tokio::fs::remove_dir_all(skills_dir).await
            && err.kind() != std::io::ErrorKind::NotFound
        {
            return Err(err);
        }
    }

    Ok(())
}
```

#### 3. `write_rollout_summary_for_thread`

**目的**: 为单个线程写入 rollout 摘要文件

**实现**:
```rust
async fn write_rollout_summary_for_thread(
    root: &Path,
    memory: &Stage1Output,
) -> std::io::Result<()> {
    let file_stem = rollout_summary_file_stem(memory);
    let path = rollout_summaries_dir(root).join(format!("{file_stem}.md"));

    let mut body = String::new();
    writeln!(body, "thread_id: {}", memory.thread_id)?;
    writeln!(body, "updated_at: {}", memory.source_updated_at.to_rfc3339())?;
    writeln!(body, "rollout_path: {}", memory.rollout_path.display())?;
    writeln!(body, "cwd: {}", memory.cwd.display())?;
    if let Some(git_branch) = memory.git_branch.as_deref() {
        writeln!(body, "git_branch: {git_branch}")?;
    }
    writeln!(body)?;
    body.push_str(&memory.rollout_summary);
    body.push('\n');

    tokio::fs::write(path, body).await
}
```

**输出格式**:
```markdown
thread_id: 0194f5a6-89ab-7cde-8123-456789abcdef
updated_at: 2025-02-11T15:35:19+00:00
rollout_path: /tmp/rollout.jsonl
cwd: /tmp/workspace
git_branch: feature/memory-branch

# Task 1: ...
...
```

#### 4. `rollout_summary_file_stem_from_parts`

**目的**: 生成规范的文件名

**算法**:
```rust
pub(super) fn rollout_summary_file_stem_from_parts(
    thread_id: codex_protocol::ThreadId,
    source_updated_at: chrono::DateTime<chrono::Utc>,
    rollout_slug: Option<&str>,
) -> String {
    const ROLLOUT_SLUG_MAX_LEN: usize = 60;
    const SHORT_HASH_ALPHABET: &[u8; 62] = b"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
    const SHORT_HASH_SPACE: u32 = 14_776_336;  // 62^4

    let thread_id = thread_id.to_string();
    
    // 1. 从 UUID 提取时间戳和哈希种子
    let (timestamp_fragment, short_hash_seed) = match Uuid::parse_str(&thread_id) {
        Ok(thread_uuid) => {
            let timestamp = thread_uuid.get_timestamp()
                .and_then(|uuid_timestamp| {
                    let (seconds, nanos) = uuid_timestamp.to_unix();
                    i64::try_from(seconds).ok().and_then(|secs| {
                        chrono::DateTime::<chrono::Utc>::from_timestamp(secs, nanos)
                    })
                })
                .unwrap_or(source_updated_at);
            let short_hash_seed = (thread_uuid.as_u128() & 0xFFFF_FFFF) as u32;
            (timestamp.format("%Y-%m-%dT%H-%M-%S").to_string(), short_hash_seed)
        }
        Err(_) => {
            // 非 UUID：使用 source_updated_at 和哈希计算
            let mut short_hash_seed = 0u32;
            for byte in thread_id.bytes() {
                short_hash_seed = short_hash_seed.wrapping_mul(31).wrapping_add(u32::from(byte));
            }
            (source_updated_at.format("%Y-%m-%dT%H-%M-%S").to_string(), short_hash_seed)
        }
    };
    
    // 2. 计算 4 字符短哈希
    let mut short_hash_value = short_hash_seed % SHORT_HASH_SPACE;
    let mut short_hash_chars = ['0'; 4];
    for idx in (0..short_hash_chars.len()).rev() {
        let alphabet_idx = (short_hash_value % SHORT_HASH_ALPHABET.len() as u32) as usize;
        short_hash_chars[idx] = SHORT_HASH_ALPHABET[alphabet_idx] as char;
        short_hash_value /= SHORT_HASH_ALPHABET.len() as u32;
    }
    let short_hash: String = short_hash_chars.iter().collect();
    let file_prefix = format!("{timestamp_fragment}-{short_hash}");

    // 3. 处理 slug
    let Some(raw_slug) = rollout_slug else {
        return file_prefix;
    };

    let mut slug = String::with_capacity(ROLLOUT_SLUG_MAX_LEN);
    for ch in raw_slug.chars() {
        if slug.len() >= ROLLOUT_SLUG_MAX_LEN {
            break;
        }
        if ch.is_ascii_alphanumeric() {
            slug.push(ch.to_ascii_lowercase());
        } else {
            slug.push('_');
        }
    }
    while slug.ends_with('_') {
        slug.pop();
    }

    if slug.is_empty() {
        file_prefix
    } else {
        format!("{file_prefix}-{slug}")
    }
}
```

**文件名格式**:
- 基础格式: `{timestamp}-{short_hash}`
- 带 slug: `{timestamp}-{short_hash}-{slug}`
- 示例: `2025-02-11T15-35-19-jqmb-migration_test.md`

## 关键代码路径与文件引用

### 主要函数

| 函数 | 行号 | 描述 |
|------|------|------|
| `rebuild_raw_memories_file_from_memories` | 13 | 重建 raw_memories.md |
| `sync_rollout_summaries_from_memories` | 23 | 同步 rollout 摘要 |
| `rebuild_raw_memories_file` | 62 | 实际重建逻辑 |
| `prune_rollout_summaries` | 98 | 清理陈旧摘要 |
| `write_rollout_summary_for_thread` | 128 | 写入单个摘要 |
| `retained_memories` | 156 | 确定保留的记忆 |
| `rollout_summary_file_stem` | 171 | 文件名生成入口 |
| `rollout_summary_file_stem_from_parts` | 179 | 文件名生成实现 |

### 辅助函数

| 函数 | 行号 | 描述 |
|------|------|------|
| `raw_memories_format_error` | 163 | 格式化错误转换 |
| `rollout_summary_format_error` | 167 | 格式化错误转换 |

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `crate::memories::ensure_layout` | 确保目录布局 |
| `crate::memories::raw_memories_file` | raw_memories.md 路径 |
| `crate::memories::rollout_summaries_dir` | rollout_summaries 路径 |
| `codex_state::Stage1Output` | 数据结构 |

### 外部依赖

| Crate | 用途 |
|-------|------|
| `std::collections::HashSet` | 去重 |
| `std::fmt::Write` | 字符串写入 |
| `tokio::fs` | 异步文件操作 |
| `tracing::warn` | 警告日志 |
| `uuid::Uuid` | UUID 解析 |

## 风险、边界与改进建议

### 已知风险

1. **文件系统竞争**:
   - 多个进程可能同时操作同一文件
   - 没有文件锁机制

2. **部分写入**:
   - 如果进程崩溃，可能留下部分写入的文件
   - 没有原子写入机制

3. **字符编码**:
   - 假设 UTF-8 编码
   - 非 UTF-8 内容可能导致错误

4. **路径长度**:
   - 在 Windows 上可能超出最大路径长度
   - 没有路径长度检查

### 边界条件

1. **空记忆**: 生成 "No raw memories yet."
2. **超长 slug**: 截断至 60 字符
3. **无效字符**: 替换为下划线
4. **非 UUID thread_id**: 使用 source_updated_at 和哈希计算

### 改进建议

1. **原子写入**:
```rust
async fn atomic_write(path: &Path, content: &str) -> std::io::Result<()> {
    let temp_path = path.with_extension("tmp");
    tokio::fs::write(&temp_path, content).await?;
    tokio::fs::rename(&temp_path, path).await
}
```

2. **文件锁**:
   - 使用 `fs2` 或类似 crate 添加文件锁
   - 防止并发修改

3. **校验和**:
   - 添加内容校验和
   - 检测文件损坏

4. **备份机制**:
   - 写入前创建备份
   - 支持回滚

5. **路径验证**:
   - 检查路径长度限制
   - 处理无效字符

6. **增量更新**:
   - 支持增量更新而非全量重建
   - 提高大记忆集的性能
