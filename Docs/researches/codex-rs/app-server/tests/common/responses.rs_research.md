# responses.rs 研究文档

## 场景与职责

该文件提供了用于测试的 SSE（Server-Sent Events）响应生成函数。在 Codex 的集成测试中，需要模拟 OpenAI Responses API 返回的各种事件流，包括：
1. 助手消息（assistant message）
2. 工具调用（function_call）
3. 权限请求（request_permissions）
4. 用户输入请求（request_user_input）
5. 命令执行（exec_command）
6. 补丁应用（apply_patch）

该模块封装了 SSE 响应的构造逻辑，使测试代码可以简洁地创建各种模拟响应。

## 功能点目的

1. **简化响应构造**：将复杂的 SSE 格式封装为简单的函数调用
2. **标准化响应结构**：确保生成的响应符合 OpenAI Responses API 格式
3. **支持多种工具调用**：覆盖 Codex 支持的主要工具类型
4. **跨平台兼容**：处理不同平台（Windows/Unix）的命令差异

## 具体技术实现

### SSE 响应构建器

依赖 `core_test_support::responses` 模块的基础设施：

```rust
// 基础 SSE 响应构建（来自 core_test_support）
pub fn sse(events: Vec<Value>) -> String
pub fn sse_response(body: String) -> ResponseTemplate
pub fn ev_response_created(id: &str) -> Value
pub fn ev_completed(id: &str) -> Value
pub fn ev_assistant_message(id: &str, text: &str) -> Value
pub fn ev_function_call(call_id: &str, name: &str, arguments: &str) -> Value
pub fn ev_apply_patch_shell_command_call_via_heredoc(call_id: &str, patch: &str) -> Value
```

### 工具调用响应生成

#### Shell 命令响应

```rust
pub fn create_shell_command_sse_response(
    command: Vec<String>,
    workdir: Option<&Path>,
    timeout_ms: Option<u64>,
    call_id: &str,
) -> anyhow::Result<String> {
    // 使用 shlex 将命令参数序列化为 shell 安全字符串
    let command_str = shlex::try_join(command.iter().map(String::as_str))?;
    
    let tool_call_arguments = serde_json::to_string(&json!({
        "command": command_str,
        "workdir": workdir.map(|w| w.to_string_lossy()),
        "timeout_ms": timeout_ms
    }))?;
    
    Ok(responses::sse(vec![
        responses::ev_response_created("resp-1"),
        responses::ev_function_call(call_id, "shell_command", &tool_call_arguments),
        responses::ev_completed("resp-1"),
    ]))
}
```

#### 最终助手消息响应

```rust
pub fn create_final_assistant_message_sse_response(message: &str) -> anyhow::Result<String> {
    Ok(responses::sse(vec![
        responses::ev_response_created("resp-1"),
        responses::ev_assistant_message("msg-1", message),
        responses::ev_completed("resp-1"),
    ]))
}
```

#### 应用补丁响应

```rust
pub fn create_apply_patch_sse_response(
    patch_content: &str,
    call_id: &str,
) -> anyhow::Result<String> {
    Ok(responses::sse(vec![
        responses::ev_response_created("resp-1"),
        responses::ev_apply_patch_shell_command_call_via_heredoc(call_id, patch_content),
        responses::ev_completed("resp-1"),
    ]))
}
```

#### 执行命令响应（跨平台）

```rust
pub fn create_exec_command_sse_response(call_id: &str) -> anyhow::Result<String> {
    // 根据平台选择不同的命令
    let (cmd, args) = if cfg!(windows) {
        ("cmd.exe", vec!["/d", "/c", "echo hi"])
    } else {
        ("/bin/sh", vec!["-c", "echo hi"])
    };
    
    let command = std::iter::once(cmd.to_string())
        .chain(args.into_iter().map(str::to_string))
        .collect::<Vec<_>>();
    
    let tool_call_arguments = serde_json::to_string(&json!({
        "cmd": command.join(" "),
        "yield_time_ms": 500
    }))?;
    
    Ok(responses::sse(vec![
        responses::ev_response_created("resp-1"),
        responses::ev_function_call(call_id, "exec_command", &tool_call_arguments),
        responses::ev_completed("resp-1"),
    ]))
}
```

#### 请求用户输入响应

```rust
pub fn create_request_user_input_sse_response(call_id: &str) -> anyhow::Result<String> {
    let tool_call_arguments = serde_json::to_string(&json!({
        "questions": [{
            "id": "confirm_path",
            "header": "Confirm",
            "question": "Proceed with the plan?",
            "options": [{
                "label": "Yes (Recommended)",
                "description": "Continue the current plan."
            }, {
                "label": "No",
                "description": "Stop and revisit the approach."
            }]
        }]
    }))?;
    
    Ok(responses::sse(vec![
        responses::ev_response_created("resp-1"),
        responses::ev_function_call(call_id, "request_user_input", &tool_call_arguments),
        responses::ev_completed("resp-1"),
    ]))
}
```

#### 请求权限响应

```rust
pub fn create_request_permissions_sse_response(call_id: &str) -> anyhow::Result<String> {
    let tool_call_arguments = serde_json::to_string(&json!({
        "reason": "Select a workspace root",
        "permissions": {
            "file_system": {
                "write": [".", "../shared"]
            }
        }
    }))?;
    
    Ok(responses::sse(vec![
        responses::ev_response_created("resp-1"),
        responses::ev_function_call(call_id, "request_permissions", &tool_call_arguments),
        responses::ev_completed("resp-1"),
    ]))
}
```

## 关键代码路径与文件引用

### 当前文件
- `codex-rs/app-server/tests/common/responses.rs`

