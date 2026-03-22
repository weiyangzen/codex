# 010_move_overwrites_existing_destination 场景研究文档

## 文件信息

- **目标文件**: `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/expected/renamed/dir/name.txt`
- **文件内容**: `new`
- **所属测试场景**: 010_move_overwrites_existing_destination
- **所属 Crate**: `codex-apply-patch`

---

## 1. 场景与职责

### 1.1 测试场景概述

本场景测试 `apply_patch` 工具的**文件移动覆盖**功能：当执行一个包含 `*** Move to:` 指令的 patch 时，如果目标位置已存在同名文件，patch 应该能够覆盖目标文件。

### 1.2 场景文件结构

```
010_move_overwrites_existing_destination/
├── patch.txt                    # Patch 操作定义
├── input/                       # 初始状态
│   ├── old/
│   │   ├── name.txt            # 源文件，内容为 "from"
│   │   └── other.txt           # 无关文件，内容为 "unrelated file"
│   └── renamed/
│       └── dir/
│           └── name.txt        # 目标位置已存在的文件，内容为 "existing"
└── expected/                    # 期望的最终状态
    ├── old/
    │   └── other.txt           # 保留，内容为 "unrelated file"
    └── renamed/
        └── dir/
            └── name.txt        # 被覆盖后的文件，内容为 "new" ← 目标文件
```

### 1.3 Patch 定义

```
*** Begin Patch
*** Update File: old/name.txt
*** Move to: renamed/dir/name.txt
@@
-from
+new
*** End Patch
```

### 1.4 场景职责

- 验证 `apply_patch` 在执行文件移动操作时，能够正确处理目标路径已存在文件的情况
- 验证源文件在移动后被正确删除
- 验证目标文件被新内容覆盖（而非追加或报错）
- 验证同一目录下的其他无关文件不受影响

---

## 2. 功能点目的

### 2.1 文件移动语义

在 `apply_patch` 的语义中，`*** Move to:` 指令与 `*** Update File:` 组合使用表示：
1. 读取源文件内容
2. 应用 patch 中定义的修改
3. 将修改后的内容写入目标路径
4. 删除源文件

### 2.2 覆盖行为的设计意图

- **幂等性**: 多次应用相同的 patch 应该产生一致的结果
- **原子性**: 移动操作应该是原子的，要么完全成功，要么完全失败
- **实用性**: 在代码重构场景中，经常需要将文件移动到新位置，而目标位置可能已经存在同名文件（如模板文件）

### 2.3 与其他场景的对比

| 场景 | 描述 | 差异点 |
|------|------|--------|
| 004_move_to_new_directory | 移动文件到新目录（目标不存在） | 目标目录不存在文件，无需覆盖 |
| 010_move_overwrites_existing_destination | 移动文件并覆盖已存在的目标 | 目标已存在文件，需要覆盖 |
| 011_add_overwrites_existing_file | 添加文件时覆盖已存在的文件 | 使用 Add File 而非 Update + Move |

---

## 3. 具体技术实现

### 3.1 关键流程

#### 3.1.1 Patch 解析流程

```rust
// parser.rs: parse_patch() -> parse_patch_text() -> parse_one_hunk()

pub fn parse_patch(patch: &str) -> Result<ApplyPatchArgs, ParseError> {
    let mode = if PARSE_IN_STRICT_MODE { ParseMode::Strict } else { ParseMode::Lenient };
    parse_patch_text(patch, mode)
}
```

对于本场景的 patch，解析器会：
1. 识别 `*** Update File: old/name.txt` → 创建 `UpdateFile` hunk
2. 识别 `*** Move to: renamed/dir/name.txt` → 设置 `move_path` 字段
3. 解析 `@@` 上下文标记和 diff 内容 → 创建 `UpdateFileChunk`

#### 3.1.2 Hunk 数据结构

```rust
// parser.rs: Hunk 枚举
pub enum Hunk {
    UpdateFile {
        path: PathBuf,           // old/name.txt
        move_path: Option<PathBuf>, // Some("renamed/dir/name.txt")
        chunks: Vec<UpdateFileChunk>,
    },
    // ...
}

pub struct UpdateFileChunk {
    pub change_context: Option<String>, // None (本场景使用空 @@)
    pub old_lines: Vec<String>,         // ["from"]
    pub new_lines: Vec<String>,         // ["new"]
    pub is_end_of_file: bool,           // false
}
```

#### 3.1.3 文件应用流程

