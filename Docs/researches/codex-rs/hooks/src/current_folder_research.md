# codex-rs/hooks/src 深度研究文档

## 目录
1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 1.1 模块定位

`codex-rs/hooks` 是 Codex 项目的 **Hook 系统核心实现**，负责在关键会话生命周期节点执行用户自定义的扩展逻辑。该模块实现了与 Claude Desktop 兼容的 Hook 协议，同时扩展了 Codex 特有的功能（如 `turn_id` 传递）。

### 1.2 核心职责

| 职责领域 | 说明 |
|---------|------|
| **事件拦截** | 在 SessionStart、UserPromptSubmit、Stop 三个关键节点拦截并处理 |
| **命令执行** | 通过外部命令（shell 脚本/可执行文件）实现 Hook 逻辑 |
| **上下文注入** | 将 Hook 输出（additional_context）注入到模型对话上下文 |
| **流程控制** | 支持 `continue: false` 停止流程、`decision: block` 拦截用户输入 |
| **配置发现** | 从 `~/.codex/hooks.json` 等配置层自动发现并加载 Hook |

### 1.3 使用场景

1. **合规检查**：在 UserPromptSubmit 时检查用户输入是否符合企业政策
2. **会话初始化**：SessionStart 时自动加载项目特定的上下文或环境变量
3. **输出审查**：Stop 时审查 AI 输出，要求用户确认后再继续
4. **审计日志**：记录所有用户输入和 AI 输出到外部系统

---

## 功能点目的

### 2.1 三大 Hook 事件类型

```rust
// codex-rs/protocol/src/protocol.rs
pub enum HookEventName {
    SessionStart,      // 会话开始时触发（Thread 级别）
    UserPromptSubmit,  // 用户提交提示时触发（Turn 级别）
    Stop,              // AI 生成停止时触发（Turn 级别）
}
```

#### SessionStart
- **触发时机**：会话首次创建或恢复时
- **作用范围**：Thread（整个会话）
- **特殊能力**：支持基于 `source`（startup/resume/clear）的正则匹配过滤
- **输出影响**：可注入开发者消息到模型上下文

#### UserPromptSubmit
- **触发时机**：用户提交输入后、发送到模型前
- **作用范围**：Turn（单次交互）
- **拦截能力**：可阻止（block）特定提示发送到模型
- **Codex 扩展**：暴露 `turn_id` 供 Hook 脚本使用

#### Stop
- **触发时机**：AI 响应生成完成后
- **作用范围**：Turn（单次交互）
- **拦截能力**：可阻止响应展示给用户，要求修改提示后重试
- **Continuation Prompt**：被拦截时可返回提示语引导用户修改

### 2.2 Hook 执行模式

| 模式 | 支持状态 | 说明 |
|------|---------|------|
| **Sync** | ✅ 已支持 | 同步执行，阻塞等待结果 |
| **Async** | ❌ 未支持 | 异步执行，后台运行（当前会生成警告并跳过） |

### 2.3 Hook 处理器类型

| 类型 | 支持状态 | 说明 |
|------|---------|------|
| **Command** | ✅ 已支持 | 执行 shell 命令或脚本 |
| **Prompt** | ❌ 未支持 | 提示型 Hook（计划中） |
| **Agent** | ❌ 未支持 | Agent 型 Hook（计划中） |

---

## 具体技术实现

### 3.1 架构总览

```
┌─────────────────────────────────────────────────────────────┐
│                        调用方 (core)                         │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────┐  │
│  │ SessionStart    │  │ UserPromptSubmit│  │ Stop        │  │
│  └────────┬────────┘  └────────┬────────┘  └──────┬──────┘  │
└───────────┼────────────────────┼──────────────────┼─────────┘
            │                    │                  │
            ▼                    ▼                  ▼
┌─────────────────────────────────────────────────────────────┐
│                    codex_hooks (registry)                    │
│                      (Hooks 结构体)                          │
└───────────┬────────────────────┬──────────────────┬─────────┘
            │                    │                  │
            ▼                    ▼                  ▼
┌─────────────────────────────────────────────────────────────┐
│                    ClaudeHooksEngine                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ discovery   │  │ dispatcher  │  │ command_runner      │  │
│  │ 配置发现     │  │ 处理器筛选   │  │ 命令执行             │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 核心数据结构

#### 3.2.1 HookPayload（旧版通知）

```rust
// src/types.rs
#[derive(Debug, Serialize, Clone)]
pub struct HookPayload {
    pub session_id: ThreadId,
    pub cwd: PathBuf,
    pub client: Option<String>,
    pub triggered_at: DateTime<Utc>,
    pub hook_event: HookEvent,  // AfterAgent | AfterToolUse
}
```

#### 3.2.2 新版 Hook 输入结构

```rust
// src/schema.rs
pub(crate) struct SessionStartCommandInput {
    pub session_id: String,
    pub transcript_path: NullableString,
    pub cwd: String,
    pub hook_event_name: String,  // "SessionStart"
    pub model: String,
    pub permission_mode: String,  // "default" | "acceptEdits" | ...
    pub source: String,           // "startup" | "resume" | "clear"
}

