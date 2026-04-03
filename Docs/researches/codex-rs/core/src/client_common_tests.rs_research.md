# client_common_tests.rs 研究文档

## 文件信息
- **路径**: `codex-rs/core/src/client_common_tests.rs`
- **大小**: ~7,672 bytes
- **所属模块**: `codex-core` (作为 `client_common.rs` 的测试模块)

---

## 一、场景与职责

`client_common_tests.rs` 是 `client_common.rs` 的单元测试文件，通过 `#[path = "client_common_tests.rs"]` 属性在 `client_common.rs` 的 `tests` 模块中引入。该测试文件负责验证：

1. **ResponsesApiRequest 序列化**: 确保 API 请求结构正确序列化为 JSON
2. **TextControls 配置**: 验证文本详细程度和输出模式的序列化行为
3. **ServiceTier 序列化**: 验证服务层级（如 flex）的正确序列化
4. **Shell 输出重序列化**: 验证 `reserialize_shell_outputs` 函数的正确性
5. **ToolSearch 命名空间序列化**: 验证延迟加载工具的命名空间结构

### 测试范围
```
┌─────────────────────────────────────────────────────────────┐
│              client_common.rs 测试覆盖                        │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────┐   │
│  │         client_common_tests.rs                      │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │   │
│  │  │ 序列化测试  │  │ Shell重序列 │  │ 工具序列化  │ │   │
│  │  │  (4 tests)  │  │  (1 test)   │  │  (1 test)   │ │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘ │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

## 二、功能点目的

### 2.1 序列化测试组

**目的**: 验证 `ResponsesApiRequest` 结构体的 JSON 序列化行为

**测试用例**:
| 测试名 | 验证内容 |
|--------|----------|
| `serializes_text_verbosity_when_set` | `text.verbosity` 字段序列化为小写字符串 |
| `serializes_text_schema_with_strict_format` | 输出模式 JSON Schema 的完整结构 |
| `omits_text_when_not_set` | `Option` 字段为 `None` 时完全省略 |
| `serializes_flex_service_tier_when_set` | `service_tier` 序列化为小写字符串 |

### 2.2 Shell 输出重序列化测试

**目的**: 验证 `reserialize_shell_outputs` 函数正确转换 Shell 输出格式

**测试场景**:
- `FunctionCall` + `FunctionCallOutput` 组合
- `CustomToolCall` + `CustomToolCallOutput` 组合
- 工具名匹配（`shell`, `container.exec`, `apply_patch`）

### 2.3 工具序列化测试

**目的**: 验证 `ToolSearchOutputTool::Namespace` 的复杂序列化结构

**测试内容**:
- 命名空间结构的正确序列化
- 延迟加载标记（`defer_loading: true`）的正确传递

---

## 三、具体技术实现

### 3.1 测试结构

```rust
// 引入被测模块的私有项
use codex_api::ResponsesApiRequest;
use codex_api::common::{OpenAiVerbosity, TextControls};
use codex_api::create_text_param_for_request;
use codex_protocol::config_types::ServiceTier;
use codex_protocol::models::FunctionCallOutputPayload;
use pretty_assertions::assert_eq;

