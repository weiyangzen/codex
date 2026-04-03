# 研究文档：renders_with_queued_messages.snap

## 场景与职责

此快照测试验证状态指示器在有排队消息时的显示效果。当有多条消息排队等待处理时，状态指示器应该显示队列信息。

## 功能点目的

1. **队列状态展示**：显示排队的消息数量和内容
2. **操作提示**：提示用户可以执行的操作（如编辑）
3. **多行显示**：支持多行显示队列内容

## 具体技术实现

### 快照输出分析

```
"• Working (0s • esc to interrupt)                                               "
"                                                                                "
" ↳ first                                                                        "
" ↳ second                                                                       "
"   alt + ↑ edit                                                                 "
"                                                                                "
"                                                                                "
"                                                                                "
```

界面元素：
- 第一行：工作状态和快捷键提示
- 空行：分隔
- `↳ first` / `↳ second`：排队的消息
- `alt + ↑ edit`：编辑提示

### 队列显示逻辑

```rust
pub struct StatusIndicatorWidget {
    pub working: bool,
    pub duration: Duration,
    pub queued_messages: Vec<String>,
}

impl StatusIndicatorWidget {
    fn render(&self, area: Rect, buf: &mut Buffer) {
        // 渲染工作状态
        let status_line = format!("• Working ({}s • esc to interrupt)", 
            self.duration.as_secs());
        
        // 渲染排队消息
        for (i, msg) in self.queued_messages.iter().enumerate() {
            let line = format!(" ↳ {}", msg);
            // 渲染...
        }
        
        // 渲染编辑提示
        if !self.queued_messages.is_empty() {
            buf.set_string(
                area.x + 3, 
                area.y + 3 + self.queued_messages.len() as u16,
                "alt + ↑ edit",
                Style::default().dim()
            );
        }
    }
}
```

## 关键代码路径与文件引用

1. **状态指示器**：
   - `codex-rs/tui/src/status_indicator_widget.rs`

2. **快捷键**：
   - `crate::key_hint` - 快捷键提示

## 依赖与外部交互

### 消息队列
- `ChatWidget` 管理的消息队列
- 用户输入的历史记录

## 风险、边界与改进建议

### 潜在风险
1. **队列过长**：大量排队消息可能占用过多空间
2. **信息过载**：用户可能难以快速理解队列状态

### 边界情况
1. 队列为空
2. 队列消息很长
3. 队列消息包含特殊字符

### 改进建议
1. 限制显示的队列消息数量
2. 添加队列清空功能
3. 支持重新排序队列
4. 添加队列消息预览
