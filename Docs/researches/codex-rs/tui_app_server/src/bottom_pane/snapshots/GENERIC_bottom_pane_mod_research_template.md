# Bottom Pane Mod Generic Research Template

## 场景与职责

该文档是底部面板模块的通用研究模板，适用于以下快照文件：
- `queued_messages_visible_when_status_hidden_snapshot.snap`
- `status_and_composer_fill_height_without_bottom_padding.snap`
- `status_hidden_when_height_too_small_height_1.snap`
- `status_only_snapshot.snap`
- `status_with_details_and_queued_messages_snapshot.snap`

### 业务场景
- 底部面板的整体布局和渲染
- 不同组件（状态栏、排队消息、输入框）的组合
- 高度不足时的自适应处理

### 组件组合
| 组件 | 描述 |
|------|------|
| Status View | 显示当前任务状态 |
| Message Queue | 显示排队消息 |
| Chat Composer | 聊天输入框 |
| Footer | 底部栏 |

## 功能点目的

### 核心功能
1. **布局管理**：管理各组件的布局和大小
2. **高度自适应**：根据可用高度调整显示
3. **优先级显示**：高度不足时优先显示重要组件

### 用户体验目标
- **信息完整**：在有限空间内显示必要信息
- **视觉平衡**：各组件比例协调
- **响应式**：适应不同终端高度

## 具体技术实现

### 关键数据结构
```rust
pub(crate) struct BottomPane {
    status_view: Option<StatusView>,
    message_queue_view: Option<MessageQueueView>,
    chat_composer: ChatComposer,
    // ...
}
```

### 关键代码路径
- **源文件**: `codex-rs/tui_app_server/src/bottom_pane/mod.rs`

## 依赖与外部交互

### 内部依赖
- `BottomPane` - 底部面板
- `StatusView` - 状态视图
- `MessageQueueView` - 消息队列视图

### 外部交互
- **任务管理器**：获取任务状态
- **消息队列**：获取排队消息

## 风险、边界与改进建议

### 潜在风险
1. **空间竞争**：各组件可能争夺有限空间
2. **信息丢失**：高度不足时某些组件可能不可见

### 改进建议
1. **可折叠组件**：允许用户折叠某些组件
2. **最小高度保障**：确保至少显示最重要的组件

### 相关文件引用
- 源文件: `codex-rs/tui_app_server/src/bottom_pane/mod.rs`
