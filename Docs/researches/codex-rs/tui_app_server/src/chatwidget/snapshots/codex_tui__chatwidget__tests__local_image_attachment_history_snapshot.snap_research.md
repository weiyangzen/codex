# Snapshot Research: local_image_attachment_history_snapshot

## 场景与职责

此快照测试验证本地图像附件在历史记录中的渲染效果。当用户在对话中附加本地图像文件时，系统需要在历史记录中显示图像查看状态。

测试场景：
- 用户在输入中附加本地图像文件
- 用户发送消息，图像作为附件提交
- 系统处理图像并在历史记录中显示查看状态
- 用户可以在历史记录中看到图像附件的记录

## 功能点目的

1. **图像附件可视化**：显示用户已查看/附加的图像
2. **文件名展示**：显示图像文件的名称
3. **历史记录追溯**：允许用户在后续会话中查看图像附件历史
4. **用户体验一致性**：保持与其他附件类型的显示风格一致

## 具体技术实现

### 关键流程

```
用户附加图像 → 发送消息 → ViewImageToolCallEvent → 历史记录更新
```

### 图像附件数据结构

```rust
// 查看图像工具调用事件
ViewImageToolCallEvent {
    call_id: String,           // 调用 ID
    turn_id: String,           // 关联的回合 ID
    file_path: String,         // 图像文件路径
    mime_type: Option<String>, // MIME 类型
}

// 本地图像附件
LocalImageAttachment {
    placeholder: String,       // 占位符文本（如 "[Image #1]"）
    path: PathBuf,             // 图像文件路径
}

// 用户消息中的图像
UserMessage {
    text: String,
    local_images: Vec<LocalImageAttachment>,  // 本地图像附件
    remote_image_urls: Vec<String>,           // 远程图像 URL
    text_elements: Vec<TextElement>,          // 文本元素（占位符位置）
    mention_bindings: Vec<MentionBinding>,    // 提及绑定
}
```

### 历史记录渲染

```rust
fn handle_view_image_tool_call(&mut self, event: ViewImageToolCallEvent) {
    // 从历史记录中提取文件名
    let file_name = Path::new(&event.file_path)
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_else(|| event.file_path.clone());
    
    // 创建历史记录单元格
    let cell = HistoryCell::ViewImage {
        file_name,
        mime_type: event.mime_type,
    };
    
    self.insert_history_cell(cell);
}
```

## 关键代码路径与文件引用

### 核心文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/chatwidget/tests.rs` | 测试定义和快照断言 |
| `codex-rs/tui/src/chatwidget.rs` | ChatWidget 主逻辑，处理图像事件 |
| `codex-rs/tui/src/history_cell.rs` | 历史记录单元格定义和渲染 |
| `codex-rs/tui/src/bottom_pane/mod.rs` | 底部面板，处理图像附件输入 |

### 关键函数

- `ChatWidget::handle_codex_event()` - 处理 ViewImageToolCallEvent
- `ChatWidget::handle_view_image_tool_call()` - 处理图像查看工具调用
- `lines_to_single_string()` - 测试辅助函数，将行转换为字符串
- `drain_insert_history()` - 测试辅助函数，获取插入的历史记录

### 测试代码位置

```rust
// codex-rs/tui/src/chatwidget/tests.rs
async fn local_image_attachment_adds_history_cell() {
    let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;

    chat.handle_codex_event(Event {
        id: "view-image-1".into(),
        msg: EventMsg::ViewImageToolCall(ViewImageToolCallEvent {
            call_id: "call-view-image".into(),
            turn_id: "turn-1".into(),
            file_path: "/tmp/example.png".into(),
            mime_type: Some("image/png".into()),
        }),
    });

    let cells = drain_insert_history(&mut rx);
    assert_eq!(cells.len(), 1, "expected a single history cell");
    let combined = lines_to_single_string(&cells[0]);
    assert_snapshot!("local_image_attachment_history_snapshot", combined);
}
```

## 依赖与外部交互

### 内部依赖

- `codex_protocol::protocol::ViewImageToolCallEvent` - 查看图像工具调用事件
- `LocalImageAttachment` - 本地图像附件结构
- `UserMessage` - 用户消息结构

### 外部交互

- **文件系统**：读取本地图像文件
- **图像处理服务**：验证和处理图像文件

## 风险、边界与改进建议

### 潜在风险

1. **文件不存在**：图像文件可能在发送后被删除或移动
2. **大图像文件**：大图像可能导致内存和性能问题
3. **隐私泄露**：图像路径可能包含敏感信息

### 边界情况

- 图像文件路径包含特殊字符
- 图像文件格式不支持
- 图像文件损坏
- 多个图像同时附加

### 改进建议

1. **显示优化**：
   - 在支持的终端中显示图像预览（如使用 iTerm2 的图像协议）
   - 添加图像缩略图
   - 显示图像尺寸和文件大小

2. **文件管理**：
   - 验证图像文件是否存在
   - 提供图像文件打开快捷方式
   - 支持图像文件拖拽上传

3. **隐私保护**：
   - 只显示文件名而非完整路径
   - 提供路径脱敏选项
   - 支持图像文件复制到安全位置

4. **可访问性**：
   - 为视觉障碍用户提供图像描述
   - 支持图像元数据查看
   - 提供图像内容 OCR 功能

---

**快照内容**：
```
• Viewed Image
  └ example.png
```

**说明**：
- `• Viewed Image` 表示用户已查看/附加图像
- `└ example.png` 显示图像文件名
- 简洁的格式让用户快速了解图像附件的状态
- 只显示文件名而非完整路径，保护用户隐私
