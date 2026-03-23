# code_mode.rs 研究文档

## 文件基本信息

- **文件路径**: `codex-rs/core/tests/suite/code_mode.rs`
- **文件大小**: ~77KB (2577 行)
- **所属模块**: `codex-core` 集成测试套件
- **测试类型**: 端到端集成测试

## 场景与职责

### 核心职责

`code_mode.rs` 是 Codex 项目中 **Code Mode (代码模式)** 功能的端到端集成测试文件。Code Mode 是一个实验性功能，允许模型通过 JavaScript/Node.js 运行时执行代码，并在此过程中调用其他工具。

### 测试场景覆盖

1. **基本代码执行**: 验证 `exec` 工具可以执行 JavaScript 代码并返回结果
2. **嵌套工具调用**: 测试在 Code Mode 中调用其他工具（如 `exec_command`, `apply_patch`）
3. **并行执行**: 验证多个工具调用可以并行执行
4. **会话管理**: 测试 `yield_control` 和 `wait` 工具的协作机制
5. **MCP 工具集成**: 验证 Code Mode 可以调用 MCP (Model Context Protocol) 工具
6. **输出处理**: 测试文本、图像、结构化数据的输出
7. **错误处理**: 验证脚本错误、超时、异常情况的处理
8. **状态持久化**: 测试 `store`/`load` 跨会话数据持久化

### Code Mode 架构角色

```
┌─────────────────────────────────────────────────────────────┐
│                     Code Mode 架构                          │
├─────────────────────────────────────────────────────────────┤
│  Model Layer    │  通过 exec/wait 工具与 Code Mode 交互      │
├─────────────────────────────────────────────────────────────┤
│  Service Layer  │  CodeModeService 管理进程生命周期          │
├─────────────────────────────────────────────────────────────┤
│  Process Layer  │  Node.js 子进程 (runner.cjs)               │
├─────────────────────────────────────────────────────────────┤
│  Worker Layer   │  CodeModeWorker 处理消息路由               │
├─────────────────────────────────────────────────────────────┤
│  Tool Layer     │  嵌套工具调用 (exec_command, apply_patch)  │
└─────────────────────────────────────────────────────────────┘
```

## 功能点目的

### 1. 基础 exec 功能测试

| 测试函数 | 目的 |
|---------|------|
| `code_mode_can_return_exec_command_output` | 验证 exec 可以执行 `exec_command` 并返回结构化输出 |
| `code_mode_can_return_exec_command_output` | 验证输出包含 chunk_id、exit_code、wall_time_seconds 等字段 |

### 2. Code Mode Only 模式

| 测试函数 | 目的 |
|---------|------|
| `code_mode_only_restricts_prompt_tools` | 验证 CodeModeOnly 特性只暴露 `exec` 和 `wait` 工具 |
| `code_mode_only_can_call_nested_tools` | 验证在 CodeModeOnly 模式下仍可调用嵌套工具 |

### 3. 嵌套工具调用

| 测试函数 | 目的 |
|---------|------|
| `code_mode_update_plan_nested_tool_result_is_empty_object` | 测试 `update_plan` 返回空对象 |
| `code_mode_nested_tool_calls_can_run_in_parallel` | 验证并行工具调用使用 barrier 同步 |
| `code_mode_can_apply_patch_via_nested_tool` | 测试通过 exec 调用 `apply_patch` |

### 4. 输出控制

| 测试函数 | 目的 |
|---------|------|
| `code_mode_can_truncate_final_result_with_configured_budget` | 验证 `max_output_tokens` 截断功能 |
| `code_mode_returns_accumulated_output_when_script_fails` | 失败时仍返回已累积的输出 |
| `code_mode_wait_uses_its_own_max_tokens_budget` | wait 工具使用独立的 token 预算 |

### 5. 错误处理

| 测试函数 | 目的 |
|---------|------|
| `code_mode_exec_surfaces_handler_errors_as_exceptions` | 嵌套工具错误作为 JavaScript 异常抛出 |
| `code_mode_surfaces_text_stringify_errors` | 循环引用序列化错误处理 |

### 6. Yield/Wait 机制

| 测试函数 | 目的 |
|---------|------|
| `code_mode_can_yield_and_resume_with_wait` | 验证 yield_control + wait 协作 |
| `code_mode_yield_timeout_works_for_busy_loop` | 忙循环下的 yield 超时 |
| `code_mode_can_run_multiple_yielded_sessions` | 多会话并发 yield/resume |
| `code_mode_wait_can_terminate_and_continue` | wait 终止后可以继续执行 |
| `code_mode_wait_returns_error_for_unknown_session` | 未知 cell_id 错误处理 |
| `code_mode_background_keeps_running_on_later_turn_without_wait` | 后台会话在没有 wait 时继续运行 |

