# 图像生成调用历史测试研究文档

## 场景与职责

本测试验证 `tui_app_server` 中图像生成工具调用的历史记录渲染。当 Codex 使用图像生成功能（如 DALL-E）创建图像时，系统会生成 `ImageGenerationEndEvent`，测试确保该事件能够正确渲染为历史单元格，展示生成的图像描述和保存路径。

## 功能点目的

1. **图像生成可视化**: 在聊天历史中展示图像生成操作及其结果
2. **元信息展示**: 显示图像的修订提示词（revised prompt）和保存路径
3. **历史追踪**: 允许用户回顾之前生成的图像
4. **状态反馈**: 告知用户图像生成已完成及保存位置

## 具体技术实现

### 测试流程

```rust
async fn image_generation_call_adds_history_cell() {
    // 1. 创建 ChatWidget 实例
    let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;

    // 2. 发送 ImageGenerationEnd 事件
    chat.handle_codex_event(Event {
        id: "sub-image-generation".into(),
        msg: EventMsg::ImageGenerationEnd(ImageGenerationEndEvent {
            call_id: "call-image-generation".into(),
            status: "completed".into(),
            revised_prompt: Some("A tiny blue square".into()),
            result: "Zm9v".into(),  // base64 编码的图像数据
            saved_path: Some("/tmp/ig-1.png".into()),
        }),
    });

    // 3. 捕获并验证渲染的历史单元格
    let cells = drain_insert_history(&mut rx);
    assert_eq!(cells.len(), 1, "expected a single history cell");
    let combined = lines_to_single_string(&cells[0]);
    assert_snapshot!("image_generation_call_history_snapshot", combined);
}
```

### 关键数据结构

- **`ImageGenerationEndEvent`**: 图像生成结束事件
  - `call_id`: 调用唯一标识
  - `status`: 生成状态（"completed", "failed" 等）
  - `revised_prompt`: 模型修订后的提示词
  - `result`: Base64 编码的图像数据
  - `saved_path`: 图像保存的本地路径

### 渲染输出格式

```
• Generated Image:
  └ A tiny blue square
  └ Saved to: /tmp
```

## 关键代码路径与文件引用

### 测试文件
- **`codex-rs/tui_app_server/src/chatwidget/tests.rs`** (行 7089-7108)
  - 测试函数 `image_generation_call_adds_history_cell`
  - 验证图像生成事件渲染为单个历史单元格

### 源文件
- **`codex-rs/tui_app_server/src/chatwidget.rs`**
  - `handle_codex_event` 方法处理 `ImageGenerationEnd` 事件
  - 图像生成历史单元格创建逻辑

### 协议定义
- **`codex-protocol/src/protocol.rs`**
  - `ImageGenerationEndEvent` 结构定义
  - `ImageGenerationBeginEvent`（对应的开始事件）

### Snapshot 文件
- **`codex-rs/tui_app_server/src/chatwidget/snapshots/codex_tui_app_server__chatwidget__tests__image_generation_call_history_snapshot.snap`**

## 依赖与外部交互

### 内部依赖
| 组件 | 用途 |
|------|------|
| `ChatWidget` | 主聊天组件，处理图像生成事件 |
| `HistoryCell` | 历史单元格渲染 |
| `AppEventSender` | 应用事件发送器 |

### 协议事件
| 事件 | 方向 | 描述 |
|------|------|------|
| `ImageGenerationBegin` | Core → TUI | 图像生成开始 |
| `ImageGenerationEnd` | Core → TUI | 图像生成完成 |

### 测试辅助函数
- `make_chatwidget_manual`: 创建测试用的 ChatWidget 实例
- `drain_insert_history`: 从事件通道中提取所有历史单元格
- `lines_to_single_string`: 将多行文本合并为单个字符串

## 风险、边界与改进建议

### 潜在风险
1. **路径截断**: 长路径可能在 UI 中被截断，影响用户体验
2. **Base64 数据大小**: 图像数据可能很大，需要确保不显示在 UI 中
3. **状态处理**: 需要正确处理图像生成失败的情况

### 边界情况
1. **失败状态**: 图像生成失败时的错误展示
2. **空提示词**: `revised_prompt` 为 None 时的处理
3. **空保存路径**: `saved_path` 为 None 时的处理
4. **特殊字符**: 提示词中包含特殊字符的处理

### 改进建议
1. **添加失败状态测试**: 补充图像生成失败时的渲染测试
2. **图像预览**: 考虑在历史记录中显示图像缩略图
3. **点击打开**: 支持点击路径打开图像文件
4. **复制路径**: 支持复制图像保存路径到剪贴板
5. **批量生成**: 支持多个图像生成结果的展示
