# 研究报告: status_line_fast_mode_footer.snap

## 场景与职责

该快照文件验证**状态栏快速模式指示器**的渲染效果。当用户启用 Fast 模式（通过 `/fast` 命令）时，状态栏会显示 "Fast on" 或 "Fast off" 来指示当前状态。

测试场景：
- 用户配置了自定义状态栏包含 `fast-mode` 项
- Fast 模式已启用 (`ServiceTier::Fast`)
- 验证状态栏正确显示 "Fast on"

## 功能点目的

**状态栏自定义**功能允许用户配置底部状态栏显示的信息：

1. **模式可见性** - 实时显示 Fast 模式开关状态
2. **用户控制** - 用户可通过 `/fast` 命令切换
3. **持久化** - Fast 模式选择会保存到配置
4. **模型关联** - 仅特定模型支持 Fast 模式

## 具体技术实现

### 测试实现

```rust
// tests.rs:10589-10607
#[tokio::test]
async fn status_line_fast_mode_footer_snapshot() {
    use ratatui::Terminal;
    use ratatui::backend::TestBackend;

    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(None).await;
    chat.show_welcome_banner = false;
    // 配置状态栏显示 fast-mode
    chat.config.tui_status_line = Some(vec!["fast-mode".to_string()]);
    chat.set_service_tier(Some(ServiceTier::Fast));
    chat.refresh_status_line();

    let width = 80;
    let height = chat.desired_height(width);
    let mut terminal = Terminal::new(TestBackend::new(width, height)).expect("create terminal");
    terminal
        .draw(|f| chat.render(f.area(), f.buffer_mut()))
        .expect("draw fast-mode footer");
    assert_snapshot!("status_line_fast_mode_footer", terminal.backend());
}
```

### 状态栏配置

```rust
// Config 中的状态栏配置
pub struct Config {
    pub tui_status_line: Option<Vec<String>>, // 状态栏项目列表
    // ...
}

// 支持的状态栏项目
const STATUS_LINE_ITEMS: &[&str] = &[
    "fast-mode",           // Fast 模式状态
    "model-with-reasoning", // 模型和推理级别
    "context-remaining",   // 剩余上下文百分比
    "current-dir",         // 当前目录
];
```

### 状态栏刷新逻辑

```rust
fn refresh_status_line(&mut self) {
    let mut parts = Vec::new();
    
    for item in self.config.tui_status_line.as_deref().unwrap_or_default() {
        match item.as_str() {
            "fast-mode" => {
                let status = if self.service_tier == Some(ServiceTier::Fast) {
                    "on"
                } else {
                    "off"
                };
                parts.push(format!("Fast {status}"));
            }
            // ... 其他项目
        }
    }
    
    self.status_line = parts.join(" · ");
}
```

### 渲染输出

```
"                                                                                "
"                                                                                "
"› Ask Codex to do anything                                                      "
"                                                                                "
"  Fast on                                                                       "
```

**解析**：
- 第 3 行：`› Ask Codex to do anything` - 输入提示
- 第 5 行：`  Fast on` - 状态栏显示 Fast 模式已启用

## 关键代码路径与文件引用

| 文件 | 行号范围 | 描述 |
|------|----------|------|
| `codex-rs/tui/src/chatwidget/tests.rs` | 10589-10607 | Fast 模式状态栏测试 |
| `codex-rs/tui/src/chatwidget/tests.rs` | 10567-10587 | Fast 模式切换逻辑测试 |
| `codex-rs/tui/src/chatwidget/mod.rs` | - | `refresh_status_line` 方法 |
| `codex-rs/tui/src/bottom_pane/` | - | 状态栏渲染组件 |

## 依赖与外部交互

### Fast 模式事件流

```rust
// 用户执行 /fast 命令
chat.dispatch_command(SlashCommand::Fast);

// 发送事件
AppEvent::CodexOp(Op::OverrideTurnContext {
    service_tier: Some(Some(ServiceTier::Fast)),
    // ...
})

// 持久化事件
AppEvent::PersistServiceTierSelection {
    service_tier: Some(ServiceTier::Fast),
}
```

### ServiceTier 枚举

```rust
codex_protocol::protocol::ServiceTier {
    Default, // 标准模式
    Fast,    // 快速模式（可能消耗更多额度）
}
```

## 风险、边界与改进建议

### 特定风险

1. **额度消耗** - Fast 模式可能更快消耗 API 额度，需要明确提示
2. **模型兼容性** - 不是所有模型都支持 Fast 模式
3. **状态同步** - 服务器端和客户端状态可能不一致

### 边界情况

1. **状态栏空间不足** - 窄终端宽度下状态栏截断
2. **多项目冲突** - 与其他状态栏项目的布局冲突
3. **配置错误** - 无效的状态栏项目名处理

### 改进建议

1. **图标指示** - 使用 ⚡ 等图标增强视觉识别
2. **颜色区分** - Fast on 使用绿色，Fast off 使用灰色
3. **悬停提示** - 鼠标悬停显示 Fast 模式详细说明
4. **快捷键** - 添加快速切换快捷键（如 Ctrl+F）
5. **自动切换** - 根据任务复杂度自动建议 Fast 模式

### 相关测试

- `status_line_model_with_reasoning_fast_footer` - 组合状态栏测试（模型+推理+Fast）
- `fast_slash_command_updates_and_persists_local_service_tier` - Fast 命令持久化测试
