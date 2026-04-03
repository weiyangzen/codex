# 研究文档: codex_tui__chatwidget__tests__apps_popup_loading_state.snap

## 场景与职责

本快照文件验证 **Apps 弹窗加载状态** 的渲染输出。

当用户打开 Apps 选择界面但应用列表尚未加载完成时，显示此加载状态。

## 功能点目的

1. **加载反馈**: 告知用户应用列表正在加载中
2. **防止误操作**: 加载期间禁用选择操作
3. **状态同步**: 列表加载完成后自动更新

## 具体技术实现

### 快照内容结构
```
Apps
Loading installed and available apps...

› 1. Loading apps...  This updates when the full list is ready.
```

### UI 元素分析

| 元素 | 说明 |
|------|------|
| 标题 | "Apps" |
| 加载提示 | "Loading installed and available apps..." |
| 占位选项 | 单个加载中选项 |
| 状态说明 | "This updates when the full list is ready." |

### 加载流程
```
用户触发 /apps
    ↓
显示加载弹窗
    ↓
异步加载应用列表
    ↓
加载完成 → 更新弹窗内容
    ↓
用户选择应用
```

## 关键代码路径与文件引用

### 测试定义
```rust
expression: before
```

### 异步加载
```rust
// 伪代码
async fn load_apps() -> Vec<App> {
    show_loading_state();
    let apps = fetch_apps_from_registry().await;
    update_popup(apps);
}
```

### 相关模块
- `chatwidget.rs` - 弹窗状态管理
- `codex_core::mcp` - MCP 服务器管理
- `skills_helpers.rs` - 技能/应用辅助函数

## 依赖与外部交互

### 数据来源
- MCP 服务器注册表
- 本地安装的应用
- 远程应用商店（如启用）

### 网络依赖
- 可能需要网络获取可用应用列表
- 超时处理

## 风险、边界与改进建议

### 用户体验风险
1. **加载超时**: 网络慢时加载时间过长
2. **空状态**: 没有可用应用时的处理
3. **错误处理**: 加载失败时的反馈

### 改进建议
1. **加载动画**: 添加 spinner 动画
2. **进度显示**: 显示加载进度（如 "3/10 apps loaded"）
3. **取消按钮**: 允许用户取消加载
4. **缓存**: 缓存上次加载的应用列表
5. **离线模式**: 网络不可用时显示已缓存列表
6. **错误重试**: 加载失败时提供重试按钮

### 相关测试
- 应补充测试：加载完成后的完整列表显示
- 应补充测试：加载失败错误状态
- 应补充测试：空列表状态
