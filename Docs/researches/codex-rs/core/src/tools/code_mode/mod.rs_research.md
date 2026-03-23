# mod.rs 研究文档

## 场景与职责

`mod.rs` 是 Code Mode 模块的**核心协调文件**，负责整合所有子模块并提供统一的公共接口。它是整个 Code Mode 功能的入口点和中央协调器，管理工具描述生成、消息处理、嵌套工具调用等核心功能。

**核心定位**：
- 模块组织：声明并导出所有子模块
- 工具描述生成：生成 `exec` 和 `wait` 工具的完整描述
- 消息处理：处理来自 Node.js 进程的各种消息类型
- 嵌套工具管理：构建工具路由器、处理工具调用
- 常量定义：定义所有 Code Mode 相关的静态资源

## 功能点目的

### 1. 模块组织与导出
```rust
mod execute_handler;
mod process;
mod protocol;
mod service;
mod wait_handler;
mod worker;
```
子模块职责：
- `execute_handler`：`exec` 工具请求处理器
- `process`：Node.js 进程管理
- `protocol`：Rust 与 Node.js 间的消息协议
- `service`：`CodeModeService` 生命周期管理
- `wait_handler`：`wait` 工具请求处理器
- `worker`：后台工具调用工作器

### 2. 静态资源嵌入
```rust
const CODE_MODE_RUNNER_SOURCE: &str = include_str!("runner.cjs");
const CODE_MODE_BRIDGE_SOURCE: &str = include_str!("bridge.js");
const CODE_MODE_DESCRIPTION_TEMPLATE: &str = include_str!("description.md");
const CODE_MODE_WAIT_DESCRIPTION_TEMPLATE: &str = include_str!("wait_description.md");
```
- 使用 `include_str!` 在编译时嵌入静态文件
- 避免运行时文件读取，提高部署便利性

### 3. 执行状态管理
```rust
enum CodeModeSessionProgress {
    Finished(FunctionToolOutput),
    Yielded { output: FunctionToolOutput },
}

enum CodeModeExecutionStatus {
    Completed,
    Failed,
    Running(String),  // 包含 cell_id
    Terminated,
}
```
- `CodeModeSessionProgress`：表示执行的中间状态
- `CodeModeExecutionStatus`：表示脚本执行的最终状态，用于生成状态头

### 4. 工具描述生成
```rust
pub(crate) fn tool_description(enabled_tools: &[(String, String)], code_mode_only: bool) -> String
```
- 生成 `exec` 工具的完整描述
- `code_mode_only` 模式：追加所有嵌套工具的 TypeScript 声明
- 与 `code_mode_description.rs` 协作生成类型信息

### 5. 消息处理（handle_node_message）
```rust
async fn handle_node_message(
    exec: &ExecContext,
    cell_id: String,
    message: protocol::NodeToHostMessage,
    poll_max_output_tokens: Option<Option<usize>>,
    started_at: std::time::Instant,
) -> Result<CodeModeSessionProgress, String>
```
处理的消息类型：
- `ToolCall`：意外错误（应在 worker 中处理）
- `Notify`：意外错误（应在 worker 中处理）
- `Yielded`：脚本让出控制权，返回累积输出
- `Terminated`：脚本被终止，返回最终输出
- `Result`：脚本执行完成，更新存储值并返回结果

### 6. 嵌套工具调用
```rust
async fn call_nested_tool(
    exec: ExecContext,
    tool_runtime: ToolCallRuntime,
    tool_name: String,
    input: Option<JsonValue>,
    cancellation_token: CancellationToken,
) -> Result<JsonValue, FunctionCallError>
```
- 支持 MCP 工具（通过 `parse_mcp_tool_name` 识别）
- 支持普通函数工具（通过 `ToolPayload::Function`）
- 支持自由格式工具（通过 `ToolPayload::Custom`）
- 防止递归调用 `exec` 自身

## 具体技术实现

### 数据结构

**ExecContext**（执行上下文）：
```rust
#[derive(Clone)]
pub(super) struct ExecContext {
    pub(super) session: Arc<Session>,
    pub(super) turn: Arc<TurnContext>,
}
```

**常量定义**：
```rust
const CODE_MODE_PRAGMA_PREFIX: &str = "// @exec:";
const CODE_MODE_ONLY_PREFACE: &str = "Use `exec/wait` tool to run all other tools...";
pub(crate) const PUBLIC_TOOL_NAME: &str = "exec";
pub(crate) const WAIT_TOOL_NAME: &str = "wait";
pub(crate) const DEFAULT_EXEC_YIELD_TIME_MS: u64 = 10_000;
pub(crate) const DEFAULT_WAIT_YIELD_TIME_MS: u64 = 10_000;
```