pub(crate) struct UserPromptSubmitCommandInput {
    pub session_id: String,
    pub turn_id: String,          // Codex 扩展字段
    pub transcript_path: NullableString,
    pub cwd: String,
    pub hook_event_name: String,  // "UserPromptSubmit"
    pub model: String,
    pub permission_mode: String,
    pub prompt: String,           // 用户输入内容
}

pub(crate) struct StopCommandInput {
    pub session_id: String,
    pub turn_id: String,          // Codex 扩展字段
    pub transcript_path: NullableString,
    pub cwd: String,
    pub hook_event_name: String,  // "Stop"
    pub model: String,
    pub permission_mode: String,
    pub stop_hook_active: bool,   // 是否处于 stop hook 激活状态
    pub last_assistant_message: NullableString,
}
```

#### 3.2.3 Hook 输出结构

```rust
// src/schema.rs - 通用输出
pub(crate) struct HookUniversalOutputWire {
    pub r#continue: bool,         // 默认 true，设为 false 停止流程
    pub stop_reason: Option<String>,
    pub suppress_output: bool,    // 抑制输出（保留字段）
    pub system_message: Option<String>, // 系统警告消息
}

// UserPromptSubmit / Stop 特有
pub(crate) struct UserPromptSubmitCommandOutputWire {
    pub universal: HookUniversalOutputWire,
    pub decision: Option<BlockDecisionWire>,  // "block" 拦截
    pub reason: Option<String>,               // 拦截原因（block 时必填）
    pub hook_specific_output: Option<UserPromptSubmitHookSpecificOutputWire>,
}

pub(crate) struct SessionStartHookSpecificOutputWire {
    pub hook_event_name: HookEventNameWire,
    pub additional_context: Option<String>,   // 注入模型的上下文
}
```

### 3.3 关键流程

#### 3.3.1 配置发现流程（discovery.rs）

```rust
pub(crate) fn discover_handlers(config_layer_stack: Option<&ConfigLayerStack>) -> DiscoveryResult {
    // 1. 遍历配置层（从最低优先级到最高优先级）
    // 2. 查找每层 config_folder/hooks.json
    // 3. 解析 JSON，提取 HookEvents
    // 4. 按 display_order 排序，构建 ConfiguredHandler 列表
}
```

**配置层优先级**：
- 系统级配置（最低优先级）
- 用户级配置（`~/.codex/`）
- 项目级配置（当前工作目录）

**hooks.json 格式**：
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
            "statusMessage": "Running startup hook"
          }
        ]
      }
    ],
    "UserPromptSubmit": [...],
    "Stop": [...]
  }
}
```

#### 3.3.2 处理器筛选流程（dispatcher.rs）

```rust
pub(crate) fn select_handlers(
    handlers: &[ConfiguredHandler],
    event_name: HookEventName,
    matcher_input: Option<&str>,  // SessionStart 时传入 source
) -> Vec<ConfiguredHandler> {
    // 1. 按 event_name 过滤
    // 2. SessionStart: 按 matcher 正则匹配 source
    // 3. UserPromptSubmit/Stop: 忽略 matcher，全部匹配
}
```

#### 3.3.3 命令执行流程（command_runner.rs）

```rust
pub(crate) async fn run_command(
    shell: &CommandShell,
    handler: &ConfiguredHandler,
    input_json: &str,
    cwd: &Path,
) -> CommandRunResult {
    // 1. 构建命令（使用配置 shell 或默认 shell）
    // 2. 设置工作目录、stdin/stdout/stderr 管道
    // 3. 写入 input_json 到 stdin
    // 4. 执行命令，带超时控制（默认 600s）
    // 5. 收集输出，计算耗时
}
```

