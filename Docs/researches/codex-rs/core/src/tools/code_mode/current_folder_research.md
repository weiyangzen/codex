# DIR codex-rs/core/src/tools/code_mode 研究文档

## 场景与职责

`code_mode` 是 Codex CLI 中一个实验性的 JavaScript 执行环境，允许模型在隔离的 JavaScript 上下文中执行代码，并调用其他工具。它是 `js_repl` 的轻量级替代方案，使用 Node.js 的内置 `vm` 模块而非持久化的 Node 内核。

### 核心职责

1. **提供隔离的 JavaScript 执行环境**：在 Node.js 的 VM 上下文中运行用户代码，无文件系统、网络或控制台访问
2. **支持嵌套工具调用**：允许 JavaScript 代码通过 `tools` 全局对象调用其他 Codex 工具
3. **状态持久化**：通过 `store`/`load` API 在同一会话的多次执行间共享数据
4. **协作式多任务**：支持 `yield_control()` 让出执行权，并通过 `wait` 工具恢复或终止运行中的脚本
5. **内容输出**：支持文本、图像等多种输出格式

### 使用场景

- 需要执行简单 JavaScript 逻辑而不想启动完整 REPL 的场景
- 需要调用其他 Codex 工具并处理其返回值的自动化脚本
- 需要长时间运行并间歇性产出输出的任务（配合 `yield_control`）

---

## 功能点目的

### 1. `exec` 工具（主入口）

**文件**: `execute_handler.rs`

- 接收原始 JavaScript 代码（非 JSON）
- 支持首行 pragma 配置（`// @exec: {...}`）
  - `yield_time_ms`: 脚本运行多久后自动让出控制权（默认 10s）
  - `max_output_tokens`: 输出截断限制（默认 10000 tokens）
- 在隔离 VM 中执行代码，返回执行结果或产出状态

### 2. `wait` 工具

**文件**: `wait_handler.rs`

- 用于恢复或终止正在运行的 `exec` 会话（cell）
- 参数：
  - `cell_id`: 要操作的 exec 会话标识
  - `yield_time_ms`: 等待多久后再次让出（默认 10s）
  - `max_tokens`: 输出限制
  - `terminate`: 设为 true 时终止会话

### 3. 嵌套工具调用

**文件**: `worker.rs`, `mod.rs`

- JavaScript 代码可通过 `tools.tool_name(args)` 调用其他工具
- 支持 MCP 工具（通过 `tools.mcp__server__tool_name` 格式）
- 工具调用是异步的，通过消息传递与主进程通信

### 4. 状态管理

**文件**: `service.rs`

- `stored_values`: 跨 exec 调用的键值存储
- `cell_id`: 会话标识分配
- 进程生命周期管理（按需启动 Node 进程）

### 5. 协议层

**文件**: `protocol.rs`

- 定义 Rust 与 Node.js 进程间的通信协议
- 消息类型：Start, Poll, Terminate, Response, Yielded, Result, Notify, ToolCall

### 6. JavaScript 运行时

**文件**: `runner.cjs`, `bridge.js`

- `runner.cjs`: Node.js 主进程，管理 Worker 线程和协议转换
- `bridge.js`: 用户代码包装器，注入全局 API（`tools`, `text`, `image`, `store`, `load`, `exit`, `yield_control`, `notify`）

---

## 具体技术实现

### 关键流程

#### 1. Exec 执行流程

```
CodeModeExecuteHandler::execute
  ├── parse_freeform_args(code)          // 解析 pragma 和代码
  ├── build_enabled_tools()              // 构建可用工具列表
  ├── build_source(code, enabled_tools)  // 生成包装后的 JS 代码
  ├── service.allocate_cell_id()         // 分配会话 ID
  ├── service.ensure_started()           // 启动 Node 进程（如需要）
  ├── process.send(Start { ... })        // 发送启动消息
  └── handle_node_message()              // 处理返回消息
       ├── Result { ... } → 完成
       ├── Yielded { ... } → 产出（可后续 wait）
       └── Terminated { ... } → 终止
```

