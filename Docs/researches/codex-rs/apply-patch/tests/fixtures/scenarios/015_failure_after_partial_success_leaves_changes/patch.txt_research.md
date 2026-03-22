# 研究文档：015_failure_after_partial_success_leaves_changes/patch.txt

## 场景与职责

### 文件位置
- **目标文件**: `codex-rs/apply-patch/tests/fixtures/scenarios/015_failure_after_partial_success_leaves_changes/patch.txt`
- **期望输出目录**: `codex-rs/apply-patch/tests/fixtures/scenarios/015_failure_after_partial_success_leaves_changes/expected/`
- **相关测试代码**: `codex-rs/apply-patch/tests/suite/tool.rs` (行243-257)

### 测试场景描述

该测试场景验证 **"部分成功后的失败保留已应用的变更"** 这一核心行为。具体来说：

1. **场景名称**: `015_failure_after_partial_success_leaves_changes`
2. **测试目的**: 验证当 patch 包含多个操作时，如果前面的操作成功但后续操作失败，前面成功的操作应该被保留，而不是被回滚。
3. **业务语义**: 这是一个关于**原子性 vs 部分应用**的设计决策测试。`apply_patch` 工具选择**不保证原子性**，而是采用"尽力而为"的策略，允许部分成功。

### 输入/输出规格

**Patch 内容**:
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

**执行流程**:
1. 第一个操作 (`Add File: created.txt`) 应该成功创建文件
2. 第二个操作 (`Update File: missing.txt`) 应该失败，因为 `missing.txt` 不存在
3. 最终状态：`created.txt` 应该保留（内容为 "hello\n"）

**期望输出** (`expected/created.txt`):
```
hello
```

---

## 功能点目的

### 1. 部分应用语义 (Partial Application Semantics)

该测试验证的核心设计决策是：**apply_patch 不实现事务性回滚**。这与传统的 patch 工具（如 `git apply`）不同，后者通常要求全部成功或全部失败。

**设计理由**:
- **实用性优先**: 在 AI 辅助编程场景中，部分成功比完全失败更有价值
- **用户可恢复性**: 用户可以基于已应用的部分继续工作
- **简化实现**: 避免复杂的事务管理逻辑

### 2. 错误隔离 (Error Isolation)

每个 hunk（文件操作单元）独立执行，错误不会传播影响已完成的操作。

### 3. 与相关测试的对比

| 场景 | 描述 | 与 015 的关系 |
|------|------|--------------|
| `009_requires_existing_file_for_update` | 验证更新不存在文件会失败 | 015 的第二个操作基于此场景 |
| `001_add_file` | 验证添加文件成功 | 015 的第一个操作基于此场景 |
| `014_update_file_appends_trailing_newline` | 验证更新时自动添加换行符 | 展示 UpdateFile 的其他行为 |

---

## 具体技术实现

### 关键流程

#### 1. Patch 解析流程

**入口**: `codex-rs/apply-patch/src/parser.rs`

```rust
// parser.rs:106-113
pub fn parse_patch(patch: &str) -> Result<ApplyPatchArgs, ParseError> {
    let mode = if PARSE_IN_STRICT_MODE {
        ParseMode::Strict
    } else {
        ParseMode::Lenient  // 当前配置为宽松模式
    };
    parse_patch_text(patch, mode)
}
```

**解析步骤**:
1. **边界检查**: 验证 `*** Begin Patch` 和 `*** End Patch` 标记
2. **Hunk 解析**: 逐行解析为 `Hunk` 枚举（AddFile/DeleteFile/UpdateFile）
3. **Chunk 解析**: 对于 UpdateFile，进一步解析 `@@` 标记的变更块

**015 场景解析结果**:
```rust
// 解析后得到两个 Hunk:
[
    AddFile {
        path: PathBuf::from("created.txt"),
        contents: "hello\n".to_string(),
    },
    UpdateFile {
        path: PathBuf::from("missing.txt"),
        move_path: None,
        chunks: vec![UpdateFileChunk {
            change_context: None,
            old_lines: vec!["old".to_string()],
            new_lines: vec!["new".to_string()],
            is_end_of_file: false,
        }],
    },
]
```

#### 2. Hunk 应用流程

**入口**: `codex-rs/apply-patch/src/lib.rs:279-339`

```rust
fn apply_hunks_to_files(hunks: &[Hunk]) -> anyhow::Result<AffectedPaths> {
    // 遍历每个 hunk，顺序执行
    for hunk in hunks {
        match hunk {
            Hunk::AddFile { path, contents } => {
                // 1. 创建父目录
                // 2. 写入文件
                // 3. 记录到 added 列表
            }
            Hunk::DeleteFile { path } => {
                // 1. 删除文件
                // 2. 记录到 deleted 列表
            }
            Hunk::UpdateFile { path, move_path, chunks } => {
                // 1. 读取原文件
                // 2. 计算替换内容
                // 3. 写入新内容/移动文件
                // 4. 记录到 modified 列表
            }
        }
    }
}
```

