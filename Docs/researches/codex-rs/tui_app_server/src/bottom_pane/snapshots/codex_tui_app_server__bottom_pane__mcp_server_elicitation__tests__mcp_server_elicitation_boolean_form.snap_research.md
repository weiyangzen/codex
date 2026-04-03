# MCP Server Elicitation Boolean Form 研究文档

## 场景与职责

该 Snapshot 展示了 **MCP Server Elicitation** 组件在处理布尔类型表单字段时的 UI 表现。这是基于 JSON Schema 的动态表单渲染能力的一部分，用于收集用户的布尔类型确认或选择。

**核心职责：**
- 根据 JSON Schema 动态渲染布尔类型输入控件
- 提供 True/False 二元选择界面
- 支持必填字段验证（显示 "1 required unanswered"）

**典型应用场景：**
- 用户确认操作（"Are you sure?"）
- 功能开关选择
- 布尔类型的配置项设置

---

## 功能点目的

### 1. 布尔字段渲染
将 JSON Schema 中的 `boolean` 类型转换为可视化的 True/False 选项：

```json
{
  "type": "object",
  "properties": {
    "confirmed": {
      "type": "boolean",
      "title": "Confirm",
      "description": "Approve the pending action."
    }
  },
  "required": ["confirmed"]
}
```

### 2. 字段元信息展示
- **标题**：`Confirm`
- **描述**：`Approve the pending action.`
- **进度**：`Field 1/1 (1 required unanswered)` - 显示有 1 个必填字段未回答

### 3. 选项呈现
- **True**：表示确认/是
- **False**：表示否认/否

### 4. 键盘交互
- 上下箭头切换选项
- 空格键或回车键选择
- 数字键 `1` 或 `2` 快速选择
- `esc` 取消

---

## 具体技术实现

### 布尔 Schema 定义

```rust
// 来自 codex_app_server_protocol
pub struct McpElicitationBooleanSchema {
    pub title: Option<String>,
    pub description: Option<String>,
    pub default: Option<bool>,  // 默认值
}
```

### 布尔字段解析

```rust
fn parse_field(
    id: &str,
    property: McpElicitationPrimitiveSchema,
    required: bool,
) -> Option<McpServerElicitationField> {
    match property {
        McpElicitationPrimitiveSchema::Boolean(schema) => {
            let label = schema.title.unwrap_or_else(|| id.to_string());
            let prompt = schema.description.unwrap_or_else(|| label.clone());
            
            // 根据默认值确定默认选中项
            let default_idx = schema.default.map(|value| if value { 0 } else { 1 });
            
            // 构建 True/False 选项
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

### 字段输入类型枚举

```rust
enum McpServerElicitationFieldInput {
    Select {
        options: Vec<McpServerElicitationOption>,
        default_idx: Option<usize>,
    },
    Text {
        secret: bool,  // 布尔类型不使用此变体
    },
}

struct McpServerElicitationOption {
    label: String,
    description: Option<String>,
    value: Value,  // 对于布尔类型是 Value::Bool(true/false)
}
```

### 必填字段追踪

```rust
fn required_unanswered_count(&self) -> usize {
    self.request
        .fields
        .iter()
        .enumerate()
        .filter(|(idx, field)| field.required && self.field_value(*idx).is_none())
        .count()
}

// 在进度显示中使用
let progress_line = if self.field_count() > 0 {
    let idx = self.current_index() + 1;
    let total = self.field_count();
    let base = format!("Field {idx}/{total}");
    let unanswered = self.required_unanswered_count();
    if unanswered > 0 {
        format!("{base} ({unanswered} required unanswered)")
    } else {
        base
    }
};
```

### 字段值提取

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
            // 对于布尔类型，返回 Value::Bool(true) 或 Value::Bool(false)
        }
        // ...
    }
}
```

---

## 关键代码路径与文件引用

### 主要实现文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/bottom_pane/mcp_server_elicitation.rs` | MCP Server Elicitation 核心实现 |

### 关键函数位置

