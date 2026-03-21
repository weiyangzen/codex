# codex-rs/hooks 深度研究文档

## 概述

`codex-hooks` 是 Codex CLI/TUI 的 **Hook 系统实现 crate**，负责在会话生命周期关键节点执行用户自定义脚本/命令，实现扩展性和自动化工作流。该系统兼容 Claude CLI 的 hook 规范，同时提供 Codex 特定的扩展功能。

---

## 场景与职责

### 核心场景

1. **Session 生命周期拦截**
   - `SessionStart`: 会话启动时（startup/resume/clear）执行初始化检查、环境准备
   - `UserPromptSubmit`: 用户提交输入前进行验证、拦截或增强
   - `Stop`: Agent 停止时执行清理、确认或阻止操作

2. **Agent 执行后通知**
   - `AfterAgent`: Agent 完成一轮对话后触发通知（向后兼容 legacy notify）
   - `AfterToolUse`: 工具执行完成后进行审计、日志记录或操作拦截

3. **企业级扩展**
   - 合规检查：在提交前验证代码/命令是否符合政策
   - 自动化工作流：自动运行测试、lint、安全检查
   - 审计追踪：记录所有用户输入和 AI 输出

### 架构定位

```
┌─────────────────────────────────────────────────────────────┐
│                        codex-core                           │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │  Session    │  │  Turn Exec  │  │   Tool Registry     │  │
│  │  Lifecycle  │  │   Pipeline  │  │   (after_tool_use)  │  │
│  └──────┬──────┘  └──────┬──────┘  └──────────┬──────────┘  │
│         │                │                    │             │
│         ▼                ▼                    ▼             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              codex-hooks (this crate)                 │  │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────────┐  │  │
│  │  │  Registry  │  │  Engine    │  │  Event Handlers │  │  │
│  │  │  (Hooks)   │──│ (Claude    │──│ (session_start, │  │  │
│  │  │            │  │  Engine)   │  │  user_prompt,   │  │  │
│  │  └────────────┘  └────────────┘  │  stop)          │  │  │
│  │                                   └────────────────┘  │  │
│  └──────────────────────────────────────────────────────┘  │
│                          │                                  │
│                          ▼                                  │
│              ┌──────────────────────┐                       │
│              │  hooks.json configs  │                       │
│              │  (config layer stack) │                       │
│              └──────────────────────┘                       │
└─────────────────────────────────────────────────────────────┘
```

---

## 功能点目的

### 1. Claude 兼容 Hook 引擎 (`ClaudeHooksEngine`)

**目的**: 实现与 Claude CLI 兼容的 hook 系统，支持从 `hooks.json` 配置文件加载和执行命令。

**关键特性**:
- 配置文件发现：从配置层栈（config layer stack）递归查找 `hooks.json`
- 事件类型支持：`SessionStart`, `UserPromptSubmit`, `Stop`
- 匹配器（Matcher）：仅 `SessionStart` 支持 regex 匹配（startup/resume/clear）
- 命令执行：通过 shell 执行用户命令，支持超时控制（默认 600s）
- 输出解析：支持 JSON 结构化输出和纯文本输出

### 2. 遗留通知系统 (`legacy_notify`)

**目的**: 向后兼容旧的 `--notify` 命令行参数，在 Agent 完成一轮后触发外部通知。

**关键特性**:
- Fire-and-forget 模式：不等待命令完成
- JSON 负载：包含 thread_id, turn_id, cwd, input_messages, last_assistant_message
- 仅支持 `AfterAgent` 事件

### 3. 工具使用钩子 (`AfterToolUse`)

**目的**: 在工具执行完成后进行审计、拦截或记录，支持对敏感操作的监控。

**关键特性**:
- 支持多种工具类型：Function, Custom, LocalShell, MCP
- 提供详细的工具执行上下文：命令参数、沙箱策略、执行结果、耗时等
- 支持操作中止：`FailedAbort` 可阻止后续操作继续

### 4. 上下文注入系统

**目的**: 允许 hook 向模型对话中注入额外的系统上下文（developer messages）。

**关键特性**:
- `additional_context` 字段：hook 输出中的字符串会被转换为 developer message
- 支持多个 hook 的顺序注入
- 仅对当前 turn 有效

---

## 具体技术实现

### 关键数据结构

