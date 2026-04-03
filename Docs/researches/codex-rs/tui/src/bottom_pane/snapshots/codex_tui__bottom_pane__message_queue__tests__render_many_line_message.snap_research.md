# Render Many Line Message

## 1. 场景与职责 (Scene and Responsibility)

### 测试场景
Tests the rendering of a queued message containing multiple explicit newlines. This verifies the handling of multi-line messages and the truncation behavior when messages exceed the preview line limit.

### 组件职责
该快照测试针对 Codex TUI 的 **PendingInputPreview** 组件，负责验证：
- 多行消息（含显式换行符）的渲染
- 行数限制和截断行为
- 溢出指示器（…）的显示

## 2. 功能点目的 (Feature Purpose)

### 测试目标
Validates rendering of a multi-line message with truncation. The test creates a queue with a 4-line message and verifies that only the first 3 lines are shown with a "…" overflow indicator.

### 验证要点
1. 多行消息 "This is\na message\nwith many\nlines" 正确解析
2. 前 3 行完整显示
3. 第 4 行被截断，显示 "…" 指示器
4. 每行都有正确的前缀/缩进
5. 编辑提示正确显示
6. 整体高度计算正确（5 行：3 行内容 + 1 行省略号 + 1 行提示）

## 3. 具体技术实现 (Technical Implementation)

### 核心数据结构
```rust
// From pending_input_preview.rs

pub(crate) struct PendingInputPreview {
    pub pending_steers: Vec<String>,
    pub queued_messages: Vec<String>,  // ["This is\na message\nwith many\nlines"]
    edit_binding: key_hint::KeyBinding,
}

const PREVIEW_LINE_LIMIT: usize = 3;  // Max lines before truncation
```

### 渲染逻辑
- Splits message by `\n` using `.lines()`
- Each line wrapped independently
- After `PREVIEW_LINE_LIMIT` lines, adds overflow line
- Overflow line uses same indent as wrapped lines

### 关键算法
1. **Line Processing** (lines 105-117):
   ```rust
   for message in &self.queued_messages {
       let wrapped = adaptive_wrap_lines(
           message.lines().map(|line| Line::from(line.dim().italic())),
           RtOptions::new(width as usize)
               .initial_indent(Line::from("  ↳ ".dim()))
               .subsequent_indent(Line::from("    ")),
       );
       Self::push_truncated_preview_lines(&mut lines, wrapped, 
           Line::from("    …".dim().italic()));
   }
   ```

2. **Truncation Logic** (lines 48-58):
   ```rust
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

3. **Output at width 40**:
   ```
   "This is"
   "a message"
   "with many"
   "…"
   ```

## 4. 关键代码路径与文件引用 (Key Code Paths)

### 源文件
- **主文件**: `codex-rs/tui/src/bottom_pane/pending_input_preview.rs`

### 关键函数/方法
| 函数/方法 | 描述 |
|-----------|------|
| `render_many_line_message()` | Test function (lines 229-240) |
| `push_truncated_preview_lines()` | Handles line limiting (lines 48-58) |
| `message.lines()` | Splits by newline characters |

### 测试代码位置
- Test: `render_many_line_message()` (lines 229-240)
- Test setup:
  ```rust
  let mut queue = PendingInputPreview::new();
  queue.queued_messages.push(
      "This is\na message\nwith many\nlines".to_string()
  );
  let width = 40;
  let height = queue.desired_height(width);  // Returns 5
  ```

### 渲染输出示例
```
  ↳ This is
    a message
    with many
    …
    alt + ↑ edit
```

## 5. 依赖与外部交互 (Dependencies)

### 外部 Crates
| Crate | 用途 |
|-------|------|
| `ratatui` | TUI 渲染框架 |
| `insta` | 快照测试框架 |

### 内部模块依赖
- `crate::wrapping::adaptive_wrap_lines`

### 常量
- `PREVIEW_LINE_LIMIT: usize = 3` - 每消息最大预览行数

## 6. 风险、边界与改进建议 (Risks, Edge Cases, Improvements)

### 潜在风险
1. **空行处理**: 连续换行或末尾换行可能导致空行
2. **行数计算**: 自动换行 + 显式换行的组合可能超出预期
3. **溢出指示**: 用户可能不知道消息被截断

### 边界情况
- 消息为空字符串
- 消息只有换行符
- 消息超过 3 行但每行都很短
- 消息包含 Windows 换行符 `\r\n`

### 改进建议
1. **行数提示**: 显示 "(4 lines, 3 shown)" 提示
2. **展开功能**: 支持按键展开查看完整消息
3. **配置选项**: 允许用户设置预览行数限制
4. **智能截断**: 在段落边界而非固定行数截断
5. **滚动支持**: 在预览区域内支持滚动

### 相关文档
- `codex-rs/tui/styles.md` - 样式规范
- `AGENTS.md` - 项目级代理指南
