# Research: modify.txt in 006_rejects_missing_context Test Scenario

## Executive Summary

This document provides an in-depth analysis of the `modify.txt` file located at `codex-rs/apply-patch/tests/fixtures/scenarios/006_rejects_missing_context/input/modify.txt`. This file serves as a **test fixture** for validating the `apply_patch` tool's behavior when encountering a patch with **missing context lines** - a critical error-handling scenario that ensures the tool fails gracefully rather than making incorrect modifications.

---

## 1. 场景与职责 (Scene and Responsibilities)

### 1.1 测试场景定位

| 属性 | 值 |
|------|-----|
| **场景编号** | 006 |
| **场景名称** | `rejects_missing_context` |
| **测试类型** | 负面测试 (Negative Test) / 错误处理测试 |
| **所属模块** | `codex-apply-patch` |
| **测试框架** | 基于文件系统的场景测试 (Scenario-based Testing) |

### 1.2 文件职责

`modify.txt` 在此测试场景中承担以下职责：

1. **作为被修改的目标文件**: 它是补丁操作试图修改的对象
2. **提供基准内容**: 文件内容 `"line1\nline2\n"` 用于验证补丁匹配失败时的行为
3. **保持原始状态**: 测试期望该文件在补丁应用失败后**保持不变**，用于验证原子性失败

### 1.3 目录结构上下文

```
codex-rs/apply-patch/tests/fixtures/scenarios/006_rejects_missing_context/
├── input/
│   └── modify.txt          # ← 本研究对象 (测试输入)
├── expected/
│   └── modify.txt          # 期望输出 (应与 input 完全一致)
└── patch.txt               # 包含错误上下文的补丁
```

---

## 2. 功能点目的 (Functional Purpose)

### 2.1 测试目标

该测试场景验证 `apply_patch` 工具的以下核心能力：

| 能力 | 描述 |
|------|------|
| **上下文验证** | 当补丁中指定的旧内容 (`old_lines`) 在目标文件中找不到时，必须拒绝应用 |
| **错误报告** | 提供清晰的错误信息，指出哪些行未能找到 |
| **原子性保证** | 补丁应用失败时，目标文件必须保持原状（无部分修改） |

### 2.2 具体测试逻辑

**输入文件内容 (`modify.txt`)**:
```
line1
line2
```

**补丁内容 (`patch.txt`)**:
```
*** Begin Patch
*** Update File: modify.txt
@@
-missing
+changed
*** End Patch
```

**关键矛盾点**:
- 补丁试图删除 `"missing"` 这一行
- 但实际文件只有 `"line1"` 和 `"line2"`
- `"missing"` 在文件中**不存在**

**期望行为**:
1. `apply_patch` 命令应该**失败** (返回非零退出码)
2. 错误信息应该提示找不到 `"missing"` 这一行
3. `modify.txt` 文件内容应保持不变 (`"line1\nline2\n"`)

---

## 3. 具体技术实现 (Technical Implementation)

### 3.1 补丁应用的核心流程

```rust
// lib.rs: apply_patch() → apply_hunks() → apply_hunks_to_files()

pub fn apply_patch(
    patch: &str,
    stdout: &mut impl std::io::Write,
    stderr: &mut impl std::io::Write,
) -> Result<(), ApplyPatchError> {
    let hunks = parse_patch(patch)?;  // 解析补丁
    apply_hunks(&hunks, stdout, stderr)  // 应用hunks
}
```

### 3.2 上下文匹配算法

当处理 `UpdateFile` hunk 时，核心逻辑在 `derive_new_contents_from_chunks()` 中：

