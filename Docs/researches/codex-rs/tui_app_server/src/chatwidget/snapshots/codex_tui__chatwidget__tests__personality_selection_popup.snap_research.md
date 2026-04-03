# Personality Selection Popup Snapshot Research

## 场景与职责

该 snapshot 测试验证个性（Personality）选择弹出框的渲染效果。Codex 支持不同的沟通风格个性，允许用户根据自己的偏好选择 AI 的交互方式。

**测试场景**：
- 用户执行 `/personality` 命令
- 系统展示可用的个性选项
- 当前选中的个性被高亮标记

## 功能点目的

1. **个性化体验**：让用户选择符合自己工作风格的 AI 沟通方式
2. **上下文适应**：不同场景（探索性编码 vs 快速修复）适合不同个性
3. **用户偏好持久化**：记住用户的选择并在后续会话中使用

## 具体技术实现

### 测试代码路径
**文件**：`codex-rs/tui_app_server/src/chatwidget/tests.rs` (约第 8341-8348 行)

```rust
#[tokio::test]
async fn personality_selection_popup_snapshot() {
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(Some("gpt-5.2-codex")).await;
    chat.thread_id = Some(ThreadId::new());
    chat.open_personality_popup();  // 打开个性选择弹出框

    let popup = render_bottom_popup(&chat, 80);
    assert_snapshot!("personality_selection_popup", popup);
}
```

### 核心实现代码
**文件**：`codex-rs/tui_app_server/src/chatwidget.rs` (约第 7344-7414 行)

```rust
pub(crate) fn open_personality_popup(&mut self) {
    if !self.is_session_configured() {
        self.add_info_message(
            "Personality selection is disabled until startup completes.".to_string(),
            /*hint*/ None,
        );
        return;
    }
    if !self.current_model_supports_personality() {
        let current_model = self.current_model();
        self.add_error_message(format!(
            "Current model ({current_model}) doesn't support personalities. \
             Try /model to pick a different model."
        ));
        return;
    }
    self.open_personality_popup_for_current_model();
}

fn open_personality_popup_for_current_model(&mut self) {
    let current_personality = self.config.personality.unwrap_or(Personality::Friendly);
    let personalities = [Personality::Friendly, Personality::Pragmatic];
    let supports_personality = self.current_model_supports_personality();

    let items: Vec<SelectionItem> = personalities
        .into_iter()
        .map(|personality| {
            let name = Self::personality_label(personality).to_string();
            let description = Some(Self::personality_description(personality).to_string());
            let actions: Vec<SelectionAction> = vec![Box::new(move |tx| {
                tx.send(AppEvent::CodexOp(
                    AppCommand::override_turn_context(
                        /*cwd*/ None,
                        /*approval_policy*/ None,
                        /*approvals_reviewer*/ None,
                        /*sandbox_policy*/ None,
                        /*windows_sandbox_level*/ None,
                        /*model*/ None,
                        /*effort*/ None,
                        /*summary*/ None,
                        /*service_tier*/ None,
                        /*collaboration_mode*/ None,
                        Some(personality),  // 只更新 personality
                    )
                    .into_core(),
                ));
                tx.send(AppEvent::UpdatePersonality(personality));
                tx.send(AppEvent::PersistPersonalitySelection { personality });
            })];
            SelectionItem {
                name,
                description,
                is_current: current_personality == personality,
                is_disabled: !supports_personality,
                actions,
                dismiss_on_select: true,
                ..Default::default()
            }
        })
        .collect();

    let mut header = ColumnRenderable::new();
    header.push(Line::from("Select Personality".bold()));
    header.push(Line::from("Choose a communication style for Codex.".dim()));

    self.bottom_pane.show_selection_view(SelectionViewParams {
        header: Box::new(header),
        footer_hint: Some(standard_popup_hint_line()),
        items,
        ..Default::default()
    });
}
```

