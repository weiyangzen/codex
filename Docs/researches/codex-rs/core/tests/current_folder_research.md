# DIR codex-rs/core/tests 研究文档

## 场景与职责

`codex-rs/core/tests` 是 Codex Rust 核心库的集成测试目录，负责验证 `codex-core` crate 的端到端行为。该目录包含 133+ 个文件，构成了一套全面的集成测试体系，模拟真实的 Codex 使用场景，包括：

- **API 交互测试**：模拟 OpenAI Responses API 的 SSE 流和 WebSocket 通信
- **工具执行测试**：验证 shell 命令、文件操作、代码补丁等工具的正确性
- **沙箱安全测试**：测试 Seatbelt (macOS) 和 Landlock (Linux) 沙箱策略
- **会话管理测试**：验证对话恢复、上下文压缩、多轮对话状态保持
- **配置与特性测试**：测试各种配置选项和特性开关的行为

该测试目录是确保 Codex 核心功能稳定性和安全性的关键基础设施。

## 功能点目的

### 1. 测试基础设施 (common/)

提供共享的测试工具和模拟服务器：

| 模块 | 目的 |
|------|------|
| `lib.rs` | 测试入口，提供配置加载、SSE fixture 加载、事件等待等通用工具 |
| `test_codex.rs` | `TestCodex` 构建器，用于创建配置好的测试 Codex 实例 |
| `test_codex_exec.rs` | `codex-exec` 二进制文件的测试支持 |
| `responses.rs` | Mock SSE 服务器和 WebSocket 测试服务器，模拟 OpenAI API |
| `streaming_sse.rs` | 流式 SSE 服务器，支持分块控制的响应模拟 |
| `apps_test_server.rs` | MCP Apps/Connectors 的模拟服务器 |
| `context_snapshot.rs` | 请求/响应快照格式化，用于 insta 快照测试 |
| `process.rs` | 进程生命周期管理工具 |
| `tracing.rs` | OpenTelemetry 测试追踪支持 |
| `zsh_fork.rs` | Zsh fork 模式测试支持 |

### 2. 测试套件 (suite/)

按功能域组织的测试模块：

**核心功能测试：**
- `client.rs` - ModelClient 的流式响应、认证、会话恢复测试
- `tools.rs` - 工具调用（shell、apply_patch、自定义工具）测试
- `shell_command.rs` - Shell 命令执行的各种场景
- `read_file.rs`, `list_dir.rs`, `grep_files.rs` - 文件系统工具测试
- `apply_patch_cli.rs` - 代码补丁应用测试

**沙箱与安全测试：**
- `exec.rs` - macOS Seatbelt 沙箱执行测试
- `seatbelt.rs` - Seatbelt 沙箱策略验证
- `exec_policy.rs` - 执行策略检查
- `request_permissions.rs` - 权限请求流程

**会话与状态管理：**
- `compact.rs` - 上下文压缩（summarization）测试
- `compact_remote.rs` - 远程模型压缩测试
- `compact_resume_fork.rs` - 压缩后的恢复和分支测试
- `resume.rs` - 会话恢复测试
- `undo.rs` - 撤销操作测试

**网络与协议测试：**
- `client_websockets.rs` - WebSocket 实时通信测试
- `websocket_fallback.rs` - WebSocket 降级到 SSE 测试
- `request_compression.rs` - 请求压缩测试
- `responses_headers.rs` - HTTP 头验证测试

**代理与多智能体：**
- `agent_jobs.rs` - 代理任务测试
- `agent_websocket.rs` - 代理 WebSocket 通信
- `hierarchical_agents.rs` - 层级代理测试
- `spawn_agent_description.rs` - 子代理描述测试

**配置与特性：**
- `model_switching.rs` - 模型切换测试
- `model_overrides.rs` - 模型配置覆盖
- `skills.rs` - Skills 系统测试
- `plugins.rs` - 插件系统测试
- `prompt_caching.rs` - 提示缓存测试

### 3. 测试 Fixtures

- `cli_responses_fixture.sse` - SSE 响应格式示例
- `fixtures/incomplete_sse.json` - 不完整 SSE 事件测试数据
- `suite/snapshots/` - insta 快照测试的预期输出

## 具体技术实现

### 关键流程

#### 1. 测试生命周期流程

```
all.rs (测试入口)
    └── suite/mod.rs (测试模块聚合)
        ├── #[ctor] CODEX_ALIASES_TEMP_DIR (初始化测试环境)
        │   └── 设置临时 CODEX_HOME
        │   └── arg0_dispatch() 创建命令别名
        └── 各测试模块...
```

