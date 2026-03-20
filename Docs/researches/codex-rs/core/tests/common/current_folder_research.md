# DIR codex-rs/core/tests/common 研究文档

## 场景与职责

`codex-rs/core/tests/common` 是 Codex Rust 核心库的集成测试基础设施目录，作为 `core_test_support` crate 提供测试共享工具集。该目录的主要职责包括：

1. **测试基础设施提供**：为 `codex-core` 的集成测试提供统一的测试辅助函数、Mock 服务器和测试数据构建器
2. **测试环境隔离**：通过临时目录、配置覆盖和环境变量控制，确保测试的独立性和可重复性
3. **Mock 服务模拟**：提供 HTTP SSE 流、WebSocket、MCP 服务器等的 Mock 实现，支持离线测试
4. **测试断言辅助**：提供针对 Codex 协议特定的断言工具和快照格式化功能

该目录被设计为独立的测试支持 crate，被多个测试文件引用（约 80+ 个测试文件依赖此 crate）。

## 功能点目的

### 1. 测试 Codex 实例构建 (`test_codex.rs`)

**目的**：提供流畅的 API 来构建和配置测试用的 Codex 实例。

**核心类型**：
- `TestCodexBuilder`：构建器模式，支持链式配置（模型、认证、预构建钩子、用户 Shell 覆盖等）
- `TestCodex`：封装测试 Codex 实例，提供便捷的文件路径访问和对话提交方法
- `TestCodexHarness`：组合 Mock 服务器和 TestCodex，提供一站式测试环境

**关键功能**：
- 支持多种服务器类型（wiremock MockServer、StreamingSseServer、WebSocketTestServer）
- 支持会话恢复（resume from rollout）
- 支持用户 Shell 覆盖（用于测试不同 Shell 行为）
- 自动配置测试模型目录（用于实验性工具测试）

### 2. codex-exec 测试构建器 (`test_codex_exec.rs`)

**目的**：专门用于测试 `codex-exec` 二进制文件的命令构建器。

**核心类型**：
- `TestCodexExecBuilder`：构建 `assert_cmd::Command` 实例，预设临时 home/work 目录和虚拟 API Key

### 3. Mock 响应服务器 (`responses.rs`)

**目的**：提供完整的 OpenAI Responses API Mock 实现，支持 SSE 流和 WebSocket。

**核心类型**：
- `ResponseMock`：捕获和验证 HTTP 请求，提供请求体解析和断言方法
- `ResponsesRequest`：封装 wiremock 请求，提供便捷的 JSON 访问和字段提取
- `WebSocketTestServer`：WebSocket 测试服务器，支持多连接、请求/响应序列
- `ModelsMock`：模型列表 API 的 Mock

**事件构造器**：
- `ev_completed`、`ev_response_created`：基础响应事件
- `ev_function_call`、`ev_custom_tool_call`：工具调用事件
- `ev_apply_patch_call`：支持多种输出格式的 apply_patch 调用
- `ev_reasoning_item`、`ev_reasoning_text_delta`：推理相关事件
- `ev_web_search_call`、`ev_image_generation_call`：搜索和图像生成事件

**Mock 挂载辅助函数**：
- `mount_sse_once`、`mount_sse_sequence`：挂载 SSE 响应
- `mount_compact_*`：挂载上下文压缩 API 响应
- `mount_models_once`：挂载模型列表响应
- `start_mock_server`：启动默认配置的 Mock 服务器

### 4. 流式 SSE 服务器 (`streaming_sse.rs`)

**目的**：提供细粒度控制的流式 SSE 测试服务器，支持分块门控（gated chunk delivery）。

**核心类型**：
- `StreamingSseServer`：轻量级 HTTP 服务器，支持 GET /v1/models 和 POST /v1/responses
- `StreamingSseChunk`：带可选门控信号的 SSE 块

**使用场景**：
- 测试流式响应处理
- 测试超时和取消逻辑
- 测试背压（backpressure）处理

### 5. 上下文快照格式化 (`context_snapshot.rs`)

**目的**：将 Codex 请求/响应项格式化为可读的快照文本，用于测试断言和调试。

**核心类型**：
- `ContextSnapshotOptions`：配置快照渲染选项（渲染模式、能力指令剥离等）
- `ContextSnapshotRenderMode`：渲染模式枚举（RedactedText、FullText、KindOnly、KindWithTextPrefix）