#### 2. 嵌套工具调用流程

```
worker.rs (监听线程)
  ├── 收到 NodeToHostMessage::ToolCall
  ├── call_nested_tool()                 // 调用实际工具
  │     ├── 解析 MCP 工具名或查找本地工具
  │     ├── ToolCallRuntime::handle_tool_call_with_source()
  │     └── 返回 AnyToolResult
  ├── 序列化结果
  └── 发送 HostToNodeMessage::Response 回 Node 进程
```

#### 3. Wait 流程

```
CodeModeWaitHandler::handle
  ├── 解析参数（cell_id, yield_time_ms, terminate）
  ├── 根据 terminate 决定发送 Poll 或 Terminate 消息
  ├── process.send(message)
  └── handle_node_message() 处理响应
```

### 数据结构

#### Rust 侧核心结构

```rust
// service.rs
pub(crate) struct CodeModeService {
    js_repl_node_path: Option<PathBuf>,     // Node 可执行路径
    stored_values: Mutex<HashMap<String, JsonValue>>,  // 持久化存储
    process: Arc<Mutex<Option<CodeModeProcess>>>,      // Node 进程
    next_cell_id: Mutex<u64>,               // 自增会话 ID
}

// protocol.rs
pub(super) struct EnabledTool {
    pub(super) tool_name: String,      // 原始工具名
    pub(super) global_name: String,    // JS 可用名（规范化后）
    pub(super) module_path: String,    // 模块路径
    pub(super) namespace: Vec<String>, // 命名空间
    pub(super) name: String,           // 工具键名
    pub(super) description: String,    // 工具描述
    pub(super) kind: CodeModeToolKind, // Function | Freeform
}

pub(super) enum HostToNodeMessage {
    Start { request_id, cell_id, tool_call_id, default_yield_time_ms, enabled_tools, stored_values, source, yield_time_ms, max_output_tokens },
    Poll { request_id, cell_id, yield_time_ms },
    Terminate { request_id, cell_id },
    Response { request_id, id, code_mode_result, error_text },
}

pub(super) enum NodeToHostMessage {
    ToolCall { request_id, id, name, input },
    Yielded { request_id, content_items },
    Terminated { request_id, content_items },
    Notify { cell_id, call_id, text },
    Result { request_id, content_items, stored_values, error_text, max_output_tokens_per_exec_call },
}

// process.rs
pub(super) struct CodeModeProcess {
    pub(super) child: tokio::process::Child,
    pub(super) stdin: Arc<Mutex<tokio::process::ChildStdin>>,
    pub(super) stdout_task: JoinHandle<()>,
    pub(super) response_waiters: Arc<Mutex<HashMap<String, oneshot::Sender<NodeToHostMessage>>>>,
    pub(super) message_rx: Arc<Mutex<mpsc::UnboundedReceiver<NodeToHostMessage>>>,
}
```

#### JavaScript 侧运行时 API

```javascript
// bridge.js 注入的全局 API
globalThis.tools    // 工具命名空间，如 tools.shell_command(...)
globalThis.ALL_TOOLS // 工具元数据数组
globalThis.text(value)        // 输出文本
globalThis.image(urlOrObj)    // 输出图片
globalThis.store(key, value)  // 存储值
globalThis.load(key)          // 读取值
globalThis.exit()             // 立即退出
globalThis.yield_control()    // 让出控制权
globalThis.notify(value)      // 发送通知消息
globalThis.console // 空实现（禁用 console）
```

### 协议细节

Rust 与 Node 进程通过 stdin/stdout 使用 JSON Lines 协议通信：

1. **Rust → Node**: 每行一个 JSON 对象，type 字段标识消息类型
2. **Node → Rust**: 同样 JSON Lines，通过 request_id 关联请求
3. **异步工具调用**: Node Worker 发送 `tool_call` 消息，Rust 侧在独立 tokio 任务中执行工具，完成后发送 `response`

