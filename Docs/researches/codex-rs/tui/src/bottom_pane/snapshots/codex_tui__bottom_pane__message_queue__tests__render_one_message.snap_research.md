# Render One Message

## 1. 场景与职责 (Scene and Responsibility)

### 测试场景
Tests the rendering of a single queued message in the message queue. This represents the simplest case of the message queue displaying one user message that has been queued while a turn is in progress.

### 组件职责
该快照测试针对 Codex TUI 的 **PendingInputPreview** 组件（原 message_queue.rs），负责验证：
- 单个排队消息的 UI 渲染
- 消息前缀和缩进样式
- 编辑提示的显示

## 2. 功能点目的 (Feature Purpose)

### 测试目标
Validates rendering of a single queued message. The test creates a queue with one message "Hello, world!" and verifies the UI correctly displays the message with proper styling and the edit hint.

### 验证要点
1. 单个消息 "Hello, world!" 正确渲染
2. 消息前缀 "↳ " 使用 dim 样式
3. 消息文本使用 dim + italic 样式
4. 编辑提示 "alt + ↑ edit" 正确显示
5. 整体高度计算正确（2 行：消息 + 提示）

## 3. 具体技术实现 (Technical Implementation)

### 核心数据结构
```rust
// From pending_input_preview.rs (formerly message_queue.rs)

pub(crate) struct PendingInputPreview {
    pub pending_steers: Vec<String>,     // Empty in this test
    pub queued_messages: Vec<String>,    // Contains ["Hello, world!"]
    edit_binding: key_hint::KeyBinding,  // Alt+Up default
}

const PREVIEW_LINE_LIMIT: usize = 3;  // Max lines per message before truncation
```

### 渲染逻辑
- Uses `as_renderable()` to create a `Paragraph` widget
- Each message wrapped with `adaptive_wrap_lines()` for text wrapping
- Message styling: `line.dim().italic()`
- Prefix styling: `"↳ ".dim()`
- Initial indent: `"  ↳ "` (2 spaces + arrow)
- Subsequent indent: `"    "` (4 spaces)
- Edit hint shown at bottom when queue not empty

### 关键算法
1. **Message Wrapping** (lines 105-117):
   ```rust
   let wrapped = adaptive_wrap_lines(
       message.lines().map(|line| Line::from(line.dim().italic())),
       RtOptions::new(width as usize)
           .initial_indent(Line::from("  ↳ ".dim()))
           .subsequent_indent(Line::from("    ")),
   );
   ```

2. **Truncation** (lines 48-58):
   - Takes up to `PREVIEW_LINE_LIMIT` lines
   - Adds overflow line "…" if truncated

3. **Height Calculation** (lines 144-146):
   - Delegates to `as_renderable().desired_height()`

## 4. 关键代码路径与文件引用 (Key Code Paths)

### 源文件
- **主文件**: `codex-rs/tui/src/bottom_pane/pending_input_preview.rs`
- **注意**: The snapshot source indicates `message_queue.rs` but the actual implementation is in `pending_input_preview.rs`

### 关键函数/方法
| 函数/方法 | 描述 |
|-----------|------|
| `PendingInputPreview::new()` | Creates empty preview (lines 32-39) |
| `render_one_message()` | Test function (lines 168-177) |
| `as_renderable()` | Builds Paragraph widget (lines 69-132) |
| `push_truncated_preview_lines()` | Adds lines with overflow handling (lines 48-58) |
| `desired_height()` | Calculates required height (lines 144-146) |
| `adaptive_wrap_lines()` | From wrapping.rs, handles text wrapping |

### 测试代码位置
- Test: `render_one_message()` (lines 168-177)
- Test setup:
  ```rust
  let mut queue = PendingInputPreview::new();
  queue.queued_messages.push("Hello, world!".to_string());
  let width = 40;
  let height = queue.desired_height(width);  // Returns 2
  ```

### 渲染输出示例
```
  ↳ Hello, world!
    alt + ↑ edit
```

## 5. 依赖与外部交互 (Dependencies)

### 外部 Crates
| Crate | 用途 |
|-------|------|
| `ratatui` | TUI 渲染框架，提供 Buffer、Rect、Paragraph |
| `crossterm` | 跨平台终端控制，KeyCode 定义 |
| `insta` | 快照测试框架 |
| `pretty_assertions` | 测试断言 |

### 内部模块依赖
- `crate::render::renderable::Renderable` - 可渲染组件 trait
- `crate::key_hint` - 键盘提示生成
- `crate::wrapping::adaptive_wrap_lines` - 自适应文本换行
- `crate::wrapping::RtOptions` - 换行选项

### 样式应用
- `DIM` modifier - 降低亮度
- `ITALIC` modifier - 斜体样式
- Combined: `DIM | ITALIC` for message text

## 6. 风险、边界与改进建议 (Risks, Edge Cases, Improvements)

### 潜在风险
1. **宽度计算错误**: Unicode 字符宽度计算可能导致换行不准确
2. **样式叠加**: DIM + ITALIC 在某些终端可能显示异常
3. **缩进不一致**: 手动缩进字符串容易出错

### 边界情况
- 空消息字符串渲染为空行
- 消息包含换行符时的多行处理
- 终端宽度小于缩进宽度时的处理
- 非常长的单字（如 URL）不换行但截断

### 改进建议
1. **最大宽度限制**: 即使终端很宽，也限制消息预览的最大宽度
2. **消息计数**: 显示 "N messages queued" 提示
3. **时间戳**: 显示消息排队时间
4. **消息预览开关**: 允许用户关闭消息预览
5. **键盘导航**: 支持在预览中滚动查看完整消息

### 相关文档
- `codex-rs/tui/styles.md` - TUI 样式规范
- `codex-rs/tui/src/wrapping.rs` - 文本换行工具
- `AGENTS.md` - 项目级代理指南
