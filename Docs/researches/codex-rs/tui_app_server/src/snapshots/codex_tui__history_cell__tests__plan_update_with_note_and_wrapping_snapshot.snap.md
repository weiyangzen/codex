# Plan Update 带备注与换行测试快照研究文档

## 场景与职责

本快照测试验证 **PlanUpdateCell** 对计划更新（Plan Update）的渲染，特别是当更新包含**解释说明（explanation/note）**且内容需要**换行**时的处理。这是 Codex TUI 中计划工具（plan tool）的核心展示功能，用于向用户展示 AI 制定的执行计划及其状态。

测试场景：
- 计划更新包含详细的解释说明
- 包含多个计划步骤，每个步骤有不同的状态（已完成、进行中、待处理）
- 窄终端宽度（32字符）强制内容换行
- 验证备注和步骤的换行及缩进处理

## 功能点目的

### 核心功能
1. **计划更新展示**：展示 AI 对计划的更新，包括解释和步骤列表
2. **状态可视化**：使用不同图标区分步骤状态（✔ 完成、□ 进行中、□ 待处理）
3. **文本换行**：在窄终端中正确换行长文本
4. **层次缩进**：保持步骤列表的层次结构

### 展示目标
- 标题行显示 "• Updated Plan"
- 解释说明（如果有）显示为斜体暗淡文本
- 步骤列表使用复选框样式
- 已完成步骤使用删除线和暗淡样式
- 进行中步骤使用青色粗体
- 待处理步骤使用暗淡样式

## 具体技术实现

### 数据结构

```rust
// codex_protocol::plan_tool
pub struct UpdatePlanArgs {
    pub explanation: Option<String>,  // 解释说明
    pub plan: Vec<PlanItemArg>,       // 计划步骤列表
}

pub struct PlanItemArg {
    pub step: String,                 // 步骤描述
    pub status: StepStatus,           // 步骤状态
}

pub enum StepStatus {
    Completed,   // 已完成
    InProgress,  // 进行中
    Pending,     // 待处理
}
```

### PlanUpdateCell 结构

位于 `history_cell.rs`（行 2200-2204）：

```rust
#[derive(Debug)]
pub(crate) struct PlanUpdateCell {
    explanation: Option<String>,
    plan: Vec<PlanItemArg>,
}
```

### 关键渲染逻辑

位于 `history_cell.rs` 的 `PlanUpdateCell::display_lines` 方法（行 2206-2258）：

```rust
impl HistoryCell for PlanUpdateCell {
    fn display_lines(&self, width: u16) -> Vec<Line<'static>> {
        // 备注渲染函数
        let render_note = |text: &str| -> Vec<Line<'static>> {
            let wrap_width = width.saturating_sub(4).max(1) as usize;
            let note = Line::from(text.to_string().dim().italic());
            let wrapped = adaptive_wrap_line(&note, RtOptions::new(wrap_width));
            let mut out = Vec::new();
            push_owned_lines(&wrapped, &mut out);
            out
        };

        // 步骤渲染函数
        let render_step = |status: &StepStatus, text: &str| -> Vec<Line<'static>> {
            let (box_str, step_style) = match status {
                StepStatus::Completed => ("✔ ", Style::default().crossed_out().dim()),
                StepStatus::InProgress => ("□ ", Style::default().cyan().bold()),
                StepStatus::Pending => ("□ ", Style::default().dim()),
            };

            let opts = RtOptions::new(width.saturating_sub(4).max(1) as usize)
                .initial_indent(box_str.into())
                .subsequent_indent("  ".into());
            let step = Line::from(text.to_string().set_style(step_style));
            let wrapped = adaptive_wrap_line(&step, opts);
            let mut out = Vec::new();
            push_owned_lines(&wrapped, &mut out);
            out
        };

        let mut lines: Vec<Line<'static>> = vec![];
        lines.push(vec!["• ".dim(), "Updated Plan".bold()].into());

        let mut indented_lines = vec![];
        let note = self.explanation.as_ref()
            .map(|s| s.trim())
            .filter(|t| !t.is_empty());
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
        // 应用整体缩进
        lines.extend(prefix_lines(indented_lines, "  └ ".dim(), "    ".into()));

        lines
    }
}
```

### 测试用例构造

位于 `history_cell.rs` 测试模块（行 4023-4051）：

