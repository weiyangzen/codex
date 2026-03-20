# codex-rs/exec 深度研究文档

## 1. 场景与职责

`codex-rs/exec` 是 OpenAI Codex CLI 的非交互式执行组件，提供 headless（无界面）模式下的 AI 辅助编程能力。它是 `codex` 多工具 CLI 的核心执行引擎之一。

### 核心定位

- **非交互式执行**: 与 `codex-rs/tui`（交互式终端界面）相对，`exec` 专为脚本化、自动化场景设计
- **CI/CD 集成**: 支持在持续集成流水线中自动执行代码审查、重构等任务
- **批处理模式**: 可通过管道接收输入，输出结构化 JSONL 或人类可读文本

### 主要使用场景

| 场景 | 说明 |
|------|------|
| 代码审查 (`review`) | 审查未提交更改、对比分支差异、审查特定提交 |
| 会话恢复 (`resume`) | 恢复之前的对话会话，继续执行任务 |
| 单次任务执行 | 直接传入 prompt，执行代码生成、修改等任务 |
| OSS 模式 | 连接本地 LLM（LMStudio/Ollama）而非 OpenAI API |

---

## 2. 功能点目的

### 2.1 CLI 命令结构

```
codex-exec [OPTIONS] [PROMPT]
codex-exec resume [OPTIONS] [SESSION_ID] [PROMPT]
codex-exec review [OPTIONS] [PROMPT]
```

### 2.2 核心功能模块

| 功能 | 目的 |
|------|------|
| `--json` / `--experimental-json` | 输出 JSONL 格式事件流，便于程序解析 |
| `--full-auto` | 全自动模式（低摩擦沙箱自动执行） |
| `--dangerously-bypass-approvals-and-sandbox` (`--yolo`) | 完全绕过审批和沙箱（仅用于外部已沙箱环境） |
| `--sandbox` | 选择沙箱策略：read-only / workspace-write / danger-full-access |
| `--oss` + `--local-provider` | 使用开源本地 LLM 替代 OpenAI API |
| `--ephemeral` | 不持久化会话文件（临时模式） |
| `--output-schema` | 指定 JSON Schema 约束模型输出格式 |
| `--add-dir` | 添加额外的可写目录 |
| `--resume --last` | 恢复最近的会话 |

### 2.3 双模式输出

1. **人类可读模式** (`EventProcessorWithHumanOutput`)
   - 彩色终端输出，带进度指示器
   - 文件变更的彩色 diff 展示
   - 命令执行结果的格式化输出

2. **JSONL 模式** (`EventProcessorWithJsonOutput`)
   - 结构化事件流，每行一个 JSON 对象
   - 支持 `thread.started`, `turn.started`, `item.completed` 等事件类型
   - 便于下游工具链集成

---

## 3. 具体技术实现

### 3.1 关键数据结构

#### 3.1.1 核心事件类型 (`exec_events.rs`)

```rust
/// 顶级 JSONL 事件枚举
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, TS)]
#[serde(tag = "type")]
pub enum ThreadEvent {
    #[serde(rename = "thread.started")]
    ThreadStarted(ThreadStartedEvent),
    #[serde(rename = "turn.started")]
    TurnStarted(TurnStartedEvent),
    #[serde(rename = "turn.completed")]
    TurnCompleted(TurnCompletedEvent),
    #[serde(rename = "turn.failed")]
    TurnFailed(TurnFailedEvent),
    #[serde(rename = "item.started")]
    ItemStarted(ItemStartedEvent),
    #[serde(rename = "item.updated")]
    ItemUpdated(ItemUpdatedEvent),
    #[serde(rename = "item.completed")]
    ItemCompleted(ItemCompletedEvent),
    #[serde(rename = "error")]
    Error(ThreadErrorEvent),
}

/// ThreadItem 详情变体
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ThreadItemDetails {
    AgentMessage(AgentMessageItem),
    Reasoning(ReasoningItem),
    CommandExecution(CommandExecutionItem),
    FileChange(FileChangeItem),
    McpToolCall(McpToolCallItem),
    CollabToolCall(CollabToolCallItem),
    WebSearch(WebSearchItem),
    TodoList(TodoListItem),
    Error(ErrorItem),
}
```

#### 3.1.2 CLI 参数结构 (`cli.rs`)

