# 008_rejects_empty_update_hunk 场景研究文档

## 场景与职责

### 场景概述

`008_rejects_empty_update_hunk` 是 `codex-rs/apply-patch` 测试套件中的一个场景测试用例，专门用于验证 **当 Update File 类型的 patch hunk 不包含任何实际的变更内容时，系统应该拒绝该 patch 并保持文件不变**。

### 测试场景结构

```
008_rejects_empty_update_hunk/
├── input/
│   └── foo.txt          # 输入文件，内容为 "stable"
├── expected/
│   └── foo.txt          # 期望输出，内容仍为 "stable"（文件未改变）
└── patch.txt            # 待应用的 patch（空的 Update File hunk）
```

### 各文件内容

**input/foo.txt** 和 **expected/foo.txt**：
```
stable
```

**patch.txt**：
```
*** Begin Patch
*** Update File: foo.txt
*** End Patch
```

### 测试目的

该场景验证以下行为：
1. 当 patch 中包含一个 `*** Update File: foo.txt` 声明，但没有跟随任何实际的变更 hunk（没有 `@@` 上下文标记和变更行）时
2. Parser 应该在解析阶段就拒绝这个无效的 patch
3. 文件系统状态保持不变（foo.txt 仍然是 "stable"）
4. 应用 patch 的操作应该失败并返回错误

---

## 功能点目的

### 1. 防御性编程 - 拒绝无意义的 Patch

空的 Update File hunk 通常意味着：
- LLM 生成的 patch 不完整或格式错误
- 用户输入错误
- 工具调用参数构造错误

如果允许空的 Update File hunk 通过，会导致：
- 用户误以为文件已被更新（实际上没有）
- 后续操作基于错误的假设
- 难以调试的潜在问题

### 2. 明确的错误反馈

系统应该提供清晰的错误信息，帮助用户理解问题所在：
```
Invalid patch hunk on line 2: Update file hunk for path 'foo.txt' is empty
```

### 3. 与相关场景的区分

| 场景 | Patch 内容 | 预期行为 |
|------|-----------|---------|
| `005_rejects_empty_patch` | `*** Begin Patch\n*** End Patch` | 拒绝：No files were modified |
| `008_rejects_empty_update_hunk` | `*** Begin Patch\n*** Update File: foo.txt\n*** End Patch` | 拒绝：Update file hunk is empty |
| 正常更新 | 包含 `@@` 和变更行 | 成功应用 |

区别：
- `005`：整个 patch 没有任何文件操作
- `008`：有 Update File 声明，但缺少具体的变更内容（chunks）

---

## 具体技术实现

### 关键流程

#### 1. Patch 解析流程

```
patch.txt → parse_patch() → parse_one_hunk() → 检测 empty chunks → 返回错误
```

**代码路径**：`codex-rs/apply-patch/src/parser.rs`

```rust
// parse_one_hunk 函数中处理 Update File 的逻辑（行 279-332）
} else if let Some(path) = first_line.strip_prefix(UPDATE_FILE_MARKER) {
    // ... 解析 move_path ...
    
    let mut chunks = Vec::new();
    while !remaining_lines.is_empty() {
        // 解析 chunk...
        let (chunk, chunk_lines) = parse_update_file_chunk(...)?;
        chunks.push(chunk);
        // ...
    }

    // 关键检查：如果 chunks 为空，返回错误
    if chunks.is_empty() {
        return Err(InvalidHunkError {
            message: format!("Update file hunk for path '{path}' is empty"),
            line_number,
        });
    }
    // ...
}
```

#### 2. 错误传播流程

```
parse_one_hunk() 返回 InvalidHunkError
    ↓
parse_patch_text() 传播错误
    ↓
apply_patch() 捕获并格式化错误输出
    ↓
stderr: "Invalid patch hunk on line 2: Update file hunk for path 'foo.txt' is empty"
```

**代码路径**：`codex-rs/apply-patch/src/lib.rs:182-213`

```rust
pub fn apply_patch(
    patch: &str,
    stdout: &mut impl std::io::Write,
    stderr: &mut impl std::io::Write,
) -> Result<(), ApplyPatchError> {
    let hunks = match parse_patch(patch) {
        Ok(source) => source.hunks,
        Err(e) => {
            match &e {
                InvalidHunkError { message, line_number } => {
                    writeln!(
                        stderr,
                        "Invalid patch hunk on line {line_number}: {message}"
                    )?;
                }
            }
            return Err(ApplyPatchError::ParseError(e));
        }
    };
    // ...
}
```

#### 3. 测试执行流程

**场景测试执行器**：`codex-rs/apply-patch/tests/suite/scenarios.rs:30-63`

