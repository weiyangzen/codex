# Render Wrapped Message

## 1. 场景与职责 (Scene and Responsibility)

### 测试场景
Tests the rendering of queued messages where the first message needs to wrap due to length. This verifies the text wrapping logic correctly handles long messages that exceed the available width.

### 组件职责
该快照测试针对 Codex TUI 的 **PendingInputPreview** 组件，负责验证：
- 长消息的自动换行处理
- 换行后的缩进一致性
- 多行消息与后续消息的混合显示

## 2. 功能点目的 (Feature Purpose)

### 测试目标
Validates rendering of wrapped messages. The test creates a queue with a long message that wraps and a second normal message, verifying the wrapping and indentation are correct.

### 验证要点
1. 长消息 "This is a longer message that should be wrapped" 正确换行
2. 第一行有前缀 "↳ "，后续行有 4 空格缩进
3. 第二消息 "This is another message" 正常显示
4. 换行后的文本保持 dim + italic 样式
5. 编辑提示正确显示在底部
6. 整体高度计算正确（4 行：2 行消息1 + 1 行消息2 + 1 行提示）

## 3. 具体技术实现 (Technical Implementation)

### 核心数据结构
```rust
// From pending_input_preview.rs

pub(crate) struct PendingInputPreview {
    pub pending_steers: Vec<String>,
    pub queued_messages: Vec<String>,  // [long_msg, "This is another message"]
    edit_binding: key_hint::KeyBinding,
}
```

### 渲染逻辑
- Uses `adaptive_wrap_lines()` with custom indentation options
- Initial indent: `"  ↳ "` (2 spaces + arrow + space)
- Subsequent indent: `"    "` (4 spaces) for wrapped lines
- Each wrapped line maintains the same styling
- Overflow ellipsis "…" shown if message exceeds 3 lines

### 关键算法
1. **Adaptive Wrapping** (lines 105-117):
   ```rust
   let wrapped = adaptive_wrap_lines(
       message.lines().map(|line| Line::from(line.dim().italic())),
       RtOptions::new(width as usize)
           .initial_indent(Line::from("  ↳ ".dim()))
           .subsequent_indent(Line::from("    ")),
   );
   ```

2. **Line Limit**:
   - `PREVIEW_LINE_LIMIT = 3` lines per message
   - Longer messages truncated with "…"

3. **Wrapped Output** (at width 40):
   ```
   "This is a longer message that should"
   "be wrapped"
   ```

## 4. 关键代码路径与文件引用 (Key Code Paths)

### 源文件
- **主文件**: `codex-rs/tui/src/bottom_pane/pending_input_preview.rs`

### 关键函数/方法
| 函数/方法 | 描述 |
|-----------|------|
| `render_wrapped_message()` | Test function (lines 213-227) |
| `adaptive_wrap_lines()` | Wraps text with adaptive indentation |
| `RtOptions::initial_indent()` | Sets first line indent |
| `RtOptions::subsequent_indent()` | Sets wrapped line indent |

### 测试代码位置
- Test: `render_wrapped_message()` (lines 213-227)
- Test setup:
  ```rust
  let mut queue = PendingInputPreview::new();
  queue.queued_messages.push(
      "This is a longer message that should be wrapped".to_string()
  );
  queue.queued_messages.push("This is another message".to_string());
  let width = 40;
  let height = queue.desired_height(width);  // Returns 4
  ```

### 渲染输出示例
```
  ↳ This is a longer message that should
    be wrapped
  ↳ This is another message
    alt + ↑ edit
```

## 5. 依赖与外部交互 (Dependencies)

### 外部 Crates
| Crate | 用途 |
|-------|------|
| `ratatui` | TUI 渲染框架 |
| `insta` | 快照测试框架 |

### 内部模块依赖
- `crate::wrapping::adaptive_wrap_lines` - 自适应换行
- `crate::wrapping::RtOptions` - 换行配置

### 样式应用
- First line: `"  ↳ "` prefix (dim) + text (dim | italic)
- Wrapped lines: `"    "` indent + text (dim | italic)

## 6. 风险、边界与改进建议 (Risks, Edge Cases, Improvements)

### 潜在风险
1. **URL 处理**: 长 URL 可能被不恰当地换行
2. **Unicode 宽度**: 多字节字符可能导致换行位置错误
3. **非常窄终端**: 宽度小于缩进时渲染异常

### 边界情况
- 单词长度超过可用宽度（如长 URL）
- 消息包含多个连续空格
- 消息包含制表符
- 终端宽度为 0 或极小值

### 改进建议
1. **智能换行**: 在单词边界换行，但允许长 URL 溢出
2. **最大行宽**: 即使终端很宽，也限制预览行宽
3. **展开/折叠**: 支持展开查看完整消息
4. **行号指示**: 显示 "(2 lines)" 提示
5. **断词提示**: 在行尾显示连字符或换行指示

### 相关文档
- `codex-rs/tui/src/wrapping.rs` - 换行实现
- `codex-rs/tui/styles.md` - 样式规范
- `AGENTS.md` - 项目级代理指南