```rust
#[derive(Parser, Debug)]
#[command(version)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Option<Command>,  // Resume / Review / None(直接执行)
    
    #[arg(long = "image", short = 'i')]
    pub images: Vec<PathBuf>,
    
    #[arg(long, short = 'm', global = true)]
    pub model: Option<String>,
    
    #[arg(long = "oss")]
    pub oss: bool,
    
    #[arg(long = "dangerously-bypass-approvals-and-sandbox", alias = "yolo")]
    pub dangerously_bypass_approvals_and_sandbox: bool,
    
    #[arg(long = "json")]
    pub json: bool,
    
    // ... 其他参数
}
```

### 3.2 关键流程

#### 3.2.1 主执行流程 (`lib.rs`)

```rust
pub async fn run_main(cli: Cli, arg0_paths: Arg0DispatchPaths) -> anyhow::Result<()> {
    // 1. 初始化配置
    let config = ConfigBuilder::default()
        .cli_overrides(cli_kv_overrides)
        .harness_overrides(overrides)
        .build()
        .await?;
    
    // 2. 启动 in-process app-server 客户端
    let mut client = InProcessAppServerClient::start(in_process_start_args).await?;
    
    // 3. 处理 resume/start 命令
    let (primary_thread_id, session_configured) = if let Some(ExecCommand::Resume(args)) = command {
        // 解析 resume 路径，调用 thread/resume
        let response: ThreadResumeResponse = send_request_with_response(...).await?;
        (response.thread.id, session_configured_from_thread_resume_response(&response)?)
    } else {
        // 调用 thread/start
        let response: ThreadStartResponse = send_request_with_response(...).await?;
        (response.thread.id, session_configured_from_thread_start_response(&response)?)
    };
    
    // 4. 发送初始任务
    let task_id = match initial_operation {
        InitialOperation::UserTurn { items, output_schema } => {
            // 调用 turn/start
            let response: TurnStartResponse = send_request_with_response(...).await?;
            response.turn.id
        }
        InitialOperation::Review { review_request } => {
            // 调用 review/start
            let response: ReviewStartResponse = send_request_with_response(...).await?;
            response.turn.id
        }
    };
    
    // 5. 事件循环
    loop {
        tokio::select! {
            // 处理 Ctrl+C 中断
            maybe_interrupt = interrupt_rx.recv() => { ... }
            // 处理服务器事件
            maybe_event = client.next_event() => { ... }
        }
    }
}
```

#### 3.2.2 事件处理流程

```rust
match server_event {
    InProcessServerEvent::ServerRequest(request) => {
        // 处理服务器请求（如 MCP 服务器引导、ChatGPT 令牌刷新）
        handle_server_request(&client, request, &config, ...).await;
    }
    InProcessServerEvent::ServerNotification(notification) => {
        // 处理服务器通知（如错误、任务完成）
        if let ServerNotification::Error(payload) = &notification { ... }
    }
    InProcessServerEvent::LegacyNotification(notification) => {
        // 处理遗留通知（事件流）
        let event = decode_legacy_notification(notification)?;
        match event_processor.process_event(event) {
            CodexStatus::Running => continue,
            CodexStatus::InitiateShutdown => break,
            CodexStatus::Shutdown => break,
        }
    }
    InProcessServerEvent::Lagged { skipped } => {
        // 事件流滞后警告
        warn!("in-process app-server event stream lagged; dropped {skipped} events");
    }
}
```

#### 3.2.3 JSONL 事件处理器 (`event_processor_with_jsonl_output.rs`)

```rust
impl EventProcessorWithJsonOutput {
    pub fn collect_thread_events(&mut self, event: &protocol::Event) -> Vec<ThreadEvent> {
        match &event.msg {
            protocol::EventMsg::SessionConfigured(ev) => self.handle_session_configured(ev),
            protocol::EventMsg::AgentMessage(ev) => self.handle_agent_message(ev),
            protocol::EventMsg::ExecCommandBegin(ev) => self.handle_exec_command_begin(ev),
            protocol::EventMsg::ExecCommandEnd(ev) => self.handle_exec_command_end(ev),
            protocol::EventMsg::McpToolCallBegin(ev) => self.handle_mcp_tool_call_begin(ev),
            protocol::EventMsg::McpToolCallEnd(ev) => self.handle_mcp_tool_call_end(ev),
            protocol::EventMsg::CollabAgentSpawnBegin(ev) => self.handle_collab_spawn_begin(ev),
            // ... 其他事件处理
        }
    }
}
```

### 3.3 协议与命令

#### 3.3.1 App-Server 协议交互

| RPC 方法 | 用途 |
|----------|------|
| `thread/start` | 创建新会话 |
| `thread/resume` | 恢复现有会话 |
| `turn/start` | 开始新的任务轮次 |
| `turn/interrupt` | 中断当前任务 |
| `thread/unsubscribe` | 关闭会话连接 |
| `review/start` | 开始代码审查 |