```rust
// lib.rs: apply_hunks_to_files()
fn apply_hunks_to_files(hunks: &[Hunk]) -> anyhow::Result<AffectedPaths> {
    for hunk in hunks {
        match hunk {
            Hunk::UpdateFile { path, move_path, chunks } => {
                // 1. 计算新内容
                let AppliedPatch { new_contents, .. } = derive_new_contents_from_chunks(path, chunks)?;
                
                if let Some(dest) = move_path {
                    // 2. 创建目标目录（如果不存在）
                    if let Some(parent) = dest.parent() && !parent.as_os_str().is_empty() {
                        std::fs::create_dir_all(parent)?;
                    }
                    // 3. 写入目标文件（覆盖已存在的文件）
                    std::fs::write(dest, new_contents)?;
                    // 4. 删除源文件
                    std::fs::remove_file(path)?;
                    modified.push(dest.clone());
                }
            }
            // ...
        }
    }
}
```

### 3.2 关键代码路径

#### 3.2.1 覆盖行为的实现

覆盖行为的核心实现在 `lib.rs` 第 313-325 行：

```rust
// lib.rs:306-331
Hunk::UpdateFile {
    path,
    move_path,
    chunks,
} => {
    let AppliedPatch { new_contents, .. } = derive_new_contents_from_chunks(path, chunks)?;
    if let Some(dest) = move_path {
        if let Some(parent) = dest.parent()
            && !parent.as_os_str().is_empty()
        {
            std::fs::create_dir_all(parent).with_context(|| {
                format!("Failed to create parent directories for {}", dest.display())
            })?;
        }
        // 使用 std::fs::write 直接写入，如果文件已存在则覆盖
        std::fs::write(dest, new_contents)
            .with_context(|| format!("Failed to write file {}", dest.display()))?;
        std::fs::remove_file(path)
            .with_context(|| format!("Failed to remove original {}", path.display()))?;
        modified.push(dest.clone());
    } else {
        // ... 非移动情况
    }
}
```

**关键点**: `std::fs::write()` 在文件已存在时会**截断并覆盖**文件内容，这正是本场景期望的行为。

#### 3.2.2 内容计算流程

```rust
// lib.rs:346-381
derive_new_contents_from_chunks(path: &Path, chunks: &[UpdateFileChunk]) 
    -> Result<AppliedPatch, ApplyPatchError> {
    // 1. 读取源文件内容
    let original_contents = std::fs::read_to_string(path)?;
    
    // 2. 分割为行
    let mut original_lines: Vec<String> = original_contents.split('\n').map(String::from).collect();
    
    // 3. 移除末尾空行（与 diff 行为一致）
    if original_lines.last().is_some_and(String::is_empty) {
        original_lines.pop();
    }
    
    // 4. 计算替换
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

#### 3.2.3 替换计算逻辑

```rust
// lib.rs:386-474
compute_replacements(
    original_lines: &[String],
    path: &Path,
    chunks: &[UpdateFileChunk]
) -> Result<Vec<(usize, usize, Vec<String>)>, ApplyPatchError> {
    let mut replacements: Vec<(usize, usize, Vec<String>)> = Vec::new();
    let mut line_index: usize = 0;

    for chunk in chunks {
        // 1. 使用上下文定位（如果有）
        if let Some(ctx_line) = &chunk.change_context {
            if let Some(idx) = seek_sequence::seek_sequence(original_lines, std::slice::from_ref(ctx_line), line_index, false) {
                line_index = idx + 1;
            } else {
                return Err(ApplyPatchError::ComputeReplacements(format!(
                    "Failed to find context '{}' in {}", ctx_line, path.display()
                )));
            }
        }

        // 2. 定位 old_lines
        let pattern: &[String] = &chunk.old_lines;
        let found = seek_sequence::seek_sequence(original_lines, pattern, line_index, chunk.is_end_of_file);
        
        // 3. 处理末尾空行的特殊情况
        if found.is_none() && pattern.last().is_some_and(String::is_empty) {
            // 重试不带末尾空行
        }

        if let Some(start_idx) = found {
            replacements.push((start_idx, pattern.len(), new_slice.to_vec()));
            line_index = start_idx + pattern.len();
        } else {
            return Err(ApplyPatchError::ComputeReplacements(...));
        }
    }

    // 按索引排序，确保替换顺序正确
    replacements.sort_by(|(lhs_idx, _, _), (rhs_idx, _, _)| lhs_idx.cmp(rhs_idx));
    Ok(replacements)
}
```

### 3.3 数据结构

#### 3.3.1 核心数据结构关系

```
ApplyPatchArgs
├── patch: String              # 原始 patch 文本
├── hunks: Vec<Hunk>           # 解析后的 hunk 列表
└── workdir: Option<String>    # 工作目录

Hunk::UpdateFile
├── path: PathBuf              # 源文件路径
├── move_path: Option<PathBuf> # 目标路径（本场景为 Some）
└── chunks: Vec<UpdateFileChunk>
    ├── change_context: Option<String>  # 上下文标记
    ├── old_lines: Vec<String>          # 要替换的旧行
    ├── new_lines: Vec<String>          # 新行
    └── is_end_of_file: bool            # 是否文件末尾

