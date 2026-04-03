# MCP Server Elicitation Boolean Form - 研究文档

## 1. 场景与职责

### 1.1 测试场景

此快照测试验证 **MCP 服务器表单中布尔类型字段的渲染和交互**。具体场景是：

- **触发条件**: MCP 服务器需要收集用户输入，且 Schema 中包含 `boolean` 类型字段
- **UI 表现**: 布尔字段渲染为单选列表，提供 "True" 和 "False" 两个选项
- **使用场景**: 需要用户确认/否认某个条件，如 "是否确认删除？"、"是否启用功能？"

### 1.2 组件职责

`McpServerElicitationOverlay` 组件在此场景中的职责：

1. **Schema 解析**: 从 JSON Schema 中解析布尔类型字段定义
2. **选项生成**: 将布尔字段转换为 True/False 单选选项
3. **默认值处理**: 支持 Schema 中定义的 `default` 值
4. **值收集**: 用户选择后，将布尔值收集到表单响应中

---

## 2. 功能点目的

### 2.1 布尔字段的设计目的

```rust
// Schema 示例
{
    "type": "object",
    "properties": {
        "confirmed": {
            "type": "boolean",
            "title": "Confirm",
            "description": "Approve the pending action.",
            // "default": true  // 可选默认值
        }
    },
    "required": ["confirmed"]
}
```

**设计意图**：
- **明确选择**: 强制用户做出明确的 true/false 选择，避免模糊输入
- **防误操作**: 相比文本输入，单选列表减少输入错误
- **快速交互**: 支持数字键（1/2）快速选择，提升效率

### 2.2 与审批模式的区别

| 特性 | 布尔表单 | 审批模式 |
|-----|---------|---------|
| Schema | 完整的字段定义 | null 或空对象 |
| 响应内容 | 字段 ID + 布尔值 | 预设动作 |
| 灵活性 | 高（可扩展更多字段） | 低（固定选项） |
| 使用场景 | 复杂表单的一部分 | 简单二元确认 |

---

## 3. 具体技术实现

### 3.1 布尔字段解析

```rust
fn parse_field(
    id: &str,
    property: McpElicitationPrimitiveSchema,
    required: bool,
) -> Option<McpServerElicitationField> {
    match property {
        McpElicitationPrimitiveSchema::Boolean(schema) => {
            // 提取标签和提示
            let label = schema.title.unwrap_or_else(|| id.to_string());
            let prompt = schema.description.unwrap_or_else(|| label.clone());
            
            // 计算默认选项索引
            let default_idx = schema.default.map(|value| if value { 0 } else { 1 });
            
            // 生成 True/False 选项
            let options = [true, false]
                .into_iter()
                .map(|value| {
                    let label = if value { "True" } else { "False" }.to_string();
                    McpServerElicitationOption {
                        label,
                        description: None,
                        value: Value::Bool(value),
                    }
                })
                .collect();
            
            Some(McpServerElicitationField {
                id: id.to_string(),
                label,
                prompt,
                required,
                input: McpServerElicitationFieldInput::Select {
                    options,
                    default_idx,
                },
            })
        }
        // ... 其他类型处理
    }
}
```

### 3.2 响应模式

```rust
enum McpServerElicitationResponseMode {
    FormContent,     // 布尔表单使用此模式
    ApprovalAction,  // 审批模式使用此模式
}
```

### 3.3 表单提交

```rust
fn submit_answers(&mut self) {
    // FormContent 模式下收集所有字段值
    let content = self
        .request
        .fields
        .iter()
        .enumerate()
        .filter_map(|(idx, field)| {
            self.field_value(idx).map(|value| (field.id.clone(), value))
        })
        .collect::<serde_json::Map<_, _>>();
    
    self.app_event_tx.send(AppEvent::SubmitThreadOp {
        op: Op::ResolveElicitation {
            decision: ElicitationAction::Accept,
            content: Some(Value::Object(content)),  // 包含 {"confirmed": true/false}
            meta: None,
        },
    });
}
```

### 3.4 字段值提取

```rust
fn field_value(&self, idx: usize) -> Option<Value> {
    let field = self.request.fields.get(idx)?;
    let answer = self.answers.get(idx)?;
    
    match &field.input {
        McpServerElicitationFieldInput::Select { options, .. } => {
            if !answer.answer_committed {
                return None;
            }
            let selected_idx = answer.selection.selected_idx?;
            options.get(selected_idx).map(|option| option.value.clone())
        }
        // ... 文本输入处理
    }
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/bottom_pane/mcp_server_elicitation.rs` | 主要实现文件 |
| `codex_app_server_protocol` | 协议类型定义（`McpElicitationPrimitiveSchema`） |

