# storage_tests.rs - 研究文档

## 场景与职责

`storage_tests.rs` 是 `storage.rs` 模块的单元测试文件，负责验证文件系统存储功能的正确性。

### 测试覆盖范围

1. **文件名生成**: 验证基于 UUID 和 slug 的文件名生成
2. **Slug 清理**: 验证 slug 的清理和截断
3. **空 slug 处理**: 验证空 slug 的处理

## 功能点目的

### 测试用例设计

| 测试函数 | 目的 |
|----------|------|
| `rollout_summary_file_stem_uses_uuid_timestamp_and_hash_when_slug_missing` | 验证无 slug 时的文件名生成 |
| `rollout_summary_file_stem_sanitizes_and_truncates_slug` | 验证 slug 清理和截断 |
| `rollout_summary_file_stem_uses_uuid_timestamp_and_hash_when_slug_is_empty` | 验证空 slug 处理 |

## 具体技术实现

### 测试辅助函数

```rust
const FIXED_PREFIX: &str = "2025-02-11T15-35-19-jqmb";

fn stage1_output_with_slug(thread_id: ThreadId, rollout_slug: Option<&str>) -> Stage1Output {
    Stage1Output {
        thread_id,
        source_updated_at: Utc.timestamp_opt(123, 0).single().expect("timestamp"),
        raw_memory: "raw memory".to_string(),
        rollout_summary: "summary".to_string(),
        rollout_slug: rollout_slug.map(ToString::to_string),
        rollout_path: PathBuf::from("/tmp/rollout.jsonl"),
        cwd: PathBuf::from("/tmp/workspace"),
        git_branch: None,
        generated_at: Utc.timestamp_opt(124, 0).single().expect("timestamp"),
    }
}

fn fixed_thread_id() -> ThreadId {
    ThreadId::try_from("0194f5a6-89ab-7cde-8123-456789abcdef").expect("valid thread id")
}
```

### 测试 1: 无 slug 文件名生成

```rust
#[test]
fn rollout_summary_file_stem_uses_uuid_timestamp_and_hash_when_slug_missing() {
    let thread_id = fixed_thread_id();
    let memory = stage1_output_with_slug(thread_id, None);

    // 验证两种函数入口返回相同结果
    assert_eq!(rollout_summary_file_stem(&memory), FIXED_PREFIX);
    assert_eq!(
        rollout_summary_file_stem_from_parts(
            memory.thread_id,
            memory.source_updated_at,
            memory.rollout_slug.as_deref(),
        ),
        FIXED_PREFIX
    );
}
```

**验证点**:
- 使用 UUID 时间戳（2025-02-11 15:35:19）
- 生成 4 字符短哈希（jqmb）
- 格式: `{timestamp}-{hash}`

### 测试 2: Slug 清理和截断

```rust
#[test]
fn rollout_summary_file_stem_sanitizes_and_truncates_slug() {
    let thread_id = fixed_thread_id();
    let memory = stage1_output_with_slug(
        thread_id,
        Some("Unsafe Slug/With Spaces & Symbols + EXTRA_LONG_12345_67890_ABCDE_fghij_klmno"),
    );

    let stem = rollout_summary_file_stem(&memory);
    let slug = stem
        .strip_prefix(&format!("{FIXED_PREFIX}-"))
        .expect("slug suffix should be present");
    
    assert_eq!(slug.len(), 60);  // 最大长度限制
    assert_eq!(
        slug,
        "unsafe_slug_with_spaces___symbols___extra_long_12345_67890_a"
    );
}
```

**验证点**:
- 大写转换为小写
- 特殊字符替换为下划线
- 截断至 60 字符
- 保留字母数字字符

### 测试 3: 空 slug 处理

```rust
#[test]
fn rollout_summary_file_stem_uses_uuid_timestamp_and_hash_when_slug_is_empty() {
    let thread_id = fixed_thread_id();
    let memory = stage1_output_with_slug(thread_id, Some(""));

    // 空 slug 应等同于无 slug
    assert_eq!(rollout_summary_file_stem(&memory), FIXED_PREFIX);
}
```

**验证点**:
- 空字符串 slug 被忽略
- 回退到基础格式

## 关键代码路径与文件引用

