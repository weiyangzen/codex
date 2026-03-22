# 研究文档：007_rejects_missing_file_delete 测试场景

## 文件信息

- **目标文件**: `codex-rs/apply-patch/tests/fixtures/scenarios/007_rejects_missing_file_delete/input/foo.txt`
- **文件内容**: `stable`
- **所属组件**: `codex-apply-patch` crate
- **测试场景编号**: 007
- **场景名称**: rejects_missing_file_delete（拒绝删除不存在的文件）

---

## 1. 场景与职责

### 1.1 测试场景概述

`007_rejects_missing_file_delete` 是 `codex-apply-patch` 组件的一个端到端测试场景，用于验证**删除不存在文件时的错误处理行为**。

该场景的目录结构如下：

```
007_rejects_missing_file_delete/
├── input/
│   └── foo.txt          # 输入文件，内容为 "stable"
├── expected/
│   └── foo.txt          # 期望输出，内容同样为 "stable"
└── patch.txt            # 补丁内容：尝试删除不存在的 missing.txt
```

### 1.2 核心职责

此测试场景的核心职责是验证：

1. **错误处理**: 当补丁尝试删除一个不存在的文件时，`apply_patch` 工具应该返回错误
2. **原子性保证**: 由于删除操作失败，已存在的文件 `foo.txt` 应该保持不变
3. **状态一致性**: 文件系统状态在操作失败后应该与操作前保持一致

### 1.3 补丁内容分析

```
*** Begin Patch
*** Delete File: missing.txt
*** End Patch
```

该补丁试图删除 `missing.txt` 文件，但在 `input/` 目录中只存在 `foo.txt`，不存在 `missing.txt`。因此，这是一个**预期会失败**的测试场景。

---

## 2. 功能点目的

### 2.1 测试目的

| 目的 | 说明 |
|------|------|
| 验证错误处理 | 确保当目标文件不存在时，删除操作会正确报告错误 |
| 验证事务性 | 确保部分失败不会留下不一致的文件系统状态 |
| 验证错误信息 | 确保错误信息清晰，指明是哪个文件删除失败 |

### 2.2 与其他场景的对比

| 场景 | 目的 | 与 007 的区别 |
|------|------|--------------|
| `020_delete_file_success` | 测试成功删除文件 | 目标文件存在，操作成功 |
| `012_delete_directory_fails` | 测试删除目录失败 | 目标是目录而非文件 |
| `007_rejects_missing_file_delete` | 测试删除不存在文件 | 目标文件根本不存在 |

### 2.3 预期行为

- **退出码**: 非零（表示失败）
- **标准输出**: 无成功信息
- **标准错误**: 包含删除失败的错误信息
- **文件系统状态**: `foo.txt` 保持不变，内容仍为 `stable`

---

## 3. 具体技术实现

### 3.1 关键流程

#### 3.1.1 补丁解析流程

```rust
// parser.rs: parse_patch() -> parse_patch_text()
// 1. 检查补丁边界标记（*** Begin Patch / *** End Patch）
// 2. 解析每个 hunk
// 3. 对于 Delete File hunk，创建 Hunk::DeleteFile { path }
```

对于本场景的补丁 `*** Delete File: missing.txt`，解析器会生成：

```rust
Hunk::DeleteFile {
    path: PathBuf::from("missing.txt")
}
```

#### 3.1.2 补丁应用流程

```rust
// lib.rs: apply_patch() -> apply_hunks() -> apply_hunks_to_files()

fn apply_hunks_to_files(hunks: &[Hunk]) -> anyhow::Result<AffectedPaths> {
    for hunk in hunks {
        match hunk {
            Hunk::DeleteFile { path } => {
                std::fs::remove_file(path)  // <-- 这里会失败
                    .with_context(|| format!("Failed to delete file {}", path.display()))?;
                deleted.push(path.clone());
            }
            // ...
        }
    }
}
```

#### 3.1.3 错误传播流程

