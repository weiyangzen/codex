# 研究文档: codex_tui__chatwidget__tests__disabled_slash_command_while_task_running_snapshot.snap

## 场景与职责

本快照文件验证 **任务运行时禁用斜杠命令** 的提示渲染。

当用户尝试在任务运行时使用 `/model` 等斜杠命令时，显示禁用提示。

## 功能点目的

1. **防止冲突**: 避免在任务运行时切换模型等操作
2. **用户反馈**: 明确告知用户当前不可用
3. **状态同步**: 确保用户了解当前系统状态

## 具体技术实现

### 快照内容
```
■ '/model' is disabled while a task is in progress.
```

### UI 元素
- `■` - 错误或警告指示符
- 斜杠命令 - `'/model'`
- 禁用原因 - "while a task is in progress"

### 禁用命令列表
```rust
const DISABLED_WHILE_RUNNING: &[&str] = &[
    "/model",
    "/personality",
    // ...
];
```

## 关键代码路径与文件引用

### 测试定义
```rust
expression: blob
```

### 命令处理
- `slash_command.rs` - 斜杠命令解析
- `chatwidget.rs` - 命令执行检查

## 依赖与外部交互

### 状态检查
```rust
if self.agent_turn_running {
    return Err(CommandDisabled);
}
```

## 风险、边界与改进建议

### 改进建议
1. **队列执行**: 允许排队而非直接拒绝
2. **具体说明**: 显示当前运行的任务
3. **预计时间**: 显示任务预计完成时间
