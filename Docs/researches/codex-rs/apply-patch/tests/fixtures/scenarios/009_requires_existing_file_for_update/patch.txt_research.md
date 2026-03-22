# 研究文档：009_requires_existing_file_for_update 测试场景

## 1. 场景与职责

### 1.1 测试场景定位

该测试场景位于 `codex-rs/apply-patch/tests/fixtures/scenarios/009_requires_existing_file_for_update/`，是 `apply-patch` 组件的端到端（E2E）测试套件中的第 9 个场景。该场景专门测试**更新文件操作（Update File）在目标文件不存在时的错误处理行为**。

### 1.2 目录结构

```
009_requires_existing_file_for_update/
├── patch.txt      # 待应用的补丁文件
├── input/         # 测试前的文件系统状态
│   └── foo.txt    # 存在的文件（内容为 "stable"）
└── expected/      # 测试后的预期文件系统状态
    └── foo.txt    # 与 input 相同（内容为 "stable"）
```

### 1.3 核心职责

该场景验证以下关键行为：
- 当补丁尝试更新一个不存在的文件（`missing.txt`）时，`apply_patch` 应该**失败**
- 失败时应该返回清晰的错误信息
- 失败时不应该修改任何已存在的文件（保持原子性）

---

## 2. 功能点目的

### 2.1 测试目标

该场景的核心目的是验证 `apply_patch` 工具在执行 **Update File** 操作时的前置条件检查：

| 检查项 | 预期行为 |
|--------|----------|
| 目标文件存在性 | 必须存在，否则报错 |
| 错误信息清晰度 | 应包含文件名和系统错误原因 |
| 副作用控制 | 不应修改任何文件（包括 input/ 中的 foo.txt） |

### 2.2 补丁内容分析

**patch.txt 内容：**
```
*** Begin Patch
*** Update File: missing.txt
@@
-old
+new
*** End Patch
```

**关键特征：**
- 使用 `*** Update File:` 指令指定要更新的文件为 `missing.txt`
- 该文件在 `input/` 目录中**不存在**
- `@@` 是变更上下文标记（change context marker）
- `-old` 表示期望找到的旧内容
- `+new` 表示要替换的新内容

### 2.3 预期行为

由于 `missing.txt` 不存在，`apply_patch` 应该：
1. 解析补丁成功（语法正确）
2. 尝试读取 `missing.txt` 失败
3. 返回 I/O 错误：`Failed to read file to update missing.txt: No such file or directory`
4. 退出码非零（表示失败）
5. **不修改** `input/foo.txt`（保持原样）

---

## 3. 具体技术实现

### 3.1 补丁解析流程

#### 3.1.1 解析入口

```rust
// codex-rs/apply-patch/src/lib.rs
pub fn apply_patch(
    patch: &str,
    stdout: &mut impl std::io::Write,
    stderr: &mut impl std::io::Write,
) -> Result<(), ApplyPatchError> {
    let hunks = match parse_patch(patch) {
        Ok(source) => source.hunks,
        Err(e) => { /* 处理解析错误 */ }
    };
    apply_hunks(&hunks, stdout, stderr)
}
```

#### 3.1.2 解析 Update File Hunk

```rust
// codex-rs/apply-patch/src/parser.rs
#[derive(Debug, PartialEq, Clone)]
pub enum Hunk {
    AddFile { path: PathBuf, contents: String },
    DeleteFile { path: PathBuf },
    UpdateFile {
        path: PathBuf,
        move_path: Option<PathBuf>,
        chunks: Vec<UpdateFileChunk>,
    },
}

#[derive(Debug, PartialEq, Clone)]
pub struct UpdateFileChunk {
    pub change_context: Option<String>,  // @@ 后的上下文
    pub old_lines: Vec<String>,          // 以 - 开头的行
    pub new_lines: Vec<String>,         // 以 + 开头的行
    pub is_end_of_file: bool,           // 是否包含 *** End of File
}
```

### 3.2 文件更新核心逻辑

#### 3.2.1 derive_new_contents_from_chunks

这是 Update File 操作的核心函数，负责读取原文件并计算新内容：

```rust
// codex-rs/apply-patch/src/lib.rs:348-381
fn derive_new_contents_from_chunks(
    path: &Path,
    chunks: &[UpdateFileChunk],
) -> std::result::Result<AppliedPatch, ApplyPatchError> {
    // 【关键】尝试读取目标文件
    let original_contents = match std::fs::read_to_string(path) {
        Ok(contents) => contents,
        Err(err) => {
            return Err(ApplyPatchError::IoError(IoError {
                context: format!("Failed to read file to update {}", path.display()),
                source: err,
            }));
        }
    };
    // ... 后续处理
}
```

