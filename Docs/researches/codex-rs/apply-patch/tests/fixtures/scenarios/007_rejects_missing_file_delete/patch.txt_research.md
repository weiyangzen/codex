# 研究文档：007_rejects_missing_file_delete/patch.txt

## 场景与职责

### 测试场景概述

`007_rejects_missing_file_delete` 是 `codex-apply-patch` 组件的一个集成测试场景，专门用于验证**删除不存在文件时的错误处理行为**。该测试确保当 patch 尝试删除一个不存在的文件时，系统能够正确地拒绝该操作并保持文件系统状态不变。

### 测试目录结构

```
codex-rs/apply-patch/tests/fixtures/scenarios/007_rejects_missing_file_delete/
├── patch.txt          # 待测试的 patch 文件
├── input/             # 测试前的初始文件状态
│   └── foo.txt        # 内容为 "stable\n"
└── expected/          # 测试后的期望文件状态
    └── foo.txt        # 内容为 "stable\n"（保持不变）
```

### 测试目标

1. **验证错误处理**：当 patch 尝试删除不存在的文件 `missing.txt` 时，apply-patch 工具应该返回错误
2. **验证原子性**：错误发生时，不应影响任何已存在的文件（`foo.txt` 应保持不变）
3. **验证状态一致性**：测试期望文件系统状态与输入状态完全一致，说明没有任何修改被应用

---

## 功能点目的

### Patch 文件内容分析

```
*** Begin Patch
*** Delete File: missing.txt
*** End Patch
```

这是一个极简的 delete 类型 patch，意图删除名为 `missing.txt` 的文件。关键特点是：

- **目标文件不存在**：`input/` 目录中只有 `foo.txt`，没有 `missing.txt`
- **无其他操作**：patch 只包含一个删除操作，没有其他文件修改

### 核心功能验证点

| 功能点 | 描述 |
|--------|------|
| Delete File 操作 | 验证 `*** Delete File: <path>` 语法的解析和执行 |
| 文件存在性检查 | 验证系统在执行删除前是否正确检查文件是否存在 |
| 错误传播 | 验证 I/O 错误（文件不存在）是否正确向上传播 |
| 失败时的状态保持 | 验证操作失败后，文件系统保持原状 |

---

## 具体技术实现

### 1. Patch 解析流程

#### 1.1 解析入口

**文件**: `codex-rs/apply-patch/src/parser.rs`

```rust
pub fn parse_patch(patch: &str) -> Result<ApplyPatchArgs, ParseError> {
    let mode = if PARSE_IN_STRICT_MODE {
        ParseMode::Strict
    } else {
        ParseMode::Lenient
    };
    parse_patch_text(patch, mode)
}
```

对于本测试中的 patch，解析流程：
1. 识别 `*** Begin Patch` 起始标记
2. 调用 `parse_one_hunk()` 解析单个 hunk
3. 识别 `*** Delete File: ` 前缀，创建 `Hunk::DeleteFile { path: PathBuf::from("missing.txt") }`
4. 识别 `*** End Patch` 结束标记

#### 1.2 DeleteFile Hunk 结构

```rust
// parser.rs:58-76
pub enum Hunk {
    AddFile {
        path: PathBuf,
        contents: String,
    },
    DeleteFile {
        path: PathBuf,  // 本测试中的类型
    },
    UpdateFile {
        path: PathBuf,
        move_path: Option<PathBuf>,
        chunks: Vec<UpdateFileChunk>,
    },
}
```

#### 1.3 Delete File 解析逻辑

**文件**: `codex-rs/apply-patch/src/parser.rs:271-278`

```rust
else if let Some(path) = first_line.strip_prefix(DELETE_FILE_MARKER) {
    // Delete File
    return Ok((
        DeleteFile {
            path: PathBuf::from(path),
        },
        1,  // Delete hunk 只占用 1 行
    ));
}
```

### 2. Patch 应用流程

#### 2.1 应用入口

**文件**: `codex-rs/apply-patch/src/lib.rs:183-213`