当 `std::fs::remove_file("missing.txt")` 失败时（返回 `std::io::ErrorKind::NotFound`）：

1. `with_context()` 添加上下文信息：`"Failed to delete file missing.txt"`
2. `?` 运算符将错误向上传播
3. `apply_hunks()` 捕获错误并写入 stderr
4. 返回 `ApplyPatchError::IoError`

### 3.2 数据结构

#### 3.2.1 Hunk 枚举（parser.rs）

```rust
#[derive(Debug, PartialEq, Clone)]
pub enum Hunk {
    AddFile {
        path: PathBuf,
        contents: String,
    },
    DeleteFile {
        path: PathBuf,  // <-- 本场景使用的变体
    },
    UpdateFile {
        path: PathBuf,
        move_path: Option<PathBuf>,
        chunks: Vec<UpdateFileChunk>,
    },
}
```

#### 3.2.2 ApplyPatchError 枚举（lib.rs）

```rust
#[derive(Debug, Error, PartialEq)]
pub enum ApplyPatchError {
    #[error(transparent)]
    ParseError(#[from] ParseError),
    #[error(transparent)]
    IoError(#[from] IoError),  // <-- 本场景触发的错误类型
    #[error("{0}")]
    ComputeReplacements(String),
    #[error("...")]
    ImplicitInvocation,
}
```

#### 3.2.3 IoError 结构（lib.rs）

```rust
#[derive(Debug, Error)]
#[error("{context}: {source}")]
pub struct IoError {
    context: String,        // e.g., "Failed to delete file missing.txt"
    #[source]
    source: std::io::Error, // e.g., Os { code: 2, kind: NotFound, ... }
}
```

### 3.3 协议与命令

#### 3.3.1 补丁格式协议

根据 `apply_patch_tool_instructions.md` 中的规范：

```
DeleteFile := "*** Delete File: " path NEWLINE
```

删除文件操作只需要文件路径，不需要额外内容。

#### 3.3.2 CLI 调用方式

```bash
# 直接参数方式
apply_patch "*** Begin Patch\n*** Delete File: missing.txt\n*** End Patch"

# 或从 stdin 读取
echo "*** Begin Patch
*** Delete File: missing.txt
*** End Patch" | apply_patch
```

### 3.4 测试执行机制

#### 3.4.1 场景测试框架（tests/suite/scenarios.rs）

```rust
fn run_apply_patch_scenario(dir: &Path) -> anyhow::Result<()> {
    let tmp = tempdir()?;
    
    // 1. 复制 input/ 到临时目录
    copy_dir_recursive(&input_dir, tmp.path())?;
    
    // 2. 读取 patch.txt
    let patch = fs::read_to_string(dir.join("patch.txt"))?;
    
    // 3. 执行 apply_patch（不检查退出码）
    Command::new(cargo_bin("apply_patch"))?)
        .arg(patch)
        .current_dir(tmp.path())
        .output()?;
    
    // 4. 比较最终状态与 expected/ 目录
    let expected_snapshot = snapshot_dir(&expected_dir)?;
    let actual_snapshot = snapshot_dir(tmp.path())?;
    assert_eq!(actual_snapshot, expected_snapshot);
    
    Ok(())
}
```

**关键设计**：测试**不检查退出码**，只验证最终文件系统状态。这是因为：
- 失败场景的预期状态就是操作前的状态
- 只要文件系统状态匹配，就认为测试通过
- 这种设计允许测试用例专注于状态验证而非错误码验证

---

## 4. 关键代码路径与文件引用

### 4.1 核心实现文件

| 文件 | 职责 | 相关行号 |
|------|------|----------|
| `codex-rs/apply-patch/src/lib.rs` | 补丁应用核心逻辑 | 279-339 (`apply_hunks_to_files`) |
| `codex-rs/apply-patch/src/parser.rs` | 补丁解析 | 58-76 (`Hunk` 枚举), 271-278 (DeleteFile 解析) |
| `codex-rs/apply-patch/src/standalone_executable.rs` | CLI 入口 | 11-58 (`run_main`) |

