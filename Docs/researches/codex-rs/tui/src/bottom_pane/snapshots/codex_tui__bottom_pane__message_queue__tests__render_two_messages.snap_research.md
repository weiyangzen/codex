# Render Two Messages

## 1. 场景与职责 (Scene and Responsibility)

### 测试场景
Tests the rendering of two queued messages in the message queue. This verifies the UI correctly displays multiple messages stacked vertically with proper spacing and styling.

### 组件职责
该快照测试针对 Codex TUI 的 **PendingInputPreview** 组件，负责验证：
- 多个排队消息的 UI 渲染
- 消息之间的正确分隔
- 每个消息的独立前缀和缩进

## 2. 功能点目的 (Feature Purpose)

### 测试目标
Validates rendering of two queued messages. The test creates a queue with messages "Hello, world!" and "This is another message" and verifies the UI correctly displays both with proper styling.

### 验证要点
1. 第一个消息 "Hello, world!" 正确渲染
2. 第二个消息 "This is another message" 正确渲染
3. 每个消息都有独立的前缀 "↳ "
4. 消息文本使用 dim + italic 样式
5. 单个编辑提示显示在底部（不是每个消息一个）
6. 整体高度计算正确（3 行：消息1 + 消息2 + 提示）

## 3. 具体技术实现 (Technical Implementation)

### 核心数据结构
```rust
// From pending_input_preview.rs

pub(crate) struct PendingInputPreview {
    pub pending_steers: Vec<String>,     // Empty in this test
    pub queued_messages: Vec<String>,    // ["Hello, world!", "This is another message"]
    edit_binding: key_hint::KeyBinding,  // Alt+Up default
}

const PREVIEW_LINE_LIMIT: usize = 3;
```

### 渲染逻辑
- Iterates over `queued_messages` vector
- Each message wrapped independently with `adaptive_wrap_lines()`
- All messages share the same styling: `dim().italic()`
- Single edit hint at bottom: "alt + ↑ edit"
- No empty line between messages (compact layout)

### 关键算法
1. **Message Iteration** (lines 105-117):
   ```rust
   for message in &self.queued_messages {
       let wrapped = adaptive_wrap_lines(
           message.lines().map(|line| Line::from(line.dim().italic())),
           RtOptions::new(width as usize)
               .initial_indent(Line::from("  ↳ ".dim()))
               .subsequent_indent(Line::from("    ")),
       );
       Self::push_truncated_preview_lines(&mut lines, wrapped, ...);
   }
   ```

2. **Height Calculation**:
   - Each message: 1 line (short messages don't wrap at width 40)
   - Edit hint: 1 line
   - Total: 3 lines

## 4. 关键代码路径与文件引用 (Key Code Paths)

### 源文件
- **主文件**: `codex-rs/tui/src/bottom_pane/pending_input_preview.rs`

### 关键函数/方法
| 函数/方法 | 描述 |
|-----------|------|
| `render_two_messages()` | Test function (lines 179-191) |
| `as_renderable()` | Builds Paragraph with all messages (lines 69-132) |
| `adaptive_wrap_lines()` | Wraps each message text |
| `push_truncated_preview_lines()` | Adds lines with 3-line limit |

### 测试代码位置
- Test: `render_two_messages()` (lines 179-191)
- Test setup:
  ```rust
  let mut queue = PendingInputPreview::new();
  queue.queued_messages.push("Hello, world!".to_string());
  queue.queued_messages.push("This is another message".to_string());
  let width = 40;
  let height = queue.desired_height(width);  // Returns 3
  ```

### 渲染输出示例
```
  ↳ Hello, world!
  ↳ This is another message
    alt + ↑ edit
```

## 5. 依赖与外部交互 (Dependencies)

### 外部 Crates
| Crate | 用途 |
|-------|------|
| `ratatui` | TUI 渲染框架 |
| `insta` | 快照测试框架 |
| `pretty_assertions` | 测试断言 |

### 内部模块依赖
- `crate::render::renderable::Renderable`
- `crate::key_hint`
- `crate::wrapping::adaptive_wrap_lines`

### 样式应用
- `DIM` - 前缀和提示
- `DIM | ITALIC` - 消息文本

## 6. 风险、边界与改进建议 (Risks, Edge Cases, Improvements)

### 潜在风险
1. **消息顺序**: 消息顺序与向量顺序一致，需要确保 FIFO
2. **内存增长**: 大量消息可能导致内存问题
3. **渲染性能**: 大量消息时渲染可能变慢

### 边界情况
- 两个消息都为空字符串
- 消息内容完全相同
- 终端高度只够显示部分消息
- 消息数量超过合理限制

### 改进建议
1. **消息分隔线**: 在消息之间添加 subtle 分隔线
2. **消息编号**: 显示消息序号（#1, #2）
3. **批量操作**: 支持批量删除或编辑消息
4. **最大限制**: 设置最大消息数限制，防止内存问题
5. **折叠显示**: 消息过多时折叠显示 "+N more"

### 相关文档
- `codex-rs/tui/styles.md` - TUI 样式规范
- `AGENTS.md` - 项目级代理指南