### 关键流程详解

#### 工具描述生成流程
```
tool_description(enabled_tools, code_mode_only)
    │
    ├──> 读取 CODE_MODE_DESCRIPTION_TEMPLATE
    │
    ├──> code_mode_only == false?
    │       └──> 返回基础描述
    │
    └──> code_mode_only == true
            │
            ├──> 添加 CODE_MODE_ONLY_PREFACE
            ├──> 添加基础描述
            └──> 为每个 enabled_tool 生成嵌套工具引用
                    │
                    ├──> normalize_code_mode_identifier(name) → global_name
                    ├──> code_mode_tool_reference(name) → module_path, namespace, tool_key
                    └──> 格式化输出: "### `{global_name}` (`{name}`)\n{description}"
```

#### 嵌套工具构建流程
```
build_enabled_tools(exec)
    │
    ├──> build_nested_router(exec).await → ToolRouter
    │       │
    │       ├──> nested_tools_config = turn.tools_config.for_code_mode_nested_tools()
    │       ├──> mcp_tools = session.services.mcp_connection_manager.list_all_tools().await
    │       └──> ToolRouter::from_config(...)
    │
    ├──> router.specs() → Vec<ToolSpec>
    ├──> 对每个 spec: augment_tool_spec_for_code_mode(spec, true) → ToolSpec
    ├──> 过滤并映射到 EnabledTool
    ├──> 排序并去重
    └──> Vec<EnabledTool>
```

#### 消息处理流程
```
handle_node_message(exec, cell_id, message, poll_max_output_tokens, started_at)
    │
    ├──> message 匹配
    │       │
    │       ├──> ToolCall { .. } → Err("unexpected tool call response")
    │       │
    │       ├──> Notify { .. } → Err("unexpected notify message")
    │       │
    │       ├──> Yielded { content_items, .. }
    │       │       │
    │       │       ├──> output_content_items_from_json_values(content_items)
    │       │       ├──> truncate_code_mode_result(items, poll_max_output_tokens.flatten())
    │       │       ├──> prepend_script_status(Running(cell_id), elapsed)
    │       │       └──> Ok(Yielded { output })
    │       │
    │       ├──> Terminated { content_items, .. }
    │       │       │
    │       │       ├──> output_content_items_from_json_values(content_items)
    │       │       ├──> truncate_code_mode_result(items, poll_max_output_tokens.flatten())
    │       │       ├──> prepend_script_status(Terminated, elapsed)
    │       │       └──> Ok(Finished(output))
    │       │
    │       └──> Result { content_items, stored_values, error_text, max_output_tokens_per_exec_call, .. }
    │               │
    │               ├──> session.services.code_mode_service.replace_stored_values(stored_values).await
    │               ├──> output_content_items_from_json_values(content_items)
    │               ├──> 如果有 error_text，添加到 items
    │               ├──> truncate_code_mode_result(items, poll_max_output_tokens.unwrap_or(max_output_tokens_per_exec_call))
    │               ├──> prepend_script_status(Completed/Failed, elapsed)
    │               └──> Ok(Finished(output))
    │
    └──> 返回 CodeModeSessionProgress
```

### 工具负载构建

**函数工具**：
```rust
fn build_function_tool_payload(tool_name: &str, input: Option<JsonValue>) -> Result<ToolPayload, String> {
    let arguments = serialize_function_tool_arguments(tool_name, input)?;
    Ok(ToolPayload::Function { arguments })
}
```

**自由格式工具**：
```rust
fn build_freeform_tool_payload(tool_name: &str, input: Option<JsonValue>) -> Result<ToolPayload, String> {
    match input {
        Some(JsonValue::String(input)) => Ok(ToolPayload::Custom { input }),
        _ => Err(format!("tool `{tool_name}` expects a string input")),
    }
}
```

