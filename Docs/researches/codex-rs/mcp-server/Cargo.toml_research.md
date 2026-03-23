# codex-rs/mcp-server/Cargo.toml 研究文档

## 场景与职责

`Cargo.toml` 是 Rust 项目的清单文件（manifest），定义了 `codex-mcp-server` crate 的元数据、依赖关系和构建配置。该 crate 实现了 **Model Context Protocol (MCP) 服务器**，允许外部客户端通过标准化协议与 Codex AI 系统交互。

### 项目定位

`codex-mcp-server` 是 Codex CLI 的配套服务器组件，它将 Codex 的核心 AI 能力封装为 MCP 工具。MCP 是 Anthropic 推出的开放协议，旨在标准化 AI 模型与外部工具、数据源之间的集成方式。

**核心价值：**
- 使任何支持 MCP 的客户端（Claude Desktop、Cursor、Windsurf 等）都能调用 Codex
- 提供标准化的工具接口（`codex` 和 `codex-reply`）
- 支持执行审批和补丁审批的交互式工作流

## 功能点目的

### 1. 包元数据配置

```toml
[package]
name = "codex-mcp-server"
version.workspace = true
edition.workspace = true
license.workspace = true
```

| 字段 | 值 | 说明 |
|------|-----|------|
| `name` | `codex-mcp-server` | crate 名称，用于 crates.io 发布和依赖引用 |
| `version` | `workspace = true` | 继承工作区根目录定义的版本号 |
| `edition` | `workspace = true` | 继承工作区的 Rust edition（通常是 2021） |
| `license` | `workspace = true` | 继承工作区的许可证配置 |

### 2. 双目标配置（库 + 二进制）

```toml
[[bin]]
name = "codex-mcp-server"
path = "src/main.rs"

[lib]
name = "codex_mcp_server"
path = "src/lib.rs"
```

**设计意图：**
- **二进制目标** (`codex-mcp-server`): 独立运行的 MCP 服务器进程
- **库目标** (`codex_mcp_server`): 允许其他 crate 嵌入使用，也便于测试

**命名规范：**
- 二进制使用 kebab-case (`codex-mcp-server`)：符合 CLI 工具命名习惯
- 库使用 snake_case (`codex_mcp_server`)：符合 Rust crate 命名规范

### 3. Lint 配置

```toml
[lints]
workspace = true
```

继承工作区级别的 Clippy lint 规则，确保代码质量一致性。

### 4. 依赖管理

#### 核心运行时依赖

| 依赖 | 用途 |
|------|------|
| `anyhow` | 错误处理和传播 |
| `tokio` | 异步运行时，支持多线程 |
| `serde`/`serde_json` | JSON 序列化/反序列化 |
| `tracing`/`tracing-subscriber` | 结构化日志和追踪 |
| `rmcp` | MCP 协议 Rust 实现 |
| `schemars` | JSON Schema 生成 |
| `shlex` | Shell 命令解析和转义 |

#### 内部 Workspace 依赖

| 依赖 | 用途 |
|------|------|
| `codex-arg0` | 参数 0 分发路径处理 |
| `codex-core` | Codex 核心功能（ThreadManager, Config 等） |
| `codex-protocol` | 协议类型定义（ThreadId, Event, Op 等） |
| `codex-shell-command` | Shell 命令解析 |
| `codex-utils-cli` | CLI 工具函数 |
| `codex-utils-json-to-toml` | JSON 到 TOML 转换 |

#### 开发依赖

| 依赖 | 用途 |
|------|------|
| `core_test_support` | 核心测试支持库 |
| `mcp_test_support` | MCP 专用测试支持 |
| `os_info` | 操作系统信息获取（测试用） |
| `pretty_assertions` | 美观的测试断言输出 |
| `tempfile` | 临时文件/目录管理 |
| `wiremock` | HTTP Mock 服务器（测试 OpenAI API 调用） |

## 具体技术实现

### Tokio 特性配置

```toml
tokio = { workspace = true, features = [
    "io-std",       # 标准输入输出异步操作
    "macros",       # 异步主函数宏
    "process",      # 异步进程管理
    "rt-multi-thread",  # 多线程运行时
    "signal",       # 信号处理（如 graceful shutdown）
] }
```

**架构设计：**

MCP 服务器采用多任务并发架构：

```
┌─────────────────────────────────────────────────────────┐
│                    Tokio Runtime                        │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐  │
│  │ stdin_reader │  │  processor  │  │ stdout_writer   │  │
│  │             │  │             │  │                 │  │
│  │ 读取 JSON   │──►│ 处理 MCP   │──►│ 写入 JSON-RPC  │  │
│  │ -RPC 请求   │  │ 请求/通知  │  │ 响应           │  │
│  └─────────────┘  └──────┬──────┘  └─────────────────┘  │
│                          │                              │
│                          ▼                              │
│                   ┌─────────────┐                       │
│                   │ ThreadManager│                      │
│                   │ (codex-core) │                      │
│                   └──────┬──────┘                       │
│                          │                              │
│                          ▼                              │
│                   ┌─────────────┐                       │
│                   │  OpenAI API │                       │
│                   └─────────────┘                       │
└─────────────────────────────────────────────────────────┘
```

