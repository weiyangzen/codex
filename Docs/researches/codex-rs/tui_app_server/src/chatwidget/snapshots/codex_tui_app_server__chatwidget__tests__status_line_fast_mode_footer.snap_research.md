# Status Line Fast Mode Footer 研究文档

## 场景与职责

该 snapshot 测试验证当状态栏配置为显示 "fast-mode" 项时，页脚的渲染效果。确保 Fast 模式状态（开启/关闭）能够正确显示在状态栏中，为用户提供当前服务层级的视觉反馈。

**测试文件**: `codex-rs/tui_app_server/src/chatwidget/tests.rs`  
**Snapshot 文件**: `codex_tui_app_server__chatwidget__tests__status_line_fast_mode_footer.snap`

## 功能点目的

1. **Fast 模式状态显示**: 显示当前是否启用了 Fast 服务层级
2. **用户配置验证**: 验证用户自定义状态栏配置的正确渲染
3. **视觉反馈**: 提供关于 API 请求优先级的即时视觉反馈
4. **配置持久化**: 确保状态栏配置从配置文件正确加载和应用

## 具体技术实现

### 状态栏配置
```rust
// 用户配置的状态栏项目
config.tui_status_line = Some(vec!["fast-mode".to_string()]);
```

### Fast 模式状态值计算
```rust
fn status_line_value_for_item(&self, item: &StatusLineItem) -> Option<String> {
    match item {
        StatusLineItem::FastMode => Some(
            if matches!(self.config.service_tier, Some(ServiceTier::Fast)) {
                "Fast on".to_string()
            } else {
                "Fast off".to_string()
            }
        ),
        // ...
    }
}
```

### 状态栏刷新流程
```rust
pub(crate) fn refresh_status_line(&mut self) {
    let (items, invalid_items) = self.status_line_items_with_invalids();
    
    // 验证配置项
    if self.thread_id.is_some() && !invalid_items.is_empty() {
        // 警告无效配置项
    }
    
    // 启用/禁用状态栏
    let enabled = !items.is_empty();
    self.bottom_pane.set_status_line_enabled(enabled);
    
    if !enabled {
        self.set_status_line(/*status_line*/ None);
        return;
    }
    
    // 构建状态栏文本
    let mut parts = Vec::new();
    for item in items {
        if let Some(value) = self.status_line_value_for_item(&item) {
            parts.push(value);
        }
    }
    
    let line = if parts.is_empty() {
        None
    } else {
        Some(Line::from(parts.join(" · ")))
    };
    self.set_status_line(line);
}
```

### 测试用例实现
```rust
#[tokio::test]
async fn status_line_fast_mode_footer_snapshot() {
    use ratatui::Terminal;
    use ratatui::backend::TestBackend;
    
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(None).await;
    chat.show_welcome_banner = false;
    
    // 配置状态栏只显示 fast-mode
    chat.config.tui_status_line = Some(vec!["fast-mode".to_string()]);
    
    // 启用 Fast 模式
    chat.set_service_tier(Some(ServiceTier::Fast));
    chat.refresh_status_line();
    
    // 渲染测试
    let width = 80;
    let height = chat.desired_height(width);
    let mut terminal = Terminal::new(TestBackend::new(width, height)).expect("create terminal");
    terminal
        .draw(|f| chat.render(f.area(), f.buffer_mut()))
        .expect("draw fast-mode footer");
    assert_snapshot!("status_line_fast_mode_footer", terminal.backend());
}
```

## 关键代码路径与文件引用

| 文件路径 | 相关代码/函数 | 说明 |
|---------|-------------|------|
| `codex-rs/tui_app_server/src/chatwidget.rs` | `refresh_status_line()` (L1604) | 状态栏刷新主函数 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | `status_line_value_for_item()` (L6956) | 状态项值计算 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | `StatusLineItem::FastMode` (L7029) | FastMode 项处理 |
| `codex-rs/tui_app_server/src/bottom_pane.rs` | `set_status_line()` | 状态栏设置 |
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | `status_line_fast_mode_footer_snapshot()` (L11322) | 测试函数 |

## 依赖与外部交互

### 依赖模块
- `codex_protocol::config_types::ServiceTier`: 服务层级枚举
- `crate::bottom_pane::StatusLineItem`: 状态栏项枚举
- `ratatui::text::Line`: 文本行渲染

### 服务层级类型
```rust
pub enum ServiceTier {
    Fast,  // 快速响应层级
    // 默认层级（None）
}
```

### 状态栏项枚举
```rust
pub enum StatusLineItem {
    ModelName,
    ModelWithReasoning,
    CurrentDir,
    ProjectRoot,
    GitBranch,
    UsedTokens,
    ContextRemaining,
    ContextUsed,
    FiveHourLimit,
    WeeklyLimit,
    CodexVersion,
    ContextWindowSize,
    TotalInputTokens,
    TotalOutputTokens,
    SessionId,
    FastMode,  // 本测试涉及的项
}
```

### 配置持久化
```toml
# ~/.codex/config.toml
[tui]
status_line = ["fast-mode"]
```

## 风险、边界与改进建议

### 潜在风险
1. **配置项拼写错误**: 用户可能输入错误的配置项 ID，导致状态栏不显示
2. **状态同步延迟**: 服务层级变更后状态栏更新可能有延迟
3. **多项冲突**: 与其他状态项组合时可能出现布局问题

### 边界情况
1. **空配置**: 状态栏配置为空列表时的处理
2. **无效配置项**: 包含不存在的状态项 ID 时的警告
3. **线程未启动**: 会话未开始时状态栏的显示策略
4. **配置热重载**: 配置变更后状态栏的实时更新

### 改进建议
1. **配置验证**: 在配置加载时验证所有状态项 ID 的有效性
2. **自动完成**: 在 `/statusline` 设置命令中提供自动完成
3. **条件显示**: 仅在 Fast 模式开启时显示，关闭时隐藏该项
4. **图标支持**: 使用图标（⚡）代替文本，节省空间
5. **颜色编码**: Fast on 时使用绿色，Fast off 时使用灰色
6. **点击切换**: 支持点击状态栏快速切换 Fast 模式

### 相关测试覆盖
- Fast 模式状态栏测试（本测试）
- 模型带推理状态栏测试
- 状态栏配置验证测试
- 无效配置项警告测试

### Snapshot 内容分析
```
"                                                                                "
"                                                                                "
"› Ask Codex to do anything                                                      "
"                                                                                "
"  Fast on                                                                       "
```

**关键观察点**:
1. **位置**: 状态栏显示在底部（第5行）
2. **格式**: "Fast on" 简洁明了
3. **对齐**: 左对齐，与输入框保持一致的缩进（2空格）
4. **无分隔符**: 单一项时不显示 "·" 分隔符
5. **欢迎横幅**: 已禁用（`show_welcome_banner = false`），避免干扰

这表明状态栏能够正确渲染单一配置项，且布局整洁。
