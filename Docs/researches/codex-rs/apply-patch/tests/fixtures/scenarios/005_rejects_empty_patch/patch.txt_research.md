# patch.txt 研究文档 - 005_rejects_empty_patch 场景

## 场景与职责

### 1.1 文件定位

| 属性 | 值 |
|------|-----|
| **文件路径** | `codex-rs/apply-patch/tests/fixtures/scenarios/005_rejects_empty_patch/patch.txt` |
| **所属模块** | `codex-apply-patch` crate |
| **测试类型** | Fixture-based 集成测试场景 |
| **场景编号** | 005 |
| **场景名称** | rejects_empty_patch（拒绝空补丁） |

### 1.2 场景目的

该场景用于验证 `apply_patch` 工具对**空补丁（Empty Patch）**的处理行为：

1. **语法层面**：补丁格式合法（包含 `*** Begin Patch` 和 `*** End Patch` 标记）
2. **语义层面**：补丁不包含任何文件操作（无 hunk）
3. **预期行为**：工具应拒绝执行并返回错误，而非静默成功

### 1.3 目录结构

```
005_rejects_empty_patch/
├── patch.txt          # 空补丁文件（本研究对象）
├── input/             # 测试前初始文件状态
│   └── foo.txt        # 内容为 "stable"
└── expected/          # 测试后预期文件状态
    └── foo.txt        # 内容仍为 "stable"（保持不变）
```

### 1.4 补丁内容

```
*** Begin Patch
*** End Patch
```

该补丁仅包含开始和结束标记，中间**无任何文件操作指令**。

---

## 功能点目的

### 2.1 核心功能

空补丁拒绝机制确保以下设计原则：

| 原则 | 说明 |
|------|------|
| **显式优于隐式** | 用户必须明确指定要修改的文件，而非依赖"无操作即成功" |
| **失败快速** | 尽早发现潜在的用户错误或 LLM 生成错误 |
| **状态一致性** | 确保文件系统状态与预期一致，避免"假阳性"成功 |

### 2.2 与相关场景的区别

| 场景 | 描述 | 错误类型 |
|------|------|----------|
| `005_rejects_empty_patch` | 补丁无任何 hunk | "No files were modified." |
| `008_rejects_empty_update_hunk` | Update hunk 无内容块 | "Update file hunk for path 'foo.txt' is empty" |

关键区别：
- `005`：解析成功（`hunks = []`），执行失败
- `008`：解析阶段即可能失败，或执行阶段失败

### 2.3 测试覆盖目标

1. **解析层**：验证 `parse_patch()` 能正确解析空 hunk 集合
2. **执行层**：验证 `apply_hunks_to_files()` 对空 hunk 集合返回错误
3. **CLI 层**：验证命令行工具返回非零退出码和正确错误信息
4. **状态层**：验证文件系统未被意外修改

---

## 具体技术实现

### 3.1 关键流程