use super::*;  // 引入 client_common.rs 的所有导出项
```

### 3.2 序列化测试详解

#### text.verbosity 序列化
```rust
#[test]
fn serializes_text_verbosity_when_set() {
    let req = ResponsesApiRequest {
        model: "gpt-5.1".to_string(),
        text: Some(TextControls {
            verbosity: Some(OpenAiVerbosity::Low),  // 枚举值
            format: None,
        }),
        // ... 其他字段
    };

    let v = serde_json::to_value(&req).expect("json");
    assert_eq!(
        v.get("text")
            .and_then(|t| t.get("verbosity"))
            .and_then(|s| s.as_str()),
        Some("low")  // 验证序列化为小写
    );
}
```

#### JSON Schema 序列化
```rust
#[test]
fn serializes_text_schema_with_strict_format() {
    let schema = serde_json::json!({
        "type": "object",
        "properties": { "answer": {"type": "string"} },
        "required": ["answer"],
    });
    let text_controls = create_text_param_for_request(None, &Some(schema.clone()))
        .expect("text controls");

    let req = ResponsesApiRequest {
        text: Some(text_controls),
        // ...
    };

    let v = serde_json::to_value(&req).expect("json");
    let format = v.get("text").expect("text field").get("format").expect("format field");
    
    // 验证完整结构
    assert_eq!(format.get("name"), Some(&serde_json::Value::String("codex_output_schema".into())));
    assert_eq!(format.get("type"), Some(&serde_json::Value::String("json_schema".into())));
    assert_eq!(format.get("strict"), Some(&serde_json::Value::Bool(true)));
    assert_eq!(format.get("schema"), Some(&schema));
}
```

### 3.3 Shell 输出重序列化测试详解

```rust
#[test]
fn reserializes_shell_outputs_for_function_and_custom_tool_calls() {
    // 原始 JSON 输出
    let raw_output = r#"{"output":"hello","metadata":{"exit_code":0,"duration_seconds":0.5}}"#;
    // 期望的结构化文本
    let expected_output = "Exit code: 0\nWall time: 0.5 seconds\nOutput:\nhello";
    
    let mut items = vec![
        // 1. Shell 函数调用
        ResponseItem::FunctionCall {
            id: None,
            name: "shell".to_string(),
            namespace: None,
            arguments: "{}".to_string(),
            call_id: "call-1".to_string(),
        },
        // 2. Shell 函数输出（应被转换）
        ResponseItem::FunctionCallOutput {
            call_id: "call-1".to_string(),
            output: FunctionCallOutputPayload::from_text(raw_output.to_string()),
        },
        // 3. apply_patch 自定义工具调用
        ResponseItem::CustomToolCall {
            id: None,
            status: None,
            call_id: "call-2".to_string(),
            name: "apply_patch".to_string(),
            input: "*** Begin Patch".to_string(),
        },
        // 4. apply_patch 自定义工具输出（应被转换）
        ResponseItem::CustomToolCallOutput {
            call_id: "call-2".to_string(),
            name: None,
            output: FunctionCallOutputPayload::from_text(raw_output.to_string()),
        },
    ];

    // 调用被测函数
    reserialize_shell_outputs(&mut items);

    // 验证输出项已被转换
    assert_eq!(
        items,
        vec![
            ResponseItem::FunctionCall { /* ... */ },
            ResponseItem::FunctionCallOutput {
                call_id: "call-1".to_string(),
                output: FunctionCallOutputPayload::from_text(expected_output.to_string()),
            },
            ResponseItem::CustomToolCall { /* ... */ },
            ResponseItem::CustomToolCallOutput {
                call_id: "call-2".to_string(),
                name: None,
                output: FunctionCallOutputPayload::from_text(expected_output.to_string()),
            },
        ]
    );
}
```

### 3.4 命名空间工具序列化测试

```rust
#[test]
fn tool_search_output_namespace_serializes_with_deferred_child_tools() {
    let namespace = tools::ToolSearchOutputTool::Namespace(tools::ResponsesApiNamespace {
        name: "mcp__codex_apps__calendar".to_string(),
        description: "Plan events".to_string(),
        tools: vec![tools::ResponsesApiNamespaceTool::Function(
            tools::ResponsesApiTool {
                name: "create_event".to_string(),
                description: "Create a calendar event.".to_string(),
                strict: false,
                defer_loading: Some(true),  // 延迟加载标记
                parameters: crate::tools::spec::JsonSchema::Object {
                    properties: Default::default(),
                    required: None,
                    additional_properties: None,
                },
                output_schema: None,
            },
        )],
    });

    let value = serde_json::to_value(namespace).expect("serialize namespace");

    // 验证完整 JSON 结构
    assert_eq!(
        value,
        serde_json::json!({
            "type": "namespace",
            "name": "mcp__codex_apps__calendar",
            "description": "Plan events",
            "tools": [
                {
                    "type": "function",
                    "name": "create_event",
                    "description": "Create a calendar event.",
                    "strict": false,
                    "defer_loading": true,  // 验证延迟加载标记
                    "parameters": {
                        "type": "object",
                        "properties": {}
                    }
                }
            ]
        })
    );
}
```

---

## 四、关键代码路径与文件引用

### 4.1 被测代码路径

| 被测代码 | 测试覆盖 |
|----------|----------|
| `client_common.rs` 中的 `reserialize_shell_outputs` | `reserializes_shell_outputs_for_function_and_custom_tool_calls` |
| `client_common.rs` 中的 `ToolSpec` 序列化 | `tool_search_output_namespace_serializes_with_deferred_child_tools` |
| `codex_api::ResponsesApiRequest` | 4 个序列化测试 |
| `codex_api::create_text_param_for_request` | `serializes_text_schema_with_strict_format` |

### 4.2 依赖项

```rust
// 测试框架
use pretty_assertions::assert_eq;  // 提供清晰的差异输出

// API 类型
use codex_api::ResponsesApiRequest;
use codex_api::common::{OpenAiVerbosity, TextControls};
use codex_api::create_text_param_for_request;

// 协议类型
use codex_protocol::config_types::ServiceTier;
use codex_protocol::models::FunctionCallOutputPayload;

