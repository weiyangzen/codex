# TUI App Server App Link View Enable Suggestion Snapshot 研究文档

## 场景与职责

该快照文件是 `codex_tui_app_server` crate 中 `app_link_view.rs` 模块的测试快照，与 `codex_tui` 前缀的对应文件类似，但针对 `tui_app_server` crate 进行验证。用于验证**应用链接视图的启用建议界面**在 app-server 架构下的渲染输出。

### 与 TUI Crate 的关系
- `tui_app_server` 是 Codex 的 TUI 应用服务器实现
- 与 `tui` crate 共享相同的应用链接视图逻辑
- 通过快照测试确保两者渲染一致性

### 架构差异
| 特性 | tui crate | tui_app_server crate |
|------|-----------|---------------------|
| 架构 | 单体 | 客户端-服务器 |
| 渲染 | 直接 | 通过协议 |
| 状态管理 | 本地 | 服务器同步 |

## 功能点目的

### 核心功能
与 `codex_tui` 版本相同：
1. **应用信息展示**：显示应用名称、描述和使用说明
2. **建议理由展示**：说明为什么建议启用此应用
3. **操作引导**：提供清晰的操作选项
4. **键盘导航支持**：支持 Tab/↑↓ 移动、Enter 选择、Esc 关闭

### App-Server 特定目标
- **协议兼容性**：确保通过 app-server 协议渲染正确
- **状态同步**：确保服务器和客户端状态一致
- **事件传递**：确保用户操作正确传递到服务器

## 具体技术实现

### 关键差异
```rust
// tui_app_server 中的事件发送
fn resolve_elicitation(&self, decision: ElicitationAction) {
    let Some(target) = self.elicitation_target.as_ref() else {
        return;
    };
    self.app_event_tx.resolve_elicitation(
        target.thread_id,
        target.server_name.clone(),
        target.request_id.clone(),
        decision,
        /*content*/ None,
        /*meta*/ None,
    );
}
```

### 测试参数
与 `codex_tui` 版本相同：
```rust
AppLinkViewParams {
    app_id: "connector_google_calendar".to_string(),
    title: "Google Calendar".to_string(),
    description: Some("Plan events and schedules.".to_string()),
    instructions: "Enable this app to use it for the current request.".to_string(),
    url: "https://example.test/google-calendar".to_string(),
    is_installed: true,
    is_enabled: false,
    suggest_reason: Some("Plan and reference events from your calendar".to_string()),
    suggestion_type: Some(AppLinkSuggestionType::Enable),
    elicitation_target: Some(suggestion_target()),
}
```

### 渲染输出对比
与 `codex_tui` 版本输出基本一致：
```
  Google Calendar
  Plan events and schedules.

  Plan and reference events from your calendar

  Use $ to insert this app into the prompt.

  Enable this app to use it for the current request.
  Newly installed apps can take a few minutes to appear in /apps.


  › 1. Manage on ChatGPT
    2. Enable app
    3. Back
  Use tab / ↑ ↓ to move, enter to select, esc to close
```

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
2. **网络延迟**：网络问题导致状态同步延迟
3. **序列化问题**：复杂状态的序列化/反序列化错误

### 边界情况
1. **连接断开**：与服务器断开连接时的处理
2. **状态冲突**：客户端和服务器状态不一致
3. **重连恢复**：重新连接后的状态恢复

### 改进建议
1. **协议版本协商**：连接时协商协议版本
2. **离线模式**：支持离线操作，联网后同步
3. **状态校验**：定期校验客户端和服务器状态
4. **重试机制**：网络失败时自动重试

### 相关文件引用
- 源文件: `codex-rs/tui_app_server/src/bottom_pane/app_link_view.rs`
- 协议定义: `codex-rs/app-server-protocol/src/`