**格式化能力**：
- 消息项（message）：角色、内容类型、文本内容
- 函数调用（function_call）：函数名
- 函数调用输出（function_call_output）：输出内容
- 本地 Shell 调用（local_shell_call）：命令
- 推理项（reasoning）：摘要、加密内容标记
- 压缩项（compaction）：加密内容标记

**规范化处理**：
- 动态路径规范化（系统技能路径替换为 `<SYSTEM_SKILLS_ROOT>`）
- 能力指令占位符替换（`<APPS_INSTRUCTIONS>`、`<SKILLS_INSTRUCTIONS>` 等）
- AGENTS.md 指令占位符
- 环境上下文占位符

### 6. 应用测试服务器 (`apps_test_server.rs`)

**目的**：模拟 Codex Apps (MCP) 服务器，用于测试连接器功能。

**核心类型**：
- `AppsTestServer`：配置 Mock 服务器以响应 Apps 协议

**模拟端点**：
- `/.well-known/oauth-authorization-server/mcp`：OAuth 元数据
- `/connectors/directory/list`：连接器目录
- `/api/codex/apps`：JSON-RPC 端点（initialize、tools/list、tools/call）

### 7. 进程管理工具 (`process.rs`)

**目的**：提供进程生命周期管理的测试辅助函数。

**功能**：
- `wait_for_pid_file`：等待 PID 文件创建并读取
- `process_is_alive`：检查进程是否存活（使用 `kill -0`）
- `wait_for_process_exit`：等待进程退出

### 8. Zsh Fork 运行时 (`zsh_fork.rs`)

**目的**：支持 Zsh fork 模式的测试配置。

**核心类型**：
- `ZshForkRuntime`：封装 Zsh 路径和 execve wrapper 路径

**功能**：
- 自动查找测试用 Zsh（通过 DotSlash）
- 检测 EXEC_WRAPPER 支持
- 配置 Shell 工具和 Zsh fork 功能

### 9. 分布式追踪 (`tracing.rs`)

**目的**：为测试提供 OpenTelemetry 追踪支持。

**核心类型**：
- `TestTracingContext`：持有追踪提供者和订阅者守卫
- `install_test_tracing`：安装测试追踪订阅者

### 10. 文件系统等待工具 (`lib.rs` 中的 `fs_wait` 模块)

**目的**：异步等待文件系统事件。

**功能**：
- `wait_for_path_exists`：等待路径创建
- `wait_for_matching_file`：等待匹配条件的文件出现

### 11. 测试宏 (`lib.rs`)

**提供的宏**：
- `skip_if_sandbox!`：在 Seatbelt 沙箱中跳过测试
- `skip_if_no_network!`：在网络禁用时跳过测试
- `codex_linux_sandbox_exe_or_skip!`：Linux 沙箱二进制不可用时跳过
- `skip_if_windows!`：Windows 平台跳过

### 12. 全局测试初始化 (`lib.rs`)

**ctor 初始化**：
- `enable_deterministic_unified_exec_process_ids_for_tests`：启用确定性进程 ID
- `configure_insta_workspace_root_for_snapshot_tests`：配置 insta 快照工作区根目录

## 具体技术实现

### 关键流程

#### 1. TestCodex 构建流程

```
TestCodexBuilder::new()
  ├── with_config() / with_model() / with_auth() / with_pre_build_hook()
  └── build(&mock_server)
       ├── 创建临时 home 目录
       ├── 加载默认测试配置 (load_default_config_for_test)
       ├── 应用配置修改器
       ├── 设置模型提供者（指向 Mock 服务器）
       ├── 执行预构建钩子
       ├── 创建 ThreadManager
       └── 启动新线程或恢复已有线程
            └── 返回 TestCodex { home, cwd, codex, session_configured, thread_manager }
```

#### 2. SSE Mock 响应流程

```
start_mock_server()
  ├── 创建 wiremock MockServer
  └── 挂载默认 /models 响应

mount_sse_once(&server, body)
  ├── 创建 ResponseMock（请求捕获器）
  ├── 创建 Mock：POST 方法 + /responses 路径 + ResponseMock
  └── 挂载到服务器，返回 ResponseMock

测试执行时：
  ├── 客户端发送 POST /v1/responses
  ├── ResponseMock::matches() 捕获请求并验证不变量
  ├── 返回预配置的 SSE 响应体
  └── 测试通过 ResponseMock 验证请求内容
```