### 进程架构

```
┌─────────────────┐
│   Codex (Rust)  │
│  ┌───────────┐  │
│  │CodeModeService│
│  │ ┌───────┐ │  │
│  │ │Process│ │  │  ← 管理 Node 子进程
│  │ │ ┌───┐ │ │  │
│  │ │ │Worker│ │  │  ← 处理工具调用和通知
│  │ │ └───┘ │ │  │
│  │ └───────┘ │  │
│  └───────────┘  │
└────────┬────────┘
         │ stdin/stdout (JSON Lines)
┌────────▼────────┐
│  Node.js (runner.cjs)  │
│  ┌───────────┐  │
│  │ 主线程     │  │  ← 协议解析、会话管理
│  │ ┌───────┐ │  │
│  │ │Worker │ │  │  ← VM 执行用户代码
│  │ │Thread│ │  │
│  │ └───────┘ │  │
│  └───────────┘  │
└─────────────────┘
```

---

## 关键代码路径与文件引用

### 核心文件

| 文件 | 职责 |
|------|------|
| `mod.rs` | 模块入口，定义 ExecContext、CodeModeSessionProgress、CodeModeExecutionStatus，实现工具构建、嵌套工具调用、消息处理 |
| `service.rs` | CodeModeService 实现，进程管理、cell ID 分配、stored_values 管理 |
| `process.rs` | Node 进程管理（spawn、stdin/stdout 通信、消息路由） |
| `protocol.rs` | 通信协议定义（HostToNodeMessage、NodeToHostMessage、EnabledTool） |
| `worker.rs` | 后台工作线程，处理 ToolCall 和 Notify 消息 |
| `execute_handler.rs` | `exec` 工具处理器，解析 pragma、启动执行 |
| `wait_handler.rs` | `wait` 工具处理器，轮询或终止会话 |
| `runner.cjs` | Node.js 运行时，VM 执行、Worker 管理、协议转换 |
| `bridge.js` | 用户代码包装器，注入全局 API |
| `description.md` | `exec` 工具描述文档（给模型看的说明） |
| `wait_description.md` | `wait` 工具描述文档 |
| `execute_handler_tests.rs` | 单元测试 |

### 关键代码路径

1. **启动 exec 会话**:
   ```
   execute_handler.rs:42-99 → service.rs:48-64 (ensure_started) → process.rs:66-161 (spawn_code_mode_process)
   ```

2. **发送启动消息**:
   ```
   execute_handler.rs:63-73 → process.rs:29-56 (send) → protocol.rs:46-76 (HostToNodeMessage::Start)
   ```

3. **处理工具调用**:
   ```
   worker.rs:30-115 → mod.rs:301-341 (call_nested_tool) → parallel.rs:75-132 (handle_tool_call_with_source)
   ```

4. **构建可用工具列表**:
   ```
   mod.rs:233-243 (build_enabled_tools) → mod.rs:276-298 (build_nested_router)
   ```

5. **生成包装代码**:
   ```
   protocol.rs:108-120 (build_source) → 替换 bridge.js 中的占位符
   ```

---

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `crate::tools::code_mode_description` | 工具名规范化、描述增强、TypeScript 类型生成 |
| `crate::tools::parallel::ToolCallRuntime` | 实际执行嵌套工具调用 |
| `crate::tools::router::ToolRouter` | 工具路由、规格查找 |
| `crate::tools::registry::ToolHandler` | 处理器 trait |
| `crate::tools::context::*` | ToolInvocation、ToolPayload、FunctionToolOutput 等 |
| `crate::features::Feature` | CodeMode、CodeModeOnly 特性开关 |
| `crate::state::service::SessionServices` | 持有 CodeModeService 实例 |
| `crate::codex::{Session, TurnContext}` | 会话和回合上下文 |

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `tokio::process` | 异步进程管理 |
| `tokio::sync::{Mutex, mpsc, oneshot}` | 异步同步原语 |
| `serde_json` | JSON 序列化/反序列化 |
| `tracing` | 日志记录 |
| Node.js (>= v22.22.0) | JavaScript 运行时 |