#### 1. HookPayload（事件负载）

```rust
// src/types.rs
#[derive(Debug, Serialize, Clone)]
#[serde(rename_all = "snake_case")]
pub struct HookPayload {
    pub session_id: ThreadId,
    pub cwd: PathBuf,
    pub client: Option<String>,
    pub triggered_at: DateTime<Utc>,
    pub hook_event: HookEvent,
}
```

#### 2. HookEvent（事件类型）

```rust
// src/types.rs
#[derive(Debug, Clone, Serialize)]
#[serde(tag = "event_type", rename_all = "snake_case")]
pub enum HookEvent {
    AfterAgent { event: HookEventAfterAgent },
    AfterToolUse { event: HookEventAfterToolUse },
}
```

#### 3. HookResult（执行结果）

```rust
// src/types.rs
pub enum HookResult {
    Success,                                    // 成功继续
    FailedContinue(Box<dyn Error + Send + Sync>), // 失败但继续
    FailedAbort(Box<dyn Error + Send + Sync>),    // 失败并中止
}
```

#### 4. ConfiguredHandler（配置化的处理器）

```rust
// src/engine/mod.rs
pub(crate) struct ConfiguredHandler {
    pub event_name: HookEventName,      // SessionStart/UserPromptSubmit/Stop
    pub matcher: Option<String>,        // 仅 SessionStart 使用 regex
    pub command: String,                // 要执行的命令
    pub timeout_sec: u64,               // 超时时间（默认 600s）
    pub status_message: Option<String>, // 状态提示信息
    pub source_path: PathBuf,           // 配置文件来源
    pub display_order: i64,             // 显示顺序
}
```

### 关键流程

#### 1. Hook 配置发现流程

```
┌─────────────────┐
│ ConfigLayerStack│
│ ( Lowest First )│
└────────┬────────┘
         │
         ▼
┌─────────────────┐     ┌─────────────────┐
│  Layer.config   │────▶│  Join(hooks.json)│
│    folder       │     │                 │
└─────────────────┘     └────────┬────────┘
                                 │
                    ┌────────────┼────────────┐
                    ▼            ▼            ▼
              ┌─────────┐  ┌─────────┐  ┌─────────┐
              │Session  │  │ User    │  │  Stop   │
              │ Start   │  │ Prompt  │  │         │
              │ Hooks   │  │ Submit  │  │ Hooks   │
              └────┬────┘  └────┬────┘  └────┬────┘
                   │            │            │
                   └────────────┴────────────┘
                                │
                                ▼
                    ┌───────────────────────┐
                    │  Vec<ConfiguredHandler>│
                    │  (sorted by display_order)
                    └───────────────────────┘
```

**代码路径**: `src/engine/discovery.rs::discover_handlers()`

#### 2. SessionStart Hook 执行流程

```
┌──────────────────┐
│  SessionStart    │
│    Request       │
│ (session_id,    │
│  source, model)  │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  select_handlers │◀── 过滤 event_name == SessionStart
│                  │    应用 matcher regex 到 source
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  Serialize Input │◀── SessionStartCommandInput JSON
│                  │    (session_id, cwd, model, source...)
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  execute_handlers│◀── 并发执行所有匹配的命令
│                  │    通过 shell 运行，stdin 传入 JSON
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  parse_completed │◀── 解析 stdout
│                  │    - exit 0 + valid JSON → 结构化处理
│                  │    - exit 0 + plain text → 作为 additional_context
│                  │    - exit 0 + invalid JSON → Failed
│                  │    - exit non-zero → Failed
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ SessionStart     │
│   Outcome        │
│ (hook_events,    │
│  should_stop,    │
│  additional_ctx) │
└──────────────────┘
```

**代码路径**: `src/events/session_start.rs::run()`

#### 3. UserPromptSubmit Hook 执行流程

与 SessionStart 类似，但支持 **Block 决策**：

```rust
// 输出 JSON 示例
{
    "continue": true,           // false = 停止处理
    "decision": "block",        // "block" = 阻止用户输入
    "reason": "Policy violation", // block 时必须提供
    "hookSpecificOutput": {
        "hookEventName": "UserPromptSubmit",
        "additionalContext": "Extra context for model"
    }
}
```

**特殊退出码**:
- Exit 0: 正常处理，解析 stdout JSON
- Exit 2: 阻止输入，stderr 内容作为阻止原因
- Exit 其他: 失败