```rust
// lib.rs: derive_new_contents_from_chunks() → compute_replacements()

fn compute_replacements(
    original_lines: &[String],
    path: &Path,
    chunks: &[UpdateFileChunk],
) -> Result<Vec<(usize, usize, Vec<String>)>, ApplyPatchError> {
    for chunk in chunks {
        // 1. 首先查找 change_context (如果存在)
        if let Some(ctx_line) = &chunk.change_context {
            if let Some(idx) = seek_sequence::seek_sequence(...) {
                line_index = idx + 1;
            } else {
                return Err(ApplyPatchError::ComputeReplacements(format!(
                    "Failed to find context '{}' in {}",
                    ctx_line, path.display()
                )));
            }
        }

        // 2. 查找 old_lines (要替换的内容)
        let pattern: &[String] = &chunk.old_lines;
        let found = seek_sequence::seek_sequence(original_lines, pattern, line_index, chunk.is_end_of_file);
        
        if let Some(start_idx) = found {
            replacements.push((start_idx, pattern.len(), new_slice.to_vec()));
        } else {
            // ← 006场景触发此错误分支
            return Err(ApplyPatchError::ComputeReplacements(format!(
                "Failed to find expected lines in {}:\n{}",
                path.display(),
                chunk.old_lines.join("\n"),
            )));
        }
    }
}
```

### 3.3 序列查找算法 (seek_sequence)

`seek_sequence.rs` 实现了多级容错匹配策略：

```rust
pub(crate) fn seek_sequence(
    lines: &[String],
    pattern: &[String],
    start: usize,
    eof: bool,
) -> Option<usize> {
    // 匹配策略（按严格程度递减）：
    // 1. 精确匹配 (exact match)
    // 2. 忽略尾部空白 (rstrip match)
    // 3. 忽略首尾空白 (trim match)
    // 4. Unicode 规范化匹配 (normalise match)
    
    // 006场景中，"missing" 无法匹配 "line1" 或 "line2"
    // 所有策略都失败，返回 None
}
```

**Unicode 规范化映射**:
```rust
fn normalise(s: &str) -> String {
    s.trim()
        .chars()
        .map(|c| match c {
            // 各种连字符/破折号 → ASCII '-'
            '\u{2010}' | '\u{2011}' | '\u{2012}' | '\u{2013}' | '\u{2014}' | '\u{2015}'
            | '\u{2212}' => '-',
            // 花式引号 → 标准引号
            '\u{2018}' | '\u{2019}' | '\u{201A}' | '\u{201B}' => '\'',
            '\u{201C}' | '\u{201D}' | '\u{201E}' | '\u{201F}' => '"',
            // 非断空格等 → 普通空格
            '\u{00A0}' | '\u{2002}' | ... | '\u{3000}' => ' ',
            other => other,
        })
        .collect()
}
```

### 3.4 关键数据结构

#### 3.4.1 UpdateFileChunk (parser.rs)

```rust
#[derive(Debug, PartialEq, Clone)]
pub struct UpdateFileChunk {
    /// 用于定位的上下文行（通常是类/函数定义）
    pub change_context: Option<String>,
    
    /// 要被替换的旧行
    pub old_lines: Vec<String>,
    
    /// 新行内容
    pub new_lines: Vec<String>,
    
    /// 是否必须在文件末尾匹配
    pub is_end_of_file: bool,
}
```

#### 3.4.2 Hunk 枚举 (parser.rs)

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

### 3.5 错误类型定义

```rust
// lib.rs
#[derive(Debug, Error, PartialEq)]
pub enum ApplyPatchError {
    #[error(transparent)]
    ParseError(#[from] ParseError),
    
    #[error(transparent)]
    IoError(#[from] IoError),
    
    /// 计算替换内容时出错 (006场景触发)
    #[error("{0}")]
    ComputeReplacements(String),
    
    /// 隐式调用错误
    #[error("patch detected without explicit call to apply_patch...")]
    ImplicitInvocation,
}
```

---

## 4. 关键代码路径与文件引用 (Key Code Paths)

### 4.1 完整调用链

