# 研究文档: approvals_selection_popup@windows_degraded.snap

## 场景与职责

该快照文件测试 Windows 平台在降级/受限模式下的权限选择弹窗渲染。当 Windows 系统无法使用完整沙盒功能时，显示降级模式的权限选项。

## 功能点目的

1. **降级模式检测**: 检测 Windows 沙盒功能不可用或受限的情况
2. **降级UI提示**: 向用户说明当前处于降级模式及其原因
3. **安全降级**: 在功能受限时提供安全的替代方案

## 具体技术实现

### 降级模式触发条件

- Windows 版本不支持容器化沙盒
- 系统策略禁止沙盒使用
- 资源限制（内存/CPU）
- 权限不足无法创建沙盒

### 降级模式UI特点

```
Update Model Permissions

› 1. Read Only (current)             Codex can read files in the current
                                     workspace. Approval is required to edit
                                     files or access the internet.
  2. Default (degraded sandbox)   Codex can read and edit files in the
                                     current workspace, and run commands.
                                     Approval is required to access the
                                     internet or edit other files.
                                     
                                     ⚠️  Sandbox protection is limited on this
                                     system. Some security features may not
                                     be available.
```

## 关键代码路径与文件引用

- **测试文件**: `codex-rs/tui/src/chatwidget/tests.rs`
- **降级检测**: `codex-core/src/windows_sandbox/`
- **警告渲染**: 使用特定的样式（如黄色/橙色）显示降级警告

## 依赖与外部交互

1. **Windows 沙盒API**: 检测沙盒功能可用性
2. **系统信息**: 获取 Windows 版本和配置信息

## 风险、边界与改进建议

### 风险
- 用户可能忽略降级警告
- 降级模式可能降低系统安全性

### 边界情况
- 动态检测：运行时沙盒功能可能变化
- 部分降级：某些功能可用而其他不可用

### 改进建议
1. 添加详细的降级原因说明
2. 提供升级到完整功能的指导
3. 在状态栏持续显示降级模式指示器
4. 允许管理员强制启用/禁用降级模式