### 4.2 测试相关文件

| 文件 | 职责 | 相关行号 |
|------|------|----------|
| `codex-rs/apply-patch/tests/suite/scenarios.rs` | 场景测试框架 | 10-63 |
| `codex-rs/apply-patch/tests/all.rs` | 测试入口 | 1-3 |

### 4.3 关键代码片段

#### 4.3.1 删除文件处理（lib.rs:301-304）

```rust
Hunk::DeleteFile { path } => {
    std::fs::remove_file(path)
        .with_context(|| format!("Failed to delete file {}", path.display()))?;
    deleted.push(path.clone());
}
```

这是本场景的核心代码。当 `path` 指向的文件不存在时，`std::fs::remove_file` 返回错误，导致整个补丁应用失败。

#### 4.3.2 错误处理（lib.rs:253-265）

```rust
Err(err) => {
    let msg = err.to_string();
    writeln!(stderr, "{msg}").map_err(ApplyPatchError::from)?;
    if let Some(io) = err.downcast_ref::<std::io::Error>() {
        Err(ApplyPatchError::from(io))
    } else {
        Err(ApplyPatchError::IoError(IoError {
            context: msg,
            source: std::io::Error::other(err),
        }))
    }
}
```

错误信息会被写入 stderr，然后返回 `ApplyPatchError`。

#### 4.3.3 解析 Delete File Hunk（parser.rs:271-278）

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

解析器识别 `*** Delete File:` 前缀，创建 `DeleteFile` hunk。

---

## 5. 依赖与外部交互

### 5.1 内部依赖

| 依赖 | 用途 |
|------|------|
| `codex-utils-cargo-bin` | 测试时定位二进制文件路径 |

### 5.2 外部依赖

| 依赖 | 用途 |
|------|------|
| `anyhow` | 错误处理和上下文传递 |
| `thiserror` | 错误类型定义 |
| `similar` | 文本差异计算（UpdateFile 使用） |
| `tree-sitter` | Bash 脚本解析（heredoc 提取） |
| `tree-sitter-bash` | Bash 语法支持 |
| `tempfile` | 测试时创建临时目录 |

### 5.3 系统调用

| 系统调用 | 用途 | 本场景行为 |
|----------|------|------------|
| `std::fs::remove_file` | 删除文件 | 失败（文件不存在） |
| `std::fs::read_dir` | 读取目录（测试框架） | 成功 |
| `std::fs::copy` | 复制文件（测试框架） | 成功 |

### 5.4 文件系统交互

```
测试执行时序：

1. 测试框架复制 input/ 到临时目录
   input/foo.txt ──────────────────────► tmp/foo.txt ("stable")

2. 执行 apply_patch，尝试删除 missing.txt
   tmp/missing.txt 不存在 ──► std::fs::remove_file 失败

3. 验证最终状态与 expected/ 一致
   tmp/foo.txt ("stable") == expected/foo.txt ("stable") ✓
```

---

## 6. 风险、边界与改进建议

### 6.1 当前风险

#### 6.1.1 错误信息不够具体

当前错误信息：
```
Failed to delete file missing.txt: No such file or directory (os error 2)
```

虽然包含了文件名，但对于用户来说，可能不清楚这是补丁中的路径问题还是文件系统问题。

#### 6.1.2 无部分成功机制

当前实现中，如果一个补丁包含多个操作，任何一个操作失败都会导致整个补丁失败。这在某些场景下可能是期望的行为，但也可能给用户带来不便。

### 6.2 边界情况

