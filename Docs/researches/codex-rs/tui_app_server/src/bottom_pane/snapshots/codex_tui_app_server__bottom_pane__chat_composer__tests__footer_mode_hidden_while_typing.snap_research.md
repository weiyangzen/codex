# 文件研究: footer_mode_hidden_while_typing.snap

## 场景与职责
该快照测试验证当用户正在输入内容时，footer 的提示信息被隐藏，改为显示上下文信息（如 "100% context left"）的场景。测试展示了编辑器从空状态变为有内容状态时，footer 从显示操作提示切换到显示上下文使用情况的智能行为。

## 功能点目的
1. **减少视觉干扰**: 当用户专注于输入时，隐藏操作提示以减少干扰
2. **提供有用信息**: 在隐藏提示的同时，显示有用的上下文使用信息
3. **状态感知**: 根据编辑器内容状态自动调整 footer 显示内容
4. **保持界面简洁**: 避免 footer 区域信息过载

## 具体技术实现

### 关键流程
1. 编辑器初始为空，`footer_mode` 为 `ComposerEmpty`
2. 用户输入字符 "h"，`handle_input_basic` 被调用
3. `reset_mode_after_activity` 被调用，根据当前模式决定新模式
4. 由于当前是 `ComposerEmpty`，切换到 `ComposerHasDraft`
5. `footer_props` 方法构建 footer 属性
6. 渲染时，`context_window_line` 生成 "100% context left" 文本
7. 右侧对齐显示上下文使用百分比

### 数据结构
```rust
// reset_mode_after_activity 函数
pub(crate) fn reset_mode_after_activity(current: FooterMode) -> FooterMode {
    match current {
        FooterMode::EscHint
        | FooterMode::ShortcutOverlay
        | FooterMode::QuitShortcutReminder
        | FooterMode::ComposerHasDraft => FooterMode::ComposerEmpty,
        other => other,
    }
}

// context_window_line 函数生成上下文信息
pub(crate) fn context_window_line(percent: Option<i64>, used_tokens: Option<i64>) -> Line<'static> {
    if let Some(percent) = percent {
        let percent = percent.clamp(0, 100);
        return Line::from(vec![Span::from(format!("{percent}% context left")).dim()]);
    }

    if let Some(tokens) = used_tokens {
        let used_fmt = format_tokens_compact(tokens);
        return Line::from(vec![Span::from(format!("{used_fmt} used")).dim()]);
    }

    Line::from(vec![Span::from("100% context left").dim()])
}

// ChatComposer 中的相关字段
pub(crate) struct ChatComposer {
    context_window_percent: Option<i64>,
    context_window_used_tokens: Option<i64>,
    // ...
}
```

### 协议/命令
- **活动检测**: 任何输入操作触发 `reset_mode_after_activity`
- **上下文百分比**: `context_window_percent` 表示剩余上下文百分比
- **令牌计数**: `context_window_used_tokens` 表示已使用的令牌数
- **右对齐渲染**: `render_context_right` 将上下文信息右对齐显示

## 关键代码路径与文件引用
- **源文件**: `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs`
  - `handle_input_basic` 方法 (行 2988-2996)
  - `reset_mode_after_activity` 调用 (相关代码)
  - `context_window_percent` 字段 (行 391)
  - `context_window_used_tokens` 字段 (行 395)
- **Footer 模块**: `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
  - `reset_mode_after_activity` 函数 (行 177-185)
  - `context_window_line` 函数 (行 848-860)
  - `render_context_right` 函数 (行 529-554)
  - `FooterMode::ComposerHasDraft` 枚举 (行 141-145)
- **相关测试**: `footer_mode_hidden_while_typing`
- **调用链**: 
  - 字符输入 → handle_input_basic → reset_mode_after_activity → ComposerHasDraft → 显示上下文信息

## 依赖与外部交互
1. **输入处理**: 依赖 `handle_input_basic` 检测用户输入活动
2. **上下文监控**: 需要外部系统提供上下文使用数据
3. **渲染布局**: `single_line_footer_layout` 处理左右两侧内容的布局
4. **状态同步**: 编辑器内容变化与 footer 模式需要同步

## 风险、边界与改进建议

### 风险点
1. **频繁切换**: 用户快速输入删除可能导致 footer 频繁切换，造成视觉闪烁
2. **信息丢失**: 隐藏的提示信息可能被用户错过
3. **上下文数据延迟**: 如果上下文数据更新有延迟，显示的信息可能不准确

### 边界条件
1. **空内容边缘**: 当用户删除所有内容时，应正确回到空状态模式
2. **大内容粘贴**: 粘贴大量内容时，上下文百分比应正确更新
3. **零上下文**: 当上下文使用达到 100% 时的显示处理

### 改进建议
1. **延迟隐藏**: 添加短暂延迟后再隐藏提示，确保用户有机会看到
2. **动画过渡**: 使用淡入淡出效果平滑切换 footer 内容
3. **优先级显示**: 对于重要提示，即使正在输入也以简化形式显示
4. **上下文警告**: 当上下文使用接近阈值时，改变颜色或添加警告图标
5. **用户控制**: 允许用户配置是否在输入时隐藏提示
6. **智能预测**: 根据输入内容预测可能的操作，显示相关提示
7. **多行支持**: 在垂直空间允许时，同时显示提示和上下文信息
