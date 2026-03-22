# 010_move_overwrites_existing_destination 场景研究文档

## 场景与职责

### 场景定位

本场景（`010_move_overwrites_existing_destination`）是 `codex-apply-patch` 组件的集成测试用例之一，位于测试固件（test fixtures）目录中。该场景专门测试 **文件移动时目标位置已存在文件** 的边界情况。

### 目录结构

```
codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/
├── patch.txt          # 待应用的补丁文件
├── input/             # 应用补丁前的初始文件系统状态
│   ├── old/
│   │   ├── name.txt   # 源文件，内容为 "from"
│   │   └── other.txt  # 无关文件，内容为 "unrelated file"
│   └── renamed/
│       └── dir/
│           └── name.txt  # 目标位置已存在的文件，内容为 "existing"
└── expected/          # 应用补丁后的期望文件系统状态
    ├── old/
    │   └── other.txt  # 保持不变
    └── renamed/
        └── dir/
            └── name.txt  # 被覆盖后的文件，内容为 "new"
```

### 测试职责

该场景验证以下核心行为：

1. **Move 操作的目标覆盖语义**：当 `*** Move to:` 指定的目标路径已存在文件时，应静默覆盖（overwrite）而非报错
2. **原子性保证**：源文件应被正确删除，目标文件应包含更新后的内容
3. **无关文件保护**：未被补丁涉及的其他文件应保持不变

---

## 功能点目的

### 补丁语义解析

目标补丁文件 `patch.txt` 内容：

```
*** Begin Patch
*** Update File: old/name.txt
*** Move to: renamed/dir/name.txt
@@
-from
+new
*** End Patch
```

该补丁表达的操作意图：

| 组件 | 说明 |
|------|------|
| `*** Update File: old/name.txt` | 指定要更新的源文件 |
| `*** Move to: renamed/dir/name.txt` | 指定移动目标路径（已存在文件） |
| `@@` | 变更块（chunk）起始标记 |
| `-from` | 要删除的旧内容 |
| `+new` | 要添加的新内容 |

### 关键行为验证点

1. **覆盖语义**：目标路径 `renamed/dir/name.txt` 在 input 中已存在（内容为 `"existing"`），补丁应用后应被覆盖为 `"new"`
2. **源文件清理**：`old/name.txt` 应在移动后被删除
3. **内容变更**：文件内容应从 `"from"` 变更为 `"new"`（而非保留目标原有内容 `"existing"`）

---

## 具体技术实现

### 1. 补丁格式规范（Patch Format）

补丁格式由 `codex-rs/apply-patch/src/parser.rs` 定义，核心语法结构：

```ebnf
patch        := "*** Begin Patch" LF hunk+ "*** End Patch" LF?
hunk         := add_hunk | delete_hunk | update_hunk
add_hunk     := "*** Add File: " filename LF add_line+
delete_hunk  := "*** Delete File: " filename LF
update_hunk  := "*** Update File: " filename LF move_line? change+
move_line    := "*** Move to: " filename LF
change       := context_line? diff_line+ eof_line?
context_line := "@@" | "@@ " text LF
diff_line    := ("+" | "-" | " ") text LF
eof_line     := "*** End of File" LF
```

### 2. 核心数据结构

#### Hunk 枚举（`parser.rs` 第 58-76 行）

```rust
#[derive(Debug, PartialEq, Clone)]
pub enum Hunk {
    AddFile {
        path: PathBuf,
        contents: String,
    },
    DeleteFile {
        path: PathBuf,
    },
    UpdateFile {
        path: PathBuf,
        move_path: Option<PathBuf>,  // 本场景的关键字段
        chunks: Vec<UpdateFileChunk>,
    },
}
```

#### UpdateFileChunk 结构（`parser.rs` 第 90-104 行）

```rust
#[derive(Debug, PartialEq, Clone)]
pub struct UpdateFileChunk {
    pub change_context: Option<String>,  // 上下文定位（如 "@@ def f():"）
    pub old_lines: Vec<String>,          // 待替换的旧行
    pub new_lines: Vec<String>,          // 新行内容
    pub is_end_of_file: bool,            // 是否在文件末尾添加
}
```

### 3. 关键执行流程

#### 3.1 补丁应用主流程（`lib.rs` 第 279-339 行）

