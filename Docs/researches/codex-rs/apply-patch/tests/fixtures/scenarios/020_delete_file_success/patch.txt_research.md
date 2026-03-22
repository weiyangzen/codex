# Research: 020_delete_file_success/patch.txt

## 场景与职责

### 文件定位
- **目标文件**: `codex-rs/apply-patch/tests/fixtures/scenarios/020_delete_file_success/patch.txt`
- **所属模块**: `codex-apply-patch` crate
- **测试场景**: 文件删除成功场景（编号020）

### 场景描述
该测试用例验证 `apply_patch` 工具能够正确删除一个已存在的文件。场景设计如下：

| 组件 | 内容 |
|------|------|
| **输入目录** (`input/`) | 包含 `keep.txt` 和 `obsolete.txt` 两个文件 |
| **补丁文件** (`patch.txt`) | 指示删除 `obsolete.txt` |
| **期望目录** (`expected/`) | 仅包含 `keep.txt`，`obsolete.txt` 应被删除 |

### 核心职责
1. **验证文件删除功能**: 确保 `apply_patch` 能正确解析并执行 `*** Delete File:` 指令
2. **验证补丁格式**: 确认最简单的补丁格式（仅包含删除操作）能被正确处理
3. **集成测试**: 作为 scenario-based 测试套件的一部分，验证端到端文件系统操作

---

## 功能点目的

### 补丁格式语义
```
*** Begin Patch
*** Delete File: obsolete.txt
*** End Patch
```

该补丁表达以下意图：
- `*** Begin Patch` / `*** End Patch`: 补丁边界标记
- `*** Delete File: <path>`: 文件删除指令，`<path>` 为相对路径

### 功能目标
1. **原子性文件删除**: 通过标准库 `std::fs::remove_file` 删除指定文件
2. **路径解析**: 将补丁中的相对路径解析为工作目录下的绝对路径
3. **结果报告**: 在成功摘要中标记删除操作（`D` 前缀）

### 与其他操作的关系
`apply_patch` 支持三种文件操作，本场景专注于 **Delete** 操作：

| 操作类型 | 语法标记 | 用途 |
|---------|---------|------|
| Add | `*** Add File:` | 创建新文件 |
| **Delete** | `*** Delete File:` | **删除现有文件** |
| Update | `*** Update File:` | 修改文件内容（可选移动） |

---

## 具体技术实现

### 关键流程

#### 1. 补丁解析流程（Parser）
```rust
// parser.rs:271-278
} else if let Some(path) = first_line.strip_prefix(DELETE_FILE_MARKER) {
    // Delete File
    return Ok((
        DeleteFile {
            path: PathBuf::from(path),
        },
        1,  // Delete hunk 只占一行
    ));
}
```

**解析特点**:
- 使用 `strip_prefix` 匹配 `*** Delete File: ` 前缀
- 路径直接转换为 `PathBuf`，保留原始格式
- 删除操作不包含额外内容行，因此只消耗 1 行

#### 2. 补丁应用流程（Apply）
```rust
// lib.rs:301-304
Hunk::DeleteFile { path } => {
    std::fs::remove_file(path)
        .with_context(|| format!("Failed to delete file {}", path.display()))?;
    deleted.push(path.clone());
}
```

**执行细节**:
- 调用 `std::fs::remove_file` 执行实际删除
- 使用 `with_context` 增强错误信息，包含失败文件路径
- 将删除的文件路径加入 `deleted` 向量，用于后续摘要输出

#### 3. 结果摘要输出
```rust
// lib.rs:536-551 (print_summary 函数)
for path in &affected.deleted {
    writeln!(out, "D {}", path.display())?;
}
```

输出格式遵循类 Git 风格：
- `A <path>` - 添加的文件
- `M <path>` - 修改的文件
- `D <path>` - 删除的文件

### 数据结构

