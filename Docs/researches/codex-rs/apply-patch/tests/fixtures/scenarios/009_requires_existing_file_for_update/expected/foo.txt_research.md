# Research: foo.txt in 009_requires_existing_file_for_update

## 场景与职责

### 测试场景定位

`009_requires_existing_file_for_update` 是 `codex-apply-patch` 测试套件中的一个**负面测试场景（negative test case）**，用于验证当 `apply_patch` 工具尝试更新一个不存在的文件时，系统应该正确地报告错误并且不创建新文件。

### 目录结构

```
codex-rs/apply-patch/tests/fixtures/scenarios/009_requires_existing_file_for_update/
├── input/
│   └── foo.txt          # 输入文件，内容为 "stable"
├── expected/
│   └── foo.txt          # 预期输出文件，内容仍为 "stable"（保持不变）
└── patch.txt            # 补丁文件，尝试更新不存在的 missing.txt
```

### 核心职责

该测试场景的核心职责是验证以下行为：

1. **错误处理**：当 `Update File` 操作的目标文件不存在时，`apply_patch` 应该返回错误
2. **原子性保证**：即使补丁中包含对其他有效文件的操作，当某个更新操作失败时，已执行的操作应该被保留（非事务性）
3. **文件系统不变性**：输入目录中的文件在测试执行后应该保持原样

---

## 功能点目的

### 测试目的详解

该测试验证 `apply_patch` 的以下关键行为：

| 验证点 | 预期行为 |
|--------|----------|
| 文件存在性检查 | 在执行 `Update File` 操作前，必须验证目标文件是否存在 |
| 错误报告 | 当目标文件不存在时，应输出清晰的错误信息到 stderr |
| 非破坏性 | 错误发生后，不应创建目标文件（区别于 `Add File`） |
| 部分应用行为 | 如果补丁包含多个操作，前面的成功操作应保留，后续操作失败 |

### 与其他场景的对比

| 场景编号 | 名称 | 测试目的 | 与 009 的区别 |
|----------|------|----------|---------------|
| 001 | add_file | 验证文件创建 | 创建新文件 vs 更新必须存在的文件 |
| 007 | rejects_missing_file_delete | 验证删除不存在文件的错误 | 删除 vs 更新 |
| 008 | rejects_empty_update_hunk | 验证空更新块错误 | 语法错误 vs 文件不存在 |
| 015 | failure_after_partial_success | 验证部分成功后的状态 | 多操作场景下的错误处理 |

---

## 具体技术实现

### 1. 补丁格式解析

测试使用的 `patch.txt` 内容：

```
*** Begin Patch
*** Update File: missing.txt
@@
-old
+new
*** End Patch
```

**关键解析点**：
- `*** Update File: missing.txt` - 声明更新操作，目标文件为 `missing.txt`
- `@@` - 变更上下文标记（空上下文）
- `-old` / `+new` - 尝试将 "old" 替换为 "new"
- `missing.txt` 在 `input/` 目录中**不存在**

### 2. 错误触发机制

当 `apply_patch` 执行时，错误触发流程如下：

```rust
// lib.rs: derive_new_contents_from_chunks 函数
fn derive_new_contents_from_chunks(
    path: &Path,
    chunks: &[UpdateFileChunk],
) -> std::result::Result<AppliedPatch, ApplyPatchError> {
    let original_contents = match std::fs::read_to_string(path) {
        Ok(contents) => contents,
        Err(err) => {
            return Err(ApplyPatchError::IoError(IoError {
                context: format!("Failed to read file to update {}", path.display()),
                source: err,
            }));
        }
    };
    // ...
}
```

**错误信息**：
```
Failed to read file to update missing.txt: No such file or directory (os error 2)
```

### 3. 测试执行流程

测试通过 `tests/suite/scenarios.rs` 中的 `run_apply_patch_scenario` 函数执行：

```rust
fn run_apply_patch_scenario(dir: &Path) -> anyhow::Result<()> {
    let tmp = tempdir()?;
    
    // 1. 复制 input/ 目录到临时目录
    let input_dir = dir.join("input");
    if input_dir.is_dir() {
        copy_dir_recursive(&input_dir, tmp.path())?;
    }
    
    // 2. 读取 patch.txt
    let patch = fs::read_to_string(dir.join("patch.txt"))?;
    
    // 3. 执行 apply_patch（不检查退出状态）
    Command::new(codex_utils_cargo_bin::cargo_bin("apply_patch")?)
        .arg(patch)
        .current_dir(tmp.path())
        .output()?;
    
    // 4. 比较实际结果与 expected/ 目录
    let expected_dir = dir.join("expected");
    let expected_snapshot = snapshot_dir(&expected_dir)?;
    let actual_snapshot = snapshot_dir(tmp.path())?;
    
    assert_eq!(actual_snapshot, expected_snapshot, ...);
    Ok(())
}
```

