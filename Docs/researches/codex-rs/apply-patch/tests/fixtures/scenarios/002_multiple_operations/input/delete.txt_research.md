# delete.txt 研究文档

## 场景与职责

`delete.txt` 是 `apply-patch` 工具测试场景 `002_multiple_operations` 的输入夹具文件，用于测试**文件删除操作**的补丁应用功能。该文件代表一个待删除的已存在文件，在测试执行后应当被补丁操作移除。

### 所属测试场景

- **场景目录**: `codex-rs/apply-patch/tests/fixtures/scenarios/002_multiple_operations/`
- **场景编号**: 002
- **场景名称**: multiple_operations（多操作组合）
- **测试目的**: 验证单个补丁文件能够同时执行多种文件操作（添加、删除、修改）

## 功能点目的

### 测试目标

1. **验证 Delete File 操作**: 确认补丁解析器能够正确识别 `*** Delete File: {path}` 指令
2. **验证文件系统删除**: 确认 `apply-patch` 工具能够正确从文件系统中删除指定文件
3. **多操作协同**: 验证删除操作可以与添加操作、修改操作在同一个补丁中正确执行

### 文件内容设计

```
obsolete
```

- 文件内容仅包含单行文本 `"obsolete"`，表明这是一个过时的、待删除的文件
- 内容简洁，测试重点在于**删除行为本身**而非内容复杂性

## 具体技术实现

### 补丁格式与解析

该测试对应的补丁指令位于同目录的 `patch.txt` 文件中：

```
*** Begin Patch
*** Add File: nested/new.txt
+created
*** Delete File: delete.txt
*** Update File: modify.txt
@@
-line2
+changed
*** End Patch
```

删除操作的解析由 `codex-rs/apply-patch/src/parser.rs` 处理：

```rust
// parser.rs 第35行
const DELETE_FILE_MARKER: &str = "*** Delete File: ";

// parser.rs 第271-278行：解析 Delete File hunk
} else if let Some(path) = first_line.strip_prefix(DELETE_FILE_MARKER) {
    // Delete File
    return Ok((
        DeleteFile {
            path: PathBuf::from(path),
        },
        1,
    ));
}
```

### 文件删除执行流程

删除操作的实际执行在 `codex-rs/apply-patch/src/lib.rs` 中：

```rust
// lib.rs 第301-305行
Hunk::DeleteFile { path } => {
    std::fs::remove_file(path)
        .with_context(|| format!("Failed to delete file {}", path.display()))?;
    deleted.push(path.clone());
}
```

### 关键数据结构

**Hunk 枚举**（`parser.rs` 第58-76行）：
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

**ApplyPatchFileChange 枚举**（`lib.rs` 第94-108行）：
```rust
pub enum ApplyPatchFileChange {
    Add { content: String },
    Delete { content: String },
    Update { ... },
}
```

## 关键代码路径与文件引用

### 解析路径

1. **入口**: `parser.rs::parse_patch()` (第106行)
2. **边界检查**: `check_patch_boundaries_strict()` / `check_patch_boundaries_lenient()`
3. **Hunk 解析**: `parse_one_hunk()` (第248行)
4. **Delete Hunk 识别**: 匹配 `*** Delete File: ` 前缀

### 执行路径

1. **入口**: `lib.rs::apply_patch()` (第183行)
2. **Hunk 应用**: `apply_hunks()` (第216行)
3. **文件系统操作**: `apply_hunks_to_files()` (第279行)
4. **删除执行**: `std::fs::remove_file()` 调用

### 测试验证路径

1. **测试入口**: `tests/suite/scenarios.rs::test_apply_patch_scenarios()` (第11行)
2. **场景执行**: `run_apply_patch_scenario()` (第30行)
3. **结果验证**: 比较 `snapshot_dir()` 生成的实际状态与 `expected/` 目录的预期状态

## 依赖与外部交互

### 文件依赖

| 文件 | 关系 | 说明 |
|------|------|------|
| `patch.txt` | 同目录依赖 | 包含删除该文件的补丁指令 |
| `modify.txt` | 同目录依赖 | 同场景中被修改的文件 |
| `expected/` | 验证依赖 | 预期最终状态（不应包含 delete.txt）|
| `nested/new.txt` | 输出依赖 | 同场景中添加的新文件 |

### 外部系统交互

- **文件系统**: 调用 `std::fs::remove_file()` 删除文件
- **错误处理**: 使用 `anyhow::Context` 提供详细的错误上下文

### 测试框架依赖

- `tempfile::tempdir()`: 创建临时测试目录
- `pretty_assertions::assert_eq`: 提供清晰的测试失败输出
- `codex_utils_cargo_bin::repo_root`: 定位仓库根目录

## 风险、边界与改进建议

### 潜在风险

1. **文件不存在错误**: 如果 `delete.txt` 在应用补丁前不存在，`std::fs::remove_file()` 将返回错误
   - 缓解: 测试框架确保 `input/` 目录内容被正确复制到临时目录

2. **权限问题**: 如果文件被设置为只读，删除可能失败
   - 相关测试: `021_update_file_deletion_only` 等场景测试错误处理

3. **目录删除误用**: 该工具**不支持**删除目录，仅支持删除文件
   - 相关测试: `012_delete_directory_fails` 验证此限制

### 边界情况

| 边界情况 | 处理方式 | 相关测试 |
|---------|---------|---------|
| 删除不存在的文件 | 返回 IO 错误 | `007_rejects_missing_file_delete` |
| 删除目录 | 失败（需要特殊处理）| `012_delete_directory_fails` |
| 删除后验证 | 通过 `expected/` 目录缺失该文件验证 | 本场景 |

### 改进建议

1. **更丰富的测试内容**: 当前文件内容仅为 `"obsolete"`，可以考虑添加多行内容测试，验证删除操作不关心文件内容复杂性

2. **错误场景覆盖**: 可以添加测试验证删除操作失败时的错误消息格式

3. **并发安全**: 当前测试是串行的，如果未来需要并行测试，需要确保临时目录隔离

4. **跨平台验证**: 确保在 Windows、Linux、macOS 上文件删除行为一致（路径分隔符、权限模型等）

### 相关规范

根据 `tests/fixtures/scenarios/README.md` 的规范：

> Each test case is one directory, composed of input state (input/), the patch operation (patch.txt), and the expected final state (expected/).

本文件遵循该规范作为 `input/` 目录的一部分，预期在应用补丁后被删除（即 `expected/` 目录中不存在对应文件）。
