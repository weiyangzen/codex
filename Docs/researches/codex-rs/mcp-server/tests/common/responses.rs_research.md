# responses.rs 研究文档

## 场景与职责

`responses.rs` 提供了构建 SSE（Server-Sent Events）响应字符串的工具函数，用于 MCP 服务器集成测试。它封装了 OpenAI Responses API 的 SSE 事件格式，使测试代码能够方便地创建模拟的模型响应，包括 shell 命令调用、补丁应用和助手消息等场景。

## 功能点目的

1. **SSE 响应构建**: 将结构化数据转换为 OpenAI API 的 SSE 格式
2. **常见场景封装**: 提供针对 shell 命令、补丁应用、助手消息等场景的专用构建函数
3. **类型安全**: 使用 `serde_json` 确保生成的 JSON 格式正确
4. **与 mock 服务器集成**: 生成的字符串可直接传递给 `create_mock_responses_server`

## 具体技术实现

### 核心函数

#### 1. Shell 命令响应

```rust
pub fn create_shell_command_sse_response(
    command: Vec<String>,           // 命令参数列表
    workdir: Option<&Path>,         // 工作目录
    timeout_ms: Option<u64>,        // 超时时间（毫秒）
    call_id: &str,                  // 函数调用 ID
) -> anyhow::Result<String>
```

实现逻辑：
```rust
pub fn create_shell_command_sse_response(
    command: Vec<String>,
    workdir: Option<&Path>,
    timeout_ms: Option<u64>,
    call_id: &str,
) -> anyhow::Result<String> {
    // 1. 将命令参数列表合并为单个字符串（使用 shell 转义）
    let command_str = shlex::try_join(command.iter().map(String::as_str))?;
    
    // 2. 构建参数 JSON
    let arguments = serde_json::to_string(&json!({
        "command": command_str,
        "workdir": workdir.map(|w| w.to_string_lossy()),
        "timeout_ms": timeout_ms,
    }))?;
    
    // 3. 构建响应 ID
    let response_id = format!("resp-{call_id}");
    
    // 4. 使用 core_test_support 的辅助函数构建 SSE 事件序列
    Ok(responses::sse(vec![
        responses::ev_response_created(&response_id),
        responses::ev_function_call(call_id, "shell_command", &arguments),
        responses::ev_completed(&response_id),
    ]))
}
```

生成的 SSE 格式示例：
```
event: response.created
data: {"type":"response.created","response":{"id":"resp-call1234"}}

event: response.output_item.done
data: {"type":"response.output_item.done","item":{"type":"function_call","call_id":"call1234","name":"shell_command","arguments":"{\"command\":\"touch test.txt\",...}"}}

event: response.completed
data: {"type":"response.completed","response":{"id":"resp-call1234",...}}
```

#### 2. 最终助手消息响应

```rust
pub fn create_final_assistant_message_sse_response(message: &str) -> anyhow::Result<String>
```

用于模拟模型返回的最终文本响应：
```rust
pub fn create_final_assistant_message_sse_response(message: &str) -> anyhow::Result<String> {
    let response_id = "resp-final";
    Ok(responses::sse(vec![
        responses::ev_response_created(response_id),
        responses::ev_assistant_message("msg-final", message),
        responses::ev_completed(response_id),
    ]))
}
```

#### 3. 补丁应用响应

```rust
pub fn create_apply_patch_sse_response(
    patch_content: &str,    // 补丁内容
    call_id: &str,          // 函数调用 ID
) -> anyhow::Result<String>
```

用于模拟模型请求应用代码补丁：
```rust
pub fn create_apply_patch_sse_response(
    patch_content: &str,
    call_id: &str,
) -> anyhow::Result<String> {
    // 使用 heredoc 格式构建命令
    let command = format!("apply_patch <<'EOF'\n{patch_content}\nEOF");
    let arguments = serde_json::to_string(&json!({ "command": command }))?;
    let response_id = format!("resp-{call_id}");
    
    Ok(responses::sse(vec![
        responses::ev_response_created(&response_id),
        responses::ev_function_call(call_id, "shell_command", &arguments),
        responses::ev_completed(&response_id),
    ]))
}
```

## 关键代码路径与文件引用