**代码路径**: `src/events/user_prompt_submit.rs::run()`

#### 4. Stop Hook 执行流程

支持更复杂的聚合逻辑：

```rust
// aggregate_results 逻辑
fn aggregate_results(results: &[StopHandlerData]) -> StopHandlerData {
    let should_stop = results.iter().any(|r| r.should_stop);
    let should_block = !should_stop && results.iter().any(|r| r.should_block);
    // block_reason 和 continuation_prompt 会连接多个 hook 的输出
}
```

**代码路径**: `src/events/stop.rs::run()`

#### 5. AfterToolUse Hook 执行流程

```rust
// src/types.rs
pub struct HookEventAfterToolUse {
    pub turn_id: String,
    pub call_id: String,
    pub tool_name: String,
    pub tool_kind: HookToolKind,      // Function/Custom/LocalShell/Mcp
    pub tool_input: HookToolInput,    // 详细的工具输入参数
    pub executed: bool,               // 是否实际执行
    pub success: bool,                // 执行是否成功
    pub duration_ms: u64,             // 执行耗时
    pub mutating: bool,               // 是否是变更操作
    pub sandbox: String,              // 沙箱类型
    pub sandbox_policy: String,       // 沙箱策略
    pub output_preview: String,       // 输出预览
}
```

**代码路径**: `src/tools/registry.rs::dispatch_after_tool_use_hook()`

### 协议与命令

#### 输入协议（Claude 兼容）

所有 Claude 兼容的 hook 都接收 JSON 输入 via stdin：

**SessionStart Input**:
```json
{
    "session_id": "uuid",
    "transcript_path": "/path/to/transcript.log",
    "cwd": "/current/working/dir",
    "hook_event_name": "SessionStart",
    "model": "gpt-4",
    "permission_mode": "default",
    "source": "startup"
}
```

**UserPromptSubmit Input**:
```json
{
    "session_id": "uuid",
    "turn_id": "turn-uuid",           // Codex 扩展字段
    "transcript_path": "/path/to/transcript.log",
    "cwd": "/current/working/dir",
    "hook_event_name": "UserPromptSubmit",
    "model": "gpt-4",
    "permission_mode": "default",
    "prompt": "User input text"
}
```

**Stop Input**:
```json
{
    "session_id": "uuid",
    "turn_id": "turn-uuid",           // Codex 扩展字段
    "transcript_path": "/path/to/transcript.log",
    "cwd": "/current/working/dir",
    "hook_event_name": "Stop",
    "model": "gpt-4",
    "permission_mode": "default",
    "stop_hook_active": true,
    "last_assistant_message": "AI response"
}
```

#### 输出协议

**通用输出字段**（所有事件）:
```json
{
    "continue": true,           // false = 停止后续 hook 和主流程
    "stopReason": "reason",     // continue=false 时解释原因
    "suppressOutput": false,    // 是否抑制输出（保留字段）
    "systemMessage": "msg"      // 系统警告消息
}
```

**UserPromptSubmit/Stop 特有字段**:
```json
{
    "decision": "block",        // "block" = 阻止操作
    "reason": "解释原因",        // decision=block 时必须
    "hookSpecificOutput": {
        "hookEventName": "UserPromptSubmit",
        "additionalContext": "给模型的额外上下文"
    }
}
```

#### 命令执行

```rust
// src/engine/command_runner.rs
pub(crate) async fn run_command(
    shell: &CommandShell,
    handler: &ConfiguredHandler,
    input_json: &str,
    cwd: &Path,
) -> CommandRunResult {
    // 1. 构建命令（使用配置的 shell 或默认 shell）
    // 2. 设置工作目录
    // 3. stdin 传入 input_json
    // 4. 应用 timeout（默认 600s）
    // 5. 捕获 stdout/stderr
    // 6. 返回 CommandRunResult
}
```

Shell 选择优先级：
1. 配置指定的 shell（`HooksConfig.shell_program`）
2. 环境变量 `SHELL`（Unix）或 `COMSPEC`（Windows）
3. 默认值 `/bin/sh`（Unix）或 `cmd.exe`（Windows）

---

## 关键代码路径与文件引用

### 核心模块结构

