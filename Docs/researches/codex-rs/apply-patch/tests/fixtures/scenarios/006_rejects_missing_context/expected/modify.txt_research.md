# 研究文档: 006_rejects_missing_context 测试场景

## 文件信息

- **目标文件**: `codex-rs/apply-patch/tests/fixtures/scenarios/006_rejects_missing_context/expected/modify.txt`
- **关联文件**:
  - `codex-rs/apply-patch/tests/fixtures/scenarios/006_rejects_missing_context/input/modify.txt`
  - `codex-rs/apply-patch/tests/fixtures/scenarios/006_rejects_missing_context/patch.txt`
- **测试代码**: `codex-rs/apply-patch/tests/suite/scenarios.rs`
- **核心实现**: `codex-rs/apply-patch/src/lib.rs`, `codex-rs/apply-patch/src/seek_sequence.rs`

---

## 1. 场景与职责

### 1.1 测试场景概述

`006_rejects_missing_context` 是 `apply-patch` 工具测试套件中的一个**负向测试场景（negative test case）**，用于验证当补丁中指定的上下文行（context line）在目标文件中不存在时，系统能够正确地拒绝应用补丁并保持文件不变。

### 1.2 场景目录结构

```
codex-rs/apply-patch/tests/fixtures/scenarios/006_rejects_missing_context/
├── input/
│   └── modify.txt          # 原始文件内容: line1\nline2\n
├── expected/
│   └── modify.txt          # 期望的最终状态（与input相同，因为补丁应被拒绝）
└── patch.txt               # 尝试应用的补丁
```

### 1.3 测试数据详情

**input/modify.txt**:
```
line1
line2
```

**patch.txt**:
```
*** Begin Patch
*** Update File: modify.txt
@@
-missing
+changed
*** End Patch
```

**expected/modify.txt**:
```
line1
line2
```

### 1.4 测试目的

该场景验证以下关键行为：
1. **上下文匹配失败检测**: 补丁尝试查找 `missing` 行，但文件中实际包含 `line1` 和 `line2`
2. **原子性保证**: 补丁应用失败时，文件内容保持不变
3. **错误报告**: 系统应输出清晰的错误信息，指明无法找到期望的行

---

## 2. 功能点目的

### 2.1 apply-patch 工具概述

`apply-patch` 是 Codex 项目中的一个核心工具，用于将类 diff 格式的补丁应用到文件系统。它支持三种基本操作：

1. **Add File**: 创建新文件
2. **Delete File**: 删除现有文件
3. **Update File**: 修改现有文件内容（支持移动/重命名）

### 2.2 上下文匹配机制

在 `Update File` 操作中，补丁使用上下文行来定位修改位置：

- `@@` 标记表示一个变更块（chunk）的开始
- `-` 前缀表示要删除的行
- `+` 前缀表示要添加的行
- ` ` 前缀（空格）表示上下文行（保持不变）

### 2.3 本场景验证的功能点

| 功能点 | 描述 |
|--------|------|
| 严格匹配 | 补丁中的 `-missing` 要求文件必须包含 `missing` 行 |
| 失败回滚 | 当匹配失败时，文件保持原始状态 |
| 错误输出 | 向 stderr 输出 `"Failed to find expected lines in modify.txt:\nmissing\n"` |

---

## 3. 具体技术实现

### 3.1 关键流程

#### 3.1.1 补丁应用主流程

```rust
// lib.rs: apply_patch 函数
pub fn apply_patch(
    patch: &str,
    stdout: &mut impl std::io::Write,
    stderr: &mut impl std::io::Write,
) -> Result<(), ApplyPatchError> {
    let hunks = match parse_patch(patch) {
        Ok(source) => source.hunks,
        Err(e) => { /* 处理解析错误 */ }
    };
    apply_hunks(&hunks, stdout, stderr)?;
    Ok(())
}
```

#### 3.1.2 Update File 处理流程

```rust
// lib.rs: apply_hunks_to_files 函数
Hunk::UpdateFile { path, move_path, chunks } => {
    let AppliedPatch { new_contents, .. } = 
        derive_new_contents_from_chunks(path, chunks)?;  // 可能返回错误
    // 写入新内容...
}
```

