# plan.rs 研究文档

## 场景与职责

`plan.rs` 实现了 Codex 的 `update_plan` 工具处理器，用于允许模型以结构化方式记录任务计划。该工具本身不执行实际操作，而是为客户端提供一个可读取和渲染的计划记录机制，强制模型在继续执行前显式地制定和记录计划。

## 功能点目的

### 1. 计划更新工具 (update_plan)
- **结构化计划记录**: 允许模型提交带有步骤和状态的计划项列表
- **客户端渲染支持**: 客户端可以读取计划更新事件并渲染进度
- **执行模式限制**: 在 Plan 模式下禁用此工具（避免循环）

### 2. 计划项状态管理
- **pending**: 待处理
- **in_progress**: 进行中（同时只能有一个）
- **completed**: 已完成

### 3. 工具规范定义
- 使用 JSON Schema 定义工具参数结构
- 支持 `explanation` 和 `plan` 两个主要字段
- `plan` 是包含 `step` 和 `status` 的数组

## 具体技术实现

### 核心数据结构

```rust
pub struct PlanHandler;
pub struct PlanToolOutput;

// 来自 codex_protocol 的参数类型
pub struct UpdatePlanArgs {
    pub explanation: Option<String>,
    pub plan: Vec<PlanItem>,
}

pub struct PlanItem {
    pub step: String,
    pub status: String, // "pending" | "in_progress" | "completed"
}
```

### 工具规范定义 (LazyLock)

```rust
pub static PLAN_TOOL: LazyLock<ToolSpec> = LazyLock::new(|| {
    let mut plan_item_props = BTreeMap::new();
    plan_item_props.insert("step".to_string(), JsonSchema::String { description: None });
    plan_item_props.insert("status".to_string(), JsonSchema::String {
        description: Some("One of: pending, in_progress, completed".to_string()),
    });

    let plan_items_schema = JsonSchema::Array {
        description: Some("The list of steps".to_string()),
        items: Box::new(JsonSchema::Object {
            properties: plan_item_props,
            required: Some(vec!["step".to_string(), "status".to_string()]),
            additional_properties: Some(false.into()),
        }),
    };

    // ... 构建 ToolSpec::Function
});
```

### 处理流程

```rust
#[async_trait]
impl ToolHandler for PlanHandler {
    type Output = PlanToolOutput;

    async fn handle(&self, invocation: ToolInvocation) -> Result<Self::Output, FunctionCallError> {
        // 1. 提取 Function payload 的 arguments
        let arguments = match payload { ... };
        
        // 2. 调用 handle_update_plan 处理
        handle_update_plan(session.as_ref(), turn.as_ref(), arguments, call_id).await?;
        
        Ok(PlanToolOutput)
    }
}
```

### 计划更新处理逻辑

```rust
pub(crate) async fn handle_update_plan(
    session: &Session,
    turn_context: &TurnContext,
    arguments: String,
    _call_id: String,
) -> Result<String, FunctionCallError> {
    // 1. 检查是否在 Plan 模式（Plan 模式下禁用）
    if turn_context.collaboration_mode.mode == ModeKind::Plan {
        return Err(FunctionCallError::RespondToModel(
            "update_plan is a TODO/checklist tool and is not allowed in Plan mode".to_string(),
        ));
    }
    
    // 2. 解析参数
    let args = parse_update_plan_arguments(&arguments)?;
    
    // 3. 发送计划更新事件
    session.send_event(turn_context, EventMsg::PlanUpdate(args)).await;
    
    Ok("Plan updated".to_string())
}
```

### 输出格式化

```rust
impl ToolOutput for PlanToolOutput {
    fn log_preview(&self) -> String {
        "Plan updated".to_string()
    }

    fn success_for_logging(&self) -> bool {
        true
    }

    fn to_response_item(&self, call_id: &str, _payload: &ToolPayload) -> ResponseInputItem {
        let mut output = FunctionCallOutputPayload::from_text("Plan updated".to_string());
        output.success = Some(true);
        ResponseInputItem::FunctionCallOutput { ... }
    }

    fn code_mode_result(&self, _payload: &ToolPayload) -> JsonValue {
        JsonValue::Object(serde_json::Map::new())
    }
}
```

## 关键代码路径与文件引用

### 本文件位置
`codex-rs/core/src/tools/handlers/plan.rs`

### 依赖模块
```rust
use crate::client_common::tools::ResponsesApiTool;
use crate::client_common::tools::ToolSpec;
use crate::tools::spec::JsonSchema;
use codex_protocol::config_types::ModeKind;
use codex_protocol::models::FunctionCallOutputPayload;
use codex_protocol::plan_tool::UpdatePlanArgs;
use codex_protocol::protocol::EventMsg;
```

### 调用路径
1. 模型调用 `update_plan` 工具
2. `PlanHandler::handle` 接收调用
3. `handle_update_plan` 验证模式并解析参数
4. `session.send_event` 发送 `EventMsg::PlanUpdate`
5. 客户端接收事件并渲染计划更新

### 相关协议定义
- `codex_protocol::plan_tool::UpdatePlanArgs` - 参数结构
- `codex_protocol::protocol::EventMsg::PlanUpdate` - 事件类型

## 依赖与外部交互

### 外部模块依赖
| 模块 | 用途 |
|-----|------|
| `client_common::tools` | ToolSpec、ResponsesApiTool 定义 |
| `tools::spec::JsonSchema` | JSON Schema 构建 |
| `codex_protocol::config_types::ModeKind` | 协作模式检查 |
| `codex_protocol::protocol::EventMsg` | 事件发送 |

### 事件系统交互
- 通过 `session.send_event` 发送 `EventMsg::PlanUpdate`
- 客户端订阅事件流接收计划更新
- 不直接修改任何持久化状态

## 风险、边界与改进建议

### 潜在风险
1. **模式检查绕过**: 当前仅在 handler 中检查 Plan 模式，如果直接调用 `handle_update_plan` 可能绕过检查
2. **状态验证缺失**: 不验证计划项状态值的合法性（依赖模型遵守约定）
3. **并发更新**: 多个并发的计划更新可能导致客户端显示不一致

### 边界情况
1. **空计划数组**: 允许提交空计划（`required: ["plan"]` 但 plan 可以是空数组）
2. **重复状态**: 不验证是否只有一个 "in_progress" 项
3. **长 explanation**: 没有长度限制，可能导致事件过大

### 改进建议
1. **增强验证**:
   ```rust
   // 验证状态值合法性
   const VALID_STATUSES: &[&str] = &["pending", "in_progress", "completed"];
   
   // 验证只有一个 in_progress
   let in_progress_count = args.plan.iter()
       .filter(|item| item.status == "in_progress")
       .count();
   if in_progress_count > 1 { ... }
   ```

2. **添加长度限制**:
   ```rust
   // 限制 explanation 长度
   if explanation.len() > MAX_EXPLANATION_LEN { ... }
   
   // 限制计划项数量
   if plan.len() > MAX_PLAN_ITEMS { ... }
   ```

3. **考虑持久化**: 当前仅发送事件，考虑是否需要持久化计划状态以便恢复

4. **添加测试**: 当前文件没有配套测试文件，建议添加 `plan_tests.rs` 验证:
   - Plan 模式下的拒绝行为
   - 参数解析错误处理
   - 事件正确发送

### 设计观察
- 这是一个"标记"工具，主要价值在于强制模型显式制定计划
- 输出对模型本身没有实际用途，纯粹为客户端提供信息
- 与 Trello、Jira 等项目管理工具的集成潜力
