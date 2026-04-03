# Rate Limit Switch Prompt Popup 研究文档

## 场景与职责

该 snapshot 测试验证当用户接近 API 速率限制时，TUI 应用服务器会显示一个提示弹出框，建议用户切换到更低成本的模型（gpt-5.1-codex-mini）以降低信用点消耗。这是 Codex CLI 的成本优化功能的一部分，旨在帮助用户在接近速率限制时做出明智的模型选择。

**测试文件**: `codex-rs/tui_app_server/src/chatwidget/tests.rs`  
**Snapshot 文件**: `codex_tui_app_server__chatwidget__tests__rate_limit_switch_prompt_popup.snap`

## 功能点目的

1. **成本优化提示**: 当用户的 API 使用量接近速率限制阈值（92%）时，系统主动提示用户切换到更便宜的模型
2. **模型切换选项**: 提供三个选项：
   - 切换到 gpt-5.1-codex-mini（优化版，更便宜更快但能力稍弱）
   - 保持当前模型
   - 保持当前模型且不再显示此类提醒
3. **用户控制**: 用户可以通过 Enter 确认或 Esc 返回，保持对模型选择的完全控制

## 具体技术实现

### 核心状态机
```rust
#[derive(Default)]
enum RateLimitSwitchPromptState {
    #[default]
    Idle,      // 空闲状态
    Pending,   // 待显示状态
    Shown,     // 已显示状态
}
```

### 触发逻辑
1. 当 `on_rate_limit_snapshot()` 检测到使用率 ≥ 90% 且当前模型不是 nudge 模型时，设置状态为 `Pending`
2. 在 `finalize_turn()` 结束时调用 `maybe_show_pending_rate_limit_prompt()`
3. 如果用户未禁用此提示，则打开模型切换弹出框

### 弹出框构建
```rust
fn open_rate_limit_switch_prompt(&mut self, preset: ModelPreset) {
    let switch_actions: Vec<SelectionAction> = vec![
        // 1. 切换到低成本模型
        Box::new(move |tx| { tx.send(AppEvent::SwitchModelAndReasoningEffort {...}) }),
        // 2. 保持当前模型
        Box::new(|tx| { tx.send(AppEvent::ClosePopup) }),
        // 3. 保持当前模型且不再提醒
        Box::new(|tx| { tx.send(AppEvent::SetRateLimitSwitchPromptHidden(true)) }),
    ];
    // 使用 SelectionList 渲染弹出框
}
```

### 测试用例实现
```rust
#[tokio::test]
async fn rate_limit_switch_prompt_popup_snapshot() {
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(Some("gpt-5")).await;
    chat.has_chatgpt_account = true;
    
    // 模拟 92% 的速率限制使用率
    chat.on_rate_limit_snapshot(Some(snapshot(92.0)));
    chat.maybe_show_pending_rate_limit_prompt();
    
    let popup = render_bottom_popup(&chat, 80);
    assert_snapshot!("rate_limit_switch_prompt_popup", popup);
}
```

## 关键代码路径与文件引用

| 文件路径 | 相关代码/函数 | 说明 |
|---------|-------------|------|
| `codex-rs/tui_app_server/src/chatwidget.rs` | `RateLimitSwitchPromptState` (L534) | 状态机定义 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | `maybe_show_pending_rate_limit_prompt()` (L7223) | 显示判断逻辑 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | `open_rate_limit_switch_prompt()` (L7242) | 弹出框构建 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | `on_rate_limit_snapshot()` (L2394) | 速率限制事件处理 |
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | `rate_limit_switch_prompt_popup_snapshot()` (L2458) | 测试函数 |
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | `render_bottom_popup()` (L7303) | 测试辅助函数 |

## 依赖与外部交互

### 依赖模块
- `codex_protocol::protocol::RateLimitSnapshot`: 速率限制快照数据结构
- `codex_core::config::Config`: 配置管理，包含 `notices.hide_rate_limit_model_nudge`
- `crate::bottom_pane`: 底部面板，负责实际渲染弹出框
- `crate::selection_list`: 选择列表组件

### 外部事件
- `AppEvent::SwitchModelAndReasoningEffort`: 切换模型事件
- `AppEvent::SetRateLimitSwitchPromptHidden`: 禁用提示事件
- `AppEvent::ClosePopup`: 关闭弹出框事件

### 配置项
```toml
[notices]
hide_rate_limit_model_nudge = false  # 控制是否显示速率限制切换提示
```

## 风险、边界与改进建议

### 潜在风险
1. **频繁打扰**: 如果阈值设置过低（90%），可能在短时间内多次触发，影响用户体验
2. **模型降级意外**: 用户可能误操作切换到能力较弱的模型，导致输出质量下降
3. **状态同步问题**: `Pending` 和 `Shown` 状态需要在正确的生命周期阶段转换，否则可能导致提示不显示或重复显示

### 边界情况
1. **无可用低成本模型**: `lower_cost_preset()` 返回 None 时，提示不会显示
2. **用户已禁用**: `rate_limit_switch_prompt_hidden()` 返回 true 时跳过
3. **已是目标模型**: 当前模型已是 gpt-5.1-codex-mini 时不提示
4. **无 ChatGPT 账号**: `has_chatgpt_account` 为 false 时的处理

### 改进建议
1. **智能阈值**: 考虑根据用户的历史使用模式动态调整触发阈值
2. **成本估算**: 在提示中显示切换后可节省的预估信用点数
3. **记住选择**: 增加"24小时内不再提醒"的临时禁用选项
4. **A/B 测试**: 测试不同的提示文案对模型切换率的影响
5. **可访问性**: 确保屏幕阅读器能正确朗读提示内容

### 相关测试覆盖
- 正常触发场景（使用率 92%）
- 用户禁用后的行为
- 已是低成本模型时的行为
- 状态转换的正确性