```
┌─────────────────────────────────────────────────────────────────┐
│                        apply_patch 调用流程                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. CLI 入口 (standalone_executable.rs::run_main)                │
│     └── 读取 patch.txt 内容作为参数                               │
│                                                                 │
│  2. 解析阶段 (parser.rs::parse_patch)                            │
│     ├── 检查边界标记 (*** Begin/End Patch)                       │
│     ├── 解析 hunk 列表                                           │
│     │   └── 本场景: 无 hunk，返回 Vec::new()                     │
│     └── 返回 ApplyPatchArgs { hunks: [], ... }                  │
│                                                                 │
│  3. 执行阶段 (lib.rs::apply_patch -> apply_hunks)                │
│     └── 调用 apply_hunks_to_files(&[])                           │
│                                                                 │
│  4. 空 hunk 检查 (lib.rs::apply_hunks_to_files)                  │
│     ├── if hunks.is_empty()                                      │
│     │   └── anyhow::bail!("No files were modified.")            │
│     └── 返回错误，流程终止                                       │
│                                                                 │
│  5. 错误处理                                                     │
│     ├── stderr 输出: "No files were modified.\n"                │
│     └── 进程退出码: 1                                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 关键数据结构

#### 3.2.1 ApplyPatchArgs（解析结果）

```rust
// src/lib.rs
#[derive(Debug, PartialEq)]
pub struct ApplyPatchArgs {
    pub patch: String,           // 原始补丁文本
    pub hunks: Vec<Hunk>,        // 本场景: 空向量
    pub workdir: Option<String>, // 工作目录
}
```

#### 3.2.2 Hunk 枚举

```rust
// src/parser.rs
#[derive(Debug, PartialEq, Clone)]
pub enum Hunk {
    AddFile { path: PathBuf, contents: String },
    DeleteFile { path: PathBuf },
    UpdateFile { path: PathBuf, move_path: Option<PathBuf>, chunks: Vec<UpdateFileChunk> },
}
```

本场景：`hunks` 向量为空，不包含任何 Hunk 变体。

### 3.3 核心代码路径

#### 3.3.1 解析阶段代码

```rust
// src/parser.rs:106-113
pub fn parse_patch(patch: &str) -> Result<ApplyPatchArgs, ParseError> {
    let mode = if PARSE_IN_STRICT_MODE {
        ParseMode::Strict
    } else {
        ParseMode::Lenient
    };
    parse_patch_text(patch, mode)
}
```

```rust
// src/parser.rs:154-183
fn parse_patch_text(patch: &str, mode: ParseMode) -> Result<ApplyPatchArgs, ParseError> {
    let lines: Vec<&str> = patch.trim().lines().collect();
    let lines: &[&str] = match check_patch_boundaries_strict(&lines) {
        Ok(()) => &lines,
        Err(e) => match mode { /* ... */ },
    };

    let mut hunks: Vec<Hunk> = Vec::new();
    let last_line_index = lines.len().saturating_sub(1);
    let mut remaining_lines = &lines[1..last_line_index];  // 本场景: 空切片
    
    // 循环条件不满足，不执行任何解析
    while !remaining_lines.is_empty() {
        let (hunk, hunk_lines) = parse_one_hunk(remaining_lines, line_number)?;
        hunks.push(hunk);
        // ...
    }
    
    // 返回空 hunk 集合
    Ok(ApplyPatchArgs { hunks, patch, workdir: None })
}
```

#### 3.3.2 执行阶段代码

```rust
// src/lib.rs:279-282
fn apply_hunks_to_files(hunks: &[Hunk]) -> anyhow::Result<AffectedPaths> {
    if hunks.is_empty() {
        anyhow::bail!("No files were modified.");  // ← 本场景触发此处
    }
    // ... 正常处理逻辑
}
```

#### 3.3.3 错误传播路径

```rust
// src/lib.rs:183-213
pub fn apply_patch(
    patch: &str,
    stdout: &mut impl std::io::Write,
    stderr: &mut impl std::io::Write,
) -> Result<(), ApplyPatchError> {
    let hunks = match parse_patch(patch) {
        Ok(source) => source.hunks,  // 本场景: hunks = []
        Err(e) => { /* 错误处理 */ },
    };

    // 调用执行层
    match apply_hunks_to_files(hunks) {  // 返回 Err
        Ok(affected) => { /* 成功处理 */ },
        Err(err) => {
            let msg = err.to_string();  // "No files were modified."
            writeln!(stderr, "{msg}").map_err(ApplyPatchError::from)?;
            // 转换为 ApplyPatchError 并返回
        }
    }
}
```

#### 3.3.4 CLI 入口代码

```rust
// src/standalone_executable.rs:11-58
pub fn run_main() -> i32 {
    // ... 参数解析 ...
    
    match crate::apply_patch(&patch_arg, &mut stdout, &mut stderr) {
        Ok(()) => {
            let _ = stdout.flush();
            0  // 成功退出码
        }
        Err(_) => 1,  // 本场景: 返回 1（失败）
    }
}
```

### 3.4 解析器边界检查

```rust
// src/parser.rs:187-194
fn check_patch_boundaries_strict(lines: &[&str]) -> Result<(), ParseError> {
    let (first_line, last_line) = match lines {
        [] => (None, None),
        [first] => (Some(first), Some(first)),
        [first, .., last] => (Some(first), Some(last)),
    };
    check_start_and_end_lines_strict(first_line, last_line)
}
```

本场景输入 `"*** Begin Patch\n*** End Patch"`：
- `lines = ["*** Begin Patch", "*** End Patch"]`
- `first_line = Some("*** Begin Patch")`
- `last_line = Some("*** End Patch")`
- 边界检查通过

---

## 关键代码路径与文件引用

### 4.1 完整调用链

```
tests/suite/scenarios.rs::run_apply_patch_scenario
    └── Command::new("apply_patch")
            .arg(patch)  // "*** Begin Patch\n*** End Patch"
            .output()
        
        src/standalone_executable.rs::run_main
            └── crate::apply_patch(&patch_arg, ...)
                
                src/lib.rs::apply_patch
                    ├── src/parser.rs::parse_patch
                    │   └── src/parser.rs::parse_patch_text
                    │       ├── src/parser.rs::check_patch_boundaries_strict ✓
                    │       └── 返回 ApplyPatchArgs { hunks: [], ... }
                    │
                    └── src/lib.rs::apply_hunks
                        └── src/lib.rs::apply_hunks_to_files
                            └── if hunks.is_empty() 
                                └── bail!("No files were modified.") ✗
