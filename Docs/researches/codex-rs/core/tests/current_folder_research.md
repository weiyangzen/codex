# 研究文档：codex-rs/core/tests 目录

## 目录结构概览

```
codex-rs/core/tests/
├── all.rs                          # 测试入口点，聚合所有测试模块
├── cli_responses_fixture.sse       # CLI SSE 响应 fixture
├── responses_headers.rs            # 响应头测试
├── common/                         # 测试共享库（core_test_support crate）
│   ├── lib.rs                      # 公共测试工具库主入口
│   ├── Cargo.toml                  # 测试库 crate 配置
│   ├── BUILD.bazel                 # Bazel 构建配置
│   ├── apps_test_server.rs         # Apps/MCP 测试服务器模拟
│   ├── context_snapshot.rs         # 请求上下文快照格式化工具
│   ├── process.rs                  # 进程管理工具（PID 等待等）
│   ├── responses.rs                # Mock HTTP/WebSocket 服务器和 SSE 构造器
│   ├── streaming_sse.rs            # 流式 SSE 测试服务器
│   ├── test_codex.rs               # TestCodex 构建器和测试 harness
│   ├── test_codex_exec.rs          # codex-exec 二进制测试工具
│   ├── tracing.rs                  # OpenTelemetry 测试追踪工具
│   └── zsh_fork.rs                 # Zsh fork 运行时测试支持
├── fixtures/                       # 测试数据文件
│   └── incomplete_sse.json         # 不完整 SSE 响应 fixture
└── suite/                          # 测试套件（80+ 个测试模块）
    ├── mod.rs                      # 测试套件模块聚合
    ├── snapshots/                  # insta 快照测试文件
    └── ...                         # 各功能测试模块
```

---

## 1. 场景与职责

### 1.1 核心职责

`codex-rs/core/tests` 是 **Codex Core** crate 的集成测试套件，负责：

1. **端到端功能验证**：测试 Codex 从用户输入到模型响应的完整流程
2. **协议兼容性测试**：验证与 OpenAI Responses API、WebSocket、MCP 协议的交互
3. **沙箱安全测试**：验证 Seatbelt、Landlock、Seccomp 等沙箱机制
4. **会话状态管理**：测试 rollout 持久化、resume、compact 等状态操作
5. **工具调用测试**：验证 shell、apply_patch、file_search 等工具行为
6. **多模态支持**：测试图像、实时对话、Web 搜索等功能

### 1.2 测试架构设计