### 4. 为什么 expected/foo.txt 内容是 "stable"

`expected/foo.txt` 内容为 `stable`，这表明：

1. **测试期望文件保持不变**：由于补丁尝试更新的是 `missing.txt` 而不是 `foo.txt`，`foo.txt` 应该完全不受影响
2. **验证隔离性**：证明 `apply_patch` 不会意外修改未指定的文件
3. **证明错误处理**：`missing.txt` 的更新失败不会波及 `foo.txt`

---

## 关键代码路径与文件引用

### 核心代码文件

| 文件路径 | 职责 |
|----------|------|
| `codex-rs/apply-patch/src/lib.rs` | 主库实现，包含 `apply_patch()` 和 `derive_new_contents_from_chunks()` |
| `codex-rs/apply-patch/src/parser.rs` | 补丁格式解析器，定义 `Hunk::UpdateFile` 等结构 |
| `codex-rs/apply-patch/src/standalone_executable.rs` | CLI 入口，处理参数和 stdin |
| `codex-rs/apply-patch/src/seek_sequence.rs` | 行匹配算法，用于在文件中定位变更上下文 |

### 关键函数调用链

```
apply_patch() [lib.rs:183]
├── parse_patch() [parser.rs:106]
│   └── 解析出 Hunk::UpdateFile { path: "missing.txt", ... }
└── apply_hunks() [lib.rs:216]
    └── apply_hunks_to_files() [lib.rs:279]
        └── derive_new_contents_from_chunks() [lib.rs:348]
            └── std::fs::read_to_string("missing.txt")  <-- 错误发生点
```

### 测试相关文件

| 文件路径 | 职责 |
|----------|------|
| `codex-rs/apply-patch/tests/suite/scenarios.rs` | 场景测试框架，`run_apply_patch_scenario()` 函数 |
| `codex-rs/apply-patch/tests/suite/tool.rs` | 单元测试，包含 `test_apply_patch_cli_requires_existing_file_for_update` |
| `codex-rs/apply-patch/tests/fixtures/scenarios/README.md` | 场景测试规范文档 |

### 单元测试对应

在 `tool.rs` 中有直接对应的单元测试：

```rust
#[test]
fn test_apply_patch_cli_requires_existing_file_for_update() -> anyhow::Result<()> {
    let tmp = tempdir()?;
    
    apply_patch_command(tmp.path())?
        .arg("*** Begin Patch\n*** Update File: missing.txt\n@@\n-old\n+new\n*** End Patch")
        .assert()
        .failure()
        .stderr(
            "Failed to read file to update missing.txt: No such file or directory (os error 2)\n",
        );
    
    Ok(())
}
```

---

## 依赖与外部交互

### 1. 内部依赖

```
codex-apply-patch
├── codex-utils-cargo-bin (测试依赖，用于定位二进制文件)
├── anyhow (错误处理)
├── similar (文本差异计算)
├── thiserror (错误类型定义)
├── tree-sitter (Bash 脚本解析)
└── tree-sitter-bash
```

### 2. 外部系统依赖

- **文件系统**：直接操作文件系统的读取和写入
- **临时目录**：测试使用 `tempfile` 创建隔离的测试环境
- **进程执行**：通过 `std::process::Command` 执行 `apply_patch` 二进制文件

### 3. 与 codex-core 的集成

`apply_patch` 是 Codex CLI 的核心工具之一，通过以下方式集成：

- **工具指令**：`apply_patch_tool_instructions.md` 定义了 AI 模型如何生成补丁
- **调用约定**：`CODEX_CORE_APPLY_PATCH_ARG1` 常量定义了自调用参数
- **验证 API**：`invocation.rs` 中的 `maybe_parse_apply_patch_verified()` 用于核心逻辑验证

### 4. 补丁格式规范

补丁格式定义在 `apply_patch_tool_instructions.md` 中：

```
Patch := Begin { FileOp } End
Begin := "*** Begin Patch" NEWLINE
End := "*** End Patch" NEWLINE
FileOp := AddFile | DeleteFile | UpdateFile
UpdateFile := "*** Update File: " path NEWLINE [ MoveTo ] { Hunk }
Hunk := "@@" [ header ] NEWLINE { HunkLine }
HunkLine := (" " | "-" | "+") text NEWLINE
```

