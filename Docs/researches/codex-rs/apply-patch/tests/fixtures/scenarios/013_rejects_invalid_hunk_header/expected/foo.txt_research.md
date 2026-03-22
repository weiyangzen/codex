# 研究文档：013_rejects_invalid_hunk_header 测试场景

## 目标文件

- **文件路径**: `codex-rs/apply-patch/tests/fixtures/scenarios/013_rejects_invalid_hunk_header/expected/foo.txt`
- **文件内容**: `stable`

---

## 1. 场景与职责

### 1.1 测试场景概述

本场景（`013_rejects_invalid_hunk_header`）是 `apply-patch` 工具的端到端测试用例之一，属于**负向测试（Negative Test）**，用于验证当传入的 patch 包含**无效的 hunk header** 时，工具能够正确拒绝处理并报告错误。

### 1.2 目录结构

```
013_rejects_invalid_hunk_header/
├── input/
│   └── foo.txt          # 输入文件，内容为 "stable"
├── expected/
│   └── foo.txt          # 期望输出文件，内容仍为 "stable"
└── patch.txt            # 包含无效 hunk header 的 patch
```

### 1.3 测试目的

- **验证错误处理**: 确保当 patch 中包含无法识别的 hunk header（如 `*** Frobnicate File: foo`）时，工具不会崩溃或静默失败
- **验证文件不变性**: 确保在解析失败的情况下，原始文件不会被修改
- **验证错误信息**: 确保返回清晰、有用的错误信息，帮助用户定位问题

---

## 2. 功能点目的

### 2.1 apply-patch 工具核心功能

`apply-patch` 是 Codex 项目中用于文件操作的底层工具，支持三种文件操作：

| 操作类型 | Header 格式 | 功能描述 |
|---------|------------|---------|
| Add File | `*** Add File: <path>` | 创建新文件 |
| Delete File | `*** Delete File: <path>` | 删除现有文件 |
| Update File | `*** Update File: <path>` | 更新现有文件内容（可选重命名） |

### 2.2 Hunk Header 验证的重要性

Hunk header 是 patch 中标识操作类型的关键元数据。有效的 header 解析是后续所有操作的基础：

1. **安全性**: 防止意外操作（如误删文件）
2. **明确性**: 每个操作必须显式声明意图
3. **可维护性**: 标准化的 header 格式便于工具解析和扩展

### 2.3 本场景的具体验证点

- **无效 header 识别**: `*** Frobnicate File: foo` 不是有效的操作类型
- **错误报告**: 工具应返回非零退出码并输出错误信息到 stderr
- **无副作用**: 输入文件 `foo.txt` 应保持原样（`stable`）

---

## 3. 具体技术实现

### 3.1 Patch 格式规范（EBNF 风格）

```
Patch := Begin { FileOp } End
Begin := "*** Begin Patch" NEWLINE
End := "*** End Patch" NEWLINE
FileOp := AddFile | DeleteFile | UpdateFile
AddFile := "*** Add File: " path NEWLINE { "+" line NEWLINE }
DeleteFile := "*** Delete File: " path NEWLINE
UpdateFile := "*** Update File: " path NEWLINE [ MoveTo ] { Hunk }
MoveTo := "*** Move to: " newPath NEWLINE
Hunk := "@@" [ header ] NEWLINE { HunkLine } [ "*** End of File" NEWLINE ]
HunkLine := (" " | "-" | "+") text NEWLINE
```

### 3.2 关键数据结构

#### 3.2.1 Hunk 枚举（parser.rs）

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

#### 3.2.2 解析错误类型（parser.rs）

```rust
#[derive(Debug, PartialEq, Error, Clone)]
pub enum ParseError {
    #[error("invalid patch: {0}")]
    InvalidPatchError(String),
    #[error("invalid hunk at line {line_number}, {message}")]
    InvalidHunkError { message: String, line_number: usize },
}
```

### 3.3 核心解析流程

#### 3.3.1 主解析函数（parser.rs:106-113）

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

#### 3.3.2 Hunk 解析函数（parser.rs:248-341）

```rust
fn parse_one_hunk(lines: &[&str], line_number: usize) -> Result<(Hunk, usize), ParseError> {
    let first_line = lines[0].trim();
    
    // 尝试匹配 Add File header
    if let Some(path) = first_line.strip_prefix(ADD_FILE_MARKER) {
        // 解析 Add File hunk...
    } 
    // 尝试匹配 Delete File header
    else if let Some(path) = first_line.strip_prefix(DELETE_FILE_MARKER) {
        // 解析 Delete File hunk...
    } 
    // 尝试匹配 Update File header
    else if let Some(path) = first_line.strip_prefix(UPDATE_FILE_MARKER) {
        // 解析 Update File hunk...
    } 
    // 无法匹配任何已知 header，返回错误
    else {
        Err(InvalidHunkError {
            message: format!(
                "'{first_line}' is not a valid hunk header. \
                Valid hunk headers: '*** Add File: {{path}}', \
                '*** Delete File: {{path}}', '*** Update File: {{path}}'"
            ),
            line_number,
        })
    }
}
```