```rust
fn run_apply_patch_scenario(dir: &Path) -> anyhow::Result<()> {
    let tmp = tempdir()?;
    
    // 1. 复制 input 文件到临时目录
    copy_dir_recursive(&input_dir, tmp.path())?;
    
    // 2. 读取 patch.txt
    let patch = fs::read_to_string(dir.join("patch.txt"))?;
    
    // 3. 运行 apply_patch（不检查 exit status）
    Command::new(codex_utils_cargo_bin::cargo_bin("apply_patch")?)
        .arg(patch)
        .current_dir(tmp.path())
        .output()?;
    
    // 4. 比较最终状态与 expected
    let expected_snapshot = snapshot_dir(&expected_dir)?;
    let actual_snapshot = snapshot_dir(tmp.path())?;
    assert_eq!(actual_snapshot, expected_snapshot);
    
    Ok(())
}
```

**关键点**：测试不检查 exit status，只验证最终文件系统状态与 `expected/` 一致。

### 数据结构

#### ParseError 枚举

```rust
// codex-rs/apply-patch/src/parser.rs:49-56
#[derive(Debug, PartialEq, Error, Clone)]
pub enum ParseError {
    #[error("invalid patch: {0}")]
    InvalidPatchError(String),
    #[error("invalid hunk at line {line_number}, {message}")]
    InvalidHunkError { message: String, line_number: usize },
}
```

#### Hunk 枚举

```rust
// codex-rs/apply-patch/src/parser.rs:58-76
pub enum Hunk {
    AddFile { path: PathBuf, contents: String },
    DeleteFile { path: PathBuf },
    UpdateFile {
        path: PathBuf,
        move_path: Option<PathBuf>,
        chunks: Vec<UpdateFileChunk>,  // 关键字段：必须非空
    },
}
```

#### UpdateFileChunk 结构

```rust
// codex-rs/apply-patch/src/parser.rs:90-104
pub struct UpdateFileChunk {
    pub change_context: Option<String>,  // @@ 后的上下文
    pub old_lines: Vec<String>,          // - 开头的行
    pub new_lines: Vec<String>,          // + 开头的行
    pub is_end_of_file: bool,            // 是否有 *** End of File
}
```

### 协议/格式规范

#### Patch 语法（来自 apply_patch_tool_instructions.md）

```
UpdateFile := "*** Update File: " path NEWLINE [ MoveTo ] { Hunk }
Hunk := "@@" [ header ] NEWLINE { HunkLine } [ "*** End of File" NEWLINE ]
HunkLine := (" " | "-" | "+") text NEWLINE
```

**关键规则**：`{ Hunk }` 表示 **一个或多个** hunk，不允许为空。

#### 有效 vs 无效 Patch 对比

**有效 Patch**（包含至少一个 hunk）：
```
*** Begin Patch
*** Update File: foo.txt
@@
-old line
+new line
*** End Patch
```

**无效 Patch**（本场景测试的）：
```
*** Begin Patch
*** Update File: foo.txt
*** End Patch
```

---

## 关键代码路径与文件引用

### 核心实现文件

| 文件 | 职责 | 相关行号 |
|-----|------|---------|
| `codex-rs/apply-patch/src/parser.rs` | Patch 解析器，包含 empty chunks 检测 | 279-332 (parse_one_hunk), 318-322 (empty check) |
| `codex-rs/apply-patch/src/lib.rs` | apply_patch 主逻辑，错误格式化输出 | 182-213 (apply_patch), 279-282 (apply_hunks_to_files 的 empty hunks 检查) |
| `codex-rs/apply-patch/src/standalone_executable.rs` | CLI 入口，参数处理 | 11-58 (run_main) |

### 测试相关文件

| 文件 | 职责 | 相关行号 |
|-----|------|---------|
| `codex-rs/apply-patch/tests/suite/scenarios.rs` | 场景测试执行框架 | 30-63 (run_apply_patch_scenario) |
| `codex-rs/apply-patch/tests/suite/tool.rs` | CLI 工具测试，包含同类测试 | 127-137 (test_apply_patch_cli_rejects_empty_update_hunk) |
| `codex-rs/apply-patch/tests/fixtures/scenarios/008_rejects_empty_update_hunk/` | 本场景测试数据 | patch.txt, input/, expected/ |

### 关键代码片段

#### 1. Empty Update Hunk 检测（parser.rs:318-322）

```rust
if chunks.is_empty() {
    return Err(InvalidHunkError {
        message: format!("Update file hunk for path '{path}' is empty"),
        line_number,
    });
}
```

#### 2. 相关测试用例（tool.rs:127-137）

```rust
#[test]
fn test_apply_patch_cli_rejects_empty_update_hunk() -> anyhow::Result<()> {
    let tmp = tempdir()?;

    apply_patch_command(tmp.path())?
        .arg("*** Begin Patch\n*** Update File: foo.txt\n*** End Patch")
        .assert()
        .failure()
        .stderr("Invalid patch hunk on line 2: Update file hunk for path 'foo.txt' is empty\n");

    Ok(())
}
```

#### 3. Empty Patch 检测（lib.rs:279-282）

注意：这是另一个层面的检查（hunks 级别），与 parser 中的 chunks 检查不同：

```rust
fn apply_hunks_to_files(hunks: &[Hunk]) -> anyhow::Result<AffectedPaths> {
    if hunks.is_empty() {
        anyhow::bail!("No files were modified.");
    }
    // ...
}
```

