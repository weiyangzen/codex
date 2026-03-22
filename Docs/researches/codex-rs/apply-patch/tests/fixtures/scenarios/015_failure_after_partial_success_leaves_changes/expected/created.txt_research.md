# created.txt 研究文档

## 场景与职责

### 文件位置
`codex-rs/apply-patch/tests/fixtures/scenarios/015_failure_after_partial_success_leaves_changes/expected/created.txt`

### 所属测试场景
**场景编号**: 015  
**场景名称**: `failure_after_partial_success_leaves_changes`（部分成功后失败保留变更）

### 场景目的
该测试场景验证 `apply_patch` 工具在处理包含多个文件操作的 patch 时，当某个操作失败时，之前已成功应用的操作是否会保留在文件系统中。这是一个关键的**事务性边界测试**，用于确认工具的行为是"部分应用"而非"全有或全无"的原子操作。

### 场景结构
```
015_failure_after_partial_success_leaves_changes/
├── patch.txt          # 包含两个操作的 patch：先成功创建文件，后失败更新不存在的文件
└── expected/
    └── created.txt    # 期望保留的成功创建的文件（内容: "hello"）
```

**注意**: 该场景没有 `input/` 目录，表示初始状态为空目录。

---

## 功能点目的

### patch.txt 内容分析
```
*** Begin Patch
*** Add File: created.txt
+hello
*** Update File: missing.txt
@@
-old
+new
*** End Patch
```

该 patch 包含两个顺序执行的 hunk：

1. **Add File 操作**: 创建 `created.txt` 文件，内容为 `"hello"`
2. **Update File 操作**: 尝试更新 `missing.txt` 文件，将 `"old"` 替换为 `"new"`

### 预期行为
- 第一个操作（Add File）应该成功执行，`created.txt` 被创建
- 第二个操作（Update File）应该失败，因为 `missing.txt` 不存在
- **关键验证点**: 尽管第二个操作失败，第一个操作创建的 `created.txt` 应该保留在文件系统中

### created.txt 的职责
`created.txt` 是本测试场景的**验证锚点**（verification anchor）：
- 它的存在证明了 patch 工具在部分失败时不会回滚已成功的操作
- 它的内容 `"hello"` 验证了 Add File 操作的正确性
- 它是 `expected/` 目录中唯一的期望输出文件

---

## 具体技术实现

### 1. Patch 解析流程

#### 解析器入口
**文件**: `codex-rs/apply-patch/src/parser.rs`

```rust
pub fn parse_patch(patch: &str) -> Result<ApplyPatchArgs, ParseError>
```

解析流程：
1. **边界检查**: 验证 patch 以 `*** Begin Patch` 开始，以 `*** End Patch` 结束
2. **Lenient 模式**: 支持处理 heredoc 包装（如 `<<'EOF'...EOF`）
3. **Hunk 解析**: 逐个解析文件操作 hunk

#### Hunk 类型定义
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

### 2. Patch 应用流程

#### 主应用函数
**文件**: `codex-rs/apply-patch/src/lib.rs`

```rust
pub fn apply_patch(
    patch: &str,
    stdout: &mut impl std::io::Write,
    stderr: &mut impl std::io::Write,
) -> Result<(), ApplyPatchError>
```

执行流程：
1. 调用 `parse_patch()` 解析 patch 文本
2. 调用 `apply_hunks()` 应用解析后的 hunks
3. 返回结果（成功或错误）

#### Hunk 应用核心逻辑
```rust
fn apply_hunks_to_files(hunks: &[Hunk]) -> anyhow::Result<AffectedPaths>
```

