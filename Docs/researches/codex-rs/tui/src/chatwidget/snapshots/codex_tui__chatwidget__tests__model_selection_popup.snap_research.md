# 研究文档: model_selection_popup.snap

## 场景与职责

该快照文件测试模型选择弹窗的完整渲染效果。

## 功能点目的

1. **模型选择**: 允许用户切换不同的AI模型
2. **模型信息**: 显示每个模型的特点和限制
3. **实时切换**: 支持在对话中切换模型

## 具体技术实现

### 模型列表

```rust
let models = chat.models_manager.try_list_models()
    .expect("models lock available");
```

### 渲染输出

```
Select Model

› 1. gpt-5              General purpose, fast
  2. gpt-5.1-codex-mini Code-optimized, efficient
  3. gpt-5.1-codex-max  Code-optimized, maximum capability
  4. gpt-5.2-codex      Latest features
  
Current: gpt-5
Press Enter to select, Esc to cancel
```

## 关键代码路径与文件引用

- **测试文件**: `codex-rs/tui/src/chatwidget/tests.rs`
- **模型管理**: `ModelsManager` 模型列表获取

## 依赖与外部交互

1. **模型API**: 获取可用模型列表

## 改进建议
1. 添加模型性能对比
2. 显示模型成本信息
3. 添加模型推荐功能
