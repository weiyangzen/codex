# Chat Composer Footer Collapse Plan Empty Full Snapshot 研究文档

## 场景与职责

该快照文件测试了聊天编辑器底部栏在**Plan 模式 + 空输入状态下的完整显示模式**。展示了当启用 Plan 模式且终端宽度充足时的 footer 渲染。

### 业务场景
- 编辑器为空，处于 Plan 模式
- 终端宽度充足（120字符）
- 显示模式指示器和快捷操作提示

### Plan 模式说明
Plan 模式是协作模式之一，用于规划和设计阶段，AI 会更多地询问用户意见而不是直接执行。

## 功能点目的

### 核心功能
1. **模式指示**：显示 "Plan mode (shift+tab to cycle)"
2. **快捷操作提示**：显示 "? for shortcuts"
3. **上下文指示**：显示 "100% context left"

### UI 设计特点
- Plan 模式使用洋红色（magenta）显示
- 使用 " · " 分隔不同部分
- 完整显示所有信息

## 具体技术实现

### 模式指示器
```rust
pub(crate) enum CollaborationModeIndicator {
    Plan,
    PairProgramming,
    Execute,
}

impl CollaborationModeIndicator {
    fn styled_span(self, show_cycle_hint: bool) -> Span<'static> {
        let label = self.label(show_cycle_hint);
        match self {
            CollaborationModeIndicator::Plan => Span::from(label).magenta(),
            CollaborationModeIndicator::PairProgramming => Span::from(label).cyan(),
            CollaborationModeIndicator::Execute => Span::from(label).dim(),
        }
    }
}
```

### Footer 状态
```rust
let state = LeftSideState {
    hint: SummaryHintKind::Shortcuts,  // "? for shortcuts"
    show_cycle_hint: true,             // "(shift+tab to cycle)"
};
```

## 关键代码路径

### 主要源文件
- `codex-rs/tui/src/bottom_pane/footer.rs`

### 相关测试系列
- `footer_collapse_plan_empty_full` - 本快照（Plan模式，空输入，全宽）
- `footer_collapse_plan_queue_full` - Plan模式，有队列消息
- `footer_collapse_queue_full` - 非Plan模式，有队列消息