```rust
pub fn apply_patch(
    patch: &str,
    stdout: &mut impl std::io::Write,
    stderr: &mut impl std::io::Write,
) -> Result<(), ApplyPatchError> {
    let hunks = match parse_patch(patch) {
        Ok(source) => source.hunks,
        Err(e) => { /* 错误处理 */ }
    };
    apply_hunks(&hunks, stdout, stderr)?;
    Ok(())
}
```

#### 2.2 Hunk 应用到文件系统

**文件**: `codex-rs/apply-patch/src/lib.rs:279-339`

```rust
fn apply_hunks_to_files(hunks: &[Hunk]) -> anyhow::Result<AffectedPaths> {
    // ...
    for hunk in hunks {
        match hunk {
            Hunk::AddFile { path, contents } => { /* ... */ }
            Hunk::DeleteFile { path } => {
                std::fs::remove_file(path)
                    .with_context(|| format!("Failed to delete file {}", path.display()))?;
                deleted.push(path.clone());
            }
            Hunk::UpdateFile { /* ... */ } => { /* ... */ }
        }
    }
    Ok(AffectedPaths { added, modified, deleted })
}
```

#### 2.3 关键：文件不存在时的错误处理

当 `std::fs::remove_file(path)` 被调用时，如果文件不存在，会返回 `std::io::Error`（错误类型为 `ErrorKind::NotFound`）。该错误通过 `with_context` 包装后向上传播。

**错误转换链**:
1. `std::fs::remove_file()` 返回 `Err(std::io::Error)`
2. `with_context()` 包装为 `anyhow::Error`
3. `apply_hunks_to_files()` 返回 `Err(anyhow::Error)`
4. `apply_hunks()` 捕获错误并转换为 `ApplyPatchError::IoError`

**文件**: `codex-rs/apply-patch/src/lib.rs:253-265`

```rust
match apply_hunks_to_files(hunks) {
    Ok(affected) => { /* 成功处理 */ }
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
}
```

### 3. 测试框架实现

#### 3.1 场景测试运行器

**文件**: `codex-rs/apply-patch/tests/suite/scenarios.rs:10-63`

```rust
#[test]
fn test_apply_patch_scenarios() -> anyhow::Result<()> {
    let scenarios_dir = repo_root()?
        .join("codex-rs")
        .join("apply-patch")
        .join("tests")
        .join("fixtures")
        .join("scenarios");
    for scenario in fs::read_dir(scenarios_dir)? {
        let scenario = scenario?;
        let path = scenario.path();
        if path.is_dir() {
            run_apply_patch_scenario(&path)?;
        }
    }
    Ok(())
}
```

#### 3.2 单个场景执行逻辑

```rust
fn run_apply_patch_scenario(dir: &Path) -> anyhow::Result<()> {
    let tmp = tempdir()?;

    // 1. 复制 input 文件到临时目录
    let input_dir = dir.join("input");
    if input_dir.is_dir() {
        copy_dir_recursive(&input_dir, tmp.path())?;
    }

    // 2. 读取 patch.txt
    let patch = fs::read_to_string(dir.join("patch.txt"))?;

    // 3. 执行 apply_patch（注意：不检查 exit status）
    Command::new(codex_utils_cargo_bin::cargo_bin("apply_patch")?)
        .arg(patch)
        .current_dir(tmp.path())
        .output()?;

    // 4. 比较最终状态与 expected 状态
    let expected_dir = dir.join("expected");
    let expected_snapshot = snapshot_dir(&expected_dir)?;
    let actual_snapshot = snapshot_dir(tmp.path())?;

    assert_eq!(
        actual_snapshot,
        expected_snapshot,
        "Scenario {} did not match expected final state",
        dir.display()
    );

    Ok(())
}
```

#### 3.3 关键设计：不检查 Exit Status

测试框架**故意不检查 exit status**，而是只比较最终文件系统状态。这意味着：
- 即使 apply-patch 返回非零退出码（本测试的预期行为）
- 只要文件系统状态与 `expected/` 一致，测试就通过

这种设计允许测试用例表达"操作失败且无副作用"的语义。

### 4. 目录快照机制

**文件**: `codex-rs/apply-patch/tests/suite/scenarios.rs:65-105`

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
enum Entry {
    File(Vec<u8>),
    Dir,
}