**关键实现细节**（行 279-339）：
```rust
for hunk in hunks {
    match hunk {
        Hunk::AddFile { path, contents } => {
            // 创建父目录（如需要）
            if let Some(parent) = path.parent() {
                std::fs::create_dir_all(parent)?;
            }
            // 写入文件
            std::fs::write(path, contents)?;
            added.push(path.clone());
        }
        Hunk::UpdateFile { path, move_path, chunks } => {
            // 读取原文件内容
            let AppliedPatch { new_contents, .. } = derive_new_contents_from_chunks(path, chunks)?;
            // 写入新内容
            std::fs::write(path, new_contents)?;
            modified.push(path.clone());
        }
        // ...
    }
}
```

### 3. 部分成功行为的根源

**关键观察**: `apply_hunks_to_files` 函数使用**顺序执行**模式：

1. 遍历 hunks 的 `for` 循环没有事务包装
2. 每个 hunk 的操作直接作用于文件系统
3. 一旦某个 hunk 失败，函数立即返回 `Err`，但之前的操作已持久化

**代码路径**（`lib.rs` 行 279-339）：
```rust
fn apply_hunks_to_files(hunks: &[Hunk]) -> anyhow::Result<AffectedPaths> {
    // ...
    for hunk in hunks {
        match hunk {
            Hunk::AddFile { ... } => {
                // 操作1: 成功执行，写入磁盘
            }
            Hunk::UpdateFile { ... } => {
                // 操作2: 失败（文件不存在），返回 Err
                // 但操作1的变更已保留
            }
        }
    }
}
```

### 4. Update File 失败的原因

**文件**: `codex-rs/apply-patch/src/lib.rs` 行 346-381

```rust
fn derive_new_contents_from_chunks(
    path: &Path,
    chunks: &[UpdateFileChunk],
) -> Result<AppliedPatch, ApplyPatchError> {
    let original_contents = match std::fs::read_to_string(path) {
        Ok(contents) => contents,
        Err(err) => {
            return Err(ApplyPatchError::IoError(IoError {
                context: format!("Failed to read file to update {}", path.display()),
                source: err,  // 此处返回错误：文件不存在
            }));
        }
    };
    // ...
}
```

当尝试更新 `missing.txt` 时，`std::fs::read_to_string(path)` 返回 `Err`，导致整个 patch 应用失败，但此时 `created.txt` 已创建。

### 5. 测试框架验证逻辑

**文件**: `codex-rs/apply-patch/tests/suite/scenarios.rs`

```rust
fn run_apply_patch_scenario(dir: &Path) -> anyhow::Result<()> {
    let tmp = tempdir()?;
    
    // 复制 input 文件（本场景无 input）
    let input_dir = dir.join("input");
    if input_dir.is_dir() {
        copy_dir_recursive(&input_dir, tmp.path())?;
    }
    
    // 读取 patch.txt
    let patch = fs::read_to_string(dir.join("patch.txt"))?;
    
    // 执行 apply_patch（**不检查退出状态**）
    Command::new(codex_utils_cargo_bin::cargo_bin("apply_patch")?)
        .arg(patch)
        .current_dir(tmp.path())
        .output()?;
    
    // 比较最终状态与 expected/
    let expected_dir = dir.join("expected");
    let expected_snapshot = snapshot_dir(&expected_dir)?;
    let actual_snapshot = snapshot_dir(tmp.path())?;
    
    assert_eq!(actual_snapshot, expected_snapshot, ...);
}
```

**关键设计**: 测试框架**故意不检查退出状态**（注释明确说明），只验证最终文件系统状态是否与 `expected/` 一致。这允许测试验证"部分成功"的行为。

---

## 关键代码路径与文件引用

### 核心文件清单

| 文件路径 | 职责 | 相关行号 |
|---------|------|---------|
| `codex-rs/apply-patch/src/lib.rs` | Patch 应用主逻辑 | 182-213, 279-339 |
| `codex-rs/apply-patch/src/parser.rs` | Patch 文本解析 | 106-183, 246-341 |
| `codex-rs/apply-patch/src/standalone_executable.rs` | CLI 入口 | 1-59 |
| `codex-rs/apply-patch/tests/suite/scenarios.rs` | 场景测试框架 | 28-63 |
| `codex-rs/apply-patch/apply_patch_tool_instructions.md` | 工具使用文档 | 全文 |

