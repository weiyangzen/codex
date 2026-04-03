# 研究文档: model_reasoning_selection_popup.snap

## 场景与职责

该快照文件测试模型推理能力选择弹窗的渲染效果。

## 功能点目的

1. **推理能力选择**: 允许用户选择模型的推理努力程度
2. **成本-质量权衡**: 让用户在推理深度和成本之间选择
3. **模型配置**: 配置特定模型的推理行为

## 具体技术实现

### 推理努力选项

```rust
enum ReasoningEffortConfig {
    Low,     // 快速响应，较少推理
    Medium,  // 平衡
    High,    // 深度推理，更慢但更彻底
}
```

### 渲染输出

```
Select Reasoning Effort

› 1. Low    - Faster responses, less thorough
  2. Medium - Balanced (current)
  3. High   - More thorough, slower

Applies to: gpt-5.1-codex-max
```

## 关键代码路径与文件引用

- **测试文件**: `codex-rs/tui/src/chatwidget/tests.rs`
- **推理配置**: `codex-protocol` 中的推理配置类型

## 依赖与外部交互

1. **模型API**: 支持推理努力参数

## 改进建议
1. 添加推理成本的估计
2. 显示当前任务的推荐设置
3. 添加自定义推理配置
