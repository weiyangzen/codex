# Research: `020_delete_file_success/expected/keep.txt`

## 概述

本文档深入研究 `codex-rs/apply-patch/tests/fixtures/scenarios/020_delete_file_success/expected/keep.txt` 文件，该文件是 `apply-patch` 工具测试套件中的一个关键测试固件（test fixture）。此测试场景验证 `apply_patch` 工具正确删除指定文件的能力，同时保留其他未受影响的文件。

---

## 1. 场景与职责

### 1.1 测试场景定位

`020_delete_file_success` 是 `apply-patch` 测试套件中的第 20 个场景测试，专注于验证**文件删除操作**的基本功能。

**目录结构：**
```
020_delete_file_success/
├── input/
│   ├── keep.txt          # 输入：应保留的文件
│   └── obsolete.txt      # 输入：将被删除的文件
├── expected/
│   └── keep.txt          # 期望输出：仅保留的文件
└── patch.txt             # 补丁定义
```

### 1.2 文件职责

| 文件 | 角色 | 内容 | 预期结果 |
|------|------|------|----------|
| `input/keep.txt` | 对照文件 | `keep` | 保持不变，存在于 `expected/` |
| `input/obsolete.txt` | 目标删除文件 | `obsolete` | 被删除，不存在于 `expected/` |
| `expected/keep.txt` | 验证基准 | `keep` | 用于断言最终状态 |
| `patch.txt` | 操作指令 | 删除指令 | 定义对 `obsolete.txt` 的删除操作 |

### 1.3 测试执行流程

测试执行遵循以下步骤（由 `tests/suite/scenarios.rs` 中的 `run_apply_patch_scenario` 函数实现）：

1. **准备阶段**：创建临时目录，复制 `input/` 下的所有文件
2. **执行阶段**：在临时目录中运行 `apply_patch` 命令，传入 `patch.txt` 内容
3. **验证阶段**：比较临时目录的最终状态与 `expected/` 目录的快照

---

## 2. 功能点目的

### 2.1 核心功能验证

此测试场景验证 `apply_patch` 工具的以下核心能力：

1. **文件删除操作**：正确解析并执行 `*** Delete File:` 指令
2. **选择性操作**：仅删除补丁中指定的文件，不影响其他文件
3. **状态一致性**：删除操作后，文件系统状态与预期完全一致

### 2.2 补丁格式验证

测试使用的补丁格式（`patch.txt`）：

```
*** Begin Patch
*** Delete File: obsolete.txt
*** End Patch
```

该格式验证：
- 补丁边界标记（`*** Begin Patch` / `*** End Patch`）
- 文件删除指令语法（`*** Delete File: <path>`）
- 空行处理（删除指令后无额外内容）

### 2.3 与其他场景的对比

| 场景编号 | 名称 | 目的差异 |
|----------|------|----------|
| 007 | `rejects_missing_file_delete` | 验证删除不存在文件时的错误处理 |
| 012 | `delete_directory_fails` | 验证尝试删除目录时的失败行为 |
| **020** | **`delete_file_success`** | **验证正常文件删除的成功路径** |

---

## 3. 具体技术实现

### 3.1 补丁解析流程

补丁解析由 `src/parser.rs` 中的 `parse_patch` 函数实现：

```rust
// parser.rs:106-113
pub fn parse_patch(patch: &str) -> Result<ApplyPatchArgs, ParseError> {
    let mode = if PARSE_IN_STRICT_MODE {
        ParseMode::Strict
    } else {
        ParseMode::Lenient
    };
    parse_patch_text(patch, mode)
}
```

**解析步骤：**

1. **边界检查**：验证 `*** Begin Patch` 和 `*** End Patch` 标记
2. **分块解析**：将补丁内容分割为多个 `Hunk`
3. **指令识别**：识别 `*** Delete File:` 标记并提取文件路径

### 3.2 Hunk 数据结构

删除操作对应的 Hunk 类型定义（`src/parser.rs:58-76`）：

