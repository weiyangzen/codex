# 研究文档: permissions_selection_history_full_access_to_default@windows.snap

## 场景与职责

该快照文件是 Windows 平台特定的权限降级历史记录测试。验证在 Windows 系统上从完全访问权限切换回默认权限时的显示效果。

## 功能点目的

1. **平台特定显示**: Windows 平台可能有特定的权限说明
2. **沙盒模式**: Windows 沙盒模式的特殊处理
3. **安全提示**: Windows 特定的安全提示

## 具体技术实现

### Windows 特定内容

可能包含 Windows 沙盒相关的额外说明：
```
⚠️  Permissions changed from Full Access to Default
   Windows Sandbox protection restored.
```

## 关键代码路径与文件引用

- **测试文件**: `codex-rs/tui/src/chatwidget/tests.rs`
- **Windows 配置**: `WindowsSandboxModeToml`

## 依赖与外部交互

1. **Windows API**: 沙盒状态检测

## 改进建议
1. 添加 Windows 特定安全功能的说明
