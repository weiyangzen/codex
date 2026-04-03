# footer_status_line_with_active_agent_label 测试研究文档

## 1. 场景与职责

该测试验证当状态行功能和 Agent Label 同时存在时，两者会合并显示在底部状态栏。这是 TUI 应用底部状态栏的多信息源组合显示场景。

**使用场景**：
- 用户启用了 `/statusline` 配置功能
- 当前有激活的 Agent（如 "Robie [explorer]"）
- 需要同时显示状态行内容和 Agent 标识
- 验证多信息源的合并显示逻辑

## 2. 功能点目的

**测试目标**：验证当 `status_line_enabled = true` 且有 `active_agent_label` 时，状态行内容和 Agent Label 会合并显示，中间用 " · " 分隔。

**预期行为**：
- 状态行内容 "Status line content" 显示在左侧
- Agent Label "Robie [explorer]" 显示在右侧
- 两者用 " · "（中间点）分隔
- 格式："Status line content · Robie [explorer]"

## 3. 具体技术实现

### 测试代码位置
`codex-rs/tui_app_server/src/bottom_pane/footer.rs` 行 1651-1666

### 关键测试逻辑
```rust
let props = FooterProps {
    mode: FooterMode::ComposerEmpty,
    esc_backtrack_hint: false,
    use_shift_enter_hint: false,
    is_task_running: false,
    collaboration_modes_enabled: false,
    is_wsl: false,
    quit_shortcut_key: key_hint::ctrl(KeyCode::Char('c')),
    context_window_percent: None,
    context_window_used_tokens: None,
    status_line_value: Some(Line::from("Status line content".to_string())),
    status_line_enabled: true,
    active_agent_label: Some("Robie [explorer]".to_string()),  // Agent Label
};

snapshot_footer("footer_status_line_with_active_agent_label", props);
```

### 合并逻辑
```rust
pub(crate) fn passive_footer_status_line(props: &FooterProps) -> Option<Line<'static>> {
    if !shows_passive_footer_line(props) {
        return None;
    }

    let mut line = if props.status_line_enabled {
        props.status_line_value.clone()
    } else {
        None
    };

    if let Some(active_agent_label) = props.active_agent_label.as_ref() {
        if let Some(existing) = line.as_mut() {
            // 状态行已存在，追加 Agent Label
            existing.spans.push(" · ".into());
            existing.spans.push(active_agent_label.clone().into());
        } else {
            // 只有 Agent Label，直接作为行内容
            line = Some(Line::from(active_agent_label.clone()));
        }
    }

    line
}
```

## 4. 关键代码路径与文件引用

### 核心文件
- `codex-rs/tui_app_server/src/bottom_pane/footer.rs` - 底部状态栏主实现
- `codex-rs/tui_app_server/src/bottom_pane/snapshots/codex_tui__bottom_pane__footer__tests__footer_status_line_with_active_agent_label.snap` - 预期快照

### 关键函数
- `passive_footer_status_line()` - 行 638-659，合并逻辑核心
- `shows_passive_footer_line()` - 行 665-673，判断是否显示被动状态行

### 分隔符定义
```rust
// 使用 " · "（空格 + 中间点 + 空格）作为分隔符
existing.spans.push(" · ".into());
```

## 5. 依赖与外部交互

### Agent 系统
- `active_agent_label` - 当前激活 Agent 的标识
- Agent 名称格式通常为 "Name [type]"，如 "Robie [explorer]"

### 状态行系统
- `status_line_value` - 状态行内容
- `status_line_enabled` - 状态行开关

### 组合优先级
1. 仅状态行 → 显示状态行
2. 仅 Agent Label → 显示 Agent Label
3. 两者都有 → 状态行 + " · " + Agent Label

## 6. 风险、边界与改进建议

### 潜在风险
1. **长内容截断**：状态行和 Agent Label 都很长时，合并后容易被截断
2. **分隔符识别**：用户可能不理解 " · " 的含义
3. **信息密度过高**：合并后信息过多，影响可读性

### 边界情况
1. **Agent Label 为空字符串**：当前测试未覆盖
2. **状态行为空但启用**：与仅 Agent Label 的场景重复
3. **超长合并内容**：合并后超过终端宽度的截断行为
4. **特殊字符**：Agent Label 包含特殊字符的处理

### 改进建议
1. **可配置分隔符**：允许用户自定义分隔符或选择不显示分隔符
2. **优先级配置**：允许用户选择显示顺序（Agent Label + 状态行 vs 状态行 + Agent Label）
3. **增加边界测试**：
   - `footer_agent_label_only` - 仅 Agent Label
   - `footer_agent_label_empty` - 空 Agent Label
   - `footer_combined_long_content` - 长内容合并截断
4. **样式区分**：为状态行和 Agent Label 应用不同样式，提高可读性
5. **交互式展开**：点击或 hover 时展开显示完整信息

### 可访问性改进
- 为屏幕阅读器提供结构化的信息读取顺序
- 考虑添加 ARIA 标签区分状态行和 Agent 信息

### 国际化考虑
- " · " 分隔符在不同语言环境下的适用性
- Agent Label 可能包含非 ASCII 字符，需要正确处理 Unicode 宽度
