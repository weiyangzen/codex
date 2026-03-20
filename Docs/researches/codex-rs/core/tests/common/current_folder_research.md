# Research: codex-rs/core/tests/common

## 概述

`codex-rs/core/tests/common` 是 Codex Rust 核心库的集成测试基础设施， crate 名为 `core_test_support`。它提供了一套完整的测试支持工具，用于构建端到端（E2E）测试、模拟外部依赖（如 OpenAI API）、管理测试生命周期以及验证系统行为。

---

## 场景与职责

### 核心职责

1. **测试基础设施提供**: 为 `codex-rs/core/tests/suite/` 中的 85+ 个集成测试提供共享的测试工具和模拟设施
2. **Mock 服务器管理**: 提供基于 `wiremock` 的 HTTP Mock 服务器，用于模拟 OpenAI Responses API 和 Models API
3. **WebSocket 测试支持**: 支持实时对话功能的 WebSocket 测试服务器
4. **测试数据构建**: 提供便捷的 SSE 事件构造器、请求/响应数据构建器
5. **环境隔离**: 通过临时目录和配置覆盖确保测试的隔离性和可重复性

### 使用场景

- **单元测试**: 模块内部的自测试（如 `responses.rs` 中的 `validate_request_body_invariants`）
- **集成测试**: 与 `codex_core` 库的完整交互测试
- **端到端测试**: 模拟完整的用户会话流程
- **回归测试**: 通过快照测试验证输出稳定性

---

## 功能点目的

### 1. 核心测试框架 (`lib.rs`)

| 功能 | 目的 |
|------|------|
|`load_default_config_for_test`|创建隔离的测试配置，使用临时目录避免污染用户真实的 `~/.codex`|
|`wait_for_event`/`wait_for_event_with_timeout`|异步等待 Codex 线程事件，用于测试异步流程|
|`fs_wait` 模块|文件系统监控工具，等待文件创建或匹配条件|
|`skip_if_sandbox!`/`skip_if_no_network!`|条件跳过宏，处理沙盒和网络限制环境|
|`load_sse_fixture`|从 JSON fixture 加载 SSE 流数据|

### 2. TestCodex 构建器 (`test_codex.rs`)

提供流式 API 构建测试环境：

```rust
let test = test_codex()
    .with_model("gpt-5.1-codex")
    .with_config(|c| c.approval_policy = AskForApproval::Never)
    .build(&mock_server)
    .await?;
```

**关键特性**:
- 支持从 rollout 文件恢复会话 (`resume`)
- 支持自定义用户 shell (`with_user_shell`)
- 支持 WebSocket 服务器 (`build_with_websocket_server`)
- 支持流式 SSE 服务器 (`build_with_streaming_server`)

### 3. Mock 响应服务器 (`responses.rs`)

提供完整的 OpenAI API 模拟：

**SSE 事件构造器**:
- `ev_completed()` - 响应完成事件
- `ev_function_call()` - 函数调用事件
- `ev_apply_patch_call()` - 代码补丁应用调用（支持多种输出格式）
- `ev_reasoning_item()` - 推理项目事件
- `ev_web_search_call_done()` - 网页搜索调用

**Mock 挂载辅助函数**:
- `mount_sse_once()` - 单次 SSE 响应
- `mount_sse_sequence()` - 顺序响应序列
- `mount_compact_json_once()` - 上下文压缩响应
- `start_mock_server()` - 启动默认 Mock 服务器

**请求验证**:
- `ResponseMock` 捕获并验证请求内容
- `ResponsesRequest` 提供丰富的请求内容查询方法
- `validate_request_body_invariants()` 验证请求体完整性（防止孤儿调用输出）

### 4. 流式 SSE 服务器 (`streaming_sse.rs`)

轻量级 HTTP 服务器，支持：
- 基于 gate 的流控（允许测试精确控制数据发送时机）
- `/v1/models` 和 `/v1/responses` 端点
- 完成通知机制（`oneshot::Receiver<i64>`）

### 5. WebSocket 测试服务器 (`responses.rs`)

- `start_websocket_server()` - 启动 WebSocket 测试服务器
- 支持 deflate 压缩扩展
- 支持自定义响应头
- 支持连接延迟模拟（用于测试 warmup 路径）

### 6. 上下文快照 (`context_snapshot.rs`)

用于测试输出的快照比较：

| 渲染模式 | 说明 |
|---------|------|
|`RedactedText`|默认模式，敏感内容替换为占位符|
|`FullText`|完整文本保留|
|`KindOnly`|仅显示消息类型|
|`KindWithTextPrefix`|显示类型和前 N 个字符|