### Tracing 配置

```toml
tracing = { workspace = true, features = ["log"] }
tracing-subscriber = { workspace = true, features = ["env-filter", "fmt"] }
```

- `log` 特性：兼容 `log` crate 的 API
- `env-filter`：通过环境变量控制日志级别（如 `RUST_LOG=debug`）
- `fmt`：格式化日志输出

### MCP 协议集成 (rmcp)

`rmcp` 是 MCP 协议的 Rust 实现，提供：

- `JsonRpcMessage`: JSON-RPC 消息封装
- `ClientRequest`/`ClientNotification`: 客户端请求/通知类型
- `CallToolRequestParams`: 工具调用参数
- `ServerCapabilities`: 服务器能力声明

## 关键代码路径与文件引用

### 源码结构

```
codex-rs/mcp-server/src/
├── main.rs                    # 二进制入口：参数解析和 run_main 调用
├── lib.rs                     # 库入口：核心运行时逻辑
│   ├── run_main()             # 主运行函数
│   ├── 配置加载               # Config::load_with_cli_overrides
│   ├── OpenTelemetry 初始化   # otel_init::build_provider
│   └── 三任务并发架构         # stdin/processor/stdout
│
├── message_processor.rs       # MCP 消息处理器（核心）
│   ├── process_request()      # 处理 JSON-RPC 请求
│   ├── process_notification() # 处理通知
│   ├── handle_initialize()    # MCP 初始化握手
│   ├── handle_list_tools()    # 返回可用工具列表
│   └── handle_call_tool()     # 执行工具调用
│
├── codex_tool_config.rs       # 工具配置定义
│   ├── CodexToolCallParam     # codex 工具参数
│   ├── CodexToolCallReplyParam # codex-reply 工具参数
│   └── create_tool_for_*()    # 生成工具 JSON Schema
│
├── codex_tool_runner.rs       # 工具执行逻辑
│   ├── run_codex_tool_session()      # 执行 codex 工具
│   ├── run_codex_tool_session_reply() # 执行回复工具
│   └── run_codex_tool_session_inner() # 事件循环处理
│
├── outgoing_message.rs        # 消息发送管理
│   ├── OutgoingMessageSender  # 发送器结构体
│   ├── send_response()        # 发送响应
│   ├── send_event_as_notification() # 发送事件通知
│   └── send_request()         # 发送请求（elicitation）
│
├── exec_approval.rs           # 执行审批处理
│   ├── ExecApprovalElicitRequestParams # 审批请求参数
│   └── handle_exec_approval_request()  # 处理执行审批
│
└── patch_approval.rs          # 补丁审批处理
    ├── PatchApprovalElicitRequestParams # 补丁审批参数
    └── handle_patch_approval_request()  # 处理补丁审批
```

### 测试结构

```
codex-rs/mcp-server/tests/
├── all.rs                     # 集成测试入口
├── suite/
│   └── codex_tool.rs          # Codex 工具集成测试
│       ├── test_shell_command_approval_triggers_elicitation
│       ├── test_patch_approval_triggers_elicitation
│       └── test_codex_tool_passes_base_instructions
└── common/
    ├── lib.rs                 # 测试公共库
    ├── mcp_process.rs         # MCP 进程管理（启动、通信、清理）
    ├── mock_model_server.rs   # Mock OpenAI API 服务器
    └── responses.rs           # SSE 响应构造器
```

## 依赖与外部交互

### 内部依赖详解

#### codex-core

提供 MCP 服务器的核心 AI 能力：

```rust
// lib.rs
let thread_manager = Arc::new(ThreadManager::new(
    config.as_ref(),
    auth_manager,
    SessionSource::Mcp,  // 标识会话来源为 MCP
    CollaborationModesConfig { ... },
));
```

**关键类型：**
- `ThreadManager`: 管理 AI 会话生命周期
- `AuthManager`: 处理 API 认证
- `Config`: 配置管理

#### codex-protocol

定义协议类型：

```rust
// message_processor.rs
use codex_protocol::ThreadId;
use codex_protocol::protocol::{SessionSource, Submission, Op};
```

**关键类型：**
- `ThreadId`: 会话唯一标识
- `Event`/`EventMsg`: 事件类型（ExecApprovalRequest, TurnComplete 等）
- `Op`: 操作类型（UserInput, ExecApproval, PatchApproval 等）

