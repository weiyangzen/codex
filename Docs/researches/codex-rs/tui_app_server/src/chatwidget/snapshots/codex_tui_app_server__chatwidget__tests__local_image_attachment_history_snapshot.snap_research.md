# 本地图像附件历史测试研究文档

## 场景与职责

本测试验证 `tui_app_server` 中查看图像工具调用的历史记录渲染。当 Codex 使用 `ViewImageToolCall` 工具查看本地图像文件时，系统会生成 `ViewImageToolCallEvent`，测试确保该事件能够正确渲染为历史单元格，展示被查看的图像文件名。

## 功能点目的

1. **图像查看追踪**: 在聊天历史中记录图像查看操作
2. **文件引用展示**: 显示被查看图像的文件路径/名称
3. **操作可视化**: 让用户了解 AI 查看了哪些图像
4. **审计支持**: 提供图像查看操作的审计记录

## 具体技术实现

### 测试流程

```rust
async fn view_image_tool_call_adds_history_cell() {
    // 1. 创建 ChatWidget 实例
    let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;
    
    // 2. 构建图像路径（使用当前工作目录）
    let image_path = chat.config.cwd.join("example.png");

    // 3. 发送 ViewImageToolCall 事件
    chat.handle_codex_event(Event {
        id: "sub-image".into(),
        msg: EventMsg::ViewImageToolCall(ViewImageToolCallEvent {
            call_id: "call-image".into(),
            path: image_path,
        }),
    });

    // 4. 捕获并验证历史单元格
    let cells = drain_insert_history(&mut rx);
    assert_eq!(cells.len(), 1, "expected a single history cell");
    let combined = lines_to_single_string(&cells[0]);
    assert_snapshot!("local_image_attachment_history_snapshot", combined);
}
```

### 关键数据结构

- **`ViewImageToolCallEvent`**: 查看图像工具调用事件
  - `call_id`: 调用唯一标识
  - `path`: 图像文件的绝对路径

### 渲染输出格式

```
• Viewed Image
  └ example.png
```

### 路径处理逻辑

1. **路径简化**: 将绝对路径简化为文件名
2. **工作目录相对化**: 如果图像在当前工作目录下，仅显示文件名
3. **格式化输出**: 使用统一的列表格式展示

## 关键代码路径与文件引用

### 测试文件
- **`codex-rs/tui_app_server/src/chatwidget/tests.rs`** (行 7070-7087)
  - 测试函数 `view_image_tool_call_adds_history_cell`
  - 验证图像查看事件渲染为单个历史单元格

### 源文件
- **`codex-rs/tui_app_server/src/chatwidget.rs`**
  - `handle_codex_event` 方法处理 `ViewImageToolCall` 事件
  - 图像查看历史单元格创建逻辑
  - 路径简化和格式化

### 协议定义
- **`codex-protocol/src/protocol.rs`**
  - `ViewImageToolCallEvent` 结构定义

### 相关测试
- **`image_generation_call_adds_history_cell`** (行 7089-7108)
  - 测试图像生成历史记录（类似但不同的功能）

### Snapshot 文件
- **`codex-rs/tui_app_server/src/chatwidget/snapshots/codex_tui_app_server__chatwidget__tests__local_image_attachment_history_snapshot.snap`**

## 依赖与外部交互

### 内部依赖
| 组件 | 用途 |
|------|------|
| `ChatWidget` | 主聊天组件，处理图像查看事件 |
| `HistoryCell` | 历史单元格渲染 |
| `AppEventSender` | 应用事件发送器 |
| `config.cwd` | 当前工作目录，用于路径简化 |

### 协议事件
| 事件 | 方向 | 描述 |
|------|------|------|
| `ViewImageToolCall` | Core → TUI | 查看图像工具调用 |

### 测试辅助函数
- `make_chatwidget_manual`: 创建测试用的 ChatWidget 实例
- `drain_insert_history`: 从事件通道中提取所有历史单元格
- `lines_to_single_string`: 将多行文本合并为单个字符串

## 风险、边界与改进建议

### 潜在风险
1. **路径泄露**: 绝对路径可能泄露敏感目录信息
2. **长路径截断**: 长路径在 UI 中可能被截断
3. **文件不存在**: 图像文件可能已被删除或移动

### 边界情况
1. **深层路径**: 图像位于深层目录结构中的展示
2. **特殊字符**: 文件名包含特殊字符的处理
3. **非图像文件**: 错误地查看非图像文件的处理
4. **大量图像**: 连续查看多个图像时的历史记录

### 改进建议
1. **路径隐私**: 考虑隐藏敏感路径信息，仅显示相对路径
2. **图像预览**: 在历史记录中显示图像缩略图
3. **点击打开**: 支持点击文件名打开图像
4. **文件状态**: 显示文件是否存在的状态指示
5. **批量查看**: 支持多个图像查看的批量展示
6. **图像元数据**: 显示图像尺寸、格式等元信息
