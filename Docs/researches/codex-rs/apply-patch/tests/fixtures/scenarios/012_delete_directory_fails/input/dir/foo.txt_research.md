# 研究文档：012_delete_directory_fails 测试场景

## 目标文件

- **文件路径**: `codex-rs/apply-patch/tests/fixtures/scenarios/012_delete_directory_fails/input/dir/foo.txt`
- **文件内容**: `stable`（单行的占位文本）
- **所属场景**: `012_delete_directory_fails`

---

## 1. 场景与职责

### 1.1 场景概述

`012_delete_directory_fails` 是 `codex-apply-patch` 组件的一个**负面测试场景（negative test scenario）**，用于验证当尝试使用 `*** Delete File:` 指令删除一个**目录**（而非普通文件）时，系统应该正确地**拒绝该操作并报告错误**。

### 1.2 测试结构

该场景遵循标准测试夹具（fixture）结构：

```
codex-rs/apply-patch/tests/fixtures/scenarios/012_delete_directory_fails/
├── input/
│   └── dir/
│       └── foo.txt          # 目标文件：位于待删除目录内的占位文件
├── expected/
│   └── dir/
│       └── foo.txt          # 期望结果：目录和文件保持原样（删除失败）
└── patch.txt                # 补丁：尝试删除 "dir" 目录
```

### 1.3 核心职责

- `foo.txt` 作为目录 `dir` 的内容物，确保 `dir` 是一个**非空目录**
- 验证 `apply_patch` 工具在面对目录删除请求时的**错误处理行为**
- 确保系统不会因为误操作而意外删除目录结构

---

## 2. 功能点目的

### 2.1 安全边界验证

该测试的核心目的是验证 `apply_patch` 的**安全边界**：

1. **类型安全检查**: `Delete File` 操作应该只适用于普通文件，不适用于目录
2. **错误报告**: 当尝试删除目录时，应该返回清晰的错误信息
3. **无副作用**: 失败的操作不应该对文件系统造成任何变更

### 2.2 与成功删除场景的对比

| 场景 | 目标类型 | 操作 | 预期结果 |
|------|----------|------|----------|
| `020_delete_file_success` | 普通文件 (`obsolete.txt`) | `*** Delete File:` | 成功删除 |
| `007_rejects_missing_file_delete` | 不存在的文件 | `*** Delete File:` | 失败（文件不存在） |
| `012_delete_directory_fails` | 目录 (`dir`) | `*** Delete File:` | 失败（目标是目录） |

### 2.3 补丁内容分析

```text
*** Begin Patch
*** Delete File: dir
*** End Patch
```

补丁明确请求删除名为 `dir` 的路径，但 `dir` 是一个包含 `foo.txt` 的目录，而非普通文件。

---

## 3. 具体技术实现

### 3.1 关键流程

#### 3.1.1 补丁解析流程

```rust
// parser.rs: parse_one_hunk
else if let Some(path) = first_line.strip_prefix(DELETE_FILE_MARKER) {
    // Delete File
    return Ok((
        DeleteFile {
            path: PathBuf::from(path),
        },
        1,
    ));
}
```

解析器将 `*** Delete File: dir` 解析为一个 `Hunk::DeleteFile { path: "dir" }`，**不进行文件类型检查**（这是设计上的，解析阶段只负责语法解析）。

#### 3.1.2 文件删除执行流程

```rust
// lib.rs: apply_hunks_to_files (line 301-304)
Hunk::DeleteFile { path } => {
    std::fs::remove_file(path)
        .with_context(|| format!("Failed to delete file {}", path.display()))?;
    deleted.push(path.clone());
}
```

关键实现细节：
- 使用 `std::fs::remove_file()` 尝试删除路径
- `remove_file()` 在 POSIX 系统上对目录会返回 `EISDIR` (Is a directory) 错误
- 错误被 `with_context` 包装为 `"Failed to delete file {path}"`

#### 3.1.3 错误传播

```rust
// lib.rs: apply_hunks (line 253-264)
Err(err) => {
    let msg = err.to_string();
    writeln!(stderr, "{msg}").map_err(ApplyPatchError::from)?;
    // ... 错误转换
}
```