**Shell 选择逻辑**：
- Windows: `%COMSPEC%` 或 `cmd.exe`，参数 `/C`
- Unix: `$SHELL` 或 `/bin/sh`，参数 `-lc`

#### 3.3.4 输出解析流程（output_parser.rs）

```rust
pub(crate) fn parse_session_start(stdout: &str) -> Option<SessionStartOutput>;
pub(crate) fn parse_user_prompt_submit(stdout: &str) -> Option<UserPromptSubmitOutput>;
pub(crate) fn parse_stop(stdout: &str) -> Option<StopOutput>;
```

**解析规则**：
1. **空输出**：无操作，继续流程
2. **JSON 对象**：按 schema 解析，提取 `continue`、`decision`、`reason` 等字段
3. **JSON 数组/非法 JSON**：标记为失败
4. **纯文本**：作为 `additional_context` 注入模型上下文

#### 3.3.5 Exit Code 语义

| Exit Code | 含义 | 处理方式 |
|-----------|------|---------|
| 0 | 成功 | 解析 stdout，按 JSON/纯文本处理 |
| 2 | 拦截（Block）| 读取 stderr 作为拦截原因，状态设为 Blocked |
| 其他 | 失败 | 状态设为 Failed，记录错误信息 |

### 3.4 事件处理实现

#### 3.4.1 SessionStart（session_start.rs）

```rust
pub(crate) async fn run(
    handlers: &[ConfiguredHandler],
    shell: &CommandShell,
    request: SessionStartRequest,
    turn_id: Option<String>,
) -> SessionStartOutcome {
    // 1. 筛选匹配 source 的 handlers
    // 2. 序列化 SessionStartCommandInput 为 JSON
    // 3. 并发执行所有匹配的 handlers
    // 4. 解析输出，收集 additional_contexts
    // 5. 检查 should_stop，合并 stop_reason
}
```

#### 3.4.2 UserPromptSubmit（user_prompt_submit.rs）

```rust
pub(crate) async fn run(
    handlers: &[ConfiguredHandler],
    shell: &CommandShell,
    request: UserPromptSubmitRequest,
) -> UserPromptSubmitOutcome {
    // 1. 筛选所有 UserPromptSubmit handlers（无视 matcher）
    // 2. 序列化 UserPromptSubmitCommandInput（含 turn_id）
    // 3. 并发执行
    // 4. 解析输出，支持 block 决策
    // 5. 被 block 的提示不会发送到模型，但 additional_context 会保留
}
```

#### 3.4.3 Stop（stop.rs）

```rust
pub(crate) async fn run(
    handlers: &[ConfiguredHandler],
    shell: &CommandShell,
    request: StopRequest,
) -> StopOutcome {
    // 1. 筛选所有 Stop handlers
    // 2. 序列化 StopCommandInput（含 turn_id, stop_hook_active）
    // 3. 并发执行
    // 4. 聚合多个 handler 的结果（block_reason 用 "\n\n" 连接）
    // 5. 支持 continuation_prompt 引导用户修改提示
}
```

**结果聚合逻辑**：
```rust
fn aggregate_results(results: impl IntoIterator<Item = &StopHandlerData>) -> StopHandlerData {
    let should_stop = results.iter().any(|r| r.should_stop);
    let should_block = !should_stop && results.iter().any(|r| r.should_block);
    let block_reason = if should_block {
        join_text_chunks(results.filter_map(|r| r.block_reason.clone()).collect())
    } else { None };
    // ...
}
```

### 3.5 旧版 Hook 兼容（legacy_notify.rs）

为兼容早期 Codex 版本的通知机制，保留 `notify_hook`：

```rust
pub fn notify_hook(argv: Vec<String>) -> Hook {
    Hook {
        name: "legacy_notify".to_string(),
        func: Arc::new(move |payload: &HookPayload| {
            // 1. 将 HookPayload 序列化为 JSON
            // 2. 追加为命令行参数
            // 3. 异步 spawn 进程（fire-and-forget）
        }),
    }
}
```

**Legacy Payload 结构**：
```json
{
  "type": "agent-turn-complete",
  "thread-id": "uuid",
  "turn-id": "string",
  "cwd": "/path/to/project",
  "client": "codex-tui",
  "input-messages": ["user input"],
  "last-assistant-message": "AI response"
}
```

