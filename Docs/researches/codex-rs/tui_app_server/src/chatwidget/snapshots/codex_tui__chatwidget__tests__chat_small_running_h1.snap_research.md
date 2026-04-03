# 研究文档: codex_tui__chatwidget__tests__chat_small_running_h1.snap

## 场景与职责

本快照文件验证 **小尺寸聊天窗口（高度=1）在运行状态** 的渲染输出。

对比空闲状态，测试任务运行时的渲染差异。

## 功能点目的

1. **状态差异**: 对比空闲和运行状态在极端尺寸下的差异
2. **优先级**: 验证运行状态是否优先显示关键信息
3. **一致性**: 确保状态切换时的渲染一致性

## 具体技术实现

### 快照内容
```
"                                        "
```

### 测试参数
- **窗口高度**: 1 行
- **窗口宽度**: 40 字符
- **状态**: Running（运行中）

### 观察
即使状态为 Running，在高度为 1 时仍然只显示空白行。
这说明：
- 极端尺寸下状态信息被隐藏
- 或者状态显示需要更多空间

## 关键代码路径与文件引用

### 状态管理
```rust
enum ChatState {
    Idle,
    Running { task: String },
}
```

### 渲染逻辑
```rust
fn render(&self, area: Rect, buf: &mut Buffer) {
    if area.height < MIN_HEIGHT_FOR_STATUS {
        // 不显示状态
        return;
    }
    // 显示状态...
}
```

## 依赖与外部交互

### 状态事件
- `TurnStartedEvent` - 开始运行
- `TurnCompleteEvent` - 运行完成

## 风险、边界与改进建议

### 问题
- 运行状态不可见可能导致用户困惑
- 不知道 Codex 是否正在工作

### 改进建议
1. **强制状态显示**: 即使空间小也显示简单状态指示
2. **终端标题**: 通过终端标题显示状态
3. **声音提示**: 使用声音指示状态变化

### 相关测试
- `chat_small_idle_h1.snap` - 空闲状态对比
- `status_widget_active.snap` - 正常状态显示
