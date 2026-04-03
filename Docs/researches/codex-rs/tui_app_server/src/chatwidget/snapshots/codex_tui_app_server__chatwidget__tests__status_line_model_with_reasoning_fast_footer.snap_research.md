# Status Line Model With Reasoning Fast Footer 研究文档

## 场景与职责

该 snapshot 测试验证当状态栏配置为显示多个项目（模型+推理、上下文剩余、当前目录）且启用 Fast 模式时，页脚的渲染效果。这是状态栏复杂配置的综合测试，确保多项组合时的正确渲染和分隔符使用。

**测试文件**: `codex-rs/tui_app_server/src/chatwidget/tests.rs`  
**Snapshot 文件**: `codex_tui_app_server__chatwidget__tests__status_line_model_with_reasoning_fast_footer.snap`

## 功能点目的

1. **复合状态显示**: 同时显示模型信息、推理努力级别、Fast 模式状态和上下文使用情况
2. **分隔符验证**: 验证多项之间的 "·" 分隔符正确渲染
3. **信息密度**: 在有限空间内展示丰富的会话状态信息
4. **配置组合**: 验证多种状态项组合的渲染效果

## 具体技术实现

### 状态栏配置
```rust
chat.config.tui_status_line = Some(vec![
    "model-with-reasoning".to_string(),  // 模型名称 + 推理级别 + Fast 状态
    "context-remaining".to_string(),      // 上下文剩余百分比
    "current-dir".to_string(),            // 当前工作目录
]);
```

### 模型带推理项值计算
```rust
StatusLineItem::ModelWithReasoning => {
    let label = Self::status_line_reasoning_effort_label(
        self.effective_reasoning_effort()
    );
    
    // 仅对 gpt-5.4 显示 fast 标签
    let fast_label = if self.should_show_fast_status(
        self.current_model(), 
        self.config.service_tier
    ) {
        " fast"
    } else {
        ""
    };
    
    Some(format!("{} {label}{fast_label}", self.model_display_name()))
}
```

### Fast 状态显示条件
```rust
fn should_show_fast_status(&self, model: &str, tier: Option<ServiceTier>) -> bool {
    // 仅对 gpt-5.4 系列模型显示 fast 标签
    model.starts_with("gpt-5.4") && matches!(tier, Some(ServiceTier::Fast))
}
```

### 推理努力级别标签
```rust
fn status_line_reasoning_effort_label(effort: Option<ReasoningEffortConfig>) -> &'static str {
    match effort {
        Some(ReasoningEffortConfig::Minimal) => "minimal",
        Some(ReasoningEffortConfig::Low) => "low",
        Some(ReasoningEffortConfig::Medium) => "medium",
        Some(ReasoningEffortConfig::High) => "high",
        Some(ReasoningEffortConfig::XHigh) => "xhigh",
        None | Some(ReasoningEffortConfig::None) => "default",
    }
}
```

### 测试用例实现
```rust
#[tokio::test]
async fn status_line_model_with_reasoning_fast_footer_snapshot() {
    use ratatui::Terminal;
    use ratatui::backend::TestBackend;
    
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(Some("gpt-5.4")).await;
    chat.show_welcome_banner = false;
    chat.config.cwd = PathBuf::from("/tmp/project");
    
    // 配置复合状态栏
    chat.config.tui_status_line = Some(vec![
        "model-with-reasoning".to_string(),
        "context-remaining".to_string(),
        "current-dir".to_string(),
    ]);
    
    // 设置推理级别为 XHigh
    chat.set_reasoning_effort(Some(ReasoningEffortConfig::XHigh));
    // 启用 Fast 模式
    chat.set_service_tier(Some(ServiceTier::Fast));
    // 设置认证（影响某些状态项的显示）
    set_chatgpt_auth(&mut chat);
    
    chat.refresh_status_line();
    
    // 渲染测试
    let width = 80;
    let height = chat.desired_height(width);
    let mut terminal = Terminal::new(TestBackend::new(width, height)).expect("create terminal");
    terminal
        .draw(|f| chat.render(f.area(), f.buffer_mut()))
        .expect("draw model-with-reasoning footer");
    assert_snapshot!("status_line_model_with_reasoning_fast_footer", terminal.backend());
}
```