fn snapshot_dir(root: &Path) -> anyhow::Result<BTreeMap<PathBuf, Entry>> {
    // 递归遍历目录，构建路径到内容的映射
}
```

对于本测试：
- `input/foo.txt` 和 `expected/foo.txt` 内容相同（都是 `"stable\n"`）
- `expected/` 目录中没有 `missing.txt`
- 测试验证 apply-patch 失败后，`foo.txt` 未被修改，`missing.txt` 也未被创建

---

## 关键代码路径与文件引用

### 核心文件清单

| 文件路径 | 职责描述 |
|----------|----------|
| `codex-rs/apply-patch/src/parser.rs` | Patch 语法解析，包括 `DeleteFile` hunk 的解析 |
| `codex-rs/apply-patch/src/lib.rs` | Patch 应用逻辑，`apply_hunks_to_files()` 函数 |
| `codex-rs/apply-patch/src/standalone_executable.rs` | CLI 入口，处理命令行参数和 stdin |
| `codex-rs/apply-patch/tests/suite/scenarios.rs` | 场景测试框架，`run_apply_patch_scenario()` |
| `codex-rs/apply-patch/apply_patch_tool_instructions.md` | Patch 语法规范文档 |

### 关键代码路径流程图

```
patch.txt (Delete File: missing.txt)
    │
    ▼
┌─────────────────────────────────────┐
│  standalone_executable::run_main()  │
│  - 读取 patch 参数                  │
└─────────────────┬───────────────────┘
                  │
                  ▼
┌─────────────────────────────────────┐
│  lib::apply_patch()                 │
│  - 解析 patch                       │
│  - 调用 apply_hunks()               │
└─────────────────┬───────────────────┘
                  │
                  ▼
┌─────────────────────────────────────┐
│  lib::apply_hunks()                 │
│  - 调用 apply_hunks_to_files()      │
└─────────────────┬───────────────────┘
                  │
                  ▼
┌─────────────────────────────────────┐
│  lib::apply_hunks_to_files()        │
│  - 匹配 Hunk::DeleteFile            │
│  - 调用 std::fs::remove_file()      │
│  - ❌ 文件不存在，返回 IO Error     │
└─────────────────┬───────────────────┘
                  │
                  ▼
┌─────────────────────────────────────┐
│  错误向上传播                        │
│  - 转换为 ApplyPatchError::IoError  │
│  - 写入 stderr                      │
│  - 返回 Err(exit_code=1)            │
└─────────────────────────────────────┘
```

---

## 依赖与外部交互

### 1. 内部依赖

| 依赖模块 | 用途 |
|----------|------|
| `codex-utils-cargo-bin` | 测试中找到 apply_patch 二进制文件的路径 |

### 2. 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `anyhow` | 错误处理和上下文包装 |
| `thiserror` | 定义 `ApplyPatchError` 错误类型 |
| `similar` | 生成 unified diff（主要用于 Update 操作）|
| `tempfile` | 测试时创建临时目录 |
| `pretty_assertions` | 测试失败时显示美观的差异对比 |

### 3. 标准库交互

| 模块 | 用途 |
|------|------|
| `std::fs::remove_file()` | 实际执行文件删除操作 |
| `std::fs::metadata()` | 检查文件存在性（在其他代码路径中）|
| `std::io::Write` | 写入 stdout/stderr |

### 4. 测试框架交互

```rust
// 使用 std::process::Command 调用 apply_patch 二进制
Command::new(codex_utils_cargo_bin::cargo_bin("apply_patch")?)
    .arg(patch)
    .current_dir(tmp.path())
    .output()?;
