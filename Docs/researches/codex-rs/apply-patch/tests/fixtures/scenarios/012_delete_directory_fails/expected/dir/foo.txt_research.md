# 研究文档：`012_delete_directory_fails` 测试场景

## 1. 场景与职责

### 1.1 目标文件
- **文件路径**: `codex-rs/apply-patch/tests/fixtures/scenarios/012_delete_directory_fails/expected/dir/foo.txt`
- **文件内容**: `stable`

### 1.2 测试场景概述
该测试场景属于 `apply-patch` 工具的端到端测试套件，专门用于验证**删除目录操作失败**的行为。场景编号 `012` 表明这是第12个测试用例，位于场景目录序列中。

### 1.3 场景结构
```
012_delete_directory_fails/
├── input/
│   └── dir/
│       └── foo.txt          # 输入状态：包含子目录和文件
├── expected/
│   └── dir/
│       └── foo.txt          # 期望状态：目录和文件保持不变（删除失败）
└── patch.txt                # 补丁操作：尝试删除目录 "dir"
```

### 1.4 核心职责
该测试验证当补丁尝试使用 `*** Delete File: dir` 删除一个目录（而非普通文件）时，`apply-patch` 工具应当：
1. **拒绝执行删除操作**（因为 `std::fs::remove_file` 无法删除目录）
2. **保持原始文件系统状态不变**
3. **返回错误状态码**（非零退出码）

目标文件 `foo.txt` 的内容 `"stable"` 作为**状态标记**，用于验证文件在删除目录操作失败后是否保持原样。

---

## 2. 功能点目的

### 2.1 测试目的

| 目的维度 | 说明 |
|---------|------|
| **边界测试** | 验证工具对"尝试删除目录"这一非法操作的正确处理 |
| **错误恢复** | 确保操作失败后，文件系统状态保持一致性（无部分修改） |
| **安全机制** | 防止意外递归删除目录及其内容 |

### 2.2 对比分析

与相邻测试场景的对比：

| 场景编号 | 场景名称 | 目的 | 与 012 的区别 |
|---------|---------|------|--------------|
| `007_rejects_missing_file_delete` | 删除不存在的文件 | 验证删除不存在文件时的错误处理 | 目标不存在 vs 目标是目录 |
| `020_delete_file_success` | 成功删除文件 | 验证正常文件删除流程 | 成功场景 vs 失败场景 |
| `012_delete_directory_fails` | 删除目录失败 | **验证删除目录时的错误处理** | **本场景：目录不可删除** |

### 2.3 预期行为

```
输入状态: dir/foo.txt 存在，内容为 "stable"
补丁操作: *** Delete File: dir  （尝试删除目录）
执行结果: 失败（remove_file 无法删除目录）
期望状态: dir/foo.txt 仍然存在，内容为 "stable"（与输入一致）
```

---

## 3. 具体技术实现

### 3.1 补丁格式解析

**patch.txt 内容：**
```text
*** Begin Patch
*** Delete File: dir
*** End Patch
```

该补丁被解析为一个 `Hunk::DeleteFile` 类型的 hunk：

```rust
// parser.rs 第 65-67 行
DeleteFile {
    path: PathBuf,  // 此处为 "dir"
},
```

### 3.2 关键执行流程

#### 3.2.1 场景测试执行流程

```rust
// tests/suite/scenarios.rs 第 30-63 行
fn run_apply_patch_scenario(dir: &Path) -> anyhow::Result<()> {
    let tmp = tempdir()?;
    
    // 1. 复制 input/ 到临时目录
    copy_dir_recursive(&input_dir, tmp.path())?;
    
    // 2. 读取 patch.txt
    let patch = fs::read_to_string(dir.join("patch.txt"))?;
    
    // 3. 执行 apply_patch（不检查退出码）
    Command::new(codex_utils_cargo_bin::cargo_bin("apply_patch")?)
        .arg(patch)
        .current_dir(tmp.path())
        .output()?;  // 注意：故意不断言 exit status
    
    // 4. 比较实际状态与 expected/ 状态
    let expected_snapshot = snapshot_dir(&expected_dir)?;
    let actual_snapshot = snapshot_dir(tmp.path())?;
    assert_eq!(actual_snapshot, expected_snapshot);
    
    Ok(())
}
```

**关键设计**：测试不检查退出码，只验证最终文件系统状态。这意味着即使 `apply_patch` 返回错误（非零退出码），只要文件状态符合预期，测试就通过。

#### 3.2.2 删除操作执行路径

```rust
// lib.rs 第 301-304 行
Hunk::DeleteFile { path } => {
    std::fs::remove_file(path)  // 使用 remove_file，非 remove_dir
        .with_context(|| format!("Failed to delete file {}", path.display()))?;
    deleted.push(path.clone());
}
```

