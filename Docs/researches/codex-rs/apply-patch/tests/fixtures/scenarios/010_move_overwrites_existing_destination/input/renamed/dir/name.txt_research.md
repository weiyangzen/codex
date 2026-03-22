# Research: 010_move_overwrites_existing_destination Test Fixture

## 1. 场景与职责

### 1.1 文件定位
- **目标文件**: `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/input/renamed/dir/name.txt`
- **文件内容**: `existing`
- **所属测试场景**: `010_move_overwrites_existing_destination`

### 1.2 测试场景描述
该测试场景验证 `apply_patch` 工具在执行**文件移动（Move）**操作时的**覆盖行为**。具体场景为：
- 源文件 `old/name.txt` 存在，内容为 `from`
- 目标位置 `renamed/dir/name.txt` 已存在，内容为 `existing`
- 执行 Move 操作时，目标文件应被**覆盖**（而非报错或保留）

### 1.3 测试结构
```
010_move_overwrites_existing_destination/
├── input/
│   ├── old/name.txt          # 源文件 (内容: "from")
│   ├── old/other.txt         # 无关文件 (内容: "unrelated file")
│   └── renamed/dir/name.txt  # 目标位置已存在文件 (内容: "existing")
├── expected/
│   ├── old/other.txt         # 保持不变 (内容: "unrelated file")
│   └── renamed/dir/name.txt  # 被覆盖后内容 (内容: "new")
└── patch.txt                 # 补丁定义
```

---

## 2. 功能点目的

### 2.1 核心功能验证
该测试验证以下关键行为：

| 功能点 | 描述 |
|--------|------|
| **Move + Update 组合** | `*** Update File` 配合 `*** Move to` 实现文件移动并修改内容 |
| **目标文件覆盖** | 当目标路径已存在文件时，应静默覆盖（与 Unix `mv -f` 行为一致） |
| **内容原子性** | 移动后的文件内容应为补丁中指定的新内容 (`new`)，而非原目标文件内容 |
| **源文件删除** | 移动后源文件 `old/name.txt` 应被删除 |

### 2.2 补丁定义解析
```
*** Begin Patch
*** Update File: old/name.txt      # 指定源文件
*** Move to: renamed/dir/name.txt  # 指定目标路径
@@                                  # 变更上下文标记
-from                               # 旧内容行（以 - 开头）
+new                               # 新内容行（以 + 开头）
*** End Patch
```

---

## 3. 具体技术实现

### 3.1 关键流程

#### 3.1.1 Patch 解析流程
```rust
// parser.rs: parse_patch() -> parse_patch_text() -> parse_one_hunk()

1. 识别 "*** Begin Patch" 和 "*** End Patch" 边界
2. 解析文件操作类型: Update File (line 279-332 in parser.rs)
3. 提取可选的 Move 目标路径 (line 285-291)
4. 解析变更块 (chunk): 
   - `@@` 上下文标记
   - `-from` -> old_lines = ["from"]
   - `+new` -> new_lines = ["new"]
```

#### 3.1.2 文件操作执行流程
```rust
// lib.rs: apply_hunks_to_files() (line 279-339)

match hunk {
    Hunk::UpdateFile { path, move_path, chunks } => {
        // 1. 计算新内容
        let AppliedPatch { new_contents, .. } = derive_new_contents_from_chunks(path, chunks)?;
        
        // 2. 如果指定了 move_path
        if let Some(dest) = move_path {
            // 2.1 创建目标目录（如果不存在）
            std::fs::create_dir_all(parent)?;
            
            // 2.2 写入目标文件（直接覆盖，无存在性检查）
            std::fs::write(dest, new_contents)?;
            
            // 2.3 删除源文件
            std::fs::remove_file(path)?;
            
            modified.push(dest.clone());
        }
    }
}
```

### 3.2 核心数据结构

#### 3.2.1 Hunk 枚举（parser.rs:58-76）
```rust
pub enum Hunk {
    AddFile { path: PathBuf, contents: String },
    DeleteFile { path: PathBuf },
    UpdateFile {
        path: PathBuf,
        move_path: Option<PathBuf>,  // Move 目标路径
        chunks: Vec<UpdateFileChunk>,
    },
}
```

