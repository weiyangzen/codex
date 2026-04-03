# 研究文档: interrupted_turn_pending_steers_message.snap

## 场景与职责

该快照文件测试当有待处理的引导消息（pending steers）时，中断回合显示的特定信息。

## 功能点目的

1. **特定场景反馈**: 区分普通中断和有引导消息的中断
2. **引导处理**: 说明引导消息将被提交
3. **状态通知**: 告知用户中断后的具体行为

## 具体技术实现

### 待处理引导

```rust
chat.pending_steers.push_back(pending_steer("steer 1"));
chat.submit_pending_steers_after_interrupt = true;
```

### 渲染输出

```
Model interrupted to submit steer instructions.
```

## 关键代码路径与文件引用

- **测试文件**: `codex-rs/tui/src/chatwidget/tests.rs` (行 6532-6566)
- **引导管理**: `pending_steers` 队列处理

## 改进建议
1. 显示待处理引导的数量
2. 提供查看/编辑引导的选项
