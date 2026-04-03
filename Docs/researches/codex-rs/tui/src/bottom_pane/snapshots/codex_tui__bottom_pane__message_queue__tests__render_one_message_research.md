# 研究文档: render_one_message

## 场景与职责

本快照测试验证消息队列（MessageQueue）在单条消息场景下的基础渲染效果。这是消息队列功能的最基本测试，验证单个消息的显示、样式和布局。

**核心场景**: 用户输入一条简单的消息并提交，系统显示该消息的预览。

## 功能点目的

1. **基础渲染**: 验证单条消息的正确显示
2. **样式应用**: 验证消息和提示的样式正确
3. **高度计算**: 验证 `desired_height` 返回正确值

## 具体技术实现

### 测试构造

```rust
#[test]
fn render_one_message() {
    let mut queue = PendingInputPreview::new();
    queue.queued_messages.push("Hello, world!".to_string());
    let width = 40;
    let height = queue.desired_height(width);
    let mut buf = Buffer::empty(Rect::new(0, 0, width, height));
    queue.render(Rect::new(0, 0, width, height), &mut buf);
    assert_snapshot!("render_one_message", format!("{buf:?}"));
}
```

### 高度计算

```rust
#[test]
fn desired_height_one_message() {
    let mut queue = PendingInputPreview::new();
    queue.queued_messages.push("Hello, world!".to_string());
    assert_eq!(queue.desired_height(40), 3);  // 标题 + 消息 + 提示 = 3行
}
```

### 渲染结构

```rust
impl Renderable for PendingInputPreview {
    fn render(&self, area: Rect, buf: &mut Buffer) {
        if area.is_empty() {
            return;
        }
        self.as_renderable(area.width).render(area, buf);
    }

    fn desired_height(&self, width: u16) -> u16 {
        self.as_renderable(width).desired_height(width)
    }
}
```

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `pending_input_preview.rs:169-177` | 测试用例 `render_one_message` |
| `pending_input_preview.rs:155-159` | `desired_height_one_message` 高度测试 |
| `pending_input_preview.rs:135-147` | `Renderable` trait 实现 |
| `pending_input_preview.rs:69-132` | `as_renderable` 渲染构造 |

## 依赖与外部交互

### 快照显示效果（40字符宽度）

```
Buffer {
    area: Rect { x: 0, y: 0, width: 40, height: 2 },  // 注意：实际应为3行
    content: [
        "  ↳ Hello, world!                       ",  // 消息行
        "    alt + ↑ edit                        ",  // 编辑提示
    ],
    styles: [
        x: 0, y: 0, fg: Reset, bg: Reset, underline: Reset, modifier: DIM,
        x: 4, y: 0, fg: Reset, bg: Reset, underline: Reset, modifier: DIM | ITALIC,
        x: 17, y: 0, fg: Reset, bg: Reset, underline: Reset, modifier: NONE,
        x: 0, y: 1, fg: Reset, bg: Reset, underline: Reset, modifier: DIM,
        x: 16, y: 1, fg: Reset, bg: Reset, underline: Reset, modifier: NONE,
    ]
}
```

### 渲染内容分析

注意：快照显示只有2行，但 `desired_height_one_message` 测试期望3行。这可能是因为：
1. 快照来源是 `message_queue.rs` 的测试（较旧）
2. `pending_input_preview.rs` 的测试添加了标题行

### 样式映射

| 位置 | 内容 | 样式 |
|------|------|------|
| x:0-3 | "  ↳ " | DIM |
| x:4-16 | "Hello, world!" | DIM \| ITALIC |
| x:0-15 | "    alt + ↑ edit" | DIM |

## 风险边界与改进建议

### 风险边界

1. **高度不一致**: `desired_height` 和实际渲染高度可能不匹配
2. **空消息处理**: 未测试空字符串消息的行为
3. **特殊字符**: 未测试包含控制字符或ANSI转义序列的消息

### 改进建议

1. **高度验证**: 添加测试确保 `desired_height` 与实际渲染一致
   ```rust
   assert_eq!(height, buf.content.len() as u16);
   ```

2. **边界测试**: 添加空消息、超长消息、特殊字符测试
   ```rust
   fn render_empty_message() { ... }
   fn render_very_long_message() { ... }
   fn render_message_with_ansi() { ... }
   ```

3. **样式一致性**: 确保所有消息类型使用一致的样式

### 相关测试

- `desired_height_empty`: 空队列高度应为0
- `render_two_messages`: 多条消息测试
- `render_wrapped_message`: 自动换行测试
