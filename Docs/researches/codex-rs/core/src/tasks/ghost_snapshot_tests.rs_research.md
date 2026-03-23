# ghost_snapshot_tests.rs 研究文档

## 场景与职责

`ghost_snapshot_tests.rs` 是 `ghost_snapshot.rs` 的配套单元测试模块，负责验证幽灵快照任务中的警告格式化逻辑。该测试文件通过 `#[path = "ghost_snapshot_tests.rs"]` 属性在 `ghost_snapshot.rs` 中内联包含。

### 测试范围
- 大未跟踪目录警告格式化
- 阈值配置对警告的影响
- 警告消息内容的正确性验证

## 功能点目的

### 1. 验证警告包含阈值信息
确保当大未跟踪目录被跳过时，警告消息中正确显示文件数量阈值（如 `>= 200 files`）。

### 2. 验证阈值禁用行为
确保当 `ignore_large_untracked_dirs` 配置为 `None` 时，不会生成大目录警告。

## 具体技术实现

### 测试用例 1：`large_untracked_warning_includes_threshold`

```rust
#[test]
fn large_untracked_warning_includes_threshold() {
    let report = GhostSnapshotReport {
        large_untracked_dirs: vec![LargeUntrackedDir {
            path: PathBuf::from("models"),
            file_count: 250,
        }],
        ignored_untracked_files: Vec::new(),
    };

    let message = format_large_untracked_warning(Some(200), &report).unwrap();
    assert!(message.contains(">= 200 files"));
}
```

**测试逻辑**：
1. 构造包含一个大目录（250 个文件）的报告
2. 设置阈值为 200
3. 验证生成的警告消息包含阈值信息

### 测试用例 2：`large_untracked_warning_disabled_when_threshold_disabled`

```rust
#[test]
fn large_untracked_warning_disabled_when_threshold_disabled() {
    let report = GhostSnapshotReport {
        large_untracked_dirs: vec![LargeUntrackedDir {
            path: PathBuf::from("models"),
            file_count: 250,
        }],
        ignored_untracked_files: Vec::new(),
    };

    assert_eq!(format_large_untracked_warning(None, &report), None);
}
```

**测试逻辑**：
1. 构造同样包含大目录的报告
2. 设置阈值为 `None`（禁用）
3. 验证不生成警告（返回 `None`）

### 依赖类型

```rust
use super::*;  // 导入 ghost_snapshot.rs 的所有私有项
use codex_git::LargeUntrackedDir;
use pretty_assertions::assert_eq;
use std::path::PathBuf;
```

## 关键代码路径与文件引用

### 文件关系
```
ghost_snapshot.rs
  ├── mod ghost_snapshot_tests (内联包含)
  │     └── ghost_snapshot_tests.rs (本文件)
  └── 被测试的函数
        ├── format_large_untracked_warning
        ├── format_ignored_untracked_files_warning
        └── format_snapshot_warnings
```

### 相关类型定义
- `codex-rs/utils/git/src/ghost_commits.rs:83-86`：`GhostSnapshotReport` 结构
- `codex-rs/utils/git/src/ghost_commits.rs:89-93`：`LargeUntrackedDir` 结构
- `codex-rs/utils/git/src/ghost_commits.rs:95-100`：`IgnoredUntrackedFile` 结构

## 依赖与外部交互

### 测试框架
- `pretty_assertions::assert_eq`：提供清晰的断言失败输出

### 被测模块
- `ghost_snapshot.rs`：通过 `use super::*` 访问私有函数

### 外部类型
- `codex_git::LargeUntrackedDir`：大未跟踪目录数据结构

## 风险、边界与改进建议

### 当前测试覆盖缺口

| 功能 | 测试状态 | 风险等级 |
|------|---------|---------|
| `format_large_untracked_warning` | ✅ 部分覆盖 | 低 |
| `format_ignored_untracked_files_warning` | ❌ 未覆盖 | 中 |
| `format_snapshot_warnings` | ❌ 未覆盖 | 中 |
| `format_bytes` | ❌ 未覆盖 | 低 |
| 多目录/文件警告截断 | ❌ 未覆盖 | 中 |

### 建议添加的测试

1. **大文件警告测试**
   ```rust
   #[test]
   fn ignored_files_warning_includes_size() {
       let report = GhostSnapshotReport {
           large_untracked_dirs: Vec::new(),
           ignored_untracked_files: vec![IgnoredUntrackedFile {
               path: PathBuf::from("large.bin"),
               byte_size: 15 * 1024 * 1024, // 15 MiB
           }],
       };
       let message = format_ignored_untracked_files_warning(
           Some(10 * 1024 * 1024), 
           &report
       ).unwrap();
       assert!(message.contains("15 MiB"));
   }
   ```

2. **多项目截断测试**
   ```rust
   #[test]
   fn warning_truncates_after_three_items() {
       // 测试超过 3 个目录时的 "N more" 逻辑
   }
   ```

3. **字节格式化测试**
   ```rust
   #[test]
   fn format_bytes_conversions() {
       assert_eq!(format_bytes(512), "512 B");
       assert_eq!(format_bytes(1024), "1 KiB");
       assert_eq!(format_bytes(1024 * 1024), "1 MiB");
   }
   ```

4. **空报告测试**
   ```rust
   #[test]
   fn no_warning_when_no_large_items() {
       let report = GhostSnapshotReport::default();
       assert_eq!(format_large_untracked_warning(Some(200), &report), None);
   }
   ```

### 改进建议

1. **集成测试**
   - 添加与 `codex_git`  crate 的集成测试
   - 验证实际 Git 仓库的快照行为

2. **属性测试**
   - 使用 `proptest` 生成随机报告数据
   - 验证格式化函数的鲁棒性

3. **快照测试**
   - 使用 `insta` crate 对警告消息进行快照测试
   - 便于检测意外的格式变更
