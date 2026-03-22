# Research: multi.txt in 003_multiple_chunks Test Scenario

## 1. 场景与职责

### 1.1 文件定位

**目标文件**: `codex-rs/apply-patch/tests/fixtures/scenarios/003_multiple_chunks/input/multi.txt`

这是一个测试夹具（test fixture）文件，用于 `apply-patch` 模块的端到端场景测试。该文件作为测试输入，验证 apply-patch 工具处理**单个文件中多个修改块（multiple chunks）**的能力。

### 1.2 测试场景结构

```
codex-rs/apply-patch/tests/fixtures/scenarios/003_multiple_chunks/
├── input/
│   └── multi.txt          # 原始文件内容（本研究对象）
├── expected/
│   └── multi.txt          # 期望的最终文件内容
└── patch.txt              # 应用的补丁
```

### 1.3 文件内容

**input/multi.txt**:
```
line1
line2
line3
line4
```

**expected/multi.txt**:
```
line1
changed2
line3
changed4
```

**patch.txt**:
```
*** Begin Patch
*** Update File: multi.txt
@@
-line2
+changed2
@@
-line4
+changed4
*** End Patch
```

### 1.4 测试目的

此场景验证以下核心能力：
1. **多 chunk 更新**: 单个 `*** Update File` 操作可以包含多个 `@@` 开头的修改块
2. **非连续行修改**: 可以在文件的不同位置（line2 和 line4）分别进行修改
3. **正确合并**: 多个修改块应该被正确合并应用到同一个文件中

---

## 2. 功能点目的

### 2.1 Multiple Chunks 功能概述

在 apply-patch 的补丁格式中，一个 `Update File` 操作可以包含多个修改块（chunks）。每个 chunk 以 `@@` 开头，可以包含：
- 可选的上下文标识（如 `@@ class MyClass`）
- 删除行（以 `-` 开头）
- 添加行（以 `+` 开头）
- 上下文行（以空格开头）

### 2.2 为什么需要 Multiple Chunks

1. **效率**: 避免为同一文件的多个不连续修改创建多个独立的 Update File 操作
2. **原子性**: 确保多个修改作为一个整体成功或失败
3. **可读性**: 将相关修改组织在一起，便于审查

### 2.3 本测试的具体验证点

| 验证点 | 说明 |
|--------|------|
| Chunk 1 | 将 `line2` 替换为 `changed2` |
| Chunk 2 | 将 `line4` 替换为 `changed4` |
| 结果验证 | 文件最终包含 4 行，其中第 2、4 行被修改 |

---

## 3. 具体技术实现

### 3.1 补丁解析流程

#### 3.1.1 入口点

```rust
// codex-rs/apply-patch/src/lib.rs
pub fn apply_patch(
    patch: &str,
    stdout: &mut impl std::io::Write,
    stderr: &mut impl std::io::Write,
) -> Result<(), ApplyPatchError> {
    let hunks = match parse_patch(patch) { ... };
    apply_hunks(&hunks, stdout, stderr)?;
    Ok(())
}
```

#### 3.1.2 解析器核心逻辑

```rust
// codex-rs/apply-patch/src/parser.rs
pub fn parse_patch(patch: &str) -> Result<ApplyPatchArgs, ParseError> {
    let mode = if PARSE_IN_STRICT_MODE { ParseMode::Strict } else { ParseMode::Lenient };
    parse_patch_text(patch, mode)
}
```

#### 3.1.3 Update File Hunk 解析

```rust
// codex-rs/apply-patch/src/parser.rs:279-332
fn parse_one_hunk(...) -> Result<(Hunk, usize), ParseError> {
    // ... 解析 *** Update File: <path>
    let mut chunks = Vec::new();
    while !remaining_lines.is_empty() {
        // 跳过空行
        if remaining_lines[0].trim().is_empty() { ... }
        // 遇到下一个 hunk 头时停止
        if remaining_lines[0].starts_with("***") { break; }
        
        // 解析单个 chunk
        let (chunk, chunk_lines) = parse_update_file_chunk(...)?;
        chunks.push(chunk);
        // ...
    }
    // ...
}
```

### 3.2 关键数据结构

#### 3.2.1 Hunk 枚举

```rust
// codex-rs/apply-patch/src/parser.rs:58-76
pub enum Hunk {
    AddFile { path: PathBuf, contents: String },
    DeleteFile { path: PathBuf },
    UpdateFile {
        path: PathBuf,
        move_path: Option<PathBuf>,
        chunks: Vec<UpdateFileChunk>,  // <-- 多个 chunks
    },
}
```

#### 3.2.2 UpdateFileChunk 结构