#### 3.2.2 UpdateFileChunk（parser.rs:90-104）
```rust
pub struct UpdateFileChunk {
    pub change_context: Option<String>,  // @@ 后的上下文
    pub old_lines: Vec<String>,          // 以 - 开头的行
    pub new_lines: Vec<String>,          // 以 + 开头的行
    pub is_end_of_file: bool,            // 是否以 "*** End of File" 结尾
}
```

#### 3.2.3 ApplyPatchFileChange（lib.rs:94-108）
```rust
pub enum ApplyPatchFileChange {
    Add { content: String },
    Delete { content: String },
    Update {
        unified_diff: String,
        move_path: Option<PathBuf>,  // 移动目标
        new_content: String,
    },
}
```

### 3.3 文本匹配算法

#### 3.3.1 seek_sequence（seek_sequence.rs:12-110）
用于在源文件中定位变更上下文，支持三级匹配策略：
1. **精确匹配**: 字节级完全匹配
2. **右侧空白忽略**: 比较时去除行尾空格
3. **双侧空白忽略**: 比较时去除行首行尾空格
4. **Unicode 归一化**: 将特殊 Unicode 标点（如智能引号、各种横线）转换为 ASCII 等价物

```rust
fn normalise(s: &str) -> String {
    s.trim()
        .chars()
        .map(|c| match c {
            // 各种横线/连字符 -> ASCII '-'
            '\u{2010}' | '\u{2011}' | '\u{2012}' | '\u{2013}' | '\u{2014}' | '\u{2015}'
            | '\u{2212}' => '-',
            // 智能引号 -> 普通引号
            '\u{2018}' | '\u{2019}' | '\u{201A}' | '\u{201B}' => '\'',
            '\u{201C}' | '\u{201D}' | '\u{201E}' | '\u{201F}' => '"',
            // 各种空格 -> 普通空格
            '\u{00A0}' | '\u{2002}' | ... => ' ',
            other => other,
        })
        .collect()
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心实现文件

| 文件路径 | 职责 |
|----------|------|
| `codex-rs/apply-patch/src/lib.rs` | Patch 应用主逻辑，`apply_hunks_to_files()` 实现文件操作 |
| `codex-rs/apply-patch/src/parser.rs` | Patch 语法解析，定义 `Hunk` 和 `UpdateFileChunk` 结构 |
| `codex-rs/apply-patch/src/seek_sequence.rs` | 模糊文本匹配算法，支持上下文定位 |
| `codex-rs/apply-patch/src/standalone_executable.rs` | CLI 入口，处理参数和 stdin |

### 4.2 关键代码位置

#### 4.2.1 Move 操作实现（lib.rs:306-330）
```rust
Hunk::UpdateFile { path, move_path, chunks } => {
    let AppliedPatch { new_contents, .. } = derive_new_contents_from_chunks(path, chunks)?;
    if let Some(dest) = move_path {
        // 创建目标目录
        if let Some(parent) = dest.parent() && !parent.as_os_str().is_empty() {
            std::fs::create_dir_all(parent)?;
        }
        // 写入目标（直接覆盖）
        std::fs::write(dest, new_contents)?;
        // 删除源文件
        std::fs::remove_file(path)?;
        modified.push(dest.clone());
    }
}
```

**关键观察**: 代码中没有检查目标文件是否存在的逻辑，直接调用 `std::fs::write()`，这天然实现了"覆盖"行为。

#### 4.2.2 Patch 解析中的 Move 提取（parser.rs:279-291）
```rust
// Optional: move file line
let move_path = remaining_lines
    .first()
    .and_then(|x| x.strip_prefix(MOVE_TO_MARKER));  // "*** Move to: "

if move_path.is_some() {
    remaining_lines = &remaining_lines[1..];
    parsed_lines += 1;
}
```

### 4.3 测试执行路径

```rust
// tests/suite/scenarios.rs:11-26
test_apply_patch_scenarios() 
  └── run_apply_patch_scenario(dir)
      ├── 复制 input/ 到临时目录
      ├── 读取 patch.txt
      ├── 执行: apply_patch <patch_content>
      └── 比较实际结果与 expected/ 目录
