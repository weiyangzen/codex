# 研究文档：021_update_file_deletion_only 测试场景

## 场景与职责

### 目标文件
- **路径**: `codex-rs/apply-patch/tests/fixtures/scenarios/021_update_file_deletion_only/input/lines.txt`
- **内容**: 包含3行文本的简单文件
  ```
  line1
  line2
  line3
  ```

### 场景定位
这是 `apply-patch` 组件的第21个测试场景，专门测试 **Update File 操作中的纯删除功能** —— 即通过 `Update File` hunk 删除文件中特定行，而不添加任何新内容。

### 测试场景结构
```
021_update_file_deletion_only/
├── input/
│   └── lines.txt          # 被测试的原始文件（3行内容）
├── expected/
│   └── lines.txt          # 期望结果（删除line2后的2行内容）
└── patch.txt              # 应用补丁
```

---

## 功能点目的

### 核心功能
本场景验证 `apply_patch` 工具能够正确处理 **仅包含删除操作** 的 `Update File` hunk。具体来说：

1. **删除单行内容**: 从现有文件中删除特定行（`line2`）
2. **保留其他行**: 保持文件的其余部分不变（`line1` 和 `line3`）
3. **维持文件结构**: 确保删除后文件格式正确（保留换行符）

### 补丁内容分析
```
*** Begin Patch
*** Update File: lines.txt
@@
 line1
-line2
 line3
*** End Patch
```

关键要素：
- `@@`: 空上下文标记，表示不使用特定上下文定位
- ` line1`: 上下文行（空格前缀表示保留）
- `-line2`: 删除行（`-` 前缀表示删除）
- ` line3`: 上下文行

### 预期行为
| 输入文件 | 操作 | 输出文件 |
|---------|------|---------|
| line1<br>line2<br>line3 | 删除 line2 | line1<br>line3 |

---

## 具体技术实现

### 1. 关键流程

#### 1.1 补丁解析流程
```
patch.txt → parse_patch() → Vec<Hunk> → apply_hunks()
```

**解析阶段** (`parser.rs`):
1. `parse_patch()` - 验证补丁边界（`*** Begin Patch` / `*** End Patch`）
2. `parse_one_hunk()` - 识别 `*** Update File: lines.txt` 头部
3. `parse_update_file_chunk()` - 解析变更块：
   - 识别 `@@` 上下文标记
   - 解析 ` `（空格）前缀的上下文行
   - 解析 `-` 前缀的删除行
   - 无 `+` 前缀行（纯删除场景）

#### 1.2 应用补丁流程
```
apply_hunks() → apply_hunks_to_files() → derive_new_contents_from_chunks() 
→ compute_replacements() → apply_replacements()
```

**核心函数** (`lib.rs`):

| 函数 | 职责 | 行号 |
|-----|------|------|
| `apply_patch()` | 主入口，解析并应用补丁 | 183-213 |
| `apply_hunks()` | 批量应用 hunk | 216-266 |
| `apply_hunks_to_files()` | 文件系统操作 | 279-339 |
| `derive_new_contents_from_chunks()` | 计算新文件内容 | 348-381 |
| `compute_replacements()` | 计算替换区域 | 386-474 |
| `apply_replacements()` | 执行内容替换 | 478-502 |

#### 1.3 行定位算法
`seek_sequence()` (`seek_sequence.rs`):
```rust
pub(crate) fn seek_sequence(
    lines: &[String],
    pattern: &[String],
    start: usize,
    eof: bool,
) -> Option<usize>
```

匹配策略（按优先级）：
1. **精确匹配**: 字节级完全匹配
2. **右侧空白忽略**: 比较 `trim_end()` 结果
3. **双侧空白忽略**: 比较 `trim()` 结果
4. **Unicode 规范化**: 将特殊 Unicode 标点转为 ASCII 等价物

### 2. 数据结构

#### 2.1 Hunk 枚举 (`parser.rs` 第58-76行)
```rust
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

#### 2.2 UpdateFileChunk 结构 (`parser.rs` 第91-104行)
```rust
pub struct UpdateFileChunk {
    pub change_context: Option<String>,  // @@ 后的上下文
    pub old_lines: Vec<String>,          // - 前缀的行（待删除）
    pub new_lines: Vec<String>,          // + 前缀的行（待添加）
    pub is_end_of_file: bool,            // 是否以 *** End of File 结尾
}
```

本场景中：
- `change_context`: `None`（空 `@@`）
- `old_lines`: `["line1", "line2", "line3"]`（包含上下文和删除行）
- `new_lines`: `["line1", "line3"]`（删除后的内容）
- `is_end_of_file`: `false`

#### 2.3 替换操作元组
```rust
type Replacement = (usize, usize, Vec<String>);
// (start_index, old_len, new_lines)
```

本场景中计算出的替换：
```rust
(0, 3, vec!["line1".to_string(), "line3".to_string()])
// 从第0行开始，替换3行，新内容为 line1 + line3
```

### 3. 协议/格式规范

#### 3.1 Patch 语法 (EBNF)
```
Patch         := BeginPatch { Hunk } EndPatch
BeginPatch    := "*** Begin Patch" LF
EndPatch      := "*** End Patch" LF?

