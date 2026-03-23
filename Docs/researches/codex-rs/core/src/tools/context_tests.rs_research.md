# context_tests.rs 研究文档

## 场景与职责

`context_tests.rs` 是 `context.rs` 的配套测试模块，负责验证工具上下文、工具输出转换和遥测预览等核心功能的正确性。测试覆盖了多种工具负载类型的响应转换、Code Mode 结果序列化以及遥测预览的截断逻辑。

## 功能点目的

### 测试覆盖范围

1. **工具负载响应转换测试**
   - 自定义工具调用的往返转换
   - 函数工具负载的响应保持
   - 工具搜索负载的往返转换

2. **MCP 工具 Code Mode 结果测试**
   - 验证 MCP 工具结果的完整序列化
   - 确保所有字段（content, structuredContent, isError, _meta）正确传递

3. **内容项处理测试**
   - 多内容项（文本+图片）的正确处理
   - 文本提取和合并逻辑

4. **遥测预览测试**
   - 正常内容的完整保留
   - 字节级别的截断
   - 行数级别的截断

5. **Exec 命令输出格式化测试**
   - 完整响应格式的验证
   - 截断输出的正确处理

## 具体技术实现

### 测试用例详情

#### 1. `custom_tool_calls_should_roundtrip_as_custom_outputs`
```rust
// 验证自定义工具调用的往返转换
let payload = ToolPayload::Custom { input: "patch".to_string() };
let response = FunctionToolOutput::from_text("patched".to_string(), Some(true))
    .to_response_item("call-42", &payload);

// 期望: ResponseInputItem::CustomToolCallOutput
// - call_id: "call-42"
// - output.body.to_text(): "patched"
// - output.success: Some(true)
```
**验证点**：
- 自定义工具负载正确转换为 CustomToolCallOutput
- 文本内容和成功状态保留

#### 2. `function_payloads_remain_function_outputs`
```rust
// 验证函数工具负载保持 FunctionCallOutput 类型
let payload = ToolPayload::Function { arguments: "{}".to_string() };
let response = FunctionToolOutput::from_text("ok".to_string(), Some(true))
    .to_response_item("fn-1", &payload);

// 期望: ResponseInputItem::FunctionCallOutput
```
**验证点**：
- Function 负载不转换为 CustomToolCallOutput
- 保持原有的 FunctionCallOutput 类型

#### 3. `mcp_code_mode_result_serializes_full_call_tool_result`
```rust
// 验证 MCP 工具结果的完整序列化
let output = CallToolResult {
    content: vec![json!({"type": "text", "text": "ignored"})],
    structured_content: Some(json!({"threadId": "thread_123", "content": "done"})),
    is_error: Some(false),
    meta: Some(json!({"source": "mcp"})),
};

let result = output.code_mode_result(&ToolPayload::Mcp { ... });

// 期望: 完整的 JSON 对象包含所有字段
```
**验证点**：
- content 数组完整保留
- structuredContent 对象正确序列化
- isError 布尔值正确映射（蛇形命名）
- _meta 字段正确映射（带下划线前缀）

#### 4. `custom_tool_calls_can_derive_text_from_content_items`
```rust
// 验证多内容项处理
let response = FunctionToolOutput::from_content(
    vec![
        FunctionCallOutputContentItem::InputText { text: "line 1".to_string() },
        FunctionCallOutputContentItem::InputImage { image_url: "data:image/png;base64,AAA".to_string(), detail: None },
        FunctionCallOutputContentItem::InputText { text: "line 2".to_string() },
    ],
    Some(true),
).to_response_item("call-99", &payload);

// 期望: output.body.to_text() == "line 1\nline 2"
```
**验证点**：
- 多文本项使用换行符连接
- 图片项不包含在文本输出中
- 所有内容项保留在 content_items 中

#### 5. `tool_search_payloads_roundtrip_as_tool_search_outputs`
```rust
// 验证工具搜索负载的往返
let payload = ToolPayload::ToolSearch { 
    arguments: SearchToolCallParams { query: "calendar".to_string(), limit: None }
};
let response = ToolSearchOutput { tools: vec![...] }
    .to_response_item("search-1", &payload);

// 期望: ResponseInputItem::ToolSearchOutput
// - status: "completed"
// - execution: "client"
```
**验证点**：
- ToolSearch 负载返回 ToolSearchOutput 类型
- 工具和参数正确序列化

#### 6. `log_preview_uses_content_items_when_plain_text_is_missing`
```rust
// 验证遥测预览使用内容项
let output = FunctionToolOutput::from_content(
    vec![FunctionCallOutputContentItem::InputText { text: "preview".to_string() }],
    Some(true),
);

assert_eq!(output.log_preview(), "preview");
```

#### 7. `telemetry_preview_returns_original_within_limits`
```rust
// 验证短内容完整保留
let content = "short output";
assert_eq!(telemetry_preview(content), content);
```

#### 8. `telemetry_preview_truncates_by_bytes`
```rust
// 验证字节截断
let content = "x".repeat(TELEMETRY_PREVIEW_MAX_BYTES + 8);
let preview = telemetry_preview(&content);

assert!(preview.contains(TELEMETRY_PREVIEW_TRUNCATION_NOTICE));
assert!(preview.len() <= TELEMETRY_PREVIEW_MAX_BYTES + TELEMETRY_PREVIEW_TRUNCATION_NOTICE.len() + 1);
```

#### 9. `telemetry_preview_truncates_by_lines`
```rust
// 验证行数截断
let content = (0..(TELEMETRY_PREVIEW_MAX_LINES + 5))
    .map(|idx| format!("line {idx}"))
    .collect::<Vec<_>>()
    .join("\n");

let preview = telemetry_preview(&content);
let lines: Vec<&str> = preview.lines().collect();

assert!(lines.len() <= TELEMETRY_PREVIEW_MAX_LINES + 1);
assert_eq!(lines.last(), Some(&TELEMETRY_PREVIEW_TRUNCATION_NOTICE));
```