#### 3. WebSocket Mock 流程

```
start_websocket_server(connections)
  ├── 绑定 TCP 监听器
  ├── 创建连接日志和握手日志
  └── 启动异步任务处理连接
       ├── 接受 TCP 连接
       ├── 执行 WebSocket 握手（可选延迟）
       ├── 记录握手信息
       └── 循环处理请求/响应
            ├── 接收 WebSocket 消息
            ├── 记录请求
            ├── 发送预配置的响应事件
            └── 可选关闭连接
```

#### 4. 请求体验证不变量

```rust
validate_request_body_invariants(request)
  ├── 解析请求体 JSON
  ├── 提取 input 数组
  ├── 收集各类调用 ID：
  │   ├── function_calls
  │   ├── custom_tool_calls
  │   ├── tool_search_calls
  │   └── local_shell_calls
  ├── 收集各类输出 ID：
  │   ├── function_call_outputs
  │   ├── custom_tool_call_outputs
  │   └── tool_search_outputs
  └── 验证对称性：
      ├── 每个输出必须有对应的调用
      └── 每个调用必须有对应的输出
```

### 关键数据结构

#### `TestCodexBuilder` 配置

```rust
pub struct TestCodexBuilder {
    config_mutators: Vec<Box<dyn FnOnce(&mut Config) + Send>>,
    auth: CodexAuth,
    pre_build_hooks: Vec<Box<dyn FnOnce(&Path) + Send + 'static>>,
    home: Option<Arc<TempDir>>,
    user_shell_override: Option<Shell>,
}
```

#### `ResponsesRequest` 请求封装

```rust
#[derive(Debug, Clone)]
pub struct ResponsesRequest(wiremock::Request);

// 主要方法：
// - body_json() -> Value：获取解析后的 JSON 请求体
// - input() -> Vec<Value>：获取 input 数组
// - function_call_output(call_id) -> Value：获取特定调用的输出
// - message_input_texts(role) -> Vec<String>：获取指定角色的输入文本
// - header(name) -> Option<String>：获取请求头
```

#### `WebSocketConnectionConfig` WebSocket 配置

```rust
pub struct WebSocketConnectionConfig {
    pub requests: Vec<Vec<Value>>,  // 每个请求对应的响应事件序列
    pub response_headers: Vec<(String, String)>,
    pub accept_delay: Option<Duration>,
    pub close_after_requests: bool,
}
```

### 协议支持

#### SSE (Server-Sent Events)

- 格式：`event: <type>\ndata: <json>\n\n`
- 支持的事件类型：
  - `response.created`、`response.completed`、`response.failed`
  - `response.output_item.added`、`response.output_item.done`
  - `response.output_text.delta`
  - `response.reasoning_text.delta`、`response.reasoning_summary_text.delta`

#### WebSocket

- 基于 `tokio-tungstenite` 实现
- 支持 permessage-deflate 压缩扩展
- 消息格式：JSON 文本帧

#### MCP (Model Context Protocol)

- JSON-RPC 2.0 协议
- 支持方法：initialize、tools/list、tools/call、notifications/initialized
- 流式 HTTP 传输

## 关键代码路径与文件引用

### 核心文件

| 文件 | 行数 | 职责 |
|------|------|------|
| `lib.rs` | 524 | 模块导出、测试工具函数、宏定义、全局初始化 |
| `test_codex.rs` | 640 | TestCodexBuilder、TestCodex、TestCodexHarness |
| `responses.rs` | 1628 | Mock 服务器、请求捕获、事件构造器、请求体验证 |
| `streaming_sse.rs` | 693 | 流式 SSE 测试服务器 |
| `context_snapshot.rs` | 602 | 上下文快照格式化 |

### 辅助文件

| 文件 | 行数 | 职责 |
|------|------|------|
| `test_codex_exec.rs` | 48 | codex-exec 二进制测试构建器 |
| `apps_test_server.rs` | 306 | Codex Apps (MCP) Mock 服务器 |
| `process.rs` | 48 | 进程管理工具 |
| `zsh_fork.rs` | 124 | Zsh fork 测试运行时 |
| `tracing.rs` | 26 | OpenTelemetry 测试追踪 |

### 配置文件

| 文件 | 职责 |
|------|------|
| `Cargo.toml` | crate 配置，声明依赖（wiremock、tokio、serde_json 等） |
| `BUILD.bazel` | Bazel 构建配置，引用模型可用性 fixtures |

