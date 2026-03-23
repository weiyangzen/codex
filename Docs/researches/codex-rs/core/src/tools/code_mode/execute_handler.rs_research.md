# execute_handler.rs 研究文档

## 场景与职责

`execute_handler.rs` 是 Code Mode **`exec` 工具的核心处理器**，负责处理模型发起的 JavaScript 代码执行请求。它是 Rust 端与 Node.js 运行时之间的协调层，管理代码执行的完整生命周期。

**核心定位**：
- 实现 `ToolHandler` trait，作为 `exec` 工具的入口点
- 解析用户输入（支持可选的 pragma 指令）
- 协调代码执行流程（构建环境、发送请求、处理响应）
- 管理执行上下文（session、turn、cell_id、request_id）

## 功能点目的

### 1. 参数解析（parse_freeform_args）
```rust
fn parse_freeform_args(input: &str) -> Result<CodeModeExecArgs, FunctionCallError>
```
- 支持原始 JavaScript 代码（无 pragma）
- 支持带 pragma 的代码：`// @exec: {"yield_time_ms": 10000, "max_output_tokens": 1000}`
- 验证 pragma 参数（必须是 JSON 对象，仅支持 `yield_time_ms` 和 `max_output_tokens`）
- 验证数值范围（必须是非负安全整数，即 ≤ 2^53-1）

### 2. 代码执行（execute 方法）
```rust
async fn execute(
    &self,
    session: Arc<Session>,
    turn: Arc<TurnContext>,
    call_id: String,
    code: String,
) -> Result<FunctionToolOutput, FunctionCallError>
```
执行流程：
1. 解析输入参数（提取 pragma 和实际代码）
2. 构建执行上下文（`ExecContext`）
3. 获取可用工具列表（`build_enabled_tools`）
4. 获取存储的值（`stored_values`）
5. 构建完整源码（`build_source`，合并 bridge.js、工具列表和用户代码）
6. 分配 cell_id 和 request_id
7. 确保 Node.js 进程已启动（`ensure_started`）
8. 发送 `Start` 消息到 Node.js 进程
9. 处理 Node.js 返回的消息（`handle_node_message`）
10. 返回执行结果或错误

### 3. 执行状态管理
- `CodeModeSessionProgress`：跟踪执行进度（Finished 或 Yielded）
- 处理多种响应类型：
  - `Result`：执行完成（成功或失败）
  - `Yielded`：执行让出控制权（仍在运行）
  - `Terminated`：执行被终止

## 具体技术实现

### 数据结构

**CodeModeExecPragma**（pragma 配置）：
```rust
#[derive(Debug, Default, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]  // 拒绝未知字段
struct CodeModeExecPragma {
    #[serde(default)]
    yield_time_ms: Option<u64>,
    #[serde(default)]
    max_output_tokens: Option<usize>,
}
```

**CodeModeExecArgs**（解析后的参数）：
```rust
#[derive(Debug, PartialEq, Eq)]
struct CodeModeExecArgs {
    code: String,                    // 实际 JavaScript 代码
    yield_time_ms: Option<u64>,      // 让出时间（毫秒）
    max_output_tokens: Option<usize>, // 最大输出 token 数
}
```

**常量定义**：
```rust
const MAX_JS_SAFE_INTEGER: u64 = (1_u64 << 53) - 1;  // 9007199254740991
```

### 关键流程详解

#### 参数解析流程
```
输入字符串
    │
    ├──> 空检查 → Err("exec expects raw JavaScript source text")
    │
    ├──> 分割第一行和剩余部分
    │
    ├──> 第一行以 "// @exec:" 开头？
    │       │
    │       ├──> 否 → 返回整个输入作为 code
    │       │
    │       └──> 是 → 解析 pragma
    │               │
    │               ├──> 剩余部分为空？→ Err("pragma must be followed by JavaScript source")
    │               │
    │               ├──> pragma 为空？→ Err("pragma must be a JSON object")
    │               │
    │               ├──> 解析 JSON → 验证字段名
    │               │
    │               ├──> 验证数值范围（≤ MAX_JS_SAFE_INTEGER）
    │               │
    │               └──> 返回 CodeModeExecArgs
    │
    └──> 返回 CodeModeExecArgs（无 pragma）
```

#### 执行流程
```
execute()
    │
    ├──> parse_freeform_args(&code) → CodeModeExecArgs
    │
    ├──> 构建 ExecContext { session, turn }
    │
    ├──> build_enabled_tools(&exec).await → Vec<EnabledTool>
    │
    ├──> service.stored_values().await → HashMap<String, JsonValue>
    │
    ├──> build_source(&args.code, &enabled_tools) → String（完整源码）
    │
    ├──> service.allocate_cell_id().await → String
    │
    ├──> service.allocate_request_id().await → String
    │
    ├──> service.ensure_started().await → OwnedMutexGuard<Option<CodeModeProcess>>
    │
    ├──> 构建 HostToNodeMessage::Start { ... }
    │
    ├──> process.send(&request_id, &message).await → NodeToHostMessage
    │
    ├──> handle_node_message(&exec, cell_id, message, None, started_at).await
    │       → CodeModeSessionProgress
    │
    └──> 匹配 progress 类型返回结果
```

### 错误处理策略

