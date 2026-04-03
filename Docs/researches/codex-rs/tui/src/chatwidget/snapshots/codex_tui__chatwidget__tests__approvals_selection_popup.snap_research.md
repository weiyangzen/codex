# 研究文档: approvals_selection_popup.snap

## 场景与职责

该快照文件测试权限选择弹窗的渲染效果。当用户需要更改 Codex 的操作权限模式时，显示此弹窗供用户选择不同的权限预设。

## 功能点目的

1. **权限模式选择**: 允许用户在运行时切换不同的权限配置
2. **预设展示**: 展示可用的权限预设（Read Only、Default、Full Access 等）
3. **安全提示**: 说明每种权限模式的安全 implications

## 具体技术实现

### 权限预设选项

```
› 1. Read Only (current)             Codex can read files in the current
                                     workspace. Approval is required to edit
                                     files or access the internet.
  2. Default (non-admin sandbox)  Codex can read and edit files in the
                                     current workspace, and run commands.
                                     Approval is required to access the
                                     internet or edit other files.
  3. Full Access                     Codex can edit files outside this
                                     workspace and access the internet without
                                     asking for approval. Exercise caution
                                     when using.
```

### 渲染特点

- 当前选中的权限用 `›` 标记
- 每个选项包含名称和详细描述
- 描述文本自动换行以适应屏幕宽度
- 底部显示操作提示

## 关键代码路径与文件引用

- **测试文件**: `codex-rs/tui/src/chatwidget/tests.rs`
- **权限配置**: `codex-core/src/config/types.rs`
- **弹窗渲染**: `render_bottom_popup` 函数

## 依赖与外部交互

1. **codex-core**: 权限配置类型定义
2. **textwrap**: 文本自动换行

## 风险、边界与改进建议

### 风险
- 用户可能误选高权限模式
- 权限切换可能需要重新认证

### 边界情况
- 平台特定的权限限制（如 Windows Sandbox）
- 网络策略与权限模式的冲突

### 改进建议
1. 添加权限变更确认对话框
2. 显示当前权限模式的视觉指示器
3. 添加权限模式切换的快捷键
4. 提供权限模式的详细文档链接
