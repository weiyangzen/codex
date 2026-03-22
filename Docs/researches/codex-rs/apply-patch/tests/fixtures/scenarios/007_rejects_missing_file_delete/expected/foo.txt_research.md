# 007_rejects_missing_file_delete 场景研究文档

## 场景与职责

### 场景定位

本场景（`007_rejects_missing_file_delete`）是 `codex-apply-patch` 组件的端到端测试用例之一，位于 `codex-rs/apply-patch/tests/fixtures/scenarios/` 目录下。该场景专门用于验证：**当 patch 尝试删除一个不存在的文件时，系统应当拒绝执行该操作，并保持原始文件系统状态不变**。

### 测试目录结构

```
007_rejects_missing_file_delete/
├── input/
│   └── foo.txt          # 输入文件，内容为 "stable"
├── expected/
│   └── foo.txt          # 期望输出，内容仍为 "stable"
└── patch.txt            # Patch 定义，尝试删除不存在的 missing.txt
```

### 核心职责

1. **错误处理验证**：确保系统在尝试删除不存在文件时能够优雅地失败
2. **状态不变性验证**：确认失败操作不会副作用地影响其他现有文件
3. **边界行为定义**：明确 `Delete File` 操作的前置条件——目标文件必须存在

---

## 功能点目的

### 被测试的具体行为

该场景测试 `apply_patch` 工具在以下特定条件下的行为：

| 条件 | 描述 |
|------|------|
| Patch 指令 | `*** Delete File: missing.txt` |
| 文件系统状态 | `foo.txt` 存在，`missing.txt` 不存在 |
| 期望结果 | 操作失败，`foo.txt` 保持原状 |

### 与相关场景的对比

| 场景编号 | 名称 | 目的 | 与 007 的区别 |
|----------|------|------|---------------|
| 005 | rejects_empty_patch | 验证空 patch 被拒绝 | 无文件操作，纯格式验证 |
| 006 | rejects_missing_context | 验证更新时上下文不匹配被拒绝 | Update 操作 vs Delete 操作 |
| 007 | **rejects_missing_file_delete** | **验证删除不存在文件被拒绝** | **Delete 操作的核心边界测试** |
| 009 | requires_existing_file_for_update | 验证更新不存在文件被拒绝 | Update 操作 vs Delete 操作 |
| 012 | delete_directory_fails | 验证删除目录失败 | 目标是目录而非文件 |
| 020 | delete_file_success | 验证成功删除文件 | 目标文件存在，操作应成功 |

### 业务价值

该测试确保 AI 助手通过 `apply_patch` 工具执行文件删除操作时，如果目标文件不存在（可能已被删除或从未创建），系统会：
1. 明确报告错误（通过 stderr 输出）
2. 不创建任何新文件
3. 不改变任何现有文件状态

---

## 具体技术实现

### 1. Patch 格式定义

**文件位置**: `codex-rs/apply-patch/tests/fixtures/scenarios/007_rejects_missing_file_delete/patch.txt`

```
*** Begin Patch
*** Delete File: missing.txt
*** End Patch
```

**语法解析**（根据 `parser.rs`）：
- `*** Begin Patch` / `*** End Patch`: Patch 边界标记
- `*** Delete File: <path>`: 删除文件指令，解析为 `Hunk::DeleteFile { path }`

### 2. 核心数据结构

#### Hunk 枚举（parser.rs 第 58-76 行）

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

#### Delete File 的解析逻辑（parser.rs 第 271-278 行）

```rust
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

### 3. 文件删除执行流程

#### 主入口：apply_hunks_to_files（lib.rs 第 279-339 行）

```rust
fn apply_hunks_to_files(hunks: &[Hunk]) -> anyhow::Result<AffectedPaths> {
    // ...
    for hunk in hunks {
        match hunk {
            Hunk::AddFile { path, contents } => {
                // 创建文件逻辑...
            }
            Hunk::DeleteFile { path } => {
                std::fs::remove_file(path)
                    .with_context(|| format!("Failed to delete file {}", path.display()))?;
                deleted.push(path.clone());
            }
            Hunk::UpdateFile { ... } => {
                // 更新文件逻辑...
            }
        }
    }
    // ...
}
```

#### 关键执行路径

1. **解析阶段**: `parse_patch()` → `parse_one_hunk()` 识别 `DeleteFile` hunk
2. **执行阶段**: `apply_patch()` → `apply_hunks()` → `apply_hunks_to_files()`
3. **文件操作**: 调用 `std::fs::remove_file(path)` 删除文件
4. **错误传播**: 使用 `anyhow::Context` 包装错误信息

### 4. 错误处理机制

当 `std::fs::remove_file()` 失败时（如文件不存在），错误传播路径：

```
std::fs::remove_file() 返回 Err(std::io::ErrorKind::NotFound)
    ↓