### 关键代码路径流程图

```
apply_patch CLI
    │
    ▼
standalone_executable::run_main()
    │
    ▼
lib::apply_patch(patch_text, stdout, stderr)
    │
    ├──► parser::parse_patch(patch_text) ──► ApplyPatchArgs { hunks }
    │
    ▼
lib::apply_hunks(&hunks, stdout, stderr)
    │
    ▼
lib::apply_hunks_to_files(hunks)
    │
    ├──► Hunk::AddFile { path: "created.txt", contents: "hello\n" }
    │    └──► fs::write("created.txt", "hello\n") ✅ 成功
    │
    └──► Hunk::UpdateFile { path: "missing.txt", ... }
         └──► fs::read_to_string("missing.txt") ❌ 失败（文件不存在）
              └──► 返回 Err

最终结果: created.txt 存在（"hello"），patch 命令返回错误
```

### 数据结构关系

```
ApplyPatchArgs
    ├── patch: String              # 原始 patch 文本
    ├── hunks: Vec<Hunk>           # 解析后的操作列表
    │       ├── Hunk::AddFile
    │       │       ├── path: PathBuf
    │       │       └── contents: String
    │       └── Hunk::UpdateFile
    │               ├── path: PathBuf
    │               ├── move_path: Option<PathBuf>
    │               └── chunks: Vec<UpdateFileChunk>
    └── workdir: Option<String>

UpdateFileChunk
    ├── change_context: Option<String>
    ├── old_lines: Vec<String>
    ├── new_lines: Vec<String>
    └── is_end_of_file: bool
```

---

## 依赖与外部交互

### 1. 内部依赖

| 依赖模块 | 用途 |
|---------|------|
| `parser` | Patch 文本解析为结构化 Hunk |
| `invocation` | 从 shell 命令提取 patch（heredoc 支持） |
| `seek_sequence` | UpdateFile 时查找匹配的行序列 |
| `standalone_executable` | CLI 入口和参数处理 |

### 2. 外部依赖（Cargo）

```toml
[dependencies]
anyhow = "..."           # 错误处理
similar = "..."          # 文本差异计算（unified diff）
thiserror = "..."        # 错误类型定义
tree-sitter = "..."      # Bash 脚本解析
tree-sitter-bash = "..." # Bash 语法定义
```

### 3. 系统交互

| 系统调用 | 用途 | 场景中的使用 |
|---------|------|-------------|
| `std::fs::write` | 创建/写入文件 | 创建 `created.txt` |
| `std::fs::read_to_string` | 读取文件内容 | 尝试读取 `missing.txt`（失败） |
| `std::fs::create_dir_all` | 创建父目录 | 本场景未触发 |
| `std::fs::remove_file` | 删除文件 | 本场景未使用 |

### 4. 测试依赖

```toml
[dev-dependencies]
assert_cmd = "..."           # CLI 测试辅助
assert_matches = "..."       # 模式匹配断言
codex-utils-cargo-bin = "..." # 定位测试二进制文件
pretty_assertions = "..."    # 美观的差异输出
tempfile = "..."             # 临时目录管理
```

---

## 风险、边界与改进建议

### 1. 当前行为的风险

#### 风险 1: 非原子性操作
**问题**: `apply_patch` 不保证原子性。如果 patch 包含多个相互依赖的操作，部分失败可能导致文件系统处于不一致状态。

**示例风险场景**:
```
*** Begin Patch
*** Add File: config.json
+{ "version": 2 }
*** Update File: main.py
@@
-config_version = 1
+config_version = 2
*** End Patch
```

如果 `main.py` 更新失败，`config.json` 仍会被创建，导致配置与代码不匹配。

