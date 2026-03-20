# DIR codex-rs/core/src/tools/code_mode 研究文档

## 场景与职责

`code_mode` 是 Codex 核心工具系统中的一个实验性功能模块，提供在隔离的 JavaScript 环境中执行用户代码的能力。它允许模型通过 `exec` 工具运行原始 JavaScript 代码，并通过 `wait` 工具与长时间运行的代码单元（cell）进行交互。

### 核心职责

1. **JavaScript 代码执行**：在隔离的 Node.js VM 环境中执行用户提供的 JavaScript 代码
2. **嵌套工具调用**：允许 JavaScript 代码调用其他 Codex 工具（如 shell、文件操作等）
3. **状态持久化**：支持在多次 `exec` 调用之间存储和加载数据
4. **长时间运行支持**：通过 `wait` 工具支持长时间运行的脚本，支持中断和恢复
5. **输出控制**：支持文本、图像输出，以及实时通知（notify）机制

### 使用场景

- 需要执行复杂逻辑编排多个工具调用时
- 需要状态在多次执行间保持时
- 需要长时间运行并可能产生中间输出的任务
- 需要程序化控制工具调用流程的场景

---

## 功能点目的

### 1. `exec` 工具（CodeModeExecuteHandler）

**目的**：执行原始 JavaScript 代码

**主要功能**：
- 接收原始 JavaScript 源代码（非 JSON）
- 支持通过 pragma 注释配置执行参数：`// @exec: {"yield_time_ms": 10000, "max_output_tokens": 1000}`
- 在隔离的 VM 中运行代码，无文件系统、网络或 console 访问
- 返回执行结果或产出（yield）中间结果

**全局辅助函数**：
- `exit()`：立即结束脚本
- `text(value)`：追加文本输出
- `image(imageUrlOrItem)`：追加图像输出
- `store(key, value)` / `load(key)`：状态存储/加载
- `notify(value)`：实时通知模型
- `yield_control()`：产出当前结果但继续运行
- `tools.*`：访问所有启用的嵌套工具

### 2. `wait` 工具（CodeModeWaitHandler）

**目的**：与长时间运行的 `exec` 单元交互

**主要功能**：
- 通过 `cell_id` 恢复等待中的执行单元
- 获取新的输出或最终完成结果
- 支持 `terminate: true` 终止运行中的单元
- 可配置 `yield_time_ms` 和 `max_tokens` 控制等待行为

### 3. 进程管理（CodeModeService + CodeModeProcess）

**目的**：管理 Node.js 运行时生命周期

**主要功能**：
- 延迟启动 Node.js 进程
- 自动检测进程退出并重新启动
- 管理多个执行单元（cell）
- 存储值（stored_values）的会话级持久化

### 4. 工具桥接（bridge.js + runner.cjs）

**目的**：在 JavaScript 代码和 Rust 工具系统之间建立桥梁

**主要功能**：
- `bridge.js`：在 VM 中设置全局运行时对象
- `runner.cjs`：完整的 Node.js 运行时，使用 Worker Threads 和 VM 模块执行代码
- 处理工具调用请求和响应的序列化
- 管理内容项（content items）的收集和产出

---

## 具体技术实现

### 关键数据结构

#### 协议消息类型（protocol.rs）

```rust
// 主机（Rust）到 Node 的消息
enum HostToNodeMessage {
    Start { request_id, cell_id, tool_call_id, default_yield_time_ms, enabled_tools, stored_values, source, yield_time_ms, max_output_tokens },
    Poll { request_id, cell_id, yield_time_ms },
    Terminate { request_id, cell_id },
    Response { request_id, id, code_mode_result, error_text },
}

// Node 到主机的消息
enum NodeToHostMessage {
    ToolCall { request_id, id, name, input },
    Yielded { request_id, content_items },
    Terminated { request_id, content_items },
    Notify { cell_id, call_id, text },
    Result { request_id, content_items, stored_values, error_text, max_output_tokens_per_exec_call },
}
```

#### 执行上下文

```rust
struct ExecContext {
    session: Arc<Session>,
    turn: Arc<TurnContext>,
}

enum CodeModeSessionProgress {
    Finished(FunctionToolOutput),
    Yielded { output: FunctionToolOutput },
}

enum CodeModeExecutionStatus {
    Completed,
    Failed,
    Running(String),
    Terminated,
}
```

#### 启用工具描述

```rust
struct EnabledTool {
    tool_name: String,      // 原始工具名
    global_name: String,    // JS 标识符（规范化后）
    module_path: String,    // 模块路径
    namespace: Vec<String>, // 命名空间
    name: String,           // 工具键名
    description: String,
    kind: CodeModeToolKind, // Function 或 Freeform
}
```

### 关键流程

#### 1. `exec` 执行流程

