# PendingInputPreview 测试快照研究文档

## 文件信息
- **快照文件**: `codex_tui__bottom_pane__pending_input_preview__tests__render_pending_steers_above_queued_messages.snap`
- **源文件**: `codex-rs/tui/src/bottom_pane/pending_input_preview.rs`
- **测试函数**: `render_pending_steers_above_queued_messages`

---

## 1. 场景与职责

### 测试场景
本测试验证当 `pending_steers` 和 `queued_messages` 同时存在时的渲染顺序和布局。测试 steer 区域是否正确显示在 message 区域上方，以及两个区域之间的分隔。

### 业务场景
用户在系统执行工具调用期间：
1. 输入了 steer 指令（如 "Please continue.", "Check the last command output."）
2. 又输入了后续问题（如 "Queued follow-up question"）

组件需要同时显示两类内容，并清晰区分它们的处理顺序。

### 组件职责
- 优先显示 pending steers（将在下一个工具调用后提交）
- 其次显示 queued messages（将在 steers 之后提交）
- 在两个区域之间添加空行分隔
- 只在 queued messages 区域显示编辑提示

---

## 2. 功能点目的

### 核心功能验证
1. **区域顺序**: 验证 steers 显示在 messages 上方
2. **区域分隔**: 验证两个区域之间有空行分隔
3. **独立样式**: 验证两个区域保持各自的样式
4. **条件编辑提示**: 验证编辑提示只在有 queued messages 时显示

### 用户体验目标
- 清晰展示消息处理的优先级顺序
- 通过空行分隔避免视觉混淆
- 让用户理解 steers 会先被处理

---

## 3. 具体技术实现

### 测试数据
```rust
let mut queue = PendingInputPreview::new();
queue.pending_steers.push("Please continue.".to_string());
queue.pending_steers.push("Check the last command output.".to_string());
queue.queued_messages.push("Queued follow-up question".to_string());
let width = 52;
```

### 渲染输出分析
```
Buffer {
    area: Rect { x: 0, y: 0, width: 52, height: 8 },
    content: [
        "• Messages to be submitted after next tool call     ",  // 第0行：steer标题
        "  (press esc to interrupt and send immediately)     ",  // 第1行：中断提示
        "  ↳ Please continue.                                ",  // 第2行：steer1
        "  ↳ Check the last command output.                  ",  // 第3行：steer2
        "                                                    ",  // 第4行：空行分隔
        "• Queued follow-up messages                         ",  // 第5行：message标题
        "  ↳ Queued follow-up question                       ",  // 第6行：message1
        "    ⌥ + ↑ edit last queued message                  ",  // 第7行：编辑提示
    ],
    ...
}
```

### 区域结构
```
┌─────────────────────────────────────────────────────┐
│ • Messages to be submitted after next tool call     │  steer 标题
 │   (press esc to interrupt and send immediately)     │  中断提示
 │   ↳ Please continue.                                │  steer 1
 │   ↳ Check the last command output.                  │  steer 2
│                                                     │  空行分隔
│ • Queued follow-up messages                         │  message 标题
 │   ↳ Queued follow-up question                       │  message 1
 │     ⌥ + ↑ edit last queued message                  │  编辑提示
└─────────────────────────────────────────────────────┘
```

---

## 4. 关键代码路径与文件引用

### 区域分隔逻辑 (lines 99-102)
```rust
if !self.queued_messages.is_empty() {
    if !lines.is_empty() {
        lines.push(Line::from(""));  // 添加空行分隔
    }
    Self::push_section_header(&mut lines, width, "Queued follow-up messages".into());
    // ...
}
```

### 渲染顺序
```rust
fn as_renderable(&self, width: u16) -> Box<dyn Renderable> {
    // 1. 先处理 pending_steers
    if !self.pending_steers.is_empty() {
        // ... 添加 steer 区域内容
    }
    
    // 2. 再处理 queued_messages
    if !self.queued_messages.is_empty() {
        // ... 添加 message 区域内容
    }
    
    // 3. 最后添加编辑提示（只在有 messages 时）
    if !self.queued_messages.is_empty() {
        // ... 添加编辑提示
    }
}
```

### 高度计算
- steer 标题：1行
- 中断提示：1行
- steer 内容：2行
- 空行分隔：1行
- message 标题：1行
- message 内容：1行
- 编辑提示：1行
- **总计：8行**

---

## 5. 依赖与外部交互

### 样式对比
| 元素 | Steer 区域 | Message 区域 |
|---|---|---|
| 标题前缀 | "• " DIM | "• " DIM |
| 内容前缀 | "  ↳ " DIM | "  ↳ " DIM |
| 内容样式 | dim() | dim().italic() |
| 特殊提示 | "(press esc...)" DIM | "⌥ + ↑ ..." DIM |

### 条件渲染
```rust
// 编辑提示只在有 queued_messages 时显示
if !self.queued_messages.is_empty() {
    lines.push(Line::from(vec![
        "    ".into(),
        self.edit_binding.into(),
        " edit last queued message".into(),
    ]).dim());
}
```

---

## 6. 风险边界与改进建议

### 当前限制
1. **固定顺序**: steers 总是在 messages 上方，无法调整
2. **单一分隔**: 仅使用空行分隔，可能不够明显
3. **无优先级提示**: 用户可能不清楚为什么 steers 先显示

### 改进建议
1. **视觉分隔增强**
   - 使用分隔线（如 "─────────────────"）代替空行
   - 或使用不同背景色区分区域

2. **处理顺序提示**
   - 添加数字标记（如 "1.", "2."）表示处理顺序
   - 或添加文字说明 "Will be sent first:"

3. **可折叠区域**
   - 允许用户折叠/展开 steer 或 message 区域
   - 节省垂直空间

4. **交互式重排**
   - 允许用户调整 steer 和 message 的顺序
   - 或提供 "Move to queue" / "Move to steers" 功能

---

## 附录：完整快照内容

```
---
source: tui/src/bottom_pane/pending_input_preview.rs
expression: "format!(\"{buf:?}\")"
---
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
    styles: [
        x: 0, y: 0, fg: Reset, bg: Reset, underline: Reset, modifier: DIM,
        x: 2, y: 0, fg: Reset, bg: Reset, underline: Reset, modifier: NONE,
        x: 0, y: 1, fg: Reset, bg: Reset, underline: Reset, modifier: DIM,
        x: 47, y: 1, fg: Reset, bg: Reset, underline: Reset, modifier: NONE,
        x: 0, y: 2, fg: Reset, bg: Reset, underline: Reset, modifier: DIM,
        x: 20, y: 2, fg: Reset, bg: Reset, underline: Reset, modifier: NONE,
        x: 0, y: 3, fg: Reset, bg: Reset, underline: Reset, modifier: DIM,
        x: 34, y: 3, fg: Reset, bg: Reset, underline: Reset, modifier: NONE,
        x: 0, y: 5, fg: Reset, bg: Reset, underline: Reset, modifier: DIM,
        x: 2, y: 5, fg: Reset, bg: Reset, underline: Reset, modifier: NONE,
        x: 0, y: 6, fg: Reset, bg: Reset, underline: Reset, modifier: DIM,
        x: 4, y: 6, fg: Reset, bg: Reset, underline: Reset, modifier: DIM | ITALIC,
        x: 29, y: 6, fg: Reset, bg: Reset, underline: Reset, modifier: NONE,
        x: 0, y: 7, fg: Reset, bg: Reset, underline: Reset, modifier: DIM,
        x: 34, y: 7, fg: Reset, bg: Reset, underline: Reset, modifier: NONE,
    ]
}
```