Hunk          := UpdateFileHunk | AddFileHunk | DeleteFileHunk
UpdateFileHunk:= "*** Update File: " path LF { ChangeChunk }
ChangeChunk   := ContextMarker { ChangeLine }
ContextMarker := "@@" [ context ] LF
ChangeLine    := (" " | "-" | "+") text LF
```

#### 3.2 行前缀语义
| 前缀 | 含义 | 存储位置 |
|-----|------|---------|
| ` ` (空格) | 上下文行（保留） | `old_lines` + `new_lines` |
| `-` | 删除行 | `old_lines` |
| `+` | 添加行 | `new_lines` |

### 4. 命令接口

#### 4.1 CLI 用法
```bash
# 直接参数
apply_patch "*** Begin Patch\n*** Update File: lines.txt\n...\n*** End Patch"

# 标准输入
echo "*** Begin Patch..." | apply_patch
```

#### 4.2 程序入口 (`standalone_executable.rs`)
```rust
pub fn run_main() -> i32 {
    // 1. 从参数或 stdin 读取 patch
    // 2. 调用 apply_patch()
    // 3. 返回 exit code (0=成功, 1=失败, 2=用法错误)
}
```

---

## 关键代码路径与文件引用

### 核心实现文件

| 文件 | 职责 | 关键行号 |
|-----|------|---------|
| `src/lib.rs` | 补丁应用核心逻辑 | 1-1074 |
| `src/parser.rs` | Patch 语法解析器 | 1-763 |
| `src/seek_sequence.rs` | 模糊行匹配算法 | 1-151 |
| `src/standalone_executable.rs` | CLI 入口 | 1-59 |
| `src/invocation.rs` | Shell 命令解析 | 1-813 |

### 本场景涉及的具体代码路径

```
test_apply_patch_scenarios() [tests/suite/scenarios.rs:11]
    └── run_apply_patch_scenario()
        ├── 读取 input/lines.txt
        ├── 读取 patch.txt
        ├── Command::new("apply_patch").arg(patch).current_dir(tmp)
        │   └── standalone_executable::run_main()
        │       └── apply_patch()
        │           ├── parse_patch() [parser.rs:106]
        │           │   └── parse_update_file_chunk()
        │           └── apply_hunks()
        │               ├── derive_new_contents_from_chunks() [lib.rs:348]
        │               │   ├── fs::read_to_string(path) -> original
        │               │   ├── compute_replacements() [lib.rs:386]
        │               │   │   └── seek_sequence::seek_sequence() [seek_sequence.rs:12]
        │               │   └── apply_replacements() [lib.rs:478]
        │               └── fs::write(path, new_contents)
        └── 对比 expected/lines.txt
```

### 测试框架代码

**场景测试** (`tests/suite/scenarios.rs`):
```rust
fn run_apply_patch_scenario(dir: &Path) -> anyhow::Result<()> {
    let tmp = tempdir()?;
    // 复制 input 到临时目录
    copy_dir_recursive(&dir.join("input"), tmp.path())?;
    // 读取并应用补丁
    let patch = fs::read_to_string(dir.join("patch.txt"))?;
    Command::new("apply_patch").arg(patch).current_dir(tmp.path()).output()?;
    // 对比 expected
    assert_eq!(actual_snapshot, expected_snapshot);
}
```

---

## 依赖与外部交互

### 1. 内部依赖

```
codex-apply-patch/
├── codex_utils_cargo_bin (测试工具)
├── similar (文本差异计算)
├── tree-sitter (Bash 脚本解析)
└── tree-sitter-bash
```

### 2. 外部 crate 依赖

| Crate | 用途 | 版本来源 |
|-------|------|---------|
| `anyhow` | 错误处理 | workspace |
| `similar` | Unified diff 生成 | workspace |
| `thiserror` | 错误类型定义 | workspace |
| `tree-sitter` | Shell 脚本 AST 解析 | workspace |
| `tree-sitter-bash` | Bash 语法支持 | workspace |

### 3. 系统交互

| 操作 | 系统调用 | 用途 |
|-----|---------|------|
| 文件读取 | `std::fs::read_to_string` | 读取原始文件 |
| 文件写入 | `std::fs::write` | 写入修改后内容 |
| 目录创建 | `std::fs::create_dir_all` | 创建父目录 |
| 文件删除 | `std::fs::remove_file` | DeleteFile hunk |

### 4. 调用方与被调用方

#### 调用方
- **Codex CLI**: 通过 `apply_patch` 命令调用
- **测试框架**: `tests/suite/scenarios.rs` 中的 `test_apply_patch_scenarios()`
- **集成测试**: `tests/suite/tool.rs` 中的 CLI 测试

#### 被调用方
- **Parser 模块**: `parser.rs` 解析补丁格式
- **Seek 模块**: `seek_sequence.rs` 行定位算法
- **Invocation 模块**: `invocation.rs` 处理 shell 包装

---

## 风险、边界与改进建议

### 1. 潜在风险

#### 1.1 行定位模糊性
**风险**: 空 `@@` 上下文（如本场景）依赖顺序匹配，如果文件中有重复行可能导致误匹配。

**示例风险场景**:
```
# 原始文件
line1
line2
line1  # 重复行
line3

