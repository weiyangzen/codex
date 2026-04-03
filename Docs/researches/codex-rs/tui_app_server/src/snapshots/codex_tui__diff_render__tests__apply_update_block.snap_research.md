# Research: codex_tui__diff_render__tests__apply_update_block.snap

## 场景与职责

本快照文件测试 Diff 渲染器中文件更新（Update）操作的渲染效果。文件更新是最常见的变更类型，需要清晰展示修改前后的对比。

## 功能点目的

验证文件更新时的 diff 渲染：
- 显示上下文行（未变更的行）
- 清晰区分删除行和添加行
- 保持行号对齐便于阅读

## 具体技术实现

### 渲染输出格式

```
"• Edited example.txt (+1 -1)                                                    "
"    1  line one                                                                 "
"    2 -line two                                                                 "
"    2 +line two changed                                                         "
"    3  line three                                                               "
```

### Diff 结构分析

```
    1  line one           <- 上下文行（未变更）
    2 -line two           <- 删除行（原内容）
    2 +line two changed   <- 添加行（新内容）
    3  line three         <- 上下文行（未变更）
```

### 行号对齐逻辑

| 行类型 | 行号显示 | 前缀 | 说明 |
|--------|----------|------|------|
| 上下文 | 原行号 | ` ` (空格) | 未变更的行 |
| 删除 | 原行号 | `-` | 被删除的行 |
| 添加 | 新行号 | `+` | 新增的行 |

### 关键代码

```rust
fn render_update_hunk(hunk: &Hunk, width: u16) -> Vec<Line<'static>> {
    let mut lines = vec![];
    let mut old_line_no = hunk.old_range().start();
    let mut new_line_no = hunk.new_range().start();
    
    for line in hunk.lines() {
        match line {
            diffy::Line::Context(text) => {
                lines.push(format!("{:>4}  {}", old_line_no, text));
                old_line_no += 1;
                new_line_no += 1;
            }
            diffy::Line::Delete(text) => {
                lines.push(format!("{:>4} -{}", old_line_no, text));
                old_line_no += 1;
            }
            diffy::Line::Insert(text) => {
                lines.push(format!("{:>4} +{}", new_line_no, text));
                new_line_no += 1;
            }
        }
    }
    lines
}
```

## 关键代码路径与文件引用

- **源文件**: `codex-rs/tui/src/diff_render.rs`
- **测试函数**: `apply_update_block`
- **diff 库**: `diffy` crate 处理 unified diff 格式

## 依赖与外部交互

- **diff 生成**: `diffy::create_patch` 生成文件差异
- **语法高亮**: 跨行保持解析器状态
- **主题适配**: 根据终端背景选择颜色

## 风险、边界与改进建议

### 边界情况

1. **大段变更**: 大量连续变更行的显示
2. **多 hunk**: 文件多处分散变更的处理
3. **空行**: 空行的正确显示和计数

### 风险点

1. **行号错位**: 复杂变更可能导致行号显示错误
2. **内存使用**: 大文件的完整 diff 可能占用大量内存

### 改进建议

1. 添加 hunk 之间的省略号（`⋮`）指示不连续的变更
2. 支持 side-by-side diff 模式
3. 添加行内差异高亮（word-level diff）
4. 支持忽略空白字符的选项