#### 3.1.3 替换计算流程

```rust
// lib.rs: compute_replacements 函数
fn compute_replacements(
    original_lines: &[String],
    path: &Path,
    chunks: &[UpdateFileChunk],
) -> Result<Vec<(usize, usize, Vec<String>)>, ApplyPatchError> {
    for chunk in chunks {
        // 1. 首先查找 change_context（如果存在）
        if let Some(ctx_line) = &chunk.change_context {
            if let Some(idx) = seek_sequence::seek_sequence(...) {
                line_index = idx + 1;
            } else {
                return Err(ApplyPatchError::ComputeReplacements(format!(
                    "Failed to find context '{}' in {}", ctx_line, path.display()
                )));
            }
        }

        // 2. 查找 old_lines（本场景的关键路径）
        let pattern: &[String] = &chunk.old_lines;
        let found = seek_sequence::seek_sequence(original_lines, pattern, line_index, chunk.is_end_of_file);
        
        if let Some(start_idx) = found {
            replacements.push((start_idx, pattern.len(), new_slice.to_vec()));
        } else {
            // 本场景触发此错误路径
            return Err(ApplyPatchError::ComputeReplacements(format!(
                "Failed to find expected lines in {}:\n{}",
                path.display(),
                chunk.old_lines.join("\n"),
            )));
        }
    }
}
```

### 3.2 核心数据结构

#### 3.2.1 Hunk 枚举