---

## 风险、边界与改进建议

### 1. 当前风险点

#### 风险 1：非事务性行为

**问题**：`apply_patch` 不是原子操作。如果补丁包含多个操作，前面的操作成功后，后续操作失败，会导致文件系统处于不一致状态。

**验证**：场景 `015_failure_after_partial_success_leaves_changes` 专门测试此行为。

```rust
// lib.rs:279-339 apply_hunks_to_files 函数
// 每个 hunk 是独立执行的，没有回滚机制
for hunk in hunks {
    match hunk {
        Hunk::AddFile { ... } => { ... }
        Hunk::DeleteFile { ... } => { ... }
        Hunk::UpdateFile { ... } => { ... }  // 失败时前面的操作已生效
    }
}
```

#### 风险 2：错误信息一致性

**问题**：错误信息依赖于操作系统，不同平台的 `std::io::Error` 描述可能不同。

```rust
// 错误信息格式
format!("Failed to read file to update {}", path.display())
// 实际错误来自操作系统，如 "No such file or directory (os error 2)"
```

#### 风险 3：路径解析歧义

**问题**：相对路径的解析依赖于当前工作目录，在复杂场景（如 `cd` + heredoc）中可能出现意外行为。

### 2. 边界情况

| 边界情况 | 当前行为 | 备注 |
|----------|----------|------|
| 更新符号链接 | 跟随链接更新目标 | 使用 `fs::metadata()` 而非 `fs::symlink_metadata()` |
| 更新目录 | 返回 IO 错误 | 尝试将目录作为文件读取 |
| 空文件名 | 解析错误 | parser 会拒绝 |
| 绝对路径 | 技术上支持 | 但工具文档要求使用相对路径 |
| 并发更新 | 无保护 | 依赖文件系统的原子性 |

### 3. 改进建议

#### 建议 1：添加预检机制

在执行任何操作前，先验证所有 `Update File` 操作的目标文件是否存在：

```rust
// 建议添加的预检代码
for hunk in hunks {
    if let Hunk::UpdateFile { path, .. } = hunk {
        if !path.exists() {
            return Err(ApplyPatchError::IoError(...));
        }
    }
}
```

**优点**：
- 更早发现错误
- 避免部分应用的问题

**缺点**：
- 与 `015` 场景的期望行为冲突（测试期望部分成功）

#### 建议 2：改进错误类型

当前错误类型不够精确：

```rust
// 当前
#[error(transparent)]
IoError(#[from] IoError),

// 建议
#[error("File not found: {path}")]
FileNotFound { path: PathBuf },
```

#### 建议 3：添加 dry-run 模式

允许用户在不实际修改文件的情况下验证补丁：

```bash
apply_patch --dry-run '*** Begin Patch...'
```

#### 建议 4：统一测试场景与单元测试

当前场景测试（`009_requires_existing_file_for_update`）和单元测试（`test_apply_patch_cli_requires_existing_file_for_update`）有重复逻辑。建议：

1. 场景测试专注于端到端行为验证
2. 单元测试专注于边界条件和错误处理
3. 考虑使用属性测试（property-based testing）生成更多边界情况

### 4. 相关安全考虑

- **路径遍历**：当前实现使用 `Path::join()`，理论上可能受到路径遍历攻击（如 `*** Update File: ../../../etc/passwd`）
- **建议**：在解析后验证所有路径都在工作目录内

```rust
// 建议添加的路径验证
let canonical_path = path.canonicalize()?;
let canonical_cwd = cwd.canonicalize()?;
if !canonical_path.starts_with(&canonical_cwd) {
    return Err(ApplyPatchError::PathTraversal { path });
}
```

---

## 总结

`009_requires_existing_file_for_update/expected/foo.txt` 是一个简单的测试夹具文件，其存在意义在于：

1. **验证隔离性**：确保 `apply_patch` 不会意外修改未指定的文件
2. **提供基准**：为场景测试框架提供一个可比较的预期状态
3. **文档化行为**：通过文件内容 "stable" 直观表达 "文件应保持不变" 的期望

该测试场景是 `codex-apply-patch` 错误处理测试套件的重要组成部分，与 `007_rejects_missing_file_delete` 和 `015_failure_after_partial_success_leaves_changes` 共同构成了完整的错误处理验证矩阵。