### 7. 输出辅助函数

| 测试函数 | 目的 |
|---------|------|
| `code_mode_can_output_serialized_text_via_global_helper` | `text()` 全局辅助函数 |
| `code_mode_notify_injects_additional_exec_tool_output` | `notify()` 注入额外输出 |
| `code_mode_exit_stops_script_immediately` | `exit()` 立即终止脚本 |
| `code_mode_can_output_images_via_global_helper` | `image()` 输出图像 |
| `code_mode_can_use_view_image_result_with_image_helper` | 使用 view_image 结果 |

### 8. MCP 工具集成

| 测试函数 | 目的 |
|---------|------|
| `code_mode_can_print_structured_mcp_tool_result_fields` | MCP 工具结构化结果字段 |
| `code_mode_exposes_mcp_tools_on_global_tools_object` | MCP 工具暴露在全局 `tools` 对象 |
| `code_mode_exposes_namespaced_mcp_tools_on_global_tools_object` | 命名空间 MCP 工具访问 |
| `code_mode_exposes_normalized_illegal_mcp_tool_names` | 非法工具名规范化 |
| `code_mode_can_print_content_only_mcp_tool_result_fields` | content-only MCP 结果 |
| `code_mode_can_print_error_mcp_tool_result_fields` | MCP 错误结果处理 |

### 9. 元数据与工具发现

| 测试函数 | 目的 |
|---------|------|
| `code_mode_lists_global_scope_items` | 列出全局作用域可用项 |
| `code_mode_exports_all_tools_metadata_for_builtin_tools` | `ALL_TOOLS` 内置工具元数据 |
| `code_mode_exports_all_tools_metadata_for_namespaced_mcp_tools` | MCP 工具元数据 |
| `code_mode_can_call_hidden_dynamic_tools` | 调用隐藏动态工具 |

### 10. 状态持久化

| 测试函数 | 目的 |
|---------|------|
| `code_mode_can_store_and_load_values_across_turns` | `store()`/`load()` 跨会话持久化 |

## 具体技术实现

### 关键流程

#### 1. 测试初始化流程

```rust
async fn run_code_mode_turn(
    server: &MockServer,
    prompt: &str,
    code: &str,
    include_apply_patch: bool,
) -> Result<(TestCodex, ResponseMock)> {
    // 1. 构建测试 Codex 实例，启用 CodeMode 特性
    let mut builder = test_codex()
        .with_model("test-gpt-5.1-codex")
        .with_config(move |config| {
            let _ = config.features.enable(Feature::CodeMode);
            config.include_apply_patch_tool = include_apply_patch;
        });
    let test = builder.build(server).await?;

    // 2. 挂载 SSE mock 响应
    responses::mount_sse_once(server, sse(vec![
        ev_response_created("resp-1"),
        ev_custom_tool_call("call-1", "exec", code),
        ev_completed("resp-1"),
    ])).await;

    // 3. 挂载后续响应
    let second_mock = responses::mount_sse_once(...).await;

    // 4. 提交用户输入
    test.submit_turn(prompt).await?;
    Ok((test, second_mock))
}
```

#### 2. MCP 工具测试初始化

```rust
async fn run_code_mode_turn_with_rmcp(
    server: &MockServer,
    prompt: &str,
    code: &str,
) -> Result<(TestCodex, ResponseMock)> {
    let rmcp_test_server_bin = stdio_server_bin()?;
    let mut builder = test_codex()
        .with_model("test-gpt-5.1-codex")
        .with_config(move |config| {
            let _ = config.features.enable(Feature::CodeMode);
            
            // 配置 MCP 服务器
            let mut servers = config.mcp_servers.get().clone();
            servers.insert(
                "rmcp".to_string(),
                McpServerConfig {
                    transport: McpServerTransportConfig::Stdio {
                        command: rmcp_test_server_bin,
                        args: Vec::new(),
                        env: Some(HashMap::from([(
                            "MCP_TEST_VALUE".to_string(),
                            "propagated-env".to_string(),
                        )])),
                        ...
                    },
                    ...
                },
            );
            config.mcp_servers.set(servers).expect("...");
        });
    ...
}
```

#### 3. Yield/Wait 测试模式