**在本场景中**，由于 `missing.txt` 不存在，`std::fs::read_to_string(path)` 返回 `Err`，导致函数提前返回错误。

#### 3.2.2 行匹配算法（seek_sequence）

如果文件存在，系统会使用 `seek_sequence` 模块进行模糊匹配：

```rust
// codex-rs/apply-patch/src/seek_sequence.rs
pub(crate) fn seek_sequence(
    lines: &[String],
    pattern: &[String],
    start: usize,
    eof: bool,
) -> Option<usize> {
    // 1. 精确匹配
    // 2. 忽略尾部空白匹配
    // 3. 忽略两端空白匹配
    // 4. Unicode 标点符号归一化匹配（如 EN DASH → ASCII -）
}
```

### 3.3 错误处理机制

#### 3.3.1 错误类型定义

```rust
// codex-rs/apply-patch/src/lib.rs
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

#[derive(Debug, Error)]
#[error("{context}: {source}")]
pub struct IoError {
    context: String,
    #[source]
    source: std::io::Error,
}
```

#### 3.3.2 本场景触发的错误链

```
ApplyPatchError::IoError(IoError {
    context: "Failed to read file to update missing.txt",
    source: std::io::Error { kind: NotFound, ... }
})
```

### 3.4 测试执行框架

#### 3.4.1 场景测试驱动

```rust
// codex-rs/apply-patch/tests/suite/scenarios.rs
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
            run_apply_patch_scenario(&path)?;  // 执行每个场景
        }
    }
    Ok(())
}
```

#### 3.4.2 单个场景执行逻辑

```rust
fn run_apply_patch_scenario(dir: &Path) -> anyhow::Result<()> {
    let tmp = tempdir()?;

    // 1. 复制 input/ 到临时目录
    let input_dir = dir.join("input");
    if input_dir.is_dir() {
        copy_dir_recursive(&input_dir, tmp.path())?;
    }

    // 2. 读取 patch.txt
    let patch = fs::read_to_string(dir.join("patch.txt"))?;

    // 3. 执行 apply_patch（不检查退出码）
    Command::new(codex_utils_cargo_bin::cargo_bin("apply_patch")?)
        .arg(patch)
        .current_dir(tmp.path())
        .output()?;

    // 4. 比较结果与 expected/
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

**关键设计**：测试**不检查退出码**，只验证最终文件系统状态。这意味着即使命令失败，只要文件系统状态与 `expected/` 一致，测试就通过。

---

## 4. 关键代码路径与文件引用

### 4.1 核心文件清单

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/apply-patch/src/lib.rs` | 主库实现，包含 `apply_patch()`、`apply_hunks()`、`derive_new_contents_from_chunks()` |
| `codex-rs/apply-patch/src/parser.rs` | 补丁解析器，定义 `Hunk`、`UpdateFileChunk` 等数据结构 |
| `codex-rs/apply-patch/src/seek_sequence.rs` | 行序列匹配算法，支持模糊匹配 |
| `codex-rs/apply-patch/src/standalone_executable.rs` | CLI 入口，处理参数和 stdin |
| `codex-rs/apply-patch/tests/suite/scenarios.rs` | 场景测试框架 |
| `codex-rs/apply-patch/tests/suite/tool.rs` | 集成测试（包含同类测试用例） |

### 4.2 关键代码路径

```
【CLI 入口】
standalone_executable.rs::run_main()
    ↓
【库入口】
lib.rs::apply_patch()
    ↓
【解析补丁】
parser.rs::parse_patch() → ApplyPatchArgs { hunks: [...] }
    ↓
【应用 Hunks】
lib.rs::apply_hunks()
    ↓
【应用到文件系统】
lib.rs::apply_hunks_to_files()
    ↓
【处理 UpdateFile Hunk】
lib.rs::derive_new_contents_from_chunks()
    ↓
【读取原文件 - 本场景在此失败】
std::fs::read_to_string(path) → Err(NotFound)
    ↓
【返回错误】
ApplyPatchError::IoError { context: "Failed to read file to update ..." }
```

### 4.3 相关测试用例

在 `codex-rs/apply-patch/tests/suite/tool.rs` 中有对应的显式测试：

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

## 5. 依赖与外部交互

### 5.1 内部依赖

| 依赖模块 | 用途 |
|---------|------|
| `codex-utils-cargo-bin` | 测试时定位二进制文件路径 |