| 错误场景 | 处理方式 | 错误消息 |
|---------|---------|---------|
| 空输入 | `RespondToModel` | "exec expects raw JavaScript source text..." |
| pragma 后无代码 | `RespondToModel` | "exec pragma must be followed by JavaScript source..." |
| pragma 格式错误 | `RespondToModel` | "exec pragma must be valid JSON..." |
| pragma 未知字段 | `RespondToModel` | "exec pragma only supports `yield_time_ms` and `max_output_tokens`..." |
| 数值超出安全整数 | `RespondToModel` | "exec pragma field `xxx` must be a non-negative safe integer" |
| Node.js 进程启动失败 | `RespondToModel` | "exec runner failed to start" |
| 消息发送失败 | `RespondToModel` | 底层 IO 错误 |

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/core/src/tools/code_mode/execute_handler.rs`

### 调用方
- `/home/sansha/Github/codex/codex-rs/core/src/tools/code_mode/mod.rs`
  - 第 1 行：`mod execute_handler;`
  - 第 56 行：`pub(crate) use execute_handler::CodeModeExecuteHandler;`

### 被调用方/依赖
| 文件 | 用途 |
|------|------|
| `mod.rs` | `CodeModeSessionProgress`, `ExecContext`, `PUBLIC_TOOL_NAME`, `build_enabled_tools`, `handle_node_message`, `CODE_MODE_PRAGMA_PREFIX`, `DEFAULT_EXEC_YIELD_TIME_MS` |
| `protocol.rs` | `HostToNodeMessage`, `build_source` |
| `service.rs` | `CodeModeService` 的方法：`stored_values()`, `allocate_cell_id()`, `allocate_request_id()`, `ensure_started()` |
| `process.rs` | `CodeModeProcess::send()` |

### 测试文件
- `/home/sansha/Github/codex/codex-rs/core/src/tools/code_mode/execute_handler_tests.rs`
  - 在文件末尾通过 `#[cfg(test)]` 引入

### 外部依赖
| crate | 用途 |
|-------|------|
| `async_trait` | `#[async_trait]` 宏 |
| `serde::Deserialize` | pragma 结构体反序列化 |
| `crate::codex::{Session, TurnContext}` | 会话和回合上下文 |
| `crate::function_tool::FunctionCallError` | 错误类型 |
| `crate::tools::context::{FunctionToolOutput, ToolInvocation, ToolPayload}` | 工具调用上下文 |
| `crate::tools::registry::{ToolHandler, ToolKind}` | 工具处理器 trait |

## 依赖与外部交互

### Trait 实现
```rust
#[async_trait]
impl ToolHandler for CodeModeExecuteHandler {
    type Output = FunctionToolOutput;

    fn kind(&self) -> ToolKind {
        ToolKind::Function
    }

    fn matches_kind(&self, payload: &ToolPayload) -> bool {
        matches!(payload, ToolPayload::Custom { .. })
    }

    async fn handle(&self, invocation: ToolInvocation) -> Result<Self::Output, FunctionCallError> {
        // ... 实现
    }
}
```

### 与 CodeModeService 的交互
```rust
let service = &exec.session.services.code_mode_service;
let stored_values = service.stored_values().await;
let cell_id = service.allocate_cell_id().await;
let request_id = service.allocate_request_id().await;
let process_slot = service.ensure_started().await?;
```

### 与 CodeModeProcess 的交互
```rust
let message = process.send(&request_id, &message).await?;
```

## 风险、边界与改进建议

### 风险点

1. **数值溢出风险**
   - 使用 `MAX_JS_SAFE_INTEGER` 检查，但 `usize` 到 `u64` 的转换在某些平台上可能溢出
   - 当前实现使用 `u64::try_from(max_output_tokens).unwrap_or(true)` 处理，但逻辑较复杂

2. **并发安全问题**
   - `ensure_started()` 返回 `OwnedMutexGuard`，确保进程访问的互斥
   - 但如果在 `send` 和 `await response` 之间进程崩溃，可能导致挂起

3. **错误信息泄露**
   - 某些底层错误（如 IO 错误）直接转换为字符串返回给模型
   - 可能包含敏感路径或系统信息

### 边界情况

1. **pragma 仅包含空白字符**
   ```rust
   let directive = pragma.trim();
   if directive.is_empty() { ... }
   ```
   正确处理，返回明确的错误信息

2. **超大输入**
   - 代码本身没有输入长度限制
   - 依赖下层（如 `build_source`）处理大输入

3. **进程重启**
   - `ensure_started()` 会检测进程是否已退出，自动重启
   - 但正在执行的 cell 会丢失，这是预期行为

### 改进建议

1. **输入长度限制**
   ```rust
   const MAX_CODE_LENGTH: usize = 1024 * 1024; // 1MB
   if input.len() > MAX_CODE_LENGTH {
       return Err(FunctionCallError::RespondToModel(
           "exec input exceeds maximum length".to_string()
       ));
   }
   ```

2. **更清晰的错误分类**
   - 区分用户错误（如无效 pragma）和系统错误（如进程启动失败）
   - 系统错误不应暴露给模型，应记录并返回通用错误

3. **执行超时保护**
   - 当前依赖 Node.js 端的 `yield_time_ms`
   - Rust 端应添加整体超时，防止无限等待

4. **代码预热**
   - `ensure_started()` 可以预先生成一些常用工具的环境
   - 减少首次执行的延迟

5. **指标收集**
   - 记录执行时间、代码长度、工具调用次数等指标
   - 便于性能分析和优化

6. **测试覆盖**
   - 当前测试仅覆盖 `parse_freeform_args`
   - 应添加集成测试，覆盖完整的 `execute` 流程
