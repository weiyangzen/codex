# 研究文档：foo.txt (009_requires_existing_file_for_update)

## 场景与职责

### 测试场景定位

该文件位于测试场景 `009_requires_existing_file_for_update` 中，是 `codex-rs/apply-patch` 模块的端到端测试固件之一。此场景专门用于验证 **Update File 操作对目标文件存在性的强制要求**。

### 场景编号含义

- `009`：在 25 个测试场景中的第 9 个
- `requires_existing_file_for_update`：明确表达测试目的——验证更新操作要求目标文件必须预先存在

### 目录结构

```
codex-rs/apply-patch/tests/fixtures/scenarios/009_requires_existing_file_for_update/
├── input/
│   └── foo.txt          # 研究目标：输入状态文件
├── expected/
│   └── foo.txt          # 期望输出状态（与输入相同）
└── patch.txt            # 补丁操作定义
```

### 文件职责

`foo.txt` 在此场景中扮演**稳定存在的文件**角色，用于验证当补丁尝试更新一个不存在的文件时：
1. 系统应正确处理错误
2. 已存在的文件（foo.txt）应保持不变
3. 整个补丁操作应失败（或部分失败）

---

## 功能点目的

### 核心测试目标

验证 `apply_patch` 工具在执行 **Update File** 操作时的前置条件检查：
- **必须条件**：被更新的文件必须在文件系统中已存在
- **失败模式**：当尝试更新不存在的文件时，操作应报告错误
- **副作用控制**：失败操作不应影响其他已存在文件的状态

### 补丁内容分析

```
*** Begin Patch
*** Update File: missing.txt    ← 尝试更新不存在的文件
@@
-old                           ← 期望找到的内容
+new                           ← 替换后的内容
*** End Patch
```

### 测试断言逻辑

| 组件 | 内容 | 说明 |
|------|------|------|
| `input/foo.txt` | `stable` | 初始存在的文件 |
| `patch.txt` | 更新 `missing.txt` | 目标文件不存在于 input/ 目录 |
| `expected/foo.txt` | `stable` | 验证 foo.txt 未被修改 |

**关键观察**：`expected/` 目录中**没有** `missing.txt`，因为补丁应该失败，不会创建新文件。

---

## 具体技术实现

### 1. 补丁解析流程

#### 1.1 解析入口

```rust
// codex-rs/apply-patch/src/lib.rs
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

#### 1.2 Hunk 类型定义

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
```

本场景中的 `patch.txt` 被解析为 `Hunk::UpdateFile` 类型。

### 2. Update File 操作实现

#### 2.1 核心更新逻辑

```rust
// codex-rs/apply-patch/src/lib.rs
fn derive_new_contents_from_chunks(
    path: &Path,
    chunks: &[UpdateFileChunk],
) -> Result<AppliedPatch, ApplyPatchError> {
    // 关键：尝试读取目标文件
    let original_contents = match std::fs::read_to_string(path) {
        Ok(contents) => contents,
        Err(err) => {
            return Err(ApplyPatchError::IoError(IoError {
                context: format!("Failed to read file to update {}", path.display()),
                source: err,  // ← 此处返回 IO 错误（文件不存在）
            }));
        }
    };
    // ... 后续处理
}
```

#### 2.2 文件存在性检查点

当 `derive_new_contents_from_chunks` 被调用时，它会立即尝试读取目标文件：

```rust
// 调用链
apply_hunks_to_files(hunks)
  └── derive_new_contents_from_chunks(path, chunks)
        └── std::fs::read_to_string(path)  // ← 文件存在性检查点
```

### 3. 行匹配算法（seek_sequence）

即使文件存在，更新操作还需要匹配旧内容：

```rust
// codex-rs/apply-patch/src/seek_sequence.rs
pub(crate) fn seek_sequence(
    lines: &[String],
    pattern: &[String],
    start: usize,
    eof: bool,
) -> Option<usize> {
    // 四级匹配策略：
    // 1. 精确匹配
    // 2. 忽略尾部空白
    // 3. 忽略首尾空白
    // 4. Unicode 标点规范化（如 EN DASH → ASCII -）
}
```

### 4. 测试框架集成

#### 4.1 场景测试执行器

