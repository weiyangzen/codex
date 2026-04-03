# Footer Status Line Generic Research Template

## 场景与职责

该文档是底部栏状态行的通用研究模板，适用于以下快照文件：
- `footer_active_agent_label.snap`
- `footer_composer_has_draft_queue_hint_enabled.snap`
- `footer_context_tokens_used.snap`
- `footer_ctrl_c_quit_idle.snap`
- `footer_ctrl_c_quit_running.snap`
- `footer_esc_hint_idle.snap`
- `footer_esc_hint_primed.snap`
- `footer_mode_indicator_narrow_overlap_hides.snap`
- `footer_mode_indicator_running_hides_hint.snap`
- `footer_mode_indicator_wide.snap`
- `footer_status_line_disabled_context_right.snap`
- `footer_status_line_enabled_mode_right.snap`
- `footer_status_line_enabled_no_mode_right.snap`
- `footer_status_line_overrides_context.snap`
- `footer_status_line_overrides_draft_idle.snap`
- `footer_status_line_overrides_shortcuts.snap`
- `footer_status_line_truncated_with_gap.snap`
- `footer_status_line_with_active_agent_label.snap`
- `footer_status_line_yields_to_queue_hint.snap`

### 业务场景
- 显示状态行信息（模型、Git 分支、上下文等）
- 根据终端宽度和状态调整显示
- 优先显示重要信息

### 状态行项目
| 项目 | 描述 |
|------|------|
| model-name | 当前模型名称 |
| git-branch | 当前 Git 分支 |
| current-dir | 当前工作目录 |
| context-remaining | 上下文窗口剩余百分比 |
| active-agent-label | 活动 Agent 标签 |

## 功能点目的

### 核心功能
1. **信息显示**：显示配置的状态行项目
2. **自适应布局**：根据宽度调整显示
3. **优先级管理**：优先显示重要信息

### 用户体验目标
- **信息丰富**：在有限空间内提供有用信息
- **视觉清晰**：不干扰主要界面
- **可配置性**：用户可以自定义显示内容

## 具体技术实现

### 关键数据结构
```rust
pub(crate) struct FooterProps {
    status_line_value: Option<Line<'static>>,
    status_line_enabled: bool,
    active_agent_label: Option<String>,
    // ...
}
```

### 关键代码路径
- **源文件**: `codex-rs/tui_app_server/src/bottom_pane/footer.rs`

## 依赖与外部交互

### 内部依赖
- `FooterProps` - 底部栏属性
- `passive_footer_status_line` - 被动状态行生成

### 外部交互
- **配置系统**：获取状态行配置
- **Git 集成**：获取当前分支
- **上下文管理器**：获取上下文使用情况

## 风险、边界与改进建议

### 潜在风险
1. **信息过载**：启用过多项目可能导致拥挤
2. **性能影响**：某些项目（如 Git）的获取可能影响性能

### 改进建议
1. **条件显示**：根据上下文条件显示项目
2. **颜色配置**：允许自定义项目颜色

### 相关文件引用
- 源文件: `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
