# Research: 008_rejects_empty_update_hunk 测试场景分析

## 1. 场景与职责

### 1.1 目标文件定位
- **文件路径**: `codex-rs/apply-patch/tests/fixtures/scenarios/008_rejects_empty_update_hunk/input/foo.txt`
- **文件内容**: 单行文本 `stable`
- **所属测试场景**: `008_rejects_empty_update_hunk`

### 1.2 测试场景结构
```
008_rejects_empty_update_hunk/
├── input/
│   └── foo.txt          # 被测试的输入文件（内容: "stable"）
├── expected/
│   └── foo.txt          # 期望输出（与输入相同: "stable"）
└── patch.txt            # 测试用的 patch 内容
```

### 1.3 场景职责
本测试场景的核心职责是**验证 apply-patch 工具能够正确拒绝空的 Update File hunk**。具体来说：
- 当一个 patch 包含 `*** Update File: <path>` 声明但没有跟随任何实际的变更块（chunks）时，工具应该拒绝应用该 patch
- 被操作的文件内容应保持不变（即 patch 应用失败后不应修改文件）

---

## 2. 功能点目的

### 2.1 测试目的
本测试场景验证以下关键行为：

1. **空 Update hunk 的拒绝**: 当 patch 中包含一个没有变更内容的 `Update File` 声明时，解析器应该报错并拒绝执行
2. **文件完整性保护**: 由于 patch 被拒绝，目标文件 `foo.txt` 应保持原样（内容为 `stable`）
3. **错误信息准确性**: 工具应提供清晰的错误信息，指明问题所在

### 2.2 与其他场景的对比

| 场景编号 | 场景名称 | 目的对比 |
|---------|---------|---------|
| 005 | rejects_empty_patch | 测试完全空的 patch（没有任何 hunk） |
| **008** | **rejects_empty_update_hunk** | **测试包含 Update File 声明但无变更块的 patch** |
| 006 | rejects_missing_context | 测试变更块中上下文不匹配的情况 |
| 016 | pure_addition_update_chunk | 测试合法的纯添加变更块（`+` 行） |

### 2.3 关键区别：005 vs 008
- **005_rejects_empty_patch**: Patch 只有 `*** Begin Patch` 和 `*** End Patch`，没有任何 hunk
  - 错误信息: `No files were modified.`
- **008_rejects_empty_update_hunk**: Patch 包含 `*** Update File: foo.txt` hunk 声明，但没有变更块
  - 错误信息: `Update file hunk for path 'foo.txt' is empty`

---

## 3. 具体技术实现

### 3.1 Patch 内容分析

**patch.txt 内容**:
```
*** Begin Patch
*** Update File: foo.txt
*** End Patch
```

**语法结构解析**:
```
*** Begin Patch          ← Patch 开始标记
*** Update File: foo.txt ← Update File hunk 声明（无变更块）
*** End Patch            ← Patch 结束标记
```

根据官方语法规范（`apply_patch_tool_instructions.md`）:
```
UpdateFile := "*** Update File: " path NEWLINE [ MoveTo ] { Hunk }
Hunk := "@@" [ header ] NEWLINE { HunkLine } [ "*** End of File" NEWLINE ]
```

一个合法的 Update File 操作必须包含至少一个 Hunk（以 `@@` 开头），而本测试中的 patch 缺少这一必需部分。

### 3.2 关键代码路径

#### 3.2.1 Patch 解析流程

**入口**: `parser.rs::parse_patch()` → `parse_patch_text()`

```rust
// parser.rs:106-113
pub fn parse_patch(patch: &str) -> Result<ApplyPatchArgs, ParseError> {
    let mode = if PARSE_IN_STRICT_MODE {
        ParseMode::Strict
    } else {
        ParseMode::Lenient
    };
    parse_patch_text(patch, mode)
}
```

**Hunk 解析**: `parser.rs::parse_one_hunk()` (行 248-341)

当解析器遇到 `*** Update File:` 标记时，会进入 Update File hunk 的解析逻辑：

