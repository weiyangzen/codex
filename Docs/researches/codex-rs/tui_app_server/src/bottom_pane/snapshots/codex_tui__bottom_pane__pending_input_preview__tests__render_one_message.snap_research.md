# Pending Input Preview Render One Message Snapshot 研究文档

## 场景与职责

该快照文件测试了**待输入预览视图**在单条排队消息状态下的渲染输出。

### 业务场景
- 用户有一条排队的跟进消息
- 预览显示在底部栏上方
- 与 message_queue 不同，此视图包含标题

## 功能点目的

### 核心功能
1. **标题显示**：显示 "Queued follow-up messages"
2. **消息预览**：显示消息内容
3. **编辑提示**：提示使用 ⌥ + ↑ 编辑

### UI 设计特点
- 标题前缀：`•`
- 消息前缀：`↳`
- 编辑提示：`⌥ + ↑ edit last queued message`

## 具体技术实现

### Buffer 渲染
```rust
Buffer {
    area: Rect { x: 0, y: 0, width: 40, height: 3 },
    content: [
        "• Queued follow-up messages             ",
        "  ↳ Hello, world!                       ",
        "    ⌥ + ↑ edit last queued message      ",
    ],
    styles: [
        // DIM 样式用于标题和提示
        // DIM | ITALIC 用于消息内容
    ]
}
```

## 关键代码路径

### 主要源文件
- `codex-rs/tui/src/bottom_pane/pending_input_preview.rs`

### 相关测试
- `render_one_message` - 本快照
- `render_two_messages` - 两条消息
- `render_many_line_message` - 多行消息
- `render_pending_steers_above_queued_messages` - 待处理引导消息
