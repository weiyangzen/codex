# Research: codex_tui__diff_render__tests__apply_delete_block.snap

## 场景与职责

本快照文件测试 Diff 渲染器中 "Apply Delete Block"（应用删除块）的渲染效果。验证当文件被成功删除后，diff 摘要的正确显示格式。

## 功能点目的

验证删除文件后的 diff 渲染：
- 使用 "Deleted" 动词表示已完成的删除操作
- 显示被删除文件的路径
- 展示被删除内容的行号和 `-` 前缀

## 具体技术实现

### 渲染输出格式

```
"• Deleted tmp_delete_example.txt (+0 -3)                                        "
"    1 -first                                                                    "
"    2 -second                                                                   "
"    3 -third                                                                    "
```

### 删除操作的 Diff 统计

- **添加行数**: 0（因为是删除）
- **删除行数**: 3（文件中的三行内容）
- **标记**: `-` 表示删除的行

### 样式处理

- **深色主题**: 红色背景 (#4A221D)
- **亮色主题**: 浅红色背景 (#ffebe9)
- **行号背景**: 与内容行一致或略深

### 关键代码

```rust
impl DiffSummary {
    fn render_delete(&self, content: &str, width: u16) -> Vec<Line<'static>> {
        let mut lines = vec![];
        // 渲染标题行
        lines.push(format!("• Deleted {} (+0 -{})", self.path, self.deletions));
        
        // 渲染内容行，每行带 - 前缀
        for (i, line) in content.lines().enumerate() {
            lines.push(format!("    {} -{}", i + 1, line));
        }
        lines
    }
}
```

## 关键代码路径与文件引用

- **源文件**: `codex-rs/tui/src/diff_render.rs`
- **测试函数**: `apply_delete_block`
- **样式定义**: 文件顶部的颜色常量

## 依赖与外部交互

- **文件系统**: 获取被删除文件的内容（从 git 或缓存）
- **Git 集成**: 可能需要从 git 历史获取删除前的内容
- **渲染框架**: ratatui 的样式系统

## 风险、边界与改进建议

### 边界情况

1. **大文件删除**: 删除大文件时显示所有内容可能不现实
2. **二进制文件**: 删除二进制文件的内容显示
3. **已删除文件内容**: 需要从某处获取删除前的内容

### 风险点

1. **内容来源**: 删除后文件内容可能无法获取（如果未提交到 git）
2. **误删确认**: 用户可能需要确认删除操作

### 改进建议

1. 对大文件删除只显示前 N 行和统计信息
2. 添加恢复/撤销删除的功能提示
3. 显示文件大小和删除节省的空间
4. 添加删除原因（如果提供）