**技术细节**：
- 使用 `std::fs::remove_file` 而非 `std::fs::remove_dir`
- 当 `path` 是目录时，`remove_file` 返回 `ErrorKind::IsADirectory` 错误
- 错误通过 `anyhow::Context` 添加上下文后向上传播

#### 3.2.3 错误处理与状态一致性

```rust
// lib.rs 第 248-265 行
match apply_hunks_to_files(hunks) {
    Ok(affected) => {
        print_summary(&affected, stdout)?;
        Ok(())
    }
    Err(err) => {
        let msg = err.to_string();
        writeln!(stderr, "{msg}").map_err(ApplyPatchError::from)?;
        // 转换为 ApplyPatchError::IoError 返回
        Err(...)
    }
}
```

**重要特性**：`apply_hunks_to_files` 使用 `?` 传播错误，一旦某个 hunk 失败，后续 hunk 不会执行。这保证了**原子性**：部分失败不会留下中间状态。

### 3.3 数据结构

#### 3.3.1 Hunk 枚举（parser.rs 第 58-76 行）

```rust
pub enum Hunk {
    AddFile {
        path: PathBuf,
        contents: String,
    },
    DeleteFile {
        path: PathBuf,  // 012 场景使用的变体
    },
    UpdateFile {
        path: PathBuf,
        move_path: Option<PathBuf>,
        chunks: Vec<UpdateFileChunk>,
    },
}
```

#### 3.3.2 文件系统状态快照

```rust
// tests/suite/scenarios.rs 第 65-69 行
enum Entry {
    File(Vec<u8>),
    Dir,
}

// 使用 BTreeMap 保证确定性比较
fn snapshot_dir(root: &Path) -> anyhow::Result<BTreeMap<PathBuf, Entry>>;
```

### 3.4 命令行接口

```rust
// standalone_executable.rs 第 11-58 行
pub fn run_main() -> i32 {
    // 支持两种调用方式：
    // 1. apply_patch '<patch内容>'  （参数传入）
    // 2. echo '<patch内容>' | apply_patch  （stdin 传入）
    
    match crate::apply_patch(&patch_arg, &mut stdout, &mut stderr) {
        Ok(()) => 0,      // 成功
        Err(_) => 1,      // 失败（012 场景预期结果）
    }
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心源码文件

| 文件 | 职责 | 相关行号 |
|-----|------|---------|
| `src/lib.rs` | 补丁应用主逻辑、错误处理 | 182-266 (apply_patch), 279-339 (apply_hunks_to_files) |
| `src/parser.rs` | 补丁格式解析、Hunk 定义 | 58-76 (Hunk 枚举), 271-278 (DeleteFile 解析) |
| `src/standalone_executable.rs` | CLI 入口、stdin/参数处理 | 11-58 (run_main) |
| `src/invocation.rs` | Shell 命令解析、heredoc 提取 | 91-128 (maybe_parse_apply_patch) |

### 4.2 测试相关文件

| 文件 | 职责 | 相关行号 |
|-----|------|---------|
| `tests/suite/scenarios.rs` | 场景测试框架 | 10-26 (test_apply_patch_scenarios), 30-63 (run_apply_patch_scenario) |
| `tests/all.rs` | 测试模块聚合 | - |

### 4.3 本场景文件

| 文件 | 内容 | 作用 |
|-----|------|------|
| `012_delete_directory_fails/input/dir/foo.txt` | `"stable"` | 测试前初始状态 |
| `012_delete_directory_fails/expected/dir/foo.txt` | `"stable"` | 测试后期望状态（保持不变） |
| `012_delete_directory_fails/patch.txt` | `*** Delete File: dir` | 触发删除目录的非法操作 |

### 4.4 代码调用链

```
test_apply_patch_scenarios (测试入口)
    └── run_apply_patch_scenario
            ├── copy_dir_recursive(input/)  →  复制到临时目录
            ├── Command::new("apply_patch").arg(patch_txt).output()
            │       └── standalone_executable::run_main
            │               └── lib::apply_patch
            │                       └── lib::apply_hunks
            │                               └── lib::apply_hunks_to_files
            │                                       └── Hunk::DeleteFile { path: "dir" }
            │                                               └── std::fs::remove_file("dir")  →  失败!
            │                       └── 错误写入 stderr，返回 Err
            │               └── std::process::exit(1)
            └── assert_eq!(actual_snapshot, expected_snapshot)  →  验证状态不变
```

---

## 5. 依赖与外部交互

### 5.1 内部依赖

| 依赖模块 | 用途 |
|---------|------|
| `codex-utils-cargo-bin` | 测试时定位编译后的 `apply_patch` 二进制文件 |

### 5.2 外部依赖（Cargo.toml）

```toml
[dependencies]
anyhow = "..."           # 错误处理、Context 扩展
similar = "..."          # 文本差异计算（unified diff）
thiserror = "..."        # 错误类型定义
tree-sitter = "..."      # Bash 脚本解析（heredoc 提取）
tree-sitter-bash = "..." # Bash 语法定义