错误会被写入 stderr 并向上传播，导致进程以非零状态退出。

### 3.2 数据结构

#### 3.2.1 Hunk 枚举（解析结果）

```rust
// parser.rs:58-76
pub enum Hunk {
    AddFile {
        path: PathBuf,
        contents: String,
    },
    DeleteFile {
        path: PathBuf,  // 012_delete_directory_fails 场景生成的变体
    },
    UpdateFile {
        path: PathBuf,
        move_path: Option<PathBuf>,
        chunks: Vec<UpdateFileChunk>,
    },
}
```

#### 3.2.2 AffectedPaths（执行结果追踪）

```rust
// lib.rs:271-275
pub struct AffectedPaths {
    pub added: Vec<PathBuf>,
    pub modified: Vec<PathBuf>,
    pub deleted: Vec<PathBuf>,
}
```

在 `012_delete_directory_fails` 场景中，由于删除操作失败，`deleted` 列表保持为空。

### 3.3 协议与命令

#### 3.3.1 补丁格式协议

官方 Lark 语法定义（`parser.rs:5-21`）：

```lark
start: begin_patch hunk+ end_patch
begin_patch: "*** Begin Patch" LF
end_patch: "*** End Patch" LF?

hunk: add_hunk | delete_hunk | update_hunk
delete_hunk: "*** Delete File: " filename LF
filename: /(.+)/
```

#### 3.3.2 CLI 接口

```bash
# 本场景等效命令
apply_patch '*** Begin Patch
*** Delete File: dir
*** End Patch'
```

预期输出：
```
Failed to delete file dir
```

退出码：`1`（失败）

---

## 4. 关键代码路径与文件引用

### 4.1 核心实现文件

| 文件 | 职责 | 相关行号 |
|------|------|----------|
| `codex-rs/apply-patch/src/lib.rs` | 补丁应用主逻辑 | 277-339 (apply_hunks_to_files) |
| `codex-rs/apply-patch/src/parser.rs` | 补丁解析 | 58-76 (Hunk 枚举), 271-278 (DeleteFile 解析) |
| `codex-rs/apply-patch/src/standalone_executable.rs` | CLI 入口 | 11-58 (run_main) |

### 4.2 测试相关文件

| 文件 | 职责 | 相关行号 |
|------|------|----------|
| `codex-rs/apply-patch/tests/suite/scenarios.rs` | 场景测试框架 | 10-63 (test_apply_patch_scenarios) |
| `codex-rs/apply-patch/tests/suite/tool.rs` | 显式测试用例 | 196-207 (test_apply_patch_cli_delete_directory_fails) |

### 4.3 关键代码片段

#### 4.3.1 删除操作实现（lib.rs:301-304）

```rust
Hunk::DeleteFile { path } => {
    std::fs::remove_file(path)
        .with_context(|| format!("Failed to delete file {}", path.display()))?;
    deleted.push(path.clone());
}
```

#### 4.3.2 显式测试用例（tool.rs:196-207）

```rust
#[test]
fn test_apply_patch_cli_delete_directory_fails() -> anyhow::Result<()> {
    let tmp = tempdir()?;
    fs::create_dir(tmp.path().join("dir"))?;

    apply_patch_command(tmp.path())?
        .arg("*** Begin Patch\n*** Delete File: dir\n*** End Patch")
        .assert()
        .failure()
        .stderr("Failed to delete file dir\n");

    Ok(())
}
```

注意：显式测试用例中创建的 `dir` 是**空目录**，而 fixture 场景中的 `dir` 包含 `foo.txt`，两者都触发相同的错误路径。

---

## 5. 依赖与外部交互

### 5.1 系统调用依赖

该场景依赖以下系统调用行为：

| 系统调用 | 行为 | 错误码 |
|----------|------|--------|
| `unlink()` (POSIX) | 删除文件 | `EISDIR` (21) - 如果目标是目录 |
| `std::fs::remove_file` (Rust) | 封装 `unlink` | 返回 `std::io::Error` with `kind: IsADirectory` |

### 5.2 跨平台行为

