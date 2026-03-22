# 研究文档: `005_rejects_empty_patch/expected/foo.txt`

## 文件基本信息

| 属性 | 值 |
|------|-----|
| **文件路径** | `codex-rs/apply-patch/tests/fixtures/scenarios/005_rejects_empty_patch/expected/foo.txt` |
| **文件内容** | `stable` |
| **所属测试场景** | 005_rejects_empty_patch |
| **测试类型** | 端到端场景测试 |

---

## 1. 场景与职责

### 1.1 测试场景概述

`005_rejects_empty_patch` 是 `apply-patch` 工具的端到端测试场景之一，用于验证**空补丁拒绝机制**。该测试确保当提供一个格式正确但不含任何文件操作（hunks）的补丁时，工具会正确拒绝应用该补丁，并保持文件系统状态不变。

### 1.2 场景目录结构

```
005_rejects_empty_patch/
├── input/
│   └── foo.txt          # 输入文件，内容为 "stable"
├── expected/
│   └── foo.txt          # 预期输出文件，内容仍为 "stable"
└── patch.txt            # 空补丁内容
```

### 1.3 核心职责

- **验证空补丁拒绝**: 确保 `*** Begin Patch` 和 `*** End Patch` 之间没有有效 hunk 时，补丁应用失败
- **验证文件系统不变性**: 确认空补丁失败后，原始文件保持不变
- **作为回归测试**: 防止未来代码改动意外允许空补丁通过

---

## 2. 功能点目的

### 2.1 空补丁定义

在本场景中，"空补丁"指：

```
*** Begin Patch
*** End Patch
```

这是一个格式上有效的补丁（有正确的开始和结束标记），但**不包含任何文件操作 hunk**（没有 `*** Add File:`、`*** Delete File:` 或 `*** Update File:` 指令）。

### 2.2 预期行为

| 方面 | 预期结果 |
|------|----------|
| **退出状态码** | 非零（失败） |
| **标准错误输出** | `No files were modified.` |
| **文件系统状态** | 与输入状态完全一致，无任何变更 |
| **foo.txt 内容** | 保持为 `stable` |

### 2.3 为什么拒绝空补丁很重要

1. **防止无意义操作**: 空补丁不会做任何有用工作，应用它是浪费计算资源
2. **早期错误检测**: 空补丁通常是 LLM 生成错误或用户输入错误的信号，应尽早失败以便排查
3. **保持语义清晰**: 明确区分"无操作补丁"和"操作执行失败"两种情况
4. **安全性**: 防止潜在的边界条件漏洞（如空补丁意外覆盖文件）

---

## 3. 具体技术实现

### 3.1 关键流程

#### 3.1.1 补丁解析流程

```
patch.txt
    ↓
parse_patch() [parser.rs:106]
    ↓
check_patch_boundaries_strict() [parser.rs:187]
    ↓
解析成功，返回 ApplyPatchArgs { hunks: [] }
```

尽管补丁被成功解析（因为格式正确），但返回的 `hunks` 向量是空的。

#### 3.1.2 空补丁检测与拒绝流程

```
apply_patch() [lib.rs:183]
    ↓
parse_patch() → 成功，hunks = []
    ↓
apply_hunks(&hunks, stdout, stderr) [lib.rs:216]
    ↓
apply_hunks_to_files(hunks) [lib.rs:279]
    ↓
if hunks.is_empty() { anyhow::bail!("No files were modified.") }
    ↓
返回错误，退出码 1
```

### 3.2 关键数据结构

#### 3.2.1 ApplyPatchArgs

```rust
// lib.rs:87-93
pub struct ApplyPatchArgs {
    pub patch: String,
    pub hunks: Vec<Hunk>,   // <-- 空补丁时此向量为空
    pub workdir: Option<String>,
}
```

#### 3.2.2 Hunk 枚举

