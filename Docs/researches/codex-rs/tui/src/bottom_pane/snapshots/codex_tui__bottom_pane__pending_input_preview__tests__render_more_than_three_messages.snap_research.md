# Render More Than Three Messages

## 1. 场景与职责 (Scene and Responsibility)

### 测试场景
Tests rendering of more than three queued messages to verify truncation behavior.

### 组件职责
该快照测试针对 Codex TUI 的 **PendingInputPreview** 组件，负责验证：
- 当排队消息超过 3 条时的渲染行为
- 消息列表的完整显示（不截断消息数量，只截断单条消息的行数）
- 编辑提示（Alt+↑）的正确显示

## 2. 功能点目的 (Feature Purpose)

### 测试目标
Validates that the widget correctly displays all queued messages without limiting the count, while still limiting each message to 3 lines max.

### 验证要点
1. 所有 4 条消息都显示在输出中
2. 每条消息前缀为 "↳"
3. 节标题 "Queued follow-up messages" 正确显示
4. 编辑提示 "⌥ + ↑ edit last queued message" 显示在底部
5. 样式使用 DIM（暗淡）和 ITALIC（斜体）

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
queue.queued_messages.push("Hello, world!".to_string());
queue.queued_messages.push("This is another message".to_string());
queue.queued_messages.push("This is a third message".to_string());
queue.queued_messages.push("This is a fourth message".to_string());
```

### 渲染输出 (40x6)
```
• Queued follow-up messages
  ↳ Hello, world!
  ↳ This is another message
  ↳ This is a third message
  ↳ This is a fourth message
    ⌥ + ↑ edit last queued message
```

### 关键算法
1. **消息列表渲染**: `queued_messages` 中的所有消息都会显示，不限数量
2. **单条消息截断**: 每条消息最多显示 `PREVIEW_LINE_LIMIT` (3) 行
3. **文本包装**: 使用 `adaptive_wrap_lines` 处理长文本
4. **样式应用**: 排队消息使用 `dim().italic()` 样式

## 4. 关键代码路径与文件引用 (Key Code Paths)

### 源文件
- **主文件**: `codex-rs/tui/src/bottom_pane/pending_input_preview.rs`

### 关键函数/方法
| 函数/方法 | 描述 |
|-----------|------|
| `render()` | 主渲染函数，将组件绘制到 Buffer |
| `as_renderable()` | 构建可渲染对象，处理 pending_steers 和 queued_messages |
| `push_truncated_preview_lines()` | 添加截断的预览行，限制为 3 行 |
| `push_section_header()` | 添加节标题 "Queued follow-up messages" |

### 测试代码位置
```rust
#[test]
fn render_more_than_three_messages() {
    let mut queue = PendingInputPreview::new();
    queue.queued_messages.push("Hello, world!".to_string());
    queue.queued_messages.push("This is another message".to_string());
    queue.queued_messages.push("This is a third message".to_string());
    queue.queued_messages.push("This is a fourth message".to_string());
    let width = 40;
    let height = queue.desired_height(width);
    let mut buf = Buffer::empty(Rect::new(0, 0, width, height));
    queue.render(Rect::new(0, 0, width, height), &mut buf);
    assert_snapshot!("render_more_than_three_messages", format!("{buf:?}"));
}
```

## 5. 依赖与外部交互 (Dependencies)

### 外部 Crates
| Crate | 用途 |
|-------|------|
| `ratatui` | TUI 渲染框架，提供 Buffer、Rect、Widget 等核心类型 |
| `crossterm` | 跨平台终端控制，处理键盘事件 |
| `insta` | 快照测试框架 |

### 内部模块依赖
- `crate::render::renderable::Renderable` - 可渲染组件 trait
- `crate::key_hint` - 键盘提示生成（Alt+Up 显示为 ⌥ + ↑）
- `crate::wrapping::{RtOptions, adaptive_wrap_lines}` - 文本包装

### 样式约定
遵循 `codex-rs/tui/styles.md`：
- 项目符号 "•" 使用 `.dim()`
- 消息前缀 "↳" 使用 `.dim()`
- 消息内容使用 `.dim().italic()`
- 编辑提示使用 `.dim()`

## 6. 风险、边界与改进建议 (Risks, Edge Cases, Improvements)

### 潜在风险
1. **消息数量无限制**: 虽然单条消息有 3 行限制，但消息数量无限制，大量消息可能占用过多屏幕空间
2. **高度计算**: `desired_height()` 需要准确计算所有消息的高度

### 边界情况
| 场景 | 行为 |
|------|------|
| 无消息 | 高度为 0，不渲染 |
| 1-3 条消息 | 正常显示所有消息 |
| 4+ 条消息 | 显示所有消息（如本测试所示） |
| 单条消息超过 3 行 | 截断显示前 3 行 + "…" |
| 宽度 < 4 | 空渲染 |

### 改进建议
1. **消息数量限制**: 考虑限制显示的消息数量（如最多 5 条），超过时显示 "... 还有 N 条消息"
2. **滚动支持**: 对于大量消息，添加滚动功能
3. **折叠/展开**: 允许用户折叠或展开消息列表
4. **测试覆盖**: 添加测试验证 10+ 条消息的渲染行为

### 相关文档
- `codex-rs/tui/styles.md` - TUI 样式规范
- `AGENTS.md` - 项目级代理指南
- `Docs/researches/codex-rs/tui/src/bottom_pane/pending_input_preview.rs_research.md` - 完整组件研究文档
