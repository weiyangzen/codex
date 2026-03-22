# Research Document: `new.txt` in 002_multiple_operations Test Scenario

## 1. 场景与职责

### 1.1 文件定位

- **目标文件**: `codex-rs/apply-patch/tests/fixtures/scenarios/002_multiple_operations/expected/nested/new.txt`
- **文件内容**: `created`（单行文本，无换行符后缀）
- **所属测试场景**: `002_multiple_operations` - 多操作组合测试场景

### 1.2 测试场景结构

```
002_multiple_operations/
├── input/
│   ├── modify.txt      # 初始内容: "line1\nline2\n"
│   └── delete.txt      # 初始内容: "obsolete\n"
├── expected/
│   ├── modify.txt      # 期望内容: "line1\nchanged\n"
│   └── nested/
│       └── new.txt     # 期望内容: "created"（本研究对象）
└── patch.txt           # 补丁定义
```

### 1.3 职责概述

`new.txt` 是本测试场景中的**预期输出文件**，用于验证 `apply_patch` 工具在执行**添加文件操作**时的正确性。该文件位于嵌套目录 `nested/` 下，测试工具是否能自动创建不存在的父目录结构。

---

## 2. 功能点目的

### 2.1 测试的核心功能点

本场景测试 `apply_patch` 的**多操作原子性组合**能力，具体包括：

1. **Add File 操作**: 在嵌套路径 `nested/new.txt` 创建新文件
2. **Delete File 操作**: 删除已存在的 `delete.txt`
3. **Update File 操作**: 修改 `modify.txt` 的特定行

### 2.2 new.txt 的具体验证目标

| 验证点 | 说明 |
|--------|------|
| 文件创建 | 验证 `*** Add File:` 操作能正确创建文件 |
| 嵌套目录自动创建 | 验证父目录 `nested/` 不存在时能自动创建 |
| 内容正确性 | 验证文件内容严格匹配 `+created` 行 |
| 换行符处理 | 验证添加的行自动附加换行符（`+created` → `created\n`） |

### 2.3 对应 Patch 定义

```text
*** Begin Patch
*** Add File: nested/new.txt
+created
*** Delete File: delete.txt
*** Update File: modify.txt
@@
-line2
+changed
*** End Patch
```

---

## 3. 具体技术实现

### 3.1 补丁格式规范（Patch Grammar）

根据 `apply_patch_tool_instructions.md`，补丁遵循以下文法：

```ebnf
Patch         := Begin { FileOp } End
Begin         := "*** Begin Patch" NEWLINE
End           := "*** End Patch" NEWLINE
FileOp        := AddFile | DeleteFile | UpdateFile
AddFile       := "*** Add File: " path NEWLINE { "+" line NEWLINE }
DeleteFile    := "*** Delete File: " path NEWLINE
UpdateFile    := "*** Update File: " path NEWLINE [ MoveTo ] { Hunk }
MoveTo        := "*** Move to: " newPath NEWLINE
Hunk          := "@@" [ header ] NEWLINE { HunkLine } [ "*** End of File" NEWLINE ]
HunkLine      := (" " | "-" | "+") text NEWLINE
```

### 3.2 Add File 操作的解析逻辑

**源码位置**: `codex-rs/apply-patch/src/parser.rs:251-270`

```rust
if let Some(path) = first_line.strip_prefix(ADD_FILE_MARKER) {
    // Add File
    let mut contents = String::new();
    let mut parsed_lines = 1;
    for add_line in &lines[1..] {
        if let Some(line_to_add) = add_line.strip_prefix('+') {
            contents.push_str(line_to_add);
            contents.push('\n');  // 自动添加换行符
            parsed_lines += 1;
        } else {
            break;
        }
    }
    return Ok((
        AddFile {
            path: PathBuf::from(path),
            contents,
        },
        parsed_lines,
    ));
}
```

**关键行为**:
- 每行以 `+` 开头的内容被提取并追加换行符
- 遇到不以 `+` 开头的行时停止解析（表示进入下一个 hunk）

### 3.3 文件系统写入逻辑

**源码位置**: `codex-rs/apply-patch/src/lib.rs:288-300`

```rust
Hunk::AddFile { path, contents } => {
    // 自动创建父目录
    if let Some(parent) = path.parent()
        && !parent.as_os_str().is_empty()
    {
        std::fs::create_dir_all(parent).with_context(|| {
            format!("Failed to create parent directories for {}", path.display())
        })?;
    }
    // 写入文件内容
    std::fs::write(path, contents)
        .with_context(|| format!("Failed to write file {}", path.display()))?;
    added.push(path.clone());
}
```

**关键行为**:
- 使用 `create_dir_all` 递归创建不存在的父目录
- 使用 `std::fs::write` 原子写入文件内容

### 3.4 数据结构定义

**Hunk 枚举** (`parser.rs:58-76`):