### 依赖关系

```
responses.rs
├── 使用:
│   ├── core_test_support::responses (../../../core/tests/common/responses.rs)
│   │   ├── responses::sse() - 构建 SSE 字符串
│   │   ├── responses::ev_response_created() - 响应创建事件
│   │   ├── responses::ev_function_call() - 函数调用事件
│   │   └── responses::ev_assistant_message() - 助手消息事件
│   │   └── responses::ev_completed() - 响应完成事件
│   ├── shlex - Shell 命令转义
│   └── serde_json - JSON 序列化
├── 被使用:
│   └── lib.rs (重新导出三个 create_* 函数)
└── 测试使用:
    └── tests/suite/codex_tool.rs
```

### 函数调用链

```rust
// 测试代码
let sse_response = create_shell_command_sse_response(
    vec!["touch".to_string(), "test.txt".to_string()],
    Some(Path::new("/tmp")),
    Some(5000),
    "call1234",
)?;

// 内部调用链:
// 1. shlex::try_join(["touch", "test.txt"]) -> "touch 'test.txt'"
// 2. serde_json::to_string({command, workdir, timeout_ms}) -> JSON 字符串
// 3. responses::sse([
//      ev_response_created("resp-call1234"),
//      ev_function_call("call1234", "shell_command", json_args),
//      ev_completed("resp-call1234")
//    ]) -> SSE 格式字符串
```

### 与 core_test_support 的协作

```rust
// core_test_support::responses 提供的函数:

/// Build an SSE stream body from a list of JSON events.
pub fn sse(events: Vec<Value>) -> String {
    use std::fmt::Write as _;
    let mut out = String::new();
    for ev in events {
        let kind = ev.get("type").and_then(|v| v.as_str()).unwrap();
        writeln!(&mut out, "event: {kind}").unwrap();
        if !ev.as_object().map(|o| o.len() == 1).unwrap_or(false) {
            write!(&mut out, "data: {ev}\n\n").unwrap();
        } else {
            out.push('\n');
        }
    }
    out
}

/// SSE event for response.created
pub fn ev_response_created(id: &str) -> Value {
    serde_json::json!({
        "type": "response.created",
        "response": { "id": id }
    })
}

/// SSE event for function call
pub fn ev_function_call(call_id: &str, name: &str, arguments: &str) -> Value {
    serde_json::json!({
        "type": "response.output_item.done",
        "item": {
            "type": "function_call",
            "call_id": call_id,
            "name": name,
            "arguments": arguments
        }
    })
}

/// SSE event for assistant message
pub fn ev_assistant_message(id: &str, text: &str) -> Value {
    serde_json::json!({
        "type": "response.output_item.done",
        "item": {
            "type": "message",
            "role": "assistant",
            "id": id,
            "content": [{"type": "output_text", "text": text}]
        }
    })
}

/// SSE event for response.completed
pub fn ev_completed(id: &str) -> Value {
    serde_json::json!({
        "type": "response.completed",
        "response": {
            "id": id,
            "usage": {...}
        }
    })
}
```

## 依赖与外部交互

### 外部 crate 依赖

1. **core_test_support**: 核心测试支持库
   - 路径: `../../../core/tests/common`
   - 提供: `responses` 模块的 SSE 构建函数

2. **shlex**: Shell 命令转义
   - `shlex::try_join`: 将命令参数列表合并为安全的 shell 字符串
   - 示例: `["touch", "file with space"]` -> `"touch 'file with space'"`

3. **serde_json**: JSON 序列化
   - `serde_json::to_string`: 将 Rust 值序列化为 JSON 字符串
   - `serde_json::json!`: 宏，方便构建 JSON 值

4. **std::path::Path**: 路径处理
   - 用于处理工作目录参数

### 数据流

```
Rust 数据结构
    │
    ▼
serde_json::to_string() / json!()
    │
    ▼
JSON 字符串
    │
    ▼
core_test_support::responses::sse()
    │
    ▼
SSE 格式字符串
    │
    ▼
wiremock::MockServer (模拟 OpenAI API)
    │
    ▼
MCP 服务器 (解析 SSE 事件)
```

## 风险、边界与改进建议

### 风险