with_context() 添加上下文: "Failed to delete file <path>"
    ↓
? 操作符将错误返回给 apply_hunks_to_files 的调用者
    ↓
apply_hunks() 捕获错误，写入 stderr，转换为 ApplyPatchError::IoError
    ↓
standalone_executable::run_main() 返回非零退出码 (1)
```

### 5. 测试框架集成

#### 场景测试执行器（tests/suite/scenarios.rs 第 30-63 行）

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
    
    // 3. 执行 apply_patch（**不检查退出码**）
    Command::new(codex_utils_cargo_bin::cargo_bin("apply_patch")?)
        .arg(patch)
        .current_dir(tmp.path())
        .output()?;
    
    // 4. 比较最终状态与 expected/
    let expected_snapshot = snapshot_dir(&expected_dir)?;
    let actual_snapshot = snapshot_dir(tmp.path())?;
    assert_eq!(actual_snapshot, expected_snapshot, ...);
    
    Ok(())
}
```

**关键设计**：测试框架**故意不检查退出码**，只验证最终文件系统状态。这意味着即使 apply_patch 返回错误（非零退出码），只要文件系统状态符合预期，测试就通过。

#### 状态快照比较

测试使用 `BTreeMap<PathBuf, Entry>` 表示文件系统状态：

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
enum Entry {
    File(Vec<u8>),
    Dir,
}
```

对于场景 007：
- **Input**: `{ "foo.txt": File(b"stable\n") }`
- **Expected**: `{ "foo.txt": File(b"stable\n") }`（与 input 相同）
- **实际执行后**: `foo.txt` 保持 "stable"，`missing.txt` 从未被创建

---

## 关键代码路径与文件引用

### 核心源码文件

| 文件路径 | 职责 | 相关行号 |
|----------|------|----------|
| `codex-rs/apply-patch/src/lib.rs` | Patch 应用主逻辑 | 279-339 (apply_hunks_to_files) |
| `codex-rs/apply-patch/src/parser.rs` | Patch 语法解析 | 271-278 (DeleteFile 解析) |
| `codex-rs/apply-patch/src/standalone_executable.rs` | CLI 入口 | 11-58 (run_main) |

### 测试相关文件

| 文件路径 | 职责 | 相关行号 |
|----------|------|----------|
| `codex-rs/apply-patch/tests/suite/scenarios.rs` | 场景测试框架 | 10-126 |
| `codex-rs/apply-patch/tests/fixtures/scenarios/007_rejects_missing_file_delete/patch.txt` | 测试 Patch 定义 | 全文件 |
| `codex-rs/apply-patch/tests/fixtures/scenarios/007_rejects_missing_file_delete/input/foo.txt` | 输入文件 | 全文件 |
| `codex-rs/apply-patch/tests/fixtures/scenarios/007_rejects_missing_file_delete/expected/foo.txt` | 期望输出 | 全文件 |

### 执行时序图

```
测试框架 (scenarios.rs)
    │
    ├─→ 创建临时目录
    ├─→ 复制 input/foo.txt 到临时目录
    │
    ├─→ 执行 apply_patch CLI
    │       │
    │       ├─→ standalone_executable::run_main()
    │       │       │
    │       │       ├─→ apply_patch::apply_patch()
    │       │       │       │
    │       │       │       ├─→ parser::parse_patch() → 识别 DeleteFile hunk
    │       │       │       │
    │       │       │       └─→ apply_hunks_to_files()
    │       │       │               │
    │       │       │               └─→ std::fs::remove_file("missing.txt")
    │       │       │                       │
    │       │       │                       └─→ 返回 Err(NotFound)
    │       │       │
    │       │       └─→ 错误写入 stderr，返回退出码 1
    │       │
    │       └─→ 进程退出 (code=1)
    │
    ├─→ 快照比较：actual vs expected
    │       │
    │       └─→ 两者均为 { foo.txt: "stable" } → 测试通过
    │
    └─→ 清理临时目录
