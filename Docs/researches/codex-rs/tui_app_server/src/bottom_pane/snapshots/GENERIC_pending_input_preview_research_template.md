# Pending Input Preview Generic Research Template

## 场景与职责

该文档是待处理输入预览的通用研究模板，适用于以下快照文件：
- `render_many_line_message.snap`
- `render_more_than_three_messages.snap`
- `render_multiline_pending_steer_uses_single_prefix_and_truncates.snap`
- `render_one_message.snap`
- `render_one_pending_steer.snap`
- `render_two_messages.snap`
- `render_wrapped_message.snap`

### 业务场景
- 显示待处理的消息预览
- 区分不同类型的待处理消息
- 提供编辑和中断选项

### 消息类型
| 类型 | 描述 |
|------|------|
| Queued Messages | 排队等待处理的消息 |
| Pending Steers | 等待工具调用完成后发送的消息 |

## 功能点目的

### 核心功能
1. **消息预览**：显示待处理消息的预览
2. **类型区分**：区分不同类型的消息
3. **操作提示**：提供编辑和中断提示

### 用户体验目标
- **状态可见**：用户知道有待处理的消息
- **灵活控制**：可以编辑或中断消息
- **空间优化**：限制预览占用的空间

## 具体技术实现

### 关键数据结构
```rust
pub(crate) struct PendingInputPreview {
    pending_steers: Vec<String>,
    queued_messages: Vec<String>,
}
```

### 关键代码路径
- **源文件**: `codex-rs/tui_app_server/src/bottom_pane/pending_input_preview.rs`

## 依赖与外部交互

### 内部依赖
- `PendingInputPreview` - 待处理输入预览

### 外部交互
- **消息队列**：获取待处理消息

## 风险、边界与改进建议

### 潜在风险
1. **消息混淆**：用户可能混淆不同类型的消息
2. **空间占用**：大量消息时占用过多空间

### 改进建议
1. **颜色区分**：使用不同颜色区分消息类型
2. **折叠功能**：允许折叠某类消息

### 相关文件引用
- 源文件: `codex-rs/tui_app_server/src/bottom_pane/pending_input_preview.rs`
