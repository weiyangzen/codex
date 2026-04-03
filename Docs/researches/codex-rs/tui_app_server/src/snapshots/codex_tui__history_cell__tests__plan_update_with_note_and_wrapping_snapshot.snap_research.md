# 研究文档：plan_update_with_note_and_wrapping_snapshot.snap

## 场景与职责

此快照测试验证 Codex TUI 中计划（Plan）更新时的 UI 渲染效果，特别是包含备注文本且需要换行的情况。计划工具允许 Codex 创建和管理任务计划，此测试确保计划更新在历史记录中正确显示。

## 功能点目的

1. **计划更新展示**：显示计划更新操作和备注
2. **任务列表渲染**：展示计划中的任务项及其状态
3. **长文本换行**：备注和任务描述需要正确换行

## 具体技术实现

### 计划数据结构

```rust
// 来自 codex_protocol::plan_tool
pub struct UpdatePlanArgs {
    pub note: Option<String>,
    pub plan: Vec<PlanItemArg>,
}

pub struct PlanItemArg {
    pub description: String,
    pub status: StepStatus,
}

pub enum StepStatus {
    Todo,
    InProgress,
    Done,
}
```

### 快照输出分析

```
• Updated Plan
  └ I'll update Grafana call
    error handling by adding
    retries and clearer messages
    when the backend is
    unreachable.
    ✔ Investigate existing error
      paths and logging around
      HTTP timeouts
    □ Harden Grafana client
      error handling with retry/
      backoff and user-friendly
      messages
    □ Add tests for transient
      failure scenarios and
      surfacing to the UI
```

关键元素：
- `• Updated Plan` - 操作类型
- 备注文本（多行换行显示）
- `✔` - 已完成任务标记
- `□` - 待办任务标记
- 任务描述的换行缩进

## 关键代码路径与文件引用

1. **计划样式**：
   - `crate::style::proposed_plan_style` - 计划样式定义
   - `codex-rs/tui/src/style.rs`

2. **计划单元格实现**：
   - `codex-rs/tui/src/history_cell.rs` - PlanUpdateCell 实现

3. **协议类型**：
   - `codex_protocol::plan_tool::UpdatePlanArgs`
   - `codex_protocol::plan_tool::StepStatus`

## 依赖与外部交互

### 样式依赖
- `ratatui::style::Style` - 基础样式
- `ratatui::style::Stylize` - 样式扩展

### 文本处理
- `crate::wrapping::RtOptions` - 换行选项
- `crate::wrapping::adaptive_wrap_line` - 自适应换行

## 风险、边界与改进建议

### 潜在风险
1. **任务过多**：大量任务可能导致历史记录过长
2. **备注过长**：非常长的备注可能影响可读性

### 边界情况
1. 空计划（无任务）
2. 所有任务都已完成
3. 任务描述包含特殊字符

### 改进建议
1. 添加计划折叠功能，只显示摘要
2. 支持点击展开查看完整计划
3. 添加计划进度百分比显示
4. 考虑添加计划时间线视图
