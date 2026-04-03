# 研究文档: codex_tui__chatwidget__tests__chatwidget_tall.snap

## 场景与职责

本快照文件验证 **高窗口布局** 的渲染输出，测试 TUI 在充足垂直空间下的完整 UI 展示。

## 功能点目的

1. **完整布局展示**: 验证高窗口下的所有 UI 元素
2. **队列消息显示**: 测试待处理消息的渲染
3. **状态指示**: 验证工作状态和输入框的协调显示

## 具体技术实现

### 快照内容结构
```
• Working (0s • esc to interrupt)

• Queued follow-up messages
  ↳ Hello, world! 0
  ↳ Hello, world! 1
  ...
  ↳ Hello, world! 15

› Ask Codex to do anything

  ? for shortcuts                                            100% left
```

### 布局元素

| 元素 | 说明 |
|------|------|
| `• Working` | 工作状态指示 |
| `(0s • esc to interrupt)` | 计时和中断提示 |
| `Queued follow-up messages` | 队列消息标题 |
| `↳` | 队列消息指示符 |
| `Hello, world! N` | 队列中的消息预览 |
| `› Ask Codex...` | 输入框提示 |
| `? for shortcuts` | 快捷键提示 |
| `100% left` | 上下文余量 |

### 队列消息
显示 16 条队列消息（0-15），测试：
- 大量队列消息的渲染性能
- 垂直空间的合理分配
- 消息截断和预览

## 关键代码路径与文件引用

### 测试定义
```rust
expression: term.backend().vt100().screen().contents()
```

### 相关模块
- `chatwidget.rs` - 队列消息管理
- `bottom_pane/` - 输入框和状态栏
- `app.rs` - 消息队列逻辑

### 队列数据结构
```rust
struct MessageQueue {
    pending: Vec<UserInput>,
    max_display: usize,  // 最大显示数量
}
```

## 依赖与外部交互

### 用户交互
- `Tab` 键 - 添加队列消息
- `Enter` 键 - 发送消息
- `Esc` 键 - 中断当前任务

### 协议交互
- 队列消息通过 `Op::UserTurn` 发送
- 状态通过 `AgentStatus` 更新

## 风险、边界与改进建议

### 性能考虑
1. **大量队列**: 队列消息过多时的性能
2. **渲染延迟**: 高窗口下的渲染延迟

### 用户体验
1. **队列管理**: 缺乏队列的查看和删除功能
2. **优先级**: 无法调整队列消息优先级

### 改进建议
1. **队列面板**: 添加专门的队列管理面板
2. **批量操作**: 支持批量删除队列消息
3. **队列预览**: 显示队列消息的完整内容
4. **优先级标记**: 支持标记高优先级消息
5. **队列持久化**: 会话间保持队列

### 相关测试
- `review_queues_user_messages_snapshot.snap` - 审查队列消息
- `chatwidget_exec_and_status_layout_vt100_snapshot.snap` - 执行状态布局