```rust
// 典型的 yield/wait 测试模式
let code = format!(
    r#"
text("phase 1");
yield_control();
{phase_2_wait}  // 等待文件存在的轮询代码
text("phase 2");
"#
);

// 第一次提交 - 执行到 yield
responses::mount_sse_once(server, sse(vec![
    ev_response_created("resp-1"),
    ev_custom_tool_call("call-1", "exec", &code),
    ev_completed("resp-1"),
])).await;
test.submit_turn("start").await?;

// 提取 cell_id
let cell_id = extract_running_cell_id(text_item(&first_items, 0));

// 写入信号文件触发继续
fs::write(&phase_2_gate, "ready")?;

// 第二次提交 - wait 恢复执行
responses::mount_sse_once(server, sse(vec![
    ev_response_created("resp-3"),
    responses::ev_function_call(
        "call-2",
        "wait",
        &serde_json::to_string(&json!({
            "cell_id": cell_id.clone(),
            "yield_time_ms": 1_000,
        }))?,
    ),
    ev_completed("resp-3"),
])).await;
test.submit_turn("wait").await?;
```

### 关键数据结构

#### 1. 辅助函数

```rust
// 提取自定义工具输出项
fn custom_tool_output_items(req: &ResponsesRequest, call_id: &str) -> Vec<Value> {
    match req.custom_tool_call_output(call_id).get("output") {
        Some(Value::Array(items)) => items.clone(),
        Some(Value::String(text)) => {
            vec![serde_json::json!({ "type": "input_text", "text": text })]
        }
        _ => panic!("..."),
    }
}

// 提取函数工具输出项
fn function_tool_output_items(req: &ResponsesRequest, call_id: &str) -> Vec<Value> {
    match req.function_call_output(call_id).get("output") {
        Some(Value::Array(items)) => items.clone(),
        Some(Value::String(text)) => {
            vec![serde_json::json!({ "type": "input_text", "text": text })]
        }
        _ => panic!("..."),
    }
}

// 提取文本项
fn text_item(items: &[Value], index: usize) -> &str {
    items[index]
        .get("text")
        .and_then(Value::as_str)
        .expect("content item should be input_text")
}

// 提取运行中的 cell ID
fn extract_running_cell_id(text: &str) -> String {
    text.strip_prefix("Script running with cell ID ")
        .and_then(|rest| rest.split('\n').next())
        .expect("running header should contain a cell ID")
        .to_string()
}
```

#### 2. 等待文件生成的辅助代码

```rust
fn wait_for_file_source(path: &Path) -> Result<String> {
    let quoted_path = shlex::try_join([path.to_string_lossy().as_ref()])?;
    let command = format!("if [ -f {quoted_path} ]; then printf ready; fi");
    Ok(format!(
        r#"while ((await tools.exec_command({{ cmd: {command:?} }})).output !== "ready") {{
}}"#
    ))
}
```

### 协议与命令

#### 1. SSE 事件构造

```rust
// 来自 core_test_support::responses 模块
pub fn ev_custom_tool_call(call_id: &str, name: &str, input: &str) -> Value {
    serde_json::json!({
        "type": "response.output_item.done",
        "item": {
            "type": "custom_tool_call",
            "call_id": call_id,
            "name": name,
            "input": input
        }
    })
}

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
```

#### 2. Code Mode JavaScript API

```javascript
// 全局辅助函数
text(value)       // 序列化并输出文本
image(url)        // 输出图像
notify(message)   // 注入额外输出到上下文
exit()            // 立即终止脚本
yield_control()   // 让出控制权，等待 wait 恢复
store(key, value) // 跨会话存储数据
load(key)         // 加载存储的数据

// 全局对象
tools             // 可调用其他工具的对象
ALL_TOOLS         // 所有可用工具的元数据数组
```

#### 3. Code Mode Pragma 配置

```javascript
// @exec: {"max_output_tokens": 6}
// @exec: {"yield_time_ms": 100}
```

## 关键代码路径与文件引用

### 被测试的核心代码

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/core/src/tools/code_mode/mod.rs` | Code Mode 模块入口，定义核心类型和函数 |
| `codex-rs/core/src/tools/code_mode/service.rs` | CodeModeService 管理进程生命周期 |
| `codex-rs/core/src/tools/code_mode/process.rs` | Node.js 子进程管理 |
| `codex-rs/core/src/tools/code_mode/worker.rs` | CodeModeWorker 消息处理 |
| `codex-rs/core/src/tools/code_mode/execute_handler.rs` | exec 工具调用处理 |
| `codex-rs/core/src/tools/code_mode/wait_handler.rs` | wait 工具调用处理 |
| `codex-rs/core/src/tools/code_mode/protocol.rs` | 主机-Node 进程间协议 |
| `codex-rs/core/src/tools/code_mode/runner.cjs` | Node.js 运行时代码 |
| `codex-rs/core/src/tools/code_mode/bridge.js` | JavaScript 桥接代码 |
| `codex-rs/core/src/tools/code_mode/description.md` | exec 工具描述模板 |
| `codex-rs/core/src/tools/code_mode/wait_description.md` | wait 工具描述模板 |

### 测试依赖

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/core/tests/common/lib.rs` | 测试公共库入口 |
| `codex-rs/core/tests/common/responses.rs` | Mock SSE 响应服务器 |
| `codex-rs/core/tests/common/test_codex.rs` | TestCodex 测试辅助结构 |
| `codex-rs/core/src/features.rs` | Feature 特性标志定义 |

