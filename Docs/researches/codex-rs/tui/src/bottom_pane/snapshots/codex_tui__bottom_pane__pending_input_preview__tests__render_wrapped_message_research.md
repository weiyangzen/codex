# PendingInputPreview 测试快照研究文档

## 文件信息
- **快照文件**: `codex_tui__bottom_pane__pending_input_preview__tests__render_wrapped_message.snap`
- **源文件**: `codex-rs/tui/src/bottom_pane/pending_input_preview.rs`
- **测试函数**: `render_wrapped_message`

---

## 1. 场景与职责

### 测试场景
本测试验证当单条消息内容超过可用宽度时的自动换行行为。测试 `adaptive_wrap_lines` 函数是否正确处理长文本的换行，以及换行后的样式保持。

### 业务场景
用户输入了一条较长的消息，在40字符宽度的显示区域需要跨越多行显示。组件需要智能地换行并保持视觉层次。

### 组件职责
- 自动检测内容宽度并执行换行
- 保持首行和后续行的不同缩进（initial_indent vs subsequent_indent）
- 确保换行后的内容样式一致

---

## 2. 功能点目的

### 核心功能验证
1. **自动换行**: 验证长消息自动换行到多行
2. **缩进一致性**: 验证首行有 "↳" 前缀，后续行有统一缩进
3. **样式继承**: 验证换行后的文本保持 dim().italic() 样式
4. **多条消息换行**: 验证一条消息换行不影响其他消息的渲染

### 用户体验目标
- 长消息不换行溢出边界
- 通过缩进清晰展示消息的延续性
- 保持整体视觉整洁

---

## 3. 具体技术实现

### 测试数据
```rust
let mut queue = PendingInputPreview::new();
queue.queued_messages.push("This is a longer message that should be wrapped".to_string());
queue.queued_messages.push("This is another message".to_string());
let width = 40;
```

### 渲染输出分析
```
Buffer {
    area: Rect { x: 0, y: 0, width: 40, height: 5 },
    content: [
        "• Queued follow-up messages             ",  // 第0行：标题
        "  ↳ This is a longer message that should",  // 第1行：消息1第1行
        "    be wrapped                          ",  // 第2行：消息1第2行
        "  ↳ This is another message             ",  // 第3行：消息2
        "    ⌥ + ↑ edit last queued message      ",  // 第4行：编辑提示
    ],
    ...
}
```

### 换行分析
- 可用宽度：40 - 4（"  ↳ " 前缀）= 36字符
- 消息1内容："This is a longer message that should be wrapped"（45字符）
- 换行结果：
  - 第1行："This is a longer message that should"（36字符）
  - 第2行："be wrapped"（10字符，前有4空格缩进）

### 样式映射
| 行 | 列范围 | 样式 |
|---|---|---|
| 1 | 0-3 | DIM ("  ↳ ") |
| 1 | 4-39 | DIM\|ITALIC (内容) |
| 2 | 0-3 | NONE (缩进) |
| 2 | 4-13 | DIM\|ITALIC (内容) |
| 2 | 14-39 | NONE (剩余) |

---

## 4. 关键代码路径与文件引用

### 换行配置
```rust
let wrapped = adaptive_wrap_lines(
    message.lines().map(|line| Line::from(line.dim().italic())),
    RtOptions::new(width as usize)
        .initial_indent(Line::from("  ↳ ".dim()))
        .subsequent_indent(Line::from("    ")),
);
```

### 关键参数
- `initial_indent`: "  ↳ "（4字符，含箭头符号）
- `subsequent_indent`: "    "（4空格）
- 换行后第2行只有缩进，没有箭头符号

### wrapping.rs 中的处理
```rust
pub(crate) fn adaptive_wrap_lines<'a, I, L>(
    lines: I,
    width_or_options: RtOptions<'a>,
) -> Vec<Line<'static>>
```

该函数：
1. 检测内容中是否包含 URL
2. 根据检测结果选择换行策略
3. 应用 initial_indent 到第一行
4. 应用 subsequent_indent 到后续行

---

## 5. 依赖与外部交互

### textwrap 集成
- 使用 `textwrap` crate 进行核心换行计算
- `adaptive_wrap_lines` 是对 `textwrap::wrap` 的包装
- 支持 URL 感知换行（避免在 URL 中间断开）

### 样式保持机制
```rust
message.lines().map(|line| Line::from(line.dim().italic()))
```
- 先将每行文本转换为带样式的 Line
- 然后传递给 wrapping 函数
- wrapping 函数保持原始样式并应用到换行后的片段

---

## 6. 风险边界与改进建议

### 当前限制
1. **硬编码缩进**: 4字符缩进在极窄宽度下可能占用过多空间
2. **无断词提示**: 换行处没有连字符或其他提示
3. **URL 处理**: 虽然支持 URL 感知换行，但在本测试中未验证

### 改进建议
1. **动态缩进**
   - 根据可用宽度动态调整缩进大小
   - 极窄宽度下使用更小的缩进或省略箭头

2. **断词提示**
   - 考虑添加软连字符或视觉提示
   - 帮助用户识别单词被截断的位置

3. **URL 测试覆盖**
   - 添加包含 URL 的长消息测试
   - 验证 URL 不被截断

4. **多语言支持**
   - 测试 CJK 字符的换行
   - 测试从右到左语言的渲染

---

## 附录：完整快照内容

```
---
source: tui/src/bottom_pane/pending_input_preview.rs
expression: "format!(\"{buf:?}\")"
---
Buffer {
    area: Rect { x: 0, y: 0, width: 40, height: 5 },
    content: [
        "• Queued follow-up messages             ",
        "  ↳ This is a longer message that should",
        "    be wrapped                          ",
        "  ↳ This is another message             ",
        "    ⌥ + ↑ edit last queued message      ",
    ],
    styles: [
        x: 0, y: 0, fg: Reset, bg: Reset, underline: Reset, modifier: DIM,
        x: 2, y: 0, fg: Reset, bg: Reset, underline: Reset, modifier: NONE,
        x: 0, y: 1, fg: Reset, bg: Reset, underline: Reset, modifier: DIM,
        x: 4, y: 1, fg: Reset, bg: Reset, underline: Reset, modifier: DIM | ITALIC,
        x: 0, y: 2, fg: Reset, bg: Reset, underline: Reset, modifier: NONE,
        x: 4, y: 2, fg: Reset, bg: Reset, underline: Reset, modifier: DIM | ITALIC,
        x: 14, y: 2, fg: Reset, bg: Reset, underline: Reset, modifier: NONE,
        x: 0, y: 3, fg: Reset, bg: Reset, underline: Reset, modifier: DIM,
        x: 4, y: 3, fg: Reset, bg: Reset, underline: Reset, modifier: DIM | ITALIC,
        x: 27, y: 3, fg: Reset, bg: Reset, underline: Reset, modifier: NONE,
        x: 0, y: 4, fg: Reset, bg: Reset, underline: Reset, modifier: DIM,
        x: 34, y: 4, fg: Reset, bg: Reset, underline: Reset, modifier: NONE,
    ]
}
```
