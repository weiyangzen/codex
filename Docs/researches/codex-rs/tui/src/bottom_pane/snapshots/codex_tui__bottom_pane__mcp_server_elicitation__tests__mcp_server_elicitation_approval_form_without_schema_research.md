# MCP Server Elicitation Approval Form without Schema - 研究文档

## 1. 场景与职责

### 1.1 测试场景

此快照测试验证 **MCP 工具调用审批表单在无 Schema 或空 Schema 时的回退行为**。具体场景是：

- **触发条件**: MCP 服务器请求用户确认，但未提供具体的表单 Schema（`requested_schema` 为 `null` 或空对象 `{}`）
- **回退策略**: 系统自动生成简化的审批界面，提供基础的 Allow/Cancel 选项
- **使用场景**: 服务器仅需二元确认，无需收集额外参数

### 1.2 组件职责

`McpServerElicitationFormRequest::from_event` 在此场景中的职责：

1. **Schema 检测**: 识别 `requested_schema` 为 `null` 或空对象的情况
2. **模式切换**: 从 `FormContent` 模式切换到 `ApprovalAction` 模式
3. **默认选项生成**: 自动生成标准的 Allow/Cancel 审批选项
4. **响应区分**: 区分工具审批（仅 Allow/Cancel）和普通表单（Allow/Deny/Cancel）

---

## 2. 功能点目的

### 2.1 回退机制的目的

```rust
// 关键判断逻辑
let is_empty_object_schema = requested_schema.as_object().is_some_and(|schema| {
    schema.get("type").and_then(Value::as_str) == Some("object")
        && schema
            .get("properties")
            .and_then(Value::as_object)
            .is_some_and(serde_json::Map::is_empty)
});
let is_tool_approval_action =
    is_tool_approval && (requested_schema.is_null() || is_empty_object_schema);
```

**设计意图**：
- **向后兼容**: 支持未实现完整 Schema 的 MCP 服务器
- **简化交互**: 对于简单确认场景，避免展示复杂的表单界面
- **快速审批**: 减少用户操作步骤，提升审批效率

### 2.2 工具审批与普通表单的区别

```rust
if is_tool_approval_action {
    // 工具审批：仅 Allow + Cancel
    options.push(McpServerElicitationOption {
        label: "Allow".to_string(),
        description: Some("Run the tool and continue.".to_string()),
        value: Value::String(APPROVAL_ACCEPT_ONCE_VALUE.to_string()),
    });
    options.push(McpServerElicitationOption {
        label: "Cancel".to_string(),
        description: Some("Cancel this tool call".to_string()),
        value: Value::String(APPROVAL_CANCEL_VALUE.to_string()),
    });
} else {
    // 普通表单：Allow + Deny + Cancel
    options.extend([
        McpServerElicitationOption {
            label: "Deny".to_string(),
            description: Some("Decline this tool call and continue.".to_string()),
            value: Value::String(APPROVAL_DECLINE_VALUE.to_string()),
        },
        McpServerElicitationOption {
            label: "Cancel".to_string(),
            description: Some("Cancel this tool call".to_string()),
            value: Value::String(APPROVAL_CANCEL_VALUE.to_string()),
        },
    ]);
}
```

---

## 3. 具体技术实现

### 3.1 Schema 检测逻辑

```rust
// 检测空对象 Schema
let is_empty_object_schema = requested_schema.as_object().is_some_and(|schema| {
    // 检查类型是否为 "object"
    schema.get("type").and_then(Value::as_str) == Some("object")
        // 检查 properties 是否为空对象
        && schema
            .get("properties")
            .and_then(Value::as_object)
            .is_some_and(serde_json::Map::is_empty)
});

// 判断是否为工具审批动作
let is_tool_approval_action =
    is_tool_approval && (requested_schema.is_null() || is_empty_object_schema);
```

### 3.2 响应模式设置