#### 3.3.2 服务器请求处理 (`handle_server_request`)

```rust
async fn handle_server_request(
    client: &InProcessAppServerClient,
    request: ServerRequest,
    config: &Config,
    thread_id: &str,
    error_seen: &mut bool,
) {
    match request {
        ServerRequest::McpServerElicitationRequest { .. } => {
            // Exec 自动取消引导（非交互模式）
            resolve_server_request(client, request_id, canceled_mcp_server_elicitation_response(), ...).await
        }
        ServerRequest::ChatgptAuthTokensRefresh { .. } => {
            // 本地 ChatGPT 令牌刷新
            local_external_chatgpt_tokens(&config).await
        }
        // 以下请求在 exec 模式中拒绝
        ServerRequest::CommandExecutionRequestApproval { .. } => reject(...),
        ServerRequest::FileChangeRequestApproval { .. } => reject(...),
        ServerRequest::ToolRequestUserInput { .. } => reject(...),
        ServerRequest::DynamicToolCall { .. } => reject(...),
        ServerRequest::ApplyPatchApproval { .. } => reject(...),
        ServerRequest::ExecCommandApproval { .. } => reject(...),
        ServerRequest::PermissionsRequestApproval { .. } => reject(...),
    }
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 源文件结构

```
codex-rs/exec/
├── Cargo.toml              # crate 配置
├── BUILD.bazel            # Bazel 构建配置
├── src/
│   ├── main.rs            # 入口点，arg0 分发
│   ├── lib.rs             # 核心逻辑：run_main, run_exec_session
│   ├── cli.rs             # CLI 参数解析
│   ├── event_processor.rs # 事件处理器 trait 定义
│   ├── event_processor_with_human_output.rs  # 人类可读输出
│   ├── event_processor_with_jsonl_output.rs  # JSONL 输出
│   └── exec_events.rs     # JSONL 事件类型定义
└── tests/
    ├── all.rs             # 测试入口
    ├── event_processor_with_json_output.rs  # JSONL 处理器单元测试
    ├── fixtures/          # 测试夹具
    │   ├── apply_patch_freeform_final.txt
    │   └── cli_responses_fixture.sse
    └── suite/             # 集成测试套件
        ├── add_dir.rs
        ├── apply_patch.rs
        ├── auth_env.rs
        ├── ephemeral.rs
        ├── mcp_required_exit.rs
        ├── originator.rs
        ├── output_schema.rs
        ├── resume.rs
        ├── sandbox.rs
        └── server_error_exit.rs