---

## 关键代码路径与文件引用

### 4.1 文件结构

```
codex-rs/hooks/src/
├── lib.rs                    # 模块导出、公共 API
├── types.rs                  # 核心类型定义（HookPayload、HookResult 等）
├── registry.rs               # Hooks 注册表、配置管理
├── schema.rs                 # JSON Schema 定义、输入输出结构
├── user_notification.rs      # 用户通知（早期实现，已废弃）
├── legacy_notify.rs          # 旧版 Hook 兼容层
├── engine/                   # ClaudeHooksEngine 实现
│   ├── mod.rs                # 引擎入口、ConfiguredHandler
│   ├── config.rs             # hooks.json 配置解析
│   ├── discovery.rs          # 配置发现、Handler 加载
│   ├── dispatcher.rs         # Handler 筛选、执行调度
│   ├── command_runner.rs     # 命令执行、超时控制
│   ├── output_parser.rs      # 输出解析、结果提取
│   └── schema_loader.rs      # Schema 加载（编译时嵌入）
├── events/                   # 事件处理实现
│   ├── mod.rs                # 事件模块入口
│   ├── common.rs             # 通用工具函数
│   ├── session_start.rs      # SessionStart 事件处理
│   ├── user_prompt_submit.rs # UserPromptSubmit 事件处理
│   └── stop.rs               # Stop 事件处理
└── bin/
    └── write_hooks_schema_fixtures.rs  # Schema 生成工具
```

### 4.2 关键类型定义位置

| 类型 | 文件 | 行号 |
|------|------|------|
| `HookPayload` | types.rs | 65-73 |
| `HookResult` | types.rs | 16-25 |
| `HookEvent` | types.rs | 147-158 |
| `Hooks` | registry.rs | 27-31 |
| `HooksConfig` | registry.rs | 17-24 |
| `ConfiguredHandler` | engine/mod.rs | 27-35 |
| `ClaudeHooksEngine` | engine/mod.rs | 57-61 |
| `SessionStartRequest` | events/session_start.rs | 35-42 |
| `UserPromptSubmitRequest` | events/user_prompt_submit.rs | 21-29 |
| `StopRequest` | events/stop.rs | 21-30 |

### 4.3 核心函数位置

