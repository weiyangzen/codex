# PendingInputPreview 测试快照研究文档

## 文件信息
- **快照文件**: `codex_tui__bottom_pane__pending_input_preview__tests__render_more_than_three_messages.snap`
- **源文件**: `codex-rs/tui/src/bottom_pane/pending_input_preview.rs`
- **测试函数**: `render_more_than_three_messages`

---

## 1. 场景与职责

### 测试场景
本测试验证当排队消息数量超过 `PREVIEW_LINE_LIMIT`（3条）时的渲染行为。测试组件是否正确显示所有消息而不进行截断，因为行数限制是针对单条消息的行数，而非消息总数。

### 业务场景
用户在系统繁忙时连续输入了多条消息（4条），组件需要完整展示所有消息，让用户了解完整的输入队列状态。

### 组件职责
- 完整显示所有排队消息，不限于3条
- 保持每条消息的独立渲染
- 确保编辑提示始终显示在最底部

---

## 2. 功能点目的

### 核心功能验证
1. **无消息数量限制**: 验证组件显示所有消息，不进行消息级截断
2. **消息行数限制**: 验证 `PREVIEW_LINE_LIMIT` 只限制单条消息的行数
3. **完整队列可见性**: 验证用户可以看到完整的消息队列

### 关键区分
- `PREVIEW_LINE_LIMIT = 3`: 限制**单条消息**最多显示3行（用于长消息的截断）
- 消息总数：无限制，所有消息都会显示

---

## 3. 具体技术实现

### 测试数据
```rust
let mut queue = PendingInputPreview::new();
queue.queued_messages.push("Hello, world!".to_string());
queue.queued_messages.push("This is another message".to_string());
queue.queued_messages.push("This is a third message".to_string());
queue.queued_messages.push("This is a fourth message".to_string());
let width = 40;
```

### 渲染输出分析
```
Buffer {
    area: Rect { x: 0, y: 0, width: 40, height: 6 },
    content: [
        "• Queued follow-up messages             ",  // 第0行：标题
        "  ↳ Hello, world!                       ",  // 第1行：消息1
        "  ↳ This is another message             ",  // 第2行：消息2
        "  ↳ This is a third message             ",  // 第3行：消息3
        "  ↳ This is a fourth message            ",  // 第4行：消息4
        "    ⌥ + ↑ edit last queued message      ",  // 第5行：编辑提示
    ],
    ...
}
```

### 高度计算
- 标题：1行
- 4条消息：4行（每条单行）
- 编辑提示：1行
- 总计：6行

---

## 4. 关键代码路径与文件引用

### 行数限制逻辑
```rust
const PREVIEW_LINE_LIMIT: usize = 3;

fn push_truncated_preview_lines(
    lines: &mut Vec<Line<'static>>,
    wrapped: Vec<Line<'static>>,
    overflow_line: Line<'static>,
) {
    let wrapped_len = wrapped.len();
    lines.extend(wrapped.into_iter().take(PREVIEW_LINE_LIMIT));
    if wrapped_len > PREVIEW_LINE_LIMIT {
        lines.push(overflow_line);
    }
}
```

### 关键观察
- `push_truncated_preview_lines` 在**每条消息**的渲染循环内调用
- 限制的是单条消息展开后的行数，而非消息总数
- 如果单条消息超过3行，会添加 "…" 省略行

---

## 5. 依赖与外部交互

### 与截断测试的对比
本测试的消息都是短消息（单行），所以不会触发 `PREVIEW_LINE_LIMIT` 截断。参考 `render_many_line_message` 测试可以看到截断行为。

### 性能考虑
- 消息数量无上限，极端情况下可能导致渲染性能问题
- 每条消息都调用 `adaptive_wrap_lines`，复杂度为 O(n*m)

---

## 6. 风险边界与改进建议

### 当前风险
1. **无消息数量上限**: 大量消息可能导致：
   - 渲染区域过高，挤占其他 UI 元素
   - 性能下降
   - 用户难以快速定位最后一条消息

2. **编辑提示位置**: 编辑提示始终在底部，消息多时用户需要滚动才能看到

### 改进建议
1. **添加消息数量上限**
   ```rust
   const MAX_QUEUED_MESSAGES_DISPLAY: usize = 10;
   ```

2. **折叠显示**
   - 超过一定数量后显示 "+ N more messages"
   - 提供展开/折叠功能

3. **反向显示**
   - 最新消息显示在最上面，方便用户查看

4. **性能优化**
   - 对大量消息使用虚拟滚动
   - 延迟渲染不可见区域

---

## 附录：完整快照内容

```
---
source: tui/src/bottom_pane/pending_input_preview.rs
expression: "format!(\"{buf:?}\")"
---
Buffer {
    area: Rect { x: 0, y: 0, width: 40, height: 6 },
    content: [
        "• Queued follow-up messages             ",
        "  ↳ Hello, world!                       ",
        "  ↳ This is another message             ",
        "  ↳ This is a third message             ",
        "  ↳ This is a fourth message            ",
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
        x: 4, y: 3, fg: Reset, bg: Reset, underline: Reset, modifier: DIM | ITALIC,
        x: 27, y: 3, fg: Reset, bg: Reset, underline: Reset, modifier: NONE,
        x: 0, y: 4, fg: Reset, bg: Reset, underline: Reset, modifier: DIM,
        x: 4, y: 4, fg: Reset, bg: Reset, underline: Reset, modifier: DIM | ITALIC,
        x: 28, y: 4, fg: Reset, bg: Reset, underline: Reset, modifier: NONE,
        x: 0, y: 5, fg: Reset, bg: Reset, underline: Reset, modifier: DIM,
        x: 34, y: 5, fg: Reset, bg: Reset, underline: Reset, modifier: NONE,
    ]
}
```