```
codex-rs/hooks/src/
├── lib.rs                    # 模块导出、公共 API
├── types.rs                  # 核心类型：HookPayload, HookEvent, HookResult
├── schema.rs                 # JSON Schema 定义和生成
├── registry.rs               # Hooks 注册表，对外统一接口
├── user_notification.rs      # 用户通知（未使用，占位）
├── legacy_notify.rs          # 遗留 notify 系统实现
├── bin/
│   └── write_hooks_schema_fixtures.rs  # Schema 生成工具
├── engine/
│   ├── mod.rs                # ClaudeHooksEngine, ConfiguredHandler, CommandShell
│   ├── config.rs             # hooks.json 配置结构
│   ├── discovery.rs          # 配置文件发现和加载
│   ├── dispatcher.rs         # Handler 选择、执行调度
│   ├── command_runner.rs     # 命令执行和超时控制
│   ├── output_parser.rs      # 输出解析（JSON/纯文本）
│   └── schema_loader.rs      # 编译时 Schema 加载
└── events/
    ├── mod.rs                # 事件模块导出
    ├── common.rs             # 事件处理公共工具
    ├── session_start.rs      # SessionStart 事件处理
    ├── user_prompt_submit.rs # UserPromptSubmit 事件处理
    └── stop.rs               # Stop 事件处理
```

### 关键文件详解

#### 1. `src/registry.rs` - 对外统一接口

```rust
pub struct Hooks {
    after_agent: Vec<Hook>,           // 遗留 notify hook
    after_tool_use: Vec<Hook>,        // 工具使用后 hook（当前为空）
    engine: ClaudeHooksEngine,        // Claude 兼容引擎
}

impl Hooks {
    pub fn new(config: HooksConfig) -> Self;
    pub async fn dispatch(&self, hook_payload: HookPayload) -> Vec<HookResponse>;
    pub fn preview_session_start(&self, request: &SessionStartRequest) -> Vec<HookRunSummary>;
    pub async fn run_session_start(&self, request: SessionStartRequest, turn_id: Option<String>) -> SessionStartOutcome;
    // ... 类似方法 for UserPromptSubmit, Stop
}
```

#### 2. `src/engine/discovery.rs` - 配置发现

- 遍历 `ConfigLayerStack` 的所有层
- 每层查找 `{config_folder}/hooks.json`
- 解析 JSON 配置，验证 regex matcher
- 生成 `Vec<ConfiguredHandler>`

**配置示例** (`hooks.json`):
```json
{
    "hooks": {
        "SessionStart": [
            {
                "matcher": "startup",
                "hooks": [
                    {
                        "type": "command",
                        "command": "echo 'Session started'",
                        "timeout": 30,
                        "statusMessage": "Running startup check"
                    }
                ]
            }
        ],
        "UserPromptSubmit": [
            {
                "hooks": [
                    {
                        "type": "command",
                        "command": "python /path/to/policy_check.py"
                    }
                ]
            }
        ],
        "Stop": [
            {
                "hooks": [
                    {
                        "type": "command",
                        "command": "echo 'Session ending'"
                    }
                ]
            }
        ]
    }
}
```

#### 3. `src/engine/dispatcher.rs` - 调度器

- `select_handlers()`: 根据 event_name 和 matcher 过滤 handler
- `execute_handlers()`: 并发执行所有选中的 handler
- `running_summary()`: 生成执行前的预览信息
- `completed_summary()`: 生成执行完成后的结果信息

#### 4. `src/events/stop.rs` - 最复杂的事件处理

支持多种决策组合：
- `continue: false` → 停止后续处理
- `decision: block` + `reason` → 阻止操作并提示用户
- Exit code 2 → 从 stderr 读取阻止原因

聚合逻辑：
- 任一 hook 要求 stop → 整体 stop
- 没有 stop 且有 hook 要求 block → 整体 block
- 多个 block reason → 用 `\n\n` 连接

---

## 依赖与外部交互

### 内部依赖

| Crate | 用途 |
|-------|------|
| `codex-config` | 配置层栈 (`ConfigLayerStack`) 访问 |
| `codex-protocol` | 协议类型 (`ThreadId`, `HookEventName`, `HookRunSummary` 等) |

### 外部依赖

