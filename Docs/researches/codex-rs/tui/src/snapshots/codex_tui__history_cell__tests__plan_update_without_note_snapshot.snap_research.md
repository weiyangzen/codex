# Research: 计划更新无备注测试快照

## 场景与职责

该快照测试验证 `PlanUpdateCell` 在渲染计划更新时的简化场景，即当计划更新不包含备注说明（explanation）时的渲染行为。

这是 Codex TUI 计划管理功能的基础测试，确保最小化场景下的正确渲染。

## 功能点目的

1. **简化计划展示**: 当没有备注时，直接显示计划步骤列表
2. **步骤状态可视化**: 使用复选框表示步骤完成状态
3. **紧凑布局**: 无备注时的紧凑渲染，减少垂直空间占用
4. **一致性**: 保持与带备注场景的样式一致性

## 具体技术实现

### 渲染格式

```
• Updated Plan
  └ □ Define error taxonomy
    □ Implement mapping to user messages
```

格式说明：
- `• Updated Plan`: 标题行
- `└ `: 内容块开始标记
- `□ `: 待处理步骤的复选框
- `Define error taxonomy`: 步骤描述

### 关键代码逻辑

```rust
// history_cell.rs:2206-2258
impl HistoryCell for PlanUpdateCell {
    fn display_lines(&self, width: u16) -> Vec<Line<'static>> {
        // ...
        
        let mut indented_lines = vec![];
        let note = self
            .explanation
            .as_ref()
            .map(|s| s.trim())
            .filter(|t| !t.is_empty());
        
        // 仅在存在非空备注时添加
        if let Some(expl) = note {
            indented_lines.extend(render_note(expl));
        };

        if self.plan.is_empty() {
            indented_lines.push(Line::from("(no steps provided)".dim().italic()));
        } else {
            for PlanItemArg { step, status } in self.plan.iter() {
                indented_lines.extend(render_step(status, step));
            }
        }
        lines.extend(prefix_lines(indented_lines, "  └ ".dim(), "    ".into()));
        lines
    }
}
```

### 测试数据构造

```rust
// history_cell.rs:4053-4073
let update = UpdatePlanArgs {
    explanation: None,  // 无备注
    plan: vec![
        PlanItemArg {
            step: "Define error taxonomy".into(),
            status: StepStatus::InProgress,
        },
        PlanItemArg {
            step: "Implement mapping to user messages".into(),
            status: StepStatus::Pending,
        },
    ],
};

let cell = new_plan_update(update);
let lines = cell.display_lines(40);
```

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `codex-rs/tui/src/history_cell.rs` | PlanUpdateCell 实现，测试位于行 4053-4073 |
| `codex-protocol/src/plan_tool.rs` | PlanItemArg、StepStatus、UpdatePlanArgs 定义 |

### 测试代码位置

```rust
// history_cell.rs:4053-4073
#[test]
fn plan_update_without_note_snapshot() {
    let update = UpdatePlanArgs {
        explanation: None,
        plan: vec![
            PlanItemArg {
                step: "Define error taxonomy".into(),
                status: StepStatus::InProgress,
            },
            PlanItemArg {
                step: "Implement mapping to user messages".into(),
                status: StepStatus::Pending,
            },
        ],
    };

    let cell = new_plan_update(update);
    let lines = cell.display_lines(40);
    let rendered = render_lines(&lines).join("\n");
    insta::assert_snapshot!(rendered);
}
```

## 依赖与外部交互

### 外部依赖

1. **ratatui**: TUI 渲染框架
2. **insta**: 快照测试

### 内部模块依赖

```rust
use codex_protocol::plan_tool::PlanItemArg;
use codex_protocol::plan_tool::StepStatus;
use codex_protocol::plan_tool::UpdatePlanArgs;
```

## 风险、边界与改进建议

### 潜在风险

1. **空值处理**: explanation 为 None 时的空值处理必须正确
2. **空白字符**: explanation 只包含空白字符时的过滤逻辑

### 边界情况

1. **空计划**: plan 为空列表时显示 `(no steps provided)`
2. **单一步骤**: 只有一个步骤时的渲染
3. **超长步骤**: 步骤描述非常长时的换行

### 改进建议

1. **智能排序**: 按状态排序（InProgress > Pending > Completed）
2. **分组显示**: 按状态分组显示步骤
3. **计数显示**: 在标题中显示步骤总数和完成数

### 相关快照文件

- `plan_update_with_note_and_wrapping_snapshot.snap` - 带备注的计划更新测试