```
测试执行入口
    │
    ▼
codex-rs/apply-patch/tests/suite/scenarios.rs
    │   run_apply_patch_scenario()
    │   - 读取 patch.txt
    │   - 复制 input/ 到临时目录
    │   - 执行 apply_patch 命令
    │   - 比较结果与 expected/
    │
    ▼
codex-rs/apply-patch/src/standalone_executable.rs
    │   run_main()
    │   - 解析命令行参数
    │   - 读取 stdin（如果无参数）
    │
    ▼
codex-rs/apply-patch/src/lib.rs
    │   apply_patch()
    │   - 解析补丁文本
    │
    ▼
codex-rs/apply-patch/src/parser.rs
    │   parse_patch()
    │   - 解析为 Hunk 列表
    │   - 006场景: 解析成功（语法正确）
    │
    ▼
codex-rs/apply-patch/src/lib.rs
    │   apply_hunks() → apply_hunks_to_files()
    │   - 遍历每个 hunk
    │   - 006场景: UpdateFile hunk
    │
    ▼
codex-rs/apply-patch/src/lib.rs
    │   derive_new_contents_from_chunks()
    │   - 读取原始文件内容
    │   - 分割为行
    │
    ▼
codex-rs/apply-patch/src/lib.rs
    │   compute_replacements()
    │   - 尝试匹配 old_lines
    │   - 006场景: 调用 seek_sequence() 查找 "missing"
    │
    ▼
codex-rs/apply-patch/src/seek_sequence.rs
        seek_sequence()
        - 在 ["line1", "line2"] 中查找 ["missing"]
        - 所有匹配策略失败
        - 返回 None
        
    ▼
codex-rs/apply-patch/src/lib.rs
    compute_replacements() (续)
    - seek_sequence 返回 None
    - 返回 Err(ApplyPatchError::ComputeReplacements(...))
    
    ▼
codex-rs/apply-patch/src/lib.rs
    apply_hunks()
    - 捕获错误
    - 写入 stderr: "Failed to find expected lines in modify.txt:\nmissing\n"
    - 返回 Err
    
    ▼
codex-rs/apply-patch/src/standalone_executable.rs
    run_main()
    - 返回退出码 1
```

### 4.2 关键文件清单

| 文件路径 | 职责 | 006场景中的角色 |
|----------|------|-----------------|
| `src/lib.rs` | 核心补丁应用逻辑 | 包含 `compute_replacements()`，触发错误 |
| `src/parser.rs` | 补丁语法解析 | 解析成功，生成 UpdateFile hunk |
| `src/seek_sequence.rs` | 序列查找算法 | 返回 None，导致匹配失败 |
| `src/standalone_executable.rs` | CLI 入口 | 处理退出码和错误输出 |
| `tests/suite/scenarios.rs` | 场景测试框架 | 执行测试，验证文件状态 |
| `tests/suite/tool.rs` | CLI 工具测试 | 包含类似测试 `test_apply_patch_cli_reports_missing_context` |

---

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### 5.1  crate 依赖

```toml
# Cargo.toml
[dependencies]
anyhow = "..."           # 错误处理
similar = "..."          # 文本差异计算 (TextDiff)
thiserror = "..."        # 错误类型派生
tree-sitter = "..."      # Bash 脚本解析 (用于 heredoc 提取)
tree-sitter-bash = "..." # Bash 语法定义
```

### 5.2 测试依赖

```toml
[dev-dependencies]
assert_cmd = "..."       # CLI 测试断言
codex-utils-cargo-bin = "..."  # 二进制文件路径解析
pretty_assertions = "..." # 美观的差异输出
tempfile = "..."         # 临时目录管理
```

### 5.3 外部工具交互

| 交互对象 | 方式 | 目的 |
|----------|------|------|
| 文件系统 | `std::fs` | 读取/写入文件，创建目录 |
| 标准输出 | `std::io::stdout()` | 输出成功摘要 |
| 标准错误 | `std::io::stderr()` | 输出错误信息 |
| 进程退出码 | `std::process::exit()` | 返回 0 (成功) 或 1 (失败) |

### 5.4 相关测试用例