```rust
// parser.rs:58-76
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

### 3.3 核心拒绝逻辑代码

```rust
// lib.rs:279-282
fn apply_hunks_to_files(hunks: &[Hunk]) -> anyhow::Result<AffectedPaths> {
    if hunks.is_empty() {
        anyhow::bail!("No files were modified.");
    }
    // ... 正常处理逻辑
}
```

### 3.4 测试执行机制

#### 3.4.1 场景测试框架

```rust
// tests/suite/scenarios.rs:30-63
fn run_apply_patch_scenario(dir: &Path) -> anyhow::Result<()> {
    let tmp = tempdir()?;
    
    // 1. 复制 input/ 到临时目录
    let input_dir = dir.join("input");
    copy_dir_recursive(&input_dir, tmp.path())?;
    
    // 2. 读取 patch.txt
    let patch = fs::read_to_string(dir.join("patch.txt"))?;
    
    // 3. 执行 apply_patch（不检查退出码）
    Command::new(cargo_bin("apply_patch")?)
        .arg(patch)
        .current_dir(tmp.path())
        .output()?;
    
    // 4. 比较实际结果与 expected/ 目录
    let expected_snapshot = snapshot_dir(&dir.join("expected"))?;
    let actual_snapshot = snapshot_dir(tmp.path())?;
    assert_eq!(actual_snapshot, expected_snapshot);
    
    Ok(())
}
```

#### 3.4.2 测试断言策略

本场景采用**状态对比**而非**退出码检查**：
- 不验证退出码（注释说明："the scenarios are specified purely in terms of final filesystem state"）
- 通过比较 `expected/foo.txt` 和实际生成的 `foo.txt` 内容来验证行为
- 由于 `input/foo.txt` 和 `expected/foo.txt` 内容相同（都是 `stable`），验证空补丁未改变文件

---

## 4. 关键代码路径与文件引用

### 4.1 完整调用链

```
测试执行
├── tests/suite/scenarios.rs
│   └── test_apply_patch_scenarios() [line 11]
│       └── run_apply_patch_scenario()
│           └── 执行 apply_patch 二进制
│
apply_patch 二进制
├── src/main.rs
│   └── main()
│       └── codex_apply_patch::main()
│
├── src/standalone_executable.rs
│   └── run_main() [line 11]
│       └── crate::apply_patch() [line 51]
│
└── src/lib.rs
    └── apply_patch() [line 183]
        ├── parse_patch() [line 188] → parser.rs
        └── apply_hunks() [line 210]
            └── apply_hunks_to_files() [line 279]
                └── if hunks.is_empty() { bail!(...) } [line 280-281]
```

### 4.2 相关文件清单

| 文件 | 职责 |
|------|------|
| `codex-rs/apply-patch/tests/fixtures/scenarios/005_rejects_empty_patch/patch.txt` | 空补丁输入 |
| `codex-rs/apply-patch/tests/fixtures/scenarios/005_rejects_empty_patch/input/foo.txt` | 测试前文件状态 |
| `codex-rs/apply-patch/tests/fixtures/scenarios/005_rejects_empty_patch/expected/foo.txt` | 测试后预期文件状态 |
| `codex-rs/apply-patch/tests/suite/scenarios.rs` | 场景测试框架 |
| `codex-rs/apply-patch/tests/suite/tool.rs` | 对应的显式测试用例 `test_apply_patch_cli_rejects_empty_patch` |
| `codex-rs/apply-patch/src/lib.rs` | 核心补丁应用逻辑，包含空补丁检测 |
| `codex-rs/apply-patch/src/parser.rs` | 补丁解析器 |
| `codex-rs/apply-patch/src/standalone_executable.rs` | CLI 入口 |

### 4.3 相关测试用例

```rust
// tests/suite/tool.rs:85-95
#[test]
fn test_apply_patch_cli_rejects_empty_patch() -> anyhow::Result<()> {
    let tmp = tempdir()?;

    apply_patch_command(tmp.path())?
        .arg("*** Begin Patch\n*** End Patch")
        .assert()
        .failure()
        .stderr("No files were modified.\n");

    Ok(())
}
```

此显式测试与场景测试 `005_rejects_empty_patch` 形成互补：
- **场景测试**: 验证文件系统状态不变
- **显式测试**: 验证错误消息输出

---

## 5. 依赖与外部交互

### 5.1 内部依赖

```
codex-apply-patch
├── lib.rs (核心逻辑)
├── parser.rs (补丁解析)
├── invocation.rs (命令行解析)
├── standalone_executable.rs (CLI)
└── seek_sequence.rs (文本匹配)
```

### 5.2 外部依赖

| 依赖 | 用途 |
|------|------|
| `anyhow` | 错误处理 |
| `similar` | 统一差异（unified diff）生成 |
| `thiserror` | 错误类型定义 |
| `tree-sitter` | Bash 脚本解析（用于 heredoc 提取） |
| `tree-sitter-bash` | Bash 语法支持 |

### 5.3 测试依赖

| 依赖 | 用途 |
|------|------|
| `assert_cmd` | CLI 测试辅助 |
| `assert_matches` | 模式匹配断言 |
| `codex-utils-cargo-bin` | 二进制路径解析 |
| `pretty_assertions` | 美观的差异输出 |
| `tempfile` | 临时目录管理 |

### 5.4 与 Codex 生态系统的交互

```
┌─────────────────┐
│   Codex CLI/TUI  │
│   (codex-cli)    │
└────────┬────────┘
         │ 调用 apply_patch 工具
         ▼
┌─────────────────┐
│ codex-apply-patch │
│   (本 crate)     │
└────────┬────────┘
         │ 直接文件系统操作
         ▼