**关键代码 - 顺序执行无事务保护**:

```rust
// lib.rs:287-339
for hunk in hunks {
    match hunk {
        Hunk::AddFile { path, contents } => {
            if let Some(parent) = path.parent()
                && !parent.as_os_str().is_empty()
            {
                std::fs::create_dir_all(parent)?;  // 可能失败
            }
            std::fs::write(path, contents)?;  // 可能失败
            added.push(path.clone());  // 成功后记录
        }
        // ... 其他分支
    }
}
```

**015 场景执行时序**:
1. `AddFile` 成功 → `created.txt` 被创建 → `added` 列表包含该路径
2. `UpdateFile` 尝试读取 `missing.txt` → `derive_new_contents_from_chunks` 失败
3. 错误向上传播 → `apply_hunks_to_files` 返回 `Err`
4. 但 `created.txt` 已经存在于文件系统，未被删除

#### 3. 错误处理流程

**入口**: `codex-rs/apply-patch/src/lib.rs:248-266`

```rust
match apply_hunks_to_files(hunks) {
    Ok(affected) => {
        print_summary(&affected, stdout)?;
        Ok(())
    }
    Err(err) => {
        let msg = err.to_string();
        writeln!(stderr, "{msg}")?;  // 错误信息写入 stderr
        // ... 转换为 ApplyPatchError
        Err(ApplyPatchError::IoError(...))
    }
}
```

**015 场景的错误输出**:
```
Failed to read file to update missing.txt: No such file or directory (os error 2)
```

### 数据结构

#### 1. Hunk 枚举

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

#### 2. UpdateFileChunk 结构

```rust
// parser.rs:90-104
pub struct UpdateFileChunk {
    pub change_context: Option<String>,  // @@ 后的上下文
    pub old_lines: Vec<String>,          // 以 - 开头的行
    pub new_lines: Vec<String>,          // 以 + 开头的行
    pub is_end_of_file: bool,            // 是否标记 *** End of File
}
```

#### 3. AffectedPaths 结构

```rust
// lib.rs:271-275
pub struct AffectedPaths {
    pub added: Vec<PathBuf>,
    pub modified: Vec<PathBuf>,
    pub deleted: Vec<PathBuf>,
}
```

### 协议/命令格式

#### Patch 文件格式 (DSL)

```
*** Begin Patch                    # 开始标记
*** Add File: <path>               # 添加文件头
+<line1>                           # 文件内容行（以 + 开头）
+<line2>
*** Delete File: <path>            # 删除文件头
*** Update File: <path>            # 更新文件头
*** Move to: <new_path>            # 可选：移动目标
@@ [context]                       # 变更块开始（可选上下文）
 <context_line>                     # 空格开头 = 上下文
-<old_line>                         # - 开头 = 删除
+<new_line>                         # + 开头 = 添加
*** End of File                    # 可选：标记文件结束
*** End Patch                      # 结束标记
```

---

## 关键代码路径与文件引用

### 核心文件

| 文件 | 职责 | 关键函数/结构 |
|------|------|--------------|
| `src/parser.rs` | Patch 解析 | `parse_patch()`, `Hunk`, `UpdateFileChunk` |
| `src/lib.rs` | 核心应用逻辑 | `apply_patch()`, `apply_hunks_to_files()`, `derive_new_contents_from_chunks()` |
| `src/standalone_executable.rs` | CLI 入口 | `run_main()` |
| `src/invocation.rs` | Shell 命令解析 | `maybe_parse_apply_patch()`, `extract_apply_patch_from_bash()` |
| `src/seek_sequence.rs` | 模糊匹配算法 | `seek_sequence()` |

### 015 场景的代码调用链

```
test_apply_patch_cli_failure_after_partial_success_leaves_changes (tests/suite/tool.rs:243)
    └── Command::new("apply_patch").arg(patch).current_dir(tmp.path()).output()
        └── apply_patch::main() (src/main.rs)
            └── codex_apply_patch::main() (src/standalone_executable.rs:4)
                └── run_main() (src/standalone_executable.rs:11)
                    └── crate::apply_patch() (src/lib.rs:183)
                        ├── parse_patch() (src/parser.rs:106)
                        └── apply_hunks() (src/lib.rs:216)
                            └── apply_hunks_to_files() (src/lib.rs:279)
                                ├── Hunk::AddFile → fs::write() 成功
                                └── Hunk::UpdateFile → derive_new_contents_from_chunks() 失败
                                    └── fs::read_to_string(path) → Err (文件不存在)
```