```rust
// codex-rs/apply-patch/src/parser.rs:90-104
pub struct UpdateFileChunk {
    /// 上下文标识（如类名、函数名）
    pub change_context: Option<String>,
    /// 要替换的旧行
    pub old_lines: Vec<String>,
    /// 新行
    pub new_lines: Vec<String>,
    /// 是否标记为文件末尾
    pub is_end_of_file: bool,
}
```

### 3.3 补丁应用流程

#### 3.3.1 计算替换

```rust
// codex-rs/apply-patch/src/lib.rs:386-474
fn compute_replacements(
    original_lines: &[String],
    path: &Path,
    chunks: &[UpdateFileChunk],
) -> Result<Vec<(usize, usize, Vec<String>)>, ApplyPatchError> {
    let mut replacements: Vec<(usize, usize, Vec<String>)> = Vec::new();
    let mut line_index: usize = 0;

    for chunk in chunks {
        // 1. 使用 seek_sequence 定位上下文
        if let Some(ctx_line) = &chunk.change_context {
            line_index = seek_sequence::seek_sequence(...) + 1;
        }
        
        // 2. 定位 old_lines
        let pattern = &chunk.old_lines;
        let found = seek_sequence::seek_sequence(original_lines, pattern, line_index, chunk.is_end_of_file);
        
        // 3. 记录替换
        if let Some(start_idx) = found {
            replacements.push((start_idx, pattern.len(), new_slice.to_vec()));
            line_index = start_idx + pattern.len();
        }
    }
    
    // 按索引排序，确保替换顺序正确
    replacements.sort_by(|(lhs_idx, _, _), (rhs_idx, _, _)| lhs_idx.cmp(rhs_idx));
    Ok(replacements)
}
```

#### 3.3.2 应用替换

```rust
// codex-rs/apply-patch/src/lib.rs:478-502
fn apply_replacements(
    mut lines: Vec<String>,
    replacements: &[(usize, usize, Vec<String>)],
) -> Vec<String> {
    // 从后往前应用替换，避免索引偏移问题
    for (start_idx, old_len, new_segment) in replacements.iter().rev() {
        // 删除旧行
        for _ in 0..*old_len {
            if *start_idx < lines.len() { lines.remove(*start_idx); }
        }
        // 插入新行
        for (offset, new_line) in new_segment.iter().enumerate() {
            lines.insert(*start_idx + offset, new_line.clone());
        }
    }
    lines
}
```

### 3.4 序列搜索算法

```rust
// codex-rs/apply-patch/src/seek_sequence.rs:12-110
pub(crate) fn seek_sequence(
    lines: &[String],
    pattern: &[String],
    start: usize,
    eof: bool,
) -> Option<usize> {
    // 1. 空模式直接返回 start
    if pattern.is_empty() { return Some(start); }
    // 2. 模式比输入长，返回 None
    if pattern.len() > lines.len() { return None; }
    
    // 3. 确定搜索起始位置
    let search_start = if eof && lines.len() >= pattern.len() {
        lines.len() - pattern.len()  // 从文件末尾开始
    } else {
        start
    };
    
    // 4. 多轮匹配尝试（从严格到宽松）
    //    - 精确匹配
    //    - 忽略行尾空白
    //    - 忽略首尾空白
    //    - Unicode 标点符号归一化（如 EN DASH → ASCII -）
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 测试执行路径

```
test_apply_patch_scenarios() 
  └─→ codex-rs/apply-patch/tests/suite/scenarios.rs:11
      └─→ run_apply_patch_scenario()
          ├─→ 复制 input/ 到临时目录
          ├─→ 读取 patch.txt
          ├─→ 执行 apply_patch 二进制
          └─→ 比较实际输出与 expected/
