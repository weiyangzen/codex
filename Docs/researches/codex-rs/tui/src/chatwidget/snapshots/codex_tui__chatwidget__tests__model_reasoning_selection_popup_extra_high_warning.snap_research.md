# 研究文档: model_reasoning_selection_popup_extra_high_warning.snap

## 场景与职责

该快照文件测试当选择"极高"推理努力时的警告弹窗渲染效果。

## 功能点目的

1. **高成本警告**: 警告用户极高推理的成本影响
2. **确认机制**: 防止意外选择昂贵的推理选项
3. **透明度**: 明确告知用户选择的后果

## 具体技术实现

### 警告弹窗

```rust
// 当选择 High 推理时显示警告
if effort == ReasoningEffortConfig::High {
    show_extra_high_warning();
}
```

### 渲染输出

```
⚠️  High Reasoning Effort Selected

This setting will:
• Significantly increase response time
• Use more tokens per request
• Increase API costs

Only recommended for complex tasks requiring deep analysis.

› Continue with High
  Cancel
```

## 关键代码路径与文件引用

- **测试文件**: `codex-rs/tui/src/chatwidget/tests.rs`
- **警告逻辑**: 推理选择的事件处理

## 改进建议
1. 添加成本估算
2. 提供任务复杂度评估
3. 添加"记住我的选择"选项
