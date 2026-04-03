# Footer Shortcuts Default Snapshot 研究文档

## 场景与职责

该快照文件是 `codex_tui_app_server` crate 中 `footer.rs` 模块的测试快照，用于验证**默认底部栏快捷键**的渲染。这是用户正常使用 Codex 时看到的底部栏状态。

### 业务场景
- 用户正常使用 Codex，没有特殊状态
- 底部栏显示默认的快捷键提示
- 提供常用操作的快速参考

### 默认底部栏特性
- 显示常用快捷键提示
- 右侧显示上下文信息
- 简洁的单行显示

## 功能点目的

### 核心功能
1. **快捷键提示**：显示常用操作的快捷键
2. **上下文信息**：显示模型、上下文使用情况等
3. **状态指示**：根据当前状态调整显示

### 用户体验目标
- **快速参考**：用户可以随时查看快捷键
- **信息丰富**：在有限空间内提供有用信息
- **不干扰**：不占用过多注意力

## 具体技术实现

### 关键数据结构
```rust
pub(crate) struct FooterProps {
    mode: FooterMode,
    context_window_percent: Option<i64>,
    // ...
}

pub(crate) enum FooterMode {
    ComposerEmpty,
    ComposerHasDraft,
    // ...
}
```

### 渲染逻辑
```rust
fn left_side_line(
    collaboration_mode_indicator: Option<CollaborationModeIndicator>,
    state: LeftSideState,
) -> Line<'static> {
    let mut line = Line::from("");
    
    // 快捷键提示
    match state.hint {
        SummaryHintKind::Shortcuts => {
            line.push_span(key_hint::plain(KeyCode::Char('?')));
            line.push_span(" for shortcuts".dim());
        }
        // ...
    };
    
    // 协作模式指示器
    if let Some(indicator) = collaboration_mode_indicator {
        line.push_span(indicator.styled_span(state.show_cycle_hint));
    }
    
    line
}
```

### 关键代码路径
- **源文件**: `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
- **测试函数**: `footer_shortcuts_default` (在 tests 模块中)

### 渲染输出分析
```
"  ? for shortcuts                                                                 100% context left"
```

- 左侧：`? for shortcuts` 提示
- 右侧：`100% context left` 上下文信息

## 依赖与外部交互

### 内部依赖
- `FooterProps` - 底部栏属性
- `left_side_line` - 左侧行生成

### 外部交互
- **上下文管理器**：获取上下文使用情况

## 风险、边界与改进建议

### 潜在风险
1. **空间不足**：终端宽度不足时内容被截断
2. **信息过时**：上下文信息可能不是实时的
3. **可发现性**：用户可能不知道 `?` 可以显示更多快捷键

### 边界情况
1. **窄终端**：宽度不足以显示完整内容
2. **无上下文信息**：无法获取上下文信息时的回退
3. **特殊模式**：特殊模式下底部栏的变化

### 改进建议
1. **响应式布局**：根据宽度调整显示内容
2. **动画提示**：新用户首次使用时高亮提示
3. **自定义配置**：允许用户自定义显示内容
4. **更多信息**：悬停显示更多信息

### 相关文件引用
- 源文件: `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
