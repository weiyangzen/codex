# 研究文档：session_info_availability_nux_tooltip_snapshot.snap

## 场景与职责

此快照测试验证会话信息可用性提示（NUX - New User Experience tooltip）的显示效果。当新模型可用时，向用户展示提示信息。

## 功能点目的

1. **新功能提示**：告知用户新模型或功能可用
2. **信息展示**：显示当前会话的关键信息
3. **用户引导**：提供操作提示（如如何切换模型）

## 具体技术实现

### 快照输出分析

```
╭─────────────────────────────────────╮
│ >_ OpenAI Codex (v0.0.0)            │
│                                     │
│ model:     gpt-5   /model to change │
│ directory: /tmp/project             │
╰─────────────────────────────────────╯

  Tip: Model just became available
```

关键元素：
- 带边框的信息面板
- 版本号显示
- 当前模型和目录
- 底部提示信息

### 面板实现

```rust
fn render_session_info(config: &Config) -> Vec<Line> {
    let mut lines = vec![];
    
    // 顶部边框
    lines.push(Line::from("╭─────────────────────────────────────╮"));
    
    // 标题
    lines.push(Line::from(format!("│ >_ OpenAI Codex (v{}) {:">width$}│", 
        CODEX_CLI_VERSION, "", width = 20 - CODEX_CLI_VERSION.len())));
    
    // 空行
    lines.push(Line::from("│                                     │"));
    
    // 模型信息
    lines.push(Line::from(format!("│ model:     {} {:">width$}│", 
        config.model, "/model to change",
        width = 30 - config.model.len())));
    
    // 目录信息
    lines.push(Line::from(format!("│ directory: {} {:">width$}│",
        config.cwd, "",
        width = 40 - config.cwd.len())));
    
    // 底部边框
    lines.push(Line::from("╰─────────────────────────────────────╯"));
    
    lines
}
```

## 关键代码路径与文件引用

1. **会话信息**：
   - `codex-rs/tui/src/history_cell.rs`
   - `codex-rs/tui/src/tooltips.rs`

2. **配置类型**：
   - `codex_core::config::Config`
   - `codex_protocol::protocol::SessionConfiguredEvent`

## 依赖与外部交互

### 版本信息
- `crate::version::CODEX_CLI_VERSION`

### 样式
- `ratatui::style::Style`
- `ratatui::widgets::Borders`

## 风险、边界与改进建议

### 潜在风险
1. **宽度适应性**：固定宽度可能在窄终端上显示不佳
2. **信息过时**：提示信息可能不及时更新

### 边界情况
1. 非常长的模型名称
2. 非常长的目录路径
3. 版本号格式变化

### 改进建议
1. 使用自适应宽度，适应不同终端大小
2. 添加点击交互，支持快速切换模型
3. 支持更多配置项的显示
4. 添加会话持续时间显示