#### Hunk 枚举（parser.rs:58-76）
```rust
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

`DeleteFile` 变体最为简单，仅包含目标路径。

#### AffectedPaths 结构（lib.rs:271-275）
```rust
pub struct AffectedPaths {
    pub added: Vec<PathBuf>,
    pub modified: Vec<PathBuf>,
    pub deleted: Vec<PathBuf>,
}
```

用于跟踪补丁应用后的文件系统变更。

### 协议与命令

#### 命令行接口
```bash
# 直接参数方式
apply_patch "*** Begin Patch\n*** Delete File: obsolete.txt\n*** End Patch"

# stdin 方式
echo "*** Begin Patch
*** Delete File: obsolete.txt
*** End Patch" | apply_patch
```

#### 测试执行流程（scenarios.rs:30-63）
```rust
fn run_apply_patch_scenario(dir: &Path) -> anyhow::Result<()> {
    let tmp = tempdir()?;
    
    // 1. 复制 input/ 到临时目录
    copy_dir_recursive(&input_dir, tmp.path())?;
    
    // 2. 读取 patch.txt
    let patch = fs::read_to_string(dir.join("patch.txt"))?;
    
    // 3. 执行 apply_patch
    Command::new(cargo_bin("apply_patch")?)
        .arg(patch)
        .current_dir(tmp.path())
        .output()?;
    
    // 4. 比较结果与 expected/
    let expected_snapshot = snapshot_dir(&expected_dir)?;
    let actual_snapshot = snapshot_dir(tmp.path())?;
    assert_eq!(actual_snapshot, expected_snapshot);
}
```

---

## 关键代码路径与文件引用

### 核心实现文件

| 文件 | 职责 | 相关行号 |
|------|------|---------|
| `src/parser.rs` | 补丁解析，识别 Delete File 指令 | 34 (DELETE_FILE_MARKER), 65-67 (DeleteFile 变体), 271-278 (解析逻辑) |
| `src/lib.rs` | 补丁应用，执行文件删除 | 228 (路径收集), 301-304 (删除执行), 548-550 (摘要输出) |
| `src/standalone_executable.rs` | CLI 入口，参数处理 | 11-58 (run_main) |

### 测试相关文件

| 文件 | 职责 |
|------|------|
| `tests/suite/scenarios.rs` | Scenario-based 测试框架，遍历所有场景目录 |
| `tests/suite/tool.rs` | 集成测试，包含删除相关测试用例 |
| `tests/fixtures/scenarios/020_delete_file_success/` | 本场景测试数据 |

### 相关测试用例

#### 单元测试（lib.rs:594-611）
```rust
fn test_delete_file_hunk_removes_file() {
    // 验证删除操作能正确移除文件并输出 D 标记
}
```

#### 集成测试（tool.rs:113-124）
```rust
fn test_apply_patch_cli_rejects_missing_file_delete() {
    // 验证删除不存在的文件会失败
}
```

#### 集成测试（tool.rs:195-207）
```rust
fn test_apply_patch_cli_delete_directory_fails() {
    // 验证删除目录会失败（只能删除文件）
}
```

---

## 依赖与外部交互

### 内部依赖

```
codex-apply-patch
├── src/lib.rs (核心逻辑)
│   ├── mod invocation (Shell 脚本解析)
│   ├── mod parser (补丁解析)
│   ├── mod seek_sequence (文本匹配)
│   └── mod standalone_executable (CLI)
```

### 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `anyhow` | 错误处理与上下文增强 |
| `thiserror` | 自定义错误类型定义 |
| `similar` | 统一差异计算（Update 操作使用） |
| `tree-sitter` + `tree-sitter-bash` | Shell heredoc 解析（间接相关） |

### 系统调用

| 调用 | 用途 | 错误处理 |
|------|------|---------|
| `std::fs::remove_file` | 删除文件 | 包装为 `ApplyPatchError::IoError`，附加文件路径上下文 |

### 测试依赖

| Crate | 用途 |
|-------|------|
| `assert_cmd` | CLI 测试断言 |
| `tempfile` | 临时目录创建 |
| `codex-utils-cargo-bin` | 定位测试二进制文件 |
| `pretty_assertions` | 更好的测试失败输出 |

---

## 风险、边界与改进建议

### 已知风险与边界

#### 1. 文件不存在错误
- **场景**: 尝试删除不存在的文件
- **行为**: 返回 `ApplyPatchError::IoError`，stderr 输出 `"Failed to delete file <path>"`
- **测试覆盖**: `007_rejects_missing_file_delete` 场景验证

#### 2. 目录删除限制
- **场景**: 尝试删除目录而非文件
- **行为**: `std::fs::remove_file` 失败，返回错误
- **测试覆盖**: `012_delete_directory_fails` 场景验证
- **注意**: 这与 `rm` 命令不同，`rm -r` 可以删除目录，但 `apply_patch` 不支持递归删除

#### 3. 路径解析
- **相对路径**: 补丁中的路径相对于当前工作目录解析
- **绝对路径**: 如果补丁包含绝对路径，将直接使用（但文档建议始终使用相对路径）

#### 4. 权限问题
- **场景**: 无权限删除文件
- **行为**: 返回 IO 错误，错误信息包含具体路径

### 改进建议

#### 1. 批量删除优化
当前实现逐个处理 hunks，如果多个删除操作中有失败，已成功的操作不会回滚。建议：
- 考虑添加 `--dry-run` 模式预先验证所有操作
- 或添加事务性支持，失败时回滚已完成的操作

#### 2. 删除确认机制
对于重要文件删除，可考虑：
- 添加 `--force` 标志跳过确认
- 默认情况下要求显式确认删除操作

#### 3. 改进错误信息
当前错误信息仅包含文件路径，可扩展为：
```rust
// 当前
"Failed to delete file /path/to/file"