**参数序列化**：
```rust
fn serialize_function_tool_arguments(tool_name: &str, input: Option<JsonValue>) -> Result<String, String> {
    match input {
        None => Ok("{}".to_string()),
        Some(JsonValue::Object(map)) => serde_json::to_string(&JsonValue::Object(map))
            .map_err(|err| format!("failed to serialize tool `{tool_name}` arguments: {err}")),
        Some(_) => Err(format!("tool `{tool_name}` expects a JSON object for arguments")),
    }
}
```

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/core/src/tools/code_mode/mod.rs`

### 子模块
| 文件 | 用途 |
|------|------|
| `execute_handler.rs` | `exec` 工具处理器 |
| `process.rs` | Node.js 进程管理 |
| `protocol.rs` | 消息协议定义 |
| `service.rs` | CodeModeService 实现 |
| `wait_handler.rs` | `wait` 工具处理器 |
| `worker.rs` | 后台工作器 |

### 静态资源文件
| 文件 | 用途 |
|------|------|
| `runner.cjs` | Node.js 运行时代码 |
| `bridge.js` | VM 环境桥梁脚本 |
| `description.md` | `exec` 工具文档模板 |
| `wait_description.md` | `wait` 工具文档模板 |

### 外部依赖
| 文件 | 用途 |
|------|------|
| `code_mode_description.rs` | 工具描述增强、标识符规范化 |
| `parallel.rs` | `ToolCallRuntime` |
| `router.rs` | `ToolRouter`, `ToolCall` |
| `context.rs` | `FunctionToolOutput`, `ToolPayload` |
| `truncate.rs` | 输出截断功能 |

### 调用方
- `/home/sansha/Github/codex/codex-rs/core/src/tools/code_mode/execute_handler.rs`
- `/home/sansha/Github/codex/codex-rs/core/src/tools/code_mode/wait_handler.rs`
- `/home/sansha/Github/codex/codex-rs/core/src/tools/code_mode/worker.rs`
- `/home/sansha/Github/codex/codex-rs/core/src/tools/code_mode/service.rs`
- `/home/sansha/Github/codex/codex-rs/core/src/tools/code_mode/protocol.rs`

## 依赖与外部交互

### 与 CodeModeService 的交互
```rust
let service = &exec.session.services.code_mode_service;
let stored_values = service.stored_values().await;
service.replace_stored_values(stored_values).await;
```

### 与 ToolRouter 的交互
```rust
let router = build_nested_router(exec).await;
let mut out = router.specs().into_iter()
    .map(|spec| augment_tool_spec_for_code_mode(spec, /*code_mode_enabled*/ true))
    .filter_map(enabled_tool_from_spec)
    .collect::<Vec<_>>();
```

### 与 MCP 的交互
```rust
let mcp_tools = exec.session.services.mcp_connection_manager
    .read().await
    .list_all_tools().await
    .into_iter()
    .map(|(name, tool_info)| (name, tool_info.tool))
    .collect();
```

### 与 Session/TurnContext 的交互
```rust
pub(super) struct ExecContext {
    pub(super) session: Arc<Session>,
    pub(super) turn: Arc<TurnContext>,
}
```

## 风险、边界与改进建议

### 风险点

1. **递归调用风险**
   ```rust
   if tool_name == PUBLIC_TOOL_NAME {
       return Err(FunctionCallError::RespondToModel(format!(
           "{PUBLIC_TOOL_NAME} cannot invoke itself"
       )));
   }
   ```
   当前仅防止直接递归，但间接递归（A → B → exec）仍可能发生

2. **存储值竞争**
   ```rust
   exec.session.services.code_mode_service.replace_stored_values(stored_values).await;
   ```
   多个并发执行可能覆盖彼此的存储值

3. **输出截断策略**
   ```rust
   let max_output_tokens = resolve_max_tokens(max_output_tokens_per_exec_call);
   ```
   截断可能发生在不合适的边界，导致输出不完整

4. **工具名称冲突**
   ```rust
   out.sort_by(|left, right| left.tool_name.cmp(&right.tool_name));
   out.dedup_by(|left, right| left.tool_name == right.tool_name);
   ```
   去重可能导致意外丢失工具

### 边界情况

1. **空工具列表**
   - `build_enabled_tools` 返回空列表时，`tool_description` 仍生成有效描述
   - 但模型可能尝试调用不存在的工具

2. **MCP 工具解析失败**
   ```rust
   if let Some((server, tool)) = exec.session.parse_mcp_tool_name(&tool_name, &None).await
   ```
   解析失败时回退到普通工具处理

3. **超大输出**
   - `truncate_code_mode_result` 处理大输出，但可能消耗大量内存

### 改进建议

1. **存储值命名空间**
   - 为每个 cell 或 session 提供独立的存储命名空间
   - 避免并发执行之间的数据竞争

2. **递归深度限制**
   - 添加全局递归计数器，限制工具调用链深度
   - 防止无限递归导致的栈溢出

3. **更好的错误上下文**
   - 在嵌套工具调用错误中包含调用链信息
   - 便于调试复杂的工具调用场景

4. **性能优化**
   - 缓存 `build_enabled_tools` 的结果
   - 避免每次执行都重新构建工具路由器

5. **测试覆盖**
   - 添加 `mod.rs` 的单元测试（当前无直接测试）
   - 测试 `handle_node_message` 的各种消息类型
   - 测试 `build_nested_router` 的工具过滤逻辑

6. **文档改进**
   - 为 `CodeModeSessionProgress` 和 `CodeModeExecutionStatus` 添加文档注释
   - 说明各种状态转换的条件
