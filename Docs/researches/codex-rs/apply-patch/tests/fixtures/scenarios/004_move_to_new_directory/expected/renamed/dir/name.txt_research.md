# 研究文档：004_move_to_new_directory 测试场景

## 目标文件

- **文件路径**: `codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/expected/renamed/dir/name.txt`
- **文件内容**: `new content`

---

## 1. 场景与职责

### 1.1 测试场景概述

该文件是 `apply-patch` 工具的端到端测试场景 **004_move_to_new_directory** 的**预期输出文件**。此场景专门测试以下复合操作：

1. **文件移动**: 将文件从 `old/name.txt` 移动到 `renamed/dir/name.txt`
2. **目录自动创建**: 在移动过程中自动创建目标目录 `renamed/dir/`
3. **内容更新**: 在移动的同时更新文件内容（从 `old content` 变为 `new content`）
4. **源文件清理**: 移动后删除原始位置的文件

### 1.2 场景目录结构

```
004_move_to_new_directory/
├── input/
│   └── old/
│       ├── name.txt      # 原始文件，内容为 "old content"
│       └── other.txt     # 无关文件，内容为 "unrelated file"
├── expected/
│   ├── old/
│   │   └── other.txt     # 预期保留的无关文件
│   └── renamed/
│       └── dir/
│           └── name.txt  # 目标文件，内容为 "new content" ← 本研究目标
└── patch.txt             # 补丁定义
```

### 1.3 职责边界

| 组件 | 职责 |
|------|------|
| `patch.txt` | 定义补丁操作（Update File + Move to + 内容变更） |
| `input/` | 提供测试前的初始文件系统状态 |
| `expected/` | 定义应用补丁后的预期文件系统状态 |
| `name.txt`（目标文件） | 验证文件移动+内容更新的复合操作结果 |

---

## 2. 功能点目的

### 2.1 核心功能验证

该测试场景验证 `apply-patch` 工具的以下核心能力：

#### 2.1.1 文件移动语义（Move Semantics）

`apply-patch` 支持在 `*** Update File:` 操作后紧跟 `*** Move to:` 指令，实现"更新并移动"的原子操作：

```
*** Update File: old/name.txt
*** Move to: renamed/dir/name.txt
@@
-old content
+new content
```

这种设计允许在一次补丁操作中同时完成：
- 读取源文件内容
- 应用内容变更
- 将结果写入新位置
- 删除源文件

#### 2.1.2 目录自动创建

当目标路径 `renamed/dir/name.txt` 的父目录不存在时，工具必须自动创建缺失的目录层级。这是通过 `std::fs::create_dir_all()` 实现的。

#### 2.1.3 内容一致性保证

目标文件 `name.txt` 的内容 `"new content"` 验证了：
- 补丁中的 `-old content` 和 `+new content` 差异被正确应用
- 文件内容在移动过程中保持一致性

### 2.2 测试覆盖范围

该场景覆盖了以下代码路径（详见第4节）：

| 代码路径 | 覆盖功能 |
|---------|---------|
| `parser.rs:279-331` | 解析 `*** Move to:` 指令 |
| `lib.rs:306-330` | 处理带移动路径的 UpdateFile hunk |
| `lib.rs:313-320` | 自动创建目标目录 |
| `lib.rs:321-324` | 写入新位置并删除源文件 |

---

## 3. 具体技术实现

### 3.1 补丁格式解析

#### 3.1.1 解析器数据结构

```rust
// parser.rs:68-76
pub enum Hunk {
    AddFile { path: PathBuf, contents: String },
    DeleteFile { path: PathBuf },
    UpdateFile {
        path: PathBuf,
        move_path: Option<PathBuf>,  // ← 移动目标路径
        chunks: Vec<UpdateFileChunk>,
    },
}
```

#### 3.1.2 Move To 解析逻辑

```rust
// parser.rs:284-292
let move_path = remaining_lines
    .first()
    .and_then(|x| x.strip_prefix(MOVE_TO_MARKER));  // "*** Move to: "

if move_path.is_some() {
    remaining_lines = &remaining_lines[1..];
    parsed_lines += 1;
}
```

### 3.2 文件操作执行流程

#### 3.2.1 核心执行逻辑（lib.rs:306-330）