```rust
let (response_mode, fields) = if requested_schema.is_null() || (is_tool_approval && is_empty_object_schema) {
    // 使用 ApprovalAction 模式
    (
        McpServerElicitationResponseMode::ApprovalAction,
        vec![McpServerElicitationField {
            id: APPROVAL_FIELD_ID.to_string(),  // "__approval"
            label: String::new(),
            prompt: String::new(),
            required: true,
            input: McpServerElicitationFieldInput::Select {
                options,  // 动态生成的选项
                default_idx: Some(0),
            },
        }],
    )
} else {
    // 使用 FormContent 模式，解析 Schema 字段
    (
        McpServerElicitationResponseMode::FormContent,
        parse_fields_from_schema(&requested_schema)?,
    )
};
```

### 3.3 常量定义

```rust
const APPROVAL_FIELD_ID: &str = "__approval";
const APPROVAL_ACCEPT_ONCE_VALUE: &str = "accept";
const APPROVAL_CANCEL_VALUE: &str = "cancel";
const APPROVAL_META_KIND_KEY: &str = "codex_approval_kind";
const APPROVAL_META_KIND_MCP_TOOL_CALL: &str = "mcp_tool_call";
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/bottom_pane/mcp_server_elicitation.rs` | 主要实现文件 |

### 4.2 关键代码路径

**1. Schema 检测路径**（行 224-232）:
```rust
let is_empty_object_schema = requested_schema.as_object().is_some_and(|schema| {
    schema.get("type").and_then(Value::as_str) == Some("object")
        && schema
            .get("properties")
            .and_then(Value::as_object)
            .is_some_and(serde_json::Map::is_empty)
});
let is_tool_approval_action =
    is_tool_approval && (requested_schema.is_null() || is_empty_object_schema);
```

**2. 选项生成路径**（行 243-293）:
```rust
if requested_schema.is_null() || (is_tool_approval && is_empty_object_schema) {
    let mut options = vec![McpServerElicitationOption { ... }];  // Allow
    // ... 条件添加 Session/Always 选项
    options.push(McpServerElicitationOption { ... });  // Cancel
    (
        McpServerElicitationResponseMode::ApprovalAction,
        vec![McpServerElicitationField { ... }],
    )
}
```

**3. 测试代码位置**（行 2342-2360）:
```rust
#[test]
fn approval_form_tool_approval_snapshot() {
    let request = McpServerElicitationFormRequest::from_event(
        thread_id,
        form_request(
            "Allow this request?",
            empty_object_schema(),  // 空对象 Schema
            tool_approval_meta(&[], None, None),  // 工具审批标记
        ),
    )
    .expect("expected approval fallback");
    let overlay = McpServerElicitationOverlay::new(request, tx, true, false, false);

    insta::assert_snapshot!(
        "mcp_server_elicitation_approval_form_without_schema",
        render_snapshot(&overlay, Rect::new(0, 0, 120, 16))
    );
}
```

**4. 相关测试 - 缺失 Schema 回退**（行 1821-1870）:
```rust
#[test]
fn missing_schema_uses_approval_actions() {
    let request = McpServerElicitationFormRequest::from_event(
        thread_id,
        form_request("Allow this request?", Value::Null, None),  // null schema
    )
    .expect("expected approval fallback");
    // 验证返回 ApprovalAction 模式
    assert_eq!(request.response_mode, McpServerElicitationResponseMode::ApprovalAction);
}
```

---

## 5. 依赖与外部交互

### 5.1 协议依赖

```rust
use codex_protocol::approvals::ElicitationRequest;
use codex_protocol::approvals::ElicitationRequestEvent;
```

### 5.2 输入数据结构

```rust
ElicitationRequest::Form {
    meta: Option<Value>,  // 包含 codex_approval_kind: "mcp_tool_call"
    message: String,      // "Allow this request?"
    requested_schema: Value,  // null 或 {"type": "object", "properties": {}}
}
```

### 5.3 事件交互

**输出事件**:
```rust
AppEvent::SubmitThreadOp {
    op: Op::ResolveElicitation {
        decision: ElicitationAction::Accept,  // 或 Cancel
        content: None,  // ApprovalAction 模式下无内容
        meta: None,     // 无持久化时无元数据
    },
}
```

---

## 6. 风险边界与改进建议

### 6.1 当前风险边界