```rust
// parser.rs:279-332
else if let Some(path) = first_line.strip_prefix(UPDATE_FILE_MARKER) {
    // Update File
    let mut remaining_lines = &lines[1..];
    let mut parsed_lines = 1;

    // Optional: move file line
    let move_path = remaining_lines
        .first()
        .and_then(|x| x.strip_prefix(MOVE_TO_MARKER));
    // ... 解析 move_path ...

    let mut chunks = Vec::new();
    while !remaining_lines.is_empty() {
        // 跳过空行
        if remaining_lines[0].trim().is_empty() {
            parsed_lines += 1;
            remaining_lines = &remaining_lines[1..];
            continue;
        }

        // 遇到下一个 hunk 头则停止
        if remaining_lines[0].starts_with("***") {
            break;
        }

        // 解析变更块
        let (chunk, chunk_lines) = parse_update_file_chunk(...)?;
        chunks.push(chunk);
        // ...
    }

    // ★★★ 关键检查点 ★★★
    if chunks.is_empty() {
        return Err(InvalidHunkError {
            message: format!("Update file hunk for path '{path}' is empty"),
            line_number,
        });
    }
    // ...
}
```

#### 3.2.2 空 hunk 检测机制

**检测位置**: `parser.rs:318-323`

```rust
if chunks.is_empty() {
    return Err(InvalidHunkError {
        message: format!("Update file hunk for path '{path}' is empty"),
        line_number,
    });
}
```

**检测逻辑**:
1. 解析器读取 `*** Update File: foo.txt` 后，尝试解析后续的变更块（chunks）
2. 变更块必须以 `@@` 开头（`CHANGE_CONTEXT_MARKER` 或 `EMPTY_CHANGE_CONTEXT_MARKER`）
3. 在本测试的 patch 中，`*** Update File: foo.txt` 后直接是 `*** End Patch`，没有 `@@` 标记
4. 因此 `chunks` 向量保持为空，触发错误返回

#### 3.2.3 错误传播路径

**错误类型定义** (`parser.rs:49-56`):
```rust
#[derive(Debug, PartialEq, Error, Clone)]
pub enum ParseError {
    #[error("invalid patch: {0}")]
    InvalidPatchError(String),
    #[error("invalid hunk at line {line_number}, {message}")]
    InvalidHunkError { message: String, line_number: usize },
}
```

**错误处理** (`lib.rs:188-207`):
```rust
let hunks = match parse_patch(patch) {
    Ok(source) => source.hunks,
    Err(e) => {
        match &e {
            InvalidPatchError(message) => {
                writeln!(stderr, "Invalid patch: {message}").map_err(...)?;
            }
            InvalidHunkError { message, line_number } => {
                writeln!(
                    stderr,
                    "Invalid patch hunk on line {line_number}: {message}"
                ).map_err(...)?;
            }
        }
        return Err(ApplyPatchError::ParseError(e));
    }
};
```

**最终输出格式**:
```
Invalid patch hunk on line 2: Update file hunk for path 'foo.txt' is empty
```

### 3.3 数据结构

#### 3.3.1 Hunk 枚举定义

```rust
// parser.rs:58-76
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
        chunks: Vec<UpdateFileChunk>,  // ← 必须非空
    },
}
```

#### 3.3.2 UpdateFileChunk 结构

```rust
// parser.rs:90-104
#[derive(Debug, PartialEq, Clone)]
pub struct UpdateFileChunk {
    /// 用于定位变更位置的上下文行（通常是类、方法或函数定义）
    pub change_context: Option<String>,
    /// 应被替换的连续行块
    pub old_lines: Vec<String>,
    /// 新行内容
    pub new_lines: Vec<String>,
    /// 如果为 true，old_lines 必须出现在文件末尾
    pub is_end_of_file: bool,
}
```

### 3.4 测试执行流程

**测试框架**: `tests/suite/scenarios.rs::test_apply_patch_scenarios()`

```rust
// scenarios.rs:10-26
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
            run_apply_patch_scenario(&path)?;  // ← 执行每个场景
        }
    }
    Ok(())
}
```

**场景执行函数** (`scenarios.rs:30-63`):
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

    // 3. 执行 apply_patch（不检查退出状态）
    Command::new(codex_utils_cargo_bin::cargo_bin("apply_patch")?)
        .arg(patch)
        .current_dir(tmp.path())
        .output()?;

    // 4. 比较最终状态与 expected 目录
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

**关键设计**: 测试框架**不检查退出状态码**，只验证最终文件系统状态。这意味着即使 apply_patch 返回错误（非零退出码），只要文件内容符合预期，测试就通过。对于本场景，由于 patch 被拒绝，文件应保持原样。