// 建议
"Failed to delete file /path/to/file: Permission denied (os error 13)"
```

#### 4. 支持删除目录
如果业务需要，可考虑：
- 添加 `*** Delete Directory:` 指令
- 或添加 `*** Delete File: <path> --recursive` 选项

#### 5. 删除前备份
对于 Update 操作，`invocation.rs` 会读取原文件内容保存到 `ApplyPatchFileChange::Delete { content }`，但直接调用 `apply_patch` 二进制时不会保留备份。建议：
- 添加 `--backup` 选项，删除前将文件内容备份到临时位置

### 相关场景对比

| 场景编号 | 名称 | 目的 | 与 020 的关系 |
|---------|------|------|--------------|
| 002 | multiple_operations | 验证多种操作组合 | 包含 Delete 作为组合的一部分 |
| 007 | rejects_missing_file_delete | 验证删除不存在文件失败 | 020 的负面测试 |
| 012 | delete_directory_fails | 验证删除目录失败 | 020 的边界测试 |
| 020 | **delete_file_success** | **验证正常删除成功** | **本场景** |

### 代码质量观察

1. **错误处理**: 使用 `anyhow::Context` 增强错误信息，符合最佳实践
2. **测试覆盖**: 单元测试、集成测试、场景测试三层覆盖
3. **文档一致性**: `apply_patch_tool_instructions.md` 准确描述了删除语法
4. **边界处理**: 对目录删除、文件不存在等情况有明确测试

---

## 总结

`020_delete_file_success/patch.txt` 是一个简洁但重要的测试场景，验证了 `apply_patch` 工具最核心的文件删除功能。该场景设计简洁，仅包含一个删除操作，确保在隔离环境下验证 Delete 功能的正确性。

补丁格式的设计遵循了"简单即安全"的原则：
- 明确的操作标记（`*** Delete File:`）
- 无额外参数（不像 Update 需要 chunks）
- 类 Git 的输出格式（`D <path>`）

该场景与相关场景（007、012）共同构成了完整的删除功能测试矩阵，覆盖了正常路径、错误路径和边界情况。