### 4.2 关键代码路径

**1. Schema 解析入口**（行 502-527）:
```rust
fn parse_fields_from_schema(requested_schema: &Value) -> Option<Vec<McpServerElicitationField>> {
    let schema = requested_schema.as_object()?;
    if schema.get("type").and_then(Value::as_str) != Some("object") {
        return None;
    }
    let required = schema
        .get("required")
        .and_then(Value::as_array)
        ...
    let properties = schema.get("properties")?.as_object()?;
    for (id, property_schema) in properties {
        let property = serde_json::from_value::<McpElicitationPrimitiveSchema>(...)?;
        fields.push(parse_field(id, property, required.contains(id))?);
    }
}
```

**2. 布尔字段解析**（行 546-570）:
```rust
McpElicitationPrimitiveSchema::Boolean(schema) => {
    let label = schema.title.unwrap_or_else(|| id.to_string());
    let prompt = schema.description.unwrap_or_else(|| label.clone());
    let default_idx = schema.default.map(|value| if value { 0 } else { 1 });
    let options = [true, false]
        .into_iter()
        .map(|value| {
            let label = if value { "True" } else { "False" }.to_string();
            McpServerElicitationOption { label, description: None, value: Value::Bool(value) }
        })
        .collect();
    Some(McpServerElicitationField { ... })
}
```

**3. 选项渲染**（行 873-895）:
```rust
fn option_rows(&self) -> Vec<GenericDisplayRow> {
    let selected_idx = self.selected_option_index();
    self.current_options()
        .iter()
        .enumerate()
        .map(|(idx, option)| {
            let prefix = if selected_idx.is_some_and(|selected| selected == idx) {
                '›'  // 选中标记
            } else {
                ' '
            };
            let number = idx + 1;
            let prefix_label = format!("{prefix} {number}. ");
            ...
        })
        .collect()
}
```

**4. 测试代码位置**（行 2312-2340）:
```rust
#[test]
fn boolean_form_snapshot() {
    let request = McpServerElicitationFormRequest::from_event(
        thread_id,
        form_request(
            "Allow this request?",
            serde_json::json!({
                "type": "object",
                "properties": {
                    "confirmed": {
                        "type": "boolean",
                        "title": "Confirm",
                        "description": "Approve the pending action.",
                    }
                },
                "required": ["confirmed"],
            }),
            None,
        ),
    )
    .expect("expected supported form");
    let overlay = McpServerElicitationOverlay::new(request, tx, true, false, false);

    insta::assert_snapshot!(
        "mcp_server_elicitation_boolean_form",
        render_snapshot(&overlay, Rect::new(0, 0, 120, 16))
    );
}
```

**5. 解析验证测试**（行 1741-1797）:
```rust
#[test]
fn parses_boolean_form_request() {
    let request = McpServerElicitationFormRequest::from_event(
        thread_id,
        form_request(...),  // 布尔字段 Schema
    )
    .expect("expected supported form");

    assert_eq!(
        request,
        McpServerElicitationFormRequest {
            response_mode: McpServerElicitationResponseMode::FormContent,
            fields: vec![McpServerElicitationField {
                id: "confirmed".to_string(),
                label: "Confirm".to_string(),
                prompt: "Approve the pending action.".to_string(),
                required: true,
                input: McpServerElicitationFieldInput::Select {
                    options: vec![
                        McpServerElicitationOption {
                            label: "True".to_string(),
                            description: None,
                            value: Value::Bool(true),
                        },
                        McpServerElicitationOption {
                            label: "False".to_string(),
                            description: None,
                            value: Value::Bool(false),
                        },
                    ],
                    default_idx: None,
                },
            }],
            ...
        }
    );
}
```

---

## 5. 依赖与外部交互

### 5.1 协议依赖

```rust
use codex_app_server_protocol::McpElicitationPrimitiveSchema;
use codex_protocol::approvals::ElicitationAction;
use codex_protocol::protocol::Op;
```

### 5.2 布尔 Schema 定义

```rust
// 来自 codex_app_server_protocol
struct McpElicitationBooleanSchema {
    title: Option<String>,
    description: Option<String>,
    default: Option<bool>,  // 可选默认值
}
```

### 5.3 事件交互