**1. 隐式行为差异**
- **问题**: 同样的空 Schema，带/不带 `codex_approval_kind` 标记会产生不同选项
- **风险**: 开发者可能困惑为何有时显示 Deny 选项，有时不显示

**2. 消息内容依赖**
- **问题**: 回退行为完全依赖 `message` 字段的内容质量
- **风险**: 服务器提供的消息可能不足以让用户做出明智决定

**3. 无参数透明度**
- **问题**: 回退模式不显示工具调用参数
- **风险**: 用户可能在不了解具体操作的情况下批准

### 6.2 改进建议

**1. 显式模式声明**
```rust
// 建议：服务器显式声明期望的交互模式
enum ElicitationMode {
    SimpleApproval,  // 简单审批（Allow/Cancel）
    FullApproval,    // 完整审批（Allow/Deny/Cancel）
    Form,            // 表单模式
}

// 在 meta 中声明
{
    "codex_approval_kind": "mcp_tool_call",
    "elicitation_mode": "simple_approval"
}
```

**2. 增强空 Schema 警告**
```rust
// 建议：在开发/调试模式下显示警告
fn from_event(...) -> Option<Self> {
    if requested_schema.is_null() && cfg!(debug_assertions) {
        tracing::warn!(
            "MCP server {} requested elicitation without schema, falling back to approval actions",
            server_name
        );
    }
    ...
}
```

**3. 默认参数显示**
```rust
// 建议：即使无 Schema，也尝试显示基本参数
fn parse_fallback_params(meta: Option<&Value>) -> Vec<DisplayParam> {
    // 从 meta 中提取 tool_name, tool_id 等基本信息显示
    meta.and_then(|m| m.get("tool_name"))
        .map(|name| vec![DisplayParam {
            label: "Tool".to_string(),
            value: name.as_str()?.to_string(),
        }])
        .unwrap_or_default()
}
```

**4. 选项自定义**
```rust
// 建议：允许服务器自定义回退选项的标签和描述
{
    "codex_approval_kind": "mcp_tool_call",
    "fallback_options": {
        "allow_label": "Execute",
        "allow_description": "Run the database migration",
        "cancel_label": "Abort",
        "cancel_description": "Stop the operation"
    }
}
```

### 6.3 测试覆盖建议

**当前测试覆盖**:
- ✅ 空对象 Schema 回退
- ✅ null Schema 回退
- ✅ 工具审批 vs 普通表单区分

**建议补充**:
- ⬜ 部分空 Schema（有 type 但无 properties）测试
- ⬜ 无效 Schema（非 object 类型）测试
- ⬜ 回退模式与持久化选项组合测试
- ⬜ 回退模式参数解析边界测试

---

## 7. 快照内容分析

### 7.1 快照输出

```
  Field 1/1
  Allow this request?
  › 1. Allow   Run the tool and continue.
    2. Cancel  Cancel this tool call
  
  
  
  
  
  
  
  
  
  enter to submit | esc to cancel
```

### 7.2 UI 结构解析

| 行 | 内容 | 说明 |
|---|------|------|
| 1 | `Field 1/1` | 字段进度指示器 |
| 2 | `Allow this request?` | 主消息（来自服务器） |
| 3 | `› 1. Allow ...` | 选项1：允许（当前选中） |
| 4 | `2. Cancel ...` | 选项2：取消 |
| 13 | `enter to submit | esc to cancel` | 底部提示 |

### 7.3 关键观察

1. **最简界面**: 仅显示两个选项（Allow/Cancel），无 Deny 选项
2. **无参数摘要**: 不显示任何工具调用参数
3. **无持久化选项**: 测试未启用 session/always 持久化
4. **默认选中 Allow**: 第一个选项默认被选中

### 7.4 与其他快照的对比

| 特性 | 无 Schema | 有参数摘要 | 有持久化选项 |
|-----|----------|-----------|-------------|
| 选项数量 | 2 | 2 | 4 |
| 参数显示 | 无 | 有 | 无 |
| 持久化支持 | 无 | 无 | 有 |
| 使用场景 | 简单确认 | 参数透明 | 频繁调用 |
