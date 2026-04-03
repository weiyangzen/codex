# Snapshot Research: rate_limit_switch_prompt_popup

## 场景与职责

此快照测试验证当用户接近 API 费率限制时显示的模型切换建议弹出框。当用户的 Codex API 使用率接近限制阈值（92%）时，系统会提示用户切换到更低成本的模型（gpt-5.1-codex-mini）以继续使用服务。

测试场景：
- 用户使用 gpt-5 模型
- 费率限制快照显示使用率达到 92%（接近限制）
- 系统触发费率限制切换提示
- 弹出框显示三个选项：切换到低成本模型、保持当前模型、保持当前模型且不再提示
- 使用 `render_bottom_popup` 捕获弹出框渲染输出

## 功能点目的

1. **成本优化建议**：在接近费率限制时建议更经济的模型选项
2. **服务连续性**：帮助用户避免因达到限制而无法使用服务
3. **用户选择**：提供明确的选项让用户自主决定
4. **智能提示**：仅在特定条件下显示（ChatGPT 账户、特定限制类型）

## 具体技术实现

### 关键流程

1. **费率限制检测流程**：
   ```
   RateLimitSnapshot (92% used) → on_rate_limit_snapshot()
   ↓
   检查条件（has_chatgpt_account, limit_id == "codex"）
   ↓
   rate_limit_switch_prompt = Pending
   ↓
   maybe_show_pending_rate_limit_prompt() → 显示弹出框
   ```

2. **弹出框渲染**：
   - 使用 `render_bottom_popup(&chat, 80)` 捕获宽度为 80 的弹出框
   - 通过 `insta::assert_snapshot` 进行快照比对

### 数据结构

```rust
pub struct RateLimitSnapshot {
    pub limit_id: Option<String>,
    pub limit_name: Option<String>,
    pub primary: Option<RateLimitWindow>,
    pub secondary: Option<RateLimitWindow>,
    pub credits: Option<CreditsSnapshot>,
    pub plan_type: Option<PlanType>,
}

pub struct RateLimitWindow {
    pub used_percent: f64,
    pub window_minutes: Option<u32>,
    pub resets_at: Option<i64>,
}

enum RateLimitSwitchPromptState {
    Idle,
    Pending,  // 等待显示
    Shown,    // 已显示
}
```

### 选项定义

- **选项 1 (Switch)**：切换到 gpt-5.1-codex-mini
  - 描述："Optimized for codex. Cheaper, faster, but less capable."
  - 动作：切换模型并关闭提示

- **选项 2 (Keep)**：保持当前模型
  - 动作：关闭提示，继续使用当前模型

- **选项 3 (Keep & Hide)**：保持当前模型且不再提示
  - 描述："Hide future rate limit reminders about switching models."
  - 动作：设置 `rate_limit_switch_prompt_hidden = true`

## 关键代码路径与文件引用

### 核心文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/chatwidget/tests.rs` | 测试定义（tui，line ~2447） |
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | 测试定义（tui_app_server，line ~2458） |
| `codex-rs/tui/src/chatwidget.rs` | `on_rate_limit_snapshot()` 和 `open_rate_limit_switch_prompt()` 实现 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | 同上 |

### 关键函数

- `ChatWidget::on_rate_limit_snapshot()` - 处理费率限制快照
- `ChatWidget::maybe_show_pending_rate_limit_prompt()` - 检查并显示待处理的提示
- `ChatWidget::open_rate_limit_switch_prompt()` - 打开模型切换提示弹出框
- `ChatWidget::lower_cost_preset()` - 获取低成本模型预设

### 实现细节

```rust
// codex-rs/tui_app_server/src/chatwidget.rs
pub(crate) fn on_rate_limit_snapshot(&mut self, snapshot: Option<RateLimitSnapshot>) {
    if let Some(mut snapshot) = snapshot {
        let limit_id = snapshot.limit_id.clone()
            .unwrap_or_else(|| "codex".to_string());
        // ... 处理逻辑
        
        // 触发提示条件检查
        if self.should_show_rate_limit_prompt(&snapshot) {
            self.rate_limit_switch_prompt = RateLimitSwitchPromptState::Pending;
        }
    }
}

fn maybe_show_pending_rate_limit_prompt(&mut self) {
    if self.rate_limit_switch_prompt_hidden() {
        self.rate_limit_switch_prompt = RateLimitSwitchPromptState::Idle;
        return;
    }
    if !matches!(self.rate_limit_switch_prompt, RateLimitSwitchPromptState::Pending) {
        return;
    }
    if let Some(preset) = self.lower_cost_preset() {
        self.open_rate_limit_switch_prompt(preset);
        self.rate_limit_switch_prompt = RateLimitSwitchPromptState::Shown;
    }
}
```

## 依赖与外部交互

### 内部依赖

- `RateLimitSnapshot`, `RateLimitWindow` - 费率限制数据结构
- `ModelPreset` - 模型预设
- `SelectionItem` - 弹出框选项

### 外部交互

- **App 层**：`app.rs` 调用 `on_rate_limit_snapshot()` 传递费率限制信息
- **配置存储**：保存用户的"不再提示"偏好
- **模型管理**：获取可用的低成本模型预设

## 风险、边界与改进建议

### 潜在风险

1. **提示频率**：过于频繁的提示可能导致用户疲劳
2. **模型可用性**：建议的低成本模型可能不可用
3. **条件判断复杂**：多个条件（账户类型、限制类型、使用率）需要同时满足

### 边界情况

- 非 ChatGPT 账户用户不会看到提示
- 非 "codex" 类型的限制不会触发提示
- 用户选择"不再提示"后的持久化
- 任务进行中时提示的延迟显示

### 改进建议

1. **智能提示策略**：
   - 根据用户历史选择动态调整提示频率
   - 添加提示冷却期，避免短时间内重复提示
   - 考虑用户的使用模式（如连续使用时间）

2. **UI/UX 改进**：
   - 显示当前使用率和限制重置时间
   - 添加模型能力对比信息
   - 提供一键切换并记住选择的选项

3. **测试覆盖**：
   - 添加非 ChatGPT 账户的负向测试
   - 测试"不再提示"偏好的持久化
   - 测试任务进行中时提示的延迟行为

---

**快照内容**：
```
  Approaching rate limits
  Switch to gpt-5.1-codex-mini for lower credit usage?

› 1. Switch to gpt-5.1-codex-mini           Optimized for codex. Cheaper,
                                            faster, but less capable.
  2. Keep current model
  3. Keep current model (never show again)  Hide future rate limit reminders
                                            about switching models.

  Press enter to confirm or esc to go back
```

**说明**：显示费率限制切换提示弹出框。标题提示接近费率限制，副标题建议切换到 gpt-5.1-codex-mini。三个选项分别对应：切换到低成本模型（带描述）、保持当前模型、保持当前模型且不再显示此类提示。选项 1 被默认选中。