### 个性定义
```rust
pub enum Personality {
    Friendly,   // 友好、协作、乐于助人
    Pragmatic,  // 简洁、任务导向、直接
}

fn personality_label(personality: Personality) -> &'static str {
    match personality {
        Personality::Friendly => "Friendly",
        Personality::Pragmatic => "Pragmatic",
    }
}

fn personality_description(personality: Personality) -> &'static str {
    match personality {
        Personality::Friendly => "Warm, collaborative, and helpful.",
        Personality::Pragmatic => "Concise, task-focused, and direct.",
    }
}
```

### Snapshot 内容
```
  Select Personality
  Choose a communication style for Codex.

  1. Friendly             Warm, collaborative, and helpful.
› 2. Pragmatic (current)  Concise, task-focused, and direct.

  Press enter to confirm or esc to go back
```

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/chatwidget.rs:7344-7360` | `open_personality_popup()` - 入口函数 |
| `codex-rs/tui_app_server/src/chatwidget.rs:7362-7414` | `open_personality_popup_for_current_model()` - 主逻辑 |
| `codex-rs/tui_app_server/src/chatwidget.rs:7370-7391` | 个性选项构建和事件处理 |
| `codex-rs/tui_app_server/src/chatwidget/tests.rs:8341-8348` | 测试用例实现 |
| `codex-rs/core/src/config.rs` | `Personality` 枚举定义 |

### 模型支持检测
```rust
fn current_model_supports_personality(&self) -> bool {
    // 检查当前模型是否支持个性功能
    // 某些旧版模型可能不支持
    self.model_capabilities()
        .map(|c| c.supports_personality)
        .unwrap_or(false)
}
```

## 依赖与外部交互

### 依赖模块
1. **Personality 枚举**：定义支持的个性类型
2. **ModelCapabilities**：检测当前模型是否支持个性
3. **OverrideTurnContext**：更新会话上下文的个性设置
4. **Config 持久化**：保存用户选择到配置文件

### 事件流
```
用户执行 /personality 命令
    ↓
检查会话是否已配置
    ↓
检查当前模型是否支持个性
    ↓
获取当前个性设置（默认 Friendly）
    ↓
构建个性选项列表
    ↓
渲染 SelectionView
    ↓
用户选择新个性
    ↓
发送多个事件：
  - CodexOp::OverrideTurnContext（更新当前会话）
  - UpdatePersonality（更新 UI 状态）
  - PersistPersonalitySelection（持久化配置）
```

### 与模型能力的集成
- 不是所有模型都支持个性功能
- 通过 `ModelCapabilities.supports_personality` 检测
- 不支持的模型会显示错误消息并建议切换模型

## 风险、边界与改进建议

### 潜在风险
1. **个性效果不明显**：用户可能难以感知不同个性之间的差异
2. **模型支持不一致**：个性效果可能因模型而异
3. **过度简化**：两种个性可能不足以覆盖所有用户需求

### 边界情况
1. **模型切换**：切换到一个不支持个性的模型时的处理
2. **会话恢复**：恢复会话时个性设置的正确应用
3. **实时更改**：个性更改对已发送消息的影响

### 改进建议
1. **更多个性选项**：
   - "Teacher"：解释型，适合学习场景
   - "Expert"：深入技术细节，适合复杂任务
   - "Creative"：探索性思维，适合头脑风暴

2. **个性预览**：提供示例对话展示不同个性的差异

3. **场景推荐**：根据当前任务类型推荐合适的个性

4. **自定义个性**：允许高级用户定义自己的个性提示词

5. **个性组合**：允许混合多种个性特征

6. **效果反馈**：收集用户对个性效果的反馈用于改进

### 相关测试
- `model_selection_popup`：类似的模型选择 UI 测试
- `personality_selection_popup_snapshot`：本测试

### 配置持久化
个性选择通过 `AppEvent::PersistPersonalitySelection` 事件持久化到 `config.toml`：

```toml
[preferences]
personality = "pragmatic"  # 或 "friendly"
```

### UI 设计特点
1. **简洁标题**："Select Personality" 明确功能
2. **副标题说明**：解释这是沟通风格选择
3. **当前状态标记**：`(current)` 标签清晰指示当前设置
4. **描述性文本**：每个个性都有简短的行为描述
5. **一致的操作提示**：Enter 确认，Esc 返回