### 配置项

在 `config.toml` 中通过 `[features]` 启用：

```toml
[features]
code_mode = true          # 启用 exec/wait 工具
code_mode_only = true     # 仅暴露 exec/wait 给模型，其他工具需通过 exec 调用
```

---

## 风险、边界与改进建议

### 已知风险

1. **Node 进程单点故障**
   - 所有 exec 调用共享同一个 Node 进程
   - 如果进程崩溃，所有正在运行的 cell 都会失败
   - **缓解**: `ensure_started()` 会检测进程状态并在需要时重启

2. **VM 逃逸风险**
   - 虽然使用 Node.js VM 模块，但仍存在潜在的逃逸风险
   - `runner.cjs` 中禁用了 `require` 和 `console`，但 VM 模块本身不是完全隔离的
   - **建议**: 考虑使用更严格的沙箱（如 WebAssembly 或独立进程）

3. **内存泄漏**
   - `stored_values` 只增不减，长期会话可能累积大量数据
   - **建议**: 添加过期机制或大小限制

4. **并发安全**
   - 多个 cell 同时运行时的资源竞争
   - **缓解**: 每个 cell 有独立 Worker，但共享 Node 进程的事件循环

### 边界情况

1. **空代码输入**: `parse_freeform_args` 会返回错误
2. **无效 pragma**: 严格的 JSON 解析，仅支持 `yield_time_ms` 和 `max_output_tokens`
3. **工具名冲突**: `normalize_code_mode_identifier` 将非法字符替换为 `_`，可能导致冲突
4. **MCP 工具名**: 使用 `mcp__server__tool` 格式，需正确处理 `split_qualified_tool_name`

### 改进建议

1. **进程隔离**
   - 考虑为每个 exec 调用启动独立的 Node 进程，提高隔离性
   - 或使用 Worker Threads 的 `resourceLimits` 限制内存/CPU

2. **超时机制增强**
   - 当前仅支持 `yield_time_ms`，建议添加绝对执行时间限制
   - 防止无限循环或长时间运行的脚本

3. **存储管理**
   - 添加 `stored_values` 大小限制和 LRU 淘汰
   - 支持显式删除键值

4. **调试支持**
   - 添加 source map 支持，方便调试生成的包装代码
   - 提供错误堆栈映射回原始代码位置

5. **性能优化**
   - 缓存 `enabled_tools` 构建结果，避免每次 exec 重新构建
   - 预编译常用工具调用的序列化格式

6. **TypeScript 支持**
   - 当前仅生成 TypeScript 声明，可考虑支持直接执行 TS（通过 esbuild-wasm 等）

7. **测试覆盖**
   - 当前仅有 `execute_handler_tests.rs`，建议添加：
     - 集成测试（完整 exec → wait → terminate 流程）
     - 并发测试（多个 cell 同时运行）
     - 错误恢复测试（Node 进程崩溃后的行为）

---

## 附录：工具名规范化规则

```rust
// code_mode_description.rs:94-116
pub(crate) fn normalize_code_mode_identifier(tool_key: &str) -> String {
    let mut identifier = String::new();
    for (index, ch) in tool_key.chars().enumerate() {
        let is_valid = if index == 0 {
            ch == '_' || ch == '$' || ch.is_ascii_alphabetic()
        } else {
            ch == '_' || ch == '$' || ch.is_ascii_alphanumeric()
        };
        if is_valid {
            identifier.push(ch);
        } else {
            identifier.push('_');
        }
    }
    if identifier.is_empty() { "_".to_string() } else { identifier }
}
```

示例转换：
- `shell_command` → `shell_command`
- `mcp:ologs:get_profile` → `mcp__ologs__get_profile`
- `123-tool` → `_23_tool`