```rust
// 布尔字段解析
fn parse_field(id: &str, property: McpElicitationPrimitiveSchema, required: bool)
    -> Option<McpServerElicitationField>
// 位于 ~579-660 行，布尔处理在 ~596-621 行

// Schema 解析入口
fn parse_fields_from_schema(requested_schema: &Value) -> Option<Vec<McpServerElicitationField>>
// 位于 ~552-577 行

// 字段值提取
fn field_value(&self, idx: usize) -> Option<Value>
// 位于 ~1067-1087 行
```

### 测试验证

```rust
#[test]
fn parses_boolean_form_request() {
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

    assert_eq!(request.fields, vec![McpServerElicitationField {
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
    }]);
}
```

---

## 依赖与外部交互

### 协议依赖

| 依赖 | 用途 |
|-----|------|
| `codex_app_server_protocol::McpElicitationPrimitiveSchema` | Schema 类型定义 |
| `codex_app_server_protocol::McpElicitationBooleanSchema` | 布尔 Schema 结构 |
| `serde_json::Value` | 表单值序列化 |

### 与其他类型的对比

| 类型 | 渲染方式 | 输入控件 |
|-----|---------|---------|
| `string` | 文本输入框 | `ChatComposer` |
| `boolean` | True/False 选项 | 选择列表（当前） |
| `enum` (legacy) | 单选列表 | 选择列表 |
| `enum` (singleSelect) | 单选列表 | 选择列表 |
| `number` | 不支持 | - |
| `enum` (multiSelect) | 不支持 | - |

### 表单提交流程

```rust
fn submit_answers(&mut self) {
    // 验证必填字段
    if let Some(idx) = self.first_required_unanswered_index() {
        self.validation_error = Some("Answer required fields before submitting.".to_string());
        self.jump_to_field(idx);
        return;
    }
    
    // 构建响应内容
    let content = self
        .request
        .fields
        .iter()
        .enumerate()
        .filter_map(|(idx, field)| self.field_value(idx).map(|value| (field.id.clone(), value)))
        .collect::<serde_json::Map<_, _>>();
    
    // 发送响应
    self.app_event_tx.resolve_elicitation(
        self.request.thread_id,
        self.request.server_name.clone(),
        self.request.request_id.clone(),
        ElicitationAction::Accept,
        Some(Value::Object(content)),  // 包含 {"confirmed": true/false}
        None,
    );
}
```

---

## 风险、边界与改进建议

### 当前限制

1. **True/False 语义不够直观**
   - "True"/"False" 对于非技术用户可能不够友好
   - 建议：支持自定义标签，如 "Yes"/"No" 或 "Enable"/"Disable"

2. **无默认值提示**
   - 当前 snapshot 显示 `default_idx: None`，用户不知道是否有默认值
   - 建议：在 UI 上标记默认值

3. **与审批模式混淆**
   - 布尔表单和简单审批表单在视觉上相似
   - 建议：增加视觉区分（如表单类型的图标或标签）

### 边界情况

| 场景 | 当前行为 |
|-----|---------|
| 布尔字段有默认值 `true` | 默认选中 "True" |
| 布尔字段有默认值 `false` | 默认选中 "False" |
| 布尔字段无默认值 | 无默认选中，显示 "required unanswered" |
| 多个布尔字段 | 支持多字段导航（←/→ 或 Ctrl+P/N） |
| 布尔字段可选（非必填） | 可以不选择，提交时该字段不包含在响应中 |

### 改进建议

1. **自定义标签支持**
   ```json
   {
     "type": "boolean",
     "title": "Confirm",
     "enumNames": ["Yes, proceed", "No, cancel"]
   }
   ```

2. **开关样式替代**
   ```rust
   // 建议：对于布尔类型，提供开关/复选框样式
   // 而非 True/False 选项列表
   [ ] Confirm  // 复选框
   ```

3. **单键快捷选择**
   ```rust
   // 建议：Y/N 快捷键
   KeyCode::Char('y') | KeyCode::Char('Y') => select_true(),
   KeyCode::Char('n') | KeyCode::Char('N') => select_false(),
   ```

4. **视觉增强**
   ```rust
   // True 使用绿色，False 使用红色
   let true_label = if selected { "True".green() } else { "True".into() };
   let false_label = if selected { "False".red() } else { "False".into() };
   ```

5. **与审批模式统一**
   - 考虑将简单审批（Allow/Cancel）也实现为特殊的布尔表单
   - 统一代码路径，减少维护成本