### 测试执行路径

**场景测试框架**: `tests/suite/scenarios.rs:30-63`

```rust
fn run_apply_patch_scenario(dir: &Path) -> anyhow::Result<()> {
    let tmp = tempdir()?;
    
    // 1. 复制 input 目录（015 场景无 input 目录）
    let input_dir = dir.join("input");
    if input_dir.is_dir() {
        copy_dir_recursive(&input_dir, tmp.path())?;
    }
    
    // 2. 读取 patch.txt
    let patch = fs::read_to_string(dir.join("patch.txt"))?;
    
    // 3. 执行 apply_patch（不检查退出码！）
    Command::new(codex_utils_cargo_bin::cargo_bin("apply_patch")?)
        .arg(patch)
        .current_dir(tmp.path())
        .output()?;  // 注意：不断言 success()
    
    // 4. 比较最终状态与 expected 目录
    let expected_snapshot = snapshot_dir(&expected_dir)?;
    let actual_snapshot = snapshot_dir(tmp.path())?;
    assert_eq!(actual_snapshot, expected_snapshot);
    
    Ok(())
}
```

**关键设计**: 场景测试**不检查退出码**，只验证最终文件系统状态。这允许测试部分失败的场景。

---

## 依赖与外部交互

### 内部依赖

```
codex-apply-patch
├── src/parser.rs           # 纯逻辑，无外部依赖
├── src/lib.rs              # 依赖 std::fs, similar (diff 库)
├── src/standalone_executable.rs  # 依赖 std::io
├── src/invocation.rs       # 依赖 tree-sitter, tree-sitter-bash
└── src/seek_sequence.rs    # 纯逻辑
```

### 外部 crate 依赖

| Crate | 用途 | 版本来源 |
|-------|------|---------|
| `anyhow` | 错误处理 | workspace |
| `similar` | 统一 diff 生成 | workspace |
| `thiserror` | 错误类型定义 | workspace |
| `tree-sitter` | Bash 脚本解析 | workspace |
| `tree-sitter-bash` | Bash 语法 | workspace |

### 测试依赖

| Crate | 用途 |
|-------|------|
| `assert_cmd` | CLI 测试辅助 |
| `assert_matches` | 模式匹配断言 |
| `codex-utils-cargo-bin` | 定位二进制文件 |
| `pretty_assertions` | 美观的 diff 输出 |
| `tempfile` | 临时目录管理 |

### 系统交互

**文件系统操作**:
- `std::fs::create_dir_all()` - 创建父目录
- `std::fs::write()` - 写入文件
- `std::fs::read_to_string()` - 读取文件（015 场景失败点）
- `std::fs::remove_file()` - 删除文件
- `std::fs::metadata()` - 获取文件元数据

**I/O 流**:
- `std::io::stdout()` - 成功输出
- `std::io::stderr()` - 错误输出
- `std::io::stdin()` - 读取 patch（stdin 模式）

---

## 风险、边界与改进建议

### 当前风险

#### 1. 非原子性导致的数据不一致

**风险描述**: 如果 patch 包含相互依赖的操作（如先移动文件再更新），部分失败可能导致项目处于不一致状态。

**示例风险场景**:
```
*** Begin Patch
*** Update File: config.json
@@
-version: 1
+version: 2
*** Update File: version.txt
@@
-1
+2
*** End Patch
```

如果第一个成功，第二个失败，项目将处于"半升级"状态。

#### 2. 无回滚机制

**当前行为**: 失败时不清除已创建的文件
**潜在问题**: 重复运行 patch 可能因文件已存在而产生意外行为

#### 3. 错误信息可能误导

**当前错误输出**:
```
Failed to read file to update missing.txt: No such file or directory (os error 2)
```

**问题**: 用户可能不知道 `created.txt` 已经成功创建。

### 边界情况

| 边界情况 | 当前行为 | 测试覆盖 |
|---------|---------|---------|
| 空 patch | 报错 "No files were modified." | `005_rejects_empty_patch` |
| 更新不存在文件 | 报错并保留之前成功的操作 | `015_failure_after_partial_success_leaves_changes` |
| 删除不存在文件 | 报错 | `007_rejects_missing_file_delete` |
| 添加已存在文件 | 覆盖（静默） | `011_add_overwrites_existing_file` |
| 移动到已存在文件 | 覆盖（静默） | `010_move_overwrites_existing_destination` |

### 改进建议

#### 1. 增加部分应用的警告信息