## 关键代码路径与文件引用

| 文件路径 | 相关代码/函数 | 说明 |
|---------|-------------|------|
| `codex-rs/tui_app_server/src/chatwidget.rs` | `status_line_value_for_item()` (L6956) | 状态项值计算 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | `StatusLineItem::ModelWithReasoning` (L6959) | 模型+推理项 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | `should_show_fast_status()` | Fast 显示条件 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | `status_line_reasoning_effort_label()` (L7085) | 推理级别标签 |
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | `status_line_model_with_reasoning_fast_footer_snapshot()` (L11370) | 测试函数 |

## 依赖与外部交互

### 依赖模块
- `codex_protocol::config_types::ReasoningEffortConfig`: 推理努力配置
- `codex_protocol::config_types::ServiceTier`: 服务层级
- `codex_core::config::Config`: 核心配置

### 推理努力级别
```rust
pub enum ReasoningEffortConfig {
    None,
    Minimal,
    Low,
    Medium,
    High,
    XHigh,
}
```

### 状态项值示例
| 配置 | 模型 | 推理 | Fast | 输出示例 |
|------|------|------|------|----------|
| model-with-reasoning | gpt-5.4 | XHigh | on | "gpt-5.4 xhigh fast" |
| model-with-reasoning | gpt-5.4 | XHigh | off | "gpt-5.4 xhigh" |
| model-with-reasoning | gpt-5.3 | XHigh | on | "gpt-5.3-codex xhigh" |
| context-remaining | - | - | - | "100% left" |
| current-dir | - | - | - | "/tmp/project" |

### 完整状态栏格式
```
gpt-5.4 xhigh fast · 100% left · /tmp/project
└──────────────┘   └─────────┘   └──────────┘
   模型+推理        上下文剩余      当前目录
```

## 风险、边界与改进建议

### 潜在风险
1. **空间不足**: 多项组合时可能超出终端宽度，导致截断
2. **信息过载**: 过多信息可能让用户难以快速获取关键信息
3. **模型名称长度**: 不同模型名称长度差异大，影响布局一致性

### 边界情况
1. **长路径**: 当前目录路径过长时的截断处理
2. **低上下文**: 上下文剩余百分比为 0 时的显示
3. **未知模型**: 使用未识别模型时的回退显示
4. **未认证状态**: 某些项在匿名状态下的不同行为

### 改进建议
1. **优先级截断**: 当空间不足时，优先截断低优先级项（如目录）
2. **缩写支持**: 对常用路径使用缩写（如 `~` 代替 `/home/user`）
3. **颜色区分**: 使用不同颜色区分不同类型的信息
4. **动态隐藏**: 根据终端宽度动态隐藏次要项
5. **悬停提示**: 截断的内容在悬停时显示完整信息
6. **自定义格式**: 允许用户使用模板字符串自定义格式

### 相关测试覆盖
- 模型带推理 Fast 模式测试（本测试）
- 模型带推理非 Fast 模式测试
- Fast 模式单独显示测试
- 状态栏配置验证测试

### Snapshot 内容分析
```
"                                                                                "
"                                                                                "
"› Ask Codex to do anything                                                      "
"                                                                                "
"  gpt-5.4 xhigh fast · 100% left · /tmp/project                                 "
```

**关键观察点**:
1. **复合信息**: 第5行显示完整的状态栏信息
2. **分隔符**: 使用 "·"（中间点）作为分隔符，视觉上清晰
3. **信息完整**: 包含模型、推理级别、Fast 状态、上下文、目录
4. **格式一致**: 各部分格式统一，易于阅读
5. **空间利用**: 在 80 列宽度下仍有充足余量

这表明状态栏能够优雅地处理多项组合，保持信息的可读性和布局的整洁。
