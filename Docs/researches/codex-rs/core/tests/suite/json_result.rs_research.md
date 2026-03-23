# json_result.rs 研究文档

## 场景与职责

`json_result.rs` 是 Codex Rust 核心库的集成测试套件，专注于验证 **JSON Schema 约束输出** 功能。该功能允许用户指定 JSON Schema，要求模型以符合该 Schema 的 JSON 格式返回结果，适用于结构化数据提取、API 响应生成等场景。

### 核心职责
1. **验证 JSON Schema 约束**：确保模型输出符合用户提供的 JSON Schema
2. **测试 GPT-5 系列模型支持**：验证 `gpt-5.1` 和 `gpt-5.1-codex` 模型的 JSON 输出功能
3. **验证请求格式**：确保正确的 `text.format` 参数被发送到 OpenAI API
4. **测试响应解析**：验证 JSON 响应被正确解析并封装为 AgentMessage

---

## 功能点目的

### 1. GPT-5 JSON 输出测试 (`codex_returns_json_result_for_gpt5`)
- **目的**：验证 `gpt-5.1` 模型支持 JSON Schema 约束输出
- **关键验证点**：
  - 请求包含正确的 `text.format` 参数
  - 格式类型为 `json_schema`
  - Schema 名称固定为 `codex_output_schema`
  - 启用严格模式 (`strict: true`)

### 2. GPT-5-Codex JSON 输出测试 (`codex_returns_json_result_for_gpt5_codex`)
- **目的**：验证 `gpt-5.1-codex` 模型支持 JSON Schema 约束输出
- **关键验证点**：与 GPT-5 测试相同，针对代码优化模型

### 3. 通用测试逻辑 (`codex_returns_json_result`)
- **目的**：提取公共测试逻辑，支持多模型测试
- **关键验证点**：
  - Mock 服务器验证请求格式
  - 响应解析为 JSON 对象
  - 验证 JSON 字段值正确性

---

## 具体技术实现

### JSON Schema 定义

```rust
const SCHEMA: &str = r#"
{
    "type": "object",
    "properties": {
        "explanation": { "type": "string" },
        "final_answer": { "type": "string" }
    },
    "required": ["explanation", "final_answer"],
    "additionalProperties": false
}
"#;
```

### 请求格式验证

测试使用自定义 Matcher 验证请求体：

```rust
let match_json_text_param = move |req: &wiremock::Request| {
    let body: serde_json::Value = serde_json::from_slice(&req.body).unwrap_or_default();
    let Some(text) = body.get("text") else { return false; };
    let Some(format) = text.get("format") else { return false; };

    format.get("name") == Some(&serde_json::Value::String("codex_output_schema".into()))
        && format.get("type") == Some(&serde_json::Value::String("json_schema".into()))
        && format.get("strict") == Some(&serde_json::Value::Bool(true))
        && format.get("schema") == Some(&expected_schema)
};
responses::mount_sse_once_match(&server, match_json_text_param, sse1).await;
```

### 请求构造

```rust
codex.submit(Op::UserTurn {
    items: vec![UserInput::Text {
        text: "hello world".into(),
        text_elements: Vec::new(),
    }],
    final_output_json_schema: Some(serde_json::from_str(SCHEMA)?),
    cwd: cwd.path().to_path_buf(),
    approval_policy: AskForApproval::Never,
    sandbox_policy: SandboxPolicy::DangerFullAccess,
    model,
    effort: None,
    summary: None,
    service_tier: None,
    collaboration_mode: None,
    personality: None,
}).await?;
```

### 响应验证

```rust
let message = wait_for_event(&codex, |ev| matches!(ev, EventMsg::AgentMessage(_))).await;
if let EventMsg::AgentMessage(message) = message {
    let json: serde_json::Value = serde_json::from_str(&message.message)?;
    assert_eq!(
        json.get("explanation"),
        Some(&serde_json::Value::String("explanation".into()))
    );
    assert_eq!(
        json.get("final_answer"),
        Some(&serde_json::Value::String("final_answer".into()))
    );
}
```

### OpenAI API 格式

发送到 OpenAI Responses API 的请求格式：

```json
{
  "text": {
    "format": {
      "type": "json_schema",
      "name": "codex_output_schema",
      "strict": true,
      "schema": {
        "type": "object",
        "properties": {
          "explanation": { "type": "string" },
          "final_answer": { "type": "string" }
        },
        "required": ["explanation", "final_answer"],
        "additionalProperties": false
      }
    }
  }
}
```

---

## 关键代码路径与文件引用

### 测试文件
- **当前文件**：`codex-rs/core/tests/suite/json_result.rs` (109 行)

### 协议定义
- **`codex-rs/protocol/src/protocol.rs`**：
  - `Op::UserTurn` 定义（包含 `final_output_json_schema` 字段）
  - `EventMsg::AgentMessage` 定义

### 实现文件
- **`codex-rs/core/src/codex.rs`**：处理 `final_output_json_schema` 并构造 API 请求

### 测试支持库
- **`codex-rs/core/tests/common/responses.rs`**：
  - `mount_sse_once_match`：带自定义 Matcher 的 Mock 挂载
  - `ev_assistant_message`、`ev_completed`：SSE 事件构造
  - `sse`：SSE 流构造
  - `start_mock_server`：Mock 服务器启动

---

## 依赖与外部交互

### 外部依赖
1. **wiremock**：HTTP Mock 服务器，用于验证请求格式
2. **tokio**：异步运行时
3. **serde_json**：JSON 序列化/反序列化
4. **pretty_assertions**：测试断言美化

### 内部依赖
1. **codex_protocol**：协议类型定义
2. **core_test_support**：测试支持库

### 网络依赖
- 使用 `skip_if_no_network!` 宏在沙箱环境中跳过测试
- 测试通过 Mock 服务器运行，不依赖真实网络

---

## 风险、边界与改进建议

### 已知风险

1. **模型限制**：
   - 仅特定模型支持 JSON Schema 输出（GPT-5 系列）
   - 旧模型可能不支持此功能

2. **Schema 复杂性限制**：
   - OpenAI API 对 JSON Schema 的复杂性有限制
   - 深层嵌套、复杂引用可能不被支持

3. **严格模式约束**：
   - `strict: true` 要求 Schema 必须严格匹配
   - 模型可能因 Schema 过于严格而无法生成有效输出

### 边界情况

1. **无效 Schema**：
   - 当前测试未覆盖无效 JSON Schema 的处理
   - 建议增加错误处理测试

2. **Schema 与提示冲突**：
   - 用户提示与 Schema 约束冲突时的行为
   - 建议增加冲突场景测试

3. **大型 Schema**：
   - 大型复杂 Schema 的性能影响
   - 建议增加性能测试

### 改进建议

1. **增加测试覆盖**：
   - 测试嵌套对象 Schema
   - 测试数组类型 Schema
   - 测试枚举类型 Schema
   - 测试 `additionalProperties: true` 场景

2. **错误场景测试**：
   - 测试模型返回无效 JSON 的处理
   - 测试 Schema 验证失败的错误提示
   - 测试网络错误时的重试逻辑

3. **多模型测试**：
   - 增加对其他支持 JSON 输出模型的测试
   - 测试不同模型的输出质量差异

4. **性能测试**：
   - 大型 Schema 的请求构造性能
   - JSON 解析性能

5. **文档改进**：
   - 提供 JSON Schema 最佳实践指南
   - 添加常见 Schema 模式示例