```rust
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
    // 窄宽度 32 强制换行
    let lines = cell.display_lines(32);
    let rendered = render_lines(&lines).join("\n");
    insta::assert_snapshot!(rendered);
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
      backoff and user‑friendly
      messages
    □ Add tests for transient
      failure scenarios and
      surfacing to the UI
```

输出结构解析：
1. `• Updated Plan` - 标题行（暗淡前缀 + 粗体标题）

2. 解释说明块（斜体暗淡）：
   - `  └ I'll update Grafana call` - 第一行，带 "  └ " 前缀
   - `    error handling by adding` - 续行，带 "    " 前缀（4空格）
   - `    retries and clearer messages`
   - `    when the backend is`
   - `    unreachable.`

3. 步骤列表：
   - 已完成步骤（删除线 + 暗淡）：
     - `    ✔ Investigate existing error`
     - `      paths and logging around`（续行缩进 6空格）
     - `      HTTP timeouts`
   
   - 进行中步骤（青色粗体）：
     - `    □ Harden Grafana client`
     - `      error handling with retry/`
     - `      backoff and user‑friendly`
     - `      messages`
   
   - 待处理步骤（暗淡）：
     - `    □ Add tests for transient`
     - `      failure scenarios and`
     - `      surfacing to the UI`

## 关键代码路径与文件引用

### 主要文件
| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/history_cell.rs` | PlanUpdateCell 实现 |
| `codex-rs/tui/src/wrapping.rs` | 自适应换行工具 |
| `codex-protocol/src/plan_tool.rs` | UpdatePlanArgs 和 StepStatus 定义 |

### 关键样式
| 元素 | 样式 |
|-----|------|
| 标题 | `"Updated Plan".bold()` |
| 备注 | `.dim().italic()` |
| 已完成步骤 | `.crossed_out().dim()` |
| 进行中步骤 | `.cyan().bold()` |
| 待处理步骤 | `.dim()` |

### 缩进层级
| 层级 | 前缀 | 用途 |
|-----|------|------|
| 0 | `• ` | 标题 |
| 1 | `  └ ` / `    ` | 备注内容 |
| 2 | `    ✔ ` / `      ` | 步骤内容 |

## 依赖与外部交互

### 内部依赖
- `codex_protocol::plan_tool::UpdatePlanArgs` - 计划更新参数
- `codex_protocol::plan_tool::StepStatus` - 步骤状态枚举
- `codex_protocol::plan_tool::PlanItemArg` - 计划项参数

### 样式系统
```rust
use ratatui::style::Style;
use ratatui::style::Stylize;

// 已完成：删除线 + 暗淡
Style::default().crossed_out().dim()

// 进行中：青色 + 粗体
Style::default().cyan().bold()

// 待处理：暗淡
Style::default().dim()
```

### 数据流
```
UpdatePlanArgs
    ├── explanation: Option<String>
    └── plan: Vec<PlanItemArg>
            ├── step: String
            └── status: StepStatus
                    ├── Completed
                    ├── InProgress
                    └── Pending
```

## 风险、边界与改进建议

### 潜在风险
1. **状态图标混淆**：✔ 和 □ 在小字体下可能难以区分
2. **删除线可读性**：长文本的删除线可能降低可读性
3. **颜色依赖**：仅依赖颜色区分状态对色盲用户不友好

### 边界情况
1. **空计划**：`plan` 为空向量时的展示
2. **超长步骤**：单步骤描述超过 1000 字符
3. **多行步骤**：步骤描述本身包含换行符
4. **特殊字符**：步骤描述包含 ANSI 转义序列

### 改进建议

#### 高优先级
1. **可访问性增强**：添加状态文本标签
   ```
   ✔ [Done] Investigate error paths
   □ [Doing] Harden client
   □ [Todo] Add tests
   ```

2. **进度指示器**：显示整体完成百分比
   ```
   • Updated Plan (1/3 done, 1 in progress)
   ```

#### 中优先级
3. **可折叠步骤**：允许展开/折叠已完成步骤
4. **步骤编号**：显示步骤序号便于引用
   ```
   1. ✔ Investigate...
   2. □ Harden...
   3. □ Add tests...
   ```

#### 低优先级
5. **时间戳**：记录每个步骤的完成时间
6. **责任人**：支持分配步骤负责人

### 测试建议
1. 增加空解释和空计划的边界测试
2. 增加超长步骤的性能测试
3. 增加特殊字符和 emoji 的渲染测试
4. 增加不同颜色主题下的对比度测试