#### 2. Mock Server 响应流程

```rust
// 1. 启动 Mock 服务器
let server = responses::start_mock_server().await;

// 2. 挂载 SSE 响应
let mock = responses::mount_sse_once(
    &server,
    responses::sse(vec![
        responses::ev_response_created("resp-1"),
        responses::ev_function_call(call_id, "shell", &arguments),
        responses::ev_completed("resp-1"),
    ]),
).await;

// 3. 构建测试 Codex
let test = test_codex().build(&server).await?;

// 4. 提交用户输入
test.submit_turn("run command").await?;

// 5. 验证请求
let request = mock.single_request();
assert!(request.has_function_call(call_id));
```

#### 3. 事件等待流程

```rust
// 等待特定事件
let ev = wait_for_event(&codex, |ev| {
    matches!(ev, EventMsg::TurnComplete { .. })
}).await;

// 等待事件并提取数据
let turn_id = wait_for_event_match(&codex, |ev| match ev {
    EventMsg::TurnStarted(event) => Some(event.turn_id.clone()),
    _ => None,
}).await;
```

### 关键数据结构

#### TestCodex 结构

```rust
pub struct TestCodex {
    pub home: Arc<TempDir>,           // 临时 CODEX_HOME
    pub cwd: Arc<TempDir>,            // 临时工作目录
    pub codex: Arc<CodexThread>,      // 被测 Codex 实例
    pub session_configured: SessionConfiguredEvent,
    pub config: Config,
    pub thread_manager: Arc<ThreadManager>,
}
```

#### SSE 事件构建器

```rust
// 事件类型
pub fn ev_response_created(id: &str) -> Value;
pub fn ev_completed(id: &str) -> Value;
pub fn ev_function_call(call_id: &str, name: &str, arguments: &str) -> Value;
pub fn ev_custom_tool_call(call_id: &str, name: &str, input: &str) -> Value;
pub fn ev_assistant_message(id: &str, text: &str) -> Value;
pub fn ev_reasoning_item(id: &str, summary: &[&str], raw_content: &[&str]) -> Value;

// SSE 流构建
pub fn sse(events: Vec<Value>) -> String;
```

#### ResponsesRequest 请求检查器

```rust
impl ResponsesRequest {
    pub fn body_json(&self) -> Value;
    pub fn input(&self) -> Vec<Value>;
    pub fn function_call_output(&self, call_id: &str) -> Value;
    pub fn has_function_call(&self, call_id: &str) -> bool;
    pub fn header(&self, name: &str) -> Option<String>;
    pub fn message_input_texts(&self, role: &str) -> Vec<String>;
}
```

### 协议与命令

#### 支持的 Mock API 端点

| 端点 | 方法 | 用途 |
|------|------|------|
| `/v1/models` | GET | 模型列表查询 |
| `/v1/responses` | POST | 主要对话端点 (SSE) |
| `/v1/responses/compact` | POST | 上下文压缩端点 |

#### 测试宏

```rust
// 跳过沙盒中的测试
skip_if_sandbox!();

// 跳过无网络测试
skip_if_no_network!();

// Linux 沙盒二进制文件检查
codex_linux_sandbox_exe_or_skip!();
```

## 关键代码路径与文件引用

### 核心测试基础设施

| 文件 | 职责 | 关键类型/函数 |
|------|------|---------------|
| `tests/all.rs` | 测试入口 | `mod suite;` |
| `tests/suite/mod.rs` | 测试模块聚合 | `CODEX_ALIASES_TEMP_DIR` |
| `tests/common/lib.rs` | 通用测试工具 | `load_default_config_for_test`, `wait_for_event` |
| `tests/common/test_codex.rs` | Codex 测试构建器 | `TestCodexBuilder`, `TestCodexHarness` |
| `tests/common/responses.rs` | Mock 响应服务器 | `start_mock_server`, `mount_sse_once` |

### 主要测试模块

