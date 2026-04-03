# Research: Footer Status Line With Active Agent Label Snapshot

## 场景与职责

此快照展示了当状态行内容与活动代理标签同时显示时的底部栏状态。显示 "Status line content · Robie [explorer]"，将应用状态信息与当前活动的 AI 代理信息结合显示，提供全面的状态概览。

## 功能点目的

- **综合状态显示**: 同时显示应用状态和活动代理信息
- **代理上下文**: 让用户了解当前状态与哪个代理相关
- **信息整合**: 在有限空间内整合多种状态信息

## 具体技术实现

状态行与代理标签的组合显示：

1. **内容组合**: 将状态行内容与代理标签用分隔符连接
   - 格式：`"{status_line} · {agent_label}"`
2. **代理标签格式**: `"AgentName [mode]"`
   - 如："Robie [explorer]"
3. **位置安排**: 根据配置决定显示在左侧、中间或右侧

代码逻辑：
```rust
let combined_content = if let Some(agent) = &props.active_agent_label {
    if let Some(status) = &props.status_line_content {
        format!("{} · {}", status, agent)
    } else {
        agent.clone()
    }
} else {
    props.status_line_content.clone().unwrap_or_default()
};

// 渲染
Line::from(vec![
    Span::from(combined_content),
    // ... 其他内容
])
```

## 关键代码路径与文件引用

- **主要实现**: `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
- **内容组合**: 状态行与代理标签的组合逻辑
- **代理标签**: `FooterProps.active_agent_label`
- **状态内容**: `FooterProps.status_line_content`

## 依赖与外部交互

- 依赖 `FooterProps` 中的状态行和代理标签字段
- 依赖代理管理系统提供当前活动代理信息
- 与状态行内容提供者交互
- 需要处理代理切换时的状态行更新

## 风险、边界与改进建议

- **边界情况**: 当状态行内容和代理标签都很长时，组合后可能超出显示宽度
- **改进建议**: 当组合内容过长时，优先显示代理标签，状态行内容可以截断或省略
- **改进建议**: 添加代理图标或颜色标识，增强视觉区分
- **改进建议**: 支持点击代理标签快速切换代理
- **改进建议**: 当代理执行特定操作时，在状态行中显示代理的操作进度
