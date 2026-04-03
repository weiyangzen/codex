# 权限选择历史从完全访问到默认（Windows 平台）测试研究文档

## 场景与职责

该 snapshot 测试是 `permissions_selection_history_full_access_to_default` 测试的 Windows 平台特定版本，验证在 Windows 操作系统上，当用户从 "Full Access"（完全访问）权限模式切换回 "Default"（默认）模式时，tui_app_server 的 ChatWidget 能够在历史记录中正确显示包含 Windows 特定信息的权限更新消息。

**测试场景**：
1. 用户在 Windows 平台上运行 Codex
2. 用户当前处于 Full Access 权限模式
3. 用户切换到 Default 权限模式
4. 系统在历史记录中显示包含 Windows 沙箱信息的权限更新消息

**职责**：确保 Windows 用户了解他们使用的是非管理员沙箱模式，提供平台特定的安全上下文信息。

## 功能点目的

- **平台透明性**：明确告知 Windows 用户当前使用的是非管理员沙箱
- **安全上下文**：帮助用户理解 Windows 平台上的权限限制
- **审计追踪**：记录 Windows 特定的权限配置状态
- **用户教育**：教育用户关于 Windows 沙箱模式的限制

## 具体技术实现

### 测试代码位置
`codex-rs/tui_app_server/src/chatwidget/tests.rs` 第 9145-9183 行（与主测试相同，使用条件编译）

```rust
#[tokio::test]
async fn permissions_selection_history_snapshot_full_access_to_default() {
    let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;
    #[cfg(target_os = "windows")]
    {
        chat.config.notices.hide_world_writable_warning = Some(true);
        chat.set_windows_sandbox_mode(Some(WindowsSandboxModeToml::Unelevated));
    }
    // ... 其余代码
    
    #[cfg(target_os = "windows")]
    insta::with_settings!({ snapshot_suffix => "windows" }, {
        assert_snapshot!(
            "permissions_selection_history_full_access_to_default",
            lines_to_single_string(&cells[0])
        );
    });
    // ...
}
```

### Windows 特定配置

1. **沙箱模式设置**：
   ```rust
   chat.set_windows_sandbox_mode(Some(WindowsSandboxModeToml::Unelevated));
   ```
   设置为非提升（非管理员）沙箱模式

2. **警告隐藏**：
   ```rust
   chat.config.notices.hide_world_writable_warning = Some(true);
   ```
   隐藏世界可写警告，避免干扰测试

3. **Snapshot 后缀**：
   使用 `insta::with_settings!({ snapshot_suffix => "windows" }, ...)` 生成平台特定的 snapshot 文件

### Snapshot 输出内容

```
• Permissions updated to Default (non-admin sandbox)
```

与非 Windows 平台的区别：
- **Windows**：`Permissions updated to Default (non-admin sandbox)`
- **非 Windows**：`Permissions updated to Default`

## 关键代码路径与文件引用

### 主要代码文件

1. **测试文件**：`codex-rs/tui_app_server/src/chatwidget/tests.rs`
   - 测试函数：`permissions_selection_history_snapshot_full_access_to_default` (第 9145 行)

2. **Windows 沙箱配置**：`codex-core/src/config/types.rs`
   - `WindowsSandboxModeToml`：Windows 沙箱模式配置
   - `Unelevated`：非提升（非管理员）模式

3. **权限显示逻辑**：`codex-rs/tui_app_server/src/chatwidget/mod.rs`
   - 平台特定的权限描述生成

4. **Snapshot 文件**：
   - Windows：`codex_tui_app_server__chatwidget__tests__permissions_selection_history_full_access_to_default@windows.snap`
   - 非 Windows：`codex_tui_app_server__chatwidget__tests__permissions_selection_history_full_access_to_default.snap`

### Windows 沙箱模式

| 模式 | 描述 |
|------|------|
| `Elevated` | 管理员权限沙箱，具有更高权限 |
| `Unelevated` | 非管理员沙箱，权限受限，更安全 |

## 依赖与外部交互

### 内部依赖

| 组件 | 用途 |
|------|------|
| `ChatWidget` | 主聊天组件，管理权限选择流程 |
| `WindowsSandboxModeToml` | Windows 沙箱模式配置 |
| `Config::notices` | 管理警告通知显示 |

### 外部依赖

- `ratatui`：终端 UI 渲染库
- `insta`：snapshot 测试框架（支持平台特定 snapshot）
- `tokio`：异步运行时

### 平台特定编译

使用 Rust 的条件编译特性：
```rust
#[cfg(target_os = "windows")]
// Windows 特定代码

#[cfg(not(target_os = "windows"))]
// 非 Windows 代码
```

## 风险、边界与改进建议

### 潜在风险

1. **权限误解**：用户可能不理解 "non-admin sandbox" 的含义，误以为功能受限
2. **平台差异**：Windows 和非 Windows 的不同行为需要额外的文档支持
3. **升级提示**：用户可能不知道可以升级到管理员沙箱模式以获得更高权限

### 边界情况

1. **管理员运行**：如果 Codex 以管理员身份运行，沙箱模式可能不同
2. **企业环境**：某些企业环境可能限制沙箱模式的选择
3. **Windows 版本**：不同 Windows 版本（Home/Pro/Enterprise）的沙箱功能可能不同

### 改进建议

1. **帮助链接**：在权限更新消息中添加链接，解释 "non-admin sandbox" 的含义
2. **升级提示**：如果用户频繁遇到权限限制，提示可以切换到管理员模式
3. **可视化指示**：在状态栏显示当前沙箱模式的图标或指示器
4. **一键切换**：提供快速切换到管理员模式的快捷方式（如果可用）
5. **权限检查**：在尝试需要高权限的操作前，预先检查并提示用户

### 相关测试

- `permissions_selection_history_full_access_to_default`（非 Windows 版本）
- `approvals_selection_popup_snapshot_windows_degraded_sandbox`：Windows 降级沙箱测试
- `windows_auto_mode_prompt_requests_enabling_sandbox_feature`：Windows 沙箱启用提示
- `startup_prompts_for_windows_sandbox_when_agent_requested`：启动时 Windows 沙箱提示

### Windows 特定 UI 考虑

1. **术语一致性**：确保 "non-admin sandbox" 与 Windows 系统的用户账户控制（UAC）术语一致
2. **权限提升指导**：提供如何以管理员身份运行 Codex 的指导
3. **安全与便利平衡**：帮助用户理解安全（非管理员）和便利（管理员）之间的权衡