```rust
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
        move_path: Option<PathBuf>,
        chunks: Vec<UpdateFileChunk>,
    },
}
```

**UpdateFileChunk 结构** (`parser.rs:90-104`):

```rust
pub struct UpdateFileChunk {
    pub change_context: Option<String>,  // @@ 后的上下文标识
    pub old_lines: Vec<String>,          // 以 - 开头的行
    pub new_lines: Vec<String>,          // 以 + 开头的行
    pub is_end_of_file: bool,            // 是否以 *** End of File 结尾
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心实现文件

| 文件路径 | 职责 |
|----------|------|
| `codex-rs/apply-patch/src/lib.rs` | 主库逻辑，包含 `apply_patch()` 和 `apply_hunks_to_files()` |
| `codex-rs/apply-patch/src/parser.rs` | 补丁解析器，将文本补丁解析为 `Hunk` 结构 |
| `codex-rs/apply-patch/src/seek_sequence.rs` | 行序列匹配算法（用于 Update 操作） |
| `codex-rs/apply-patch/src/standalone_executable.rs` | CLI 入口，处理 stdin/参数输入 |
| `codex-rs/apply-patch/src/invocation.rs` | Shell 调用解析（heredoc、bash -lc 等） |

### 4.2 测试相关文件

| 文件路径 | 职责 |
|----------|------|
| `codex-rs/apply-patch/tests/suite/scenarios.rs` | 场景测试框架，`run_apply_patch_scenario()` 函数 |
| `codex-rs/apply-patch/tests/suite/tool.rs` | 具体场景测试用例，包含 `test_apply_patch_cli_applies_multiple_operations` |
| `codex-rs/apply-patch/tests/suite/cli.rs` | CLI 集成测试 |

### 4.3 关键函数调用链

```
测试执行流程:
    test_apply_patch_scenarios() [scenarios.rs:11]
    └── run_apply_patch_scenario(dir) [scenarios.rs:30]
        ├── copy_dir_recursive(input_dir, tmp_dir) [scenarios.rs:36]
        ├── Command::new("apply_patch").arg(patch).current_dir(tmp.path()).output() [scenarios.rs:45-48]
        └── assert_eq!(actual_snapshot, expected_snapshot) [scenarios.rs:55-60]
            └── snapshot_dir(expected_dir) vs snapshot_dir(tmp.path())

apply_patch 执行流程:
    main() [standalone_executable.rs:4]
    └── run_main() [standalone_executable.rs:11]
        └── apply_patch(patch_arg, stdout, stderr) [lib.rs:183]
            ├── parse_patch(patch) -> Vec<Hunk> [parser.rs:106]
            └── apply_hunks(hunks, stdout, stderr) [lib.rs:216]
                └── apply_hunks_to_files(hunks) [lib.rs:279]
                    └── 处理每个 Hunk::AddFile (创建目录+写入文件)
```

### 4.4 场景测试框架详解

**源码位置**: `codex-rs/apply-patch/tests/suite/scenarios.rs`

测试框架采用**声明式测试**设计：

1. **输入状态**: `input/` 目录包含测试前的文件系统状态
2. **操作定义**: `patch.txt` 定义要应用的补丁
3. **期望状态**: `expected/` 目录定义应用补丁后的文件系统状态
4. **验证方式**: 比较实际输出目录与期望目录的完整快照（包括文件内容和目录结构）

**快照比较逻辑** (`scenarios.rs:71-105`):

```rust
fn snapshot_dir(root: &Path) -> anyhow::Result<BTreeMap<PathBuf, Entry>> {
    // 递归遍历目录，生成 (相对路径 -> 文件内容/目录标记) 的有序映射
}

