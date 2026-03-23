# plan_tool.rs 研究文档

## 场景与职责

`plan_tool.rs` 是 Codex 协议库中的计划工具类型定义模块，定义了 `update_plan` 工具的参数结构。该工具允许模型在执行任务时维护和更新一个结构化的计划列表，客户端可以读取和展示这些计划，帮助用户跟踪任务进度。

**核心职责：**
- 定义计划项状态枚举（StepStatus）
- 定义计划项参数结构（PlanItemArg）
- 定义更新计划工具的参数结构（UpdatePlanArgs）
- 支持与 codex-vscode/todo-mcp 的兼容性

## 功能点目的

### 1. 计划项状态 (StepStatus)

**目的：** 表示计划中每个步骤的执行状态。

```rust
pub enum StepStatus {
    Pending,     // 待处理
    InProgress,  // 进行中
    Completed,   // 已完成
}
```

**约束：**
- 同时只能有一个步骤处于 `InProgress` 状态
- 模型通过更新计划来反映当前执行进度

### 2. 计划项参数 (PlanItemArg)

**目的：** 表示单个计划步骤的内容和状态。

```rust
pub struct PlanItemArg {
    pub step: String,       // 步骤描述
    pub status: StepStatus, // 步骤状态
}
```

### 3. 更新计划参数 (UpdatePlanArgs)

**目的：** `update_plan` 工具的完整参数结构。

```rust
pub struct UpdatePlanArgs {
    #[serde(default)]
    pub explanation: Option<String>,  // 可选的解释说明
    pub plan: Vec<PlanItemArg>,       // 计划步骤列表
}
```

**设计说明：**
- `explanation` 字段是可选的，允许模型提供额外的上下文
- `#[serde(deny_unknown_fields)]` 确保严格的字段验证
- 与 `codex-vscode/todo-mcp/src/main.rs` 中的类型保持兼容

## 具体技术实现

### 序列化配置

```rust
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, TS)]
#[serde(rename_all = "snake_case")]  // 使用 snake_case 进行序列化
pub enum StepStatus {
    Pending,
    InProgress,
    Completed,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, TS)]
#[serde(deny_unknown_fields)]  // 拒绝未知字段，确保严格验证
pub struct PlanItemArg {
    pub step: String,
    pub status: StepStatus,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, TS)]
#[serde(deny_unknown_fields)]
pub struct UpdatePlanArgs {
    #[serde(default)]  // 默认为 None
    pub explanation: Option<String>,
    pub plan: Vec<PlanItemArg>,
}
```

### JSON 格式示例

**完整请求：**
```json
{
    "explanation": "开始实现用户认证功能",
    "plan": [
        {"step": "创建用户模型", "status": "completed"},
        {"step": "实现登录接口", "status": "in_progress"},
        {"step": "添加密码加密", "status": "pending"},
        {"step": "编写单元测试", "status": "pending"}
    ]
}
```

**无解释的请求：**
```json
{
    "plan": [
        {"step": "分析代码结构", "status": "completed"},
        {"step": "重构核心模块", "status": "completed"}
    ]
}
```

## 关键代码路径与文件引用

### 本文件完整代码

```rust
use schemars::JsonSchema;
use serde::Deserialize;
use serde::Serialize;
use ts_rs::TS;

// Types for the TODO tool arguments matching codex-vscode/todo-mcp/src/main.rs
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, TS)]
#[serde(rename_all = "snake_case")]
pub enum StepStatus {
    Pending,
    InProgress,
    Completed,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, TS)]
#[serde(deny_unknown_fields)]
pub struct PlanItemArg {
    pub step: String,
    pub status: StepStatus,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, TS)]
#[serde(deny_unknown_fields)]
pub struct UpdatePlanArgs {
    /// Arguments for the `update_plan` todo/checklist tool (not plan mode).
    #[serde(default)]
    pub explanation: Option<String>,
    pub plan: Vec<PlanItemArg>,
}
```

### 调用方

**主要实现位于：** `codex-rs/core/src/tools/handlers/plan.rs`

该文件包含：
- `PlanHandler` 结构体
- `handle_update_plan` 函数
- 工具规范定义（`PLAN_TOOL`）

### 使用方

| 文件 | 用途 |
|------|------|
| `protocol.rs` | 导入并重新导出 `UpdatePlanArgs` |
| `protocol.rs:EventMsg::PlanUpdate` | 作为事件消息类型 |
| `core/src/tools/handlers/plan.rs` | 工具实现 |
| `exec/src/event_processor_with_human_output.rs` | 事件处理器输出 |
| `exec/src/event_processor_with_jsonl_output.rs` | JSONL 输出处理 |
| `tui/src/history_cell.rs` | TUI 历史记录展示 |
| `tui_app_server/src/history_cell.rs` | App Server 历史记录 |
| `tui/src/chatwidget.rs` | TUI 聊天组件 |
| `tui_app_server/src/chatwidget.rs` | App Server 聊天组件 |

### 导入路径

