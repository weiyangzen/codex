# turn_diff_tracker_tests.rs 研究文档

## 场景与职责

`turn_diff_tracker_tests.rs` 是 `turn_diff_tracker.rs` 的配套测试模块，全面验证文件变更追踪和差异生成功能：

1. **添加和更新测试**：验证文件创建和修改的 diff 生成
2. **删除测试**：验证文件删除的 diff 格式
3. **移动和更新测试**：验证重命名+内容修改的组合场景
4. **纯移动测试**：验证无内容变化的重命名不产生 diff
5. **新增目标测试**：验证源文件不存在时的特殊处理
6. **多文件累积测试**：验证跨多个补丁的累积 diff
7. **二进制文件测试**：验证非 UTF-8 内容的二进制标记
8. **特殊文件名测试**：验证含空格文件名的处理

该模块使用真实临时文件系统操作，是集成测试风格。

## 功能点目的

### 1. 添加和更新测试 (`accumulates_add_and_update`)

验证流程：
1. 首次补丁添加文件 -> 生成 new file diff
2. 第二次补丁更新文件 -> 累积显示从空到最终状态的完整 diff

### 2. 删除测试 (`accumulates_delete`)

验证：
- 删除前文件存在时捕获基线
- 生成 deleted file diff
- 正确显示 `-` 行删除

### 3. 移动和更新测试 (`accumulates_move_and_update`)

验证：
- 源文件内容作为基线
- 目标文件内容作为当前状态
- 正确显示 rename + content change

### 4. 纯移动测试 (`move_without_1change_yields_no_diff`)

验证：
- 仅重命名无内容变化时返回 `None`
- 不生成无意义的 diff

### 5. 新增目标测试 (`move_declared_but_file_only_appears_at_dest_is_add`)

验证边界情况：
- 声明移动但源文件从未存在
- 按新增文件处理（从 /dev/null 开始）

### 6. 多文件累积测试 (`update_persists_across_new_baseline_for_new_file`)

验证：
- 第一个补丁修改文件 A
- 第二个补丁删除文件 B
- 最终 diff 包含 A 和 B 的变更

### 7. 二进制文件测试 (`binary_files_differ_update`)

验证：
- 非 UTF-8 字节序列检测为二进制
- 生成 "Binary files differ" 标记
- 不尝试文本 diff

### 8. 特殊文件名测试 (`filenames_with_spaces_add_and_update`)

验证：
- 含空格文件名正确处理
- diff 头部正确引用路径

## 具体技术实现

### 测试辅助函数

```rust
/// 计算 Git SHA-1 blob ID
fn git_blob_sha1_hex(data: &str) -> String {
    format!("{:x}", git_blob_sha1_hex_bytes(data.as_bytes()))
}

/// 标准化 diff 输出用于比较
fn normalize_diff_for_test(input: &str, root: &Path) -> String {
    // 1. 替换临时目录路径为 <TMP>
    let root_str = root.display().to_string().replace('\\', "/");
    let replaced = input.replace(&root_str, "<TMP>");
    
    // 2. 按 "diff --git " 分割为块
    let mut blocks: Vec<String> = Vec::new();
    let mut current = String::new();
    for line in replaced.lines() {
        if line.starts_with("diff --git ") && !current.is_empty() {
            blocks.push(current);
            current = String::new();
        }
        // ...
    }
    
    // 3. 排序块以确保确定性
    blocks.sort();
    blocks.join("\n")
}
```

### 典型测试模式