```rust
fn apply_hunks_to_files(hunks: &[Hunk]) -> anyhow::Result<AffectedPaths> {
    // ...
    for hunk in hunks {
        match hunk {
            // ...
            Hunk::UpdateFile { path, move_path, chunks } => {
                let AppliedPatch { new_contents, .. } = 
                    derive_new_contents_from_chunks(path, chunks)?;
                
                if let Some(dest) = move_path {
                    // 创建目标目录（如不存在）
                    if let Some(parent) = dest.parent()
                        && !parent.as_os_str().is_empty() 
                    {
                        std::fs::create_dir_all(parent)?;
                    }
                    // 写入目标文件（覆盖已存在文件）
                    std::fs::write(dest, new_contents)?;
                    // 删除源文件
                    std::fs::remove_file(path)?;
                    modified.push(dest.clone());
                } else {
                    // 普通更新（无移动）
                    std::fs::write(path, new_contents)?;
                    modified.push(path.clone());
                }
            }
        }
    }
}
```

**关键观察**：代码使用 `std::fs::write()` 直接写入目标文件，该操作在目标文件已存在时会**静默覆盖**，不会报错。这正是本场景测试的行为基础。

#### 3.2 内容变更计算（`lib.rs` 第 346-381 行）

```rust
fn derive_new_contents_from_chunks(
    path: &Path,
    chunks: &[UpdateFileChunk],
) -> Result<AppliedPatch, ApplyPatchError> {
    // 1. 读取源文件内容
    let original_contents = std::fs::read_to_string(path)?;
    
    // 2. 按行分割（处理末尾换行符）
    let mut original_lines: Vec<String> = 
        original_contents.split('\n').map(String::from).collect();
    if original_lines.last().is_some_and(String::is_empty) {
        original_lines.pop();
    }
    
    // 3. 计算替换区域
    let replacements = compute_replacements(&original_lines, path, chunks)?;
    
    // 4. 应用替换
    let new_lines = apply_replacements(original_lines, &replacements);
    
    // 5. 确保末尾换行符
    let mut new_lines = new_lines;
    if !new_lines.last().is_some_and(String::is_empty) {
        new_lines.push(String::new());
    }
    
    let new_contents = new_lines.join("\n");
    Ok(AppliedPatch { original_contents, new_contents })
}
```

#### 3.3 替换区域计算（`lib.rs` 第 386-474 行）

```rust
fn compute_replacements(
    original_lines: &[String],
    path: &Path,
    chunks: &[UpdateFileChunk],
) -> Result<Vec<(usize, usize, Vec<String>)>, ApplyPatchError> {
    let mut replacements: Vec<(usize, usize, Vec<String>)> = Vec::new();
    let mut line_index: usize = 0;

    for chunk in chunks {
        // 1. 使用上下文定位（如果提供）
        if let Some(ctx_line) = &chunk.change_context {
            if let Some(idx) = seek_sequence::seek_sequence(
                original_lines, 
                std::slice::from_ref(ctx_line), 
                line_index, 
                false
            ) {
                line_index = idx + 1;
            } else {
                return Err(ApplyPatchError::ComputeReplacements(
                    format!("Failed to find context '{}' in {}", ctx_line, path.display())
                ));
            }
        }

        // 2. 纯添加场景（无 old_lines）
        if chunk.old_lines.is_empty() {
            let insertion_idx = if original_lines.last().is_some_and(String::is_empty) {
                original_lines.len() - 1
            } else {
                original_lines.len()
            };
            replacements.push((insertion_idx, 0, chunk.new_lines.clone()));
            continue;
        }

        // 3. 查找 old_lines 在文件中的位置
        let mut pattern: &[String] = &chunk.old_lines;
        let mut found = seek_sequence::seek_sequence(
            original_lines, pattern, line_index, chunk.is_end_of_file
        );

        // 4. 处理末尾空行的容错匹配
        if found.is_none() && pattern.last().is_some_and(String::is_empty) {
            pattern = &pattern[..pattern.len() - 1];
            // ... 重试匹配
        }

        // 5. 记录替换区域
        if let Some(start_idx) = found {
            replacements.push((start_idx, pattern.len(), new_slice.to_vec()));
            line_index = start_idx + pattern.len();
        } else {
            return Err(/* 未找到匹配 */);
        }
    }

    replacements.sort_by(|(a, _, _), (b, _, _)| a.cmp(b));
    Ok(replacements)
}
```

### 4. 序列匹配算法（`seek_sequence.rs`）

`seek_sequence` 函数实现了模糊匹配逻辑，支持四级匹配严格度：

