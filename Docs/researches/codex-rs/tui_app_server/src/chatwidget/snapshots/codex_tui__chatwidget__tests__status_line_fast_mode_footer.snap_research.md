# Snapshot Research: status_line_fast_mode_footer

## 场景与职责

此快照测试验证当启用快速模式（Fast Mode）时状态栏的渲染输出。状态栏可以配置显示多种信息，此测试专门验证 `fast-mode` 配置项在启用时的显示效果。

测试场景：
- 创建 ChatWidget 并禁用欢迎横幅
- 配置状态栏显示 `fast-mode`：`config.tui_status_line = Some(vec!["fast-mode".to_string()])`
- 设置服务层级为 Fast：`set_service_tier(Some(ServiceTier::Fast))`
- 刷新状态栏：`refresh_status_line()`
- 使用 `TestBackend` 捕获终端渲染输出

## 功能点目的

1. **服务模式指示**：显示当前使用的服务层级（Fast/Standard）
2. **性能预期管理**：让用户了解当前响应速度预期
3. **配置可视化**：将配置的状态栏项正确渲染到 UI
4. **状态同步**：确保状态栏与实际服务配置保持同步

## 具体技术实现

### 关键流程

1. **状态栏刷新流程**：
   ```
   配置 tui_status_line = ["fast-mode"]
   ↓
   set_service_tier(Some(ServiceTier::Fast))
   ↓
   refresh_status_line()
   ↓
   解析状态栏项
   ↓
   渲染 "Fast on" 到页脚
   ```

2. **状态栏项处理**：
   - 读取 `config.tui_status_line` 配置
   - 根据当前状态生成每个项的显示文本
   - `fast-mode` 项在 `ServiceTier::Fast` 时显示 "Fast on"

### 数据结构

```rust
pub enum ServiceTier {
    Auto,
    Default,
    Fast,
}

pub struct Config {
    pub tui_status_line: Option<Vec<String>>,
    // ...
}

// ChatWidget 中的状态
service_tier: Option<ServiceTier>,
```

### 状态栏刷新实现

```rust
pub(crate) fn refresh_status_line(&mut self) {
    let (items, invalid_items) = self.status_line_items_with_invalids();
    // ... 警告处理
    
    let text = items.join(" · ");
    self.bottom_pane.set_status_line(text);
}

fn status_line_items_with_invalids(&self) -> (Vec<String>, Vec<String>) {
    let mut items = Vec::new();
    let mut invalid = Vec::new();
    
    if let Some(config_items) = &self.config.tui_status_line {
        for item in config_items {
            match item.as_str() {
                "fast-mode" => {
                    if let Some(ServiceTier::Fast) = self.service_tier {
                        items.push("Fast on".to_string());
                    }
                }
                // ... 其他状态栏项
                _ => invalid.push(item.clone()),
            }
        }
    }
    
    (items, invalid)
}
```

## 关键代码路径与文件引用

### 核心文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/chatwidget/tests.rs` | 测试定义（tui，line ~10590） |
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | 测试定义（tui_app_server，line ~11322） |
| `codex-rs/tui/src/chatwidget.rs` | `refresh_status_line()` 和 `status_line_items_with_invalids()` 实现 |
| `codex-rs/tui/src/bottom_pane/mod.rs` | 状态栏渲染 |

### 关键函数

- `ChatWidget::refresh_status_line()` - 刷新状态栏显示
- `ChatWidget::status_line_items_with_invalids()` - 生成状态栏项列表
- `ChatWidget::set_service_tier()` - 设置服务层级
- `BottomPane::set_status_line()` - 设置状态栏文本

### 测试实现

```rust
#[tokio::test]
async fn status_line_fast_mode_footer_snapshot() {
    use ratatui::Terminal;
    use ratatui::backend::TestBackend;

    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(None).await;
    chat.show_welcome_banner = false;
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

## 依赖与外部交互

### 内部依赖

- `ServiceTier` - 服务层级枚举
- `Config::tui_status_line` - 状态栏配置
- `TestBackend` - 测试用的终端后端
- `ratatui::Terminal` - 终端渲染

### 外部交互

- **配置系统**：读取用户配置的状态栏项
- **API 服务**：通过服务层级影响 API 调用行为
- **UI 渲染**：通过 `bottom_pane` 渲染状态栏

## 风险、边界与改进建议

### 潜在风险

1. **配置错误**：无效的状态栏项配置可能导致警告
2. **状态不同步**：服务层级变更后未及时刷新状态栏
3. **布局问题**：状态栏内容过长可能导致布局问题

### 边界情况

- 多个状态栏项的组合显示
- 无效的状态栏项配置
- 服务层级为 Auto 或 Default 时的显示
- 空状态栏配置

### 改进建议

1. **配置验证**：
   - 在配置加载时验证状态栏项的有效性
   - 提供有效的状态栏项列表文档
   - 添加配置建议功能

2. **UI/UX 改进**：
   - 添加状态栏项的图标支持
   - 支持状态栏项的颜色自定义
   - 添加状态栏位置选项（左/中/右对齐）

3. **功能扩展**：
   - 添加更多内置状态栏项（如当前模型、上下文使用率等）
   - 支持自定义状态栏项（通过插件或脚本）
   - 添加状态栏项的条件显示

4. **测试覆盖**：
   - 添加多个状态栏项组合的测试
   - 测试无效配置的处理
   - 测试状态栏的动态更新

---

**快照内容**：
```
"                                                                                "
"                                                                                "
"› Ask Codex to do anything                                                      "
"                                                                                "
"  Fast on                                                                       "
```

**说明**：显示启用快速模式时的 ChatWidget 渲染输出。关键元素：
- `› Ask Codex to do anything` - 输入提示符
- `Fast on` - 状态栏显示快速模式已启用

状态栏位于页脚，显示 "Fast on" 指示当前服务层级为 Fast。这验证了 `fast-mode` 状态栏项在 `ServiceTier::Fast` 时的正确渲染。
