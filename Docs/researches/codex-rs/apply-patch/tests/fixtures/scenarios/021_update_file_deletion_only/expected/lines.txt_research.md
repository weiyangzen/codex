# 研究文档：021_update_file_deletion_only 测试场景

## 文件位置

- **目标文件**: `codex-rs/apply-patch/tests/fixtures/scenarios/021_update_file_deletion_only/expected/lines.txt`
- **场景目录**: `codex-rs/apply-patch/tests/fixtures/scenarios/021_update_file_deletion_only/`

---

## 1. 场景与职责

### 1.1 测试场景概述

`021_update_file_deletion_only` 是 `apply-patch` 工具的一个端到端测试场景，专门用于验证**仅删除行**的文件更新操作。该场景测试的核心功能是：通过 patch 格式删除文件中的特定行，同时保留其他行不变。

### 1.2 测试结构

该场景遵循标准的三部分结构：

```
021_update_file_deletion_only/
├── input/
│   └── lines.txt          # 原始文件内容（3行）
├── expected/
│   └── lines.txt          # 预期结果（2行）
└── patch.txt              # 补丁定义
```

### 1.3 数据流

| 文件 | 内容 | 说明 |
|------|------|------|
| `input/lines.txt` | `line1\nline2\nline3\n` | 原始文件，包含3行 |
| `patch.txt` | 删除 `line2` 的指令 | 使用 `-line2` 语法标记删除 |
| `expected/lines.txt` | `line1\nline3\n` | 预期结果，`line2` 被删除 |

---

## 2. 功能点目的

### 2.1 核心功能验证

此测试场景验证以下关键功能：

1. **行级删除操作**: 验证 patch 格式中 `-` 前缀能够正确删除匹配的行
2. **上下文保留**: 验证删除操作不会影响到其他未标记的行
3. **文件完整性**: 验证删除后文件仍保持正确的换行符结构

### 2.2 Patch 格式解析

该场景使用的 patch 格式：

```
*** Begin Patch
*** Update File: lines.txt
@@
 line1
-line2
 line3
*** End Patch
```

格式说明：
- `*** Begin Patch` / `*** End Patch`: Patch 起止标记
- `*** Update File: <path>`: 指定要更新的文件路径
- `@@`: 变更块（chunk）的起始标记，表示新的变更上下文
- ` line1`: 空格前缀表示上下文行（保留不变）
- `-line2`: 减号前缀表示要删除的行
- ` line3`: 上下文行（保留不变）

### 2.3 与其他场景的对比

| 场景编号 | 场景名称 | 测试重点 |
|----------|----------|----------|
| 001 | add_file | 验证文件创建 |
| 020 | delete_file_success | 验证整文件删除 |
| **021** | **update_file_deletion_only** | **验证行级删除** |
| 022 | update_file_end_of_file_marker | 验证 EOF 标记处理 |

---

## 3. 具体技术实现

### 3.1 关键流程

#### 3.1.1 测试执行流程

测试执行遵循 `scenarios.rs` 中定义的流程：

```rust
// tests/suite/scenarios.rs
fn run_apply_patch_scenario(dir: &Path) -> anyhow::Result<()> {
    let tmp = tempdir()?;
    
    // 1. 复制 input 文件到临时目录
    copy_dir_recursive(&input_dir, tmp.path())?;
    
    // 2. 读取 patch.txt
    let patch = fs::read_to_string(dir.join("patch.txt"))?;
    
    // 3. 执行 apply_patch 命令
    Command::new(cargo_bin("apply_patch")?)
        .arg(patch)
        .current_dir(tmp.path())
        .output()?;
    
    // 4. 比较实际结果与 expected 目录
    let expected_snapshot = snapshot_dir(&expected_dir)?;
    let actual_snapshot = snapshot_dir(tmp.path())?;
    assert_eq!(actual_snapshot, expected_snapshot);
}
```

#### 3.1.2 Patch 解析流程

`parser.rs` 中的解析逻辑：

```rust
// src/parser.rs
fn parse_update_file_chunk(...) -> Result<(UpdateFileChunk, usize), ParseError> {
    // 解析 @@ 上下文标记
    let (change_context, start_index) = if lines[0] == EMPTY_CHANGE_CONTEXT_MARKER {
        (None, 1)
    } else if let Some(context) = lines[0].strip_prefix(CHANGE_CONTEXT_MARKER) {
        (Some(context.to_string()), 1)
    }
    
    // 解析每一行的前缀
    for line in &lines[start_index..] {
        match line_contents.chars().next() {
            Some(' ') => { /* 上下文行 */ }
            Some('+') => { /* 新增行 */ }
            Some('-') => { /* 删除行 */ }
        }
    }
}
```