```
1. CodeModeExecuteHandler::handle
   └─> execute()
       ├─> parse_freeform_args() 解析 pragma 和代码
       ├─> build_enabled_tools() 构建可用工具列表
       ├─> protocol::build_source() 生成完整 JS 代码（bridge + user code）
       ├─> CodeModeService::ensure_started() 确保 Node 进程运行
       ├─> CodeModeProcess::send(HostToNodeMessage::Start)
       └─> handle_node_message() 处理响应
           ├─> Yielded: 返回中间结果
           ├─> Result: 返回最终结果，更新 stored_values
           └─> Terminated: 返回终止结果
```

#### 2. `wait` 执行流程

```
1. CodeModeWaitHandler::handle
   └─> 解析参数（cell_id, yield_time_ms, max_tokens, terminate）
       ├─> 如果 terminate: 发送 Terminate 消息
       └─> 否则: 发送 Poll 消息
           └─> handle_node_message() 处理响应
```

#### 3. 嵌套工具调用流程

```
1. Worker 循环接收 NodeToHostMessage::ToolCall
2. call_nested_tool()
   ├─> 检查 MCP 工具或普通工具
   ├─> 构建 ToolPayload
   ├─> ToolCallRuntime::handle_tool_call_with_source()
   └─> 获取结果后发送 HostToNodeMessage::Response
```

#### 4. Node.js 运行时流程（runner.cjs）

```
1. 主进程创建 readline 接口监听 stdin
2. 收到 start 消息：
   ├─> 创建 Worker（codeModeWorkerMain）
   ├─> Worker 创建 VM 上下文
   ├─> 加载工具模块和代码模式模块
   └─> 执行用户代码
3. Worker 消息处理：
   ├─> tool_call: 转发到主进程，等待响应
   ├─> content_item: 收集到 session.content_items
   ├─> yield: 发送 yielded 消息
   ├─> notify: 发送 notify 消息
   └─> result: 发送 result 消息
```

### 代码模块组织

| 文件 | 职责 |
|------|------|
| `mod.rs` | 模块入口，核心逻辑（参数解析、工具构建、消息处理、输出截断） |
| `service.rs` | CodeModeService 实现，进程生命周期管理，cell ID 分配 |
| `process.rs` | CodeModeProcess 实现，Node 进程创建和通信 |
| `worker.rs` | CodeModeWorker 实现，后台消息处理循环 |
| `protocol.rs` | 协议消息类型定义，序列化/反序列化，工具描述构建 |
| `execute_handler.rs` | `exec` 工具处理器实现 |
| `wait_handler.rs` | `wait` 工具处理器实现 |
| `execute_handler_tests.rs` | 参数解析单元测试 |
| `bridge.js` | VM 内运行的桥接代码，设置全局对象 |
| `runner.cjs` | Node.js 主运行时，Worker 线程管理 |
| `description.md` | `exec` 工具描述文档 |
| `wait_description.md` | `wait` 工具描述文档 |

---

## 关键代码路径与文件引用

### 核心入口

- **工具注册**：`codex-rs/core/src/tools/handlers/mod.rs:34-35`
  ```rust
  pub(crate) use crate::tools::code_mode::CodeModeExecuteHandler;
  pub(crate) use crate::tools::code_mode::CodeModeWaitHandler;
  ```

- **服务创建**：`codex-rs/core/src/codex.rs:1827`
  ```rust
  code_mode_service: crate::tools::code_mode::CodeModeService::new(
      config.js_repl_node_path.clone(),
  ),
  ```

- **服务挂载**：`codex-rs/core/src/state/service.rs:64`
  ```rust
  pub(crate) code_mode_service: CodeModeService,
  ```

### 工具描述生成

- **描述模板**：`codex-rs/core/src/tools/code_mode/description.md`
- **代码模式专用描述**：`codex-rs/core/src/tools/code_mode/mod.rs:72-99`
- **工具引用生成**：`codex-rs/core/src/tools/code_mode_description.rs`

### 功能开关

- **Feature::CodeMode**：`codex-rs/core/src/features.rs:89`
- **Feature::CodeModeOnly**：`codex-rs/core/src/features.rs:91`
- **功能检查**：`codex-rs/core/src/tools/code_mode/service.rs:73-75`

### 路由器集成

- **嵌套工具过滤**：`codex-rs/core/src/tools/router.rs:66-82`
- **工具调用源**：`codex-rs/core/src/tools/router.rs:27`