| 文件 | 测试范围 | 关键测试 |
|------|----------|----------|
| `tests/suite/client.rs` | ModelClient 核心功能 | `resume_includes_initial_messages`, `stream_yields_events` |
| `tests/suite/tools.rs` | 工具调用 | `shell_escalated_permissions_rejected`, `sandbox_denied_shell_returns_original_output` |
| `tests/suite/shell_command.rs` | Shell 执行 | `shell_command_works`, `output_with_login` |
| `tests/suite/compact.rs` | 上下文压缩 | `manual_compact_with_history`, `pre_turn_compaction` |
| `tests/suite/exec.rs` | 沙箱执行 | `exit_code_0_succeeds`, `write_file_fails_as_sandbox_error` |
| `tests/suite/resume.rs` | 会话恢复 | `resume_from_rollout`, `resume_preserves_model` |

### 快照测试文件

位于 `tests/suite/snapshots/`，使用 insta 框架：
- `all__suite__compact__*.snap` - 压缩测试快照
- `all__suite__compact_remote__*.snap` - 远程压缩测试快照
- `all__suite__model_visible_layout__*.snap` - 模型可见布局快照

## 依赖与外部交互

### 内部依赖

```
codex-core (被测库)
├── codex-protocol (协议类型)
├── codex-otel (遥测)
├── codex-utils-* (工具库)
└── core_test_support (测试支持库)
    ├── codex-core
    ├── codex-protocol
    ├── wiremock (HTTP mock)
    ├── tokio (异步运行时)
    └── insta (快照测试)
```

### 外部依赖

| Crate | 用途 |
|-------|------|
| `wiremock` | HTTP Mock 服务器 |
| `tokio` | 异步运行时 |
| `insta` | 快照测试 |
| `tempfile` | 临时目录管理 |
| `serde_json` | JSON 处理 |
| `assert_cmd` | CLI 测试 |
| `pretty_assertions` | 美观的断言输出 |

### 系统依赖

- **zsh**: Zsh fork 模式测试需要特定版本的 zsh
- **dotslash**: 用于获取测试用的 zsh 二进制文件
- **codex-linux-sandbox**: Linux 沙箱测试需要此二进制文件
- **codex-execve-wrapper**: Zsh fork 测试需要

### 网络依赖

部分测试需要网络访问（使用 `skip_if_no_network!()` 宏跳过）：
- 实际的 API 调用测试
- 模型列表获取测试
- OAuth 流程测试

## 风险、边界与改进建议

### 当前风险

1. **平台特定代码分散**
   - 大量 `#[cfg(not(target_os = "windows"))]` 和 `#[cfg(target_os = "macos")]` 条件编译
   - 某些测试仅在特定平台运行，可能导致跨平台回归

2. **测试执行时间**
   - 集成测试涉及完整的 Codex 启动流程，执行时间较长
   - 部分测试使用 `tokio::time::timeout`，在慢速 CI 环境可能不稳定

3. **外部二进制依赖**
   - 依赖 `codex-linux-sandbox`、`codex-execve-wrapper` 等二进制文件
   - 如果这些二进制文件未构建，相关测试会被跳过，可能掩盖问题

4. **快照测试维护成本**
   - 大量 `.snap` 文件需要随代码变更更新
   - 格式变更可能导致大量快照需要重新生成

### 边界情况

1. **沙盒环境检测**
   - 测试通过 `CODEX_SANDBOX` 环境变量检测是否在沙盒中运行
   - 在 Seatbelt 沙盒中某些测试会被跳过（如 `exec.rs`）

2. **网络禁用环境**
   - `CODEX_SANDBOX_NETWORK_DISABLED` 环境变量控制网络测试跳过

3. **临时目录生命周期**
   - 使用 `TempDir` 确保测试隔离，但需要小心处理跨异步任务的目录引用

### 改进建议

1. **测试分类标记**
   - 使用更细粒度的测试分类属性
   - 例如：`#[test_category("network_required")]`, `#[test_category("slow")]`

2. **Mock 服务器复用**
   - 当前每个测试启动独立的 MockServer
   - 考虑使用共享的 MockServer 减少启动开销

3. **测试数据工厂**
   - 建立统一的测试数据生成工厂，减少重复代码
   - 例如：统一的 SSE 响应序列生成器

4. **增强文档**
   - 为复杂的测试场景添加更多内联文档
   - 特别是 `compact.rs` 和 `client.rs` 中的复杂状态机测试

5. **并行测试优化**
   - 当前使用 `serial_test` 的部分测试可以评估是否真正需要串行
   - 提高并行度以缩短测试时间

6. **覆盖率监控**
   - 建议添加代码覆盖率监控，确保关键路径有测试覆盖
   - 特别关注错误处理分支的覆盖

---

*文档生成时间: 2026-03-21*
*研究范围: codex-rs/core/tests 目录及其子目录*