### 3.2 数据结构

#### 3.2.1 Hunk 枚举

```rust
// src/parser.rs
pub enum Hunk {
    AddFile { path: PathBuf, contents: String },
    DeleteFile { path: PathBuf },
    UpdateFile {
        path: PathBuf,
        move_path: Option<PathBuf>,
        chunks: Vec<UpdateFileChunk>,
    },
}
```

#### 3.2.2 UpdateFileChunk 结构

```rust
// src/parser.rs
pub struct UpdateFileChunk {
    pub change_context: Option<String>,  // @@ 后的上下文描述
    pub old_lines: Vec<String>,          // 要删除的行（以 - 标记）
    pub new_lines: Vec<String>,          // 要新增的行（以 + 标记）
    pub is_end_of_file: bool,            // 是否到达文件末尾
}
```

对于本场景的 patch，`UpdateFileChunk` 将被填充为：
- `change_context`: `None`（@@ 后无额外上下文）
- `old_lines`: `["line2"]`（带 `-` 前缀的行）
- `new_lines`: `[]`（无新增行）
- `is_end_of_file`: `false`

### 3.3 行匹配与替换算法

#### 3.3.1 计算替换位置

`lib.rs` 中的 `compute_replacements` 函数：

```rust
// src/lib.rs
fn compute_replacements(
    original_lines: &[String],
    path: &Path,
    chunks: &[UpdateFileChunk],
) -> Result<Vec<(usize, usize, Vec<String>)>, ApplyPatchError> {
    for chunk in chunks {
        // 1. 寻找 old_lines 在原始文件中的位置
        let found = seek_sequence::seek_sequence(
            original_lines,
            pattern,      // ["line2"]
            line_index,
            chunk.is_end_of_file,
        );
        
        // 2. 记录替换操作 (起始索引, 旧行数, 新行内容)
        if let Some(start_idx) = found {
            replacements.push((start_idx, pattern.len(), new_slice.to_vec()));
        }
    }
}
```

#### 3.3.2 序列匹配算法

`seek_sequence.rs` 实现了模糊匹配逻辑：

```rust
// src/seek_sequence.rs
pub(crate) fn seek_sequence(
    lines: &[String],
    pattern: &[String],
    start: usize,
    eof: bool,
) -> Option<usize> {
    // 1. 精确匹配
    // 2. 忽略尾部空白匹配
    // 3. 忽略首尾空白匹配
    // 4. Unicode 标点符号归一化（如将中文破折号转为 ASCII 减号）
}
```

### 3.4 应用替换

```rust
// src/lib.rs
fn apply_replacements(
    mut lines: Vec<String>,
    replacements: &[(usize, usize, Vec<String>)],
) -> Vec<String> {
    // 从后向前应用替换，避免索引偏移问题
    for (start_idx, old_len, new_segment) in replacements.iter().rev() {
        // 删除旧行
        for _ in 0..old_len {
            lines.remove(start_idx);
        }
        // 插入新行
        for (offset, new_line) in new_segment.iter().enumerate() {
            lines.insert(start_idx + offset, new_line.clone());
        }
    }
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心文件

| 文件路径 | 职责 |
|----------|------|
| `codex-rs/apply-patch/src/lib.rs` | 主库逻辑，包含 `apply_patch`、`apply_hunks`、`compute_replacements`、`apply_replacements` |
| `codex-rs/apply-patch/src/parser.rs` | Patch 格式解析器，定义 `Hunk`、`UpdateFileChunk` 等数据结构 |
| `codex-rs/apply-patch/src/seek_sequence.rs` | 模糊行匹配算法，支持 Unicode 归一化 |
| `codex-rs/apply-patch/src/invocation.rs` | Shell 命令解析，支持 heredoc 格式 |
| `codex-rs/apply-patch/src/main.rs` | CLI 入口 |

### 4.2 测试相关文件

| 文件路径 | 职责 |
|----------|------|
| `codex-rs/apply-patch/tests/suite/scenarios.rs` | 场景测试框架，`run_apply_patch_scenario` 函数 |
| `codex-rs/apply-patch/tests/suite/cli.rs` | CLI 集成测试 |
| `codex-rs/apply-patch/tests/suite/tool.rs` | 工具行为测试 |
| `codex-rs/apply-patch/tests/fixtures/scenarios/README.md` | 场景测试规范文档 |

### 4.3 关键函数调用链

```
test_apply_patch_scenarios (scenarios.rs)
  └── run_apply_patch_scenario
        ├── copy_dir_recursive (复制 input 到临时目录)
        ├── Command::new("apply_patch").arg(patch).output()
        │     └── codex_apply_patch::main (main.rs)
        │           └── apply_patch (lib.rs)
        │                 ├── parse_patch (parser.rs)
        │                 │     └── parse_update_file_chunk
        │                 └── apply_hunks
        │                       └── apply_hunks_to_files
        │                             └── derive_new_contents_from_chunks
        │                                   ├── compute_replacements
        │                                   │     └── seek_sequence::seek_sequence
        │                                   └── apply_replacements
        └── snapshot_dir (比较 expected 与实际结果)