**自动归一化**:
- 路径归一化（系统技能路径 → `<SYSTEM_SKILLS_ROOT>`）
- 指令占位符（`<APPS_INSTRUCTIONS>`, `<SKILLS_INSTRUCTIONS>` 等）
- 环境上下文简化

### 7. Apps 测试服务器 (`apps_test_server.rs`)

模拟 ChatGPT Apps/Connectors 服务：
- OAuth 元数据端点
- Connectors 目录列表
- MCP (Model Context Protocol) JSON-RPC 端点
- 支持可搜索工具（100+ 工具模拟）

### 8. Zsh Fork 运行时 (`zsh_fork.rs`)

支持 zsh fork 模式的测试：
- 通过 DotSlash 获取测试用 zsh
- EXEC_WRAPPER 拦截支持检测
- 受限沙盒策略构建

### 9. 进程管理 (`process.rs`)

- `wait_for_pid_file()` - 等待 PID 文件创建
- `process_is_alive()` - 检测进程存活
- `wait_for_process_exit()` - 等待进程退出

### 10. 分布式追踪 (`tracing.rs`)

- `install_test_tracing()` - 安装 OpenTelemetry 测试追踪器
- 支持测试中的分布式追踪上下文

---

## 具体技术实现

### 关键数据结构

```rust
// TestCodex 实例 - 代表一个完整的测试环境
pub struct TestCodex {
    pub home: Arc<TempDir>,           // 隔离的 CODEX_HOME
    pub cwd: Arc<TempDir>,            // 测试工作目录
    pub codex: Arc<CodexThread>,      // 核心线程实例
    pub session_configured: SessionConfiguredEvent,
    pub config: Config,
    pub thread_manager: Arc<ThreadManager>,
}

// Mock 响应捕获
pub struct ResponseMock {
    requests: Arc<Mutex<Vec<ResponsesRequest>>>,
}

// WebSocket 连接配置
pub struct WebSocketConnectionConfig {
    pub requests: Vec<Vec<Value>>,           // 每个请求的事件序列
    pub response_headers: Vec<(String, String)>,
    pub accept_delay: Option<Duration>,      // 握手延迟
    pub close_after_requests: bool,          // 是否发送 close 帧
}
```

### 关键流程

**测试构建流程**:
1. `TestCodexBuilder::build()` → 创建临时目录
2. `prepare_config()` → 加载默认配置 + 应用覆盖
3. `build_from_config()` → 创建 ThreadManager
4. `thread_manager.start_thread()` → 启动 CodexThread
5. 返回 `TestCodex` 实例

**SSE Mock 流程**:
1. `start_mock_server()` → 启动 wiremock 服务器
2. `mount_sse_once()` → 挂载 SSE 响应到 `/v1/responses`
3. 测试提交用户输入 → Codex 发送 HTTP 请求
4. `ResponseMock` 捕获请求并验证
5. Mock 服务器返回 SSE 流

**请求不变量验证** (`validate_request_body_invariants`):
```rust
// 验证每个 function_call_output 都有对应的 function_call
// 验证每个 custom_tool_call_output 都有对应的 custom_tool_call
// 验证每个 tool_search_output 都有对应的 tool_search_call
// 反之亦然（对称性验证）
```

---

## 关键代码路径与文件引用

### 文件清单

| 文件 | 行数 | 职责 |
|-----|------|------|
|`lib.rs`|524|核心测试基础设施、配置加载、事件等待、宏定义|
|`test_codex.rs`|640|TestCodex 构建器、TestCodexHarness、测试流程封装|
|`responses.rs`|1628|Mock 服务器、SSE 构造器、WebSocket 服务器、请求验证|
|`streaming_sse.rs`|693|流式 SSE 测试服务器（轻量级替代 wiremock）|
|`context_snapshot.rs`|602|快照格式化、输出归一化|
|`apps_test_server.rs`|306|ChatGPT Apps Mock 服务器|
|`zsh_fork.rs`|124|Zsh fork 模式测试支持|
|`process.rs`|48|进程生命周期管理|
|`test_codex_exec.rs`|48|codex-exec CLI 测试构建器|
|`tracing.rs`|26|OpenTelemetry 测试追踪|
|`Cargo.toml`|38|依赖声明|
|`BUILD.bazel`|10|Bazel 构建配置|

### 关键依赖