# 补丁尝试删除第二个 line1，但可能匹配到第一个
```

**缓解措施**: 
- 使用 `@@ 上下文` 精确定位（如 `@@ line2`）
- `seek_sequence` 的多级匹配策略（精确→rstrip→trim→Unicode）

#### 1.2 并发修改
**风险**: 补丁应用非原子操作，进程崩溃可能导致文件损坏。

**代码分析** (`lib.rs` 第327行):
```rust
std::fs::write(path, new_contents)  // 直接覆盖，无备份
```

#### 1.3 大文件性能
**风险**: `apply_replacements()` 使用 `Vec::remove` 和 `Vec::insert`，时间复杂度 O(n²)。

**代码位置** (`lib.rs` 第489-498行):
```rust
for _ in 0..old_len {
    if start_idx < lines.len() {
        lines.remove(start_idx);  // O(n) 操作
    }
}
for (offset, new_line) in new_segment.iter().enumerate() {
    lines.insert(start_idx + offset, new_line.clone());  // O(n) 操作
}
```

### 2. 边界情况

| 边界情况 | 当前行为 | 测试覆盖 |
|---------|---------|---------|
| 删除最后一行 | 支持（需处理 trailing newline） | 场景022 |
| 删除所有行 | 产生空文件（仅含换行符） | 未明确覆盖 |
| 空文件更新 | 报错（找不到匹配行） | 未明确覆盖 |
| 不存在的文件 | 报错（I/O error） | 场景009 |
| 重复行匹配 | 匹配首次出现 | 依赖 seek_sequence |
| Unicode 内容 | 支持（UTF-8） | 场景019 |

### 3. 改进建议

#### 3.1 原子写入
```rust
// 建议：使用临时文件 + rename 实现原子写入
let tmp_path = path.with_extension(".tmp");
std::fs::write(&tmp_path, new_contents)?;
std::fs::rename(&tmp_path, path)?;  // 原子操作
```

#### 3.2 性能优化
对于大文件，考虑使用 `im::Vector` 或分段处理替代 `Vec` 的频繁 `remove`/`insert`。

#### 3.3 增强定位精度
为纯删除场景添加 `@@` 上下文最佳实践文档：
```
# 推荐：使用上下文精确定位
*** Update File: lines.txt
@@ line1
 line1
-line2
 line3
```

#### 3.4 备份机制
添加可选的 `.bak` 备份功能：
```rust
if should_backup {
    std::fs::copy(path, path.with_extension("bak"))?;
}
```

#### 3.5 冲突检测
当前实现无冲突检测。多 hunk 修改同一块区域时，行为未定义：
```rust
// 潜在问题：两个 chunk 都修改 line2
@@
 line1
-line2
+newA
@@
 line1
-line2
+newB
```

建议添加重叠检测：
```rust
// 在 compute_replacements 中检查替换区域是否重叠
for i in 0..replacements.len() {
    for j in (i+1)..replacements.len() {
        if ranges_overlap(replacements[i], replacements[j]) {
            return Err(ApplyPatchError::OverlappingReplacements);
        }
    }
}
```

### 4. 测试覆盖建议

| 建议新增场景 | 目的 |
|-------------|------|
| 删除首行 | 验证边界索引处理 |
| 删除末行（无 trailing newline） | 验证 EOF 处理 |
| 删除所有行 | 验证空文件生成 |
| 多 chunk 删除不相邻行 | 验证多区域替换 |
| 大文件（>10k 行） | 性能基准测试 |

---

## 总结

`021_update_file_deletion_only` 是一个聚焦 **纯删除操作** 的基础测试场景，验证了 `apply-patch` 组件的核心能力：

1. **解析**: 正确识别无上下文的 `@@` 标记和 `-` 前缀删除行
2. **定位**: 通过 `seek_sequence` 找到匹配行序列
3. **替换**: 正确计算并应用删除操作
4. **输出**: 生成格式正确的结果文件

该场景虽然简单，但覆盖了 `UpdateFile` hunk 的核心代码路径，是理解补丁应用机制的良好切入点。