```rust
// codex-rs/apply-patch/tests/suite/scenarios.rs
fn run_apply_patch_scenario(dir: &Path) -> anyhow::Result<()> {
    let tmp = tempdir()?;
    
    // 1. 复制 input/ 到临时目录
    copy_dir_recursive(&input_dir, tmp.path())?;
    
    // 2. 读取 patch.txt
    let patch = fs::read_to_string(dir.join("patch.txt"))?;
    
    // 3. 执行 apply_patch（不检查退出码）
    Command::new(cargo_bin("apply_patch")?)
        .arg(patch)
        .current_dir(tmp.path())
        .output()?;
    
    // 4. 比较最终状态与 expected/
    let expected_snapshot = snapshot_dir(&expected_dir)?;
    let actual_snapshot = snapshot_dir(tmp.path())?;
    assert_eq!(actual_snapshot, expected_snapshot);
}
```

#### 4.2 快照比较机制

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
enum Entry {
    File(Vec<u8>),
    Dir,
}

fn snapshot_dir(root: &Path) -> anyhow::Result<BTreeMap<PathBuf, Entry>> {
    // 递归遍历目录，生成有序映射用于比较
}
```

---

## 关键代码路径与文件引用

### 核心源码文件

| 文件路径 | 职责 | 相关行号 |
|---------|------|---------|
| `codex-rs/apply-patch/src/lib.rs` | 补丁应用主逻辑 | 182-213 (`apply_patch`), 346-381 (`derive_new_contents_from_chunks`) |
| `codex-rs/apply-patch/src/parser.rs` | 补丁格式解析 | 58-76 (`Hunk` 定义), 279-332 (`UpdateFile` 解析) |
| `codex-rs/apply-patch/src/seek_sequence.rs` | 行序列匹配算法 | 12-110 (`seek_sequence`) |
| `codex-rs/apply-patch/src/standalone_executable.rs` | CLI 入口 | 11-58 (`run_main`) |
| `codex-rs/apply-patch/src/invocation.rs` | 调用解析与验证 | 132-217 (`maybe_parse_apply_patch_verified`) |

### 测试相关文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/apply-patch/tests/suite/scenarios.rs` | 场景测试框架（126 行） |
| `codex-rs/apply-patch/tests/fixtures/scenarios/009_requires_existing_file_for_update/input/foo.txt` | **本研究目标文件** |
| `codex-rs/apply-patch/tests/fixtures/scenarios/009_requires_existing_file_for_update/patch.txt` | 测试用补丁 |
| `codex-rs/apply-patch/tests/fixtures/scenarios/009_requires_existing_file_for_update/expected/foo.txt` | 期望输出 |

### 关键代码片段

#### 文件读取失败处理

```rust
// codex-rs/apply-patch/src/lib.rs:352-360
let original_contents = match std::fs::read_to_string(path) {
    Ok(contents) => contents,
    Err(err) => {
        return Err(ApplyPatchError::IoError(IoError {
            context: format!("Failed to read file to update {}", path.display()),
            source: err,
        }));
    }
};
```

#### 测试场景执行（不检查退出码）

```rust
// codex-rs/apply-patch/tests/suite/scenarios.rs:42-48
// We intentionally do not assert on the exit status here;
// the scenarios are specified purely in terms of final filesystem state
Command::new(codex_utils_cargo_bin::cargo_bin("apply_patch")?)
    .arg(patch)
    .current_dir(tmp.path())
    .output()?;
```

---

## 依赖与外部交互

### 1. 内部依赖

```
apply-patch crate
├── parser module          # 补丁解析
├── invocation module      # 调用解析
├── seek_sequence module   # 行匹配算法
└── standalone_executable  # CLI 入口
```

### 2. 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `anyhow` | 错误处理与上下文 |
| `thiserror` | 错误类型定义 |
| `similar` | 统一差异（Unified Diff）生成 |
| `tempfile` | 测试临时目录 |
| `tree-sitter` | Bash 脚本解析（用于 heredoc 提取） |

### 3. 标准库交互

| 模块 | 用途 |
|------|------|
| `std::fs` | 文件读写、目录操作 |
| `std::process::Command` | 测试中的子进程调用 |
| `std::io::Write` | 输出流控制 |

### 4. 测试固件规范

