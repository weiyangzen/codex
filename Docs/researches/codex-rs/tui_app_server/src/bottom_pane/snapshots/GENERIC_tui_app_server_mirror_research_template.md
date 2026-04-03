# TUI App Server Mirror Snapshots Generic Research Template

## 场景与职责

该文档是 TUI App Server 镜像快照的通用研究模板，适用于以下快照文件：
- `codex_tui_app_server__bottom_pane__app_link_view__tests__app_link_view_install_suggestion_with_reason.snap`
- `codex_tui_app_server__bottom_pane__approval_overlay__tests__approval_overlay_additional_permissions_macos_prompt.snap`
- `codex_tui_app_server__bottom_pane__approval_overlay__tests__approval_overlay_additional_permissions_prompt.snap`
- `codex_tui_app_server__bottom_pane__approval_overlay__tests__approval_overlay_cross_thread_prompt.snap`
- `codex_tui_app_server__bottom_pane__approval_overlay__tests__approval_overlay_permissions_prompt.snap`
- `codex_tui_app_server__bottom_pane__chat_composer__tests__*.snap` (多个)

### 与 TUI Crate 的关系
这些快照与 `codex_tui` 前缀的快照对应，但针对 `tui_app_server` crate：
- 测试相同的 UI 组件
- 确保 app-server 架构下的渲染一致性
- 验证协议兼容性

### 架构差异
| 方面 | tui crate | tui_app_server crate |
|------|-----------|---------------------|
| 架构 | 单体应用 | 客户端-服务器 |
| 状态管理 | 本地状态 | 服务器同步状态 |
| 渲染 | 直接渲染 | 通过协议渲染 |
| 事件处理 | 本地处理 | 发送到服务器处理 |

## 功能点目的

### 核心功能
1. **协议兼容性**：确保通过 app-server 协议正确渲染
2. **状态同步**：确保客户端和服务器状态一致
3. **事件传递**：确保用户操作正确传递到服务器

### 测试目标
- 验证 app-server 架构下的 UI 正确性
- 确保与单体架构的行为一致性
- 捕获协议或序列化问题

## 具体技术实现

### 关键差异
```rust
// tui_app_server 中的事件发送
self.app_event_tx.send(AppEvent::SomeEvent { ... });

// 与 tui crate 的主要区别
// 1. 事件通过网络发送到服务器
// 2. 状态变更需要服务器确认
// 3. 渲染基于服务器同步的状态
```

### 测试方法
- 创建相同的测试场景
- 使用相同的测试参数
- 比较渲染输出的一致性

## 依赖与外部交互

### 内部依赖
- `codex_protocol` - 与服务器通信的协议
- `AppEventSender` - 应用事件发送器

### 外部交互
- **App Server**：通过协议与服务器通信
- **WebSocket**：实时同步状态

## 风险、边界与改进建议

### 潜在风险
1. **协议版本不匹配**：客户端和服务器协议版本不一致
2. **网络延迟**：状态同步的网络延迟
3. **序列化问题**：复杂状态的序列化/反序列化错误

### 改进建议
1. **协议版本协商**：连接时协商协议版本
2. **离线模式**：支持离线操作，联网后同步
3. **状态校验**：定期校验客户端和服务器状态

### 相关文件引用
- 源文件: `codex-rs/tui_app_server/src/bottom_pane/*.rs`
- 协议定义: `codex-rs/app-server-protocol/src/`
