# tool.rs 研究文档

## 场景与职责

`tool.rs` 是 `codex-apply-patch` crate 的工具级功能测试模块，专注于验证 `apply_patch` 二进制在复杂场景下的行为。与 `cli.rs` 的基础测试和 `scenarios.rs` 的 fixture 驱动测试不同，`tool.rs` 包含更细粒度的边界条件测试、错误处理验证和复杂操作组合测试。

### 文件位置
- **源文件**: `codex-rs/apply-patch/tests/suite/tool.rs`
- **所属 crate**: `codex-apply-patch`
- **测试类型**: 集成测试（通过 `assert_cmd` 调用实际二进制文件）
- **平台限制**: 仅在非 Windows 平台编译（由 `mod.rs` 中的 `#[cfg(not(target_os = "windows"))]` 控制）

---

## 功能点目的

### 1. 复杂操作组合测试
验证多种文件操作在同一个 patch 中的正确执行：
- Add + Update + Delete 组合
- 多 chunk 更新（同一文件多个独立变更）
- Move 操作与内容更新组合

### 2. 边界条件与错误处理
测试各种异常场景和错误恢复：
- 空 patch 拒绝
- 上下文不匹配报告
- 缺失文件处理
- 无效 hunk 头拒绝
- 部分失败后的状态保留

### 3. 文件系统边界行为
验证与文件系统交互的边界情况：
- 目录删除尝试（应失败）
- 文件覆盖行为（Add/Update 覆盖已存在文件）
- 末尾换行符自动添加
- 移动操作覆盖目标文件

---

## 具体技术实现

### 辅助函数

#### 1. 命令执行封装
```rust
fn run_apply_patch_in_dir(dir: &Path, patch: &str) -> anyhow::Result<assert_cmd::assert::Assert> {
    let mut cmd = Command::new(codex_utils_cargo_bin::cargo_bin("apply_patch")?);
    cmd.current_dir(dir);
    Ok(cmd.arg(patch).assert())
}

fn apply_patch_command(dir: &Path) -> anyhow::Result<Command> {
    let mut cmd = Command::new(codex_utils_cargo_bin::cargo_bin("apply_patch")?);
    cmd.current_dir(dir);
    Ok(cmd)
}
```

#### 2. 测试模式
- **快捷模式**: `run_apply_patch_in_dir` - 一行执行并断言
- **灵活模式**: `apply_patch_command` - 支持链式配置参数、stdin 等

### 测试用例详解

#### 1. 多操作组合测试 (`test_apply_patch_cli_applies_multiple_operations`)
```rust
// Patch 内容：同时执行 Add、Delete、Update
"*** Begin Patch
*** Add File: nested/new.txt
+created
*** Delete File: delete.txt
*** Update File: modify.txt
@@
-line2
+changed
*** End Patch"
```
**验证点**:
- 嵌套目录自动创建
- 多操作顺序执行
- 输出包含所有操作标记（A、M、D）

#### 2. 多 chunk 更新测试 (`test_apply_patch_cli_applies_multiple_chunks`)
```rust
// 同一文件两个独立 @@ chunk
"@@
-line2
+changed2
@@
-line4
+changed4"
```
**验证点**:
- 多个 @@ 上下文块正确处理
- 文件只被标记一次 M（Modified）

#### 3. 移动操作测试 (`test_apply_patch_cli_moves_file_to_new_directory`)
```rust
// Update + Move 组合
"*** Update File: old/name.txt
*** Move to: renamed/dir/name.txt
@@
-old content
+new content"
```
**验证点**:
- 源文件删除
- 目标目录自动创建
- 内容同时更新
- 输出显示目标路径

#### 4. 错误处理测试矩阵

| 测试函数 | 输入 | 预期错误 |
|----------|------|----------|
| `test_apply_patch_cli_rejects_empty_patch` | 无操作 patch | `No files were modified.` |
| `test_apply_patch_cli_reports_missing_context` | 不匹配的上下文 | `Failed to find expected lines` |
| `test_apply_patch_cli_rejects_missing_file_delete` | 删除不存在文件 | `Failed to delete file` |
| `test_apply_patch_cli_rejects_empty_update_hunk` | 空 Update hunk | `Update file hunk for path 'foo.txt' is empty` |
| `test_apply_patch_cli_requires_existing_file_for_update` | 更新不存在文件 | `Failed to read file to update` |
| `test_apply_patch_cli_rejects_invalid_hunk_header` | 无效 hunk 头 | `is not a valid hunk header` |
| `test_apply_patch_cli_delete_directory_fails` | 尝试删除目录 | `Failed to delete file` |

#### 5. 覆盖行为测试

**移动覆盖目标** (`test_apply_patch_cli_move_overwrites_existing_destination`):
```rust
// 目标文件已存在，应被覆盖
// 验证：源文件删除，目标文件内容更新
```

**添加覆盖** (`test_apply_patch_cli_add_overwrites_existing_file`):
```rust
// Add File 目标已存在，应覆盖内容
// 验证：文件内容被替换，标记为 A（非 M）
```

#### 6. 末尾换行符处理 (`test_apply_patch_cli_updates_file_appends_trailing_newline`)
```rust
// 原始文件无末尾换行符
// Patch 更新后应自动添加换行符
// 验证：结果文件以 \n 结尾
```

#### 7. 部分失败处理 (`test_apply_patch_cli_failure_after_partial_success_leaves_changes`)
```rust
// Patch: Add 成功 + Update 失败（文件不存在）
// 验证：
// - 退出码为失败
// - stdout 为空（无成功摘要）
// - 但已创建的 created.txt 保留
```
**重要语义**: 当前实现是"尽力而为"，失败前的变更会被保留。