| Crate | 用途 |
|-------|------|
| `tokio` | 异步运行时、进程管理、超时控制 |
| `serde`/`serde_json` | JSON 序列化/反序列化 |
| `schemars` | JSON Schema 生成 |
| `regex` | Matcher 正则表达式匹配 |
| `chrono` | 时间戳处理 |
| `futures` | 异步工具（`join_all`） |
| `anyhow` | 错误处理 |

### 调用方（上游）

| 模块 | 用途 |
|------|------|
| `codex-core::codex` | 初始化 Hooks，触发 AfterAgent/AfterToolUse |
| `codex-core::hook_runtime` | 封装 SessionStart/UserPromptSubmit 调用 |
| `codex-core::state::service` | 在 SessionServices 中持有 Hooks 实例 |
| `codex-core::tools::registry` | 触发 AfterToolUse hook |

### 被调用方（下游）

| 目标 | 方式 |
|------|------|
| 用户脚本/命令 | 通过 shell 执行，stdin 传 JSON |
| 系统通知（遗留） | 通过 `notify_hook` 执行外部命令 |

---

## 风险、边界与改进建议

### 已知风险

1. **超时风险**
   - 默认 600s 超时可能过长，会阻塞用户操作
   - 建议：提供更细粒度的超时配置，或支持异步 hook

2. **命令注入风险**
   - Hook 命令直接通过 shell 执行，如果配置来源不可信可能存在注入
   - 缓解：确保 `hooks.json` 只能由用户本人编辑

3. **性能风险**
   - Hook 在主线程同步执行，慢 hook 会显著影响响应时间
   - 建议：关键路径 hook 应该有更严格的默认超时（如 5s）

4. **错误处理不一致**
   - `SessionStart` 和 `UserPromptSubmit` 对纯文本输出的处理不同
   - `SessionStart` 接受纯文本作为 additional_context
   - `UserPromptSubmit` 仅接受 JSON 或 exit code 2

### 边界情况

1. **空命令**: 发现阶段跳过空命令，记录警告
2. **无效 regex**: 发现阶段验证，无效 matcher 会跳过整个 group
3. **JSON 解析失败**: 以 `{` 或 `[` 开头但解析失败 → Failed 状态
4. **序列化失败**: 输入 JSON 序列化失败 → 所有 handler 标记为 Failed
5. **并发执行**: 所有匹配的 handler 并发执行，结果顺序按 display_order

### 改进建议

1. **异步 Hook 支持**
   - 配置中已预留 `async: true` 字段，但尚未实现
   - 建议实现真正的异步 hook（fire-and-forget，不等待结果）

2. **Prompt/Agent Hook 类型**
   - 配置中已预留 `Prompt` 和 `Agent` 类型，但仅记录警告
   - Prompt hook: 向用户显示提示并收集输入
   - Agent hook: 调用另一个 AI agent 处理

3. **更细粒度的 Matcher**
   - 当前仅 `SessionStart` 支持 matcher
   - 建议 `UserPromptSubmit` 也支持基于 prompt 内容的 regex 匹配

4. **Hook 链式依赖**
   - 当前 hook 之间无依赖关系
   - 建议支持 `depends_on` 字段，实现顺序执行和条件执行

5. **更好的错误报告**
   - 当前 stderr 内容仅在失败时记录
   - 建议支持将 stderr 作为 warning entry 返回

6. **Schema 版本控制**
   - 当前无版本控制，协议变更可能破坏现有 hook
   - 建议在 `hooks.json` 中添加 `version` 字段

7. **Hook 调试工具**
   - 提供 CLI 命令测试 hook 配置
   - 例如：`codex hook test --event SessionStart --source startup`

---

## 附录：JSON Schema 文件

生成的 Schema 文件位于 `schema/generated/`：

| 文件 | 用途 |
|------|------|
| `session-start.command.input.schema.json` | SessionStart 输入验证 |
| `session-start.command.output.schema.json` | SessionStart 输出验证 |
| `user-prompt-submit.command.input.schema.json` | UserPromptSubmit 输入验证 |
| `user-prompt-submit.command.output.schema.json` | UserPromptSubmit 输出验证 |
| `stop.command.input.schema.json` | Stop 输入验证 |
| `stop.command.output.schema.json` | Stop 输出验证 |

生成命令：
```bash
cargo run --bin write_hooks_schema_fixtures
```

或：
```bash
just write-hooks-schema  # 如果 justfile 中有定义
```