```

---

## 5. 依赖与外部交互

### 5.1 内部依赖

| 依赖 | 用途 |
|------|------|
| `codex-utils-cargo-bin` | 测试中获取二进制文件路径 |

### 5.2 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `anyhow` | 错误处理 |
| `similar` | 文本差异计算（生成 unified diff） |
| `thiserror` | 自定义错误类型 |
| `tree-sitter` / `tree-sitter-bash` | Shell heredoc 解析 |
| `tempfile` | 测试临时目录 |
| `assert_cmd` | CLI 测试断言 |
| `pretty_assertions` | 美观的测试失败输出 |

### 5.3 系统交互

- **文件系统操作**: `std::fs::read_to_string`, `std::fs::write`, `std::fs::remove_file`
- **进程执行**: 通过 `Command` 执行 `apply_patch` 二进制文件

---

## 6. 风险、边界与改进建议

### 6.1 潜在风险

#### 6.1.1 行匹配模糊性

当前 `seek_sequence` 实现了多级模糊匹配（精确匹配 → 忽略尾部空白 → 忽略首尾空白 → Unicode 归一化）。虽然提高了容错性，但可能导致意外匹配：

```rust
// 如果文件中有多个相同的 "line2" 行
line1
line2  // 第一个匹配
line2  // 第二个匹配（可能被错误匹配）
line3
```

**建议**: 对于删除操作，如果找到多个匹配位置，应发出警告或要求更精确的上下文。

#### 6.1.2 部分失败后的状态一致性

`apply_hunks_to_files` 按顺序应用 hunk，如果中间失败，前面的修改已经生效。虽然场景 `015_failure_after_partial_success_leaves_changes` 测试了这种行为，但在生产环境中可能需要事务性支持。

### 6.2 边界情况

| 边界情况 | 当前行为 | 测试覆盖 |
|----------|----------|----------|
| 删除最后一行 | 支持（通过 `is_end_of_file` 标记） | 场景 022 |
| 删除不存在的行 | 报错 "Failed to find expected lines" | 场景 006 |
| 空文件更新 | 报错 "Update file hunk is empty" | 场景 008 |
| 删除文件的所有行 | 结果为空文件（保留文件） | 未明确覆盖 |
| Unicode 内容 | 支持（通过 `seek_sequence` 的归一化） | 场景 019 |

### 6.3 改进建议

#### 6.3.1 增强诊断信息

当前删除失败时的错误信息：
```
Failed to find expected lines in lines.txt:
line2
```

建议增加行号提示：
```
Failed to find expected lines in lines.txt (around line 2):
  Context: line1
  Expected: -line2
  Actual: +lineX
```

#### 6.3.2 支持批量删除

当前 patch 格式对于大量不连续行的删除需要多个 chunk：

```
@@
 line1
-line2
 line3
@@
 line3
-line4
 line5
```

建议支持通配符或范围语法：
```
@@
 line1
-line2
-line4
 line5
```

#### 6.3.3 原子性保证

对于包含多个文件操作的 patch，建议实现预检机制：

```rust
fn validate_all_hunks(hunks: &[Hunk]) -> Result<(), ApplyPatchError> {
    for hunk in hunks {
        // 预检所有文件是否存在、所有上下文行是否匹配
    }
}
```

### 6.4 相关测试场景建议

建议新增以下测试场景：

1. **删除文件首行**: 验证 `@@` 后直接跟 `-` 行的场景
2. **删除文件所有行**: 验证保留空文件的行为
3. **删除重复行**: 验证多个相同内容行的精确匹配
4. **大文件删除性能**: 验证在万行级文件中的删除性能

---

## 7. 总结

`021_update_file_deletion_only` 是一个基础但关键的测试场景，它验证了 `apply-patch` 工具最核心的行级删除功能。该场景通过简洁的三行文件结构，清晰地展示了 patch 格式的工作原理：

1. **输入**: 3 行文本
2. **操作**: 删除中间行
3. **输出**: 2 行文本

该测试的成功执行依赖于：
- 正确的 patch 格式解析（`parser.rs`）
- 精确的行匹配算法（`seek_sequence.rs`）
- 正确的替换应用逻辑（`lib.rs`）

理解此场景有助于深入理解整个 `apply-patch` 工具的设计哲学：**简单、明确、可预测**的文件操作抽象。
