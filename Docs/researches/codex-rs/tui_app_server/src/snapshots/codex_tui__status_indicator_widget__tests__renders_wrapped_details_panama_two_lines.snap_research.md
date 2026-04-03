# 研究文档：renders_wrapped_details_panama_two_lines.snap

## 场景与职责

此快照测试验证状态指示器中详情文本的换行显示。当详情文本很长时，应该正确换行。

## 功能点目的

1. **详情换行**：长详情文本正确换行
2. **缩进对齐**：换行后保持适当的缩进
3. **可读性**：保持详情文本的可读性

## 具体技术实现

### 快照输出分析

```
"• Working (0s)                "
"  └ A man a plan a canal      "
"    panama                    "
```

测试文本：
- "A man a plan a canal panama"（回文，用于测试换行）

显示结构：
- 第一行：工作状态
- 第二行：`└` + 详情开始
- 第三行：缩进继续

### 详情换行逻辑

```rust
fn render_details(details: &str, width: u16) -> Vec<Line> {
    let mut lines = vec![];
    let prefix = "  └ ";
    let wrapped = textwrap::wrap(details, width as usize - prefix.width());
    
    for (i, line) in wrapped.iter().enumerate() {
        if i == 0 {
            lines.push(Line::from(format!("{prefix}{line}")));
        } else {
            // 后续行有额外缩进
            lines.push(Line::from(format!("    {line}")));
        }
    }
    
    lines
}
```

## 关键代码路径与文件引用

1. **状态指示器**：
   - `codex-rs/tui/src/status_indicator_widget.rs`

2. **换行工具**：
   - `crate::wrapping`

## 依赖与外部交互

### 文本处理
- `textwrap` - 文本换行
- `unicode_width` - 字符宽度计算

## 风险、边界与改进建议

### 潜在风险
1. **详情过多**：大量详情可能占用过多空间
2. **换行位置不当**：可能在单词中间换行

### 边界情况
1. 详情包含极长单词
2. 详情包含多行文本
3. 终端宽度极窄

### 改进建议
1. 限制详情显示行数
2. 添加 "更多" 展开功能
3. 支持详情滚动
4. 考虑使用弹出窗口显示长详情
