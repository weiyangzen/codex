# 研究文档：实验性功能弹出菜单

## 场景与职责

该快照测试验证实验性功能选择界面的渲染。用户可以通过此界面启用或禁用实验性功能，如 Ghost snapshots 和 Shell tool。

**测试场景**：
- 用户通过 `/experimental` 或类似命令打开实验性功能菜单
- 界面显示可用的实验性功能列表
- 用户可以切换功能的启用状态

## 功能点目的

1. **功能发现**：让用户了解可用的实验性功能
2. **安全控制**：实验性功能默认禁用，用户主动选择启用
3. **配置持久化**：更改保存到 `config.toml`，影响后续会话

## 具体技术实现

### 测试代码路径
- **文件**: `codex-rs/tui/src/chatwidget/tests.rs` (第 7587-7608 行)
- **测试函数**: `experimental_features_popup_snapshot`

### 核心测试逻辑

```rust
// 1. 准备实验性功能列表
let features = vec![
    ExperimentalFeatureItem {
        feature: Feature::GhostCommit,
        name: "Ghost snapshots".to_string(),
        description: "Capture undo snapshots each turn.".to_string(),
        enabled: false,  // 未启用
    },
    ExperimentalFeatureItem {
        feature: Feature::ShellTool,
        name: "Shell tool".to_string(),
        description: "Allow the model to run shell commands.".to_string(),
        enabled: true,   // 已启用
    },
];

// 2. 创建视图并显示
let view = ExperimentalFeaturesView::new(features, chat.app_event_tx.clone());
chat.bottom_pane.show_view(Box::new(view));

// 3. 渲染并验证
let popup = render_bottom_popup(&chat, 80);
assert_snapshot!("experimental_features_popup", popup);
```

### 快照内容分析

```
  Experimental features
  Toggle experimental features. Changes are saved to config.toml.

› [ ] Ghost snapshots  Capture undo snapshots each turn.
  [x] Shell tool       Allow the model to run shell commands.

  Press space to select or enter to save for next conversation
```

### UI元素解析

| 元素 | 说明 |
|------|------|
| `Experimental features` | 标题 |
| `Toggle experimental features...` | 说明文本 |
| `›` | 当前选中项指示器 |
| `[ ]` | 未启用复选框 |
| `[x]` | 已启用复选框 |
| `Ghost snapshots` | 功能名称 |
| `Capture undo snapshots each turn.` | 功能描述 |
| `Press space to select...` | 操作提示 |

### 功能定义

```rust
// codex-core/src/features.rs
pub enum Feature {
    GhostCommit,  // 每轮创建撤销快照
    ShellTool,    // 允许模型运行 shell 命令
}
```

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `codex-rs/tui/src/bottom_pane/experimental_features_view.rs` | 实验性功能视图实现 |
| `codex-rs/tui/src/bottom_pane/selection_popup_common.rs` | 通用选择弹出组件 |
| `codex-core/src/features.rs` | `Feature` 枚举定义 |
| `codex-rs/tui/src/bottom_pane/mod.rs` | 底部面板管理 |

## 依赖与外部交互

### 配置系统
- `config.toml`：保存功能启用状态
- `ConfigBuilder`：加载和保存配置

### 事件系统
- `AppEvent::SetFeatureEnabled`：启用/禁用功能事件
- `AppEvent::SaveConfig`：保存配置请求

## 风险、边界与改进建议

### 潜在风险
1. **功能稳定性**：实验性功能可能存在 bug 或不稳定
2. **配置冲突**：某些功能可能与其他设置冲突
3. **用户体验**：用户可能不理解某些功能的作用

### 边界情况
- 所有功能都启用时的显示
- 功能列表为空
- 配置保存失败

### 改进建议
1. **功能分类**：按类别组织功能（如安全性、性能、UI）
2. **风险提示**：对高风险功能显示警告
3. **快速重置**：提供恢复默认设置的选项
4. **在线文档**：添加链接到功能文档
5. **A/B 测试标记**：标记正在 A/B 测试的功能

### 相关测试
- `experimental_features_toggle_saves_on_exit`：测试切换和保存
- 其他弹出菜单测试（如 `model_selection_popup`）