**集成测试** (`tests/suite/tool.rs:98-111`):
```rust
#[test]
fn test_apply_patch_cli_reports_missing_context() -> anyhow::Result<()> {
    let tmp = tempdir()?;
    let target_path = tmp.path().join("modify.txt");
    fs::write(&target_path, "line1\nline2\n")?;

    apply_patch_command(tmp.path())?
        .arg("*** Begin Patch\n*** Update File: modify.txt\n@@\n-missing\n+changed\n*** End Patch")
        .assert()
        .failure()
        .stderr("Failed to find expected lines in modify.txt:\nmissing\n");
    assert_eq!(fs::read_to_string(&target_path)?, "line1\nline2\n");

    Ok(())
}
```

此测试与 006 场景测试**完全等价**，只是实现方式不同（代码 vs 文件 fixture）。

---

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Recommendations)

### 6.1 当前实现的风险

| 风险点 | 描述 | 严重程度 |
|--------|------|----------|
| **部分应用残留** | 如果多个 hunks 中前面的成功，后面的失败，已应用的修改不会回滚 | 中 |
| **模糊匹配过度** | Unicode 规范化可能意外匹配不相关的行 | 低 |
| **行尾空白处理** | 不同操作系统换行符 (CRLF/LF) 可能导致匹配失败 | 中 |

### 6.2 边界情况分析

#### 6.2.1 已处理的边界

| 场景 | 处理方式 |
|------|----------|
| 空 pattern | `seek_sequence()` 返回 `Some(start)`（无操作匹配） |
| pattern 比输入长 | 提前返回 `None`，避免越界 panic |
| 文件末尾匹配 | `is_end_of_file` 标志调整搜索起始位置 |
| 尾部空行 | 自动剥离/添加尾部空行以匹配 diff 行为 |

#### 6.2.2 潜在边界问题

| 场景 | 当前行为 | 建议 |
|------|----------|------|
| 二进制文件 | 尝试作为 UTF-8 文本读取，可能失败 | 明确检测二进制文件，给出友好错误 |
| 超大文件 | 全部读入内存 | 考虑流式处理 |
| 循环依赖的 hunks | 未检测 | 添加 hunk 间依赖验证 |

### 6.3 改进建议

#### 6.3.1 错误信息增强

当前错误信息:
```
Failed to find expected lines in modify.txt:
missing
```

建议增强:
```
Failed to apply patch to modify.txt:
  Could not find the following context lines:
    - "missing"
  
  File content (2 lines):
    1 | line1
    2 | line2
  
  Suggestion: Check if the file has been modified or if the patch context is correct.
```

#### 6.3.2 原子性改进

当前实现 (`lib.rs:279-339`):
```rust
fn apply_hunks_to_files(hunks: &[Hunk]) -> anyhow::Result<AffectedPaths> {
    // 逐个应用 hunk，遇到错误即返回
    // 已应用的 hunks 不会自动回滚
}
```

建议实现**两阶段提交**:
1. **验证阶段**: 预演所有 hunks，验证所有上下文匹配
2. **应用阶段**: 全部验证通过后，实际修改文件
3. **回滚机制**: 应用失败时回滚已完成的修改

#### 6.3.3 模糊匹配可配置

当前 Unicode 规范化是**硬编码**的。建议添加配置选项:

```rust
pub enum MatchMode {
    Strict,      // 精确匹配
    Whitespace,  // 忽略空白差异
    Unicode,     // 包含 Unicode 规范化（当前行为）
}
```

#### 6.3.4 测试覆盖增强

建议添加以下测试场景:

| 场景编号 | 描述 | 预期行为 |
|----------|------|----------|
| 006b | 多个 hunks，第一个失败 | 文件保持原状 |
| 006c | change_context 不匹配 | 报告 context 未找到 |
| 006d | 空 old_lines（纯添加） | 成功添加（无需匹配） |
| 006e | 正则表达式特殊字符 | 作为字面量匹配，非正则 |

### 6.4 相关场景对比