---

## 依赖与外部交互

### 内部依赖

```
apply-patch crate
├── parser.rs          # Patch 语法解析
├── lib.rs             # 核心应用逻辑
├── invocation.rs      # Shell 命令解析（heredoc 等）
├── seek_sequence.rs   # 模糊匹配算法
└── standalone_executable.rs  # CLI 入口
```

### 外部依赖

| Crate | 用途 |
|-------|------|
| `anyhow` | 错误处理 |
| `thiserror` | 自定义错误类型 |
| `similar` | 统一 diff 生成 |
| `tree-sitter` + `tree-sitter-bash` | Bash 脚本解析（用于 heredoc 提取）|
| `tempfile` | 测试临时目录 |
| `assert_cmd` | CLI 测试断言 |
| `pretty_assertions` | 测试输出美化 |

### 与 codex 其他组件的交互

```
codex-cli / codex-tui
    ↓ 调用
apply_patch 工具（通过 shell 命令或 API）
    ↓ 解析执行
文件系统（实际修改）
```

在 `invocation.rs` 中，`maybe_parse_apply_patch_verified` 被其他组件调用以验证和解析 apply_patch 调用。

---

## 风险、边界与改进建议

### 当前风险

#### 1. 错误信息行号可能不准确

当前行号计算基于解析时的行偏移，如果 patch 包含前导/后导空白行，行号可能与用户感知的行号不一致。

**建议**：在错误信息中同时显示上下文内容，而不仅仅是行号。

#### 2. 与 Empty Patch 的边界模糊

`005_rejects_empty_patch` 和 `008_rejects_empty_update_hunk` 两个场景的区别可能对用户造成困惑：
- 前者：patch 完全为空（没有任何文件操作）
- 后者：有 Update File 声明但无变更内容

**建议**：统一错误信息风格，使用更明确的术语区分 "empty patch" vs "empty update hunk"。

#### 3. 场景测试不验证 exit code

当前场景测试框架 `run_apply_patch_scenario` 不检查 apply_patch 的退出码：

```rust
// scenarios.rs:45-48
Command::new(...)
    .arg(patch)
    .current_dir(tmp.path())
    .output()?;  // 不检查 exit status
```

这可能导致某些本应失败的场景被错误地通过（如果 expected/ 错误地包含了变更）。

**建议**：增强场景测试框架，支持可选的 exit code 验证。

### 边界情况

| 情况 | 当前行为 | 评估 |
|-----|---------|------|
| `*** Update File: foo.txt\n\n*** End Patch`（空白行） | 拒绝：Update file hunk is empty | ✅ 正确 |
| `*** Update File: foo.txt\n@@\n*** End Patch`（只有 @@） | 拒绝：Update hunk does not contain any lines | ✅ 正确 |
| `*** Update File: foo.txt\n@@ context`（只有上下文） | 拒绝：Update hunk does not contain any lines | ✅ 正确 |
| Add File / Delete File 为空 | Add：允许（创建空文件）；Delete：允许 | ⚠️ 需要文档说明 |

### 改进建议

#### 1. 增强错误信息

当前：
```
Invalid patch hunk on line 2: Update file hunk for path 'foo.txt' is empty
```

建议：
```
Invalid patch hunk on line 2: Update file hunk for path 'foo.txt' is empty.
Expected at least one change block (starting with @@) after '*** Update File: foo.txt'.
Example:
  *** Update File: foo.txt
  @@
  -old line
  +new line
```

#### 2. 文档补充

在 `apply_patch_tool_instructions.md` 中明确说明：
- Update File 必须包含至少一个 hunk
- 每个 hunk 必须包含至少一个变更行（`+` 或 `-`）

#### 3. 代码结构优化

考虑将 empty chunks 检查与 parse_update_file_chunk 的错误处理统一，目前分散在两个地方：
- `parse_one_hunk` 检查 `chunks.is_empty()`
- `parse_update_file_chunk` 检查 `parsed_lines == 0`

#### 4. 测试覆盖

当前已有：
- ✅ 场景测试（008_rejects_empty_update_hunk）
- ✅ CLI 测试（test_apply_patch_cli_rejects_empty_update_hunk）
- ✅ Parser 单元测试（test_parse_patch 中的相关用例）

建议补充：
- 多个 Update File hunks，其中一个是空的
- 空的 Update File hunk 但包含 Move to

### 相关 Issue/PR 参考

- 该场景测试可能关联到早期关于 patch 验证的改进
- 与 `seek_sequence.rs` 的模糊匹配改进无直接关联，但同属 patch 应用的健壮性改进

---

## 总结

`008_rejects_empty_update_hunk` 场景测试是 `apply-patch` 工具防御性设计的重要组成部分，确保：

1. **数据完整性**：无意义的 patch 不会被静默接受
2. **用户体验**：清晰的错误信息帮助快速定位问题
3. **LLM 安全网**：捕获模型可能生成的不完整 patch

该测试通过验证 "当 Update File hunk 为空时，文件保持不变" 这一行为，为整个 patch 系统的可靠性提供了保障。