```toml
wiremock = "..."           # HTTP Mock 服务器
tokio-tungstenite = "..."  # WebSocket 支持
notify = "..."             # 文件系统监控
zstd = "..."               # 请求体压缩解码
```

### 外部调用关系

**被调用方** (来自 `codex_core`):
- `CodexThread::submit()` - 提交用户输入
- `ThreadManager::start_thread()` - 启动会话
- `test_support::set_deterministic_process_ids()` - 测试模式

**调用方** (测试套件):
- `codex-rs/core/tests/suite/*.rs` - 85+ 个测试文件
- `codex-rs/core/tests/responses_headers.rs` - 响应头测试

---

## 依赖与外部交互

### 内部依赖

```
core_test_support (本 crate)
├── codex-core          # 被测试的核心库
├── codex-protocol      # 协议类型定义
├── codex-utils-cargo-bin   # 二进制文件定位
└── codex-utils-absolute-path  # 路径处理
```

### 外部服务模拟

| 服务 | 模拟方式 | 文件 |
|-----|---------|------|
|OpenAI Responses API|wiremock Mock|`responses.rs`|
|OpenAI Models API|wiremock Mock|`responses.rs`|
|WebSocket Realtime API|tokio-tungstenite|`responses.rs`|
|ChatGPT Apps|MCP JSON-RPC|`apps_test_server.rs`|

### 环境依赖

- `codex-linux-sandbox` 二进制（Linux 测试）
- `codex-execve-wrapper` 二进制（zsh fork 测试）
- `zsh` DotSlash 文件（zsh fork 测试）
- `dotslash` 工具（获取依赖）

---

## 风险、边界与改进建议

### 已知风险

1. **测试隔离性**: 使用 `ctor` 设置全局测试模式，可能影响并行测试
   ```rust
   #[ctor]
   fn enable_deterministic_unified_exec_process_ids_for_tests() { ... }
   ```

2. **平台差异**: 部分功能仅支持特定平台（如 zsh fork 仅 Linux/macOS）

3. **超时硬编码**: `wait_for_event_with_timeout` 中有硬编码的 10 秒最小超时

4. **Panics 用于断言**: 部分验证使用 `panic!` 而非返回 `Result`，可能导致测试崩溃

### 边界条件

- **并发限制**: `ResponseMock` 使用 `Mutex<Vec<...>>`，高并发测试可能阻塞
- **内存使用**: `BodyPrintLimit::Limited(80_000)` 限制请求体打印大小
- **zstd 解码**: 请求体验证时自动解码 zstd，失败时 panic

### 改进建议

1. **增强可观测性**:
   - 为 Mock 服务器添加结构化日志输出
   - 支持请求/响应的详细追踪模式

2. **性能优化**:
   - 考虑使用 `RwLock` 替代 `Mutex` 提高并发性能
   - 流式 SSE 服务器可支持 HTTP/2 多路复用

3. **功能扩展**:
   - 添加 gRPC Mock 支持（为未来可能的后端迁移准备）
   - 支持模拟网络延迟和故障注入

4. **可维护性**:
   - `responses.rs` 已达 1628 行，建议拆分为子模块（`sse.rs`, `websocket.rs`, `models.rs`）
   - 提取公共的 HTTP 服务器启动逻辑

5. **文档完善**:
   - 为复杂的 SSE 事件构造器添加更多示例
   - 文档化 `ContextSnapshotRenderMode` 的使用场景

---

## 附录：使用示例

### 基础测试模式

```rust
#[tokio::test]
async fn test_basic_flow() -> anyhow::Result<()> {
    let server = responses::start_mock_server().await;
    let mock = responses::mount_sse_once(
        &server,
        responses::sse(vec![
            responses::ev_response_created("resp-1"),
            responses::ev_function_call("call-1", "shell", r#"{"command":["echo","hello"]}"#),
            responses::ev_completed("resp-1"),
        ])
    ).await;

    let test = test_codex().build(&server).await?;
    test.submit_turn("run echo hello").await?;

    let request = mock.single_request();
    assert!(request.has_function_call("call-1"));
    Ok(())
}
```

### 使用 TestCodexHarness

```rust
#[tokio::test]
async fn test_with_harness() -> anyhow::Result<()> {
    let harness = TestCodexHarness::with_config(|c| {
        c.model = Some("gpt-5.1-codex".to_string());
    }).await?;

    harness.submit("hello").await?;
    
    let bodies = harness.request_bodies().await;
    assert_eq!(bodies.len(), 1);
    Ok(())
}
```

---

*Generated: 2026-03-21*
*Research Scope: codex-rs/core/tests/common/*