```rust
// protocol.rs 中导入
use crate::plan_tool::UpdatePlanArgs;

// 在 EventMsg 中使用
pub enum EventMsg {
    PlanUpdate(UpdatePlanArgs),
    // ...
}

// 外部 crate 使用
use codex_protocol::plan_tool::UpdatePlanArgs;
```

### 工具处理流程

```
模型调用 update_plan
    └── core/src/tools/handlers/plan.rs:PlanHandler::handle()
        └── handle_update_plan()
            ├── 检查 collaboration_mode.mode != ModeKind::Plan
            ├── parse_update_plan_arguments() 解析参数
            ├── session.send_event(EventMsg::PlanUpdate(args))
            └── 返回 PlanToolOutput
```

## 依赖与外部交互

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `schemars` | JSON Schema 生成 |
| `serde` | 序列化/反序列化 |
| `ts_rs` | TypeScript 类型生成 |

### 与其他模块的关系

```
plan_tool.rs (类型定义)
    ↑
    │ 使用
    │
protocol.rs
    ├── 导入 UpdatePlanArgs
    ├── 在 EventMsg::PlanUpdate 中使用
    └── 重新导出供外部使用
    
core/src/tools/handlers/plan.rs (工具实现)
    ├── 使用 UpdatePlanArgs 解析参数
    ├── 发送 EventMsg::PlanUpdate 事件
    └── 在 Plan mode 中禁用该工具
    
TUI/App Server (UI 展示)
    └── 接收 EventMsg::PlanUpdate 并渲染计划列表
```

### 与外部系统的兼容性

**与 codex-vscode/todo-mcp 的兼容性：**
- 注释明确说明类型需要与 `codex-vscode/todo-mcp/src/main.rs` 匹配
- 使用 `#[serde(deny_unknown_fields)]` 确保严格验证
- 使用 `snake_case` 命名约定

## 风险、边界与改进建议

### 已知风险

1. **Plan 模式冲突**
   - 风险：`update_plan` 工具在 Plan 模式下被禁用
   - 原因：Plan 模式有自己的计划管理系统
   - 处理：`handle_update_plan` 检查 `ModeKind::Plan` 并返回错误

2. **严格的字段验证**
   - 风险：`#[serde(deny_unknown_fields)]` 会导致未知字段被拒绝
   - 影响：向前兼容性受限，新增字段需要同步更新
   - 缓解：这是有意的设计，确保类型安全

3. **空计划列表**
   - 风险：`plan` 字段没有 `#[serde(default)]`，空列表需要显式传递
   - 影响：模型可能传递空计划清空现有计划

### 边界条件

| 场景 | 行为 |
|------|------|
| Plan 模式下调用 | 返回错误 "update_plan is a TODO/checklist tool and is not allowed in Plan mode" |
| 空计划列表 | 合法，会清空现有计划 |
| 多个 InProgress 步骤 | 模型可能这样做，但规范建议最多一个 |
| explanation 为 None | 合法，不显示解释 |
| 未知字段 | 反序列化失败，返回错误给模型 |

### 改进建议

1. **添加验证逻辑**
   - 在反序列化后验证最多只有一个 `InProgress` 步骤
   - 验证步骤描述不为空

2. **添加元数据字段**
   - 考虑添加 `timestamp` 字段记录更新时间
   - 添加 `version` 字段支持计划版本管理

3. **支持计划嵌套**
   - 当前只有扁平列表
   - 考虑支持子步骤或层级结构

4. **增强错误信息**
   - 当前解析失败只返回通用错误
   - 提供具体的字段错误信息

5. **添加进度统计**
   - 添加辅助方法计算完成百分比
   - 帮助 UI 展示进度条

### 测试建议

当前此文件无测试（仅类型定义），测试主要在 `core/src/tools/handlers/plan.rs`。

建议添加：
- 序列化/反序列化一致性测试
- 未知字段拒绝测试
- Plan 模式禁用测试
- 空计划列表处理测试

### 代码示例

**验证最多一个 InProgress 的建议实现：**

```rust
impl UpdatePlanArgs {
    pub fn validate(&self) -> Result<(), String> {
        let in_progress_count = self.plan
            .iter()
            .filter(|item| matches!(item.status, StepStatus::InProgress))
            .count();
        
        if in_progress_count > 1 {
            return Err(format!(
                "Expected at most one in_progress step, found {}",
                in_progress_count
            ));
        }
        
        Ok(())
    }
}
```

**进度统计辅助方法：**

```rust
impl UpdatePlanArgs {
    pub fn progress(&self) -> (usize, usize) {
        let total = self.plan.len();
        let completed = self.plan
            .iter()
            .filter(|item| matches!(item.status, StepStatus::Completed))
            .count();
        (completed, total)
    }
    
    pub fn progress_percent(&self) -> f64 {
        let (completed, total) = self.progress();
        if total == 0 {
            0.0
        } else {
            (completed as f64 / total as f64) * 100.0
        }
    }
}
```