```rust
#[test]
fn accumulates_add_and_update() {
    let mut acc = TurnDiffTracker::new();
    let dir = tempdir().unwrap();
    let file = dir.path().join("a.txt");

    // 第一步：添加文件
    let add_changes = HashMap::from([(
        file.clone(),
        FileChange::Add { content: "foo\n".to_string() },
    )]);
    acc.on_patch_begin(&add_changes);
    fs::write(&file, "foo\n").unwrap();  // 模拟应用补丁
    
    let first = acc.get_unified_diff().unwrap().unwrap();
    let first = normalize_diff_for_test(&first, dir.path());
    
    // 验证 new file diff 格式
    let expected_first = format!(
        r#"diff --git a/<TMP>/a.txt b/<TMP>/a.txt
new file mode {mode}
index {ZERO_OID}..{right_oid}
--- {DEV_NULL}
+++ b/<TMP>/a.txt
@@ -0,0 +1 @@
+foo
"#,
    );
    assert_eq!(first, expected_first);

    // 第二步：更新文件
    let update_changes = HashMap::from([(
        file.clone(),
        FileChange::Update { unified_diff: "".to_owned(), move_path: None },
    )]);
    acc.on_patch_begin(&update_changes);
    fs::write(&file, "foo\nbar\n").unwrap();
    
    let combined = acc.get_unified_diff().unwrap().unwrap();
    // 验证累积 diff 包含完整内容
}
```

### 删除测试验证

```rust
#[test]
fn accumulates_delete() {
    let dir = tempdir().unwrap();
    let file = dir.path().join("b.txt");
    fs::write(&file, "x\n").unwrap();  // 先创建文件

    let mut acc = TurnDiffTracker::new();
    let del_changes = HashMap::from([(
        file.clone(),
        FileChange::Delete { content: "x\n".to_string() },
    )]);
    acc.on_patch_begin(&del_changes);  // 捕获基线
    
    let baseline_mode = file_mode_for_path(&file).unwrap_or(FileMode::Regular);
    fs::remove_file(&file).unwrap();  // 删除文件
    
    let diff = acc.get_unified_diff().unwrap().unwrap();
    // 验证 deleted file mode 和 -x 行
}
```

### 移动测试验证

```rust
#[test]
fn accumulates_move_and_update() {
    let src = dir.path().join("src.txt");
    let dest = dir.path().join("dst.txt");
    fs::write(&src, "line\n").unwrap();

    let mut acc = TurnDiffTracker::new();
    let mv_changes = HashMap::from([(
        src.clone(),
        FileChange::Update {
            unified_diff: "".to_owned(),
            move_path: Some(dest.clone()),  // 声明移动
        },
    )]);
    acc.on_patch_begin(&mv_changes);
    
    fs::rename(&src, &dest).unwrap();
    fs::write(&dest, "line2\n").unwrap();  // 同时修改内容
    
    let out = acc.get_unified_diff().unwrap().unwrap();
    // 验证 diff --git a/src.txt b/dst.txt
    // 验证 index old_oid..new_oid
    // 验证 --- a/src.txt +++ b/dst.txt
    // 验证 -line +line2
}
```

### 二进制文件测试

```rust
#[test]
fn binary_files_differ_update() {
    let file = dir.path().join("bin.dat");
    let left_bytes: Vec<u8> = vec![0xff, 0xfe, 0xfd, 0x00];
    let right_bytes: Vec<u8> = vec![0x01, 0x02, 0x03, 0x00];

    fs::write(&file, &left_bytes).unwrap();
    
    let mut acc = TurnDiffTracker::new();
    acc.on_patch_begin(&update_changes);
    fs::write(&file, &right_bytes).unwrap();
    
    let diff = acc.get_unified_diff().unwrap().unwrap();
    // 验证包含 "Binary files differ"
    // 不包含 @@ 上下文行
}
```

## 关键代码路径与文件引用

### 被测方法

| 方法 | 路径 | 测试覆盖 |
|------|------|----------|
| `TurnDiffTracker::new` | `turn_diff_tracker.rs:46` | 所有测试 |
| `on_patch_begin` | `turn_diff_tracker.rs:54` | 所有测试 |
| `get_unified_diff` | `turn_diff_tracker.rs:225` | 所有测试 |
| `get_file_diff` | `turn_diff_tracker.rs:252` | 间接测试 |

### 被测辅助函数

| 函数 | 路径 | 测试 |
|------|------|------|
| `git_blob_sha1_hex_bytes` | `turn_diff_tracker.rs:372` | 通过 `git_blob_sha1_hex` 间接 |
| `file_mode_for_path` | `turn_diff_tracker.rs:408` | 所有涉及文件模式的测试 |