ApplyPatchFileChange::Update
├── unified_diff: String       # 统一 diff 格式
├── move_path: Option<PathBuf> # 目标路径
└── new_content: String        # 最终内容
```

### 3.4 测试框架

#### 3.4.1 场景测试执行流程

```rust
// tests/suite/scenarios.rs: run_apply_patch_scenario()
fn run_apply_patch_scenario(dir: &Path) -> anyhow::Result<()> {
    let tmp = tempdir()?;

    // 1. 复制 input 到临时目录
    let input_dir = dir.join("input");
    copy_dir_recursive(&input_dir, tmp.path())?;

    // 2. 读取 patch.txt
    let patch = fs::read_to_string(dir.join("patch.txt"))?;

    // 3. 执行 apply_patch
    Command::new(codex_utils_cargo_bin::cargo_bin("apply_patch")?)
        .arg(patch)
        .current_dir(tmp.path())
        .output()?;

    // 4. 比较结果与 expected
    let expected_dir = dir.join("expected");
    let expected_snapshot = snapshot_dir(&expected_dir)?;
    let actual_snapshot = snapshot_dir(tmp.path())?;
    assert_eq!(actual_snapshot, expected_snapshot);

    Ok(())
}
```

#### 3.4.2 快照比较

```rust
// tests/suite/scenarios.rs: snapshot_dir()
#[derive(Debug, Clone, PartialEq, Eq)]
enum Entry {
    File(Vec<u8>),
    Dir,
}