┌─────────────────┐
│   文件系统       │
│   (目标代码库)   │
└─────────────────┘
```

`apply-patch` 是一个独立的可执行工具，既可被 Codex 核心调用，也可作为独立 CLI 使用。

---

## 6. 风险、边界与改进建议

### 6.1 当前风险

#### 6.1.1 测试覆盖风险

| 风险 | 描述 | 严重程度 |
|------|------|----------|
| 仅验证内容不变 | 测试只比较文件内容，不验证文件元数据（权限、时间戳） | 低 |
| 单文件场景 | 仅测试单个文件，未测试多文件目录结构 | 低 |
| 无退出码验证 | 场景测试不验证退出码，依赖显式测试补充 | 中 |

#### 6.1.2 边界情况

```rust
// 以下情况当前行为需要明确：

// 1. 只有空白行的补丁（是否算空？）
"*** Begin Patch\n\n*** End Patch"

// 2. 有无效 hunk 头的补丁
"*** Begin Patch\n*** Invalid Header\n*** End Patch"

// 3. 有注释的补丁（如果支持）
"*** Begin Patch\n# comment\n*** End Patch"
```

### 6.2 边界条件分析

#### 6.2.1 空补丁 vs 无效补丁

| 场景 | 补丁内容 | 当前行为 |
|------|----------|----------|
| 纯空补丁 | `*** Begin Patch\n*** End Patch` | 拒绝，`No files were modified.` |
| 空 Update hunk | `*** Begin Patch\n*** Update File: foo\n*** End Patch` | 解析错误，`Update file hunk for path 'foo' is empty` |
| 无效 hunk 头 | `*** Begin Patch\n*** Foo: bar\n*** End Patch` | 解析错误，`'*** Foo: bar' is not a valid hunk header` |

#### 6.2.2 错误消息一致性

当前空补丁错误消息 `No files were modified.` 与空 Update hunk 错误消息 `Update file hunk for path 'foo' is empty` 不一致：
- 前者是运行时错误（`apply_hunks_to_files`）
- 后者是解析时错误（`parse_one_hunk`）

### 6.3 改进建议

#### 6.3.1 测试增强

```rust
// 建议添加的测试场景

// 1. 验证退出码的场景测试变体
#[test]
fn test_apply_patch_scenarios_with_exit_code() { ... }

// 2. 多文件空补丁测试
// input/: foo.txt, bar.txt
// patch.txt: 空补丁
// expected/: foo.txt, bar.txt 均保持不变

// 3. 嵌套目录空补丁测试
// input/: dir/nested/file.txt
// patch.txt: 空补丁
// expected/: dir/nested/file.txt 保持不变
```

#### 6.3.2 错误消息改进

```rust
// 当前实现 (lib.rs:280-281)
if hunks.is_empty() {
    anyhow::bail!("No files were modified.");
}

// 建议改进：更详细的错误信息
if hunks.is_empty() {
    anyhow::bail!(
        "Empty patch: no file operations found between '{}' and '{}'.",
        BEGIN_PATCH_MARKER, END_PATCH_MARKER
    );
}
```

#### 6.3.3 早期验证

```rust
// 当前：解析成功后才在 apply 阶段拒绝
// 建议：在解析阶段就检测并拒绝空补丁

// parser.rs:parse_patch_text() 中添加
if hunks.is_empty() {
    return Err(InvalidPatchError(
        "Patch contains no file operations.".to_string()
    ));
}
```

**权衡**: 早期验证会改变错误类型（从 `IoError` 变为 `ParseError`），可能影响依赖此行为的调用方。

#### 6.3.4 文档改进

```markdown
<!-- 建议在 apply_patch_tool_instructions.md 中添加 -->

## 空补丁

空补丁（即 `*** Begin Patch` 和 `*** End Patch` 之间没有任何文件操作）
会被拒绝并返回错误。每个补丁必须包含至少一个有效的文件操作
（Add File、Delete File 或 Update File）。
```

### 6.4 相关安全考虑

1. **拒绝服务**: 空补丁不会导致 DoS，但大量空补丁调用可能浪费资源
2. **信息泄露**: 错误消息 `No files were modified.` 不泄露文件系统信息
3. **竞态条件**: 空补丁不涉及文件写入，无竞态风险

---

## 7. 总结

`005_rejects_empty_patch/expected/foo.txt` 是一个简单但重要的测试固件，其内容为 `stable`。它与 `input/foo.txt` 内容相同，共同验证以下行为：

1. **输入**: 包含 `stable` 内容的文件
2. **操作**: 应用空补丁（被预期拒绝）
3. **输出**: 文件内容保持 `stable` 不变

该测试场景是 `apply-patch` 工具健壮性测试套件的一部分，确保工具在面对无效输入时表现可预测且安全。