```

### 4.2 关键代码路径

| 功能 | 文件 | 行号范围 |
|------|------|----------|
| 主入口 | `src/main.rs` | 1-82 |
| 核心执行逻辑 | `src/lib.rs` | 161-900 |
| CLI 参数定义 | `src/cli.rs` | 1-318 |
| 事件处理器 trait | `src/event_processor.rs` | 1-45 |
| 人类可读输出 | `src/event_processor_with_human_output.rs` | 1-1457 |
| JSONL 输出 | `src/event_processor_with_jsonl_output.rs` | 1-884 |
| 事件类型定义 | `src/exec_events.rs` | 1-312 |

### 4.3 重要函数

| 函数 | 位置 | 用途 |
|------|------|------|
| `run_main` | `lib.rs:161` | 主入口，初始化配置和客户端 |
| `run_exec_session` | `lib.rs:469` | 执行会话主循环 |
| `send_request_with_response` | `lib.rs:961` | 发送 RPC 请求并等待响应 |
| `handle_server_request` | `lib.rs:1199` | 处理服务器请求 |
| `resolve_prompt` | `lib.rs:1545` | 解析 prompt（支持 stdin） |
| `decode_prompt_bytes` | `lib.rs:1498` | 处理 UTF-8/UTF-16 编码输入 |
| `build_review_request` | `lib.rs:1585` | 构建代码审查请求 |

---

## 5. 依赖与外部交互

### 5.1 内部依赖

| Crate | 用途 |
|-------|------|
| `codex-core` | 核心配置、认证、Git 信息 |
| `codex-app-server-client` | In-process app-server 客户端 |
| `codex-app-server-protocol` | App-server 协议类型 |
| `codex-protocol` | 事件协议定义 |
| `codex-arg0` | arg0 分发（支持 codex-linux-sandbox 别名） |
| `codex-utils-cli` | CLI 工具函数 |
| `codex-utils-cargo-bin` | 测试时定位二进制文件 |
| `codex-apply-patch` | apply_patch 功能 |

### 5.2 外部依赖

| Crate | 用途 |
|-------|------|
| `clap` | CLI 参数解析 |
| `tokio` | 异步运行时 |
| `serde` / `serde_json` | 序列化 |
| `tracing` / `tracing-subscriber` | 日志和追踪 |
| `owo-colors` | 终端颜色 |
| `ts-rs` | TypeScript 类型生成 |

### 5.3 外部系统交互

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   codex-exec    │────▶│  InProcessApp    │────▶│  OpenAI API     │
│   (CLI 入口)     │     │  Server Client   │     │  / OSS Provider │
└─────────────────┘     └──────────────────┘     └─────────────────┘
         │
         ▼
┌─────────────────┐     ┌──────────────────┐
│  codex-linux-   │     │  Session Files   │
│  sandbox        │     │  (JSONL 持久化)   │
│  (Linux 沙箱)    │     │                  │
└─────────────────┘     └──────────────────┘
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 说明 | 缓解措施 |
|------|------|----------|
| `--yolo` 模式 | 完全绕过沙箱和审批，可能导致数据丢失 | 仅用于外部已沙箱环境，文档明确警告 |
| MCP 服务器失败 | 必需的 MCP 服务器初始化失败会导致非零退出 | 测试覆盖 `mcp_required_exit.rs` |
| 编码问题 | 输入 prompt 可能包含非 UTF-8 编码 | `decode_prompt_bytes` 处理 UTF-8/UTF-16 BOM |
| 事件流滞后 | 高负载时可能丢弃事件 | `Lagged` 事件警告用户 |

### 6.2 边界条件

1. **沙箱策略边界**
   - `ReadOnly`: 仅读取，无写入
   - `WorkspaceWrite`: 工作区可写，网络访问受限
   - `DangerFullAccess`: 完全访问（需显式指定）

2. **会话恢复边界**
   - 通过 UUID 或会话名称恢复
   - `--last` 恢复最近会话（可按 cwd 过滤）
   - `--all` 禁用 cwd 过滤

3. **输出模式边界**
   - 人类可读模式：仅 stderr 输出，stdout 保留给最终结果
   - JSONL 模式：每行一个有效 JSON，便于流式解析

### 6.3 改进建议

| 建议 | 优先级 | 说明 |
|------|--------|------|
| 增强错误上下文 | 中 | 在 `handle_server_request` 中添加更多错误上下文 |
| 支持更多编码 | 低 | 当前仅支持 UTF-8/UTF-16，可考虑添加 GBK 等 |
| 进度指示器优化 | 低 | 当前进度条实现较简单，可考虑更精细的进度报告 |
| 会话恢复冲突处理 | 中 | 当多个会话匹配时，提供更清晰的选择提示 |
| 文档完善 | 高 | 添加更多使用示例和最佳实践 |

### 6.4 测试覆盖

| 测试文件 | 覆盖场景 |
|----------|----------|
| `add_dir.rs` | `--add-dir` 参数多目录支持 |
| `apply_patch.rs` | apply_patch 工具调用（自定义工具 + 函数调用） |
| `auth_env.rs` | `CODEX_API_KEY` 环境变量认证 |
| `ephemeral.rs` | `--ephemeral` 临时模式（不持久化） |
| `mcp_required_exit.rs` | 必需 MCP 服务器失败时非零退出 |
| `originator.rs` | Originator header 设置 |
| `output_schema.rs` | `--output-schema` JSON Schema 约束 |
| `resume.rs` | 会话恢复功能（UUID、名称、--last、--all） |
| `sandbox.rs` | Linux/macOS 沙箱行为测试 |
| `server_error_exit.rs` | 服务器错误时非零退出 |

---

## 7. 附录

### 7.1 相关文档

- `AGENTS.md`: 项目级编码规范
- `codex-rs/exec/src/cli.rs`: CLI 参数完整定义
- `codex-rs/app-server-protocol`: App-Server 协议定义

### 7.2 调试技巧

```bash
# 使用 SSE fixture 进行离线测试
CODEX_RS_SSE_FIXTURE=tests/fixtures/cli_responses_fixture.sse \
  OPENAI_BASE_URL=http://unused.local \
  cargo run --bin codex-exec -- --skip-git-repo-check "test prompt"

# JSONL 输出模式
cargo run --bin codex-exec -- --json --skip-git-repo-check "test prompt"

# 恢复最近会话
cargo run --bin codex-exec -- resume --last "continue task"
```

---

*文档生成时间: 2026-03-21*
*研究对象: codex-rs/exec (DIR)*
