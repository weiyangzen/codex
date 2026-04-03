# Research: 计划更新带备注和换行测试快照

## 场景与职责

该快照测试验证 `PlanUpdateCell` 在渲染计划更新时的完整功能，包括备注说明的显示、计划步骤的复选框列表，以及长文本的自动换行处理。

这是 Codex TUI 中计划管理功能的核心组件，用于向用户展示 AI 助手的工作计划和进度更新。

## 功能点目的

1. **计划更新展示**: 显示 "Updated Plan" 标题和计划内容
2. **备注说明**: 支持显示计划更新的解释说明（explanation）
3. **步骤状态**: 使用复选框（✔/□）表示步骤的完成状态
4. **自动换行**: 长文本自动换行并保持一致的对齐
5. **状态区分**: 
   - ✔ Completed（已完成，删除线样式）
   - □ InProgress（进行中，青色粗体）
   - □ Pending（待处理，灰色）

## 具体技术实现

### 渲染格式

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
      backoff and user‑friendly
      messages
    □ Add tests for transient
      failure scenarios and
      surfacing to the UI
```

### 关键数据结构

```rust
// PlanUpdateCell 结构（history_cell.rs:2200-2204）
#[derive(Debug)]
pub(crate) struct PlanUpdateCell {
    explanation: Option<String>,  // 备注说明
    plan: Vec<PlanItemArg>,       // 计划步骤列表
}

// PlanItemArg 结构（来自 codex_protocol::plan_tool）
pub struct PlanItemArg {
    pub step: String,           // 步骤描述
    pub status: StepStatus,     // 步骤状态
}

pub enum StepStatus {
    Completed,   // 已完成
    InProgress,  // 进行中
    Pending,     // 待处理
}
```

### 渲染逻辑

```rust
// history_cell.rs:2206-2258
impl HistoryCell for PlanUpdateCell {
    fn display_lines(&self, width: u16) -> Vec<Line<'static>> {
        let render_note = |text: &str| -> Vec<Line<'static>> {
            let wrap_width = width.saturating_sub(4).max(1) as usize;
            let note = Line::from(text.to_string().dim().italic());
            let wrapped = adaptive_wrap_line(&note, RtOptions::new(wrap_width));
            // ...
        };

        let render_step = |status: &StepStatus, text: &str| -> Vec<Line<'static>> {
            let (box_str, step_style) = match status {
                StepStatus::Completed => ("✔ ", Style::default().crossed_out().dim()),
                StepStatus::InProgress => ("□ ", Style::default().cyan().bold()),
                StepStatus::Pending => ("□ ", Style::default().dim()),
            };
            // ...
        };

        let mut lines: Vec<Line<'static>> = vec![];
        lines.push(vec!["• ".dim(), "Updated Plan".bold()].into());

        let mut indented_lines = vec![];
        // 添加备注（如果有）
        if let Some(expl) = note {
            indented_lines.extend(render_note(expl));
        };

        // 添加步骤
        for PlanItemArg { step, status } in self.plan.iter() {
            indented_lines.extend(render_step(status, step));
        }
        
        // 使用 prefix_lines 添加统一前缀
        lines.extend(prefix_lines(indented_lines, "  └ ".dim(), "    ".into()));
        lines
    }
}
```

### 测试数据构造

```rust
// history_cell.rs:4022-4051
let update = UpdatePlanArgs {
    explanation: Some(
        "I'll update Grafana call error handling by adding retries and clearer messages when the backend is unreachable."
            .to_string(),
    ),
    plan: vec![
        PlanItemArg {
            step: "Investigate existing error paths and logging around HTTP timeouts".into(),
            status: StepStatus::Completed,
        },
        PlanItemArg {
            step: "Harden Grafana client error handling with retry/backoff and user‑friendly messages".into(),
            status: StepStatus::InProgress,
        },
        PlanItemArg {
            step: "Add tests for transient failure scenarios and surfacing to the UI".into(),
            status: StepStatus::Pending,
        },
    ],
};

let cell = new_plan_update(update);
let lines = cell.display_lines(32);  // 窄宽度强制换行
```

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `codex-rs/tui/src/history_cell.rs` | PlanUpdateCell 实现，测试位于行 4022-4051 |
| `codex-protocol/src/plan_tool.rs` | PlanItemArg、StepStatus、UpdatePlanArgs 定义 |
| `codex-rs/tui/src/render/line_utils.rs` | `prefix_lines` 函数实现 |
| `codex-rs/tui/src/wrapping.rs` | `adaptive_wrap_line`、`RtOptions` |

### 测试代码位置

```rust
// history_cell.rs:4022-4051
#[test]
fn plan_update_with_note_and_wrapping_snapshot() {
    let update = UpdatePlanArgs {
        explanation: Some(
            "I'll update Grafana call error handling by adding retries and clearer messages when the backend is unreachable."
                .to_string(),
        ),
        plan: vec![
            PlanItemArg {
                step: "Investigate existing error paths and logging around HTTP timeouts".into(),
                status: StepStatus::Completed,
            },
            // ... 更多步骤
        ],
    };

    let cell = new_plan_update(update);
    let lines = cell.display_lines(32);
    let rendered = render_lines(&lines).join("\n");
    insta::assert_snapshot!(rendered);
}
```

## 依赖与外部交互

### 外部依赖

1. **ratatui**: TUI 渲染框架
2. **textwrap**: 文本换行
3. **insta**: 快照测试

### 内部模块依赖

```rust
use crate::wrapping::RtOptions;
use crate::wrapping::adaptive_wrap_line;
use crate::render::line_utils::prefix_lines;
use codex_protocol::plan_tool::PlanItemArg;
use codex_protocol::plan_tool::StepStatus;
use codex_protocol::plan_tool::UpdatePlanArgs;
```

## 风险、边界与改进建议

### 潜在风险

1. **状态样式冲突**: 删除线（crossed_out）与颜色样式可能产生意外的视觉效果
2. **复选框字符兼容性**: `✔` 和特殊空格字符在某些终端可能显示异常
3. **换行对齐问题**: 长步骤文本换行后与复选框的对齐可能偏移

### 边界情况

1. **超长备注**: explanation 非常长时的渲染性能
2. **大量步骤**: 数十个步骤时的列表渲染
3. **空计划**: plan 为空列表时的处理
4. **特殊字符**: 步骤文本包含 emoji、控制字符等

### 改进建议

1. **折叠展开**: 支持折叠已完成的步骤，突出显示进行中的任务
2. **进度百分比**: 在标题中显示完成百分比
3. **时间戳**: 显示每个步骤的完成时间
4. **交互功能**: 支持用户点击步骤进行跳转或查看详情
5. **动画效果**: 为 InProgress 状态添加微妙的动画效果

### 相关快照文件

- `plan_update_without_note_snapshot.snap` - 无备注的计划更新测试