| 函数 | 文件 | 行号 | 说明 |
|------|------|------|------|
| `Hooks::new` | registry.rs | 40-60 | 创建 Hooks 实例 |
| `Hooks::dispatch` | registry.rs | 73-86 | 分发 Hook 事件 |
| `discover_handlers` | engine/discovery.rs | 17-119 | 发现配置 |
| `select_handlers` | engine/dispatcher.rs | 24-44 | 筛选处理器 |
| `run_command` | engine/command_runner.rs | 24-101 | 执行命令 |
| `parse_session_start` | engine/output_parser.rs | 38-47 | 解析输出 |
| `preview` / `run` | events/*.rs | - | 事件处理 |

### 4.4 调用链追踪

#### SessionStart 调用链

```
core/src/hook_runtime.rs::run_pending_session_start_hooks
  └─> registry.rs::Hooks::preview_session_start / run_session_start
      └─> engine/mod.rs::ClaudeHooksEngine::preview_session_start / run_session_start
          └─> events/session_start.rs::preview / run
              ├─> dispatcher.rs::select_handlers
              └─> dispatcher.rs::execute_handlers
                  └─> command_runner.rs::run_command
```

#### UserPromptSubmit 调用链

```
core/src/hook_runtime.rs::run_user_prompt_submit_hooks
  └─> registry.rs::Hooks::preview_user_prompt_submit / run_user_prompt_submit
      └─> engine/mod.rs::ClaudeHooksEngine::preview_user_prompt_submit / run_user_prompt_submit
          └─> events/user_prompt_submit.rs::preview / run
```

#### Stop 调用链

```
core/src/codex.rs（TurnContext 内部）
  └─> registry.rs::Hooks::preview_stop / run_stop
      └─> engine/mod.rs::ClaudeHooksEngine::preview_stop / run_stop
          └─> events/stop.rs::preview / run
```

---

## 依赖与外部交互

### 5.1 内部依赖

```
codex-hooks
├── codex-config          # 配置层栈（ConfigLayerStack）
├── codex-protocol        # 协议类型（HookEventName、HookRunSummary 等）
└── codex_protocol::models # SandboxPermissions（HookToolInputLocalShell）
```

### 5.2 外部依赖（Cargo.toml）

| 依赖 | 用途 |
|------|------|
| `anyhow` | 错误处理 |
| `chrono` | 时间戳处理（serde 特性启用） |
| `futures` | 异步 Future 支持 |
| `regex` | Matcher 正则匹配 |
| `schemars` | JSON Schema 生成 |
| `serde`/`serde_json` | 序列化/反序列化 |
| `tokio` | 异步运行时（process、io-util、time） |

### 5.3 与 core 模块的交互

```rust
// core/src/hook_runtime.rs - 主要集成点

pub(crate) async fn run_pending_session_start_hooks(
    sess: &Arc<Session>,
    turn_context: &Arc<TurnContext>,
) -> bool {
    // 构造 SessionStartRequest
    // 调用 sess.hooks().preview_session_start(&request)
    // 调用 sess.hooks().run_session_start(request, turn_id).await
    // 处理结果，注入 additional_contexts
}

pub(crate) async fn run_user_prompt_submit_hooks(
    sess: &Arc<Session>,
    turn_context: &Arc<TurnContext>,
    prompt: String,
) -> HookRuntimeOutcome {
    // 构造 UserPromptSubmitRequest
    // 调用 Hook 执行
    // 返回 should_stop、additional_contexts
}
```

### 5.4 与 protocol 模块的交互

```rust
// protocol/src/protocol.rs - 协议类型定义

pub enum HookEventName {
    SessionStart,
    UserPromptSubmit,
    Stop,
}

pub struct HookRunSummary {
    pub id: String,
    pub event_name: HookEventName,
    pub handler_type: HookHandlerType,
    pub execution_mode: HookExecutionMode,
    pub scope: HookScope,  // Thread | Turn
    pub source_path: PathBuf,
    pub display_order: i64,
    pub status: HookRunStatus,  // Running | Completed | Failed | Stopped | Blocked
    // ...
}

pub struct HookCompletedEvent {
    pub turn_id: Option<String>,
    pub run: HookRunSummary,
}
```

### 5.5 与 TUI/AppServer 的交互

Hook 事件通过 `EventMsg` 发送到客户端：

```rust
// protocol/src/protocol.rs
pub enum EventMsg {
    HookStarted(HookStartedEvent),    // Hook 开始执行
    HookCompleted(HookCompletedEvent), // Hook 执行完成
    // ...
}
```

客户端（TUI）可以展示 Hook 执行状态、进度和结果。

---

## 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 安全风险

| 风险 | 描述 | 缓解措施 |
|------|------|---------|
| **任意代码执行** | Hook 配置允许执行任意 shell 命令 | 需要文件系统权限控制，建议限制 hooks.json 写入权限 |
| **命令注入** | 如果 Hook 脚本未正确处理输入，可能存在注入风险 | 输入通过 stdin JSON 传递，非命令行参数 |
| **超时绕过** | 恶意 Hook 可能通过子进程绕过超时 | `kill_on_drop(true)` 确保清理 |

#### 6.1.2 稳定性风险

| 风险 | 描述 | 缓解措施 |
|------|------|---------|
| **Hook 崩溃** | Hook 进程崩溃不影响主流程 | 错误被捕获，标记为 Failed 状态 |
| **超时处理** | 默认 600s 超时，可能阻塞用户 | 可配置 timeout，最小 1s |
| **资源泄漏** | 大量 Hook 并发执行可能耗尽资源 | 当前同步执行，限制并发数 |

#### 6.1.3 兼容性风险

| 风险 | 描述 |
|------|------|
| **Schema 变更** | 输入输出 Schema 变更可能破坏现有 Hook |
| **Claude 协议漂移** | 与 Claude Desktop 的 Hook 协议可能产生差异 |
| **turn_id 依赖** | Codex 特有的 turn_id 扩展，Claude 不兼容 |

### 6.2 边界情况

#### 6.2.1 配置边界

```rust
// discovery.rs 中的边界处理

// 1. 无效正则 matcher：记录警告，跳过该组
if let Err(err) = Regex::new(matcher) {
    warnings.push(format!("invalid matcher {matcher:?}..."));
    return;
}

// 2. 空命令：记录警告，跳过
if command.trim().is_empty() {
    warnings.push(format!("skipping empty hook command..."));
    continue;
}

// 3. 不支持类型：记录警告
HookHandlerConfig::Prompt {} => 
    warnings.push("prompt hooks are not supported yet")
HookHandlerConfig::Agent {} => 
    warnings.push("agent hooks are not supported yet")
```

#### 6.2.2 执行边界

```rust
// command_runner.rs 中的边界处理

// 1. 命令构建失败：记录错误，返回失败结果
let mut child = match command.spawn() {
    Ok(child) => child,
    Err(err) => return CommandRunResult { error: Some(err.to_string()), ... },
};

// 2. stdin 写入失败：杀死进程，返回错误
if let Err(err) = stdin.write_all(input_json.as_bytes()).await {
    let _ = child.kill().await;
    return CommandRunResult { error: Some(format!("failed to write hook stdin: {err}")), ... };
}

// 3. 超时：返回超时错误
Err(_) => CommandRunResult {
    error: Some(format!("hook timed out after {}s", handler.timeout_sec)),
    ...
}
```

#### 6.2.3 输出解析边界

```rust
// output_parser.rs

// 1. 空输出：无操作
if trimmed.is_empty() { return None; }

// 2. 非法 JSON：返回 None，调用方处理
let value: serde_json::Value = serde_json::from_str(trimmed).ok()?;
if !value.is_object() { return None; }

// 3. block 无 reason：标记为无效，不执行 block
let invalid_block_reason = if should_block && reason.trim().is_empty() {
    Some(invalid_block_message("UserPromptSubmit"))
} else { None };
```

### 6.3 改进建议

#### 6.3.1 功能扩展

1. **Async Hook 支持**
   - 当前仅记录警告并跳过
   - 实现真正的异步执行，不阻塞用户流程

2. **Prompt/Agent Hook 类型**
   - 当前仅 Command 类型被支持
   - Prompt 类型可用于交互式确认
   - Agent 类型可调用其他 Agent 处理

3. **更细粒度的 Matcher**
   - UserPromptSubmit 和 Stop 当前无视 matcher
   - 可支持基于 prompt 内容的正则匹配

4. **Hook 链式执行**
   - 当前多个 Hook 并发执行
   - 支持顺序执行，前一个 Hook 的输出作为后一个的输入

#### 6.3.2 性能优化

1. **Hook 缓存**
   - 缓存已编译的正则表达式
   - 缓存频繁执行的 Hook 结果（如果幂等）

2. **并行执行优化**
   - 当前使用 `join_all` 并发执行
   - 可限制最大并发数，防止资源耗尽

#### 6.3.3 可观测性

1. **Hook 执行日志**
   - 记录每个 Hook 的输入输出（脱敏后）
   - 便于调试和审计

2. **Metrics 暴露**
   - Hook 执行次数、成功率、耗时分布
   - 用于监控和告警

#### 6.3.4 安全性增强

1. **Hook 签名验证**
   - 验证 Hook 脚本来源，防止篡改

2. **沙箱执行**
   - 在受限环境中执行 Hook，限制文件系统/网络访问

3. **配置审计**
   - 记录 hooks.json 变更历史

#### 6.3.5 代码质量

1. **错误处理细化**
   - 当前大量使用 `String` 传递错误信息
   - 可定义更具体的错误类型

2. **测试覆盖**
   - 增加集成测试，覆盖更多边界情况
   - 测试不同 shell 环境的兼容性

3. **文档完善**
   - Hook 协议文档（已部分存在于 app-server/README.md）
   - 示例 Hook 脚本集合

---

## 附录

### A. 生成的 Schema 文件

```
codex-rs/hooks/schema/generated/
├── session-start.command.input.schema.json
├── session-start.command.output.schema.json
├── user-prompt-submit.command.input.schema.json
├── user-prompt-submit.command.output.schema.json
├── stop.command.input.schema.json
└── stop.command.output.schema.json
```

### B. 测试文件

```
codex-rs/core/tests/suite/hooks.rs  # 集成测试
```

主要测试场景：
- Stop hook 多次拦截同一会话
- SessionStart hook 访问 transcript 路径
- 恢复会话保留 Stop continuation prompt
- UserPromptSubmit 拦截并保留上下文
- 队列提示处理（不阻塞已接受的提示）

### C. 相关协议定义

```
codex-rs/protocol/src/protocol.rs   # HookEventName、HookRunSummary 等
codex-rs/app-server-protocol/       # TypeScript 类型定义
```