```
┌─────────────────────────────────────────────────────────────────┐
│                        Test Suite Architecture                   │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────────┐  │
│  │  all.rs     │───▶│  suite/mod  │───▶│  Individual Tests   │  │
│  │  (entry)    │    │  (modules)  │    │  (80+ modules)      │  │
│  └─────────────┘    └─────────────┘    └─────────────────────┘  │
│         │                                                    │  │
│         ▼                                                    │  │
│  ┌──────────────────────────────────────────────────────────┐│  │
│  │              core_test_support (common/)                 ││  │
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────────────┐ ││  │
│  │  │ TestCodex   │ │ MockServer  │ │  Event Assertions   │ ││  │
│  │  │ Builder     │ │ (wiremock)  │ │  (wait_for_event)   │ ││  │
│  │  └─────────────┘ └─────────────┘ └─────────────────────┘ ││  │
│  └──────────────────────────────────────────────────────────┘│  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. 功能点目的

### 2.1 common/ 测试支持库

| 模块 | 功能目的 | 关键能力 |
|------|----------|----------|
| `lib.rs` | 测试基础设施入口 | 配置加载、路径处理、宏定义（skip_if_sandbox, skip_if_no_network） |
| `test_codex.rs` | TestCodex 构建器 | 创建隔离的 Codex 实例，支持 mock 服务器、配置覆盖、resume |
| `responses.rs` | Mock 服务器和 SSE 构造 | wiremock 集成、SSE 事件构造器、请求捕获和验证 |
| `streaming_sse.rs` | 流式 SSE 服务器 | 支持 gated chunk 的流式响应测试，用于测试超时、中断场景 |
| `context_snapshot.rs` | 请求快照格式化 | 将 API 请求转换为可读的快照格式，用于 insta 快照测试 |
| `apps_test_server.rs` | Apps/MCP 模拟 | 模拟 Calendar/Gmail 等 connector 的 MCP 协议响应 |
| `zsh_fork.rs` | Zsh fork 测试支持 | 支持 ShellZshFork 特性的测试环境搭建 |
| `process.rs` | 进程管理 | PID 文件等待、进程存活检测 |
| `tracing.rs` | OpenTelemetry 测试 | 测试追踪上下文设置 |
| `test_codex_exec.rs` | codex-exec 测试 | codex-exec 二进制命令构建 |

### 2.2 suite/ 测试模块分类

#### A. 核心客户端测试 (Client)
- `client.rs` - 基础客户端功能：认证、header、指令、会话恢复
- `client_websockets.rs` - WebSocket 实时对话测试
- `resume.rs` - 会话恢复功能
- `resume_warning.rs` - 恢复警告场景

#### B. 模型与配置测试 (Model)
- `model_overrides.rs` - 模型覆盖配置
- `model_info_overrides.rs` - 模型信息覆盖
- `model_switching.rs` - 运行时模型切换
- `model_visible_layout.rs` - 模型可见布局（快照测试）
- `remote_models.rs` - 远程模型列表
- `models_cache_ttl.rs` - 模型缓存 TTL
- `models_etag_responses.rs` - ETag 响应处理

#### C. 上下文压缩测试 (Compact)
- `compact.rs` - 手动/自动上下文压缩
- `compact_remote.rs` - 远程压缩端点测试
- `compact_resume_fork.rs` - 压缩后恢复和 fork

#### D. 工具调用测试 (Tools)
- `tools.rs` - 基础工具调用、超时、沙箱拒绝
- `shell_command.rs` - Shell 命令执行
- `shell_serialization.rs` - Shell 序列化
- `shell_snapshot.rs` - Shell 快照测试
- `user_shell_cmd.rs` - 用户 shell 命令
- `apply_patch_cli.rs` - apply_patch CLI 测试
- `read_file.rs` - 文件读取工具
- `list_dir.rs` - 目录列表工具
- `grep_files.rs` - 文件搜索工具
- `search_tool.rs` - 搜索工具
- `view_image.rs` - 图像查看工具
- `web_search.rs` - Web 搜索工具
- `js_repl.rs` - JavaScript REPL 工具
- `image_rollout.rs` - 图像 rollout 处理

#### E. 执行与沙箱测试 (Execution)
- `exec.rs` - macOS Seatbelt 沙箱执行（仅 macOS）
- `exec_policy.rs` - 执行策略测试
- `seatbelt.rs` - Seatbelt 沙箱特定测试
- `unified_exec.rs` - UnifiedExec 工具测试
- `sandbox_denied.rs` - 沙箱拒绝场景

#### F. Agent 与子代理测试 (Agent)
- `agent_jobs.rs` - Agent 作业管理
- `agent_websocket.rs` - Agent WebSocket 通信
- `hierarchical_agents.rs` - 层级 Agent 结构
- `spawn_agent_description.rs` - 子代理描述
- `subagent_notifications.rs` - 子代理通知
- `codex_delegate.rs` - Codex 委托

#### G. 权限与审批测试 (Permissions)
- `approvals.rs` - 审批流程
- `request_permissions.rs` - 权限请求
- `request_permissions_tool.rs` - 工具权限请求
- `skill_approval.rs` - Skill 审批
- `permissions_messages.rs` - 权限消息

#### H. 会话与状态测试 (Session)
- `sqlite_state.rs` - SQLite 状态存储
- `turn_state.rs` - Turn 状态管理
- `pending_input.rs` - 待处理输入
- `items.rs` - 响应项处理
- `undo.rs` - 撤销操作
- `fork_thread.rs` - 线程 fork

#### I. 协议与通信测试 (Protocol)
- `cli_stream.rs` - CLI 流式响应
- `websocket_fallback.rs` - WebSocket 降级
- `stream_error_allows_next_turn.rs` - 流错误恢复
- `stream_no_completed.rs` - 无 completed 事件处理
- `request_compression.rs` - 请求压缩 (zstd)
- `responses_headers.rs` - 响应头验证

#### J. 特性与扩展测试 (Features)
- `skills.rs` - Skills 系统
- `plugins.rs` - Plugins 系统
- `hooks.rs` - Hooks 系统
- `collaboration_instructions.rs` - 协作指令
- `personality.rs` - Personality 配置
- `personality_migration.rs` - Personality 迁移
- `memories.rs` - Memories 功能
- `code_mode.rs` - Code 模式

#### K. 其他测试
- `auth_refresh.rs` - 认证刷新
- `deprecation_notice.rs` - 弃用通知
- `live_cli.rs` - 实时 CLI
- `live_reload.rs` - 实时重载
- `otel.rs` - OpenTelemetry 集成
- `override_updates.rs` - 配置覆盖更新
- `prompt_caching.rs` - 提示缓存
- `quota_exceeded.rs` - 配额超限
- `realtime_conversation.rs` - 实时对话
- `review.rs` - 审查功能
- `rmcp_client.rs` - RMCP 客户端
- `rollout_list_find.rs` - Rollout 列表查找
- `safety_check_downgrade.rs` - 安全检查降级
- `text_encoding_fix.rs` - 文本编码修复
- `tool_harness.rs` - 工具 harness
- `tool_parallelism.rs` - 工具并行执行
- `truncation.rs` - 截断处理
- `unstable_features_warning.rs` - 不稳定特性警告
- `user_notification.rs` - 用户通知
- `json_result.rs` - JSON 结果输出
- `abort_tasks.rs` - 任务中止

---

## 3. 具体技术实现

### 3.1 TestCodex 构建器模式

```rust
// tests/common/test_codex.rs
pub struct TestCodexBuilder {
    config_mutators: Vec<Box<ConfigMutator>>,
    auth: CodexAuth,
    pre_build_hooks: Vec<Box<PreBuildHook>>,
    home: Option<Arc<TempDir>>,
    user_shell_override: Option<Shell>,
}

