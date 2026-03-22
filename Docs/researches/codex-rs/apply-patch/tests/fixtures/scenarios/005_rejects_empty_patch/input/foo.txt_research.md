# 005_rejects_empty_patch/input/foo.txt 研究文档

## 场景与职责

### 文件定位
- **目标文件**: `codex-rs/apply-patch/tests/fixtures/scenarios/005_rejects_empty_patch/input/foo.txt`
- **文件内容**: 单行文本 `"stable"`
- **所属场景**: 005_rejects_empty_patch（拒绝空补丁测试场景）

### 测试场景目的
该测试场景用于验证 `apply_patch` 工具在遇到**空补丁**（即不包含任何文件操作指令的补丁）时的正确行为：
1. **输入文件** (`input/foo.txt`): 一个已存在的文件，内容为 `"stable"`
2. **补丁文件** (`patch.txt`): 仅包含补丁边界标记，无实际文件操作
3. **预期输出** (`expected/foo.txt`): 文件内容保持不变，仍为 `"stable"`

### 场景目录结构
```
005_rejects_empty_patch/
├── input/
│   └── foo.txt          # 测试前文件状态（本研究对象）
├── patch.txt            # 空补丁
└── expected/
    └── foo.txt          # 测试后预期文件状态
```

---

## 功能点目的

### 空补丁拒绝机制
该测试验证以下核心功能点：

1. **空补丁检测**: 当补丁只包含 `*** Begin Patch` 和 `*** End Patch` 标记，但中间没有任何 `Add File`/`Delete File`/`Update File` 指令时，系统应正确识别并拒绝应用。

2. **错误报告**: 系统应向 stderr 输出 `"No files were modified."` 错误信息，并返回非零退出码。

3. **文件完整性保护**: 空补丁被拒绝后，所有现有文件应保持原状，不受任何修改。

### 与其他场景的对比

| 场景 | 补丁内容 | 预期行为 |
|------|----------|----------|
| 001_add_file | 包含 `*** Add File` | 成功创建新文件 |
| 005_rejects_empty_patch | 仅边界标记，无操作 | 拒绝并报告错误 |
| 008_rejects_empty_update_hunk | 包含 `*** Update File` 但无变更块 | 拒绝并报告错误（解析阶段） |

---

## 具体技术实现

### 1. 补丁解析流程

#### 1.1 解析入口
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

#### 1.2 边界检查
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

#### 1.3 关键：空补丁的解析结果
根据 `parser.rs` 第 484-490 行的测试用例：
```rust
assert_eq!(
    parse_patch_text(
        "*** Begin Patch\n\
         *** End Patch",
        ParseMode::Strict
    )
    .unwrap()
    .hunks,
    Vec::new()  // 返回空 Vec，解析成功但无 hunk
);
```

**重要发现**: 空补丁在**解析阶段是成功的**，返回 `hunks: Vec::new()`（空向量），而不是解析错误。

### 2. 空补丁拒绝机制（应用阶段）

空补丁的拒绝发生在**应用阶段**，而非解析阶段：

```rust
// src/lib.rs:279-282
fn apply_hunks_to_files(hunks: &[Hunk]) -> anyhow::Result<AffectedPaths> {
    if hunks.is_empty() {
        anyhow::bail!("No files were modified.");
    }
    // ... 继续处理
}
```

#### 调用链
```
apply_patch() -> apply_hunks() -> apply_hunks_to_files()
                              -> 检查 hunks.is_empty()
                              -> 返回错误 "No files were modified."
```

### 3. 错误处理流程

```rust
// src/lib.rs:248-265
match apply_hunks_to_files(hunks) {
    Ok(affected) => {
        print_summary(&affected, stdout).map_err(ApplyPatchError::from)?;
        Ok(())
    }
    Err(err) => {
        let msg = err.to_string();
        writeln!(stderr, "{msg}").map_err(ApplyPatchError::from)?;
        // 转换为 ApplyPatchError::IoError 并返回
        Err(ApplyPatchError::IoError(IoError {
            context: msg,
            source: std::io::Error::other(err),
        }))
    }
}
```

### 4. 数据结构

