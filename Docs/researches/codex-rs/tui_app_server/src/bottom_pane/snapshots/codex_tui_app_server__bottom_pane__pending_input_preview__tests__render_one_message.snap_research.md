# render_one_message Snapshot 研究文档

## 场景与职责

本快照测试展示了 `PendingInputPreview` 组件处理**单条排队消息**时的基础渲染行为。这是最基本的测试用例，验证组件能够正确显示一条简单的用户排队消息。

**典型使用场景**：
- 用户输入一条消息后按 Enter 排队，等待当前任务完成
- 测试组件的基本渲染能力
- 作为其他复杂场景的基准参考

## 功能点目的

该测试验证以下核心功能：

1. **基础渲染**：正确渲染标题、单条消息和编辑提示
2. **最小高度计算**：验证单条消息时的最小高度需求（3行）
3. **样式应用**：正确应用 dim 和 italic 样式
4. **编辑提示**：显示 `"⌥ + ↑ edit last queued message"` 快捷键提示

**渲染输出特征**：
```
• Queued follow-up messages             <- 标题行（dim 样式）
  ↳ Hello, world!                       <- 消息内容（dim + italic）
    ⌥ + ↑ edit last queued message      <- 编辑提示（dim 样式）
```

## 具体技术实现

### 高度计算验证
```rust
#[test]
fn desired_height_one_message() {
    let mut queue = PendingInputPreview::new();
    queue.queued_messages.push("Hello, world!".to_string());
    assert_eq!(queue.desired_height(40), 3);  // 标题 + 消息 + 提示
}
```

### 渲染流程
```rust
#[test]
fn render_one_message() {
    let mut queue = PendingInputPreview::new();
    queue.queued_messages.push("Hello, world!".to_string());
    let width = 40;
    let height = queue.desired_height(width);  // = 3
    let mut buf = Buffer::empty(Rect::new(0, 0, width, height));
    queue.render(Rect::new(0, 0, width, height), &mut buf);
    assert_snapshot!("render_one_message", format!("{buf:?}"));
}
```

### 样式定义
```rust
// 标题
"• ".dim() + "Queued follow-up messages"

// 消息
"  ↳ ".dim() + "Hello, world!".dim().italic()

// 编辑提示
"    ".into() + key_hint::alt(KeyCode::Up) + " edit last queued message"
```

## 关键代码路径与文件引用

### 主要文件
- `codex-rs/tui_app_server/src/bottom_pane/pending_input_preview.rs` - PendingInputPreview 组件实现

### 关键函数
| 函数 | 行号 | 职责 |
|------|------|------|
| `render_one_message` (test) | 169-177 | 本测试用例 |
| `desired_height_one_message` (test) | 162-166 | 高度计算测试 |
| `PendingInputPreview::new()` | 33-39 | 组件初始化 |
| `as_renderable()` | 69-132 | 主渲染逻辑 |

### 数据结构
```rust
pub(crate) struct PendingInputPreview {
    pub pending_steers: Vec<String>,
    pub queued_messages: Vec<String>,
    edit_binding: key_hint::KeyBinding,  // 默认 Alt+Up
}
```

## 依赖与外部交互

### 依赖模块
- `crate::key_hint` - 键盘快捷键提示生成
- `ratatui::buffer::Buffer` - 渲染缓冲区
- `ratatui::layout::Rect` - 布局区域定义
- `insta::assert_snapshot` - 快照测试框架

### 默认快捷键
```rust
edit_binding: key_hint::alt(KeyCode::Up),  // ⌥ + ↑
```

## 风险、边界与改进建议

### 当前边界情况
1. **空消息处理**：测试使用 `"Hello, world!"`，未测试空字符串
2. **特殊字符**：未测试包含转义字符或控制字符的消息
3. **宽度边界**：使用 40 字符宽度，未测试极端宽度

### 潜在风险
1. **空队列渲染**：`desired_height_empty` 测试显示空队列返回高度 0
2. **宽度不足**：如果宽度小于 4，组件返回空渲染
3. **样式冲突**：dim + italic 在某些终端可能显示不明显

### 改进建议
1. **空消息处理**：明确处理空字符串消息的行为
2. **边界测试**：添加宽度 < 4 的测试用例
3. **国际化**：测试非 ASCII 字符（如中文）的渲染
4. **可访问性**：考虑高对比度模式下的样式可见性
5. **配置化**：允许自定义编辑快捷键提示文本
