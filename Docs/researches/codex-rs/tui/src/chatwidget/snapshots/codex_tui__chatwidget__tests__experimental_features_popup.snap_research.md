# 研究文档: experimental_features_popup.snap

## 场景与职责

该快照文件测试实验性功能选择弹窗的渲染效果。允许用户启用或禁用正在开发中的新功能。

## 功能点目的

1. **功能开关**: 让用户控制实验性功能的启用状态
2. **早期访问**: 允许用户体验正在开发的新功能
3. **风险控制**: 明确标识实验性功能的风险

## 具体技术实现

### 实验性功能管理

```rust
use codex_core::features::FEATURES;
use codex_core::features::Feature;

// 启用实验性功能
chat.set_feature_enabled(Feature::CollaborationModes, true);
```

### 弹窗内容

```
Experimental Features

› 1. Collaboration Modes    [✓]
  2. Real-time Voice       [ ]
  3. Advanced Tools        [ ]

Note: Experimental features may be unstable.
```

## 关键代码路径与文件引用

- **测试文件**: `codex-rs/tui/src/chatwidget/tests.rs`
- **功能管理**: `codex-core/src/features.rs`
- **配置持久化**: 实验性功能状态保存

## 依赖与外部交互

1. **codex-core**: 功能标志定义

## 风险、边界与改进建议

### 风险
- 实验性功能可能导致不稳定
- 功能依赖关系可能导致意外行为

### 改进建议
1. 添加功能依赖关系检查
2. 提供功能说明和文档链接
3. 添加反馈收集机制
4. 实验性功能使用独立配置命名空间