---

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `crate::tools::code_mode_description` | 工具描述生成和标识符规范化 |
| `crate::tools::parallel::ToolCallRuntime` | 嵌套工具调用执行 |
| `crate::tools::router::ToolRouter` | 工具路由和规格查找 |
| `crate::tools::context::*` | 工具调用上下文和输出类型 |
| `crate::tools::registry::*` | 工具处理器注册表 |
| `crate::features::Feature` | 功能开关检查 |
| `crate::codex::{Session, TurnContext}` | 会话和回合上下文 |
| `crate::truncate::*` | 输出截断策略 |

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `tokio` | 异步运行时，进程管理，通道 |
| `serde_json` | JSON 序列化/反序列化 |
| `uuid` | 生成唯一请求 ID |
| `tracing` | 日志和遥测 |
| `async_trait` | 异步 trait 支持 |
| `codex_protocol` | 协议模型（FunctionCallOutputContentItem 等） |

### Node.js 运行时依赖

- **VM 模块**：`node:vm` - 创建隔离上下文
- **Worker Threads**：`node:worker_threads` - 后台执行
- **SourceTextModule/SyntheticModule**：ES 模块支持

### 配置项

- `js_repl_node_path`：Node.js 可执行文件路径（可选）
- `features.code_mode`：启用代码模式功能
- `features.code_mode_only`：仅暴露 `exec`/`wait` 工具给模型

---

## 风险、边界与改进建议

### 已知风险

1. **进程崩溃处理**
   - 风险：Node.js 进程可能因内存不足或 VM 错误而崩溃
   - 缓解：`ensure_started()` 会检测进程状态并自动重启
   - 代码：`service.rs:52-55`

2. **无限循环/长时间运行**
   - 风险：用户代码可能无限循环
   - 缓解：`yield_time_ms` 默认 10 秒，可通过 `wait` 继续或 `terminate` 终止
   - 边界：最大安全整数限制（2^53 - 1）

3. **工具调用递归**
   - 风险：`exec` 调用自身可能导致无限递归
   - 缓解：`call_nested_tool` 显式拒绝调用 `PUBLIC_TOOL_NAME`
   - 代码：`mod.rs:308-311`

4. **存储值大小**
   - 风险：`stored_values` 可能在会话中无限增长
   - 缓解：无显式限制，依赖用户代码控制

5. **输出截断**
   - 风险：大输出可能超出模型上下文限制
   - 缓解：`max_output_tokens` 默认 10000，支持截断策略

### 边界条件

| 边界 | 处理 |
|------|------|
| 空代码输入 | `parse_freeform_args` 返回错误 |
| 无效 pragma JSON | 返回详细的解析错误 |
| 未知 pragma 字段 | 拒绝并列出支持的字段 |
| 进程启动失败 | 返回 `RespondToModel` 错误 |
| 单元不存在 | `wait` 返回错误结果 |
| 工具不存在 | `call_nested_tool` 返回错误 |

### 改进建议

1. **资源限制**
   - 添加内存使用限制（通过 Node.js `--max-old-space-size`）
   - 添加 CPU 时间限制
   - 添加存储值大小限制

2. **可观测性**
   - 添加 VM 执行指标（执行时间、内存使用）
   - 添加工具调用频率统计
   - 改进错误堆栈跟踪

3. **安全性**
   - 考虑使用更严格的 VM 沙箱（如 `vm2` 替代原生 `vm`）
   - 添加代码静态分析（检测危险模式）
   - 限制单次执行的工具调用次数

4. **性能优化**
   - 预编译常用工具模块
   - 复用 Worker 进程（当前每个 cell 创建新 Worker）
   - 添加代码缓存机制

5. **开发者体验**
   - 添加调试模式（保留 console.log 输出）
   - 提供 TypeScript 类型定义
   - 支持 source map 用于错误定位

6. **代码质量**
   - `runner.cjs` 文件较大（938 行），可考虑拆分为模块
   - 添加更多单元测试（当前仅 `execute_handler_tests.rs` 有测试）
   - 添加集成测试验证完整执行流程

---

## 附录：关键常量

```rust
const CODE_MODE_RUNNER_SOURCE: &str = include_str!("runner.cjs");
const CODE_MODE_BRIDGE_SOURCE: &str = include_str!("bridge.js");
const CODE_MODE_DESCRIPTION_TEMPLATE: &str = include_str!("description.md");
const CODE_MODE_PRAGMA_PREFIX: &str = "// @exec:";
const CODE_MODE_ONLY_PREFACE: &str = "Use `exec/wait` tool to run all other tools...";

pub(crate) const PUBLIC_TOOL_NAME: &str = "exec";
pub(crate) const WAIT_TOOL_NAME: &str = "wait";
pub(crate) const DEFAULT_EXEC_YIELD_TIME_MS: u64 = 10_000;
pub(crate) const DEFAULT_WAIT_YIELD_TIME_MS: u64 = 10_000;
```

---

*文档生成时间：2026-03-21*
*研究范围：codex-rs/core/src/tools/code_mode/*