// 被测模块
use super::*;  // 引入 client_common.rs 的所有导出
```

---

## 五、依赖与外部交互

### 5.1 与 codex_api 的交互

测试直接依赖于 `codex_api` crate 的类型：
```rust
use codex_api::ResponsesApiRequest;
use codex_api::common::{OpenAiVerbosity, TextControls};
```

这些类型定义了与 OpenAI API 通信的数据结构，测试验证它们正确序列化为 API 期望的 JSON 格式。

### 5.2 与 codex_protocol 的交互

```rust
use codex_protocol::models::FunctionCallOutputPayload;
```

用于构造测试数据中的输出负载。

### 5.3 与 tools/spec 的交互

```rust
use crate::tools::spec::JsonSchema;
```

在命名空间工具测试中用于构造工具参数模式。

---

## 六、风险、边界与改进建议

### 6.1 当前测试覆盖分析

| 功能 | 覆盖状态 | 说明 |
|------|----------|------|
| `Prompt::get_formatted_input` | ❌ 未覆盖 | 主要逻辑未测试 |
| `ToolSpec::name()` | ❌ 未覆盖 | 工具名提取方法未测试 |
| `ToolSpec` 所有变体序列化 | ⚠️ 部分覆盖 | 仅测试了 Namespace 变体 |
| WebSearch 配置转换 | ❌ 未覆盖 | `From<ConfigWebSearchFilters>` 等未测试 |
| `ResponseStream` | ❌ 未覆盖 | Stream trait 实现未测试 |

### 6.2 边界条件测试缺失

当前测试未覆盖以下边界条件：

1. **空输入**: `reserialize_shell_outputs` 对空 `items` 的处理
2. **无效 JSON**: Shell 输出不是有效 JSON 时的行为
3. **缺失 metadata 字段**: JSON 缺少 `exit_code` 或 `duration_seconds`
4. **call_id 不匹配**: 调用和输出的 `call_id` 不一致
5. **重复 call_id**: 多个输出使用相同 `call_id`
6. **非 Shell 工具**: 其他工具类型的输出不应被修改

### 6.3 改进建议

#### 1. 添加 Prompt 测试
```rust
#[test]
fn prompt_formats_input_with_shell_reserialization() {
    let prompt = Prompt {
        input: vec![/* shell call and output */],
        tools: vec![ToolSpec::Freeform(FreeformTool {
            name: "apply_patch".to_string(),
            // ...
        })],
        // ...
    };
    
    let formatted = prompt.get_formatted_input();
    // 验证输出已被重序列化
}
```

#### 2. 添加边界条件测试
```rust
#[test]
fn reserialize_shell_outputs_handles_invalid_json() {
    let mut items = vec![
        ResponseItem::FunctionCall {
            name: "shell".to_string(),
            call_id: "call-1".to_string(),
            // ...
        },
        ResponseItem::FunctionCallOutput {
            call_id: "call-1".to_string(),
            output: FunctionCallOutputPayload::from_text("not valid json".to_string()),
        },
    ];
    
    // 不应 panic，应保持原样
    reserialize_shell_outputs(&mut items);
    
    // 验证输出未被修改
    match &items[1] {
        ResponseItem::FunctionCallOutput { output, .. } => {
            assert_eq!(output.text_content(), Some("not valid json"));
        }
        _ => panic!("unexpected item type"),
    }
}
```

#### 3. 添加 ToolSpec 全覆盖测试
```rust
#[test]
fn all_tool_spec_variants_serialize_correctly() {
    let tools = vec![
        ToolSpec::Function(/* ... */),
        ToolSpec::ToolSearch { /* ... */ },
        ToolSpec::LocalShell {},
        ToolSpec::ImageGeneration { /* ... */ },
        ToolSpec::WebSearch { /* ... */ },
        ToolSpec::Freeform(/* ... */),
    ];
    
    for tool in tools {
        let json = serde_json::to_value(&tool).expect("should serialize");
        // 验证每个变体的序列化结构
    }
}
```

#### 4. 添加 ResponseStream 测试
```rust
#[tokio::test]
async fn response_stream_polls_from_channel() {
    let (tx, rx) = tokio::sync::mpsc::channel(10);
    let mut stream = ResponseStream { rx_event: rx };
    
    tx.send(Ok(ResponseEvent::Completed { /* ... */ })).await.unwrap();
    drop(tx);  // 关闭通道
    
    // 验证 Stream 正确产生事件
    let event = stream.next().await;
    assert!(event.is_some());
    
    // 验证通道关闭后 Stream 结束
    let event = stream.next().await;
    assert!(event.is_none());
}
```

### 6.4 测试组织改进

建议将测试按功能分组：
```rust
mod serialization_tests {
    use super::*;
    // 所有序列化测试
}

mod shell_reserialization_tests {
    use super::*;
    // Shell 输出重序列化测试
}

mod tool_tests {
    use super::*;
    // 工具相关测试
}
```