```
测试场景目录结构（契约）
├── input/          # 初始文件系统状态
├── expected/       # 期望的最终状态
└── patch.txt       # 补丁操作
```

---

## 风险、边界与改进建议

### 1. 当前实现的风险

#### 1.1 错误信息粒度

**问题**：当文件不存在时，错误信息为：
```
Failed to read file to update <path>: <io_error>
```

这不够明确——用户无法区分"文件不存在"和"权限不足"。

**建议**：增加专门的错误变体：
```rust
pub enum ApplyPatchError {
    // ...
    #[error("Cannot update non-existent file: {0}")]
    UpdateTargetNotFound(PathBuf),
}
```

#### 1.2 部分应用风险

**问题**：当前实现中，如果多个 hunks 中前面的成功、后面的失败，已应用的修改不会回滚。

**代码位置**：`apply_hunks_to_files` 函数按顺序处理 hunks，没有事务机制。

**建议**：考虑实现两阶段提交：
1. 预检阶段：验证所有文件存在性和内容匹配
2. 执行阶段：实际应用修改

#### 1.3 竞态条件

**问题**：TOCTOU（Time-of-check to time-of-use）风险：
```rust
// 检查与使用之间有时间窗口
let original_contents = std::fs::read_to_string(path)?;  // check
// ... 处理 ...
std::fs::write(path, new_contents)?;  // use
```

### 2. 边界情况

| 边界情况 | 当前行为 | 评估 |
|---------|---------|------|
| 更新空文件 | 支持（`old_lines` 为空） | ✅ 正常 |
| 更新符号链接 | 跟随链接（`fs::metadata`） | ⚠️ 可能意外 |
| 路径包含 `..` | 按相对路径解析 | ⚠️ 安全风险 |
| 并发修改 | 无锁，最后写入者胜出 | ❌ 风险 |

### 3. 改进建议

#### 3.1 增强错误报告

```rust
// 建议添加
#[derive(Debug, Error)]
pub enum UpdateError {
    #[error("Target file does not exist: {path}")]
    NotFound { path: PathBuf },
    #[error("Content mismatch at line {line}: expected {expected:?}, found {found:?}")]
    ContentMismatch { line: usize, expected: String, found: String },
    #[error("Permission denied: {path}")]
    PermissionDenied { path: PathBuf },
}
```

#### 3.2 原子性改进

```rust
// 建议：使用临时文件 + 原子重命名
fn atomic_write(path: &Path, contents: &str) -> io::Result<()> {
    let temp_path = path.with_extension("tmp");
    fs::write(&temp_path, contents)?;
    fs::rename(&temp_path, path)?;  // 原子操作
    Ok(())
}
```

#### 3.3 测试覆盖扩展

建议增加以下测试场景：

| 场景 ID | 描述 | 预期行为 |
|--------|------|---------|
| 026 | 更新无权限读取的文件 | 明确的权限错误 |
| 027 | 更新正在被其他进程写入的文件 | 错误或可配置策略 |
| 028 | 更新大小为 0 的文件 | 成功（空内容匹配） |
| 029 | 更新包含 NUL 字节的文件 | 错误（非文本文件） |

### 4. 相关场景交叉验证

与本场景相关的其他测试场景：

| 场景 | 描述 | 与 009 的关系 |
|------|------|--------------|
| 007_rejects_missing_file_delete | 删除不存在的文件 | 对称测试（删除 vs 更新） |
| 008_rejects_empty_update_hunk | 空更新块 | 解析时错误 vs 运行时错误 |
| 015_failure_after_partial_success | 部分成功后失败 | 事务性边界测试 |
| 021_update_file_deletion_only | 仅删除行的更新 | 更新操作的子集 |

---

## 总结

`foo.txt` 在场景 `009_requires_existing_file_for_update` 中是一个**稳定的参照物**，用于验证 `apply_patch` 工具在面对无效更新操作时的行为：

1. **存在性验证**：`Update File` 操作要求目标文件必须存在
2. **错误传播**：文件不存在时返回 `ApplyPatchError::IoError`
3. **副作用隔离**：失败操作不应影响其他已存在文件
4. **测试契约**：通过比较 `expected/` 和实际输出验证行为

该测试场景是 apply-patch 安全模型的关键组成部分，确保工具不会意外创建文件（应使用 `Add File` 操作显式创建）。