### 被调用方（测试文件引用）

该 crate 被以下主要测试模块引用：

- `codex-rs/core/tests/suite/*.rs`（约 70+ 个测试文件）
- `codex-rs/exec/tests/suite/*.rs`
- `codex-rs/app-server/tests/suite/*.rs`
- `codex-rs/login/tests/suite/*.rs`
- `codex-rs/mcp-server/tests/suite/*.rs`

## 依赖与外部交互

### 内部依赖

| Crate | 用途 |
|-------|------|
| `codex-core` | 被测试的核心库，提供 CodexThread、Config、ThreadManager 等 |
| `codex-protocol` | 协议类型定义（EventMsg、Op、ResponseItem 等） |
| `codex-utils-absolute-path` | 绝对路径类型 |
| `codex-utils-cargo-bin` | 二进制文件路径解析（支持 Cargo 和 Bazel） |

### 外部依赖

| Crate | 用途 |
|-------|------|
| `wiremock` | HTTP Mock 服务器 |
| `tokio` / `tokio-tungstenite` | 异步运行时和 WebSocket |
| `serde_json` | JSON 序列化/反序列化 |
| `tempfile` | 临时目录管理 |
| `notify` | 文件系统事件监听 |
| `regex-lite` | 正则表达式处理 |
| `zstd` | 请求体压缩解码 |
| `opentelemetry` / `tracing-opentelemetry` | 分布式追踪 |

### 环境交互

- **文件系统**：创建临时目录、读取 fixtures、监听文件变化
- **网络**：绑定本地端口提供 Mock 服务
- **进程**：执行 dotslash 获取依赖、检查进程存活
- **环境变量**：`INSTA_WORKSPACE_ROOT`、`CODEX_HOME`、`EXEC_WRAPPER`

## 风险、边界与改进建议

### 风险点

1. **测试间状态泄漏**
   - 风险：全局状态（如 `test_support` 模式、环境变量）可能影响后续测试
   - 缓解：使用 `#[ctor]` 初始化确保每个测试进程独立；使用临时目录隔离文件状态

2. **Mock 服务器竞争条件**
   - 风险：多个测试同时启动 Mock 服务器可能导致端口冲突
   - 缓解：wiremock 自动分配端口；自定义服务器绑定到 `127.0.0.1:0`

3. **请求体验证过于严格**
   - 风险：`validate_request_body_invariants` 中的断言可能导致测试崩溃而非失败
   - 现状：已在 `ResponseMock::matches` 中调用，panic 会中断测试

4. **平台特定代码**
   - 风险：Linux 沙箱、Zsh fork 等功能在其他平台不可用
   - 缓解：使用条件编译和跳过宏（`skip_if_windows!`、`codex_linux_sandbox_exe_or_skip!`）

### 边界情况

1. **超时处理**
   - `wait_for_event_with_timeout` 默认最小 10 秒超时
   - `fs_wait` 模块使用可配置超时（默认 30 秒）

2. **大请求体处理**
   - wiremock 配置 `BodyPrintLimit::Limited(80_000)` 限制请求体打印
   - zstd 压缩请求体自动解码

3. **并发连接**
   - WebSocketTestServer 支持多连接，但按 FIFO 顺序消费配置
   - StreamingSseServer 每个连接独立处理

### 改进建议

1. **增强文档**
   - 为复杂的构建器模式添加更多使用示例
   - 记录每个事件构造器的预期 JSON 格式

2. **性能优化**
   - 考虑使用连接池复用 Mock 服务器实例（当前每个测试独立启动）
   - 延迟初始化重型资源（如 OpenTelemetry 追踪）

3. **可维护性**
   - 将 `responses.rs` 拆分为多个子模块（事件构造器、Mock 类型、验证逻辑）
   - 提取通用的请求体验证逻辑到独立 crate

4. **功能扩展**
   - 添加对 gRPC 或 HTTP/2 的 Mock 支持（如果未来协议需要）
   - 支持更复杂的请求匹配（如 JSON Schema 验证）

5. **错误处理**
   - 将 `validate_request_body_invariants` 中的 panic 改为返回 Result，允许测试优雅失败
   - 添加更详细的诊断信息当 Mock 响应不匹配时

---

*研究日期：2026-03-21*
*模型：k2p5*
