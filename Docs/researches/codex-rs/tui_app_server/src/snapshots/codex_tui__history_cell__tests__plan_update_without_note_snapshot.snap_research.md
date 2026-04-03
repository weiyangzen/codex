# 研究文档：plan_update_without_note_snapshot.snap

## 场景与职责

此快照测试验证 Codex TUI 中计划更新时不包含备注文本的 UI 渲染效果。这是计划更新的简化形式，只显示任务列表。

## 功能点目的

1. **简化计划展示**：当没有备注时，直接显示任务列表
2. **紧凑布局**：减少不必要的空白，提高信息密度
3. **任务状态清晰**：通过符号清晰区分任务状态

## 具体技术实现

### 快照输出分析

```
• Updated Plan
  └ □ Define error taxonomy
    □ Implement mapping to user messages
```

与带备注的版本对比：
- 没有备注文本段落
- 直接显示任务列表
- 更紧凑的布局

### 条件渲染逻辑

```rust
fn render_plan_update(plan: &UpdatePlanArgs) -> Vec<Line> {
    let mut lines = vec![];
    lines.push(Line::from("• Updated Plan"));
    
    let mut content = vec![];
    
    // 只有在有备注时才添加备注文本
    if let Some(note) = &plan.note {
        content.extend(wrap_text(note));
    }
    
    // 添加任务列表
    for item in &plan.plan {
        let symbol = match item.status {
            StepStatus::Done => "✔",
            _ => "□",
        };
        content.push(format!("{symbol} {}", item.description));
    }
    
    // 添加树形前缀
    add_tree_prefix(&mut lines, content);
    lines
}
```

## 关键代码路径与文件引用

1. **计划更新单元格**：
   - `codex-rs/tui/src/history_cell.rs` - PlanUpdateCell

2. **样式定义**：
   - `crate::style::proposed_plan_style`

## 依赖与外部交互

### 协议类型
- `codex_protocol::plan_tool::UpdatePlanArgs`
- `codex_protocol::plan_tool::StepStatus`
- `codex_protocol::plan_tool::PlanItemArg`

## 风险、边界与改进建议

### 边界情况
1. 空任务列表
2. 单个任务
3. 所有任务状态相同

### 改进建议
1. 当没有备注且任务少时，考虑单行显示
2. 添加任务计数摘要
3. 支持任务优先级显示