```rust
Hunk::UpdateFile { path, move_path, chunks } => {
    // 1. 计算新内容
    let AppliedPatch { new_contents, .. } = derive_new_contents_from_chunks(path, chunks)?;
    
    if let Some(dest) = move_path {
        // 2. 创建目标目录（如果不存在）
        if let Some(parent) = dest.parent() && !parent.as_os_str().is_empty() {
            std::fs::create_dir_all(parent)?;
        }
        
        // 3. 写入新位置
        std::fs::write(dest, new_contents)?;
        
        // 4. 删除源文件
        std::fs::remove_file(path)?;
        
        modified.push(dest.clone());
    } else {
        // 无移动操作，直接覆盖源文件
        std::fs::write(path, new_contents)?;
        modified.push(path.clone());
    }
}
```

#### 3.2.2 执行时序图

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Patch.txt  │────▶│   Parser    │────▶│  Hunk::     │
│             │     │             │     │  UpdateFile │
└─────────────┘     └─────────────┘     └──────┬──────┘
                                               │
                                               ▼
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Delete     │◀────│  Write to   │◀────│ Create dirs │
│  original   │     │  dest       │     │ if needed   │
└─────────────┘     └─────────────┘     └─────────────┘
```

### 3.3 内容差异计算

#### 3.3.1 差异应用流程

```rust
// lib.rs:346-381
fn derive_new_contents_from_chunks(path: &Path, chunks: &[UpdateFileChunk]) 
    -> Result<AppliedPatch, ApplyPatchError> 
{
    // 1. 读取原始文件
    let original_contents = std::fs::read_to_string(path)?;
    
    // 2. 按行分割
    let mut original_lines: Vec<String> = original_contents.split('\n').map(String::from).collect();
    
    // 3. 移除末尾空行（与标准 diff 行为一致）
    if original_lines.last().is_some_and(String::is_empty) {
        original_lines.pop();
    }
    
    // 4. 计算替换区域
    let replacements = compute_replacements(&original_lines, path, chunks)?;
    
    // 5. 应用替换
    let new_lines = apply_replacements(original_lines, &replacements);
    
    // 6. 确保末尾有换行符
    if !new_lines.last().is_some_and(String::is_empty) {
        new_lines.push(String::new());
    }
    
    let new_contents = new_lines.join("\n");
    Ok(AppliedPatch { original_contents, new_contents })
}
```

#### 3.3.2 替换计算算法

```rust
// lib.rs:386-474
fn compute_replacements(
    original_lines: &[String],
    path: &Path,
    chunks: &[UpdateFileChunk],
) -> Result<Vec<(usize, usize, Vec<String>)>, ApplyPatchError> 
{
    let mut replacements: Vec<(usize, usize, Vec<String>)> = Vec::new();
    let mut line_index: usize = 0;

    for chunk in chunks {
        // 1. 使用上下文定位（如果有 @@ 标记）
        if let Some(ctx_line) = &chunk.change_context {
            line_index = seek_sequence(original_lines, &[ctx_line.clone()], line_index, false)?
                .map(|idx| idx + 1)
                .ok_or_else(|| ApplyPatchError::ComputeReplacements(...))?;
        }

        // 2. 查找 old_lines 在文件中的位置
        let pattern = &chunk.old_lines;
        let start_idx = seek_sequence(original_lines, pattern, line_index, chunk.is_end_of_file)
            .ok_or_else(|| ApplyPatchError::ComputeReplacements(...))?;

        // 3. 记录替换操作 (起始索引, 旧行数, 新行内容)
        replacements.push((start_idx, pattern.len(), chunk.new_lines.clone()));
        line_index = start_idx + pattern.len();
    }

    // 4. 按索引排序，确保替换顺序正确
    replacements.sort_by(|(a, _, _), (b, _, _)| a.cmp(b));
    Ok(replacements)
}
```

### 3.4 序列匹配算法（seek_sequence）

`seek_sequence.rs` 实现了模糊匹配算法，支持四级匹配策略：

```rust
pub(crate) fn seek_sequence(
    lines: &[String],
    pattern: &[String],
    start: usize,
    eof: bool,
) -> Option<usize> 
{
    // Level 1: EOF 模式优先从文件末尾开始匹配
    let search_start = if eof && lines.len() >= pattern.len() {
        lines.len() - pattern.len()
    } else {
        start
    };

    // Level 2: 精确匹配
    for i in search_start..=lines.len().saturating_sub(pattern.len()) {
        if lines[i..i + pattern.len()] == *pattern {
            return Some(i);
        }
    }

    // Level 3: 忽略行尾空白匹配
    for i in search_start..=lines.len().saturating_sub(pattern.len()) {
        if lines[i..i + pattern.len()].iter().zip(pattern)
            .all(|(a, b)| a.trim_end() == b.trim_end()) {
            return Some(i);
        }
    }

    // Level 4: 忽略首尾空白匹配
    for i in search_start..=lines.len().saturating_sub(pattern.len()) {
        if lines[i..i + pattern.len()].iter().zip(pattern)
            .all(|(a, b)| a.trim() == b.trim()) {
            return Some(i);
        }
    }

    // Level 5: Unicode 标点符号归一化匹配
    // 将各种 Unicode 连字符、引号归一化为 ASCII 等价物
    for i in search_start..=lines.len().saturating_sub(pattern.len()) {
        if lines[i..i + pattern.len()].iter().zip(pattern)
            .all(|(a, b)| normalise(a) == normalise(b)) {
            return Some(i);
        }
    }

    None
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心源文件

| 文件 | 行数 | 职责 |
|------|------|------|
| `lib.rs` | 1000+ | 补丁应用主逻辑、差异计算、文件操作 |
| `parser.rs` | 763 | 补丁格式解析、Hunk 提取 |
| `seek_sequence.rs` | 151 | 模糊序列匹配算法 |
| `invocation.rs` | 813 | 命令行参数解析、heredoc 处理 |
| `standalone_executable.rs` | 59 | CLI 入口点 |

### 4.2 关键代码路径

#### 4.2.1 补丁解析路径

```
parse_patch() [parser.rs:106]
    └── parse_patch_text() [parser.rs:154]
        └── check_patch_boundaries_strict/lenient() [parser.rs:187-224]
        └── parse_one_hunk() [parser.rs:248-341]
            └── 解析 *** Update File: [parser.rs:279]
            └── 解析 *** Move to: [parser.rs:285-292]
            └── parse_update_file_chunk() [parser.rs:343-434]
```

#### 4.2.2 补丁应用路径

```
apply_patch() [lib.rs:183]
    └── apply_hunks() [lib.rs:216]
        └── apply_hunks_to_files() [lib.rs:279]
            └── derive_new_contents_from_chunks() [lib.rs:348]
                └── compute_replacements() [lib.rs:386]
                    └── seek_sequence::seek_sequence() [seek_sequence.rs:12]
                └── apply_replacements() [lib.rs:478]
            └── 文件移动操作 [lib.rs:313-324]
```

#### 4.2.3 测试执行路径

```
test_apply_patch_scenarios() [tests/suite/scenarios.rs:11]
    └── run_apply_patch_scenario() [tests/suite/scenarios.rs:30]
        ├── copy_dir_recursive() [tests/suite/scenarios.rs:107]
        ├── Command::new(apply_patch) [tests/suite/scenarios.rs:45]
        └── snapshot_dir() [tests/suite/scenarios.rs:71]
            └── 比较 actual vs expected [tests/suite/scenarios.rs:55-60]
```

### 4.3 相关测试文件

| 测试文件 | 测试函数 | 覆盖场景 |
|---------|---------|---------|
| `tests/suite/scenarios.rs` | `test_apply_patch_scenarios` | 所有场景测试（包括004） |
| `tests/suite/tool.rs` | `test_apply_patch_cli_moves_file_to_new_directory` | 显式移动测试 |
| `lib.rs` (内联测试) | `test_update_file_hunk_can_move_file` | 单元测试 |
| `invocation.rs` (内联测试) | `test_apply_patch_resolves_move_path_with_effective_cwd` | 路径解析测试 |

---

## 5. 依赖与外部交互

### 5.1 外部依赖

```toml
# Cargo.toml
[dependencies]
anyhow = { workspace = true }           # 错误处理
similar = { workspace = true }          # 文本差异计算（unified diff）
thiserror = { workspace = true }        # 错误类型定义
tree-sitter = { workspace = true }      # Bash 脚本解析
tree-sitter-bash = { workspace = true } # Bash 语法定义

[dev-dependencies]
assert_cmd = { workspace = true }       # CLI 测试断言
codex-utils-cargo-bin = { workspace = true }  # 二进制文件定位
pretty_assertions = { workspace = true } # 测试输出美化
tempfile = { workspace = true }         # 临时目录创建
```

### 5.2 系统交互

| 系统调用 | 用途 | 代码位置 |
|---------|------|---------|
| `std::fs::create_dir_all` | 创建目标目录 | `lib.rs:317` |
| `std::fs::write` | 写入文件内容 | `lib.rs:321`, `lib.rs:327` |
| `std::fs::remove_file` | 删除源文件 | `lib.rs:323` |
| `std::fs::read_to_string` | 读取原始文件 | `lib.rs:352` |
| `std::fs::metadata` | 检查文件存在性 | `lib.rs:233` |

### 5.3 与其他组件的集成

```
┌─────────────────────────────────────────────────────────────┐
│                      Codex CLI / TUI                        │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│               codex-apply-patch (library)                   │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │   parser    │  │  lib.rs     │  │   invocation.rs     │  │
│  │  (解析补丁)  │  │ (应用补丁)   │  │ (参数/heredoc处理)   │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                    apply_patch (binary)                     │
└─────────────────────────────────────────────────────────────┘
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 部分成功问题

当前实现中，如果多个 hunk 中的某一个失败，之前的 hunk 已经应用的修改**不会回滚**。这可能导致文件系统处于不一致状态。

```rust
// lib.rs:279-339
for hunk in hunks {
    match hunk {
        // 如果第N个hunk失败，前N-1个hunk的修改已生效
        Hunk::UpdateFile { ... } => { ... }
    }
}
```

**缓解措施**: 场景 `015_failure_after_partial_success_leaves_changes` 明确测试并记录了此行为。

#### 6.1.2 目录与文件同名冲突

如果目标路径 `renamed/dir/name.txt` 中的 `dir` 已存在且是一个**文件**（而非目录），`create_dir_all` 将失败。

#### 6.1.3 跨文件系统移动

`std::fs::remove_file` + `std::fs::write` 的组合不是原子操作。如果进程在写入后、删除前崩溃，可能导致文件重复。

### 6.2 边界情况

| 边界情况 | 当前行为 | 测试覆盖 |
|---------|---------|---------|
| 目标目录已存在 | 正常处理 | 是（隐含） |
| 目标文件已存在 | 覆盖写入 | 场景 `010_move_overwrites_existing_destination` |
| 源文件不存在 | 报错 | 场景 `009_requires_existing_file_for_update` |
| 移动到同一位置 | 相当于更新 | 未明确测试 |
| 移动到子目录（源是目标祖先） | 可能出错 | 未测试 |

### 6.3 改进建议

#### 6.3.1 事务性应用

实现两阶段提交：
1. 预验证阶段：检查所有 hunk 是否可以应用
2. 执行阶段：应用所有更改，或全部回滚

#### 6.3.2 原子性文件移动

使用临时文件 + 原子重命名：

```rust
// 建议改进
let temp_path = dest.with_extension(".tmp");
std::fs::write(&temp_path, new_contents)?;
std::fs::rename(&temp_path, &dest)?;  // 原子操作
std::fs::remove_file(path)?;
```

#### 6.3.3 增强错误信息

当前错误信息在批量操作时难以定位问题：

```
// 当前
Failed to find expected lines in old/name.txt:
old content

// 建议
[004_move_to_new_directory/old/name.txt:1] Failed to find expected lines:
  Expected: "old content"
  Actual:   "different content"
```

#### 6.3.4 路径遍历防护

虽然当前实现要求相对路径，但应显式检查并拒绝 `../` 等路径遍历尝试：

```rust
// 建议添加
if path.components().any(|c| matches!(c, std::path::Component::ParentDir)) {
    return Err(ApplyPatchError::InvalidPath("Path traversal not allowed"));
}
```

### 6.4 测试覆盖建议

| 建议添加的测试场景 | 目的 |
|-------------------|------|
| 移动到已存在的目录 | 验证目录存在性检查 |
| 跨多层级目录移动 | 验证 `create_dir_all` 的递归行为 |
| 移动同时修改权限 | 测试文件权限保持（如果适用） |
| 并发补丁应用 | 测试线程安全性 |

---

## 7. 总结

目标文件 `name.txt`（内容 `"new content"`）是 `apply-patch` 工具**文件移动+内容更新**复合功能的验证锚点。它位于测试场景的预期输出目录中，与输入目录中的 `old/name.txt` 形成对比，完整验证了以下能力：

1. ✅ 补丁格式解析（`*** Move to:` 指令）
2. ✅ 差异计算与内容替换
3. ✅ 目标目录自动创建
4. ✅ 文件原子性移动（写入新位置+删除旧位置）
5. ✅ 无关文件保留（`other.txt` 未被影响）

该测试场景是 `apply-patch` 工具 25 个端到端测试场景中的关键一环，确保了工具在处理复杂文件重构操作时的可靠性。

---

*文档生成时间: 2026-03-22*
*基于代码版本: codex-rs/apply-patch (commit 未追踪)*
