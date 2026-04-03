# Research: codex_tui__diff_render__tests__apply_add_block.snap

## 场景与职责

本快照文件测试 Diff 渲染器中 "Apply Add Block"（应用添加块）的渲染效果。验证当文件被成功添加后，diff 摘要的正确显示格式。

## 功能点目的

验证添加文件后的 diff 渲染：
- 使用 "Added" 动词表示已完成的操作
- 显示文件路径和变更统计
- 展示新增内容的行号和前缀

## 具体技术实现

### 渲染输出格式

```
"• Added new_file.txt (+2 -0)                                                    "
"    1 +alpha                                                                    "
"    2 +beta                                                                     "
```

### 与 "Proposed Change" 的区别

| 状态 | 前缀 | 含义 |
|------|------|------|
| Proposed Change | `• Proposed Change` | 提议中的变更，等待确认 |
| Added | `• Added` | 已应用的添加操作 |
| Edited | `• Edited` | 已应用的编辑操作 |
| Deleted | `• Deleted` | 已应用的删除操作 |

### 关键数据结构

```rust
// DiffSummary 创建
pub fn create_diff_summary(file_change: &FileChange) -> DiffSummary {
    match file_change {
        FileChange::Add { path, content } => DiffSummary {
            path: path.into(),
            change_type: ChangeType::Add,
            additions: content.lines().count(),
            deletions: 0,
        },
        // ...
    }
}
```

### 显示路径处理

```rust
pub fn display_path_for(path: &Path) -> String {
    // 优先显示相对于 git 仓库根的路径
    // 其次显示相对于主目录的路径
    // 最后显示绝对路径
}
```

## 关键代码路径与文件引用

- **源文件**: `codex-rs/tui/src/diff_render.rs`
- **测试函数**: `apply_add_block`
- **路径工具**: `exec_command::relativize_to_home`

## 依赖与外部交互

- **文件系统**: 读取文件路径和内容
- **Git 集成**: `get_git_repo_root` 用于相对路径显示
- **渲染管道**: 集成到历史记录单元（HistoryCell）

## 风险、边界与改进建议

### 边界情况

1. **空文件**: 添加空文件应显示 (+0 -0)
2. **换行符**: 末尾换行符的处理（POSIX 标准）
3. **多字节字符**: Unicode 字符的宽度计算

### 风险点

1. **行数统计**: 不同换行符风格（CRLF vs LF）可能影响计数
2. **路径截断**: 长路径在窄终端上的显示

### 改进建议

1. 添加文件大小（字节）信息
2. 对多文件添加显示文件类型图标
3. 支持点击/快捷键打开文件
4. 添加文件权限变更显示