---

## 4. 关键代码路径与文件引用

### 4.1 核心源文件

| 文件路径 | 职责描述 |
|---------|---------|
| `codex-rs/apply-patch/src/parser.rs` | Patch 语法解析器，包含空 hunk 检测逻辑（行 318-323） |
| `codex-rs/apply-patch/src/lib.rs` | 核心库，实现 `apply_patch()` 和 `apply_hunks()` 函数 |
| `codex-rs/apply-patch/src/standalone_executable.rs` | CLI 入口，处理命令行参数和 stdin |
| `codex-rs/apply-patch/src/invocation.rs` | 从 shell 脚本中提取 patch 的辅助函数 |
| `codex-rs/apply-patch/src/seek_sequence.rs` | 模糊匹配算法，用于定位变更上下文 |

### 4.2 测试相关文件

| 文件路径 | 职责描述 |
|---------|---------|
| `codex-rs/apply-patch/tests/suite/scenarios.rs` | 场景测试框架，自动执行所有 fixtures/scenarios/ 下的测试 |
| `codex-rs/apply-patch/tests/suite/tool.rs` | CLI 工具测试，包含 `test_apply_patch_cli_rejects_empty_update_hunk` |
| `codex-rs/apply-patch/tests/fixtures/scenarios/008_rejects_empty_update_hunk/` | 本场景的数据文件 |

### 4.3 关键代码行引用

```
parser.rs:
  - 31-37:   Patch 标记常量定义
  - 58-76:   Hunk 枚举定义
  - 90-104:  UpdateFileChunk 结构定义
  - 248-341: parse_one_hunk() 函数
  - 318-323: ★ 空 chunks 检测逻辑 ★
  - 343-434: parse_update_file_chunk() 函数

lib.rs:
  - 37-51:   ApplyPatchError 错误枚举
  - 182-213: apply_patch() 主函数
  - 188-207: 解析错误处理逻辑

tests/suite/tool.rs:
  - 127-137: test_apply_patch_cli_rejects_empty_update_hunk 测试

tests/suite/scenarios.rs:
  - 10-26:   test_apply_patch_scenarios() 主测试函数
  - 30-63:   run_apply_patch_scenario() 场景执行逻辑
```

---

## 5. 依赖与外部交互

### 5.1 内部依赖

```
codex-apply-patch
├── lib.rs (核心逻辑)
│   ├── parser.rs (解析器)
│   ├── invocation.rs (shell 调用解析)
│   ├── seek_sequence.rs (模糊匹配)
│   └── standalone_executable.rs (CLI)
```

### 5.2 外部依赖

| 依赖包 | 用途 |
|-------|------|
| `anyhow` | 错误处理和上下文 |
| `similar` | 文本差异计算（unified diff） |
| `thiserror` | 派生错误类型 |
| `tree-sitter` | Bash 脚本解析（用于提取 heredoc） |
| `tree-sitter-bash` | Bash 语法支持 |

### 5.3 测试依赖

| 依赖包 | 用途 |
|-------|------|
| `assert_cmd` | CLI 测试辅助 |
| `assert_matches` | 模式匹配断言 |
| `codex-utils-cargo-bin` | 定位测试二进制文件 |
| `pretty_assertions` | 美观的差异输出 |
| `tempfile` | 临时目录管理 |

### 5.4 与 TUI/App Server 的交互

apply-patch 作为底层工具，被上层组件调用：

```
┌─────────────────────────────────────────────────────────────┐
│  Codex CLI / TUI / App Server                               │
│  - 构建 patch 字符串                                         │
│  - 调用 apply_patch 函数或二进制                              │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│  codex-apply-patch (本组件)                                  │
│  - 解析 patch                                               │
│  - 应用变更到文件系统                                         │
│  - 返回结果或错误                                             │
└─────────────────────────────────────────────────────────────┘
```

在 `invocation.rs` 中，`maybe_parse_apply_patch_verified()` 函数是上层调用的主要入口：
- 检测隐式 patch 调用（直接传递 patch 内容而无 `apply_patch` 命令）
- 解析 shell heredoc 形式的调用
- 验证并返回结构化的 `ApplyPatchAction`

---

## 6. 风险、边界与改进建议

### 6.1 当前风险与边界情况

#### 6.1.1 已处理的边界情况