### 5.2 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `anyhow` | 错误处理和上下文传播 |
| `similar` | 生成统一差异格式（unified diff） |
| `thiserror` | 派生错误类型 |
| `tree-sitter` + `tree-sitter-bash` | 解析 shell heredoc 形式的补丁调用 |
| `tempfile` | 测试时创建临时目录 |
| `assert_cmd` | CLI 测试断言 |

### 5.3 系统交互

| 系统调用 | 用途 | 本场景行为 |
|---------|------|-----------|
| `std::fs::read_to_string()` | 读取待更新文件 | 失败（文件不存在） |
| `std::fs::write()` | 写入更新后的文件 | 未执行 |
| `std::fs::remove_file()` | 删除文件（DeleteFile） | 未执行 |
| `std::fs::create_dir_all()` | 创建父目录 | 未执行 |

---

## 6. 风险、边界与改进建议

### 6.1 当前风险点

#### 6.1.1 错误信息一致性

当前错误信息直接依赖操作系统返回的 I/O 错误描述（如 `"No such file or directory (os error 2)"`）。不同操作系统可能有不同的错误描述，可能导致跨平台测试不稳定。

**建议**：考虑标准化错误信息，或在测试中仅检查关键部分（如 `"Failed to read file to update"`）。

#### 6.1.2 部分成功问题

如果补丁包含多个操作（如先 Add File 再 Update File），而 Update File 失败时，Add File 的操作**已经生效**。这在 `015_failure_after_partial_success_leaves_changes` 场景中有专门测试。

**当前行为**：失败前的修改会保留（非原子性）。

### 6.2 边界情况

| 边界情况 | 当前行为 | 备注 |
|---------|---------|------|
| 更新空文件 | 支持 | `old_lines` 为空即可 |
| 更新符号链接 | 跟随链接 | 使用 `fs::metadata()` 跟随符号链接 |
| 文件被其他进程锁定 | 返回 I/O 错误 | 依赖操作系统行为 |
| 路径遍历攻击（`../../../etc/passwd`） | 相对路径解析 | 依赖调用方验证路径 |

### 6.3 改进建议

#### 6.3.1 原子性增强

**现状**：多 hunk 补丁失败时，已应用的 hunk 不会回滚。

**建议方案**：
1. 预验证阶段：先检查所有目标文件存在性和可写性
2. 或使用临时文件 + 原子重命名策略

```rust
// 伪代码：预验证示例
fn validate_hunks(hunks: &[Hunk]) -> Result<(), ApplyPatchError> {
    for hunk in hunks {
        match hunk {
            Hunk::UpdateFile { path, .. } => {
                if !path.exists() {
                    return Err(ApplyPatchError::IoError(...));
                }
            }
            // ... 其他类型检查
        }
    }
    Ok(())
}
```

#### 6.3.2 错误信息改进

当前错误信息：
```
Failed to read file to update missing.txt: No such file or directory (os error 2)
```

建议增加操作上下文：
```
Failed to apply patch: Update File operation failed for 'missing.txt'
  Caused by: File not found (os error 2)
  Hint: Ensure the file exists before attempting to update it
```

#### 6.3.3 测试覆盖率扩展

建议增加以下边界测试场景：

1. **权限不足**：尝试更新只读文件
2. **目录作为目标**：`*** Update File: directory/`（应失败）
3. **并发修改**：补丁应用过程中文件被其他进程修改
4. **大文件处理**：测试 GB 级文件的更新性能

### 6.4 相关场景索引

| 场景编号 | 名称 | 与本场景关系 |
|---------|------|-------------|
| 001 | add_file | 对比：Add File 不需要目标文件存在 |
| 007 | rejects_missing_file_delete | 相似：Delete File 也需要目标文件存在 |
| 008 | rejects_empty_update_hunk | 相关：Update File 的其他错误情况 |
| 015 | failure_after_partial_success_leaves_changes | 依赖：理解非原子性行为 |

---

## 7. 总结

`009_requires_existing_file_for_update` 是一个关键的负面测试场景（negative test case），它验证了 `apply_patch` 工具在面对不存在的更新目标时的正确错误处理行为。

**核心价值**：
1. 确保工具不会静默失败或创建意外文件
2. 验证错误信息的清晰度和准确性
3. 保证失败时的无副作用（不修改其他文件）

**技术要点**：
- 错误发生在 `derive_new_contents_from_chunks()` 函数的 `std::fs::read_to_string()` 调用
- 错误类型为 `ApplyPatchError::IoError`
- 测试框架通过比较文件系统快照验证行为，而非检查退出码