```

---

## 5. 依赖与外部交互

### 5.1 直接依赖（Cargo.toml）
```toml
[dependencies]
anyhow = { workspace = true }        # 错误处理
similar = { workspace = true }       # 文本差异计算（unified_diff）
thiserror = { workspace = true }     # 错误定义宏
tree-sitter = { workspace = true }   # Bash 脚本解析
tree-sitter-bash = { workspace = true }
```

### 5.2 上游调用方

| 调用方 | 用途 |
|--------|------|
| `codex-rs/core/src/tools/handlers/apply_patch.rs` | Core 层处理 apply_patch 工具调用 |
| `codex-rs/core/src/tools/runtimes/apply_patch.rs` | 运行时执行环境准备 |
| `codex-rs/core/src/apply_patch.rs` | 安全评估和审批流程 |
| `codex-rs/arg0/src/lib.rs` | 进程自调用参数分发 |

### 5.3 下游被调用方

| 被调用方 | 用途 |
|----------|------|
| `std::fs::write()` | 文件写入（覆盖） |
| `std::fs::remove_file()` | 源文件删除 |
| `std::fs::create_dir_all()` | 目标目录创建 |
| `tree_sitter::Parser` | Bash heredoc 解析 |

---

## 6. 风险、边界与改进建议

### 6.1 当前行为风险

| 风险点 | 描述 | 严重程度 |
|--------|------|----------|
| **无覆盖确认** | 目标文件存在时直接覆盖，无警告或备份 | 中 |
| **无原子性保证** | 写入和删除是独立操作，中间失败可能导致数据丢失 | 中 |
| **权限问题** | 目标目录无写权限时的错误处理依赖系统错误 | 低 |

### 6.2 边界情况

| 场景 | 当前行为 | 测试覆盖 |
|------|----------|----------|
| 目标文件存在 | 静默覆盖 | ✅ 本测试覆盖 |
| 目标目录不存在 | 自动创建 | ✅ 004_move_to_new_directory |
| 源文件不存在 | 报错 | ✅ 009_requires_existing_file_for_update |
| 目标路径是目录 | 写入失败（fs::write 报错） | ✅ 012_delete_directory_fails |
| 跨文件系统移动 | 复制+删除（非原子重命名） | ❌ 未明确测试 |

### 6.3 改进建议

#### 6.3.1 短期改进
1. **添加覆盖警告日志**: 在覆盖现有文件时输出警告信息到 stderr
2. **原子性优化**: 考虑使用临时文件 + 重命名策略减少数据丢失风险
3. **测试扩展**: 添加跨文件系统移动、符号链接目标等边界测试

#### 6.3.2 长期改进
1. **可选备份模式**: 支持 `--backup` 参数，覆盖前创建 `.bak` 文件
2. **交互式确认**: 在 TUI 模式下提供覆盖确认对话框
3. **冲突检测**: 检测并发修改场景，提供合并选项

### 6.4 相关测试场景

| 场景编号 | 描述 | 与 010 的关系 |
|----------|------|---------------|
| 004_move_to_new_directory | Move 到不存在的目录 | 基础 Move 功能 |
| 009_requires_existing_file_for_update | Update 要求源文件存在 | 前置条件验证 |
| 011_add_overwrites_existing_file | Add 操作覆盖现有文件 | 类似的覆盖行为 |
| 012_delete_directory_fails | 删除目录失败 | 边界错误处理 |

---

## 7. 总结

`010_move_overwrites_existing_destination` 测试场景验证了 `apply_patch` 工具在执行文件移动操作时的**覆盖语义**。目标文件 `renamed/dir/name.txt` 作为已存在的目标，在 Move 操作后应被源文件的新内容覆盖。

该测试确认了以下设计决策：
1. Move 操作默认采用**覆盖模式**（而非报错或跳过）
2. 目标目录不存在时**自动创建**
3. 源文件在成功写入目标后**被删除**

这种设计符合 Unix 工具链的常规行为（`mv -f`），但用户应注意数据覆盖风险。