```

---

## 依赖与外部交互

### 1. 内部依赖

| 依赖模块 | 用途 |
|----------|------|
| `parser` | Patch 文本解析为结构化 `Hunk` |
| `invocation` | 处理 shell 脚本形式的 patch 调用（本场景未使用） |
| `standalone_executable` | CLI 入口和参数处理 |
| `seek_sequence` | Update 操作的上下文匹配（Delete 操作未使用） |

### 2. 外部依赖（Cargo.toml）

| Crate | 用途 |
|-------|------|
| `anyhow` | 错误处理和上下文包装 |
| `similar` | 文本差异计算（Update 操作使用） |
| `thiserror` | 错误类型定义 |
| `tree-sitter` / `tree-sitter-bash` | Shell 脚本解析（本场景未使用） |

### 3. 系统调用

| 系统调用 | 用途 | 场景 007 中的行为 |
|----------|------|-------------------|
| `std::fs::remove_file` | 删除文件 | 失败（文件不存在），返回 `std::io::ErrorKind::NotFound` |

### 4. 测试依赖

| Crate | 用途 |
|-------|------|
| `tempfile` | 创建临时目录隔离测试 |
| `pretty_assertions` | 测试失败时提供清晰的差异对比 |
| `codex-utils-cargo-bin` | 定位测试二进制文件 |

---

## 风险、边界与改进建议

### 1. 当前实现的风险

#### 风险 1：原子性缺失

**问题**：`apply_hunks_to_files` 逐个执行 hunk，如果多个 hunk 中前面的成功、后面的失败，已执行的变更不会回滚。

**相关场景**：`015_failure_after_partial_success_leaves_changes` 专门测试此行为。

**场景 007 的影响**：本场景只有一个 DeleteFile hunk，且该操作失败，因此不存在部分成功问题。

#### 风险 2：错误信息不够具体

**当前错误**：`Failed to delete file <path>: No such file or directory (os error 2)`

**潜在改进**：可以明确告知用户这是预期外的情况（"尝试删除不存在的文件"）。

### 2. 边界情况分析

| 边界情况 | 当前行为 | 是否需要测试 |
|----------|----------|--------------|
| 删除不存在的文件 | 返回错误，状态不变 | ✅ 本场景覆盖 |
| 删除存在的文件 | 成功删除 | ✅ 场景 020 覆盖 |
| 删除目录（而非文件） | `remove_file` 返回错误 | ✅ 场景 012 覆盖 |
| 删除无权限的文件 | 返回权限错误 | ❌ 未明确测试 |
| 路径包含特殊字符 | 正常处理 | ❌ 未明确测试 |
| 相对路径 vs 绝对路径 | 相对路径基于 cwd 解析 | ✅ 其他场景覆盖 |

### 3. 改进建议

#### 建议 1：增强错误信息

在 `lib.rs` 第 301-304 行，可以为删除不存在文件的情况提供更友好的错误信息：

```rust
Hunk::DeleteFile { path } => {
    if !path.exists() {
        anyhow::bail!("Cannot delete file {}: file does not exist", path.display());
    }
    std::fs::remove_file(path)
        .with_context(|| format!("Failed to delete file {}", path.display()))?;
    deleted.push(path.clone());
}
```

**权衡**：这会增加一次额外的文件系统检查（`exists()` 调用），在性能敏感场景下可能不是最优。

#### 建议 2：区分 "文件不存在" 与其他 IO 错误

可以将 `std::io::ErrorKind::NotFound` 单独处理，提供更精确的错误类型：

```rust
#[derive(Debug, Error, PartialEq)]
pub enum ApplyPatchError {
    // ...
    #[error("File to delete does not exist: {0}")]
    DeleteTargetNotFound(PathBuf),
}
```

这可以让调用者（如 IDE 或 AI 助手）更精确地理解失败原因。

#### 建议 3：添加 dry-run 模式

对于 AI 助手场景，添加 `--dry-run` 模式可以在实际执行前验证所有操作的可行性：

```rust
fn apply_hunks_to_files(hunks: &[Hunk], dry_run: bool) -> anyhow::Result<AffectedPaths> {
    for hunk in hunks {
        match hunk {
            Hunk::DeleteFile { path } => {
                if !path.exists() {
                    anyhow::bail!("Would fail: file does not exist: {}", path.display());
                }
                if dry_run {
                    continue; // 仅验证，不执行
                }
                std::fs::remove_file(path)?;
            }
            // ...
        }
    }
}
```

### 4. 测试覆盖建议

| 建议添加的测试 | 目的 |
|---------------|------|
| 删除符号链接（指向不存在目标） | 验证符号链接处理 |
| 删除被其他进程锁定的文件 | 验证并发场景错误处理 |
| 删除路径极长的文件 | 验证路径长度边界 |
| 删除后验证文件确实不存在 | 当前测试只验证其他文件未被修改 |

---

## 总结

场景 `007_rejects_missing_file_delete` 是 `codex-apply-patch` 测试套件中的关键边界测试，验证系统在尝试删除不存在文件时的正确行为。通过该场景，我们可以确认：

1. **正确性**：系统会拒绝删除不存在的文件
2. **安全性**：失败操作不会副作用地影响其他文件
3. **一致性**：错误处理遵循 Rust 的 `Result` 类型和 `anyhow` 错误传播模式

该场景与 `020_delete_file_success` 形成互补，共同定义了 `Delete File` 操作的完整行为边界。
