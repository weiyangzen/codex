# 研究文档: approvals_selection_popup@windows.snap

## 场景与职责

该快照文件是 Windows 平台特定的权限选择弹窗测试。验证在 Windows 操作系统上权限预设的正确渲染，包括 Windows 特有的沙盒模式。

## 功能点目的

1. **平台适配**: 针对 Windows 平台的权限选项调整
2. **Windows 沙盒**: 展示 Windows 特有的沙盒模式选项
3. **跨平台一致性**: 确保核心功能在各平台一致，同时尊重平台特性

## 具体技术实现

### Windows 特定配置

```rust
#[cfg(target_os = "windows")]
use codex_core::config::types::WindowsSandboxModeToml;

#[cfg(target_os = "windows")]
use codex_protocol::config_types::WindowsSandboxLevel;
```

### Windows 特有选项

Windows 版本可能包含额外的权限选项，如：
- Windows Sandbox 集成
- 管理员权限要求提示
- Windows 特定的安全策略

## 关键代码路径与文件引用

- **测试文件**: `codex-rs/tui/src/chatwidget/tests.rs`
- **Windows 配置**: `codex-core/src/config/types.rs` (Windows 特定代码)
- **平台检测**: 使用 `#[cfg(target_os = "windows")]` 条件编译

## 依赖与外部交互

1. **Windows API**: 用于检测和配置 Windows 沙盒
2. **codex-protocol**: 跨平台协议定义

## 风险、边界与改进建议

### 风险
- Windows 版本差异可能导致行为不一致
- 沙盒模式可能与某些功能不兼容

### 边界情况
- Windows 家庭版 vs 专业版的功能差异
- UAC（用户账户控制）设置的影响

### 改进建议
1. 添加 Windows 版本检测和适配
2. 提供 Windows 沙盒的详细配置选项
3. 添加 Windows 特定的安全提示