| 场景 | 名称 | 与 006 的关系 |
|------|------|---------------|
| 003 | `multiple_chunks` | 正向测试：多个 hunks 成功应用 |
| 005 | `rejects_empty_patch` | 错误处理：无 hunks |
| 007 | `rejects_missing_file_delete` | 错误处理：删除不存在的文件 |
| 008 | `rejects_empty_update_hunk` | 错误处理：空的 update hunk |
| 009 | `requires_existing_file_for_update` | 错误处理：更新不存在的文件 |
| 015 | `failure_after_partial_success` | 错误处理：部分成功后失败（残留问题） |

---

## 7. 总结

`modify.txt` 在 `006_rejects_missing_context` 测试场景中扮演**受害者文件**的角色，用于验证 `apply_patch` 工具在面对不匹配上下文时的正确错误处理。该测试确保：

1. **正确性**: 工具不会错误地应用不匹配的补丁
2. **安全性**: 失败时不会破坏原始文件
3. **可诊断性**: 提供清晰的错误信息帮助用户定位问题

该场景与 `tests/suite/tool.rs` 中的 `test_apply_patch_cli_reports_missing_context` 测试形成**双重验证**，确保 CLI 行为和场景测试行为一致。

---

## 附录 A: 完整文件内容

### A.1 modify.txt (input 和 expected)
```
line1
line2
```

### A.2 patch.txt
```
*** Begin Patch
*** Update File: modify.txt
@@
-missing
+changed
*** End Patch
```

### A.3 期望的错误输出
```
Failed to find expected lines in modify.txt:
missing
```

---

## 附录 B: 相关代码引用

### B.1 场景测试执行器 (tests/suite/scenarios.rs:30-63)
```rust
fn run_apply_patch_scenario(dir: &Path) -> anyhow::Result<()> {
    let tmp = tempdir()?;
    
    // 复制 input 文件
    let input_dir = dir.join("input");
    if input_dir.is_dir() {
        copy_dir_recursive(&input_dir, tmp.path())?;
    }
    
    // 读取补丁
    let patch = fs::read_to_string(dir.join("patch.txt"))?;
    
    // 执行 apply_patch（不断言退出码）
    Command::new(codex_utils_cargo_bin::cargo_bin("apply_patch")?)
        .arg(patch)
        .current_dir(tmp.path())
        .output()?;
    
    // 断言最终状态与 expected 一致
    let expected_dir = dir.join("expected");
    let expected_snapshot = snapshot_dir(&expected_dir)?;
    let actual_snapshot = snapshot_dir(tmp.path())?;
    assert_eq!(actual_snapshot, expected_snapshot, ...);
    
    Ok(())
}
```

### B.2 计算替换的核心逻辑 (lib.rs:386-474)
```rust
fn compute_replacements(
    original_lines: &[String],
    path: &Path,
    chunks: &[UpdateFileChunk],
) -> Result<Vec<(usize, usize, Vec<String>)>, ApplyPatchError> {
    // ... 省略上下文处理代码 ...
    
    for chunk in chunks {
        // 查找 old_lines
        let mut pattern: &[String] = &chunk.old_lines;
        let mut found = seek_sequence::seek_sequence(original_lines, pattern, line_index, chunk.is_end_of_file);
        
        // 尝试去除尾部空行重试
        if found.is_none() && pattern.last().is_some_and(String::is_empty) {
            pattern = &pattern[..pattern.len() - 1];
            found = seek_sequence::seek_sequence(original_lines, pattern, line_index, chunk.is_end_of_file);
        }
        
        match found {
            Some(start_idx) => {
                replacements.push((start_idx, pattern.len(), new_slice.to_vec()));
                line_index = start_idx + pattern.len();
            }
            None => {
                // 006场景触发此处
                return Err(ApplyPatchError::ComputeReplacements(format!(
                    "Failed to find expected lines in {}:\n{}",
                    path.display(),
                    chunk.old_lines.join("\n"),
                )));
            }
        }
    }
    
    Ok(replacements)
}
```

---

*文档生成时间: 2026-03-22*
*研究对象版本: codex-rs/apply-patch (最新主分支)*
