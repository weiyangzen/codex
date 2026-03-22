# 研究文档：`013_rejects_invalid_hunk_header` 测试场景

## 场景与职责

### 测试场景概述

`013_rejects_invalid_hunk_header` 是 `codex-apply-patch`  crate 的一个集成测试场景，用于验证当 patch 文件包含无效的 hunk 头（hunk header）时，系统能够正确拒绝并报告错误。

### 测试文件结构

```
codex-rs/apply-patch/tests/fixtures/scenarios/013_rejects_invalid_hunk_header/
├── patch.txt          # 包含无效 hunk 头的 patch 文件
├── input/             # 测试前的文件系统状态
│   └── foo.txt        # 内容为 "stable"
└── expected/          # 测试后的预期文件系统状态
    └── foo.txt        # 内容仍为 "stable"（patch 应被拒绝，文件未改变）
```

### patch.txt 内容分析

```
*** Begin Patch
*** Frobnicate File: foo
*** End Patch
```

该 patch 文件的关键特征是：
- 使用了有效的 patch 边界标记（`*** Begin Patch` 和 `*** End Patch`）
- 但使用了无效的 hunk 头 `*** Frobnicate File: foo`，而非标准定义的三种有效头之一

### 预期行为

- **解析阶段**：parser 应该识别出 `*** Frobnicate File: foo` 不是有效的 hunk 头
- **错误报告**：应输出错误信息到 stderr，指明第 2 行包含无效的 hunk 头
- **文件系统状态**：由于 patch 被拒绝，`input/foo.txt` 应保持不变，与 `expected/foo.txt` 一致

---

## 功能点目的

### 核心功能：Hunk Header 验证

该测试验证 `parse_one_hunk` 函数对无效 hunk 头的拒绝能力。根据 Lark 语法规范，有效的 hunk 头只有三种：

1. `*** Add File: <path>` - 添加文件
2. `*** Delete File: <path>` - 删除文件
3. `*** Update File: <path>` - 更新文件

### 防御性编程

此测试确保系统对 LLM 生成的 patch 具有容错能力。由于 LLM 可能产生格式错误的输出（如本例中的虚构动词 "Frobnicate"），系统必须：
- 明确拒绝无效操作
- 提供清晰的错误信息帮助诊断
- 不执行任何文件系统修改（原子性失败）

### 错误信息质量

期望的错误输出格式：
```
Invalid patch hunk on line 2: '*** Frobnicate File: foo' is not a valid hunk header. Valid hunk headers: '*** Add File: {path}', '*** Delete File: {path}', '*** Update File: {path}'
```

这体现了良好的错误报告设计：
- 明确指出错误位置（line 2）
- 显示实际接收到的内容
- 列出所有有效的选项供参考

---

## 具体技术实现

### 关键流程

#### 1. Patch 解析流程

```
apply_patch(patch_text)
  └── parse_patch(patch_text)
        └── parse_patch_text(patch, mode)
              ├── check_patch_boundaries_strict(&lines)  [验证边界标记]
              └── 循环解析每个 hunk
                    └── parse_one_hunk(lines, line_number)  [关键函数]
```

#### 2. Hunk 头解析逻辑（`parse_one_hunk` 函数）

位于 `codex-rs/apply-patch/src/parser.rs:248-341`：

```rust
fn parse_one_hunk(lines: &[&str], line_number: usize) -> Result<(Hunk, usize), ParseError> {
    let first_line = lines[0].trim();
    
    // 尝试匹配 Add File 头
    if let Some(path) = first_line.strip_prefix(ADD_FILE_MARKER) {
        // 解析 Add File hunk...
    } 
    // 尝试匹配 Delete File 头
    else if let Some(path) = first_line.strip_prefix(DELETE_FILE_MARKER) {
        // 解析 Delete File hunk...
    } 
    // 尝试匹配 Update File 头
    else if let Some(path) = first_line.strip_prefix(UPDATE_FILE_MARKER) {
        // 解析 Update File hunk...
    } 
    // 所有匹配失败，返回错误
    else {
        Err(InvalidHunkError {
            message: format!(
                "'{}' is not a valid hunk header. Valid hunk headers: ..."
            ),
            line_number,
        })
    }
}
```

