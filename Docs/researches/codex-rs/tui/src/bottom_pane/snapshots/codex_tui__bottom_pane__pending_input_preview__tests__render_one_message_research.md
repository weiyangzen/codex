# PendingInputPreview 测试快照研究文档

## 文件信息
- **快照文件**: `codex_tui__bottom_pane__pending_input_preview__tests__render_one_message.snap`
- **源文件**: `codex-rs/tui/src/bottom_pane/pending_input_preview.rs`
- **测试函数**: `render_one_message`

---

## 1. 场景与职责

### 测试场景
本测试验证 `PendingInputPreview` 组件在只有一个排队消息时的基本渲染行为。这是该组件最基础的使用场景，用于确认单条消息的渲染格式、样式和布局是否正确。

### 业务场景
在 TUI 应用中，当用户提交一条消息但系统正在处理前一条消息时，新消息会被放入 `queued_messages` 队列。`PendingInputPreview` 负责在底部面板显示这些待处理的消息，让用户知道他们的输入已被接收并将在适当时候发送。

### 组件职责
- 显示排队等待发送的用户消息
- 提供编辑最后一条排队消息的快捷键提示
- 使用视觉层次（缩进、符号、样式）区分不同消息

---

## 2. 功能点目的

### 核心功能验证
1. **单条消息渲染**: 验证组件能正确渲染一条排队消息
2. **标题显示**: 验证 "Queued follow-up messages" 标题正确显示
3. **消息前缀**: 验证消息前有 "↳" 符号作为视觉指示器
4. **编辑提示**: 验证显示 "⌥ + ↑ edit last queued message" 快捷键提示
5. **样式应用**: 验证正确应用 DIM（暗淡）和 ITALIC（斜体）样式

### 用户体验目标
- 让用户清楚地看到已排队等待发送的消息
- 提供直观的键盘快捷键提示，方便用户编辑消息
- 通过视觉样式区分标题、消息内容和提示信息

---

## 3. 具体技术实现

### 测试数据
```rust
let mut queue = PendingInputPreview::new();
queue.queued_messages.push("Hello, world!".to_string());
let width = 40;
```

### 渲染输出分析
```
Buffer {
    area: Rect { x: 0, y: 0, width: 40, height: 3 },
    content: [
        "• Queued follow-up messages             ",  // 第0行：标题
        "  ↳ Hello, world!                       ",  // 第1行：消息内容
        "    ⌥ + ↑ edit last queued message      ",  // 第2行：编辑提示
    ],
    ...
}
```

### 样式映射
| 行 | 列范围 | 样式 | 说明 |
|---|---|---|---|
| 0 | 0-1 | DIM | "• " 符号暗淡显示 |
| 0 | 2-26 | NONE | 标题文本正常显示 |
| 1 | 0-3 | DIM | "  ↳ " 前缀暗淡显示 |
| 1 | 4-16 | DIM \| ITALIC | 消息内容暗淡+斜体 |
| 1 | 17-39 | NONE | 剩余空间 |
| 2 | 0-33 | DIM | 编辑提示整体暗淡 |
| 2 | 34-39 | NONE | 剩余空间 |

---

## 4. 关键代码路径与文件引用

### 渲染流程
```
pending_input_preview.rs::render()
  └─> as_renderable()
      └─> 检查 queued_messages 是否为空
      └─> push_section_header()  // 添加标题
      └─> adaptive_wrap_lines()  // 包装消息文本 (wrapping.rs)
      └─> push_truncated_preview_lines()  // 添加截断处理
      └─> 添加编辑提示行
  └─> Paragraph::new(lines).into()  // 创建可渲染对象
```

### 关键代码段

**标题渲染** (lines 99-103):
```rust
if !self.queued_messages.is_empty() {
    if !lines.is_empty() {
        lines.push(Line::from(""));
    }
    Self::push_section_header(&mut lines, width, "Queued follow-up messages".into());
    // ...
}
```

**消息渲染** (lines 105-117):
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

