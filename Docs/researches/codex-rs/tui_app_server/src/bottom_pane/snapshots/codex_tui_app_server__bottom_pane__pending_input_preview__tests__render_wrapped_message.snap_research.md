# render_wrapped_message Snapshot 研究文档

## 场景与职责

本快照测试展示了 `PendingInputPreview` 组件处理**长消息自动换行**时的渲染行为。当消息内容超过可用宽度时，组件需要正确地将消息拆分为多行显示，并保持适当的缩进对齐。

**典型使用场景**：
- 用户输入较长的句子或段落
- 粘贴长文本内容后排队
- 验证文本换行和缩进对齐的正确性

## 功能点目的

该测试验证以下核心功能：

1. **自动换行**：长文本自动按宽度换行
2. **首行缩进**：消息第一行使用 `"  ↳ "` 前缀
3. **续行缩进**：后续行使用 `"    "` 缩进对齐
4. **多消息处理**：换行后的消息与后续消息正确排列

**渲染输出特征**：
```
• Queued follow-up messages             <- 标题行（dim 样式）
  ↳ This is a longer message that should<- 消息 1 第一行（dim + italic）
    be wrapped                          <- 消息 1 续行（dim + italic）
  ↳ This is another message             <- 消息 2（dim + italic）
    ⌥ + ↑ edit last queued message      <- 编辑提示（dim 样式）
```

## 具体技术实现

### 换行配置
```rust
let wrapped = adaptive_wrap_lines(
    message.lines().map(|line| Line::from(line.dim().italic())),
    RtOptions::new(width as usize)           // width = 40
        .initial_indent(Line::from("  ↳ ".dim()))    // 首行前缀
        .subsequent_indent(Line::from("    ")),      // 续行缩进
);
```

### 换行示例
```
原始消息: "This is a longer message that should be wrapped"
宽度: 40 字符

换行结果:
  ↳ This is a longer message that should  <- 第一行（36 字符 + 4 字符前缀）
    be wrapped                            <- 续行（4 字符缩进）
```

### 高度计算
```rust
// 标题：1 行
// 消息 1（换行后）：2 行
// 消息 2：1 行
// 编辑提示：1 行
// 总计：5 行
```

## 关键代码路径与文件引用

### 主要文件
- `codex-rs/tui_app_server/src/bottom_pane/pending_input_preview.rs` - PendingInputPreview 组件实现
- `codex-rs/tui_app_server/src/wrapping.rs` - 文本换行工具

### 关键函数
| 函数 | 行号 | 职责 |
|------|------|------|
| `render_wrapped_message` (test) | 214-227 | 本测试用例 |
| `adaptive_wrap_lines()` | wrapping.rs | 自适应文本换行 |
| `as_renderable()` | 69-132 | 主渲染逻辑 |

### 测试数据
```rust
queue.queued_messages.push(
    "This is a longer message that should be wrapped".to_string()
);
queue.queued_messages.push("This is another message".to_string());
```

## 依赖与外部交互

### 依赖模块
- `crate::wrapping::adaptive_wrap_lines` - 自适应文本换行
- `crate::wrapping::RtOptions` - 换行选项配置
  - `initial_indent`: 首行缩进
  - `subsequent_indent`: 续行缩进

### 换行算法
使用 `textwrap` 库进行文本换行，支持：
- 按单词边界换行
- 自定义缩进
- Unicode 字符处理

## 风险、边界与改进建议

### 当前边界情况
1. **英文文本**：测试使用英文，单词边界清晰
2. **适中长度**：消息长度适中，只触发一次换行
3. **固定宽度**：40 字符宽度是测试硬编码

### 潜在风险
1. **长 URL**：如 `long_url_like_message_does_not_expand_into_wrapped_ellipsis_rows` 测试所示，URL 可能在奇怪位置换行
2. **中文字符**：中文没有空格分隔，换行行为可能不同
3. **特殊字符**：表情符号、组合字符可能占用不同宽度

### 改进建议
1. **智能换行**：对 URL 等特殊文本使用专用换行策略
2. **断字支持**：对长单词使用断字（hyphenation）
3. **最小行长度**：避免最后一行只有 1-2 个字符
4. **视觉指示**：在换行处添加视觉提示（如 `"↩"`）
5. **展开功能**：允许用户展开查看完整未换行内容
6. **响应式宽度**：根据终端宽度动态调整换行
