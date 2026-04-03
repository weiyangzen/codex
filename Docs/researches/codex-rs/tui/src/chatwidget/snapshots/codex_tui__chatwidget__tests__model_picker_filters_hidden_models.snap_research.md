# 研究文档: model_picker_filters_hidden_models.snap

## 场景与职责

该快照文件测试模型选择器过滤隐藏模型的功能。

## 功能点目的

1. **模型过滤**: 隐藏不推荐或已弃用的模型
2. **简化选择**: 减少用户面对的选项数量
3. **模型管理**: 根据配置显示可用模型

## 具体技术实现

### 模型过滤

```rust
let models = chat.models_manager.try_list_models()
    .expect("models lock available")
    .into_iter()
    .filter(|preset| !preset.hidden)  // 过滤隐藏模型
    .collect::<Vec<_>>();
```

### 渲染输出

```
Select Model

› 1. gpt-5
  2. gpt-5.1-codex-mini
  3. gpt-5.1-codex-max
  
(3 of 5 models shown - 2 hidden)
```

## 关键代码路径与文件引用

- **测试文件**: `codex-rs/tui/src/chatwidget/tests.rs`
- **模型管理**: `codex-core/src/models_manager/`

## 依赖与外部交互

1. **模型配置**: 模型预设和可见性设置

## 改进建议
1. 添加显示隐藏模型的选项
2. 显示模型隐藏原因
3. 添加模型搜索功能
