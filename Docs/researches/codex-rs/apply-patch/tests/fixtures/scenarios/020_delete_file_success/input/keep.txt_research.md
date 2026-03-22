# keep.txt 研究文档

## 场景与职责

`keep.txt` 是 `020_delete_file_success` 测试场景中的**保留文件**，用于验证 `apply_patch` 工具在执行删除操作时的选择性行为。该文件代表在补丁操作过程中**不应被修改或删除**的现有文件，确保工具能够精确地仅删除指定的目标文件，而保留其他无关文件。

## 功能点目的

### 测试目标
1. **验证选择性删除**：确认 `apply_patch` 工具能够仅删除补丁中明确指定的文件（`obsolete.txt`），而保留其他文件（`keep.txt`）不受影响
2. **验证文件系统隔离**：确保补丁操作不会意外影响工作目录中的其他文件
3. **回归测试**：防止未来的代码变更引入"误删"或"过度删除"的 bug

### 在测试场景中的角色
- **输入状态**：`keep.txt` 包含内容 `"keep"`
- **预期行为**：执行补丁后，`keep.txt` 应保持原样，内容不变
- **验证方式**：测试框架会比较 `expected/keep.txt` 和实际输出，确保两者一致

## 具体技术实现

### 文件内容
```
keep
```

### 补丁操作定义 (`patch.txt`)
```
*** Begin Patch
*** Delete File: obsolete.txt
*** End Patch
```

### 测试执行流程

1. **测试准备阶段**（`run_apply_patch_scenario` 函数）
   ```rust
   // 复制输入文件到临时目录
   copy_dir_recursive(&input_dir, tmp.path())?;
   ```
   - 将 `input/keep.txt` 和 `input/obsolete.txt` 复制到临时目录

2. **补丁执行阶段**
   ```rust
   Command::new(codex_utils_cargo_bin::cargo_bin("apply_patch")?)
       .arg(patch)
       .current_dir(tmp.path())
       .output()?;
   ```
   - 执行 `apply_patch` 工具，传入补丁内容
   - 工具解析补丁，识别出 `DeleteFile` 操作

3. **删除操作实现**（`apply_hunks_to_files` 函数）
   ```rust
   Hunk::DeleteFile { path } => {
       std::fs::remove_file(path)
           .with_context(|| format!("Failed to delete file {}", path.display()))?;
       deleted.push(path.clone());
   }
   ```

4. **结果验证阶段**
   ```rust
   let expected_snapshot = snapshot_dir(&expected_dir)?;
   let actual_snapshot = snapshot_dir(tmp.path())?;
   assert_eq!(actual_snapshot, expected_snapshot, ...);
   ```
   - 使用 `snapshot_dir` 函数对整个目录进行快照
   - 比较预期状态（`expected/`）和实际状态

### 目录快照机制

测试使用 `Entry` 枚举来表示文件系统状态：
```rust
#[derive(Debug, Clone, PartialEq, Eq)]
enum Entry {
    File(Vec<u8>),
    Dir,
}
```

通过递归遍历目录，构建 `BTreeMap<PathBuf, Entry>` 进行精确比较。

## 关键代码路径与文件引用

### 核心实现文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/apply-patch/src/lib.rs` | 包含 `apply_hunks_to_files` 函数，执行实际的文件删除操作 |
| `codex-rs/apply-patch/src/parser.rs` | 解析补丁格式，识别 `DeleteFile` 类型的 hunk |
| `codex-rs/apply-patch/tests/suite/scenarios.rs` | 场景测试框架，包含 `run_apply_patch_scenario` 函数 |

### 关键代码路径

1. **补丁解析路径**
   ```
   parse_patch() -> parse_patch_text() -> parse_one_hunk()
   ```
   - 识别 `*** Delete File:` 标记
   - 创建 `Hunk::DeleteFile { path: PathBuf }`

2. **删除执行路径**
   ```
   apply_patch() -> apply_hunks() -> apply_hunks_to_files()
   ```
   - 匹配 `Hunk::DeleteFile` 变体
   - 调用 `std::fs::remove_file(path)` 删除文件

3. **测试验证路径**
   ```
   test_apply_patch_scenarios() -> run_apply_patch_scenario()
   -> snapshot_dir() -> assert_eq!()
   ```

### 相关测试用例

- `test_delete_file_hunk_removes_file`（`lib.rs` 第 594-611 行）：单元测试验证单个文件删除
- `test_apply_patch_scenarios`（`scenarios.rs` 第 10-26 行）：集成测试运行所有场景

## 依赖与外部交互

### 文件依赖

```
020_delete_file_success/
├── input/
│   ├── keep.txt          # 本文件（保留目标）
│   └── obsolete.txt      # 待删除文件
├── expected/
│   └── keep.txt          # 预期保留状态
└── patch.txt             # 删除操作定义
```

### 外部依赖

| 依赖 | 用途 |
|-----|------|
| `std::fs::remove_file` | 执行实际的文件删除操作 |
| `std::fs::metadata` | 在快照时跟随符号链接（支持 Buck2 构建环境） |
| `tempfile::tempdir` | 创建隔离的临时测试环境 |
| `codex_utils_cargo_bin::repo_root` | 定位测试固件目录 |

### 与其他场景的关联

- `007_rejects_missing_file_delete`：验证删除不存在文件时的错误处理
- `012_delete_directory_fails`：验证尝试删除目录时的失败行为
- `015_failure_after_partial_success_leaves_changes`：验证部分失败时的状态一致性

## 风险、边界与改进建议

### 潜在风险

1. **并发安全问题**
   - 当前实现直接调用 `std::fs::remove_file`，没有文件锁机制
   - 如果在测试执行期间有其他进程修改文件，可能导致非确定性结果

2. **符号链接处理**
   - 代码使用 `fs::metadata()` 跟随符号链接
   - 如果 `keep.txt` 是符号链接，测试可能无法正确验证链接本身的存在性

3. **权限问题**
   - 如果测试目录权限不足，`remove_file` 可能失败
   - 但此场景测试的是保留文件，不涉及权限边界

### 边界情况

| 边界情况 | 当前行为 | 说明 |
|---------|---------|------|
| 文件不存在 | 报错 | 由 `007_rejects_missing_file_delete` 场景覆盖 |
| 删除目录 | 报错 | 由 `012_delete_directory_fails` 场景覆盖 |
| 只读文件 | 可能失败 | 取决于操作系统和文件系统 |
| 空文件 | 正常保留 | 本场景验证非空文件的保留 |

### 改进建议

1. **增强测试覆盖**
   ```rust
   // 建议添加：验证文件元数据（修改时间、权限）未被改变
   let metadata_before = fs::metadata(&keep_path)?;
   // ... 执行补丁 ...
   let metadata_after = fs::metadata(&keep_path)?;
   assert_eq!(metadata_before.modified()?, metadata_after.modified()?);
   ```

2. **添加符号链接测试场景**
   - 验证当 `keep.txt` 是符号链接时，链接关系不会被破坏

3. **性能优化**
   - 当前 `snapshot_dir` 读取整个文件内容到内存
   - 对于大文件可以使用哈希比较而非字节比较

4. **文档增强**
   - 在场景目录添加 `README.md` 说明测试目的和预期行为

### 相关 Issue/PR 参考

- 此场景是 `apply-patch` 测试套件的基础场景之一
- 与文件删除相关的任何修改都应确保此测试通过
- 如果修改删除逻辑，建议同时检查 `007` 和 `012` 场景