```

### 4.2 相关测试代码

#### 4.2.1 Fixture 测试框架

```rust
// tests/suite/scenarios.rs:30-63
fn run_apply_patch_scenario(dir: &Path) -> anyhow::Result<()> {
    let tmp = tempdir()?;

    // 复制 input 到临时目录
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

    // 比较最终状态与 expected
    let expected_dir = dir.join("expected");
    let expected_snapshot = snapshot_dir(&expected_dir)?;
    let actual_snapshot = snapshot_dir(tmp.path())?;
    assert_eq!(actual_snapshot, expected_snapshot);
    
    Ok(())
}
```

#### 4.2.2 显式 CLI 测试

```rust
// tests/suite/tool.rs:85-95
#[test]
fn test_apply_patch_cli_rejects_empty_patch() -> anyhow::Result<()> {
    let tmp = tempdir()?;

    apply_patch_command(tmp.path())?
        .arg("*** Begin Patch\n*** End Patch")
        .assert()
        .failure()                           // 期望失败
        .stderr("No files were modified.\n"); // 期望错误信息

    Ok(())
}
```

### 4.3 关键文件清单

| 文件 | 职责 | 相关行号 |
|------|------|----------|
| `patch.txt` | 测试数据（空补丁） | 1-2 |
| `input/foo.txt` | 初始文件状态 | - |
| `expected/foo.txt` | 预期最终状态 | - |
| `src/lib.rs` | 核心应用逻辑，空补丁检测 | 279-282 |
| `src/parser.rs` | 补丁解析器 | 106-183 |
| `src/standalone_executable.rs` | CLI 入口 | 11-58 |
| `tests/suite/scenarios.rs` | Fixture 测试框架 | 30-63 |
| `tests/suite/tool.rs` | 显式 CLI 测试 | 85-95 |

---

## 依赖与外部交互

### 5.1 内部依赖

```
codex-apply-patch/
├── src/lib.rs
│   ├── src/parser.rs        # Hunk 解析
│   ├── src/invocation.rs    # Shell 脚本解析（本场景未使用）
│   ├── src/seek_sequence.rs # 上下文匹配（本场景未使用）
│   └── src/standalone_executable.rs  # CLI 入口
```

### 5.2 外部 crate 依赖

| Crate | 用途 | 本场景使用 |
|-------|------|-----------|
| `anyhow` | 错误处理 | ✓ `anyhow::bail!` |
| `thiserror` | 错误定义 | - |
| `similar` | 文本差异计算 | - |
| `tree-sitter` | Bash 脚本解析 | - |
| `tree-sitter-bash` | Bash 语法支持 | - |

### 5.3 测试依赖

| Crate | 用途 |
|-------|------|
| `assert_cmd` | CLI 测试断言 |
| `tempfile` | 临时目录创建 |
| `pretty_assertions` | 差异对比输出 |
| `codex-utils-cargo-bin` | 二进制路径解析 |

### 5.4 系统交互

```
┌────────────────────────────────────────┐
│           系统交互图                   │
├────────────────────────────────────────┤
│                                        │
│  输入                                  │
│  ├── 命令行参数: patch 文本            │
│  └── 工作目录: input/ 内容             │
│                                        │
│  输出                                  │
│  ├── stdout: 空（无成功输出）          │
│  ├── stderr: "No files were modified.\n" │
│  └── 退出码: 1（失败）                 │
│                                        │
│  文件系统                              │
│  ├── 读取: input/foo.txt               │
│  └── 写入: 无（保持原状）              │
│                                        │
└────────────────────────────────────────┘
```

---

## 风险、边界与改进建议

### 6.1 当前风险

| 风险点 | 描述 | 严重程度 |
|--------|------|----------|
| **错误信息模糊** | "No files were modified" 不区分"空补丁"和"补丁执行后无变化" | 低 |
| **静默失败可能** | 如果未来修改逻辑，可能导致空补丁被错误接受 | 中 |
| **测试覆盖重叠** | Fixture 测试和 tool 测试重复验证同一行为 | 低 |

### 6.2 边界情况

| 边界情况 | 当前行为 | 说明 |
|----------|----------|------|
| 仅空白字符的补丁 | 解析失败 | `trim()` 后可能无边界标记 |
| 带注释的空补丁 | 不支持 | 补丁格式无注释语法 |
| 大小写变体 | 解析失败 | 标记必须完全匹配 |
| 多余空行 | 解析成功 | `parse_patch_text` 会跳过 |

### 6.3 改进建议

#### 6.3.1 错误信息优化

```rust
// 当前实现
anyhow::bail!("No files were modified.");

