# 012_delete_directory_fails 场景研究文档

## 场景与职责

### 场景概述

`012_delete_directory_fails` 是 `codex-apply-patch` 组件的一个测试场景，用于验证当尝试使用 `*** Delete File:` 指令删除一个目录（而非文件）时，系统应该正确地失败并保持文件系统状态不变。

### 目录结构

```
codex-rs/apply-patch/tests/fixtures/scenarios/012_delete_directory_fails/
├── input/
│   └── dir/
│       └── foo.txt     # 内容为 "stable"
├── expected/
│   └── dir/
│       └── foo.txt     # 内容为 "stable"（与 input 相同，表示未改变）
└── patch.txt           # 尝试删除 "dir" 目录的 patch
```

### 测试职责

该测试场景的核心职责是：
1. **验证错误处理**：当 patch 尝试删除一个目录而非文件时，系统应返回错误
2. **验证原子性保证**：即使删除操作失败，文件系统状态应保持不变
3. **验证错误信息**：提供清晰的错误信息指示删除失败

---

## 功能点目的

### Patch 格式解析

目标 patch 文件内容：
```
*** Begin Patch
*** Delete File: dir
*** End Patch
```

这是一个简单的删除文件 patch，意图删除名为 `dir` 的路径。

### 预期行为

| 方面 | 预期行为 |
|------|----------|
| 退出状态 | 非零（失败） |
| 错误输出 | `Failed to delete file dir` |
| 文件系统状态 | `dir/foo.txt` 保持不变 |
| 标准输出 | 无成功信息 |

### 与其他场景的对比

| 场景 | 描述 | 预期结果 |
|------|------|----------|
 `007_rejects_missing_file_delete` | 尝试删除不存在的文件 | 失败，文件系统不变 |
| `012_delete_directory_fails` | 尝试删除目录而非文件 | 失败，文件系统不变 |
| `020_delete_file_success` | 成功删除存在的文件 | 成功，文件被删除 |

---

## 具体技术实现

### 关键流程

#### 1. Patch 解析流程

```rust
// parser.rs: parse_patch() -> parse_patch_text() -> parse_one_hunk()
// 解析 "*** Delete File: dir" 生成 Hunk::DeleteFile { path: PathBuf::from("dir") }
```

解析器识别 `*** Delete File:` 前缀，提取路径 `dir`，生成 `DeleteFile` hunk。

#### 2. Hunk 应用流程

```rust
// lib.rs: apply_hunks_to_files()
match hunk {
    Hunk::DeleteFile { path } => {
        std::fs::remove_file(path)  // 这里会失败，因为 path 是目录
            .with_context(|| format!("Failed to delete file {}", path.display()))?;
        deleted.push(path.clone());
    }
    // ...
}
```

#### 3. 错误处理流程

```rust
// lib.rs: apply_hunks()
match apply_hunks_to_files(hunks) {
    Ok(affected) => { /* 成功路径 */ }
    Err(err) => {
        let msg = err.to_string();
        writeln!(stderr, "{msg}").map_err(ApplyPatchError::from)?;
        // 转换为 ApplyPatchError::IoError
        if let Some(io) = err.downcast_ref::<std::io::Error>() {
            Err(ApplyPatchError::from(io))
        } else {
            Err(ApplyPatchError::IoError(IoError { context: msg, source: ... }))
        }
    }
}
```

### 数据结构