#### 3. 错误处理流程

当 `parse_one_hunk` 返回 `Err(InvalidHunkError)` 时，错误传播路径：

```
parse_one_hunk (返回 Err)
  └── parse_patch_text (传播 Err)
        └── parse_patch (传播 Err)
              └── apply_patch (处理错误)
                    ├── 写入错误信息到 stderr
                    └── 返回 ApplyPatchError::ParseError
```

`apply_patch` 函数中的错误处理代码（`lib.rs:188-207`）：

```rust
let hunks = match parse_patch(patch) {
    Ok(source) => source.hunks,
    Err(e) => {
        match &e {
            InvalidPatchError(message) => {
                writeln!(stderr, "Invalid patch: {message}")?;
            }
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
```

### 数据结构

#### ParseError 枚举

```rust
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

### 常量定义

```rust
const BEGIN_PATCH_MARKER: &str = "*** Begin Patch";
const END_PATCH_MARKER: &str = "*** End Patch";
const ADD_FILE_MARKER: &str = "*** Add File: ";
const DELETE_FILE_MARKER: &str = "*** Delete File: ";
const UPDATE_FILE_MARKER: &str = "*** Update File: ";
```

---

## 关键代码路径与文件引用

### 核心实现文件

| 文件路径 | 职责 | 相关行号 |
|---------|------|---------|
| `codex-rs/apply-patch/src/parser.rs` | Patch 解析器实现 | 1-763 |
| `codex-rs/apply-patch/src/lib.rs` | 核心库逻辑、错误处理 | 1-1000+ |
| `codex-rs/apply-patch/src/standalone_executable.rs` | CLI 入口点 | 1-59 |

### 关键函数引用

| 函数 | 文件 | 行号 | 职责 |
|-----|------|------|------|
| `parse_one_hunk` | `parser.rs` | 248-341 | 解析单个 hunk，拒绝无效头 |
| `parse_patch` | `parser.rs` | 106-113 | 公开 API，启动解析 |
| `parse_patch_text` | `parser.rs` | 154-183 | 内部解析逻辑 |
| `apply_patch` | `lib.rs` | 183-213 | 应用 patch，处理解析错误 |

### 测试相关文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/apply-patch/tests/suite/scenarios.rs` | 场景测试框架 |
| `codex-rs/apply-patch/tests/suite/tool.rs` | 显式测试无效 hunk 头场景（`test_apply_patch_cli_rejects_invalid_hunk_header`） |
| `codex-rs/apply-patch/tests/suite/cli.rs` | CLI 集成测试 |

### 测试框架执行流程

`scenarios.rs` 中的 `run_apply_patch_scenario` 函数：

```rust
fn run_apply_patch_scenario(dir: &Path) -> anyhow::Result<()> {
    let tmp = tempdir()?;
    
    // 1. 复制 input 到临时目录
    let input_dir = dir.join("input");
    copy_dir_recursive(&input_dir, tmp.path())?;
    
    // 2. 读取 patch.txt
    let patch = fs::read_to_string(dir.join("patch.txt"))?;
    
    // 3. 执行 apply_patch（不检查 exit code，因为预期会失败）
    Command::new(cargo_bin("apply_patch")?)
        .arg(patch)
        .current_dir(tmp.path())
        .output()?;
    
    // 4. 比较结果与 expected 目录
    let expected_snapshot = snapshot_dir(&dir.join("expected"))?;
    let actual_snapshot = snapshot_dir(tmp.path())?;
    assert_eq!(actual_snapshot, expected_snapshot);
    
    Ok(())
}
```

---

## 依赖与外部交互

### 内部依赖

| 模块 | 依赖类型 | 说明 |
|-----|---------|------|
| `codex-utils-cargo-bin` | dev-dependency | 测试时定位二进制文件 |

### 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `thiserror` | 错误类型派生宏 |
| `anyhow` | 错误处理与传播 |
| `similar` | 文本差异计算（unified diff） |
| `tree-sitter` | Bash 脚本解析（用于 heredoc 提取） |
| `tree-sitter-bash` | Bash 语法定义 |

### 测试依赖