**编辑提示渲染** (lines 120-129):
```rust
if !self.queued_messages.is_empty() {
    lines.push(
        Line::from(vec![
            "    ".into(),
            self.edit_binding.into(),  // 转换为 KeyBinding 显示
            " edit last queued message".into(),
        ])
        .dim(),
    );
}
```

### 依赖文件
- `codex-rs/tui/src/wrapping.rs`: 提供 `adaptive_wrap_lines` 和 `RtOptions`
- `codex-rs/tui/src/key_hint.rs`: 提供 `KeyBinding` 和快捷键显示转换
- `codex-rs/tui/src/render/renderable.rs`: 提供 `Renderable` trait

---

## 5. 依赖与外部交互

### 外部 crate 依赖
| Crate | 用途 |
|---|---|
| `ratatui` | 提供 `Buffer`, `Rect`, `Line`, `Paragraph`, `Stylize` trait |
| `crossterm` | 提供 `KeyCode` 用于快捷键定义 |
| `insta` | 快照测试框架 |
| `pretty_assertions` | 测试断言增强 |

### 内部模块依赖
```rust
use crate::key_hint;
use crate::render::renderable::Renderable;
use crate::wrapping::RtOptions;
use crate::wrapping::adaptive_wrap_lines;
```

### 样式系统
- 使用 `ratatui::style::Stylize` trait 提供 `.dim()` 和 `.italic()` 方法
- 样式继承：消息内容同时应用 `dim()` 和 `italic()`

---

## 6. 风险边界与改进建议

### 当前风险与边界

1. **宽度限制处理**
   - 当 `width < 4` 时，组件返回空渲染 (line 70-71)
   - 风险：极窄宽度下内容可能被完全隐藏，用户无法看到排队消息

2. **行数限制**
   - `PREVIEW_LINE_LIMIT = 3` 限制每条消息最多显示3行
   - 超过部分显示 "…" 省略号
   - 风险：长消息可能被截断，用户看不到完整内容

3. **硬编码样式**
   - 缩进级别（2空格、4空格）和符号（•、↳）硬编码
   - 风险：难以适应不同的主题或本地化需求

### 改进建议

1. **可配置性增强**
   ```rust
   // 建议：添加配置选项
   pub struct PreviewConfig {
       pub max_lines_per_message: usize,
       pub indent_sizes: IndentSizes,
       pub symbols: PreviewSymbols,
   }
   ```

2. **宽度警告**
   - 在宽度不足以显示内容时，可以显示简化提示而非完全隐藏

3. **滚动支持**
   - 对于被截断的长消息，考虑添加滚动或展开功能

4. **国际化支持**
   - 将标题和提示文本提取到可配置的资源文件中

### 测试覆盖建议
- 添加边界宽度测试（width = 3, 4, 5）
- 添加空消息测试
- 添加特殊字符消息测试
- 添加超长单行消息测试

---

## 附录：完整快照内容

```
---
source: tui/src/bottom_pane/pending_input_preview.rs
expression: "format!(\"{buf:?}\")"
---
Buffer {
    area: Rect { x: 0, y: 0, width: 40, height: 3 },
    content: [
        "• Queued follow-up messages             ",
        "  ↳ Hello, world!                       ",
        "    ⌥ + ↑ edit last queued message      ",
    ],
    styles: [
        x: 0, y: 0, fg: Reset, bg: Reset, underline: Reset, modifier: DIM,
        x: 2, y: 0, fg: Reset, bg: Reset, underline: Reset, modifier: NONE,
        x: 0, y: 1, fg: Reset, bg: Reset, underline: Reset, modifier: DIM,
        x: 4, y: 1, fg: Reset, bg: Reset, underline: Reset, modifier: DIM | ITALIC,
        x: 17, y: 1, fg: Reset, bg: Reset, underline: Reset, modifier: NONE,
        x: 0, y: 2, fg: Reset, bg: Reset, underline: Reset, modifier: DIM,
        x: 34, y: 2, fg: Reset, bg: Reset, underline: Reset, modifier: NONE,
    ]
}
```