impl TestCodexBuilder {
    pub fn with_config<T>(mut self, mutator: T) -> Self
    pub fn with_model(self, model: &str) -> Self
    pub fn with_auth(mut self, auth: CodexAuth) -> Self
    pub async fn build(&mut self, server: &MockServer) -> anyhow::Result<TestCodex>
    pub async fn resume(&mut self, server: &MockServer, home: Arc<TempDir>, rollout_path: PathBuf) -> anyhow::Result<TestCodex>
}
```

**关键设计**：
- 使用 `TempDir` 隔离每个测试的 `CODEX_HOME`，避免污染开发者真实配置
- 支持配置覆盖链式调用
- 自动配置 mock 服务器为模型 provider

### 3.2 Mock 服务器与 SSE 构造

```rust
// tests/common/responses.rs

// SSE 事件构造器
pub fn sse(events: Vec<Value>) -> String
pub fn ev_completed(id: &str) -> Value
pub fn ev_function_call(call_id: &str, name: &str, arguments: &str) -> Value
pub fn ev_assistant_message(id: &str, text: &str) -> Value

// Mock 服务器挂载
pub async fn mount_sse_once(server: &MockServer, body: String) -> ResponseMock
pub async fn mount_sse_sequence(server: &MockServer, responses: Vec<String>) -> ResponseMock
pub async fn start_mock_server() -> MockServer