### 3.4 本场景的 Patch 内容分析

**patch.txt 内容**:
```
*** Begin Patch
*** Frobnicate File: foo
*** End Patch
```

**解析过程**:
1. 验证 patch 边界：`*** Begin Patch` 和 `*** End Patch` 存在 ✓
2. 提取中间行：`*** Frobnicate File: foo`
3. 调用 `parse_one_hunk` 解析 hunk
4. 尝试匹配 `ADD_FILE_MARKER` (`*** Add File: `) → 失败
5. 尝试匹配 `DELETE_FILE_MARKER` (`*** Delete File: `) → 失败
6. 尝试匹配 `UPDATE_FILE_MARKER` (`*** Update File: `) → 失败
7. 返回 `InvalidHunkError`，行号 2，包含详细的错误信息

---

## 4. 关键代码路径与文件引用

### 4.1 核心源文件

| 文件路径 | 职责描述 | 关键行号 |
|---------|---------|---------|
| `codex-rs/apply-patch/src/parser.rs` | Patch 解析器实现 | 1-763 |
| `codex-rs/apply-patch/src/lib.rs` | 核心库逻辑，hunk 应用 | 1-1000+ |
| `codex-rs/apply-patch/src/standalone_executable.rs` | CLI 入口点 | 1-59 |
| `codex-rs/apply-patch/src/invocation.rs` | Shell 调用解析 | 1-813 |
| `codex-rs/apply-patch/src/seek_sequence.rs` | 模糊匹配算法 | 1-151 |

### 4.2 测试相关文件

| 文件路径 | 职责描述 |
|---------|---------|
| `codex-rs/apply-patch/tests/suite/scenarios.rs` | 场景测试框架，遍历所有 fixtures |
| `codex-rs/apply-patch/tests/suite/tool.rs` | CLI 工具测试，包含 `test_apply_patch_cli_rejects_invalid_hunk_header` |
| `codex-rs/apply-patch/tests/suite/cli.rs` | CLI 测试辅助函数 |
| `codex-rs/apply-patch/tests/fixtures/scenarios/` | 端到端测试场景目录 |

### 4.3 关键代码引用

#### 4.3.1 Hunk Header 常量定义（parser.rs:31-39）

```rust
const BEGIN_PATCH_MARKER: &str = "*** Begin Patch";
const END_PATCH_MARKER: &str = "*** End Patch";
const ADD_FILE_MARKER: &str = "*** Add File: ";
const DELETE_FILE_MARKER: &str = "*** Delete File: ";
const UPDATE_FILE_MARKER: &str = "*** Update File: ";
const MOVE_TO_MARKER: &str = "*** Move to: ";
const EOF_MARKER: &str = "*** End of File";
```

#### 4.3.2 场景测试执行逻辑（scenarios.rs:30-63）

