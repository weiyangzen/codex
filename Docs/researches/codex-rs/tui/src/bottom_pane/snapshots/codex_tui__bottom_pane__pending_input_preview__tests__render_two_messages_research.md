# PendingInputPreview 测试快照研究文档

## 文件信息
- **快照文件**: `codex_tui__bottom_pane__pending_input_preview__tests__render_two_messages.snap`
- **源文件**: `codex-rs/tui/src/bottom_pane/pending_input_preview.rs`
- **测试函数**: `render_two_messages`

---

## 1. 场景与职责

### 测试场景
本测试验证 `PendingInputPreview` 组件在有两个排队消息时的渲染行为。测试多条消息的垂直堆叠显示、每条消息的独立样式以及整体布局的正确性。

### 业务场景
用户在系统处理前一条消息期间连续输入了两条消息，这两条消息都被排队等待发送。组件需要清晰展示多条消息的列表，让用户了解消息的顺序和内容。

### 组件职责
- 按顺序显示多条排队消息
- 为每条消息提供一致的视觉前缀（↳）
- 保持消息间的适当间距和缩进
- 只在最后显示一次编辑提示

---

## 2. 功能点目的

### 核心功能验证
1. **多条消息渲染**: 验证组件能正确渲染多条排队消息
2. **消息顺序保持**: 验证消息按添加顺序显示
3. **独立样式**: 验证每条消息都有正确的缩进和样式
4. **单一编辑提示**: 验证即使有多条消息，也只显示一个编辑提示

### 用户体验目标
- 清晰展示消息队列的顺序
- 通过一致的视觉样式帮助用户快速扫描多条消息
- 避免重复提示造成的视觉混乱

---

## 3. 具体技术实现

### 测试数据
```rust
let mut queue = PendingInputPreview::new();
queue.queued_messages.push("Hello, world!".to_string());
queue.queued_messages.push("This is another message".to_string());
let width = 40;
```

### 渲染输出分析
```
Buffer {
    area: Rect { x: 0, y: 0, width: 40, height: 4 },
    content: [
        "• Queued follow-up messages             ",  // 第0行：标题
        "  ↳ Hello, world!                       ",  // 第1行：消息1
        "  ↳ This is another message             ",  // 第2行：消息2
        "    ⌥ + ↑ edit last queued message      ",  // 第3行：编辑提示
    ],
    ...
}
```

### 样式映射
| 行 | 内容 | 样式 |
|---|---|---|
| 0 | "• Queued follow-up messages" | "• " DIM, 标题 NONE |
| 1 | "  ↳ Hello, world!" | "  ↳ " DIM, 内容 DIM\|ITALIC |
| 2 | "  ↳ This is another message" | "  ↳ " DIM, 内容 DIM\|ITALIC |
| 3 | "    ⌥ + ↑ edit last queued message" | 整体 DIM |

---

## 4. 关键代码路径与文件引用

### 消息迭代渲染
```rust
for message in &self.queued_messages {
    let wrapped = adaptive_wrap_lines(
        message.lines().map(|line| Line::from(line.dim().italic())),
        RtOptions::new(width as usize)
            .initial_indent(Line::from("  ↳ ".dim()))
            .subsequent_indent(Line::from("    ")),
    );
    Self::push_truncated_preview_lines(&mut lines, wrapped, Line::from("    …".dim().italic()));
}
```

### 关键实现细节
- 使用 `for` 循环遍历 `queued_messages` Vec
- 每条消息独立调用 `adaptive_wrap_lines` 处理换行
- `initial_indent` 为第一行添加 "  ↳ " 前缀
- `subsequent_indent` 为后续行添加 "    " 缩进

---

## 5. 依赖与外部交互

### 与单条消息测试的对比
| 特性 | 单条消息 | 两条消息 |
|---|---|---|
| 高度 | 3 | 4 |
| 标题 | 1行 | 1行 |
| 消息行 | 1行 | 2行 |
| 编辑提示 | 1行 | 1行 |

### 内存布局
- 每条消息独立渲染，不共享状态
- 使用 `Vec<Line>` 累积所有行后一次性创建 Paragraph

---

## 6. 风险边界与改进建议

### 当前限制
1. **消息数量无限制**: 虽然每条消息有3行限制，但消息数量本身无上限
   - 风险：大量消息可能导致渲染区域过高

2. **编辑提示语义**: "edit last queued message" 提示只编辑最后一条，但用户可能想编辑任意一条

### 改进建议
1. **消息数量限制**: 添加总消息数限制或分页显示
2. **可选择编辑**: 考虑支持选择编辑任意消息，而不仅是最后一条
3. **消息删除**: 添加删除单条消息的功能

---

## 附录：完整快照内容

```
---
source: tui/src/bottom_pane/pending_input_preview.rs
expression: "format!(\"{buf:?}\")"
---
Buffer {
    area: Rect { x: 0, y: 0, width: 40, height: 4 },
    content: [
        "• Queued follow-up messages             ",
        "  ↳ Hello, world!                       ",
        "  ↳ This is another message             ",
        "    ⌥ + ↑ edit last queued message      ",
    ],
    styles: [
        x: 0, y: 0, fg: Reset, bg: Reset, underline: Reset, modifier: DIM,
        x: 2, y: 0, fg: Reset, bg: Reset, underline: Reset, modifier: NONE,
        x: 0, y: 1, fg: Reset, bg: Reset, underline: Reset, modifier: DIM,
        x: 4, y: 1, fg: Reset, bg: Reset, underline: Reset, modifier: DIM | ITALIC,
        x: 17, y: 1, fg: Reset, bg: Reset, underline: Reset, modifier: NONE,
        x: 0, y: 2, fg: Reset, bg: Reset, underline: Reset, modifier: DIM,
        x: 4, y: 2, fg: Reset, bg: Reset, underline: Reset, modifier: DIM | ITALIC,
        x: 27, y: 2, fg: Reset, bg: Reset, underline: Reset, modifier: NONE,
        x: 0, y: 3, fg: Reset, bg: Reset, underline: Reset, modifier: DIM,
        x: 34, y: 3, fg: Reset, bg: Reset, underline: Reset, modifier: NONE,
    ]
}
```