#### 风险 2: 无回滚机制
**问题**: 一旦操作失败，工具不会自动回滚已成功的操作。用户需要手动清理或重新运行修复后的 patch。

#### 风险 3: 并发安全性
**问题**: 没有文件锁定机制。如果在应用 patch 过程中其他进程修改了目标文件，可能导致未定义行为。

### 2. 边界情况分析

| 边界情况 | 当前行为 | 潜在问题 |
|---------|---------|---------|
| Patch 为空（无 hunk） | 返回错误 "No files were modified" | 合理 |
| 更新操作中目标文件被其他 hunk 创建 | 取决于执行顺序 | 可能成功或失败 |
| 同一文件被多个 hunk 修改 | 每个 hunk 独立应用 | 可能产生冲突 |
| 磁盘空间不足 | 部分写入后失败 | 文件可能损坏 |
| 权限不足 | 返回 IO 错误 | 部分操作可能已执行 |

### 3. 改进建议

#### 建议 1: 添加事务性支持（可选模式）
```rust
pub enum ApplyMode {
    BestEffort,      // 当前行为：部分应用
    Atomic,          // 新行为：全有或全无
}

pub fn apply_patch_with_mode(
    patch: &str,
    mode: ApplyMode,
    stdout: &mut impl Write,
    stderr: &mut impl Write,
) -> Result<(), ApplyPatchError>
```

**Atomic 模式实现思路**:
1. 预验证阶段：检查所有文件是否存在/可写
2. 创建临时文件进行所有写操作
3. 原子重命名（atomic rename）替换原文件
4. 失败时清理临时文件

#### 建议 2: 添加 dry-run 模式
```rust
pub fn apply_patch_dry_run(
    patch: &str,
) -> Result<AffectedPaths, ApplyPatchError>
```

允许用户在实际应用前预览变更，检测潜在冲突。

#### 建议 3: 增强错误信息
当前错误信息：
```
Failed to read file to update missing.txt: No such file or directory (os error 2)
```

建议改进：
```
Failed to apply patch: UpdateFile operation failed for 'missing.txt'
  Caused by: File not found
  Context: This was hunk 2 of 2. Hunk 1 (AddFile 'created.txt') was successfully applied.
  Suggestion: Ensure 'missing.txt' exists before applying this patch.
```

#### 建议 4: 添加部分应用警告
即使在使用 `BestEffort` 模式时，也应在 stderr 中明确警告用户哪些操作已成功：
```rust
eprintln!("Warning: Patch partially applied. {} files modified before error.", 
          affected.added.len() + affected.modified.len() + affected.deleted.len());
```

### 4. 测试覆盖建议

| 建议测试场景 | 目的 |
|------------|------|
| 三个操作，中间失败 | 验证多个成功操作后的失败处理 |
| 更新操作后删除同一文件 | 验证操作间的依赖关系 |
| 磁盘满场景 | 验证 IO 错误处理 |
| 并发修改目标文件 | 验证竞争条件处理 |

### 5. 文档改进建议

当前 `apply_patch_tool_instructions.md` 未明确说明部分应用行为。建议添加：

```markdown
## 错误处理与部分应用

`apply_patch` 按顺序应用文件操作。如果某个操作失败：
- 之前已成功应用的操作**不会**被回滚
- 后续操作**不会**被执行
- 工具返回非零退出码

建议：在发送包含多个文件操作的 patch 前，确保所有目标文件存在且可访问。
```

---

## 总结

`created.txt` 是本测试场景的核心验证点，它的存在证明了 `apply_patch` 工具的**非原子性**行为特征。这种设计选择简化了实现，但要求使用者（包括 AI 模型和人类开发者）理解其语义：patch 应用是顺序的、非事务的，部分失败会留下已应用的变更。

理解这一行为对于正确使用 `apply_patch` 工具至关重要，特别是在需要保持文件系统一致性的复杂重构场景中。