1. **精确匹配**：字节级完全相等
2. **右修剪匹配**：忽略行尾空白
3. **全修剪匹配**：忽略行首和行尾空白
4. **Unicode 规范化**：将特殊 Unicode 标点（如各种破折号、引号）归一化为 ASCII 等价物

```rust
pub(crate) fn seek_sequence(
    lines: &[String],
    pattern: &[String],
    start: usize,
    eof: bool,
) -> Option<usize> {
    // 边界检查
    if pattern.is_empty() { return Some(start); }
    if pattern.len() > lines.len() { return None; }

    // EOF 模式：优先从文件末尾开始匹配
    let search_start = if eof && lines.len() >= pattern.len() {
        lines.len() - pattern.len()
    } else {
        start
    };

    // 四级匹配尝试...
}
```

---

## 关键代码路径与文件引用

### 核心文件清单

| 文件路径 | 职责 | 相关行号 |
|---------|------|---------|
| `codex-rs/apply-patch/src/lib.rs` | 补丁应用核心逻辑 | 1-1000+ |
| `codex-rs/apply-patch/src/parser.rs` | 补丁格式解析器 | 1-763 |
| `codex-rs/apply-patch/src/seek_sequence.rs` | 模糊序列匹配 | 1-151 |
| `codex-rs/apply-patch/src/standalone_executable.rs` | CLI 入口 | 1-59 |
| `codex-rs/apply-patch/tests/suite/scenarios.rs` | 场景测试框架 | 1-126 |
| `codex-rs/apply-patch/tests/suite/tool.rs` | CLI 集成测试（含本场景的直接测试） | 154-175 |

### 关键代码路径

#### 路径 1：场景测试执行流

```
test_apply_patch_scenarios() [scenarios.rs:11]
  └── run_apply_patch_scenario(dir) [scenarios.rs:30]
        ├── copy_dir_recursive(input_dir, tmp.path()) [scenarios.rs:36]
        ├── fs::read_to_string(dir.join("patch.txt")) [scenarios.rs:40]
        ├── Command::new("apply_patch").arg(patch).current_dir(tmp.path()).output() [scenarios.rs:45-48]
        └── assert_eq!(actual_snapshot, expected_snapshot) [scenarios.rs:55-60]
```

#### 路径 2：补丁应用执行流

```
apply_patch(patch, stdout, stderr) [lib.rs:183]
  ├── parse_patch(patch) [lib.rs:188] → ApplyPatchArgs { hunks, ... }
  └── apply_hunks(&hunks, stdout, stderr) [lib.rs:210]
        └── apply_hunks_to_files(hunks) [lib.rs:248]
              └── for hunk in hunks:
                    └── match hunk:
                          └── UpdateFile { path, move_path: Some(dest), chunks } [lib.rs:306-325]
                                ├── derive_new_contents_from_chunks(path, chunks) [lib.rs:311]
                                ├── std::fs::create_dir_all(parent) [lib.rs:317]
                                ├── std::fs::write(dest, new_contents) [lib.rs:321]  ← 覆盖点
                                ├── std::fs::remove_file(path) [lib.rs:323]
                                └── modified.push(dest.clone()) [lib.rs:325]
```

#### 路径 3：补丁解析执行流

```
parse_patch(patch_text) [parser.rs:106]
  └── parse_patch_text(patch, mode) [parser.rs:154]
        ├── check_patch_boundaries_strict/lenient(&lines) [parser.rs:156-163]
        └── while !remaining_lines.is_empty():
              └── parse_one_hunk(remaining_lines, line_number) [parser.rs:172]
                    └── match first_line:
                          └── strip_prefix(UPDATE_FILE_MARKER) [parser.rs:279]
                                ├── parse move_path [parser.rs:285-291]
                                └── while parse_update_file_chunk() [parser.rs:308]
```

---

## 依赖与外部交互

### 内部依赖

| 依赖项 | 用途 | 版本来源 |
|-------|------|---------|
| `codex-utils-cargo-bin` | 测试中获取二进制路径 | workspace |

### 外部依赖

| Crate | 用途 | 版本 |
|-------|------|------|
| `anyhow` | 错误处理 | workspace |
| `similar` | 文本差异计算（unified diff 生成） | workspace |
| `thiserror` | 错误类型定义 | workspace |
| `tree-sitter` | Bash 脚本解析（用于 heredoc 提取） | workspace |
| `tree-sitter-bash` | Bash 语法支持 | workspace |

### 测试依赖

| Crate | 用途 |
|-------|------|
| `assert_cmd` | CLI 测试断言 |
| `assert_matches` | 模式匹配断言 |
| `pretty_assertions` | 美观的差异输出 |
| `tempfile` | 临时目录管理 |

