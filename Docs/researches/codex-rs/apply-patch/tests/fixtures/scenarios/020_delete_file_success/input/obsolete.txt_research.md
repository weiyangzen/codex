# obsolete.txt 研究文档

## 场景与职责

`obsolete.txt` 是 `020_delete_file_success` 测试场景中的**删除目标文件**，用于验证 `apply_patch` 工具的文件删除功能。该文件代表在补丁操作过程中**应该被删除**的过时或不需要的文件，测试工具能否正确解析删除指令并执行文件删除操作。

## 功能点目的

### 测试目标
1. **验证文件删除功能**：确认 `apply_patch` 工具能够正确解析 `*** Delete File:` 指令并删除指定文件
2. **验证删除后状态一致性**：确保删除操作后，文件系统状态与预期一致
3. **回归测试**：防止未来的代码变更破坏文件删除功能

### 在测试场景中的角色
- **输入状态**：`obsolete.txt` 包含内容 `"obsolete"`
- **预期行为**：执行补丁后，`obsolete.txt` 应被完全删除，不应存在于文件系统中
- **验证方式**：测试框架会比较预期目录（`expected/`）和实际输出，`expected/` 中不包含 `obsolete.txt`

## 具体技术实现

### 文件内容
```
obsolete
```

### 补丁操作定义 (`patch.txt`)
```
*** Begin Patch
*** Delete File: obsolete.txt
*** End Patch
```

### 补丁格式解析

补丁使用自定义的类统一 diff 格式，由 `parser.rs` 解析：

1. **标记定义**
   ```rust
   const DELETE_FILE_MARKER: &str = "*** Delete File: ";
   ```

2. **Hunk 类型定义**
   ```rust
   pub enum Hunk {
       AddFile { path: PathBuf, contents: String },
       DeleteFile { path: PathBuf },
       UpdateFile { path: PathBuf, move_path: Option<PathBuf>, chunks: Vec<UpdateFileChunk> },
   }
   ```

3. **解析逻辑**（`parse_one_hunk` 函数）
   ```rust
   else if let Some(path) = first_line.strip_prefix(DELETE_FILE_MARKER) {
       // Delete File
       return Ok((
           DeleteFile {
               path: PathBuf::from(path),
           },
           1,  // 只消耗一行（hunk 头部）
       ));
   }
   ```

### 删除操作执行流程

1. **路径解析**
   ```rust
   impl Hunk {
       pub fn resolve_path(&self, cwd: &Path) -> PathBuf {
           match self {
               Hunk::DeleteFile { path } => cwd.join(path),
               // ...
           }
       }
   }
   ```

2. **文件删除执行**（`apply_hunks_to_files` 函数，第 301-304 行）
   ```rust
   Hunk::DeleteFile { path } => {
       std::fs::remove_file(path)
           .with_context(|| format!("Failed to delete file {}", path.display()))?;
       deleted.push(path.clone());
   }
   ```

3. **结果汇总**（`print_summary` 函数）
   ```rust
   for path in &affected.deleted {
       writeln!(out, "D {}", path.display())?;
   }
   ```
   输出格式：`D obsolete.txt`（git 风格的删除标记）

### 测试验证机制

```rust
fn run_apply_patch_scenario(dir: &Path) -> anyhow::Result<()> {
    let tmp = tempdir()?;
    
    // 1. 复制输入文件
    copy_dir_recursive(&input_dir, tmp.path())?;
    // 此时 tmp/ 包含 keep.txt 和 obsolete.txt
    
    // 2. 执行补丁
    Command::new(codex_utils_cargo_bin::cargo_bin("apply_patch")?)
        .arg(patch)
        .current_dir(tmp.path())
        .output()?;
    // 此时 tmp/ 只包含 keep.txt
    
    // 3. 验证结果
    let expected_snapshot = snapshot_dir(&expected_dir)?;
    let actual_snapshot = snapshot_dir(tmp.path())?;
    assert_eq!(actual_snapshot, expected_snapshot);
    // expected/ 只包含 keep.txt，验证 obsolete.txt 已被删除
}
```

## 关键代码路径与文件引用

### 核心实现文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/apply-patch/src/parser.rs` | 解析补丁格式，识别 `DeleteFile` hunk（第 271-278 行） |
| `codex-rs/apply-patch/src/lib.rs` | 执行删除操作（第 301-304 行） |
| `codex-rs/apply-patch/tests/suite/scenarios.rs` | 场景测试框架 |

### 关键代码路径详解

1. **补丁解析链**
   ```
   parse_patch(patch_text)
   └── parse_patch_text(lines, mode)
       └── check_patch_boundaries_strict/lenient
           └── parse_one_hunk(lines, line_number)
               └── 匹配 DELETE_FILE_MARKER → Hunk::DeleteFile
   ```

2. **删除执行链**
   ```
   apply_patch(patch, stdout, stderr)
   └── apply_hunks(&hunks, stdout, stderr)
       └── apply_hunks_to_files(hunks)
           └── 匹配 Hunk::DeleteFile → std::fs::remove_file(path)
   ```

3. **测试验证链**
   ```
   test_apply_patch_scenarios()
   └── run_apply_patch_scenario(dir)
       ├── copy_dir_recursive(input_dir, tmp_dir)
       ├── Command::new("apply_patch").arg(patch).output()
       └── assert_eq!(snapshot_dir(tmp), snapshot_dir(expected))
   ```

### 相关单元测试