1. **纯空白字符的变更块**: `parse_update_file_chunk()` 会正确处理空行（行 399-403）
   ```rust
   None => {
       // 将空行解释为空白行
       chunk.old_lines.push(String::new());
       chunk.new_lines.push(String::new());
   }
   ```

2. **只有 `@@` 没有后续内容的变更块**: 会被检测为无效（行 388-392）
   ```rust
   EOF_MARKER if parsed_lines == 0 => {
       return Err(InvalidHunkError {
           message: "Update hunk does not contain any lines".to_string(),
           // ...
       });
   }
   ```

3. **模式长度超过输入**: `seek_sequence.rs:26-28` 防止 panic
   ```rust
   if pattern.len() > lines.len() {
       return None;
   }
   ```

#### 6.1.2 潜在风险

1. **错误信息一致性**: 
   - 当前错误信息硬编码在多处（parser.rs 行 320、477）
   - 如果修改错误信息格式，需要同步更新测试断言

2. **行号计算**:
   - 错误信息中的行号（`line_number: 2`）是相对于 patch 内容的行号
   - 如果 patch 通过 heredoc 传递，行号可能让用户困惑

3. **与其他场景的耦合**:
   - 场景 005（空 patch）和 008（空 update hunk）的错误处理路径不同
   - 需要确保两者都返回非零退出码

### 6.2 改进建议

#### 6.2.1 代码质量改进

1. **错误信息模板化**:
   ```rust
   // 建议：定义常量避免硬编码
   const EMPTY_UPDATE_HUNK_MSG: &str = "Update file hunk for path '{path}' is empty";
   ```

2. **增强错误上下文**:
   ```rust
   // 当前：只报告行号
   // 建议：同时报告期望的格式示例
   message: format!(
       "Update file hunk for path '{path}' is empty. \
        Expected at least one chunk starting with '@@'. \
        See documentation for patch format."
   ),
   ```

3. **分离验证逻辑**:
   ```rust
   // 建议：将空 hunk 检查提取为独立函数
   fn validate_update_hunk(path: &str, chunks: &[UpdateFileChunk], line_number: usize) 
       -> Result<(), ParseError> {
       if chunks.is_empty() {
           return Err(InvalidHunkError { ... });
       }
       Ok(())
   }
   ```

#### 6.2.2 测试改进

1. **添加边界测试**:
   - 测试只有 `@@` 标记但没有后续行的场景
   - 测试多个 Update File hunk，其中一个是空的场景

2. **验证错误信息格式**:
   ```rust
   // 当前测试只验证 stderr 包含特定字符串
   // 建议：使用结构化断言验证错误类型
   assert_matches!(
       result,
       Err(ApplyPatchError::ParseError(ParseError::InvalidHunkError { .. }))
   );
   ```

3. **添加文档测试**:
   ```rust
   /// ```
   /// // 示例：空 update hunk 应该失败
   /// let patch = "*** Begin Patch\n*** Update File: test.txt\n*** End Patch";
   /// assert!(apply_patch(patch, &mut stdout, &mut stderr).is_err());
   /// ```
   ```

#### 6.2.3 用户体验改进

1. **更友好的错误信息**:
   ```
   当前: "Invalid patch hunk on line 2: Update file hunk for path 'foo.txt' is empty"
   建议: "Error on line 2: The update for 'foo.txt' has no changes. \
          Each '*** Update File:' must be followed by at least one '@@' chunk."
   ```

2. **快速修复建议**:
   - 在错误信息中提供修复示例
   - 链接到完整的 patch 格式文档

### 6.3 相关 Issue 追踪

- 当前未发现与此场景直接相关的 open issue
- 建议关注：如果修改 patch 格式或错误处理逻辑，需要同步更新所有 scenario 测试

---

## 7. 总结

`008_rejects_empty_update_hunk` 是一个关键的**负向测试场景**，它验证了 apply-patch 工具对无效输入的健壮性。该场景确保：

1. **解析器严格性**: 工具拒绝缺少变更块的 Update File 声明
2. **错误清晰性**: 提供准确的错误信息和行号定位
3. **数据安全性**: 由于 patch 被拒绝，目标文件保持原样

核心检测逻辑位于 `parser.rs:318-323`，是 patch 语法验证的重要组成部分。该场景与 `005_rejects_empty_patch` 形成互补，共同覆盖了 patch 为空或 hunk 为空的边界情况。
