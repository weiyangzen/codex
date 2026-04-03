# Render Multiline Pending Steer Uses Single Prefix and Truncates

## 1. 场景与职责 (Scene and Responsibility)

### 测试场景
Tests rendering of a multiline pending steer message with single prefix and truncation.

### 组件职责
该快照测试针对 Codex TUI 的 **PendingInputPreview** 组件，负责验证：
- 多行 pending steer 消息的正确渲染
- 只有首行显示 "↳" 前缀，后续行使用缩进
- 超过 3 行的消息被截断并显示 "…"

## 2. 功能点目的 (Feature Purpose)

### 测试目标
Validates that multiline pending steer messages are rendered with proper indentation and truncation.

### 验证要点
1. 节标题 "Messages to be submitted after next tool call" 正确显示
2. 提示文本 "(press esc to interrupt and send immediately)" 显示在标题下方
3. 多行 steer 只有首行有 "↳" 前缀
4. 后续行使用 4 空格缩进（无前缀）
5. 超过 3 行的部分显示 "…" 截断提示
6. 所有文本使用 DIM（暗淡）样式

## 3. 具体技术实现 (Technical Implementation)

### 核心数据结构
```rust
pub(crate) struct PendingInputPreview {
    pub pending_steers: Vec<String>,
    pub queued_messages: Vec<String>,
    edit_binding: key_hint::KeyBinding,
}

const PREVIEW_LINE_LIMIT: usize = 3;  // 单条消息最大行数限制
```

### 测试数据
```rust
queue.pending_steers.push("First line\nSecond line\nThird line\nFourth line".to_string());
```

### 渲染输出 (48x6)
```
• Messages to be submitted after next tool call
  (press esc to interrupt and send immediately)
  ↳ First line
    Second line
    Third line
    …
```

### 关键算法
1. **文本包装**: 使用 `adaptive_wrap_lines` 处理多行文本
2. **缩进配置**:
   ```rust
   RtOptions::new(width as usize)
       .initial_indent(Line::from("  ↳ ".dim()))   // 首行：↳ 前缀
       .subsequent_indent(Line::from("    ")),     // 后续行：4空格缩进
   ```
3. **截断逻辑**: `push_truncated_preview_lines()` 只取前 3 行，超过时添加 "…"

## 4. 关键代码路径与文件引用 (Key Code Paths)

### 源文件
- **主文件**: `codex-rs/tui/src/bottom_pane/pending_input_preview.rs`

### 关键代码段
```rust
for steer in &self.pending_steers {
    let wrapped = adaptive_wrap_lines(
        steer.lines().map(|line| Line::from(line.dim())),
        RtOptions::new(width as usize)
            .initial_indent(Line::from("  ↳ ".dim()))
            .subsequent_indent(Line::from("    ")),
    );
    Self::push_truncated_preview_lines(&mut lines, wrapped, Line::from("    …".dim()));
}
```

### 关键函数/方法
| 函数/方法 | 描述 |
|-----------|------|
| `push_truncated_preview_lines()` | 添加截断的预览行，限制为 PREVIEW_LINE_LIMIT (3) 行 |
| `adaptive_wrap_lines()` | 智能文本包装，支持首行和后续行不同缩进 |
| `steer.lines()` | 将多行字符串拆分为行迭代器 |

### 测试代码位置
```rust
#[test]
fn render_multiline_pending_steer_uses_single_prefix_and_truncates() {
    let mut queue = PendingInputPreview::new();
    queue.pending_steers.push("First line\nSecond line\nThird line\nFourth line".to_string());
    let width = 48;
    let height = queue.desired_height(width);
    let mut buf = Buffer::empty(Rect::new(0, 0, width, height));
    queue.render(Rect::new(0, 0, width, height), &mut buf);
    assert_snapshot!("render_multiline_pending_steer_uses_single_prefix_and_truncates", format!("{buf:?}"));
}
```

## 5. 依赖与外部交互 (Dependencies)

### 外部 Crates
| Crate | 用途 |
|-------|------|
| `ratatui` | TUI 渲染框架，提供 Buffer、Rect、Line、Stylize 等 |
| `insta` | 快照测试框架 |

### 内部模块依赖
- `crate::wrapping::{RtOptions, adaptive_wrap_lines}` - 文本包装工具
- `crate::key_hint` - 按键提示生成（显示 "esc"）

### 样式约定
- 所有 pending steer 内容使用 `.dim()` 样式
- 截断提示 "…" 同样使用 `.dim()` 样式
- 与 queued messages 不同，pending steers 不使用斜体

## 6. 风险、边界与改进建议 (Risks, Edge Cases, Improvements)

### 潜在风险
1. **缩进不一致**: 如果 `initial_indent` 和 `subsequent_indent` 长度不匹配，可能导致视觉对齐问题
2. **宽字符处理**: 多字节字符可能影响缩进计算

### 边界情况
| 场景 | 行为 |
|------|------|
| 单行 steer | 只显示一行，有 ↳ 前缀 |
| 正好 3 行 | 显示全部 3 行，无 "…" |
| 4+ 行 | 显示前 3 行 + "…" |
| 空字符串 | 只显示 ↳ 前缀（可能为空内容） |
| 包含空行的 steer | 空行也会被计数和显示 |

### 改进建议
1. **展开功能**: 添加按键（如 Enter）展开截断的 steer 查看完整内容
2. **行数提示**: 显示 "... 还有 N 行" 而不是简单的 "…"
3. **空内容处理**: 过滤或特殊处理空字符串 steer
4. **测试覆盖**: 添加测试验证包含空行、特殊字符的 steer

### 相关文档
- `codex-rs/tui/styles.md` - TUI 样式规范
- `Docs/researches/codex-rs/tui/src/bottom_pane/pending_input_preview.rs_research.md` - 完整组件研究文档