### 测试结构

```
storage_tests.rs
├── 导入被测函数
├── 常量 FIXED_PREFIX
├── 辅助函数 stage1_output_with_slug (行 11-23)
├── 辅助函数 fixed_thread_id (行 25-27)
├── 测试 1: rollout_summary_file_stem_uses_uuid_timestamp_and_hash_when_slug_missing (行 29-43)
├── 测试 2: rollout_summary_file_stem_sanitizes_and_truncates_slug (行 45-62)
└── 测试 3: rollout_summary_file_stem_uses_uuid_timestamp_and_hash_when_slug_is_empty (行 64-70)
```

### 依赖

| 依赖 | 用途 |
|------|------|
| `super::rollout_summary_file_stem` | 被测函数 |
| `super::rollout_summary_file_stem_from_parts` | 被测函数 |
| `chrono::TimeZone`/`Utc` | 时间戳构建 |
| `codex_protocol::ThreadId` | Thread ID |
| `codex_state::Stage1Output` | 测试数据 |
| `pretty_assertions::assert_eq` | 清晰的测试失败输出 |
| `std::path::PathBuf` | 路径构建 |

## 依赖与外部交互

### 测试框架

- 使用标准 Rust 测试框架 (`#[test]`)
- 使用 `pretty_assertions` 提供清晰的 diff 输出

### 测试数据

- 使用固定 UUID: `0194f5a6-89ab-7cde-8123-456789abcdef`
- 该 UUID 对应时间戳: 2025-02-11T15:35:19
- 期望前缀: `2025-02-11T15-35-19-jqmb`

## 风险、边界与改进建议

### 当前覆盖缺口

1. **文件系统操作**:
   - 没有测试 `rebuild_raw_memories_file_from_memories`
   - 没有测试 `sync_rollout_summaries_from_memories`
   - 没有测试 `write_rollout_summary_for_thread`

2. **非 UUID thread_id**:
   - 没有测试非 UUID 格式的 thread_id 处理

3. **边界条件**:
   - 没有测试超长 slug（超过 60 字符）
   - 没有测试特殊 Unicode 字符
   - 没有测试路径注入攻击

4. **并发场景**:
   - 没有测试并发文件访问

### 改进建议

1. **添加文件系统测试**:
```rust
#[tokio::test]
async fn rebuild_raw_memories_file_creates_correct_format() {
    let temp_dir = tempdir().unwrap();
    let memories = vec![Stage1Output { ... }];
    
    rebuild_raw_memories_file_from_memories(temp_dir.path(), &memories, 100).await.unwrap();
    
    let content = tokio::fs::read_to_string(temp_dir.path().join("raw_memories.md")).await.unwrap();
    assert!(content.contains("# Raw Memories"));
    assert!(content.contains("## Thread"));
}
```

2. **添加非 UUID 测试**:
```rust
#[test]
fn rollout_summary_file_stem_handles_non_uuid_thread_id() {
    let thread_id = ThreadId::try_from("not-a-uuid").unwrap();
    let stem = rollout_summary_file_stem_from_parts(thread_id, Utc::now(), None);
    // 验证使用 source_updated_at 而非 UUID 时间戳
}
```

3. **添加边界测试**:
```rust
#[test]
fn rollout_summary_file_stem_handles_very_long_slug() {
    let long_slug = "a".repeat(1000);
    let stem = rollout_summary_file_stem_from_parts(fixed_thread_id(), Utc::now(), Some(&long_slug));
    let slug = stem.strip_prefix(&format!("{FIXED_PREFIX}-")).unwrap();
    assert_eq!(slug.len(), 60);
}
```

4. **添加安全测试**:
```rust
#[test]
fn rollout_summary_file_stem_prevents_path_traversal() {
    let malicious_slug = Some("../../../etc/passwd");
    let stem = rollout_summary_file_stem_from_parts(fixed_thread_id(), Utc::now(), malicious_slug);
    assert!(!stem.contains("/"));
    assert!(!stem.contains(".."));
}
```

5. **使用属性测试**:
   - 使用 `proptest` 生成随机 slug
   - 验证清理函数的不变性

6. **添加性能测试**:
   - 测试大记忆集的重建性能
   - 测试并发同步性能