```rust
// lib.rs:3
#[cfg(not(target_os = "windows"))]
mod tool;
```

注意：`tool.rs` 中的显式测试仅在非 Windows 平台运行，但 fixture 场景测试（`scenarios.rs`）是跨平台的。

### 5.3 错误消息格式

错误消息格式由 `anyhow::Context::with_context` 生成：

```rust
.with_context(|| format!("Failed to delete file {}", path.display()))
```

最终输出：`"Failed to delete file dir"`（加上换行符）

### 5.4 项目内部依赖

```toml
# codex-rs/apply-patch/Cargo.toml
[dependencies]
anyhow = { workspace = true }
thiserror = { workspace = true }

[dev-dependencies]
codex-utils-cargo-bin = { workspace = true }
tempfile = { workspace = true }
```

---

## 6. 风险、边界与改进建议

### 6.1 当前实现的风险

#### 6.1.1 错误消息不够精确

当前错误消息 `"Failed to delete file dir"` 没有明确说明失败原因是目标是目录。对比：
- 当前：`Failed to delete file dir`
- 建议：`Failed to delete file dir: Is a directory (os error 21)`

#### 6.1.2 缺乏前置类型检查

系统依赖 `std::fs::remove_file` 的失败来拒绝目录删除，而非主动检查。前置检查可以提供更清晰的错误：

```rust
// 建议的改进
if path.is_dir() {
    anyhow::bail!("Cannot delete directory '{}' using Delete File operation", path.display());
}
```

### 6.2 边界情况

| 边界情况 | 当前行为 | 备注 |
|----------|----------|------|
| 空目录 | 删除失败 | `remove_file` 对空目录同样返回 `EISDIR` |
| 符号链接指向目录 | 删除成功 | 符号链接本身被删除，目标目录不受影响 |
| 嵌套目录结构 | 删除失败 | 与单层目录行为一致 |
| 权限不足 | 删除失败 | `EPERM` 错误，消息格式相同 |

### 6.3 改进建议

#### 6.3.1 增强错误消息（高优先级）

```rust
Hunk::DeleteFile { path } => {
    if path.is_dir() {
        return Err(anyhow::anyhow!(
            "Cannot delete directory '{}' using Delete File operation. Use a shell command to remove directories.",
            path.display()
        ));
    }
    std::fs::remove_file(path)
        .with_context(|| format!("Failed to delete file {}", path.display()))?;
    deleted.push(path.clone());
}
```

#### 6.3.2 支持递归删除目录（功能扩展）

考虑添加新的补丁指令 `*** Delete Directory:` 来支持安全的目录删除：

```text
*** Begin Patch
*** Delete Directory: dir
*** End Patch
```

这需要：
1. 解析器支持新的 hunk 类型
2. 使用 `std::fs::remove_dir_all` 实现删除逻辑
3. 充分的安全审查（防止误删重要目录）

#### 6.3.3 测试覆盖增强

当前测试仅验证错误发生，建议增强：

```rust
// 验证目录内容未被修改
assert!(tmp.path().join("dir").exists());
assert_eq!(fs::read_to_string(tmp.path().join("dir/foo.txt"))?, "stable");
```

### 6.4 相关场景索引

| 场景编号 | 名称 | 与 012 的关系 |
|----------|------|---------------|
| 007 | rejects_missing_file_delete | 同类错误处理（删除不存在的文件） |
| 020 | delete_file_success | 正向案例（成功删除文件） |
| 015 | failure_after_partial_success_leaves_changes | 错误处理与状态一致性 |

---

## 7. 总结

`012_delete_directory_fails/input/dir/foo.txt` 是一个**测试夹具支持文件**，其存在意义在于：

1. **确保 `dir` 是一个有效的非空目录**，能够被文件系统正常识别为目录类型
2. **验证 `apply_patch` 工具的类型安全边界**，防止目录被误删
3. **作为预期状态的一部分**，验证失败操作不会导致副作用

该文件内容 `"stable"` 是任意的（仅作为占位），但其**存在本身**是测试逻辑的关键组成部分。

---

*研究完成时间: 2026-03-22*
*基于代码版本: codex-rs/apply-patch 当前 HEAD*