### 导出位置
- `lib.rs`: 
```rust
pub use responses::create_apply_patch_sse_response;
pub use responses::create_exec_command_sse_response;
pub use responses::create_final_assistant_message_sse_response;
pub use responses::create_request_permissions_sse_response;
pub use responses::create_request_user_input_sse_response;
pub use responses::create_shell_command_sse_response;
```

### 依赖的上游模块
- `core_test_support::responses` - 基础 SSE 响应构建工具

### 使用示例

```rust
// 测试代码中使用示例

// 1. 简单的助手消息响应
let responses = vec![
    create_final_assistant_message_sse_response("Hello, how can I help you today?")?,
];

// 2. Shell 命令调用响应
let responses = vec![
    create_shell_command_sse_response(
        vec!["ls".to_string(), "-la".to_string()],
        Some(Path::new("/home/user")),
        Some(30000),
        "call-1",
    )?,
    create_final_assistant_message_sse_response("Done")?,
];

// 3. 应用补丁响应
let patch = r#"--- a/file.txt
+++ b/file.txt
@@ -1 +1 @@
-old
+new
"#;
let responses = vec![
    create_apply_patch_sse_response(patch, "call-1")?,
];

// 创建 mock 服务器
let server = create_mock_responses_server_sequence(responses).await;
```

## 依赖与外部交互

### 外部 crate 依赖
- `core_test_support::responses` - 基础 SSE 构建函数
- `serde_json::json` - JSON 构造宏
- `shlex` - Shell 命令安全序列化
- `std::path::Path` - 路径处理

### 响应事件序列结构

每个响应都遵循标准的事件序列：
```
event: response.created
data: {"type":"response.created","response":{"id":"resp-1"}}

event: response.output_item.done
data: {"type":"response.output_item.done","item":{...}}

event: response.completed
data: {"type":"response.completed","response":{"id":"resp-1",...}}
```

### 工具调用参数结构

#### shell_command
```json
{
  "command": "ls -la",
  "workdir": "/home/user",
  "timeout_ms": 30000
}
```

#### exec_command
```json
{
  "cmd": "/bin/sh -c 'echo hi'",
  "yield_time_ms": 500
}
```

#### request_user_input
```json
{
  "questions": [{
    "id": "confirm_path",
    "header": "Confirm",
    "question": "Proceed with the plan?",
    "options": [...]
  }]
}
```

#### request_permissions
```json
{
  "reason": "Select a workspace root",
  "permissions": {
    "file_system": {
      "write": [".", "../shared"]
    }
  }
}
```

## 风险、边界与改进建议

### 风险
1. **硬编码 ID**：响应 ID（如 `"resp-1"`、`"msg-1"`）是硬编码的，如果测试需要验证特定 ID 可能产生冲突
2. **shlex 依赖**：`shlex::try_join` 在 Windows 上可能产生不符合预期的结果（Windows 不使用 shell 风格的引号）
3. **JSON 序列化错误**：`serde_json::to_string` 可能失败，但错误处理仅使用 `?`，可能丢失上下文
4. **工具参数硬编码**：如 `exec_command` 的 `yield_time_ms: 500` 是硬编码的，不够灵活

### 边界
- 仅支持特定的工具调用类型（shell_command、exec_command、apply_patch、request_user_input、request_permissions）
- 每个响应序列固定包含 `response.created` 和 `response.completed` 事件
- 不支持自定义事件类型或扩展字段
- 不支持流式增量响应（如 `response.output_text.delta`）

### 改进建议

1. **可配置的响应 ID**：
```rust
pub fn create_final_assistant_message_sse_response_with_id(
    message: &str,
    response_id: &str,
    message_id: &str,
) -> anyhow::Result<String> { ... }
```

2. **支持增量响应**：
```rust
pub fn create_streaming_assistant_message_sse_response(
    deltas: Vec<&str>,
) -> anyhow::Result<String> {
    let mut events = vec![responses::ev_response_created("resp-1")];
    for (i, delta) in deltas.iter().enumerate() {
        events.push(responses::ev_output_text_delta(delta));
    }
    events.push(responses::ev_completed("resp-1"));
    Ok(responses::sse(events))
}
```

3. **更灵活的工具参数**：
```rust
pub struct ShellCommandParams {
    pub command: Vec<String>,
    pub workdir: Option<PathBuf>,
    pub timeout_ms: Option<u64>,
    pub env: Option<HashMap<String, String>>,  // 新增环境变量支持
}

pub fn create_shell_command_sse_response_with_params(
    params: &ShellCommandParams,
    call_id: &str,
) -> anyhow::Result<String> { ... }
```

4. **错误响应支持**：
```rust
pub fn create_error_sse_response(
    error_code: &str,
    error_message: &str,
) -> anyhow::Result<String> { ... }
```

5. **批量工具调用**：
```rust
pub fn create_multiple_tool_calls_sse_response(
    calls: Vec<(&str, &str, serde_json::Value)>,  // (call_id, tool_name, arguments)
) -> anyhow::Result<String> { ... }
```

6. **文档和示例**：
```rust
/// 创建 shell_command 工具调用的 SSE 响应。
/// 
/// # 示例
/// ```
/// let response = create_shell_command_sse_response(
///     vec!["echo".to_string(), "hello".to_string()],
///     None,
///     Some(5000),
///     "call-1",
/// )?;
/// ```
/// 
/// # 注意
/// - 使用 shlex 处理命令参数，确保 shell 安全
/// - Windows 和 Unix 的 shell 行为可能不同
pub fn create_shell_command_sse_response(...) -> anyhow::Result<String> { ... }
```