| 边界情况 | 当前行为 | 备注 |
|----------|----------|------|
| 删除不存在的文件 | 失败 | 本场景测试的边界 |
| 删除目录 | 失败 | 由 `012_delete_directory_fails` 测试 |
| 删除符号链接 | 删除链接本身 | 未明确测试 |
| 删除无权限文件 | 失败 | 依赖操作系统权限检查 |
| 相对路径 | 相对于当前工作目录 | 由 `cwd` 参数控制 |
| 绝对路径 | 直接使用 | 规范建议避免使用 |

### 6.3 改进建议

#### 6.3.1 增强错误信息

建议添加更详细的错误上下文：

```rust
.with_context(|| format!(
    "Failed to delete file '{}' specified in patch. \
     The file does not exist in the current working directory '{}'",
    path.display(),
    std::env::current_dir().unwrap_or_default().display()
))?
```

#### 6.3.2 添加 "强制删除" 选项

考虑添加一个可选的 `force` 标志，允许删除不存在的文件时不报错：

```
*** Begin Patch
*** Delete File: missing.txt (force)
*** End Patch
```

这在幂等性脚本中可能有用。

#### 6.3.3 改进测试覆盖

建议添加以下测试场景：

1. **删除符号链接**: 验证是删除链接还是链接目标
2. **删除只读文件**: 验证权限处理
3. **删除被其他进程占用的文件**: 验证 Windows 上的行为
4. **删除路径中包含不存在的目录**: 验证路径解析

#### 6.3.4 文档改进

在 `apply_patch_tool_instructions.md` 中明确说明：
- 删除文件操作要求文件必须存在
- 删除操作失败时的错误行为
- 建议在使用删除前先确认文件存在

### 6.4 相关 Issue 追踪

建议关注以下潜在问题：

1. **跨平台一致性**: Windows 和 Unix 在文件删除行为上的差异
2. **并发安全**: 多个 apply_patch 实例同时操作时的竞态条件
3. **大文件处理**: 虽然删除操作本身不涉及文件内容，但 UpdateFile 操作需要读取文件

---

## 7. 总结

`007_rejects_missing_file_delete` 是一个关键的负面测试场景，它验证了 `apply_patch` 工具在删除不存在文件时的错误处理能力。该场景确保：

1. **错误被正确报告**: 通过非零退出码和 stderr 错误信息
2. **状态保持一致**: 已存在的文件不受影响
3. **行为可预测**: 用户可以依赖这一行为进行错误处理

该场景与 `020_delete_file_success` 形成对比，共同构成了删除操作的完整测试覆盖（成功和失败路径）。

---

## 附录：相关文件完整列表

### 实现文件
- `codex-rs/apply-patch/src/lib.rs` - 核心库实现
- `codex-rs/apply-patch/src/parser.rs` - 补丁解析器
- `codex-rs/apply-patch/src/standalone_executable.rs` - CLI 入口
- `codex-rs/apply-patch/src/invocation.rs` - 调用解析
- `codex-rs/apply-patch/src/seek_sequence.rs` - 序列匹配
- `codex-rs/apply-patch/src/main.rs` - 二进制入口

### 测试文件
- `codex-rs/apply-patch/tests/all.rs` - 测试入口
- `codex-rs/apply-patch/tests/suite/mod.rs` - 测试模块组织
- `codex-rs/apply-patch/tests/suite/scenarios.rs` - 场景测试框架
- `codex-rs/apply-patch/tests/suite/cli.rs` - CLI 测试
- `codex-rs/apply-patch/tests/suite/tool.rs` - 工具测试

### 测试场景
- `codex-rs/apply-patch/tests/fixtures/scenarios/007_rejects_missing_file_delete/` - 本场景
- `codex-rs/apply-patch/tests/fixtures/scenarios/020_delete_file_success/` - 成功删除场景
- `codex-rs/apply-patch/tests/fixtures/scenarios/012_delete_directory_fails/` - 删除目录失败场景

### 文档
- `codex-rs/apply-patch/apply_patch_tool_instructions.md` - 工具使用说明
- `codex-rs/apply-patch/tests/fixtures/scenarios/README.md` - 场景测试规范