fn snapshot_dir(root: &Path) -> anyhow::Result<BTreeMap<PathBuf, Entry>> {
    // 递归遍历目录，生成路径到内容的映射
    // 使用 BTreeMap 确保顺序一致
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心实现文件

| 文件 | 职责 | 相关行号 |
|------|------|----------|
| `lib.rs` | 核心 patch 应用逻辑 | 1-1000+ |
| `parser.rs` | Patch 语法解析 | 1-763 |
| `invocation.rs` | Shell 命令解析和验证 | 1-813 |
| `seek_sequence.rs` | 模糊匹配算法 | 1-151 |
| `standalone_executable.rs` | CLI 入口 | 1-59 |

### 4.2 关键函数调用链

```
main() [main.rs]
└── codex_apply_patch::main() [standalone_executable.rs]
    └── apply_patch() [lib.rs:183]
        ├── parse_patch() [parser.rs:106]
        │   └── parse_patch_text()
        │       └── parse_one_hunk()
        └── apply_hunks() [lib.rs:216]
            └── apply_hunks_to_files() [lib.rs:279]
                ├── derive_new_contents_from_chunks() [lib.rs:348]
                │   ├── compute_replacements() [lib.rs:386]
                │   │   └── seek_sequence::seek_sequence() [seek_sequence.rs:12]
                │   └── apply_replacements() [lib.rs:478]
                ├── std::fs::write() [覆盖目标文件]
                └── std::fs::remove_file() [删除源文件]
```

### 4.3 测试相关文件

| 文件 | 职责 |
|------|------|
| `tests/all.rs` | 测试入口 |
| `tests/suite/scenarios.rs` | 场景测试框架 |
| `tests/suite/cli.rs` | CLI 测试 |
| `tests/suite/tool.rs` | 工具函数测试 |
| `tests/fixtures/scenarios/` | 测试场景数据 |

---

## 5. 依赖与外部交互

### 5.1 外部依赖

```toml
# Cargo.toml
[dependencies]
anyhow = { workspace = true }           # 错误处理
similar = { workspace = true }          # 文本差异计算
thiserror = { workspace = true }        # 错误定义
tree-sitter = { workspace = true }      # Bash 脚本解析
tree-sitter-bash = { workspace = true } # Bash 语法
```

### 5.2 系统调用

本场景涉及的关键系统调用：

| 调用 | 用途 | 位置 |
|------|------|------|
| `std::fs::read_to_string()` | 读取源文件内容 | `lib.rs:352` |
| `std::fs::create_dir_all()` | 创建目标目录 | `lib.rs:317` |
| `std::fs::write()` | 写入/覆盖目标文件 | `lib.rs:321` |
| `std::fs::remove_file()` | 删除源文件 | `lib.rs:323` |

### 5.3 与其他 Crate 的交互

```
codex-apply-patch
├── codex-utils-cargo-bin (dev-dependency)  # 测试时定位二进制文件
└── 被以下 crate 依赖:
    ├── codex-core (可能)
    └── codex-cli (可能)
```

### 5.4 协议/格式

- **Patch 格式**: 自定义类 diff 格式，定义见 `apply_patch_tool_instructions.md`
- **Grammar**: 见 `parser.rs` 第 4-24 行的 Lark 语法定义

---

## 6. 风险、边界与改进建议

### 6.1 当前实现的风险

#### 6.1.1 数据丢失风险

**风险**: 文件移动操作会**无条件覆盖**目标位置的文件，没有备份或确认机制。

```rust
// lib.rs:321 - 直接写入，无备份
std::fs::write(dest, new_contents)?;
```

**影响**: 如果 patch 编写错误或目标文件包含重要数据，可能导致不可逆的数据丢失。

**缓解**: 测试场景 `010_move_overwrites_existing_destination` 明确验证了这一行为是设计意图。

#### 6.1.2 原子性问题

**风险**: 移动操作不是原子的。如果系统在 `write` 和 `remove_file` 之间崩溃，可能导致数据不一致（两个文件都存在或都不存在）。

#### 6.1.3 错误恢复

**风险**: 如果 patch 中的多个 hunk 中某个失败，已经应用的修改不会回滚。

```rust
// lib.rs:279-339
for hunk in hunks {
    match hunk {
        // 如果这里失败，之前已应用的 hunk 不会回滚
    }
}
```

### 6.2 边界情况

| 边界情况 | 当前行为 | 潜在问题 |
|----------|----------|----------|
| 目标文件是目录 | `std::fs::write` 会失败 | 错误信息可能不够清晰 |
| 源文件不存在 | `derive_new_contents_from_chunks` 会失败 | 错误处理正确 |
| 目标路径与源路径相同 | 文件被覆盖后删除 | 可能导致数据丢失 |
| 目标目录无写权限 | 返回 IO 错误 | 错误处理正确 |
| 跨文件系统移动 | 先写后删，非原子重命名 | 如果写入成功但删除失败，数据重复 |

### 6.3 改进建议

#### 6.3.1 添加覆盖确认机制

```rust
// 建议：添加覆盖检查
if dest.exists() && !force {
    return Err(ApplyPatchError::IoError(IoError {
        context: format!("Destination file already exists: {}", dest.display()),
        source: std::io::Error::new(std::io::ErrorKind::AlreadyExists, "file exists"),
    }));
}
```

#### 6.3.2 使用原子写入

```rust
// 建议：使用临时文件 + 重命名实现原子写入
let temp_path = dest.with_extension("tmp");
std::fs::write(&temp_path, new_contents)?;
std::fs::rename(&temp_path, dest)?; // 原子操作
```

#### 6.3.3 支持事务性回滚

```rust
// 建议：记录已应用的修改，失败时回滚
struct AppliedHunk {
    path: PathBuf,
    backup: Option<Vec<u8>>, // 原始内容备份
}

fn apply_hunks_to_files(hunks: &[Hunk]) -> Result<AffectedPaths> {
    let mut applied: Vec<AppliedHunk> = Vec::new();
    
    for hunk in hunks {
        match apply_hunk(hunk) {
            Ok(_) => applied.push(hunk.to_backup()),
            Err(e) => {
                // 回滚已应用的 hunk
                for backup in applied.iter().rev() {
                    restore_backup(backup)?;
                }
                return Err(e);
            }
        }
    }
    Ok(...)
}
```

#### 6.3.4 增强错误信息

当前错误信息：
```
Failed to write file /path/to/dest
```

建议增强为：
```
Failed to write file /path/to/dest while moving from /path/to/source: destination already exists and will be overwritten
```

### 6.4 测试覆盖建议

| 测试场景 | 优先级 | 说明 |
|----------|--------|------|
| 移动时目标为只读文件 | 高 | 验证权限错误处理 |
| 移动时目标为符号链接 | 中 | 验证链接处理行为 |
| 移动时源和目标在同一目录 | 低 | 验证基本重命名 |
| 并发移动同一文件 | 低 | 验证竞态条件处理 |
| 移动大文件 | 低 | 验证性能和内存使用 |

---

## 7. 总结

`010_move_overwrites_existing_destination` 场景验证了 `apply_patch` 工具的核心文件移动功能，特别是**覆盖已存在目标文件**的行为。该行为通过 `std::fs::write()` 实现，当目标文件存在时会无条件覆盖。

目标文件 `expected/renamed/dir/name.txt` 的内容为 `"new"`，这表示：
1. 源文件 `old/name.txt` 的内容 `"from"` 被替换为 `"new"`
2. 目标位置已存在的文件内容 `"existing"` 被覆盖
3. 最终只保留了修改后的内容 `"new"`

这一设计体现了 `apply_patch` 的实用主义哲学：在代码重构场景中，开发者通常希望新内容完全替代旧内容，而不是合并或报错。但同时也带来了数据丢失的风险，建议在使用时确保 patch 的正确性，或考虑添加 `--force` 等显式覆盖确认机制。