```

### 4.2 核心代码文件

| 文件 | 职责 |
|------|------|
| `src/lib.rs` | 补丁应用主逻辑，包含 `apply_patch()`, `apply_hunks()`, `compute_replacements()`, `apply_replacements()` |
| `src/parser.rs` | 补丁格式解析器，包含 `parse_patch()`, `parse_one_hunk()`, `parse_update_file_chunk()` |
| `src/seek_sequence.rs` | 行序列搜索算法，支持模糊匹配 |
| `src/standalone_executable.rs` | CLI 入口，`run_main()` |
| `src/invocation.rs` | Shell 命令解析，支持 heredoc 形式 |

### 4.3 相关测试代码

| 文件 | 测试内容 |
|------|----------|
| `tests/suite/scenarios.rs` | 场景测试框架，`test_apply_patch_scenarios()` |
| `tests/suite/tool.rs:45-62` | `test_apply_patch_cli_applies_multiple_chunks()` - 相同逻辑的代码测试 |
| `src/lib.rs:676-710` | `test_multiple_update_chunks_apply_to_single_file()` - 单元测试 |

---

## 5. 依赖与外部交互

### 5.1 内部依赖

```
codex-apply-patch
├── codex-utils-cargo-bin (dev)  # 测试时定位二进制文件
├── anyhow                       # 错误处理
├── similar                      # 文本差异计算（unified diff）
├── thiserror                    # 错误派生宏
├── tree-sitter                  # Bash 脚本解析
└── tree-sitter-bash
```

### 5.2 外部工具交互

| 工具 | 用途 |
|------|------|
| `apply_patch` 二进制 | 被测试调用的 CLI 工具 |
| `tempfile` crate | 创建临时目录进行隔离测试 |

### 5.3 与其他模块的关系

```
codex-rs/
├── apply-patch/          # 本模块：独立的补丁应用工具
├── core/                 # 可能通过 invocation 调用 apply-patch
└── ...
```

`apply-patch` 设计为可独立运行的工具，同时也可作为库被其他 Rust 代码使用。

---

## 6. 风险、边界与改进建议

### 6.1 当前风险点

#### 6.1.1 部分成功问题

当前实现按顺序应用 hunks，如果中间失败，前面已应用的修改不会回滚：

```rust
// src/lib.rs:287-338
for hunk in hunks {
    match hunk {
        Hunk::AddFile { ... } => { ... }  // 如果这里成功
        Hunk::UpdateFile { ... } => { ... }  // 但这里失败，前面的添加不会回滚
    }
}
```

场景 `015_failure_after_partial_success_leaves_changes` 正是测试此行为。

#### 6.1.2 Chunk 顺序依赖

Chunks 必须按文件中出现的顺序排列，否则可能定位失败：

```rust
// compute_replacements 中 line_index 是递增的
line_index = start_idx + pattern.len();  // 只能向前搜索
```

#### 6.1.3 重复行匹配歧义

如果文件中有重复的行模式（如多个空行），`seek_sequence` 可能匹配到错误位置。

### 6.2 边界情况

| 场景 | 当前行为 |
|------|----------|
| 空 chunk | 解析错误："Update file hunk for path 'x' is empty" |
| 重叠 chunks | 后应用的替换可能基于已修改的内容，导致意外结果 |
| 空 old_lines（纯添加）| 支持，在文件末尾或指定上下文后添加 |
| 文件末尾标记 `*** End of File` | 支持，确保添加发生在文件末尾 |

### 6.3 改进建议

#### 6.3.1 事务性应用

```rust
// 建议：先计算所有修改，验证可行性后再应用
fn apply_hunks_atomically(hunks: &[Hunk]) -> Result<()> {
    // 1. 预计算所有替换
    // 2. 验证无冲突
    // 3. 原子性应用（或创建备份以便回滚）
}
```

#### 6.3.2 Chunk 冲突检测

```rust
// 在 compute_replacements 中添加
for i in 0..replacements.len() {
    for j in (i+1)..replacements.len() {
        if replacements[i].overlaps(&replacements[j]) {
            return Err(ApplyPatchError::OverlappingChunks);
        }
    }
}
```

#### 6.3.3 增强模糊匹配

当前 `seek_sequence` 支持 Unicode 归一化，但可以考虑：
- 支持正则表达式匹配
- 支持行号提示（如 `@@ line 42`）

### 6.4 测试覆盖建议

| 建议添加的测试 | 说明 |
|----------------|------|
| 重叠 chunks 测试 | 验证当前行为并考虑是否应报错 |
| 逆序 chunks 测试 | chunks 按文件倒序排列时的行为 |
| 大量 chunks 测试 | 单个文件包含数十个 chunks 的性能 |
| 二进制文件测试 | 当前仅支持文本文件，应明确拒绝二进制文件 |

---

## 7. 总结

`multi.txt` 是 `003_multiple_chunks` 测试场景的核心输入文件，用于验证 apply-patch 工具处理**单个文件中多个不连续修改块**的能力。该测试覆盖了：

1. **解析层**: 验证 `parser.rs` 能正确解析包含多个 `@@` chunk 的 Update File 操作
2. **应用层**: 验证 `lib.rs` 中的 `compute_replacements` 和 `apply_replacements` 能正确合并多个修改
3. **集成层**: 验证从 CLI 到文件系统的端到端流程

此功能是 apply-patch 工具的核心能力之一，使得 LLM 可以在一次操作中完成文件的多处修改，提高效率并保证原子性。
