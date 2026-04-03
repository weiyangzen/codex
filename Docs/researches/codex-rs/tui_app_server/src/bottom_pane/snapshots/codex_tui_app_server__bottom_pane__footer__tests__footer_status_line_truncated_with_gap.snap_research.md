# Research: Footer Status Line Truncated With Gap Snapshot

## 场景与职责

此快照展示了当状态行内容过长时的截断处理。显示 "Status line content that … Plan mode"，状态行内容被截断并添加省略号，同时保留模式指示器的显示，确保底部栏布局的平衡。

## 功能点目的

- **空间管理**: 在有限宽度内优雅地处理长状态行内容
- **信息保留**: 截断时保留关键信息（开头部分），让用户知道状态类型
- **布局平衡**: 在截断处留出间隙，与模式指示器分隔

## 具体技术实现

状态行截断逻辑：

1. **宽度计算**: 计算状态行可用宽度
2. **截断判断**: 如果内容长度超过可用宽度，进行截断
3. **截断格式**: `"{truncated_content}… {other_content}"`
   - 保留开头部分
   - 添加省略号 "…"
   - 保留间隙和其他内容（如模式指示器）

代码逻辑：
```rust
fn truncate_status_line(content: &str, max_width: u16, suffix: &str) -> String {
    let content_width = content.width();
    let suffix_width = suffix.width();
    
    if content_width + suffix_width <= max_width as usize {
        format!("{} {}", content, suffix)
    } else {
        let available = max_width as usize - suffix_width - 2; // 2 for "… "
        let truncated = content.chars()
            .take_while(|c| {
                available -= c.width().unwrap_or(1);
                available > 0
            })
            .collect::<String>();
        format!("{}… {}", truncated, suffix)
    }
}

// 使用
let display = truncate_status_line(
    "Status line content that is very long",
    available_width,
    "Plan mode"
);
```

## 关键代码路径与文件引用

- **主要实现**: `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
- **截断函数**: 处理字符串截断的辅助函数
- **宽度计算**: `single_line_footer_layout()` 中的可用宽度计算
- **Unicode 处理**: 使用 `unicode-width` 正确处理多字节字符

## 依赖与外部交互

- 依赖 `unicode-width` crate 计算字符串显示宽度
- 依赖终端宽度信息进行截断判断
- 与状态行内容提供者交互，获取原始内容
- 需要响应终端大小变化，重新计算截断

## 风险、边界与改进建议

- **边界情况**: 当中文或其他宽字符被截断时，需要确保不出现乱码
- **改进建议**: 添加悬停提示，显示完整的状态行内容
- **改进建议**: 支持状态行内容的跑马灯滚动效果
- **改进建议**: 当内容被截断时，添加指示器提示用户内容不完整
- **改进建议**: 考虑使用工具提示（tooltip）替代截断，鼠标悬停时显示完整内容
