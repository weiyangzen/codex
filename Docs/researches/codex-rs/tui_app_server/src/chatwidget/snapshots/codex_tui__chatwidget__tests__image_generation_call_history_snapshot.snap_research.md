# Snapshot Research: image_generation_call_history_snapshot

## 场景与职责

此快照测试验证图像生成工具调用完成后的历史记录渲染效果。当 Codex 使用图像生成功能（如 DALL-E）创建图像时，系统需要向用户展示生成结果的相关信息。

测试场景：
- Codex 调用图像生成工具创建图像
- 图像生成完成，返回生成结果
- TUI 在历史记录中显示图像生成结果
- 用户可以在历史记录中查看生成的图像描述和保存路径

## 功能点目的

1. **图像生成结果可视化**：显示图像生成完成的状态
2. **生成内容描述**：显示用于生成图像的提示词（revised_prompt）
3. **文件保存信息**：显示生成图像的保存路径
4. **历史记录追溯**：允许用户在后续会话中查看图像生成历史

## 具体技术实现

### 关键流程

```
ImageGenerationBeginEvent → 图像生成中 → ImageGenerationEndEvent → 历史记录更新
```

### 图像生成事件数据结构

```rust
// 图像生成开始事件
ImageGenerationBeginEvent {
    call_id: String,    // 调用 ID
    turn_id: String,    // 关联的回合 ID
    prompt: String,     // 生成提示词
}

// 图像生成完成事件
ImageGenerationEndEvent {
    call_id: String,           // 调用 ID
    status: String,            // 完成状态（如 "completed"）
    revised_prompt: Option<String>, // 修订后的提示词（模型优化后的）
    result: String,            // 图像数据（Base64 编码）
    saved_path: Option<String>, // 保存路径
}
```

### 历史记录渲染

图像生成完成后，系统会在历史记录中创建一个专门的单元格，显示：
- 图像生成状态（Generated Image）
- 修订后的提示词描述
- 文件保存路径（如果已保存到本地）

## 关键代码路径与文件引用

### 核心文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/chatwidget/tests.rs` | 测试定义和快照断言 |
| `codex-rs/tui/src/chatwidget.rs` | ChatWidget 主逻辑，处理图像生成事件 |
| `codex-rs/tui/src/history_cell.rs` | 历史记录单元格定义和渲染 |
| `codex-protocol/src/protocol.rs` | 图像生成相关协议事件定义 |

### 关键函数

- `ChatWidget::handle_codex_event()` - 处理 ImageGenerationEndEvent
- `lines_to_single_string()` - 测试辅助函数，将行转换为字符串
- `drain_insert_history()` - 测试辅助函数，获取插入的历史记录

### 测试代码位置

```rust
// codex-rs/tui/src/chatwidget/tests.rs
async fn image_generation_call_adds_history_cell() {
    let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;

    chat.handle_codex_event(Event {
        id: "sub-image-generation".into(),
        msg: EventMsg::ImageGenerationEnd(ImageGenerationEndEvent {
            call_id: "call-image-generation".into(),
            status: "completed".into(),
            revised_prompt: Some("A tiny blue square".into()),
            result: "Zm9v".into(), // Base64 编码的图像数据
            saved_path: Some("/tmp/ig-1.png".into()),
        }),
    });

    let cells = drain_insert_history(&mut rx);
    assert_eq!(cells.len(), 1, "expected a single history cell");
    let combined = lines_to_single_string(&cells[0]);
    assert_snapshot!("image_generation_call_history_snapshot", combined);
}
```

## 依赖与外部交互

### 内部依赖

- `codex_protocol::protocol::ImageGenerationBeginEvent` - 图像生成开始事件
- `codex_protocol::protocol::ImageGenerationEndEvent` - 图像生成完成事件
- `codex_protocol::protocol::ViewImageToolCallEvent` - 查看图像工具调用事件

### 外部交互

- **图像生成服务**：调用 OpenAI DALL-E 或其他图像生成 API
- **文件系统**：保存生成的图像到本地路径

## 风险、边界与改进建议

### 潜在风险

1. **大图像数据处理**：Base64 编码的大图像可能占用大量内存
2. **存储空间**：自动保存的图像可能占用大量磁盘空间
3. **隐私问题**：生成的图像可能包含敏感信息

### 边界情况

- 图像生成失败（如内容政策违规）
- 图像数据损坏或无法解码
- 保存路径不存在或没有写入权限
- 多个图像同时生成

### 改进建议

1. **显示优化**：
   - 在终端支持的情况下显示图像预览（如使用 iTerm2 的图像协议）
   - 添加图像缩略图
   - 支持点击查看大图

2. **文件管理**：
   - 自动清理旧的生成图像
   - 提供图像管理命令（如 `/images` 列出所有生成图像）
   - 支持自定义图像保存路径

3. **交互改进**：
   - 允许用户重新生成图像（使用相同或修改后的提示词）
   - 支持图像编辑指令
   - 提供图像分享功能

4. **可访问性**：
   - 为视觉障碍用户提供图像描述
   - 支持导出图像元数据

---

**快照内容**：
```
• Generated Image:
  └ A tiny blue square
  └ Saved to: /tmp
```

**说明**：
- `• Generated Image:` 表示图像生成完成
- 第一级缩进显示修订后的提示词 "A tiny blue square"
- 第二级缩进显示文件保存路径 "/tmp"
- 简洁的格式让用户快速了解图像生成结果和位置
