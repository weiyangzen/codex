# Pending Input Preview - Render Many Line Message

## 1. 场景与职责 (Scene and Responsibility)

### 测试场景
Tests the rendering of a multi-line queued message in the PendingInputPreview component. This differs from message_queue tests by including the section header "Queued follow-up messages" and using a different edit binding display.

### 组件职责
该快照测试针对 Codex TUI 的 **PendingInputPreview** 组件，负责验证：
- 带标题的多行消息预览渲染
- 章节标题 "Queued follow-up messages" 的显示
- 多行消息的截断和溢出指示
- 编辑提示的显示（使用 ⌥ + ↑ 符号）

## 2. 功能点目的 (Feature Purpose)

### 测试目标
Validates rendering of a multi-line queued message with section header. The test creates a preview with a 4-line message and verifies the header, message truncation, and edit hint are all correctly displayed.

### 验证要点
1. 章节标题 "• Queued follow-up messages" 正确显示
2. 多行消息 "This is\na message\nwith many\nlines" 正确渲染
3. 前 3 行显示，第 4 行显示为 "…"
4. 编辑提示 "⌥ + ↑ edit last queued message" 正确显示
5. 标题使用 dim 样式，消息使用 dim + italic 样式
6. 整体高度计算正确（6 行：标题 + 3 行内容 + 省略号 + 提示）

## 3. 具体技术实现 (Technical Implementation)

### 核心数据结构
```rust
// From pending_input_preview.rs

pub(crate) struct PendingInputPreview {
    pub pending_steers: Vec<String>,     // Empty in this test
    pub queued_messages: Vec<String>,    // ["This is\na message\nwith many\nlines"]
    edit_binding: key_hint::KeyBinding,  // Alt+Up default
}

const PREVIEW_LINE_LIMIT: usize = 3;
```

### 渲染逻辑
- Renders section header with bullet point: "• Queued follow-up messages"
- Header wrapped with `adaptive_wrap_lines()`
- Each queued message rendered with prefix "↳ "
- Multi-line messages truncated at 3 lines
- Edit hint at bottom with key binding symbol

### 关键算法
1. **Section Header** (lines 99-103):
   ```rust
   Self::push_section_header(&mut lines, width, "Queued follow-up messages".into());
   ```

2. **Header Rendering** (lines 60-67):
   ```rust
   fn push_section_header(lines: &mut Vec<Line<'static>>, width: u16, header: Line<'static>) {
       let mut spans = vec!["• ".dim()];
       spans.extend(header.spans);
       lines.extend(adaptive_wrap_lines(...));
   }
   ```

3. **Edit Hint** (lines 120-129):
   ```rust
   lines.push(
       Line::from(vec![
           "    ".into(),
           self.edit_binding.into(),  // Shows as "⌥ + ↑"
           " edit last queued message".into(),
       ])
       .dim(),
   );
   ```

## 4. 关键代码路径与文件引用 (Key Code Paths)

### 源文件
- **主文件**: `codex-rs/tui/src/bottom_pane/pending_input_preview.rs`

### 关键函数/方法
| 函数/方法 | 描述 |
|-----------|------|
| `render_many_line_message()` | Test function (lines 229-240) |
| `push_section_header()` | Renders bullet header (lines 60-67) |
| `as_renderable()` | Main rendering logic (lines 69-132) |
| `push_truncated_preview_lines()` | Handles truncation (lines 48-58) |

### 测试代码位置
- Test: `render_many_line_message()` (lines 229-240)
- Same test name as message_queue but different source file
- Renders at width 40, height 6

### 渲染输出示例
```
• Queued follow-up messages
  ↳ This is
    a message
    with many
    …
    ⌥ + ↑ edit last queued message
```

## 5. 依赖与外部交互 (Dependencies)

### 外部 Crates
| Crate | 用途 |
|-------|------|
| `ratatui` | TUI 渲染框架 |
| `crossterm` | 终端控制，KeyCode |
| `insta` | 快照测试框架 |

### 内部模块依赖
- `crate::key_hint` - 键盘提示，支持符号显示
- `crate::wrapping::adaptive_wrap_lines`
- `crate::wrapping::RtOptions`

### 样式应用
- `"• "` - dim
- `"Queued follow-up messages"` - default
- Message text - dim + italic
- `"…"` - dim + italic
- Edit hint - dim

## 6. 风险、边界与改进建议 (Risks, Edge Cases, Improvements)

### 潜在风险
1. **章节标题截断**: 长标题可能被截断
2. **符号兼容性**: ⌥ 符号在某些终端可能显示异常
3. **空章节**: pending_steers 和 queued_messages 都为空时无输出

### 边界情况
- 只有 pending_steers，没有 queued_messages（不显示 edit hint）
- 只有 queued_messages，没有 pending_steers
- 两者都有，需要空行分隔
- 终端宽度小于标题长度

### 改进建议
1. **章节折叠**: 支持折叠/展开章节
2. **消息计数**: 标题显示 "Queued follow-up messages (4)"
3. **时间戳**: 显示消息等待时间
4. **优先级指示**: 区分 steer 和 message 的优先级
5. **快速编辑**: 支持点击/选择直接编辑某条消息

### 相关文档
- `codex-rs/tui/styles.md` - 样式规范
- `codex-rs/tui/src/key_hint.rs` - 键盘提示实现
- `AGENTS.md` - 项目级代理指南

### 与 message_queue 的关系
This snapshot is from `pending_input_preview.rs` but has the same test name as one in `message_queue.rs`. The key differences:
- PendingInputPreview includes section headers
- PendingInputPreview shows "⌥ + ↑" instead of "alt + ↑"
- PendingInputPreview has additional "edit last queued message" text
- PendingInputPreview can show both pending_steers and queued_messages sections