```rust
#[derive(Debug, PartialEq, Clone)]
#[allow(clippy::enum_variant_names)]
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

对于本测试场景，解析后的 Hunk 为：

```rust
Hunk::DeleteFile {
    path: PathBuf::from("obsolete.txt"),
}
```

### 3.3 文件删除执行

文件删除操作由 `src/lib.rs` 中的 `apply_hunks_to_files` 函数执行：

```rust
// lib.rs:301-305
Hunk::DeleteFile { path } => {
    std::fs::remove_file(path)
        .with_context(|| format!("Failed to delete file {}", path.display()))?;
    deleted.push(path.clone());
}
```

**执行细节：**
- 使用 `std::fs::remove_file` 进行文件删除
- 错误上下文包装：提供友好的错误信息
- 路径追踪：将被删除的路径加入 `deleted` 向量，用于后续摘要输出

### 3.4 结果输出

成功执行后，`apply_patch` 输出 Git 风格的摘要：

```
Success. Updated the following files:
D obsolete.txt
```

输出实现（`src/lib.rs:537-552`）：

```rust
pub fn print_summary(
    affected: &AffectedPaths,
    out: &mut impl std::io::Write,
) -> std::io::Result<()> {
    writeln!(out, "Success. Updated the following files:")?;
    for path in &affected.added {
        writeln!(out, "A {}", path.display())?;
    }
    for path in &affected.modified {
        writeln!(out, "M {}", path.display())?;
    }
    for path in &affected.deleted {
        writeln!(out, "D {}", path.display())?;
    }
    Ok(())
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 完整调用链

```
测试入口
└── tests/suite/scenarios.rs::test_apply_patch_scenarios()
    └── run_apply_patch_scenario(dir)
        ├── 复制 input/ 到临时目录
        ├── 读取 patch.txt
        ├── 执行 apply_patch 命令
        │   └── src/standalone_executable.rs::run_main()
        │       └── src/lib.rs::apply_patch()
        │           └── src/parser.rs::parse_patch()
        │               └── parse_one_hunk() → Hunk::DeleteFile
        │           └── src/lib.rs::apply_hunks()
        │               └── apply_hunks_to_files()
        │                   └── std::fs::remove_file()
        │           └── print_summary()
        └── 比较实际状态与 expected/ 快照
```

### 4.2 关键文件引用

| 文件路径 | 功能 | 相关行号 |
|----------|------|----------|
| `src/parser.rs` | 补丁解析 | 31-40（标记常量）、58-76（Hunk 定义）、271-278（DeleteFile 解析） |
| `src/lib.rs` | 核心逻辑 | 99-108（ApplyPatchFileChange）、279-339（apply_hunks_to_files）、537-552（print_summary） |
| `src/standalone_executable.rs` | CLI 入口 | 11-59（run_main） |
| `tests/suite/scenarios.rs` | 场景测试框架 | 30-63（run_apply_patch_scenario） |

### 4.3 补丁解析关键代码

删除文件指令的解析逻辑（`src/parser.rs:271-278`）：

```rust
} else if let Some(path) = first_line.strip_prefix(DELETE_FILE_MARKER) {
    // Delete File
    return Ok((
        DeleteFile {
            path: PathBuf::from(path),
        },
        1,
    ));
}
```

其中 `DELETE_FILE_MARKER` 定义为（`src/parser.rs:34`）：

```rust
const DELETE_FILE_MARKER: &str = "*** Delete File: ";
```

---

## 5. 依赖与外部交互

### 5.1 内部依赖

```
codex-apply-patch/
├── src/lib.rs          # 核心库：补丁应用逻辑
├── src/parser.rs       # 补丁解析器
├── src/invocation.rs   # 调用解析（heredoc 等）
├── src/standalone_executable.rs  # CLI 入口
└── src/seek_sequence.rs # 文本匹配算法
```

### 5.2 外部依赖

| 依赖 | 用途 | 版本来源 |
|------|------|----------|
| `anyhow` | 错误处理 | workspace |
| `similar` | 文本差异计算（unified diff） | workspace |
| `thiserror` | 错误类型定义 | workspace |
| `tree-sitter` | Bash 脚本解析（heredoc 提取） | workspace |
| `tree-sitter-bash` | Bash 语法支持 | workspace |

### 5.3 测试依赖

| 依赖 | 用途 |
|------|------|
| `assert_cmd` | CLI 测试断言 |
| `codex-utils-cargo-bin` | 测试二进制文件定位 |
| `pretty_assertions` | 差异对比输出 |
| `tempfile` | 临时目录管理 |

### 5.4 系统交互

- **文件系统操作**：通过 `std::fs` 模块执行
  - `std::fs::remove_file()` - 删除目标文件
  - `std::fs::metadata()` - 文件元数据检查（用于快照比较）

- **进程执行**：测试框架通过 `std::process::Command` 调用 `apply_patch` 二进制

---

## 6. 风险、边界与改进建议

### 6.1 潜在风险

#### 6.1.1 误删除风险

**问题**：`apply_patch` 工具直接执行文件删除，无回收站或备份机制。

**缓解**：
- 工具文档明确说明删除操作不可逆
- 建议在版本控制环境下使用

#### 6.1.2 路径遍历风险

**问题**：补丁中的相对路径可能被解析到预期目录之外。

**当前防护**：
- 路径解析使用 `Path::join`，受限于执行时的工作目录
- 测试场景使用临时目录隔离

**建议**：
- 考虑添加路径规范化检查，拒绝 `../` 等遍历模式
- 在 `maybe_parse_apply_patch_verified` 中增加路径安全检查

#### 6.1.3 并发执行风险

**问题**：多个 `apply_patch` 进程同时操作可能产生竞态条件。

**当前状态**：无文件锁机制，依赖外部协调。

### 6.2 边界情况

| 边界情况 | 当前行为 | 测试覆盖 |
|----------|----------|----------|
| 删除不存在的文件 | 返回错误（场景 007） | ✅ |
| 删除目录 | 返回错误（场景 012） | ✅ |
| 删除只读文件 | 依赖操作系统行为 | ❌ |
| 删除符号链接 | 删除链接本身（非目标） | ❌ |
| 路径包含特殊字符 | 正常处理 | 部分覆盖 |

### 6.3 改进建议

#### 6.3.1 功能增强

1. **删除确认机制**
   - 添加 `--dry-run` 模式，预览将要删除的文件
   - 实现交互式确认（当未在管道中运行时）

2. **备份与恢复**
   - 添加 `--backup` 选项，删除前创建 `.bak` 文件
   - 实现撤销日志，支持操作回滚

3. **增强日志**
   - 添加 `--verbose` 模式，输出详细的删除过程
   - 记录原始文件内容（用于审计）

#### 6.3.2 测试增强

1. **边界测试**
   ```rust
   // 建议添加的测试场景
   - 删除符号链接（不跟随）
   - 删除硬链接（仅删除指定路径）
   - 删除权限受限的文件
   - 删除路径包含 Unicode/空格的文件
   ```

2. **并发测试**
   - 验证多进程同时操作同一目录的行为

3. **性能测试**
   - 大规模文件删除的性能基准

#### 6.3.3 代码质量

1. **错误信息改进**
   - 当前：`Failed to delete file obsolete.txt`
   - 建议：`Failed to delete file "obsolete.txt": No such file or directory (os error 2)`

2. **文档完善**
   - 在 `apply_patch_tool_instructions.md` 中添加删除操作的风险提示
   - 提供删除操作的最佳实践示例

### 6.4 与相关场景的关联

```
020_delete_file_success
├── 前置依赖：无（基础功能）
├── 相关场景：
│   ├── 007_rejects_missing_file_delete（错误路径）
│   ├── 012_delete_directory_fails（错误路径）
│   └── 002_multiple_operations（组合场景，含删除）
└── 后续扩展建议：
    ├── 删除后验证文件内容（用于审计）
    └── 批量删除优化
```

---

## 7. 总结

`020_delete_file_success/expected/keep.txt` 是一个简洁但关键的测试固件，它：

1. **验证核心功能**：确认 `apply_patch` 能正确执行文件删除操作
2. **确保选择性**：证明工具不会意外影响未指定的文件
3. **提供回归防护**：任何对删除逻辑的修改都会通过此测试暴露

该测试场景的设计遵循了测试套件的整体规范：
- **输入/预期分离**：`input/` 和 `expected/` 目录清晰区分
- **最小化原则**：每个场景测试单一概念
- **可移植性**：纯文件结构，易于跨语言/平台实现

---

*文档生成时间：2026-03-23*
*基于代码版本：codex-rs/apply-patch 主分支*