### 系统交互

| 系统调用 | 用途 | 位置 |
|---------|------|------|
| `std::fs::write` | 写入/覆盖文件 | `lib.rs:321, 327` |
| `std::fs::remove_file` | 删除源文件 | `lib.rs:323` |
| `std::fs::create_dir_all` | 创建目标目录 | `lib.rs:317` |
| `std::fs::read_to_string` | 读取源文件 | `lib.rs:352` |

---

## 风险、边界与改进建议

### 当前风险点

#### 1. 静默覆盖风险（已接受的设计决策）

**现状**：`std::fs::write()` 在目标文件存在时会静默覆盖，不会保留原文件备份。

**潜在问题**：
- 用户可能意外丢失目标位置的已有文件内容
- 无法撤销（undo）覆盖操作

**缓解措施**：
- 该行为是设计意图（通过本场景测试显式确认）
- 建议用户在应用补丁前使用版本控制（git）

#### 2. 部分失败后的状态不一致

**场景 015**（`failure_after_partial_success_leaves_changes`）测试了此边界：

```rust
// 补丁包含两个操作：
// 1. Add File: created.txt （成功）
// 2. Update File: missing.txt （失败，文件不存在）
```

**现状**：第一个操作不会回滚，导致文件系统处于部分应用状态。

#### 3. 目录与文件冲突

**场景 012**（`delete_directory_fails`）测试：尝试删除目录会失败。

### 边界条件

| 边界条件 | 当前行为 | 测试覆盖 |
|---------|---------|---------|
| Move 目标已存在文件 | 静默覆盖 | ✅ 本场景 |
| Move 目标已存在目录 | `std::fs::write` 会失败（EISDIR） | ❌ 未明确测试 |
| Add 目标已存在文件 | 静默覆盖 | ✅ 场景 011 |
| 源文件在更新过程中被修改 | 基于初始状态计算替换 | ⚠️ 无并发控制 |
| 补丁包含多个 hunks | 顺序应用，失败时部分生效 | ✅ 场景 015 |

### 改进建议

#### 1. 添加覆盖确认机制（可选）

```rust
// 建议添加的配置选项
pub enum OverwritePolicy {
    Silent,      // 当前行为
    Warn,        // 打印警告但继续
    Error,       // 报错并中止
    Backup,      // 创建 .bak 备份
}
```

#### 2. 原子性增强

考虑使用临时文件 + 原子重命名模式：

```rust
// 伪代码
let temp_path = dest.with_extension("tmp");
std::fs::write(&temp_path, new_contents)?;
std::fs::rename(&temp_path, dest)?;  // 原子操作
```

#### 3. 事务性应用

对于包含多个 hunks 的补丁，考虑：
- 预验证阶段：检查所有文件存在性和可匹配性
- 或提供 `--dry-run` 模式预览变更

#### 4. 增强测试覆盖

建议添加以下边界测试：

```rust
// 1. Move 目标为目录的情况
#[test]
fn test_move_to_existing_directory_fails() { /* ... */ }

// 2. Move 跨文件系统（不同挂载点）
#[test]
fn test_move_across_filesystems() { /* ... */ }

// 3. 权限不足场景
#[test]
fn test_move_permission_denied() { /* ... */ }
```

### 相关测试矩阵

| 场景 ID | 名称 | 测试目的 | 与本场景关系 |
|--------|------|---------|-------------|
| 004 | move_to_new_directory | Move 到全新目录 | 基础功能 |
| 010 | **move_overwrites_existing_destination** | **Move 覆盖已存在文件** | **本场景** |
| 011 | add_overwrites_existing_file | Add 覆盖已存在文件 | 类似行为 |
| 015 | failure_after_partial_success | 部分失败处理 | 错误处理 |

---

## 总结

`010_move_overwrites_existing_destination` 场景是 `codex-apply-patch` 组件中验证 **Move 操作覆盖语义** 的关键测试用例。它确保当补丁尝试将文件移动到已存在目标位置时，系统能够：

1. 正确应用内容变更（`"from"` → `"new"`）
2. 静默覆盖目标位置的现有文件（`"existing"` 被替换）
3. 清理源文件（`old/name.txt` 被删除）
4. 保持无关文件不变（`old/other.txt` 保留）

该行为基于 Rust 标准库 `std::fs::write()` 的覆盖语义，是设计上的有意选择，但用户应注意这可能导致目标位置原有数据的不可恢复丢失。