enum Entry {
    File(Vec<u8>),  // 文件内容（二进制）
    Dir,            // 目录标记
}
```

---

## 5. 依赖与外部交互

### 5.1 运行时依赖

| 依赖 | 用途 |
|------|------|
| `anyhow` | 错误处理和上下文传递 |
| `similar` | 生成统一差异格式（unified diff） |
| `thiserror` | 自定义错误类型定义 |
| `tree-sitter` | 解析 bash 脚本中的 heredoc |
| `tree-sitter-bash` | Bash 语法支持 |

### 5.2 测试依赖

| 依赖 | 用途 |
|------|------|
| `assert_cmd` | CLI 命令断言测试 |
| `assert_matches` | 模式匹配断言 |
| `codex-utils-cargo-bin` | 在测试中定位编译后的二进制文件 |
| `pretty_assertions` | 美观的差异输出 |
| `tempfile` | 临时目录管理 |

### 5.3 外部工具交互

| 交互对象 | 方式 | 说明 |
|----------|------|------|
| 文件系统 | `std::fs` | 直接文件操作 |
| Shell 脚本解析 | `tree-sitter` | 提取 heredoc 中的补丁内容 |
| 标准输入/输出 | `std::io` | 支持管道输入和结果输出 |

### 5.4 调用方式支持

`apply_patch` 支持多种调用方式（`invocation.rs`）：

1. **直接调用**: `apply_patch "*** Begin Patch..."`
2. **Bash heredoc**: `bash -lc "apply_patch <<'EOF'..."`
3. **PowerShell**: `powershell -Command "apply_patch <<'EOF'..."`
4. **标准输入**: `echo "patch" | apply_patch`
5. **带工作目录**: `bash -lc "cd foo && apply_patch <<'EOF'..."`

---

## 6. 风险、边界与改进建议

### 6.1 当前风险点

#### 6.1.1 部分成功问题

当补丁包含多个操作时，如果中间某个操作失败，**已成功的操作不会回滚**。

**源码位置**: `lib.rs:248-265`

```rust
// 当前实现：遇到错误直接返回，不撤销之前的操作
match apply_hunks_to_files(hunks) {
    Ok(affected) => { /* ... */ }
    Err(err) => { /* 仅报告错误，无回滚 */ }
}
```

**场景 015 测试验证**: `015_failure_after_partial_success_leaves_changes`

#### 6.1.2 路径解析歧义

补丁中使用相对路径，但解析依赖于执行时的当前工作目录。如果调用方式涉及 `cd` 和 heredoc，路径解析可能产生歧义。

#### 6.1.3 换行符一致性

`new.txt` 的内容是 `created`（无显式换行符），但实际文件内容是 `created\n`。这种隐式换行符添加可能在某些场景下导致意外行为。

### 6.2 边界情况

| 边界情况 | 当前行为 | 测试覆盖 |
|----------|----------|----------|
| 添加已存在的文件 | 覆盖（静默） | `011_add_overwrites_existing_file` |
| 删除不存在的文件 | 报错 | `007_rejects_missing_file_delete` |
| 更新不存在的文件 | 报错 | `009_requires_existing_file_for_update` |
| 空补丁 | 报错 "No files were modified" | `005_rejects_empty_patch` |
| 空 Update hunk | 报错 "Update file hunk is empty" | `008_rejects_empty_update_hunk` |
| 删除目录（非文件） | 报错 | `012_delete_directory_fails` |
| 纯添加 chunk（无 old_lines） | 支持 | `016_pure_addition_update_chunk` |
| 文件末尾标记 | 支持 `*** End of File` | `022_update_file_end_of_file_marker` |

### 6.3 改进建议

#### 6.3.1 事务性支持

建议实现**原子性补丁应用**：

```rust
// 建议的实现模式
fn apply_hunks_atomically(hunks: &[Hunk]) -> Result<()> {
    // 1. 预验证所有 hunks（检查文件存在性、上下文匹配等）
    for hunk in hunks {
        hunk.validate()?;
    }
    
    // 2. 创建临时备份
    let backup = create_backup(hunks)?;
    
    // 3. 应用所有 hunks
    match apply_hunks_to_files(hunks) {
        Ok(result) => {
            cleanup_backup(backup)?;
            Ok(result)
        }
        Err(e) => {
            restore_backup(backup)?;
            Err(e)
        }
    }
}
```

#### 6.3.2 路径验证增强

建议添加路径安全检查：

- 禁止绝对路径（已部分支持）
- 禁止路径遍历攻击（`../` 等）
- 验证路径在指定工作目录内

#### 6.3.3 内容编码支持

当前实现仅支持 UTF-8 文本文件。建议：

- 明确文档说明编码要求
- 考虑支持二进制文件的 Base64 编码

#### 6.3.4 测试覆盖率扩展

建议添加以下场景的测试：

- 并发补丁应用测试
- 大文件（>1MB）性能测试
- 特殊字符文件名测试
- 符号链接处理测试

### 6.4 与相关场景的对比

| 场景 | 目的 | 与 002 的关系 |
|------|------|---------------|
| `001_add_file` | 基础 Add File 测试 | 002 的简化版，无嵌套目录 |
| `003_multiple_chunks` | 多 chunk Update 测试 | 002 的 Update 操作深化 |
| `004_move_to_new_directory` | 文件移动测试 | 002 的 Move 操作扩展 |
| `016_pure_addition_update_chunk` | 纯添加 chunk 测试 | Update 操作的边界情况 |

---

## 7. 总结

`new.txt` 是 `apply_patch` 工具**多操作补丁**测试场景中的关键验证点，主要验证：

1. **嵌套目录自动创建**能力
2. **Add File 操作**的正确实现
3. **内容格式化**（自动添加换行符）

该测试场景通过声明式测试框架（input/patch/expected 结构）实现了高可维护性和可移植性，是项目中端到端测试的最佳实践范例。

---

*文档生成时间: 2026-03-22*  
*基于代码版本: codex-rs/apply-patch 最新主分支*