**输出事件**:
```rust
AppEvent::SubmitThreadOp {
    op: Op::ResolveElicitation {
        decision: ElicitationAction::Accept,
        content: Some(Value::Object({
            "confirmed": Value::Bool(true)  // 或 false
        })),
        meta: None,
    },
}
```

---

## 6. 风险边界与改进建议

### 6.1 当前风险边界

**1. 标签固定**
- **问题**: 布尔选项固定显示为 "True"/"False"
- **风险**: 在某些语境下不够直观（如 "启用/禁用" 比 "True/False" 更易理解）

**2. 无描述支持**
- **问题**: 布尔选项的 `description` 字段被硬编码为 `None`
- **风险**: 用户可能不理解选择 True/False 的具体含义

**3. 必填验证**
- **问题**: 布尔字段标记为 `required` 时，用户必须做出选择
- **风险**: 如果用户未选择就提交，会触发验证错误

### 6.2 改进建议

**1. 自定义选项标签**
```rust
// 建议：在 Schema 中支持自定义选项标签
{
    "type": "boolean",
    "title": "Enable feature",
    "enumLabels": {
        "true": "Enable",
        "false": "Disable"
    }
}

// 实现
let options = [true, false]
    .into_iter()
    .map(|value| {
        let label = schema.enum_labels
            .and_then(|labels| labels.get(value))
            .unwrap_or_else(|| if value { "True" } else { "False" });
        ...
    })
    .collect();
```

**2. 选项描述支持**
```rust
// 建议：为每个选项添加描述
McpServerElicitationOption {
    label: "True".to_string(),
    description: Some(schema.true_description.unwrap_or("Yes, proceed".to_string())),
    value: Value::Bool(true),
}
```

**3. 三态布尔支持**
```rust
// 建议：支持 null/undefined 作为第三状态（未选择）
enum BooleanValue {
    True,
    False,
    Unselected,  // 用于可选布尔字段
}

// Schema 扩展
{
    "type": ["boolean", "null"],
    "default": null
}
```

**4. 开关组件替代**
```rust
// 建议：对于单布尔字段，使用开关而非列表
fn render_boolean_switch(&self, area: Rect, buf: &mut Buffer) {
    let switch = if self.boolean_value {
        "[●] Enabled"
    } else {
        "[○] Disabled"
    };
    // 使用空格键切换
}
```

### 6.3 测试覆盖建议

**当前测试覆盖**:
- ✅ 布尔字段解析
- ✅ 布尔表单渲染
- ✅ 布尔值提交

**建议补充**:
- ⬜ 带默认值的布尔字段测试
- ⬜ 可选布尔字段（非 required）测试
- ⬜ 多字段表单中的布尔字段测试
- ⬜ 数字键选择布尔选项测试
- ⬜ 布尔字段与其他类型字段组合测试

---

## 7. 快照内容分析

### 7.1 快照输出

```
  Field 1/1 (1 required unanswered)
  Allow this request?
  
  Confirm
  Approve the pending action.
  › 1. True
    2. False
  
  
  
  
  
  
  
  enter to submit | esc to cancel
```

### 7.2 UI 结构解析

| 行 | 内容 | 说明 |
|---|------|------|
| 1 | `Field 1/1 (1 required unanswered)` | 字段进度 + 必填未答提示 |
| 2 | `Allow this request?` | 主消息 |
| 4 | `Confirm` | 字段标签（来自 `title`） |
| 5 | `Approve the pending action.` | 字段提示（来自 `description`） |
| 6 | `› 1. True` | 选项1：True（当前选中） |
| 7 | `2. False` | 选项2：False |
| 14 | `enter to submit | esc to cancel` | 底部提示 |

### 7.3 关键观察

1. **必填提示**: 标题显示 `(1 required unanswered)`，提醒用户必须回答
2. **层级结构**: 消息 → 字段标签 → 字段描述 → 选项列表
3. **选中状态**: 选项 `1. True` 前有 `›` 标记，表示当前选中
4. **无默认值**: 测试 Schema 未提供 `default`，所以无默认选中

### 7.4 与审批模式的对比

| 特性 | 布尔表单 | 审批模式 |
|-----|---------|---------|
| 响应模式 | `FormContent` | `ApprovalAction` |
| 字段 ID | `confirmed` | `__approval` |
| 选项来源 | Schema 解析 | 硬编码生成 |
| 响应内容 | `{"confirmed": true}` | `decision: Accept` |
| 可扩展性 | 支持多字段 | 固定结构 |
| UI 层级 | 消息 + 字段标签 + 描述 + 选项 | 消息 + 选项 |