```

---

## 风险、边界与改进建议

### 1. 当前实现的风险点

#### 1.1 错误信息可读性

**现状**：当文件不存在时，错误信息来自 `std::fs::remove_file()` 的底层错误，可能不够友好。

**示例错误输出**：
```
Failed to delete file missing.txt: No such file or directory (os error 2)
```

**建议**：可以添加更明确的错误提示，例如：
```
Cannot delete 'missing.txt': file does not exist
```

#### 1.2 部分失败的处理

**现状**：根据 `015_failure_after_partial_success_leaves_changes` 测试，当前实现**不会回滚**已成功的操作。如果 patch 包含多个操作，前面的操作成功后，后面的操作失败，已成功的修改会保留。

**风险**：对于本测试场景（单操作失败），这不是问题。但对于多操作 patch，可能导致文件系统处于不一致状态。

### 2. 边界情况分析

| 边界情况 | 当前行为 | 风险等级 |
|----------|----------|----------|
| 删除不存在的文件 | 返回错误，无副作用 | ✅ 已正确处理 |
| 删除目录而非文件 | 返回错误（见 `012_delete_directory_fails`） | ✅ 已正确处理 |
| 删除无权限的文件 | 返回 Permission Denied 错误 | ✅ 标准行为 |
| 路径包含特殊字符 | 正常处理 | ✅ 标准行为 |
| 空 patch | 返回错误（见 `005_rejects_empty_patch`） | ✅ 已正确处理 |

### 3. 改进建议

#### 3.1 增强错误类型

**文件**: `codex-rs/apply-patch/src/lib.rs:37-51`

当前 `ApplyPatchError` 对删除操作的错误没有细分：

```rust
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

建议添加更具体的错误变体：

```rust
pub enum ApplyPatchError {
    // ... 现有变体
    #[error("Cannot delete '{path}': file does not exist")]
    DeleteFileNotFound { path: PathBuf },
}
```

#### 3.2 预验证机制

在执行任何操作前，可以先进行预验证：

```rust
fn validate_hunks(hunks: &[Hunk]) -> Result<(), ApplyPatchError> {
    for hunk in hunks {
        match hunk {
            Hunk::DeleteFile { path } => {
                if !path.exists() {
                    return Err(ApplyPatchError::DeleteFileNotFound {
                        path: path.clone()
                    });
                }
            }
            // ... 其他验证
        }
    }
    Ok(())
}
```

这样可以实现"全有或全无"（atomic）的语义，避免部分成功的情况。

#### 3.3 添加日志/调试信息

当前实现只在 stderr 输出错误信息。建议添加更详细的日志：

```rust
// 在尝试删除前记录
eprintln!("Attempting to delete: {}", path.display());

// 删除成功后记录
eprintln!("Successfully deleted: {}", path.display());
```

### 4. 相关测试场景

本测试与其他测试场景的关系：

| 测试场景 | 关系 | 说明 |
|----------|------|------|
| `020_delete_file_success` | 正向对照 | 验证删除存在的文件成功 |
| `012_delete_directory_fails` | 边界对照 | 验证删除目录失败 |
| `009_requires_existing_file_for_update` | 类似模式 | Update 操作也需要目标文件存在 |
| `015_failure_after_partial_success_leaves_changes` | 副作用验证 | 验证失败时的状态保持行为 |

### 5. 文档改进建议

1. **在 `apply_patch_tool_instructions.md` 中添加错误处理说明**：
   - 明确说明当文件不存在时 patch 会失败
   - 建议 LLM 在删除前先确认文件存在

2. **添加开发者注释**：
   - 在 `apply_hunks_to_files()` 函数中添加注释，说明错误传播机制
   - 解释为什么使用 `with_context` 包装错误

---

## 总结

`007_rejects_missing_file_delete` 测试场景是一个**负向测试用例**（negative test case），用于验证 `apply-patch` 工具在面对无效操作（删除不存在的文件）时的健壮性。

### 核心要点

1. **测试目标**：验证删除不存在文件时返回错误，且不产生副作用
2. **实现机制**：依赖 `std::fs::remove_file()` 的错误传播
3. **验证方式**：比较操作前后的文件系统快照
4. **设计哲学**：失败时保持文件系统状态不变（fail-safe）

### 代码质量评估

| 维度 | 评分 | 说明 |
|------|------|------|
| 正确性 | ✅ 优秀 | 正确处理文件不存在的情况 |
| 错误处理 | ✅ 良好 | 错误向上传播，有上下文信息 |
| 原子性 | ⚠️ 一般 | 单操作场景安全，多操作场景可能部分成功 |
| 可测试性 | ✅ 优秀 | 快照对比机制清晰可靠 |
| 文档完整性 | ⚠️ 一般 | 缺少详细的错误处理说明 |