### 关键类型引用

```rust
// Feature 特性标志
codex_core::features::Feature::CodeMode
codex_core::features::Feature::CodeModeOnly

// MCP 配置
codex_core::config::types::McpServerConfig
codex_core::config::types::McpServerTransportConfig

// 协议类型
codex_protocol::protocol::EventMsg
codex_protocol::protocol::Op
codex_protocol::dynamic_tools::DynamicToolSpec

// 测试辅助
core_test_support::test_codex::TestCodex
core_test_support::responses::ResponseMock
core_test_support::responses::ResponsesRequest
```

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|-----|------|
| `wiremock` | HTTP Mock 服务器，模拟 OpenAI Responses API |
| `tokio` | 异步运行时 |
| `serde_json` | JSON 序列化/反序列化 |
| `tempfile` | 临时目录管理 |
| `base64` | Base64 编解码 |
| `shlex` | Shell 命令引用处理 |
| `pretty_assertions` | 更好的测试断言输出 |

### 内部模块依赖

```
code_mode.rs
├── core_test_support (测试公共库)
│   ├── responses (Mock SSE 服务器)
│   ├── test_codex (测试辅助)
│   └── wait_for_event (事件等待)
├── codex_core (核心库)
│   ├── config (配置)
│   ├── features (特性标志)
│   └── tools::code_mode (被测试代码)
└── codex_protocol (协议定义)
    ├── protocol (事件/操作)
    └── dynamic_tools (动态工具)
```

### 网络依赖

测试使用 `skip_if_no_network!` 宏检查网络可用性：

```rust
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn code_mode_can_return_exec_command_output() -> Result<()> {
    skip_if_no_network!(Ok(()));  // 无网络时跳过
    ...
}
```

### 平台特定处理

```rust
#[cfg_attr(windows, ignore = "no exec_command on Windows")]
```

Windows 平台跳过某些测试（`exec_command` 不可用）。

## 风险、边界与改进建议

### 当前风险

1. **测试稳定性**
   - 依赖 timing 的测试（如并行工具调用）可能在慢速环境 flaky
   - 文件系统轮询依赖 `tokio::time::sleep`，可能不稳定

2. **网络依赖**
   - 所有测试都需要网络（`skip_if_no_network!`）
   - Mock 服务器虽然本地运行，但仍需要网络栈

3. **平台差异**
   - Windows 平台大量测试被跳过
   - 不同平台 shell 命令行为差异

4. **测试复杂度**
   - 测试代码本身复杂，涉及多轮 SSE 响应挂载
   - 状态管理复杂（cell_id 提取、会话跟踪）

### 边界情况

1. **Token 预算**
   - `max_output_tokens` 截断边界
   - wait 工具独立的 token 预算

2. **会话生命周期**
   - Yield 后会话超时
   - 未知 cell_id 处理
   - 终止后重新执行

3. **MCP 工具**
   - 非法工具名规范化边界
   - 命名空间冲突处理

### 改进建议

1. **测试优化**
   ```rust
   // 建议：提取公共的 yield/wait 测试模式
   async fn run_yield_resume_test(
       phases: Vec<&str>,
       gates: Vec<PathBuf>,
   ) -> Result<()> { ... }
   ```

2. **减少平台跳过**
   - 为 Windows 实现 `exec_command` 替代方案
   - 使用跨平台命令抽象

3. **增强断言**
   - 当前使用字符串匹配，建议使用结构化断言
   - 添加更多中间状态验证

4. **文档改进**
   - 添加更多测试场景图示
   - 解释 Code Mode 与其他工具的关系

5. **性能优化**
   - 并行测试执行（已使用 `multi_thread`）
   - 减少不必要的文件系统轮询

### 相关 TODO

- 部分测试标记为 `#[ignore = "TODO once we have a delegate that can ask for approvals"]`
- 需要关注 Code Mode 与审批流程的集成