---

## 依赖与外部交互

### 外部依赖
| 依赖 | 用途 |
|------|------|
| `assert_cmd::Command` | 执行和断言外部命令 |
| `pretty_assertions::assert_eq` | 可视化差异断言 |
| `tempfile::tempdir` | 临时测试目录 |
| `std::fs` | 文件系统操作和验证 |
| `codex_utils_cargo_bin::cargo_bin` | 跨构建系统二进制定位 |

### 被测组件
- **二进制**: `apply_patch`
- **核心函数**: `lib::apply_patch()`, `lib::apply_hunks()`, `lib::apply_hunks_to_files()`

---

## 关键代码路径与文件引用

### 调用链
```
tool.rs 测试
    ↓ (调用)
apply_patch 二进制
    ↓ (内部)
standalone_executable::run_main()
    ↓ (解析参数)
lib::apply_patch(patch, stdout, stderr)
    ↓ (解析)
parser::parse_patch(patch) -> Vec<Hunk>
    ↓ (应用)
lib::apply_hunks(&hunks, stdout, stderr)
    ↓ (文件操作)
lib::apply_hunks_to_files(hunks) -> AffectedPaths
    ↓ (更新文件)
lib::derive_new_contents_from_chunks(path, chunks)
    ↓ (行匹配)
seek_sequence::seek_sequence(lines, pattern, start, eof)
```

### 相关文件
| 文件 | 职责 |
|------|------|
| `src/lib.rs` | Patch 应用核心逻辑，包含 `apply_patch`, `apply_hunks`, `apply_hunks_to_files` |
| `src/parser.rs` | Patch 格式解析，定义 `Hunk`, `UpdateFileChunk` 等类型 |
| `src/seek_sequence.rs` | 上下文行模糊匹配算法 |
| `src/standalone_executable.rs` | CLI 入口和参数处理 |

---

## 风险、边界与改进建议

### 当前风险与边界

1. **平台限制**
   - 整个模块被排除在 Windows 构建之外
   - 可能错过 Windows 特有的边界条件（如路径长度限制、保留文件名等）

2. **测试重复**
   - 部分场景与 `scenarios.rs` 的 fixture 测试重叠
   - 例如 `test_apply_patch_cli_applies_multiple_operations` 与 `002_multiple_operations`

3. **错误消息耦合**
   - 测试断言硬编码错误消息字符串
   - 如果 lib.rs 修改错误消息格式，测试会失败
   ```rust
   .stderr("Failed to delete file missing.txt\n");
   ```

4. **部分失败语义不明确**
   - `test_apply_patch_cli_failure_after_partial_success_leaves_changes` 验证当前行为
   - 但这是否是预期行为？文档未明确说明

### 改进建议

1. **添加 Windows 支持**
   ```rust
   // 将平台特定测试分离
   #[cfg(unix)]
   mod unix_specific;
   
   #[cfg(windows)]
   mod windows_specific;
   ```

2. **错误消息解耦**
   ```rust
   // 使用包含检查而非精确匹配
   .stderr(predicates::str::contains("Failed to delete file"));
   ```

3. **添加更多边界测试**
   ```rust
   // 建议添加：
   - test_apply_patch_cli_large_file          // 大文件处理
   - test_apply_patch_cli_binary_file         // 二进制文件处理
   - test_apply_patch_cli_special_chars       // 特殊字符文件名
   - test_apply_patch_cli_deep_nesting        // 深层目录嵌套
   - test_apply_patch_cli_concurrent_access   // 并发访问处理
   ```

4. **明确部分失败语义**
   - 在文档中明确说明事务性保证级别
   - 考虑添加 `--atomic` 选项支持原子性应用

5. **与 scenarios.rs 整合**
   - 将部分测试迁移为 fixture 格式
   - 减少代码重复，提高可维护性

### 测试覆盖矩阵

| 功能类别 | 覆盖测试 | 缺失测试 |
|----------|----------|----------|
| Add File | `test_apply_patch_cli_add_overwrites_existing_file` | 大文件、特殊字符文件名 |
| Delete File | `test_apply_patch_cli_rejects_missing_file_delete`, `test_apply_patch_cli_delete_directory_fails` | 权限不足场景 |
| Update File | `test_apply_patch_cli_applies_multiple_chunks`, `test_apply_patch_cli_updates_file_appends_trailing_newline` | 二进制文件更新 |
| Move File | `test_apply_patch_cli_moves_file_to_new_directory`, `test_apply_patch_cli_move_overwrites_existing_destination` | 跨文件系统移动 |
| 错误处理 | 7个错误场景测试 | 权限错误、磁盘满、IO错误 |
| 组合操作 | `test_apply_patch_cli_applies_multiple_operations` | 更多随机组合 |

### 与 cli.rs、scenarios.rs 的关系

```
测试金字塔
    ^
    |    tool.rs  (深度边界测试，13个测试)
    |   /        \
    |  /          \
    | /            \
    |/              \
    +------------------->
    cli.rs        scenarios.rs
  (基础功能)    (综合场景)
  (2个测试)     (22个fixture)
```

- **cli.rs**: 验证 CLI 基本可用性（快速反馈）
- **scenarios.rs**: 验证规范符合性（全面覆盖）
- **tool.rs**: 验证边界行为和错误处理（深度测试）

三者互补，共同确保 `apply_patch` 工具的正确性和健壮性。