// 请求捕获和验证
pub struct ResponseMock {
    requests: Arc<Mutex<Vec<ResponsesRequest>>>,
}
impl ResponseMock {
    pub fn single_request(&self) -> ResponsesRequest
    pub fn requests(&self) -> Vec<ResponsesRequest>
    pub fn saw_function_call(&self, call_id: &str) -> bool
}
```

### 3.3 事件等待与断言

```rust
// tests/common/lib.rs
pub async fn wait_for_event<F>(
    codex: &CodexThread,
    predicate: F,
) -> codex_protocol::protocol::EventMsg
where
    F: FnMut(&codex_protocol::protocol::EventMsg) -> bool,

pub async fn wait_for_event_with_timeout<F>(
    codex: &CodexThread,
    mut predicate: F,
    wait_time: tokio::time::Duration,
) -> codex_protocol::protocol::EventMsg
```

**使用模式**：
```rust
// 等待特定事件
let turn_id = wait_for_event_match(&codex, |event| match event {
    EventMsg::TurnStarted(event) => Some(event.turn_id.clone()),
    _ => None,
}).await;

// 等待 turn 完成
wait_for_event(&codex, |event| matches!(event, EventMsg::TurnComplete(_))).await;
```

### 3.4 流式 SSE 服务器

```rust
// tests/common/streaming_sse.rs
pub struct StreamingSseChunk {
    pub gate: Option<oneshot::Receiver<()>>,  // 控制 chunk 发送时机
    pub body: String,
}

pub async fn start_streaming_sse_server(
    responses: Vec<Vec<StreamingSseChunk>>,
) -> (StreamingSseServer, Vec<oneshot::Receiver<i64>>)
```

**用途**：测试流式响应中断、超时、背压等场景。

### 3.5 上下文快照测试

```rust
// tests/common/context_snapshot.rs
pub fn format_request_input_snapshot(
    request: &ResponsesRequest,
    options: &ContextSnapshotOptions,
) -> String

pub fn format_response_items_snapshot(
    items: &[Value],
    options: &ContextSnapshotOptions,
) -> String
```

**功能**：
- 将 API 请求转换为可读文本格式
- 支持敏感信息脱敏（RedactedText 模式）
- 支持能力指令剥离（strip_capability_instructions）
- 与 `insta` 快照测试框架集成

### 3.6 条件编译与平台特定测试

```rust
// tests/suite/mod.rs
#[cfg(not(target_os = "windows"))]
mod abort_tasks;
mod agent_jobs;
...
#[cfg(not(target_os = "windows"))]
mod hooks;
...
#[cfg(not(target_os = "windows"))]
mod request_permissions;
#[cfg(not(target_os = "windows"))]
mod request_permissions_tool;
```

**平台跳过宏**：
```rust
// tests/common/lib.rs
#[macro_export]
macro_rules! skip_if_sandbox {
    () => {{ if env::var($crate::sandbox_env_var()) == Ok("seatbelt".to_string()) { return; } }};
}