```rust
fn run_apply_patch_scenario(dir: &Path) -> anyhow::Result<()> {
    let tmp = tempdir()?;

    // 复制输入文件到临时目录
    let input_dir = dir.join("input");
    if input_dir.is_dir() {
        copy_dir_recursive(&input_dir, tmp.path())?;
    }

    // 读取 patch.txt
    let patch = fs::read_to_string(dir.join("patch.txt"))?;

    // 执行 apply_patch（不检查退出码）
    Command::new(codex_utils_cargo_bin::cargo_bin("apply_patch")?)
        .arg(patch)
        .current_dir(tmp.path())
        .output()?;

    // 比较实际结果与期望结果
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

#### 4.3.3 对应的显式测试（tool.rs:209-220）

```rust
#[test]
fn test_apply_patch_cli_rejects_invalid_hunk_header() -> anyhow::Result<()> {
    let tmp = tempdir()?;

    apply_patch_command(tmp.path())?
        .arg("*** Begin Patch\n*** Frobnicate File: foo\n*** End Patch")
        .assert()
        .failure()
        .stderr("Invalid patch hunk on line 2: '*** Frobnicate File: foo' is not a valid hunk header. Valid hunk headers: '*** Add File: {path}', '*** Delete File: {path}', '*** Update File: {path}'\n");

    Ok(())
}
```

---

## 5. 依赖与外部交互

### 5.1 内部依赖

```
codex-apply-patch
├── codex-utils-cargo-bin (测试依赖，用于定位二进制文件)
├── anyhow (错误处理)
├── similar (文本差异计算)
├── thiserror (错误类型定义)
├── tree-sitter (Bash 脚本解析)
├── tree-sitter-bash (Bash 语法定义)
├── assert_cmd (CLI 测试)
├── assert_matches (模式匹配测试)
├── pretty_assertions (美观的测试输出)
└── tempfile (临时目录管理)
```

### 5.2 外部工具交互

| 工具/环境 | 交互方式 | 用途 |
|---------|---------|------|
| 文件系统 | `std::fs` 模块 | 读取/写入文件，创建目录 |
| 标准 I/O | `stdin`/`stdout`/`stderr` | 接收 patch 内容，输出结果和错误 |
| Shell (Bash/PowerShell/Cmd) | Tree-sitter 解析 | 解析 heredoc 形式的调用 |

### 5.3 测试框架集成

- **Cargo Test**: 通过 `tests/all.rs` 聚合所有测试模块
- **Bazel**: 通过 `BUILD.bazel` 定义构建规则
- **场景测试**: 自动发现 `fixtures/scenarios/` 下的所有子目录

---

## 6. 风险、边界与改进建议

### 6.1 当前风险点

#### 6.1.1 Header 匹配的严格性

**问题**: 当前实现使用 `strip_prefix` 进行前缀匹配，对大小写敏感。

```rust
if let Some(path) = first_line.strip_prefix(ADD_FILE_MARKER) {
    // ...
}
```

**风险**: 如果 LLM 生成的大小写不一致（如 `*** add file: foo`），会导致解析失败。

**缓解措施**: 文档中明确规范格式，工具指令中强调大小写敏感性。

#### 6.1.2 错误信息的国际化

**问题**: 错误信息目前只有英文版本。

**风险**: 非英语用户可能难以理解错误原因。

#### 6.1.3 部分失败的副作用

**问题**: 虽然本场景测试的是解析失败（无副作用），但在多 hunk 场景中，如果前面成功后面失败，会留下部分修改。

**相关测试**: `015_failure_after_partial_success_leaves_changes` 验证了这一行为。

### 6.2 边界情况

| 边界情况 | 当前行为 | 测试覆盖 |
|---------|---------|---------|
| 空 patch | 报错 "No files were modified" | `005_rejects_empty_patch` |
| 只有空白字符的 header | 视为无效 header | 未明确测试 |
| 超长的 header 行 | 正常解析（受限于内存） | 未测试 |
| 包含特殊字符的路径 | 正常处理 | `019_unicode_simple` |
| Header 后缺少换行 | 可能解析异常 | 未明确测试 |

### 6.3 改进建议

#### 6.3.1 增强错误恢复能力

建议添加 "Did you mean?" 提示，当检测到类似但非精确的 header 时给出建议：

```rust
// 伪代码
if looks_like_header_but_invalid(first_line) {
    let suggestion = suggest_closest_header(first_line);
    Err(InvalidHunkError {
        message: format!("'{}' is not a valid hunk header. Did you mean: '{}'?", 
                        first_line, suggestion),
        line_number,
    })
}
```

#### 6.3.2 支持大小写不敏感的 Header

考虑到 LLM 可能生成大小写不一致的 header，可以考虑：

```rust
let first_line_lower = first_line.to_lowercase();
if first_line_lower.starts_with("*** add file: ") {
    // ...
}
```

**注意**: 这需要权衡，因为会降低格式的严格性。

#### 6.3.3 添加更多负向测试场景

建议添加以下测试场景：

1. `023_rejects_malformed_add_file`: 测试 Add File hunk 中缺少 `+` 前缀的行
2. `024_rejects_duplicate_file_operations`: 测试同一文件被多次操作
3. `025_rejects_absolute_path`: 测试拒绝绝对路径（安全考虑）

#### 6.3.4 性能优化

对于大型 patch 文件，当前的逐行解析可能存在性能瓶颈。可以考虑：

- 使用 `memchr` 进行快速模式匹配
- 对超大文件使用流式解析而非一次性加载到内存

### 6.4 安全考虑

| 风险 | 当前防护 | 建议 |
|-----|---------|------|
| 路径遍历攻击 | 相对路径限制 | 添加显式的 `..` 检测 |
| 符号链接攻击 | 无特殊处理 | 解析前检查文件类型 |
| 拒绝服务（超大 patch） | 无限制 | 添加大小和行数限制 |

---

## 7. 总结

`013_rejects_invalid_hunk_header` 是一个关键的负向测试场景，验证了 `apply-patch` 工具在面对无效 hunk header 时的正确行为：

1. **输入**: 包含 `*** Frobnicate File: foo` 无效 header 的 patch
2. **期望行为**: 工具应拒绝处理，返回错误，且原始文件保持不变
3. **实际行为**: 工具返回 `InvalidHunkError`，stderr 输出清晰错误信息，文件保持 `stable`

该测试场景与 `test_apply_patch_cli_rejects_invalid_hunk_header` 单元测试形成互补，确保了解析逻辑的健壮性。

---

## 附录：相关代码引用索引

- **Parser 模块**: `codex-rs/apply-patch/src/parser.rs`
  - `parse_one_hunk`: 行 248-341
  - `ParseError` 定义: 行 49-56
  - `Hunk` 枚举定义: 行 58-87

- **测试框架**: `codex-rs/apply-patch/tests/suite/scenarios.rs`
  - `test_apply_patch_scenarios`: 行 10-26
  - `run_apply_patch_scenario`: 行 30-63

- **CLI 测试**: `codex-rs/apply-patch/tests/suite/tool.rs`
  - `test_apply_patch_cli_rejects_invalid_hunk_header`: 行 209-220

- **工具文档**: `codex-rs/apply-patch/apply_patch_tool_instructions.md`
  - Patch 格式完整规范