- `test_delete_file_hunk_removes_file`（`lib.rs` 第 594-611 行）
  ```rust
  #[test]
  fn test_delete_file_hunk_removes_file() {
      let dir = tempdir().unwrap();
      let path = dir.path().join("del.txt");
      fs::write(&path, "x").unwrap();
      let patch = wrap_patch(&format!("*** Delete File: {}", path.display()));
      // ... 执行并验证 ...
      assert!(!path.exists());  // 验证文件已删除
  }
  ```

## 依赖与外部交互

### 文件依赖关系

```
020_delete_file_success/
├── input/
│   ├── keep.txt          # 保留文件（对照组）
│   └── obsolete.txt      # 本文件（删除目标）
├── expected/
│   └── keep.txt          # 预期保留状态（不含 obsolete.txt）
└── patch.txt             # 删除指令定义
```

### 外部系统依赖

| 依赖 | 用途 | 接口 |
|-----|------|------|
| `std::fs::remove_file` | 删除文件 | Rust 标准库 |
| `std::fs::metadata` | 检查文件存在性 | Rust 标准库 |
| `tempfile::tempdir` | 创建隔离测试环境 | crates.io |
| `anyhow::Context` | 错误上下文增强 | crates.io |

### 错误处理

删除操作可能产生的错误：

| 错误类型 | 触发条件 | 错误信息 |
|---------|---------|---------|
| `std::io::ErrorKind::NotFound` | 文件不存在 | "Failed to delete file {path}" |
| `std::io::ErrorKind::PermissionDenied` | 权限不足 | "Failed to delete file {path}" |
| `std::io::ErrorKind::Other` | 其他 I/O 错误 | "Failed to delete file {path}" |

### 与其他场景的关联

| 场景 | 关系 | 说明 |
|-----|------|------|
| `007_rejects_missing_file_delete` | 补充 | 验证删除不存在文件时的错误处理 |
| `012_delete_directory_fails` | 补充 | 验证尝试删除目录时的失败行为 |
| `015_failure_after_partial_success_leaves_changes` | 相关 | 验证部分失败时的状态一致性 |
| `021_update_file_deletion_only` | 区分 | 验证 UpdateFile hunk 的删除行功能（不同于 DeleteFile） |

## 风险、边界与改进建议

### 潜在风险

1. **误删风险**
   - 当前实现没有"回收站"或"备份"机制
   - 一旦删除，文件无法恢复
   - **缓解措施**：生产环境使用前应确保有版本控制或备份

2. **路径遍历风险**
   - 补丁中指定的路径可能包含 `../` 等相对路径组件
   - 当前实现使用 `PathBuf::from(path)` 直接拼接
   - **缓解措施**：建议添加路径规范化检查

3. **并发删除冲突**
   - 如果多个进程同时操作同一文件，可能出现竞态条件
   - **缓解措施**：考虑添加文件锁或原子操作

### 边界情况分析

| 边界情况 | 预期行为 | 实际行为 | 测试覆盖 |
|---------|---------|---------|---------|
| 文件不存在 | 报错 | 报错（I/O Error） | ✅ `007_rejects_missing_file_delete` |
| 路径是目录 | 报错 | 报错（I/O Error） | ✅ `012_delete_directory_fails` |
| 文件被其他进程占用 | 报错 | 依赖操作系统行为 | ❌ 未覆盖 |
| 符号链接 | 删除链接本身 | 删除链接目标（跟随链接） | ❌ 未明确覆盖 |
| 只读文件 | 可能失败 | 依赖操作系统 | ❌ 未覆盖 |

### 改进建议

1. **添加删除确认机制**
   ```rust
   // 建议添加可选的 "dry-run" 模式
   pub fn apply_hunks_to_files(hunks: &[Hunk], dry_run: bool) -> Result<AffectedPaths> {
       for hunk in hunks {
           match hunk {
               Hunk::DeleteFile { path } => {
                   if dry_run {
                       println!("Would delete: {}", path.display());
                   } else {
                       std::fs::remove_file(path)?;
                   }
               }
               // ...
           }
       }
   }
   ```

2. **增强路径安全**
   ```rust
   // 建议添加路径验证
   fn validate_delete_path(path: &Path, workdir: &Path) -> Result<()> {
       let canonical_path = path.canonicalize()?;
       let canonical_workdir = workdir.canonicalize()?;
       if !canonical_path.starts_with(&canonical_workdir) {
           bail!("Delete path escapes working directory: {}", path.display());
       }
       Ok(())
   }
   ```

3. **添加删除前备份选项**
   ```rust
   // 建议添加备份功能
   fn backup_and_delete(path: &Path, backup_dir: &Path) -> Result<()> {
       let backup_path = backup_dir.join(path.file_name().unwrap());
       std::fs::copy(path, &backup_path)?;
       std::fs::remove_file(path)?;
       Ok(())
   }
   ```

4. **测试增强**
   - 添加符号链接删除测试场景
   - 添加并发删除测试场景
   - 添加大文件删除性能测试

### 代码风格建议

根据项目 `AGENTS.md` 的 Rust 编码规范：

1. **错误处理**：当前使用 `with_context` 符合规范，但可以进一步使用 `#[error(transparent)]` 模式
2. **路径显示**：使用 `path.display()` 符合规范
3. **测试断言**：可以使用 `pretty_assertions` 进行更清晰的差异展示

### 相关配置

此场景没有特殊的配置文件依赖，完全通过文件系统状态和补丁文本定义测试行为。