1. **shlex 转义失败**:
   - `shlex::try_join` 在极端情况下可能失败（如包含 null 字符）
   - 当前使用 `?` 传播错误，但错误信息可能不够具体

2. **JSON 序列化失败**:
   - `serde_json::to_string` 理论上不会失败，但如果输入包含循环引用会 panic
   - 当前输入都是简单类型，风险较低

3. **硬编码函数名**:
   - `"shell_command"` 是硬编码的，如果 API 变更需要同步修改

4. **响应 ID 格式**:
   - `format!("resp-{call_id}")` 的格式是约定，如果服务器端变更会不匹配

### 边界情况

1. **空命令列表**:
   - `shlex::try_join` 对空迭代器返回空字符串
   - 可能导致生成无效的 shell 命令

2. **特殊字符**:
   - 补丁内容可能包含特殊字符（如 `$`、`\``）
   - heredoc 格式 `<<'EOF'` 使用单引号防止变量扩展，但仍有边界情况

3. **路径编码**:
   - `workdir.map(|w| w.to_string_lossy())` 使用平台编码
   - 非 UTF-8 路径可能导致信息丢失

4. **超时值**:
   - `timeout_ms: None` 表示无超时
   - 但某些系统可能有默认超时

### 改进建议

1. **输入验证**:
   ```rust
   pub fn create_shell_command_sse_response(
       command: Vec<String>,
       workdir: Option<&Path>,
       timeout_ms: Option<u64>,
       call_id: &str,
   ) -> anyhow::Result<String> {
       // 验证命令非空
       if command.is_empty() {
           anyhow::bail!("command cannot be empty");
       }
       
       // 验证 call_id 格式
       if call_id.is_empty() {
           anyhow::bail!("call_id cannot be empty");
       }
       
       // ... 原有实现
   }
   ```

2. **更安全的补丁内容处理**:
   ```rust
   pub fn create_apply_patch_sse_response(
       patch_content: &str,
       call_id: &str,
   ) -> anyhow::Result<String> {
       // 转义补丁内容中的特殊字符
       let escaped_content = patch_content
           .replace('\\', "\\\\")
           .replace('\'', "'\"'\"'");
       
       let command = format!("apply_patch <<'EOF'\n{escaped_content}\nEOF");
       // ...
   }
   ```

3. **支持更多响应类型**:
   ```rust
   // 添加对 reasoning、web_search 等新类型的支持
   pub fn create_reasoning_sse_response(
       summary: &[&str],
       call_id: &str,
   ) -> anyhow::Result<String> {
       let response_id = format!("resp-{call_id}");
       Ok(responses::sse(vec![
           responses::ev_response_created(&response_id),
           responses::ev_reasoning_item(call_id, summary, &[]),
           responses::ev_completed(&response_id),
       ]))
   }
   ```

4. **类型安全增强**:
   ```rust
   // 使用 newtype 模式避免字符串混淆
   pub struct CallId(pub String);
   pub struct ResponseId(pub String);
   
   pub fn create_shell_command_sse_response(
       command: Vec<String>,
       workdir: Option<&Path>,
       timeout_ms: Option<u64>,
       call_id: &CallId,
   ) -> anyhow::Result<String> {
       let response_id = ResponseId(format!("resp-{}", call_id.0));
       // ...
   }
   ```

5. **文档和示例**:
   ```rust
   /// Creates an SSE response for a shell command function call.
   ///
   /// # Example
   ///
   /// ```
   /// let response = create_shell_command_sse_response(
   ///     vec!["git".to_string(), "status".to_string()],
   ///     Some(Path::new("/repo")),
   ///     Some(30000),
   ///     "call-1",
   /// )?;
   /// ```
   pub fn create_shell_command_sse_response(...) -> anyhow::Result<String> { ... }
   ```

6. **配置化函数名**:
   ```rust
   pub enum ToolName {
       ShellCommand,
       Shell,
       ApplyPatch,
   }
   
   impl ToolName {
       fn as_str(&self) -> &'static str {
           match self {
               ToolName::ShellCommand => "shell_command",
               ToolName::Shell => "shell",
               ToolName::ApplyPatch => "apply_patch",
           }
       }
   }
   ```
