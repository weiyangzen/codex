# Plan Update 无备注测试快照研究文档

## 场景与职责

本快照测试验证 **PlanUpdateCell** 对计划更新的渲染，特别是当更新**不包含解释说明（explanation）**时的简化展示。这是 Plan Update 功能的边界情况测试，确保在没有备注时仍能正确展示计划步骤。

测试场景：
- 计划更新不包含 explanation 字段（`explanation: None`）
- 包含两个计划步骤（进行中、待处理）
- 验证无备注时的简洁展示

## 功能点目的

### 核心功能
1. **可选备注展示**：explanation 字段是可选的，可能为 None
2. **简洁模式**：无备注时直接展示步骤列表
3. **状态可视化**：保持步骤状态的视觉区分

### 展示目标
- 标题行显示 "• Updated Plan"
- 不显示备注块（因为 explanation 为 None）
- 直接展示步骤列表
- 保持步骤状态的视觉样式

## 具体技术实现

### 空备注处理逻辑

位于 `history_cell.rs` 的 `PlanUpdateCell::display_lines` 方法（行 2238-2245）：

```rust
let mut indented_lines = vec![];
let note = self.explanation.as_ref()
    .map(|s| s.trim())
    .filter(|t| !t.is_empty());  // 过滤空字符串
if let Some(expl) = note {
    indented_lines.extend(render_note(expl));
};
```

关键处理：
1. `as_ref()` - 将 `Option<String>` 转为 `Option<&String>`
2. `map(|s| s.trim())` - 去除首尾空白
3. `filter(|t| !t.is_empty())` - 过滤空字符串
4. `if let Some(expl)` - 仅在存在非空备注时渲染

### 空计划处理

位于同一方法（行 2247-2253）：

```rust
if self.plan.is_empty() {
    indented_lines.push(Line::from("(no steps provided)".dim().italic()));
} else {
    for PlanItemArg { step, status } in self.plan.iter() {
        indented_lines.extend(render_step(status, step));
    }
}
```

### 测试用例构造

位于 `history_cell.rs` 测试模块（行 4054-4073）：

```rust
#[test]
fn plan_update_without_note_snapshot() {
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
    let lines = cell.display_lines(40);  // 较宽终端
    let rendered = render_lines(&lines).join("\n");
    insta::assert_snapshot!(rendered);
}
```

### 快照输出分析

```
• Updated Plan
  └ □ Define error taxonomy
    □ Implement mapping to user messages
```

输出结构解析：
1. `• Updated Plan` - 标题行
   - `• ` - 暗淡前缀
   - `Updated Plan` - 粗体标题

2. `  └ □ Define error taxonomy` - 第一个步骤
   - `  └ ` - 初始缩进前缀（4空格 + 角符号 + 1空格）
   - `□ ` - 进行中状态图标（青色粗体）
   - `Define error taxonomy` - 步骤描述

3. `    □ Implement mapping to user messages` - 第二个步骤
   - `    ` - 续行缩进（4空格）
   - `□ ` - 待处理状态图标（暗淡）
   - `Implement mapping to user messages` - 步骤描述

**注意**：由于终端宽度（40字符）足够，步骤不需要换行。

## 关键代码路径与文件引用

### 主要文件
| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/history_cell.rs` | PlanUpdateCell 实现，行 2200-2258 |
| `codex-protocol/src/plan_tool.rs` | UpdatePlanArgs 定义 |

### 关键函数
| 函数 | 位置 | 职责 |
|-----|------|------|
| `new_plan_update` | `history_cell.rs:2127` | 构造函数 |
| `display_lines` | `history_cell.rs:2207` | 渲染方法 |
| `render_step` | `history_cell.rs:2217` | 步骤渲染闭包 |

### 构造函数

```rust
/// Render a user‑friendly plan update styled like a checkbox todo list.
pub(crate) fn new_plan_update(update: UpdatePlanArgs) -> PlanUpdateCell {
    let UpdatePlanArgs { explanation, plan } = update;
    PlanUpdateCell { explanation, plan }
}
```

## 依赖与外部交互

### 数据结构依赖
```rust
// codex-protocol/src/plan_tool.rs
pub struct UpdatePlanArgs {
    pub explanation: Option<String>,
    pub plan: Vec<PlanItemArg>,
}

pub struct PlanItemArg {
    pub step: String,
    pub status: StepStatus,
}

pub enum StepStatus {
    Completed,
    InProgress,
    Pending,
}
```

### 渲染工具
```rust
use crate::render::line_utils::prefix_lines;
use crate::wrapping::RtOptions;
use crate::wrapping::adaptive_wrap_line;
```

## 风险、边界与改进建议

### 潜在风险
1. **空计划展示**：当 plan 为空时显示 "(no steps provided)"，用户可能困惑
2. **状态不明确**：无备注时用户可能不清楚计划更新的上下文
3. **步骤过多**：大量步骤可能淹没历史记录

### 边界情况
1. **空字符串备注**：`explanation: Some("".to_string())`
2. **仅空白备注**：`explanation: Some("   ".to_string())`
3. **单步骤计划**：只有一个步骤的计划
4. **全完成计划**：所有步骤都是 Completed 状态

### 改进建议

#### 高优先级
1. **智能提示**：无备注时添加默认提示
   ```
   • Updated Plan
     (no additional notes)
     □ Define error taxonomy
   ```

2. **计划摘要**：显示步骤统计
   ```
   • Updated Plan (2 steps: 1 in progress, 1 pending)
   ```

#### 中优先级
3. **上下文感知**：根据前一条消息推断备注上下文
4. **快捷添加备注**：允许用户事后添加备注

#### 低优先级
5. **计划模板**：提供常见计划模板
6. **计划导出**：支持导出计划为 TODO 格式

### 测试建议
1. 增加空字符串和空白字符串备注测试
2. 增加空计划（无步骤）测试
3. 增加大量步骤（100+）的性能测试
4. 增加所有步骤同状态的展示测试
