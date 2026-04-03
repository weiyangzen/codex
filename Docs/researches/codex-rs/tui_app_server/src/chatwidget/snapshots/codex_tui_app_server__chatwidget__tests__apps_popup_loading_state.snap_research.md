# Research: apps_popup_loading_state (App Server)

## 场景与职责

此 snapshot 测试验证 **tui_app_server** 中应用弹出框的加载状态渲染效果。当用户打开应用选择界面时，如果应用列表尚未加载完成，会显示一个加载状态界面。

**测试目的**：确保应用加载状态界面正确显示加载提示和占位符选项。

## 功能点目的

1. **加载状态反馈**：告知用户应用列表正在加载中
2. **占位符显示**：在数据加载完成前显示占位选项
3. **防止误操作**：避免用户在数据未就绪时进行无效选择
4. **状态更新提示**：说明界面会在数据就绪后自动更新

## 具体技术实现

### Snapshot 内容
```
  Apps
  Loading installed and available apps...

› 1. Loading apps...  This updates when the full list is ready.
```

### 关键代码路径

1. **测试函数**：
   - 文件：`codex-rs/tui_app_server/src/chatwidget/tests.rs`
   - 函数：`apps_popup_loading_state_snapshot` (约 line 7377)

2. **加载状态触发**：
   ```rust
   // 在测试前，ConnectorsCacheState 为 Uninitialized 或 Loading
   chat.connectors_cache = ConnectorsCacheState::Loading;
   ```

3. **应用弹出框渲染**：
   - 文件：`codex-rs/tui_app_server/src/bottom_pane/app_link_view.rs`
   - 结构：`AppLinkView`
   - 根据 `ConnectorsCacheState` 状态渲染不同内容

4. **连接器缓存状态**：
   ```rust
   #[derive(Debug, Clone, Default, PartialEq, Eq)]
   enum ConnectorsCacheState {
       #[default]
       Uninitialized,
       Loading,
       Ready(ConnectorsSnapshot),
       Failed(String),
   }
   ```

### 数据结构

```rust
// 连接器快照
codex_chatgpt::connectors::ConnectorsSnapshot {
    connectors: Vec<AppInfo>,
}

// 应用信息
codex_chatgpt::connectors::AppInfo {
    id: String,
    name: String,
    description: Option<String>,
    logo_url: Option<String>,
    logo_url_dark: Option<String>,
    distribution_channel: Option<String>,
    branding: Option<AppBranding>,
    app_metadata: Option<AppMetadata>,
    labels: Option<Vec<String>>,
    install_url: Option<String>,
    is_accessible: bool,
    is_enabled: bool,
    plugin_display_names: Vec<String>,
}
```

### 状态流转

```
Uninitialized -> Loading -> Ready(ConnectorsSnapshot)
                     |
                     v
                  Failed(String)
```

## 依赖与外部交互

### 内部依赖
| 模块 | 用途 |
|------|------|
| `chatwidget::ChatWidget` | 管理连接器缓存状态 |
| `bottom_pane::app_link_view::AppLinkView` | 应用链接视图渲染 |
| `bottom_pane::list_selection_view` | 选项列表渲染 |

### 外部依赖
| 模块 | 用途 |
|------|------|
| `codex_chatgpt::connectors` | 应用/连接器数据获取 |

### 异步加载流程
1. 用户触发应用选择（如 `/apps` 命令）
2. `ChatWidget` 检查 `connectors_cache` 状态
3. 如果为 `Uninitialized`，发起异步加载请求
4. 状态变为 `Loading`，显示加载界面
5. 数据加载完成后，状态变为 `Ready`
6. 界面自动更新显示应用列表

## 风险、边界与改进建议

### 当前风险
1. **加载超时**：长时间加载无反馈可能导致用户困惑
2. **加载失败**：网络错误时的错误状态处理
3. **状态同步**：异步状态更新与 UI 渲染的同步问题

### 边界情况
1. **空应用列表**：加载成功但无可用应用
2. **部分加载**：部分应用数据加载失败
3. **重复加载**：用户快速多次触发加载
4. **缓存过期**：缓存数据过期的处理

### 改进建议
1. **加载进度**：显示加载进度条或百分比
2. **取消操作**：提供取消加载的选项
3. **重试机制**：加载失败时提供重试按钮
4. **缓存优先**：先显示缓存数据，后台更新
5. **加载超时**：设置合理的超时时间并提示用户
6. **骨架屏**：使用骨架屏替代简单文本提示

### 与 TUI 版本的关系
- 与 `codex_tui__chatwidget__tests__apps_popup_loading_state.snap` 保持平行实现
- 连接器缓存机制在两个版本中一致
- 加载状态渲染逻辑相同

### 测试验证点
1. ✅ 标题 "Apps" 正确显示
2. ✅ 加载提示 "Loading installed and available apps..." 正确显示
3. ✅ 占位选项 "Loading apps..." 正确显示
4. ✅ 占位选项描述 "This updates when the full list is ready." 正确显示
5. ✅ 选中标记（›）正确显示在占位选项上

### 相关测试
- `apps_popup_loading_state`：加载状态
- 后续测试验证加载完成后的应用列表显示（如 Notion、Linear 等应用）