| Crate | 用途 |
|-------|------|
| `assert_cmd` | CLI 测试断言 |
| `assert_matches` | 模式匹配断言 |
| `pretty_assertions` | 美观的差异输出 |
| `tempfile` | 临时目录管理 |

### 进程交互

```
测试进程
  └── 执行 apply_patch 二进制
        ├── 从 stdin 或参数读取 patch
        ├── 解析 patch
        ├── 如遇错误，写入 stderr
        └── 返回 exit code (0=成功, 1=失败)
```

---

## 风险、边界与改进建议

### 当前风险

#### 1. 错误信息大小写敏感

当前实现使用 `strip_prefix` 进行精确匹配，对大小写敏感。如果 LLM 生成 `*** add file: foo`（小写），将被拒绝。

**代码位置**：`parser.rs:251-279`

**建议**：考虑增加大小写不敏感匹配或更宽容的解析模式。

#### 2. 空白字符处理

虽然 patch 边界标记允许前后空白（`trim()` 处理），但 hunk 头前缀检查使用 `strip_prefix`，对额外空白敏感。

**示例问题**：`***  Add File: foo`（两个空格）会被拒绝。

#### 3. 行号计算

错误报告的行号是 1-indexed 的，但内部处理是 0-indexed。在复杂 patch 中，行号计算可能出错。

### 边界情况

| 场景 | 当前行为 | 评估 |
|-----|---------|------|
| 空 patch（只有 Begin/End） | 拒绝："No files were modified" | ✅ 正确 |
| 多个无效 hunk 头 | 报告第一个错误 | ✅ 合理 |
| 混合有效/无效 hunk | 报告第一个无效头 | ✅ 合理 |
| 极长 hunk 头行 | 正常处理 | ✅ 无缓冲区限制 |
| Unicode 路径 | 支持 | ✅ 支持 UTF-8 |

### 改进建议

#### 1. 错误恢复机制

当前实现遇到第一个错误即停止。对于大型 patch，可考虑：
- 收集所有解析错误后统一报告
- 提供 "best effort" 模式，跳过无效 hunk 继续处理

#### 2. 模糊匹配

考虑实现 Levenshtein 距离或类似算法，对接近但不完全匹配的头提供建议：
```
Error: '*** Frobnicate File: foo' is not a valid hunk header.
Did you mean: '*** Update File: foo'?
```

#### 3. 扩展测试覆盖

建议增加以下边界测试：
- 大小写变体（`add file`, `ADD FILE`）
- 多余空格（`***  Add File: foo`）
- 拼写错误（`*** Addd File: foo`）
- 空 hunk 头行（`*** `）

#### 4. 文档增强

`apply_patch_tool_instructions.md` 已包含清晰规范，但可考虑：
- 增加常见错误示例
- 提供调试技巧

### 相关测试对照

| 测试场景 | 目的 | 与本场景关系 |
|---------|------|-------------|
| `005_rejects_empty_patch` | 验证空 patch 拒绝 | 边界条件 |
| `008_rejects_empty_update_hunk` | 验证空 Update hunk 拒绝 | 同类错误处理 |
| `017_whitespace_padded_hunk_header` | 验证空白填充头处理 | 对比行为 |

### 代码质量评估

| 指标 | 评分 | 说明 |
|-----|------|------|
| 错误信息清晰度 | ⭐⭐⭐⭐⭐ | 提供具体行号和有效选项 |
| 防御性 | ⭐⭐⭐⭐⭐ | 严格验证所有输入 |
| 可测试性 | ⭐⭐⭐⭐⭐ | 场景测试覆盖完善 |
| 容错性 | ⭐⭐⭐ | 对近似匹配不够宽容 |

---

## 总结

`013_rejects_invalid_hunk_header` 是一个设计良好的防御性测试场景，验证系统对无效 hunk 头的拒绝能力。该测试确保：

1. **安全性**：无效 patch 不会导致意外的文件系统修改
2. **可诊断性**：清晰的错误信息帮助定位问题
3. **一致性**：与 Lark 语法规范严格对齐

该场景与 `tests/suite/tool.rs` 中的显式测试 `test_apply_patch_cli_rejects_invalid_hunk_header` 形成互补，既验证了具体错误行为，又通过场景测试框架验证了文件系统状态不变性。