**建议**: 当部分成功时，在 stderr 中输出已应用的操作列表：

```rust
// lib.rs:253-265
Err(err) => {
    let msg = err.to_string();
    writeln!(stderr, "{msg}")?;
    
    // 新增：报告已成功的操作
    if !affected.added.is_empty() || !affected.modified.is_empty() {
        writeln!(stderr, "\nWarning: Partial success. The following changes were applied before the error:")?;
        for path in &affected.added {
            writeln!(stderr, "  A {}", path.display())?;
        }
        for path in &affected.modified {
            writeln!(stderr, "  M {}", path.display())?;
        }
    }
    // ...
}
```

#### 2. 添加 "dry-run" 模式

**建议**: 在正式应用前验证所有操作的可行性：

```rust
pub fn apply_hunks_to_files(hunks: &[Hunk], dry_run: bool) -> Result<AffectedPaths> {
    // 先验证所有 UpdateFile 的目标文件存在
    for hunk in hunks {
        if let Hunk::UpdateFile { path, .. } = hunk {
            if !path.exists() {
                bail!("File does not exist: {}", path.display());
            }
        }
    }
    if dry_run {
        return Ok(AffectedPaths::default());
    }
    // ... 实际应用
}
```

#### 3. 添加 "continue-on-error" 选项

**建议**: 显式控制是否继续处理后续 hunks：

```rust
pub enum OnError {
    Stop,      // 当前行为：遇到错误立即停止
    Continue,  // 尝试应用所有 hunks，收集所有错误
}
```

#### 4. 改进测试框架

**当前场景测试限制**:
- 无法验证 stderr 输出
- 无法验证退出码

**建议**: 扩展场景目录结构：

```
015_failure_after_partial_success_leaves_changes/
├── patch.txt
├── expected/           # 期望的文件系统状态
│   └── created.txt
├── expected_stderr.txt  # 新增：期望的 stderr 输出
├── expected_exit_code.txt  # 新增：期望的退出码（如 "1"）
└── input/              # 可选的输入文件
```

### 代码质量建议

#### 1. 提取 AffectedPaths 的显示逻辑

当前 `print_summary` 和错误处理中的 affected 报告逻辑重复，建议统一：

```rust
impl AffectedPaths {
    fn format_report(&self) -> String {
        let mut out = String::new();
        for path in &self.added {
            writeln!(&mut out, "A {}", path.display()).unwrap();
        }
        // ...
        out
    }
}
```

#### 2. 增加日志/追踪

建议添加 `tracing` 依赖以便调试：

```rust
#[tracing::instrument(skip(hunks))]
fn apply_hunks_to_files(hunks: &[Hunk]) -> Result<AffectedPaths> {
    tracing::debug!(hunk_count = hunks.len(), "Applying hunks");
    // ...
}
```

---

## 附录：相关文件完整列表

### 源代码
- `/home/sansha/Github/codex/codex-rs/apply-patch/src/lib.rs` (1000+ 行)
- `/home/sansha/Github/codex/codex-rs/apply-patch/src/parser.rs` (763 行)
- `/home/sansha/Github/codex/codex-rs/apply-patch/src/standalone_executable.rs` (59 行)
- `/home/sansha/Github/codex/codex-rs/apply-patch/src/invocation.rs` (813 行)
- `/home/sansha/Github/codex/codex-rs/apply-patch/src/seek_sequence.rs` (151 行)
- `/home/sansha/Github/codex/codex-rs/apply-patch/src/main.rs` (3 行)

### 测试代码
- `/home/sansha/Github/codex/codex-rs/apply-patch/tests/all.rs`
- `/home/sansha/Github/codex/codex-rs/apply-patch/tests/suite/mod.rs`
- `/home/sansha/Github/codex/codex-rs/apply-patch/tests/suite/scenarios.rs` (126 行)
- `/home/sansha/Github/codex/codex-rs/apply-patch/tests/suite/cli.rs` (91 行)
- `/home/sansha/Github/codex/codex-rs/apply-patch/tests/suite/tool.rs` (257 行)

### 测试场景
- `/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/015_failure_after_partial_success_leaves_changes/patch.txt`
- `/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/015_failure_after_partial_success_leaves_changes/expected/created.txt`

### 配置与文档
- `/home/sansha/Github/codex/codex-rs/apply-patch/Cargo.toml`
- `/home/sansha/Github/codex/codex-rs/apply-patch/BUILD.bazel`
- `/home/sansha/Github/codex/codex-rs/apply-patch/apply_patch_tool_instructions.md` (75 行)

---

*文档生成时间: 2026-03-22*
*研究范围: codex-rs/apply-patch 模块*