```rust
// parser.rs
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

#### 3.2.2 UpdateFileChunk 结构

```rust
// parser.rs
pub struct UpdateFileChunk {
    /// 上下文定位行（如类名、函数名）
    pub change_context: Option<String>,
    /// 要替换的旧行
    pub old_lines: Vec<String>,
    /// 新行内容
    pub new_lines: Vec<String>,
    /// 是否必须在文件末尾匹配
    pub is_end_of_file: bool,
}
```

#### 3.2.3 ApplyPatchError 枚举

```rust
// lib.rs
pub enum ApplyPatchError {
    #[error(transparent)]
    ParseError(#[from] ParseError),
    #[error(transparent)]
    IoError(#[from] IoError),
    /// 计算替换时出错（本场景触发的错误类型）
    #[error("{0}")]
    ComputeReplacements(String),
    /// 隐式调用错误
    #[error("patch detected without explicit call...")]
    ImplicitInvocation,
}
```

### 3.3 序列查找算法

`seek_sequence` 是上下文匹配的核心算法，实现了多级匹配策略：

```rust
// seek_sequence.rs
pub(crate) fn seek_sequence(
    lines: &[String],
    pattern: &[String],
    start: usize,
    eof: bool,
) -> Option<usize> {
    // 1. 空模式直接返回
    if pattern.is_empty() { return Some(start); }
    
    // 2. 模式比输入长，不可能匹配
    if pattern.len() > lines.len() { return None; }
    
    // 3. 确定搜索起始位置
    let search_start = if eof && lines.len() >= pattern.len() {
        lines.len() - pattern.len()
    } else {
        start
    };
    
    // 4. 四级匹配策略（按严格程度递减）
    // 4.1 精确匹配
    for i in search_start..=lines.len().saturating_sub(pattern.len()) {
        if lines[i..i + pattern.len()] == *pattern { return Some(i); }
    }
    
    // 4.2 忽略行尾空白匹配
    for i in search_start..=lines.len().saturating_sub(pattern.len()) {
        if lines[i + p_idx].trim_end() == pat.trim_end() { /* ... */ }
    }
    
    // 4.3 忽略首尾空白匹配
    for i in search_start..=lines.len().saturating_sub(pattern.len()) {
        if lines[i + p_idx].trim() == pat.trim() { /* ... */ }
    }
    
    // 4.4 Unicode 标点规范化匹配（最宽松）
    // 将各种 Unicode 标点（如 EN DASH、智能引号）映射为 ASCII 等价物
    fn normalise(s: &str) -> String {
        s.trim().chars().map(|c| match c {
            '\u{2010}'..='\u{2015}' | '\u{2212}' => '-',
            '\u{2018}'..='\u{201B}' => '\'',
            '\u{201C}'..='\u{201F}' => '"',
            // ... 其他 Unicode 空格字符
            _ => c,
        }).collect()
    }
    
    None  // 所有匹配策略失败
}
```

### 3.4 补丁格式协议

补丁遵循自定义的类 diff 格式：

```
*** Begin Patch                    # 补丁开始标记
*** Update File: <path>            # 文件操作头
@@ [context]                        # 变更块开始（可选上下文）
- <old line>                        # 删除行
+ <new line>                        # 添加行
  <context line>                    # 上下文行（空格前缀）
*** End of File                     # 文件结束标记（可选）
*** End Patch                       # 补丁结束标记
```

---

## 4. 关键代码路径与文件引用

### 4.1 测试执行路径

```
tests/suite/scenarios.rs::test_apply_patch_scenarios()
  └── run_apply_patch_scenario(dir)
      ├── 复制 input/ 到临时目录
      ├── 读取 patch.txt
      ├── 执行 apply_patch 二进制
      │   └── standalone_executable.rs::run_main()
      │       └── lib.rs::apply_patch()
      │           ├── parser.rs::parse_patch()          # 解析补丁
      │           └── lib.rs::apply_hunks()
      │               └── lib.rs::apply_hunks_to_files()
      │                   └── lib.rs::derive_new_contents_from_chunks()
      │                       └── lib.rs::compute_replacements()
      │                           └── seek_sequence.rs::seek_sequence()  # 关键匹配
      └── 比较实际结果与 expected/
```

### 4.2 错误处理路径

本场景触发的错误路径：

```
compute_replacements()
  ├── chunk.old_lines = ["missing"]
  ├── seek_sequence(lines=["line1", "line2"], pattern=["missing"], ...)
  │   ├── 精确匹配失败
  │   ├── trim_end 匹配失败
   │   ├── trim 匹配失败
  │   └── Unicode 规范化匹配失败
  │   └── return None
  └── 返回 Err(ApplyPatchError::ComputeReplacements(
        "Failed to find expected lines in modify.txt:\nmissing"
      ))
```

### 4.3 相关测试代码

**工具测试** (`tests/suite/tool.rs`):
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

---

## 5. 依赖与外部交互

### 5.1 内部依赖

| 模块 | 文件 | 职责 |
|------|------|------|
| parser | `src/parser.rs` | 解析补丁文本为结构化 Hunk |
| seek_sequence | `src/seek_sequence.rs` | 多策略行序列匹配算法 |
| invocation | `src/invocation.rs` | 从 shell 命令提取补丁 |
| standalone_executable | `src/standalone_executable.rs` | CLI 入口点 |

### 5.2 外部依赖

**Cargo.toml**:
```toml
[dependencies]
anyhow = { workspace = true }      # 错误处理
similar = { workspace = true }     # 文本差异计算（unified diff）
thiserror = { workspace = true }   # 错误派生宏
tree-sitter = { workspace = true } # Bash 脚本解析
tree-sitter-bash = { workspace = true }
```

### 5.3 测试依赖

```toml
[dev-dependencies]
assert_cmd = { workspace = true }        # CLI 测试断言
codex-utils-cargo-bin = { workspace = true }  # 二进制路径解析
pretty_assertions = { workspace = true } # 美观的断言输出
tempfile = { workspace = true }          # 临时目录
```

### 5.4 与其他组件的交互

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Codex CLI     │────▶│  apply_patch     │────▶│  File System    │
│  (codex-cli)    │     │  (codex-apply-   │     │                 │
│                 │     │   patch)         │     │                 │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                               │
                               ▼
                        ┌──────────────────┐
                        │  tree-sitter     │
                        │  (Bash parsing)  │
                        └──────────────────┘
```

---

## 6. 风险、边界与改进建议

### 6.1 当前风险

#### 6.1.1 部分应用风险

```rust
// lib.rs: apply_hunks_to_files
for hunk in hunks {
    match hunk {
        // 如果前面的 hunk 成功，后面的 hunk 失败
        // 已经应用的更改不会自动回滚
    }
}
```

**015_failure_after_partial_success_leaves_changes** 场景验证了此行为：当多个 hunk 中前面的成功、后面的失败时，已应用的更改会保留。

#### 6.1.2 模糊匹配风险

`seek_sequence` 的四级匹配策略（精确 → trim_end → trim → Unicode 规范化）虽然提高了补丁成功率，但也可能导致意外匹配。例如：

```
文件内容: "foo   "（带尾部空格）
补丁查找: "foo"
结果: 匹配成功（通过 trim_end 策略）
```

这可能不是用户期望的行为。

### 6.2 边界情况

| 场景 | 行为 | 测试覆盖 |
|------|------|----------|
| 空补丁 | 报错 "No files were modified." | 005_rejects_empty_patch |
| 更新不存在的文件 | 报错 "Failed to read file..." | 009_requires_existing_file_for_update |
| 删除不存在的文件 | 报错 "Failed to delete file..." | 007_rejects_missing_file_delete |
| 空更新块 | 报错 "Update file hunk...is empty" | 008_rejects_empty_update_hunk |
| 无效 hunk 头 | 报错 "is not a valid hunk header" | 013_rejects_invalid_hunk_header |
| 删除目录 | 报错 "Failed to delete file..." | 012_delete_directory_fails |

### 6.3 改进建议

#### 6.3.1 事务性应用

建议实现原子性应用机制：

```rust
// 伪代码
fn apply_hunks_atomically(hunks: &[Hunk]) -> Result<(), Error> {
    // 1. 预验证所有 hunks
    for hunk in hunks {
        hunk.validate()?;  // 提前检查所有上下文匹配
    }
    
    // 2. 创建备份
    let backups = create_backups(hunks)?;
    
    // 3. 应用所有 hunks
    match apply_all(hunks) {
        Ok(()) => { delete_backups(backups); Ok(()) }
        Err(e) => { restore_backups(backups); Err(e) }
    }
}
```

#### 6.3.2 增强错误信息

当前错误信息仅指出无法找到行，建议增加：
- 建议的相似行（使用编辑距离）
- 行号信息
- 搜索范围

```
当前: "Failed to find expected lines in modify.txt:\nmissing"
建议: "Failed to find expected lines in modify.txt at line 3:\n  expected: 'missing'\n  file has 2 lines, did you mean 'line2'?"
```

#### 6.3.3 模糊匹配可配置

建议添加 `--strict` 模式开关：

```rust
enum MatchMode {
    Strict,      // 仅精确匹配
    Normal,      // 精确 + trim_end
    Lenient,     // 精确 + trim_end + trim
    Fuzzy,       // 包含 Unicode 规范化
}
```

#### 6.3.4 补丁验证模式

建议添加 `--dry-run` 选项，仅验证补丁可应用性而不实际修改文件：

```rust
fn apply_patch(patch: &str, dry_run: bool) -> Result<ApplyPreview, Error> {
    // 返回预览结果，不实际写入
}
```

### 6.4 相关测试场景索引

| 场景 ID | 名称 | 目的 |
|---------|------|------|
| 001 | add_file | 验证文件创建 |
| 002 | multiple_operations | 验证多操作组合 |
| 003 | multiple_chunks | 验证多变更块 |
| 004 | move_to_new_directory | 验证文件移动 |
| 005 | rejects_empty_patch | 验证空补丁拒绝 |
| **006** | **rejects_missing_context** | **验证上下文不匹配拒绝** |
| 007 | rejects_missing_file_delete | 验证删除不存在文件拒绝 |
| 008 | rejects_empty_update_hunk | 验证空更新块拒绝 |
| 009 | requires_existing_file_for_update | 验证更新需文件存在 |
| 015 | failure_after_partial_success_leaves_changes | 验证部分失败行为 |

---

## 7. 总结

`006_rejects_missing_context` 场景是 `apply-patch` 工具测试套件中的关键负向测试，验证了工具在上下文匹配失败时的正确行为。通过 `seek_sequence` 的多级匹配算法和 `compute_replacements` 的错误处理，工具能够：

1. 检测到补丁中指定的 `missing` 行不存在于目标文件
2. 拒绝应用补丁
3. 保持文件原始状态不变
4. 输出清晰的错误信息

该测试场景与 `tests/suite/tool.rs` 中的 `test_apply_patch_cli_reports_missing_context` 测试用例共同确保了此行为的正确性。
