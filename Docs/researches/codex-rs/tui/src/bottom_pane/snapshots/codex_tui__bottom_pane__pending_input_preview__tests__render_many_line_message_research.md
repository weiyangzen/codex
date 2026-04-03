# PendingInputPreview 测试快照研究文档

## 文件信息
- **快照文件**: `codex_tui__bottom_pane__pending_input_preview__tests__render_many_line_message.snap`
- **源文件**: `codex-rs/tui/src/bottom_pane/pending_input_preview.rs`
- **测试函数**: `render_many_line_message`

---

## 1. 场景与职责

### 测试场景
本测试验证当单条消息包含多行内容（使用 `\n` 换行符）且总行数超过 `PREVIEW_LINE_LIMIT`（3行）时的截断行为。测试组件是否正确截断超长消息并显示省略号。

### 业务场景
用户粘贴或输入了一段多行文本（如代码片段、多段落内容），组件需要预览前3行并提示内容被截断。

### 组件职责
- 识别消息中的换行符并正确处理多行内容
- 限制显示行数为3行
- 当内容超过3行时显示 "…" 省略号
- 保持截断后的视觉一致性

---

## 2. 功能点目的

### 核心功能验证
1. **多行内容识别**: 验证正确处理包含 `\n` 的消息
2. **行数限制**: 验证 `PREVIEW_LINE_LIMIT` 截断机制
3. **省略号显示**: 验证超过3行时显示 "…"
4. **样式一致性**: 验证省略号与消息内容样式一致

### 用户体验目标
- 避免单条消息占用过多垂直空间
- 通过省略号提示用户内容被截断
- 保持预览区域的紧凑性

---

## 3. 具体技术实现

### 测试数据
```rust
let mut queue = PendingInputPreview::new();
queue.queued_messages.push("This is\na message\nwith many\nlines".to_string());
let width = 40;
```

### 渲染输出分析
```
Buffer {
    area: Rect { x: 0, y: 0, width: 40, height: 6 },
    content: [
        "• Queued follow-up messages             ",  // 第0行：标题
        "  ↳ This is                             ",  // 第1行：第1行内容
        "    a message                           ",  // 第2行：第2行内容
        "    with many                           ",  // 第3行：第3行内容
        "    …                                   ",  // 第4行：省略号
        "    ⌥ + ↑ edit last queued message      ",  // 第5行：编辑提示
    ],
    ...
}
```

### 截断逻辑分析
1. 原始消息有4行（"This is", "a message", "with many", "lines"）
2. `PREVIEW_LINE_LIMIT = 3`，所以只显示前3行
3. 第4行被替换为 "    …" 省略号行

### 样式映射
| 行 | 内容 | 样式 |
|---|---|---|
| 1 | "  ↳ This is" | "  ↳ " DIM, "This is" DIM\|ITALIC |
| 2 | "    a message" | "    " NONE, "a message" DIM\|ITALIC |
| 3 | "    with many" | "    " NONE, "with many" DIM\|ITALIC |
| 4 | "    …" | 整体 DIM\|ITALIC |

---

## 4. 关键代码路径与文件引用

### 截断逻辑实现
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

### 调用点
```rust
Self::push_truncated_preview_lines(
    &mut lines,
    wrapped,
    Line::from("    …".dim().italic()),  // 省略号样式与消息一致
);
```

### 多行处理流程
```rust
message.lines().map(|line| Line::from(line.dim().italic()))
```
- `str::lines()` 按 `\n` 分割消息
- 每行映射为带样式的 Line
- `adaptive_wrap_lines` 进一步处理每行的换行

---

## 5. 依赖与外部交互

### 行数统计
- `wrapped_len` 是经过 `adaptive_wrap_lines` 处理后的总行数
- 包括原始换行符产生的行和自动换行产生的行

### 样式一致性
省略号使用与消息内容相同的样式：
```rust
Line::from("    …".dim().italic())  // queued_messages
Line::from("    …".dim())           // pending_steers
```

---

## 6. 风险边界与改进建议

### 当前限制
1. **硬编码限制**: `PREVIEW_LINE_LIMIT` 是编译时常量，无法动态调整
2. **无展开功能**: 用户无法查看被截断的完整内容
3. **截断提示简单**: 仅用 "…" 提示，不显示被截断的行数

### 改进建议
1. **可配置行数限制**
   ```rust
   pub fn with_line_limit(mut self, limit: usize) -> Self {
       self.line_limit = limit;
       self
   }
   ```

2. **展开/折叠功能**
   - 添加快捷键展开显示完整内容
   - 或使用鼠标点击展开

3. **更详细的截断提示**
   - 显示 "… (+N more lines)" 提示被截断的行数

4. **智能截断**
   - 在句子边界或段落边界截断，而非固定行数
   - 避免截断在单词中间

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
        "  ↳ This is                             ",
        "    a message                           ",
        "    with many                           ",
        "    …                                   ",
        "    ⌥ + ↑ edit last queued message      ",
    ],
    styles: [
        x: 0, y: 0, fg: Reset, bg: Reset, underline: Reset, modifier: DIM,
        x: 2, y: 0, fg: Reset, bg: Reset, underline: Reset, modifier: NONE,
        x: 0, y: 1, fg: Reset, bg: Reset, underline: Reset, modifier: DIM,
        x: 4, y: 1, fg: Reset, bg: Reset, underline: Reset, modifier: DIM | ITALIC,
        x: 11, y: 1, fg: Reset, bg: Reset, underline: Reset, modifier: NONE,
        x: 4, y: 2, fg: Reset, bg: Reset, underline: Reset, modifier: DIM | ITALIC,
        x: 13, y: 2, fg: Reset, bg: Reset, underline: Reset, modifier: NONE,
        x: 4, y: 3, fg: Reset, bg: Reset, underline: Reset, modifier: DIM | ITALIC,
        x: 13, y: 3, fg: Reset, bg: Reset, underline: Reset, modifier: NONE,
        x: 0, y: 4, fg: Reset, bg: Reset, underline: Reset, modifier: DIM | ITALIC,
        x: 5, y: 4, fg: Reset, bg: Reset, underline: Reset, modifier: NONE,
        x: 0, y: 5, fg: Reset, bg: Reset, underline: Reset, modifier: DIM,
        x: 34, y: 5, fg: Reset, bg: Reset, underline: Reset, modifier: NONE,
    ]
}
```