#### 4.1 Hunk 枚举
```rust
// src/parser.rs:58-76
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

#### 4.2 ApplyPatchArgs
```rust
// src/lib.rs:87-92
pub struct ApplyPatchArgs {
    pub patch: String,
    pub hunks: Vec<Hunk>,  // 空补丁时此向量为空
    pub workdir: Option<String>,
}
```

### 5. 测试执行流程

#### 5.1 场景测试框架
```rust
// tests/suite/scenarios.rs:30-63
fn run_apply_patch_scenario(dir: &Path) -> anyhow::Result<()> {
    let tmp = tempdir()?;
    
    // 1. 复制输入文件到临时目录
    let input_dir = dir.join("input");
    if input_dir.is_dir() {
        copy_dir_recursive(&input_dir, tmp.path())?;
    }
    
    // 2. 读取补丁
    let patch = fs::read_to_string(dir.join("patch.txt"))?;
    
    // 3. 执行 apply_patch（不检查退出码）
    Command::new(codex_utils_cargo_bin::cargo_bin("apply_patch")?)
        .arg(patch)
        .current_dir(tmp.path())
        .output()?;
    
    // 4. 比较最终状态与预期状态
    let expected_dir = dir.join("expected");
    let expected_snapshot = snapshot_dir(&expected_dir)?;
    let actual_snapshot = snapshot_dir(tmp.path())?;
    assert_eq!(actual_snapshot, expected_snapshot, ...);
    
    Ok(())
}
```

#### 5.2 本场景的特殊性
由于 `run_apply_patch_scenario` **不检查退出码**，只比较最终文件系统状态，因此：
- 即使 `apply_patch` 返回非零退出码，只要文件状态符合预期，测试就通过
- `005_rejects_empty_patch` 的 `expected/foo.txt` 与 `input/foo.txt` 内容相同（都是 `"stable"`），验证了"空补丁不修改文件"的行为

### 6. 独立测试验证

在 `tests/suite/tool.rs` 中有专门针对空补丁的 CLI 测试：

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

---

## 关键代码路径与文件引用

### 核心文件
| 文件 | 职责 |
|------|------|
| `src/parser.rs` | 补丁解析，空补丁返回 `hunks: []` |
| `src/lib.rs:279-282` | `apply_hunks_to_files()` 空 hunk 检查 |
| `src/lib.rs:248-265` | 错误处理与 stderr 输出 |
| `src/standalone_executable.rs:51-58` | CLI 入口，返回退出码 |
| `tests/suite/scenarios.rs` | 场景测试框架 |
| `tests/suite/tool.rs:85-95` | 空补丁 CLI 测试 |

### 关键代码位置
```
codex-rs/apply-patch/
├── src/
│   ├── lib.rs              # 核心逻辑：apply_hunks_to_files() 第279行空检查
│   ├── parser.rs           # parse_patch() 第106行，解析返回空 hunks
│   └── standalone_executable.rs  # main() 入口
└── tests/
    ├── suite/
    │   ├── scenarios.rs    # 场景测试执行器
    │   └── tool.rs         # CLI 测试（含空补丁测试）
    └── fixtures/
        └── scenarios/
            └── 005_rejects_empty_patch/
                ├── input/foo.txt     # 本研究对象
                ├── patch.txt         # 空补丁
                └── expected/foo.txt  # 预期输出
```

### 执行流程图
```
┌─────────────────┐
│  patch.txt      │  "*** Begin Patch\n*** End Patch"
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  parse_patch()  │  解析成功，返回 hunks = []
│  (parser.rs)    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ apply_hunks()   │
│   (lib.rs:216)  │
└────────┬────────┘
         │
         ▼
┌───────────────────────┐
│ apply_hunks_to_files()│  检查 hunks.is_empty()
│     (lib.rs:279)      │  是 → bail!("No files were modified.")
└────────┬──────────────┘
         │
         ▼