[dev-dependencies]
assert_cmd = "..."       # CLI 测试辅助
assert_matches = "..."   # 模式匹配断言
pretty_assertions = "..." # 美观的差异输出
tempfile = "..."         # 临时目录创建
```

### 5.3 系统调用

| 系统调用 | 用途 | 012 场景行为 |
|---------|------|-------------|
| `std::fs::remove_file` | 删除文件 | 失败（目标是目录） |
| `std::fs::metadata` | 获取文件元数据 | 用于 snapshot_dir 遍历 |
| `std::fs::read_dir` | 读取目录内容 | 遍历 input/expected 目录 |

### 5.4 与 Shell 的交互

`apply-patch` 工具设计为可由 AI 模型通过 shell 调用：

```json
{
  "command": ["apply_patch", "*** Begin Patch\n*** Delete File: dir\n*** End Patch"]
}
```

或通过 heredoc：

```bash
bash -lc "apply_patch <<'EOF'
*** Begin Patch
*** Delete File: dir
*** End Patch
EOF"
```

---

## 6. 风险、边界与改进建议

### 6.1 当前风险

| 风险点 | 描述 | 严重程度 |
|-------|------|---------|
| **错误信息不明确** | 用户只看到 "Failed to delete file dir: Is a directory (os error 21)"，未明确提示应使用其他工具删除目录 | 低 |
| **无递归删除保护** | 如果未来误用 `remove_dir_all`，可能导致数据丢失 | 中 |
| **测试依赖外部二进制** | 测试需要预编译的 `apply_patch` 二进制文件 | 低 |

### 6.2 边界情况

| 边界情况 | 当前行为 | 建议 |
|---------|---------|------|
| 删除符号链接（指向目录） | `remove_file` 可以删除符号链接本身 | 符合预期 |
| 删除空目录 | 同样失败（需要 `remove_dir`） | 符合预期 |
| 删除带斜杠的目录路径 (`dir/`) | 行为取决于 OS | 建议规范化路径处理 |

### 6.3 改进建议

#### 6.3.1 错误信息优化

当前错误：
```
Failed to delete file dir: Is a directory (os error 21)
```

建议改进：
```
Failed to delete 'dir': it is a directory, not a file. 
Note: apply_patch can only delete files. Use 'rm -r' to delete directories.
```

实现方式：
```rust
// lib.rs 第 301-304 行改进
Hunk::DeleteFile { path } => {
    match std::fs::remove_file(path) {
        Ok(()) => deleted.push(path.clone()),
        Err(e) if e.kind() == std::io::ErrorKind::IsADirectory => {
            anyhow::bail!(
                "Failed to delete '{}': it is a directory, not a file. \
                 Note: apply_patch can only delete files.",
                path.display()
            );
        }
        Err(e) => {
            return Err(IoError {
                context: format!("Failed to delete file {}", path.display()),
                source: e,
            }.into());
        }
    }
}
```

#### 6.3.2 添加显式目录删除检测

在解析阶段增加警告：

```rust
// parser.rs 第 271-278 行
} else if let Some(path) = first_line.strip_prefix(DELETE_FILE_MARKER) {
    let path = PathBuf::from(path);
    // 可选：在解析时检查路径类型（需要 cwd 上下文）
    return Ok((DeleteFile { path }, 1));
}
```

#### 6.3.3 测试覆盖扩展

建议添加以下测试场景：

| 新场景 | 目的 |
|-------|------|
| `023_delete_symlink_to_dir` | 验证删除指向目录的符号链接的行为 |
| `024_delete_nonempty_directory` | 验证删除非空目录的失败行为 |
| `025_delete_file_and_directory_in_one_patch` | 验证混合操作的错误处理 |

#### 6.3.4 文档改进

在 `apply_patch_tool_instructions.md` 中明确说明：

```markdown
### 限制
- `*** Delete File:` 只能删除普通文件，**不能删除目录**
- 如需删除目录，请使用 shell 命令（如 `rm -r`）
```

---

## 7. 总结

`012_delete_directory_fails` 场景通过简单的 `"stable"` 标记文件，验证了 `apply-patch` 工具在面对非法操作（删除目录）时的正确行为：

1. **拒绝执行**：使用 `remove_file` 正确失败
2. **状态一致**：文件系统保持原样
3. **错误传播**：向上层返回清晰的错误信息

该测试场景是 `apply-patch` 安全模型的重要组成部分，确保工具不会意外修改目录结构，为 AI 驱动的代码编辑提供了安全边界。