#### Hunk 枚举（parser.rs）

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
        move_path: Option<PathBuf>,
        chunks: Vec<UpdateFileChunk>,
    },
}
```

#### ApplyPatchError 枚举（lib.rs）

```rust
#[derive(Debug, Error, PartialEq)]
pub enum ApplyPatchError {
    #[error(transparent)]
    ParseError(#[from] ParseError),
    #[error(transparent)]
    IoError(#[from] IoError),
    #[error("{0}")]
    ComputeReplacements(String),
    #[error("patch detected without explicit call to apply_patch...")]
    ImplicitInvocation,
}
```

### 协议/命令

#### Patch 语法协议

```
*** Begin Patch
*** Delete File: <path>
*** End Patch
```

- `*** Begin Patch`：Patch 开始标记
- `*** Delete File: <path>`：删除文件指令，后跟文件路径
- `*** End Patch`：Patch 结束标记

#### 完整语法定义（parser.rs 注释）

```
start: begin_patch hunk+ end_patch
begin_patch: "*** Begin Patch" LF
end_patch: "*** End Patch" LF?

hunk: add_hunk | delete_hunk | update_hunk
add_hunk: "*** Add File: " filename LF add_line+
delete_hunk: "*** Delete File: " filename LF
update_hunk: "*** Update File: " filename LF change_move? change?
```

---

## 关键代码路径与文件引用

### 核心文件

| 文件 | 职责 | 关键函数/行 |
|------|------|-------------|
| `parser.rs` | Patch 解析 | `parse_patch()` (line 106), `parse_one_hunk()` (line 248) |
| `lib.rs` | Patch 应用 | `apply_patch()` (line 183), `apply_hunks_to_files()` (line 279) |
| `standalone_executable.rs` | CLI 入口 | `run_main()` (line 11) |

### 关键代码路径

#### 删除文件执行路径

```
main() [main.rs]
  └─> codex_apply_patch::main() [standalone_executable.rs:4]
      └─> run_main() [standalone_executable.rs:11]
          └─> apply_patch() [lib.rs:183]
              └─> parse_patch() [parser.rs:106]
              └─> apply_hunks() [lib.rs:216]
                  └─> apply_hunks_to_files() [lib.rs:279]
                      └─> std::fs::remove_file(path) [lib.rs:302]  <-- 失败点
```

#### 错误传播路径

```
std::fs::remove_file() 返回 Err(std::io::Error)
  └─> with_context() 包装为 anyhow::Error
      └─> apply_hunks() 捕获错误 [lib.rs:253-264]
          └─> 写入 stderr: "Failed to delete file dir"
              └─> 返回 ApplyPatchError::IoError
                  └─> run_main() 返回 exit code 1 [standalone_executable.rs:57]
```

### 测试代码路径

#### 场景测试（scenarios.rs）

```rust
// tests/suite/scenarios.rs: run_apply_patch_scenario()
fn run_apply_patch_scenario(dir: &Path) -> anyhow::Result<()> {
    let tmp = tempdir()?;
    
    // 1. 复制 input 到临时目录
    copy_dir_recursive(&input_dir, tmp.path())?;
    
    // 2. 读取 patch.txt
    let patch = fs::read_to_string(dir.join("patch.txt"))?;
    
    // 3. 运行 apply_patch（不检查退出状态）
    Command::new("apply_patch")
        .arg(patch)
        .current_dir(tmp.path())
        .output()?;
    
    // 4. 比较实际结果与 expected 目录快照
    let expected_snapshot = snapshot_dir(&expected_dir)?;
    let actual_snapshot = snapshot_dir(tmp.path())?;
    assert_eq!(actual_snapshot, expected_snapshot);
    
    Ok(())
}
```

#### CLI 测试（tool.rs）

```rust
// tests/suite/tool.rs: test_apply_patch_cli_delete_directory_fails()
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

---

## 依赖与外部交互

### 系统调用

| 调用 | 用途 | 在本场景中的行为 |
|------|------|-----------------|
| `std::fs::remove_file(path)` | 删除文件 | 失败，返回 `std::io::ErrorKind::PermissionDenied` 或 `IsADirectory` |

### 操作系统行为

在 Unix/Linux 系统上：
- `remove_file()` 内部调用 `unlink(2)` 系统调用
- `unlink()` 不能删除目录，返回 `EISDIR` 错误
- Rust 标准库将其转换为 `std::io::ErrorKind::PermissionDenied`

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `anyhow` | 错误处理和上下文包装 |
| `thiserror` | 错误类型定义 |
| `similar` | 统一差异（unified diff）生成 |
| `tempfile` | 测试临时目录管理 |
| `assert_cmd` | CLI 测试断言 |

---

## 风险、边界与改进建议

### 当前风险

#### 1. 错误信息不够精确

**问题**：当前错误信息 `Failed to delete file dir` 没有明确说明失败原因是路径是目录而非文件。

**改进建议**：
```rust
// 改进前
std::fs::remove_file(path)
    .with_context(|| format!("Failed to delete file {}", path.display()))?;

// 改进后
if path.is_dir() {
    anyhow::bail!("Cannot delete '{}': it is a directory, not a file", path.display());
}
std::fs::remove_file(path)
    .with_context(|| format!("Failed to delete file {}", path.display()))?;
```

#### 2. 缺乏递归删除目录的支持

**问题**：Patch 协议不支持删除目录，这在某些场景下可能是需要的。

**改进建议**：
- 添加 `*** Delete Directory:` 指令
- 或添加 `*** Delete File: <path> --recursive` 选项

#### 3. 错误类型区分不足

**问题**：所有 I/O 错误都统一为 `ApplyPatchError::IoError`，调用方难以区分错误类型。

**改进建议**：
```rust
pub enum ApplyPatchError {
    // ...
    #[error("cannot delete directory as file: {path}")]
    DeleteDirectoryAsFile { path: PathBuf },
    #[error("file not found: {path}")]
    FileNotFound { path: PathBuf },
    // ...
}
```

### 边界情况

| 边界情况 | 当前行为 | 评估 |
|----------|----------|------|
| 删除符号链接（指向文件） | 删除链接本身 | ✅ 正确 |
| 删除符号链接（指向目录） | 删除链接本身 | ✅ 正确 |
| 删除空目录 | 失败 | ✅ 符合预期（明确区分文件和目录） |
| 删除非空目录 | 失败 | ✅ 符合预期 |
| 路径包含特殊字符 | 正常处理 | ✅ 正确 |
| 相对路径 `..` | 解析后处理 | ⚠️ 需注意安全风险 |

### 测试覆盖

当前测试覆盖：
- ✅ 场景测试（scenarios.rs）
- ✅ CLI 测试（tool.rs）

建议增加的测试：
- 符号链接删除测试
- 权限不足导致删除失败的测试
- 并发删除的竞态条件测试

### 安全考虑

1. **路径遍历防护**：确保 `dir` 不会解析到工作目录之外的敏感路径
2. **权限检查**：在尝试删除前验证对目标路径的写权限
3. **操作日志**：记录删除操作以便审计

---

## 总结

`012_delete_directory_fails` 场景是 `codex-apply-patch` 组件错误处理机制的重要组成部分。它验证了当用户错误地尝试使用文件删除指令删除目录时，系统能够：

1. 正确识别并拒绝该操作
2. 提供清晰的错误信息
3. 保持文件系统状态不变（原子性保证）

该场景的实现依赖于 Rust 标准库的 `std::fs::remove_file()` 函数，该函数在底层使用 `unlink(2)` 系统调用，天然地拒绝删除目录，从而确保了行为的安全性和可预测性。
