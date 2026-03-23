# 研究报告: status_line_model_with_reasoning_fast_footer.snap

## 场景与职责

该快照文件验证**组合状态栏**的渲染效果，同时显示多个状态信息：模型名称、推理级别、Fast 模式状态和剩余上下文。

测试场景：
- 使用 gpt-5.4 模型
- 推理级别设置为 XHigh
- Fast 模式已启用
- 显示当前目录和剩余上下文百分比

## 功能点目的

**组合状态栏**提供更全面的会话状态概览：

1. **模型信息** - 当前使用的 AI 模型
2. **推理配置** - 推理努力级别（影响响应质量和速度）
3. **性能模式** - Fast 模式开关状态
4. **上下文使用** - 剩余上下文窗口百分比
5. **工作目录** - 当前工作目录

## 具体技术实现

### 测试实现

```rust
// tests.rs:10637-10665
#[tokio::test]
async fn status_line_model_with_reasoning_fast_footer_snapshot() {
    use ratatui::Terminal;
    use ratatui::backend::TestBackend;

    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(Some("gpt-5.4")).await;
    chat.show_welcome_banner = false;
    chat.config.cwd = PathBuf::from("/tmp/project");
    // 配置多个状态栏项目
    chat.config.tui_status_line = Some(vec![
        "model-with-reasoning".to_string(),
        "context-remaining".to_string(),
        "current-dir".to_string(),
    ]);
    chat.set_reasoning_effort(Some(ReasoningEffortConfig::XHigh));
    chat.set_service_tier(Some(ServiceTier::Fast));
    set_chatgpt_auth(&mut chat); // 需要 ChatGPT 认证才显示 Fast
    chat.refresh_status_line();

    let width = 80;
    let height = chat.desired_height(width);
    let mut terminal = Terminal::new(TestBackend::new(width, height)).expect("create terminal");
    terminal
        .draw(|f| chat.render(f.area(), f.buffer_mut()))
        .expect("draw model-with-reasoning footer");
    assert_snapshot!("status_line_model_with_reasoning_fast_footer", terminal.backend());
}
```

### 状态栏项目格式化

```rust
fn refresh_status_line(&mut self) {
    let mut parts = Vec::new();
    
    for item in self.config.tui_status_line.as_deref().unwrap_or_default() {
        match item.as_str() {
            "model-with-reasoning" => {
                let mut part = String::new();
                // 模型名称
                part.push_str(&self.current_model);
                // 推理级别
                if let Some(effort) = self.current_reasoning_effort() {
                    part.push_str(&format!(" {effort:?}").to_lowercase());
                }
                // Fast 模式（仅 gpt-5.4 显示）
                if self.current_model.starts_with("gpt-5.4") 
                    && self.service_tier == Some(ServiceTier::Fast) {
                    part.push_str(" fast");
                }
                parts.push(part);
            }
            "context-remaining" => {
                let percent = self.context_remaining_percent();
                parts.push(format!("{percent}% left"));
            }
            "current-dir" => {
                parts.push(format_directory_display(&self.config.cwd));
            }
            // ...
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
"  gpt-5.4 xhigh fast · 100% left · /tmp/project                                 "
```

**解析**：
- `gpt-5.4` - 当前模型
- `xhigh` - 推理级别（XHigh）
- `fast` - Fast 模式已启用
- `100% left` - 上下文余量 100%
- `/tmp/project` - 当前工作目录
- `·` - 分隔符

## 关键代码路径与文件引用

| 文件 | 行号范围 | 描述 |
|------|----------|------|
| `codex-rs/tui/src/chatwidget/tests.rs` | 10637-10665 | 组合状态栏测试 |
| `codex-rs/tui/src/chatwidget/tests.rs` | 10609-10635 | 模型+推理+Fast 逻辑测试 |
| `codex-rs/tui/src/chatwidget/mod.rs` | - | 状态栏刷新实现 |
| `codex-rs/tui/src/status.rs` | - | 状态格式化工具 |

## 依赖与外部交互

### ReasoningEffortConfig

```rust
codex_protocol::protocol::ReasoningEffortConfig {
    Low,    // 快速响应
    Medium, // 平衡
    High,   // 深度思考
    XHigh,  // 最大推理（仅特定模型）
}
```

### 模型特定行为

```rust
// Fast 状态仅对 gpt-5.4 系列模型显示
let show_fast = self.current_model.starts_with("gpt-5.4") 
    && self.service_tier == Some(ServiceTier::Fast);

// gpt-5.3-codex 即使启用 Fast 也不显示
// 测试验证: "gpt-5.3-codex xhigh · 100% left · /tmp/project" (无 fast)
```

## 风险、边界与改进建议

### 特定风险

1. **信息过载** - 过多状态项目导致状态栏拥挤
2. **模型差异** - 不同模型支持的功能不同，状态显示需适配
3. **宽度适配** - 长目录名或模型名可能导致截断

### 边界情况

1. **空配置** - `tui_status_line = None` 时的默认行为
2. **无效项目** - 配置中包含不支持的状态项目名
3. **长路径** - 深层目录路径的截断和显示

### 改进建议

1. **动态优先级** - 空间不足时自动隐藏低优先级项目
2. **缩写规则** - 长路径显示为 `.../project` 或 `~/project`
3. **颜色编码** - 上下文低于 20% 时变红警告
4. **自定义格式** - 支持用户自定义状态栏格式字符串
5. **多行状态栏** - 极宽终端支持双行状态显示

### 相关测试

- `status_line_fast_mode_footer` - 单独的 Fast 模式状态栏
- `stream_recovery_restores_previous_status_header` - 状态恢复测试