#[macro_export]
macro_rules! skip_if_no_network {
    () => {{ if env::var($crate::sandbox_network_env_var()).is_ok() { return; } }};
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 测试执行流程

```
1. all.rs
   └── mod suite;  // 引入 suite/mod.rs

2. suite/mod.rs
   └── #[ctor] static CODEX_ALIASES_TEMP_DIR  // 测试前初始化
   └── mod client;  // 等 80+ 模块

3. 单个测试（如 suite/client.rs）
   └── #[tokio::test]
       └── test_codex().build(&server).await  // 使用 common/test_codex.rs
       └── mount_sse_once(&server, ...)       // 使用 common/responses.rs
       └── wait_for_event(&codex, ...)        // 使用 common/lib.rs
```

### 4.2 核心依赖链

```
codex-core (被测 crate)
    ▲
    │ 使用 ThreadManager, CodexThread, Config 等
    │
core_test_support (测试库)
    │
    ├── wiremock (HTTP mock 服务器)
    ├── tokio-tungstenite (WebSocket 测试)
    ├── insta (快照测试)
    ├── tempfile (临时目录)
    └── pretty_assertions (更好的断言输出)
```

### 4.3 关键文件索引

| 功能 | 文件路径 |
|------|----------|
| 测试入口 | `codex-rs/core/tests/all.rs` |
| 测试模块聚合 | `codex-rs/core/tests/suite/mod.rs` |
| 测试库主入口 | `codex-rs/core/tests/common/lib.rs` |
| TestCodex 构建器 | `codex-rs/core/tests/common/test_codex.rs` |
| Mock 服务器 | `codex-rs/core/tests/common/responses.rs` |
| 流式 SSE 服务器 | `codex-rs/core/tests/common/streaming_sse.rs` |
| 快照格式化 | `codex-rs/core/tests/common/context_snapshot.rs` |
| Apps 测试服务器 | `codex-rs/core/tests/common/apps_test_server.rs` |
| Zsh fork 支持 | `codex-rs/core/tests/common/zsh_fork.rs` |
| 进程工具 | `codex-rs/core/tests/common/process.rs` |
| 追踪工具 | `codex-rs/core/tests/common/tracing.rs` |
| codex-exec 测试 | `codex-rs/core/tests/common/test_codex_exec.rs` |
| 测试库配置 | `codex-rs/core/tests/common/Cargo.toml` |

---

## 5. 依赖与外部交互

### 5.1 内部依赖

| Crate | 用途 |
|-------|------|
| `codex-core` | 被测 crate，提供 ThreadManager、CodexThread、Config 等 |
| `codex-protocol` | 协议类型定义（EventMsg、Op、ResponseItem 等） |
| `codex-utils-cargo-bin` | 定位测试二进制文件 |
| `codex-utils-absolute-path` | 绝对路径处理 |
| `codex-arg0` | arg0 分发测试支持 |

### 5.2 外部依赖

| Crate | 用途 |
|-------|------|
| `wiremock` | HTTP mock 服务器，模拟 OpenAI API |
| `tokio-tungstenite` | WebSocket 服务器和客户端 |
| `insta` | 快照测试框架 |
| `tempfile` | 临时目录和文件 |
| `pretty_assertions` | 美观的断言输出 |
| `assert_cmd` | CLI 二进制测试 |
| `predicates` | 断言谓词 |
| `serde_json` | JSON 序列化/反序列化 |
| `tokio` | 异步运行时 |
| `futures` | 异步工具 |
| `notify` | 文件系统监视（fs_wait 模块） |
| `walkdir` | 目录遍历 |
| `zstd` | 请求体压缩解码 |
| `opentelemetry` / `tracing-opentelemetry` | 分布式追踪测试 |

### 5.3 测试数据与 Fixtures

| 文件 | 用途 |
|------|------|
| `cli_responses_fixture.sse` | CLI SSE 响应示例 |
| `fixtures/incomplete_sse.json` | 不完整 SSE 事件测试数据 |
| `suite/snapshots/*.snap` | insta 快照文件（30+ 个） |

---

## 6. 风险、边界与改进建议

### 6.1 当前风险

#### A. 平台差异风险
- **Windows 支持不完整**：大量测试使用 `#[cfg(not(target_os = "windows"))]` 跳过
  - 影响模块：hooks、request_permissions、request_permissions_tool、abort_tasks、approvals
  - 风险：Windows 平台行为未充分验证

#### B. 网络依赖风险
- **skip_if_no_network 宏**：部分测试需要网络访问，在沙箱环境中被跳过
  - 可能导致沙箱 CI 中测试覆盖率下降
  - 建议：增加纯本地 mock 测试作为补充

#### C. 沙箱环境限制
- **skip_if_sandbox 宏**：Seatbelt 沙箱中部分测试被跳过
  - 原因：沙箱内无法嵌套沙箱，或需要特定系统权限
  - 风险：沙箱相关代码路径在沙箱 CI 中未测试

#### D. 测试执行时间
- **流式测试超时**：`wait_for_event_with_timeout` 默认 10 秒超时
  - 在慢速 CI 环境中可能 flaky
  - 建议：根据 CI 环境动态调整超时

### 6.2 边界情况

#### A. 并发测试边界
```rust
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
```
- 多线程运行时可能暴露竞态条件
- 建议：关键路径增加单线程测试验证

#### B. 资源清理边界
- `TempDir` 在测试结束时自动清理
- 风险：测试 panic 时可能泄漏临时文件
- 缓解：`#[ctor]` 初始化的 `CODEX_ALIASES_TEMP_DIR` 使用 `Arg0PathEntryGuard` 确保清理

#### C. 快照测试边界
- 快照文件与代码变更同步
- 风险：模型输出格式变更导致大量快照失效
- 缓解：使用 `context_snapshot.rs` 的脱敏模式减少敏感数据

### 6.3 改进建议

#### A. 测试覆盖率
1. **增加 Windows 测试覆盖**
   - 优先实现 hooks、permissions 的 Windows 兼容测试
   - 使用 Windows 容器或 VM 运行 CI

2. **增加错误路径测试**
   - 当前测试主要关注正常路径
   - 建议增加：网络超时、API 错误响应、磁盘满等异常场景

3. **增加并发压力测试**
   - 多 turn 并发提交
   - 大量工具调用并行执行

#### B. 测试基础设施
1. **统一测试超时配置**
   ```rust
   // 建议：从环境变量读取超时
   const TEST_TIMEOUT: Duration = Duration::from_secs(
       env::var("CODEX_TEST_TIMEOUT_SECS")
           .ok()
           .and_then(|s| s.parse().ok())
           .unwrap_or(10)
   );
   ```

2. **增强日志输出**
   - 测试失败时自动输出 Codex 事件日志
   - 集成 `tracing` 的测试订阅器

3. **并行测试优化**
   - 使用 `cargo-nextest` 提高并行度
   - 隔离共享资源（如端口分配）

#### C. 维护性改进
1. **测试文档化**
   - 为复杂测试增加注释说明测试意图
   - 使用 `rustdoc` 生成测试 API 文档

2. **快照测试管理**
   - 定期审查快照文件大小
   - 压缩或分割过大的快照文件

3. **依赖更新策略**
   - `wiremock`、`insta` 等关键依赖及时跟进
   - 评估 `tokio-tungstenite` 的替代方案（如 `fastwebsockets`）

#### D. 安全测试增强
1. **沙箱逃逸测试**
   - 增加恶意 payload 测试
   - 验证沙箱边界（文件系统、网络、进程）

2. **认证安全测试**
   - JWT token 过期处理
   - API key 泄露检测

---

## 7. 附录：测试运行指南

### 7.1 运行全部测试
```bash
cd codex-rs
cargo test -p codex-core
```

### 7.2 运行特定模块测试
```bash
cargo test -p codex-core compact       # 仅运行 compact 相关测试
cargo test -p codex-core client        # 仅运行 client 测试
```

### 7.3 快照测试管理
```bash
# 查看待审查快照
cargo insta pending-snapshots -p codex-core

# 接受所有新快照
cargo insta accept -p codex-core

# 查看特定快照差异
cargo insta show -p codex-core path/to/file.snap.new
```

### 7.4 使用 nextest（推荐）
```bash
# 安装 cargo-nextest
cargo install cargo-nextest

# 运行测试（并行度更高）
cargo nextest run -p codex-core
```

---

*文档生成时间：2026-03-21*
*研究范围：codex-rs/core/tests 目录及其子目录*
