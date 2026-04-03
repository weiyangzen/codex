# Footer Active Agent Label Snapshot 研究文档

## 场景与职责

该快照文件测试了底部栏在**多代理模式**下显示活动代理标签的状态。

### 业务场景
- 用户处于多代理模式
- 当前活动代理为 "Robie [explorer]"
- 底部栏显示活动代理标签和上下文信息

## 功能点目的

### 核心功能
1. **代理标识**：显示当前活动代理的名称和角色
2. **上下文指示**：显示上下文窗口使用状态
3. **状态整合**：将代理标签与上下文信息整合显示

### UI 设计特点
- 格式：`Robie [explorer]                                           100% context left`
- 左对齐代理标签
- 右对齐上下文信息

## 具体技术实现

### Footer 属性
```rust
pub(crate) struct FooterProps {
    pub(crate) active_agent_label: Option<String>,
    pub(crate) context_window_percent: Option<i64>,
    // ...
}
```

### 被动 Footer 状态行
```rust
pub(crate) fn passive_footer_status_line(props: &FooterProps) -> Option<Line<'static>> {
    let mut line = if props.status_line_enabled {
        props.status_line_value.clone()
    } else {
        None
    };
    
    if let Some(active_agent_label) = props.active_agent_label.as_ref() {
        if let Some(existing) = line.as_mut() {
            existing.spans.push(" · ".into());
            existing.spans.push(active_agent_label.clone().into());
        } else {
            line = Some(Line::from(active_agent_label.clone()));
        }
    }
    
    line
}
```

## 关键代码路径

### 主要源文件
- `codex-rs/tui/src/bottom_pane/footer.rs`

### 相关测试
- `footer_active_agent_label` - 本快照
- `footer_status_line_with_active_agent_label` - 状态行与代理标签