### 测试依赖

| crate | 用途 |
|-------|------|
| `tempfile::tempdir` | 临时目录和文件 |
| `pretty_assertions::assert_eq` | 友好断言输出 |
| `std::fs` | 文件系统操作 |

## 依赖与外部交互

### 文件系统操作

所有测试执行真实文件系统操作：
- `fs::write` - 创建/修改文件
- `fs::remove_file` - 删除文件
- `fs::rename` - 移动文件

### 临时目录

使用 `tempfile` crate 自动清理：
```rust
let dir = tempdir().unwrap();  // RAII 清理
```

### 纯同步测试

无异步操作，使用 `#[test]` 而非 `#[tokio::test]`。

## 风险、边界与改进建议

### 当前覆盖缺口

1. **符号链接**：未测试 symlink 的创建、修改、指向变更
2. **权限变更**：未测试 mode change（100644 -> 100755）
3. **可执行文件**：未测试 Unix 可执行权限检测
4. **大文件**：未测试大文件性能和内存使用
5. **并发修改**：未测试多线程同时调用
6. **Git 工作区**：未测试嵌套 git 仓库、子模块
7. **空 diff**：未测试内容相同但格式不同的情况

### 平台覆盖

当前测试在 Unix 和 Windows 均可运行，但：
- 未测试 Windows 特有的路径格式
- 未测试 Unix 特有的权限模式
- `file_mode_for_path` 在非 Unix 平台固定返回 Regular

### 潜在问题

1. **路径分隔符**：`normalize_diff_for_test` 替换 `\\` 为 `/`，但可能不完全
2. **排序稳定性**：diff 块排序依赖字符串比较，可能受 locale 影响
3. **时间依赖**：无时间相关逻辑，但文件系统时间戳可能影响 git 命令

### 改进建议

1. **添加权限测试**：
```rust
#[cfg(unix)]
#[test]
fn detects_executable_mode_change() {
    use std::os::unix::fs::PermissionsExt;
    let file = dir.path().join("script.sh");
    fs::write(&file, "#!/bin/sh\necho hello").unwrap();
    
    // 捕获基线（普通文件）
    acc.on_patch_begin(&update_changes);
    
    // 添加执行权限
    let mut perms = fs::metadata(&file).unwrap().permissions();
    perms.set_mode(0o755);
    fs::set_permissions(&file, perms).unwrap();
    
    let diff = acc.get_unified_diff().unwrap().unwrap();
    // 验证包含 "old mode 100644" 和 "new mode 100755"
}
```

2. **添加符号链接测试**：
```rust
#[cfg(unix)]
#[test]
fn handles_symlink_changes() {
    let link = dir.path().join("link");
    std::os::unix::fs::symlink("old_target", &link).unwrap();
    
    acc.on_patch_begin(&update_changes);
    
    fs::remove_file(&link).unwrap();
    std::os::unix::fs::symlink("new_target", &link).unwrap();
    
    // 验证 symlink 目标变化
}
```

3. **性能基准测试**：
```rust
#[test]
fn handles_many_files_efficiently() {
    for i in 0..1000 {
        let file = dir.path().join(format!("file_{}.txt", i));
        fs::write(&file, format!("content {}", i)).unwrap();
        acc.on_patch_begin(&...);
    }
    // 验证性能和内存使用
}
```

4. **使用 insta snapshot**：
```rust
#[test]
fn diff_snapshot() {
    let diff = acc.get_unified_diff().unwrap().unwrap();
    insta::assert_snapshot!(diff);
}
```

### 代码统计

- 测试行数：427 行
- 测试函数：8 个
- 辅助函数：2 个
- 常量使用：`ZERO_OID`, `DEV_NULL`

### 测试组织

建议按功能分组：
```rust
mod add_tests { ... }
mod delete_tests { ... }
mod move_tests { ... }
mod binary_tests { ... }
```

当前所有测试在顶层，随着功能增加可能变得难以导航。