#### 10. `exec_command_tool_output_formats_truncated_response`
```rust
// 验证 Exec 命令输出的完整格式
let response = ExecCommandToolOutput {
    event_call_id: "call-42".to_string(),
    chunk_id: "abc123".to_string(),
    wall_time: Duration::from_millis(1250),
    raw_output: b"token one token two token three token four token five".to_vec(),
    max_output_tokens: Some(4),
    process_id: None,
    exit_code: Some(0),
    original_token_count: Some(10),
    session_command: Some(vec!["/bin/zsh", "-lc", "rm -rf /tmp/example.sqlite"]),
}.to_response_item("call-42", &payload);

// 使用正则验证格式包含：
// - Command: /bin/zsh -lc 'rm -rf /tmp/example.sqlite'
// - Chunk ID: abc123
// - Wall time: X.XXXX seconds
// - Process exited with code 0
// - Original token count: 10
// - Output: (truncated content)
```

## 关键代码路径与文件引用

| 测试函数 | 被测类型/函数 | 所在文件 |
|----------|--------------|----------|
| `custom_tool_calls_should_roundtrip_as_custom_outputs` | `FunctionToolOutput::to_response_item` | context.rs:197 |
| `function_payloads_remain_function_outputs` | `FunctionToolOutput::to_response_item` | context.rs:197 |
| `mcp_code_mode_result_serializes_full_call_tool_result` | `CallToolResult::code_mode_result` | context.rs:110 |
| `custom_tool_calls_can_derive_text_from_content_items` | `FunctionToolOutput::from_content` | context.rs:171 |
| `tool_search_payloads_roundtrip_as_tool_search_outputs` | `ToolSearchOutput::to_response_item` | context.rs:140 |
| `log_preview_uses_content_items_when_plain_text_is_missing` | `FunctionToolOutput::log_preview` | context.rs:186 |
| `telemetry_preview_returns_original_within_limits` | `telemetry_preview` | context.rs:466 |
| `telemetry_preview_truncates_by_bytes` | `telemetry_preview` | context.rs:466 |
| `telemetry_preview_truncates_by_lines` | `telemetry_preview` | context.rs:466 |
| `exec_command_tool_output_formats_truncated_response` | `ExecCommandToolOutput::to_response_item` | context.rs:297 |

## 依赖与外部交互

### 测试依赖

| 依赖 | 用途 |
|------|------|
| `super::*` | 被测模块的所有公有项 |
| `core_test_support::assert_regex_match` | 正则匹配断言 |
| `pretty_assertions::assert_eq` | 清晰的差异输出 |
| `serde_json::json!` | 构造 JSON 测试数据 |

### 辅助函数

```rust
// 创建模拟的 BlockedRequest
fn denied_blocked_request(host: &str) -> BlockedRequest {
    BlockedRequest::new(BlockedRequestArgs {
        host: host.to_string(),
        reason: "not_allowed".to_string(),
        // ...
    })
}
```

## 风险、边界与改进建议

### 当前测试覆盖缺口

1. **未覆盖的输出类型**
   - `AbortedToolOutput` 的各种场景
   - `ApplyPatchToolOutput` 的 Code Mode 结果（返回空对象）
   - `ExecCommandToolOutput` 的多种边界情况（无 exit_code、无 process_id 等）

2. **未覆盖的错误路径**
   - 序列化失败的处理
   - 无效 UTF-8 的处理
   - 超大输出的处理

3. **未覆盖的 payload 类型组合**
   - `ToolPayload::LocalShell` 的响应转换
   - `ToolPayload::Mcp` 的各种错误场景

### 改进建议

1. **添加边界测试**
   ```rust
   #[test]
   fn exec_output_handles_missing_optional_fields() {
       let output = ExecCommandToolOutput {
           exit_code: None,
           process_id: None,
           // ...
       };
       // 验证格式正确，不 panic
   }
   ```

2. **添加错误场景测试**
   ```rust
   #[test]
   fn aborted_tool_output_handles_mcp_payload() {
       let payload = ToolPayload::Mcp { ... };
       let aborted = AbortedToolOutput { message: "cancelled".to_string() };
       // 验证返回 McpToolCallOutput 类型
   }
   ```

3. **添加性能测试**
   ```rust
   #[test]
   fn telemetry_preview_handles_very_large_content() {
       let content = "x".repeat(10_000_000); // 10MB
       // 验证在合理时间内完成，不 OOM
   }
   ```

4. **改进测试组织**
   - 使用 `mod` 分组相关测试（如 `telemetry_tests`、`response_tests`）
   - 添加测试辅助函数减少重复代码

### 测试风格建议

当前测试使用了 `pretty_assertions` 和 `assert_regex_match`，这是良好的实践。建议：

1. **使用参数化测试**（如果 Rust 版本支持或引入 `rstest`）
   ```rust
   #[rstest]
   #[case(ToolPayload::Function { ... }, ResponseInputItem::FunctionCallOutput)]
   #[case(ToolPayload::Custom { ... }, ResponseInputItem::CustomToolCallOutput)]
   fn payload_roundtrip(#[case] payload: ToolPayload, #[case] expected_variant: ...) {
       // 测试逻辑
   }
   ```

2. **添加测试文档注释**
   ```rust
   /// Test that MCP tool results are fully serialized in Code Mode.
   /// 
   /// This ensures structured content and metadata are preserved
   /// when returning results to the model in Code Mode context.
   #[test]
   fn mcp_code_mode_result_serializes_full_call_tool_result() {
       // ...
   }
   ```