┌─────────────────┐
│   错误处理       │  写入 stderr: "No files were modified.\n"
│  (lib.rs:253)   │  返回 ApplyPatchError::IoError
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  退出码 1       │  (standalone_executable.rs:57)
└─────────────────┘
```

---

## 依赖与外部交互

### 1. 内部依赖

| 模块 | 用途 |
|------|------|
| `parser` | 解析补丁文本为 Hunk 结构 |
| `invocation` | 处理 shell 脚本形式的调用 |
| `standalone_executable` | CLI 入口点 |
| `seek_sequence` | 文件内容匹配算法 |

### 2. 外部依赖（Cargo.toml）

```toml
[dependencies]
anyhow = "..."           # 错误处理
similar = "..."          # 文本差异计算（unified diff）
thiserror = "..."        # 错误类型定义
tree-sitter = "..."      # Bash 脚本解析
tree-sitter-bash = "..." # Bash 语法支持
```

### 3. 测试依赖

```toml
[dev-dependencies]
assert_cmd = "..."       # CLI 测试断言
codex-utils-cargo-bin = "..."  # 二进制文件定位
pretty_assertions = "..."      # 美观的差异输出
tempfile = "..."         # 临时目录管理
```

### 4. 与测试框架的交互

```rust
// tests/all.rs
mod suite;  // 聚合所有测试模块

// tests/suite/mod.rs
pub mod cli;
pub mod scenarios;
pub mod tool;
```

---

## 风险、边界与改进建议

### 1. 当前实现的风险

#### 1.1 错误分类问题
```rust
// 当前实现将空补丁错误归类为 IoError
Err(ApplyPatchError::IoError(IoError {
    context: msg,
    source: std::io::Error::other(err),
}))
```
**问题**: "No files were modified" 是业务逻辑错误，不是 I/O 错误。这种分类可能导致：
- 调用方难以区分真正的 I/O 错误和空补丁错误
- 错误处理逻辑需要依赖字符串匹配

#### 1.2 场景测试不检查退出码
```rust
// scenarios.rs:45-48
Command::new(...)
    .arg(patch)
    .current_dir(tmp.path())
    .output()?;  // 不检查 exit status
```
**风险**: 如果空补丁意外成功（比如未来修改引入了 bug），场景测试无法发现，因为只比较文件状态。

### 2. 边界情况

| 边界情况 | 当前行为 | 说明 |
|----------|----------|------|
| 纯空白字符补丁 | 解析错误 | `trim()` 后可能只剩边界标记 |
| 仅含注释的补丁 | 解析错误 | 不支持注释语法 |
| 空 Update hunk | 解析错误 | `008_rejects_empty_update_hunk` 场景 |
| 多个空行补丁 | 解析成功，应用失败 | 空 hunk 检查触发 |

### 3. 改进建议

#### 3.1 添加专门的错误类型
```rust
// 建议添加
#[derive(Debug, Error, PartialEq)]
pub enum ApplyPatchError {
    // ... 现有错误类型
    
    #[error("No files were modified.")]
    EmptyPatch,  // 专门用于空补丁错误
}
```

#### 3.2 场景测试增强
```rust
// 建议修改 scenarios.rs
let output = Command::new(...).output()?;
// 对于预期失败的场景，检查退出码
if should_fail(&scenario_name) {
    assert!(!output.status.success());
}
```

#### 3.3 早期验证
可以在解析阶段就检测空补丁，提前返回更友好的错误：
```rust
// 在 parse_patch_text 中添加
if hunks.is_empty() {
    return Err(ParseError::InvalidPatchError(
        "Patch contains no file operations".to_string()
    ));
}
```

### 4. 相关测试覆盖

确保以下测试用例覆盖空补丁场景：

1. **单元测试**: `parser.rs` 中已验证空补丁解析返回空 `hunks`
2. **集成测试**: `tool.rs:85-95` 验证 CLI 行为和错误输出
3. **场景测试**: `005_rejects_empty_patch` 验证文件系统无副作用

### 5. 文档一致性

`apply_patch_tool_instructions.md` 中应明确说明：
- 补丁必须包含至少一个文件操作
- 空补丁将被拒绝并返回错误

---

## 总结

`005_rejects_empty_patch/input/foo.txt` 是一个简单的测试夹具文件，内容为 `"stable"`，用于验证 `apply_patch` 工具对空补丁的正确处理。该场景的核心机制是：

1. **解析阶段**: 空补丁被成功解析，返回空的 `hunks` 向量
2. **应用阶段**: `apply_hunks_to_files()` 检测到空 `hunks`，返回 `"No files were modified."` 错误
3. **结果验证**: 输入文件保持 `"stable"` 不变，与预期输出一致

这种两阶段处理（解析成功、应用失败）的设计允许：
- 解析器保持简单，只负责语法验证
- 应用层负责语义验证（是否有实际操作）
- 清晰的错误报告给最终用户