#### rmcp (MCP 协议)

```rust
// message_processor.rs
use rmcp::model::{
    CallToolRequestParams, ClientRequest, JsonRpcRequest,
    ServerCapabilities, ToolsCapability, InitializeResult
};
```

### 外部交互流程

```
┌─────────────────────────────────────────────────────────────────┐
│                        MCP Client                               │
│              (Claude Desktop / Cursor / etc.)                   │
└───────────────────────────┬─────────────────────────────────────┘
                            │ JSON-RPC over stdio
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                     codex-mcp-server                            │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              MessageProcessor                           │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐  │   │
│  │  │ initialize  │  │ tools/list  │  │  tools/call     │  │   │
│  │  └─────────────┘  └─────────────┘  └────────┬────────┘  │   │
│  │                                              │          │   │
│  │  ┌───────────────────────────────────────────▼────────┐ │   │
│  │  │              codex_tool_runner                      │ │   │
│  │  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │ │   │
│  │  │  │  codex      │  │ codex-reply │  │  events     │  │ │   │
│  │  │  │  (新会话)   │  │ (继续会话)  │  │  (流式)     │  │ │   │
│  │  │  └──────┬──────┘  └─────────────┘  └─────────────┘  │ │   │
│  │  └─────────┼───────────────────────────────────────────┘ │   │
│  └────────────┼─────────────────────────────────────────────┘   │
└───────────────┼─────────────────────────────────────────────────┘
                │
                ▼
┌─────────────────────────────────────────────────────────────────┐
│                        codex-core                               │
│                   (ThreadManager)                               │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                      OpenAI API                                 │
│                 (responses API)                                 │
└─────────────────────────────────────────────────────────────────┘
```

## 风险、边界与改进建议

### 当前风险

1. **依赖版本管理**
   - 所有依赖都使用 `workspace = true`，版本集中管理
   - 风险：工作区升级可能影响本 crate 的兼容性

2. **rmcp 版本锁定**
   - MCP 协议仍在演进（2025-03-26 版本）
   - `rmcp` crate 更新可能引入破坏性变更

3. **测试复杂性**
   - 集成测试需要 Mock OpenAI API 服务器
   - 测试依赖网络（某些测试会检查 `CODEX_SANDBOX_NETWORK_DISABLED`）

### 边界情况

1. **平台差异**
   - 代码中处理了 Windows (PowerShell) 和 Unix 的差异
   - 测试中有平台特定的跳过逻辑：
   ```rust
   if cfg!(windows) {
       // powershell apply_patch shell calls are not parsed into apply patch approvals
       return Ok(());
   }
   ```

2. **沙箱环境**
   - 测试会检查 `CODEX_SANDBOX_NETWORK_DISABLED` 环境变量
   - 在沙箱环境中某些测试会被跳过

3. **并发限制**
   - 通道容量固定为 128：
   ```rust
   const CHANNEL_CAPACITY: usize = 128;
   ```
   - 高并发场景可能需要调整

### 改进建议

1. **添加特性标志**

```toml
[features]
default = ["otel"]
otel = ["codex-core/otel"]  # 可选的 OpenTelemetry 支持
# 未来可添加：
# - "experimental": 实验性功能
# - "strict-mode": 严格的 MCP 协议验证
```

2. **细化依赖特性**

```toml
# 当前 tokio 特性较全，可按需精简
tokio = { workspace = true, features = [
    "io-std",
    "macros", 
    "process",
    "rt-multi-thread",
    # "signal",  # 如果不需要信号处理可移除
] }
```

3. **添加文档依赖**

```toml
[package.metadata.docs.rs]
all-features = true
rustdoc-args = ["--cfg", "docsrs"]
```

4. **版本兼容性声明**

```toml
[package.metadata]
# 声明支持的 MCP 协议版本
mcp-protocol-version = "2025-03-26"
```

### 维护注意事项

1. **依赖更新流程**
   ```bash
   # 1. 更新工作区 Cargo.toml
   # 2. 验证本 crate 兼容性
   cargo check -p codex-mcp-server
   
   # 3. 运行测试
   cargo test -p codex-mcp-server
   
   # 4. 更新 Bazel 锁文件
   just bazel-lock-update
   ```

2. **发布检查清单**
   - [ ] 版本号已更新
   - [ ] CHANGELOG 已更新
   - [ ] 所有测试通过
   - [ ] 文档已生成并检查
   - [ ] Bazel 构建验证通过

3. **调试技巧**
   ```bash
   # 启用详细日志
   RUST_LOG=debug cargo run -p codex-mcp-server
   
   # 运行特定测试
   cargo test -p codex-mcp-server test_shell_command_approval
   
   # 集成测试（需要 mock 服务器）
   cargo test -p codex-mcp-server --test all
   ```
