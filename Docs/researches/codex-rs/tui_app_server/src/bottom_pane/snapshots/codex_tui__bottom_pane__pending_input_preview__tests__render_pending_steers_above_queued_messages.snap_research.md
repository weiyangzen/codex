# Pending Input Preview Render Pending Steers Above Queued Messages Snapshot 研究文档

## 场景与职责

该快照文件是 `codex_tui_app_server` crate 中 `pending_input_preview.rs` 模块的测试快照，用于验证**待处理输入预览中待处理引导消息在排队消息上方**的渲染。当用户有待处理的引导消息（steers）和排队消息时，显示此界面。

### 业务场景
- 用户在等待工具调用完成时输入了后续消息
- 系统需要区分"工具调用后发送的消息"和"排队消息"
- 引导消息（steers）显示在排队消息上方

### 消息类型
- **Pending Steers**：等待工具调用完成后发送的消息
- **Queued Messages**：排队等待处理的消息

## 功能点目的

### 核心功能
1. **消息分类**：区分不同类型的待处理消息
2. **顺序显示**：按优先级显示消息
3. **编辑提示**：提供编辑消息的快捷方式
4. **中断提示**：提示可以按 Esc 中断并立即发送

### 用户体验目标
- **状态清晰**：用户清楚知道消息的处理顺序
- **灵活控制**：可以中断等待立即发送
- **便捷编辑**：可以快速编辑待处理消息

## 具体技术实现

### 关键数据结构
```rust
pub(crate) struct PendingInputPreview {
    pending_steers: Vec<String>,
    queued_messages: Vec<String>,
}
```

### 渲染逻辑
```rust
impl Renderable for PendingInputPreview {
    fn render(&self, area: Rect, buf: &mut Buffer) {
        let mut y = area.y;
        
        // 渲染待处理引导消息
        if !self.pending_steers.is_empty() {
            Line::from("• Messages to be submitted after next tool call")
                .dim()
                .render(Rect::new(area.x, y, area.width, 1), buf);
            y += 1;
            
            Line::from("  (press esc to interrupt and send immediately)")
                .dim()
                .render(Rect::new(area.x, y, area.width, 1), buf);
            y += 1;
            
            for steer in &self.pending_steers {
                Line::from(format!("  ↳ {}", steer))
                    .dim()
                    .render(Rect::new(area.x, y, area.width, 1), buf);
                y += 1;
            }
            
            y += 1; // 空行分隔
        }
        
        // 渲染排队消息
        if !self.queued_messages.is_empty() {
            Line::from("• Queued follow-up messages")
                .dim()
                .render(Rect::new(area.x, y, area.width, 1), buf);
            y += 1;
            
            for msg in &self.queued_messages {
                Line::from(format!("  ↳ {}", msg))
                    .dim()
                    .render(Rect::new(area.x, y, area.width, 1), buf);
                y += 1;
            }
            
            Line::from("    ⌥ + ↑ edit last queued message")
                .dim()
                .render(Rect::new(area.x, y, area.width, 1), buf);
        }
    }
}
```

### 关键代码路径
- **源文件**: `codex-rs/tui_app_server/src/bottom_pane/pending_input_preview.rs`
- **测试函数**: `render_pending_steers_above_queued_messages` (在 tests 模块中)

### 渲染输出分析
```
Buffer {
    area: Rect { x: 0, y: 0, width: 52, height: 8 },
    content: [
        "• Messages to be submitted after next tool call     ",
        "  (press esc to interrupt and send immediately)     ",
        "  ↳ Please continue.                                ",
        "  ↳ Check the last command output.                  ",
        "                                                    ",
        "• Queued follow-up messages                         ",
        "  ↳ Queued follow-up question                       ",
        "    ⌥ + ↑ edit last queued message                  ",
    ],
    // ... 样式信息
}
```

- 待处理引导消息显示在上方
- 排队消息显示在下方
- 提供不同的操作提示

## 依赖与外部交互

### 内部依赖
- `PendingInputPreview` - 待处理输入预览

### 外部交互
- **消息队列**：获取待处理消息
- **工具调用系统**：了解工具调用状态

## 风险、边界与改进建议

### 潜在风险
1. **消息混淆**：用户可能混淆两种消息类型
2. **空间占用**：大量消息时占用过多空间
3. **状态同步**：消息状态可能不同步

### 边界情况
1. **仅有一种消息**：只显示一种消息类型
2. **空消息**：消息内容为空时的处理
3. **消息过多**：消息过多时的截断策略

### 改进建议
1. **颜色区分**：使用不同颜色区分消息类型
2. **折叠功能**：允许折叠某类消息
3. **优先级标记**：允许设置消息优先级
4. **批量操作**：支持批量编辑或删除

### 相关文件引用
- 源文件: `codex-rs/tui_app_server/src/bottom_pane/pending_input_preview.rs`