// 建议改进
if hunks.is_empty() {
    anyhow::bail!("No files were modified: the patch contains no file operations.");
}
```

#### 6.3.2 添加警告模式

对于某些使用场景，空补丁可能是合法的"检查"操作：

```rust
pub enum EmptyPatchBehavior {
    Reject,   // 当前行为
    Warn,     // 警告但返回成功
    Allow,    // 静默允许
}
```

#### 6.3.3 增强测试覆盖

建议添加以下边界测试：

```rust
// 测试：带空白字符的空补丁
#[test]
fn test_rejects_whitespace_only_patch() {
    // "*** Begin Patch\n   \n*** End Patch"
}

// 测试：空补丁不修改文件时间戳
#[test]
fn test_empty_patch_preserves_mtime() {
    // 验证文件修改时间未被更新
}
```

#### 6.3.4 解析时提前检测

当前在**执行阶段**检测空 hunk，可考虑在**解析阶段**增加警告：

```rust
// src/parser.rs
if hunks.is_empty() {
    eprintln!("Warning: Patch contains no file operations");
}
```

### 6.4 与其他组件的协调

| 组件 | 协调建议 |
|------|----------|
| LLM 生成层 | 在生成补丁时过滤空操作，减少无效调用 |
| CLI 工具 | 添加 `--allow-empty` 标志用于特殊场景 |
| 日志系统 | 记录空补丁尝试，用于调试和监控 |

---

## 附录

### A. 相关测试场景对比

| 场景编号 | 名称 | 补丁特征 | 预期结果 |
|----------|------|----------|----------|
| 001 | add_file | 包含 AddFile hunk | 成功，文件创建 |
| 005 | rejects_empty_patch | 无 hunk | 失败，"No files were modified" |
| 008 | rejects_empty_update_hunk | Update hunk 无 chunks | 失败，"Update file hunk for path 'foo.txt' is empty" |
| 013 | rejects_invalid_hunk_header | 无效 hunk 头 | 失败，无效 hunk 头错误 |

### B. 错误代码映射

| 错误信息 | 来源 | 退出码 |
|----------|------|--------|
| "No files were modified." | `lib.rs:281` | 1 |
| "Invalid patch: ..." | `parser.rs` | 1 |
| "Invalid patch hunk on line X: ..." | `parser.rs` | 1 |

### C. 参考文档

- `apply_patch_tool_instructions.md`: LLM 使用说明
- `AGENTS.md`: 项目编码规范
- `codex-rs/tui/styles.md`: TUI 样式规范（如适用）
