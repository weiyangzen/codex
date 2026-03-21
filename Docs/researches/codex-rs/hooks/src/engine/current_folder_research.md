# DIR codex-rs/hooks/src/engine 深度研究文档

## 1. 场景与职责

`codex-rs/hooks/src/engine` 是 Codex 项目中 **Hook 系统的核心执行引擎**，负责管理 Claude 风格的 Hook 生命周期。该引擎实现了与 Claude CLI 兼容的 Hook 协议，允许用户在特定事件点（SessionStart、UserPromptSubmit、Stop）执行自定义命令，实现会话控制、输入拦截和流程阻断等功能。

### 1.1 核心职责

| 职责 | 说明 |
|------|------|
| **配置发现** | 从配置层栈中自动发现 `hooks.json` 配置文件 |
| **Handler 管理** | 解析并管理 ConfiguredHandler，支持正则匹配过滤 |
| **命令执行** | 异步执行 Hook 命令，支持超时控制和 Shell 定制 |
| **输出解析** | 解析 Hook 命令的 JSON/纯文本输出，支持阻断决策 |
| **事件分发** | 协调 SessionStart、UserPromptSubmit、Stop 三类事件的处理 |

### 1.2 架构定位

```
┌─────────────────────────────────────────────────────────────┐
│                      codex-hooks (Registry)                  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │           ClaudeHooksEngine (engine/mod.rs)            │  │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐  │  │
│  │  │ discovery│ │ command_ │ │dispatcher│ │ output_  │  │  │
│  │  │  .rs     │ │ runner.rs│ │  .rs     │ │ parser.rs│  │  │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────┘  │  │
│  │  ┌──────────┐ ┌──────────┐                            │  │
│  │  │  config  │ │ schema_  │                            │  │
│  │  │  .rs     │ │loader.rs │                            │  │
│  │  └──────────┘ └──────────┘                            │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              Hook Events (session_start/stop/user_prompt)   │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. 功能点目的

### 2.1 事件类型支持

引擎支持三种 Claude 兼容的 Hook 事件：

| 事件 | 触发时机 | 特殊能力 | Scope |
|------|----------|----------|-------|
| **SessionStart** | 会话启动时 | 可阻断启动、注入上下文 | Thread |
| **UserPromptSubmit** | 用户提交提示时 | 可阻断输入、要求修改 | Turn |
| **Stop** | 会话停止时 | 可阻断停止、要求继续 | Turn |

### 2.2 阻断机制

引擎实现了两种阻断语义：

1. **Stop（停止）**：`continue: false` - 完全停止处理流程
2. **Block（阻断）**：`decision: "block"` - 阻断当前操作并提示用户修改

### 2.3 上下文注入

Hook 可以通过 `additionalContext` 字段向模型注入额外上下文，支持：
- 纯文本输出（非 JSON 格式自动作为上下文）
- JSON 格式的结构化上下文

---

## 3. 具体技术实现

### 3.1 关键数据结构

#### 3.1.1 ConfiguredHandler（配置化处理器）

```rust
// engine/mod.rs
pub(crate) struct ConfiguredHandler {
    pub event_name: HookEventName,      // SessionStart/UserPromptSubmit/Stop
    pub matcher: Option<String>,        // 正则匹配（仅 SessionStart 有效）
    pub command: String,                // 执行的命令
    pub timeout_sec: u64,               // 超时时间（默认600秒）
    pub status_message: Option<String>, // 状态消息
    pub source_path: PathBuf,           // 配置文件来源
    pub display_order: i64,             // 显示顺序
}
```

#### 3.1.2 CommandShell（Shell 配置）

```rust
// engine/mod.rs
pub(crate) struct CommandShell {
    pub program: String,       // Shell 程序（如 /bin/bash）
    pub args: Vec<String>,     // Shell 参数（如 -lc）
}
```

#### 3.1.3 CommandRunResult（命令执行结果）

```rust
// engine/command_runner.rs
pub(crate) struct CommandRunResult {
    pub started_at: i64,       // 开始时间戳
    pub completed_at: i64,     // 完成时间戳
    pub duration_ms: i64,      // 执行时长
    pub exit_code: Option<i32>,// 退出码
    pub stdout: String,        // 标准输出
    pub stderr: String,        // 标准错误
    pub error: Option<String>, // 执行错误
}
```

### 3.2 配置文件格式

Hook 通过 `hooks.json` 配置，位于配置目录下：

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          {
            "type": "command",
            "command": "echo 'Session starting'",
            "timeout": 30,
            "statusMessage": "Checking environment..."
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "python /path/to/filter.py"
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

### 3.3 核心流程

#### 3.3.1 引擎初始化流程

```rust
// engine/mod.rs
impl ClaudeHooksEngine {
    pub(crate) fn new(
        enabled: bool,
        config_layer_stack: Option<&ConfigLayerStack>,
        shell: CommandShell,
    ) -> Self {
        if !enabled {
            return Self { handlers: Vec::new(), warnings: Vec::new(), shell };
        }
        // 预加载 schema（确保编译时包含）
        let _ = schema_loader::generated_hook_schemas();
        // 发现 handlers
        let discovered = discovery::discover_handlers(config_layer_stack);
        Self { handlers: discovered.handlers, warnings: discovered.warnings, shell }
    }
}
```

#### 3.3.2 Handler 发现流程

```rust
// engine/discovery.rs
pub(crate) fn discover_handlers(config_layer_stack: Option<&ConfigLayerStack>) -> DiscoveryResult {
    // 1. 遍历配置层（从最低优先级到最高优先级）
    for layer in config_layer_stack.get_layers(LowestPrecedenceFirst, false) {
        // 2. 查找 hooks.json 文件
        let source_path = folder.join("hooks.json")?;
        if !source_path.is_file() { continue; }
        
        // 3. 解析 JSON
        let parsed: HooksFile = serde_json::from_str(&contents)?;
        
        // 4. 提取各事件的 handlers
        for group in parsed.hooks.session_start { /* ... */ }
        for group in parsed.hooks.user_prompt_submit { /* ... */ }
        for group in parsed.hooks.stop { /* ... */ }
    }
}
```

#### 3.3.3 命令执行流程

```rust
// engine/command_runner.rs
pub(crate) async fn run_command(
    shell: &CommandShell,
    handler: &ConfiguredHandler,
    input_json: &str,
    cwd: &Path,
) -> CommandRunResult {
    let started_at = chrono::Utc::now().timestamp();
    let started = Instant::now();
    
    // 1. 构建命令
    let mut command = build_command(shell, handler);
    command.current_dir(cwd).stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::piped());
    
    // 2. 启动子进程
    let mut child = match command.spawn() { /* ... */ };
    
    // 3. 写入 stdin（Hook 输入 JSON）
    if let Some(mut stdin) = child.stdin.take() {
        stdin.write_all(input_json.as_bytes()).await?;
    }
    
    // 4. 带超时等待执行
    let timeout_duration = Duration::from_secs(handler.timeout_sec);
    match timeout(timeout_duration, child.wait_with_output()).await {
        Ok(Ok(output)) => { /* 成功 */ },
        Ok(Err(err)) => { /* 执行错误 */ },
        Err(_) => { /* 超时 */ },
    }
}
```

#### 3.3.4 输出解析流程

```rust
// engine/output_parser.rs
pub(crate) fn parse_session_start(stdout: &str) -> Option<SessionStartOutput> {
    let wire: SessionStartCommandOutputWire = parse_json(stdout)?;
    Some(SessionStartOutput {
        universal: UniversalOutput::from(wire.universal),
        additional_context: wire.hook_specific_output.and_then(|o| o.additional_context),
    })
}

pub(crate) fn parse_user_prompt_submit(stdout: &str) -> Option<UserPromptSubmitOutput> {
    let wire: UserPromptSubmitCommandOutputWire = parse_json(stdout)?;
    let should_block = matches!(wire.decision, Some(BlockDecisionWire::Block));
    // 验证：block 必须有 reason
    let invalid_block_reason = if should_block && reason.trim().is_empty() { /* ... */ }
    /* ... */
}
```

### 3.4 输入/输出 Schema

引擎使用 JSON Schema 定义输入输出格式：

#### SessionStart 输入
```json
{
  "session_id": "uuid",
  "cwd": "/path/to/project",
  "hook_event_name": "SessionStart",
  "model": "gpt-4",
  "permission_mode": "default",
  "source": "startup",
  "transcript_path": "/path/to/transcript"
}
```

#### SessionStart 输出
```json
{
  "continue": true,
  "stopReason": null,
  "suppressOutput": false,
  "systemMessage": null,
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "上下文信息"
  }
}
```

#### UserPromptSubmit/Stop 输出（支持阻断）
```json
{
  "continue": true,
  "decision": "block",
  "reason": "请添加测试用例",
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "建议信息"
  }
}
```

### 3.5 事件处理实现

#### SessionStart 事件处理

```rust
// events/session_start.rs
pub(crate) async fn run(
    handlers: &[ConfiguredHandler],
    shell: &CommandShell,
    request: SessionStartRequest,
    turn_id: Option<String>,
) -> SessionStartOutcome {
    // 1. 选择匹配的 handlers（支持正则匹配 source）
    let matched = dispatcher::select_handlers(handlers, HookEventName::SessionStart, Some(source));
    
    // 2. 序列化输入 JSON
    let input_json = serde_json::to_string(&SessionStartCommandInput::new(...))?;
    
    // 3. 执行所有 handlers
    let results = dispatcher::execute_handlers(shell, matched, input_json, cwd, turn_id, parse_completed).await;
    
    // 4. 聚合结果
    SessionStartOutcome {
        hook_events: results.into_iter().map(|r| r.completed).collect(),
        should_stop: results.iter().any(|r| r.data.should_stop),
        stop_reason: results.iter().find_map(|r| r.data.stop_reason.clone()),
        additional_contexts: common::flatten_additional_contexts(...),
    }
}
```

#### UserPromptSubmit 事件处理

```rust
// events/user_prompt_submit.rs
fn parse_completed(...) -> dispatcher::ParsedHandler<UserPromptSubmitHandlerData> {
    match run_result.exit_code {
        Some(0) => {
            // 正常退出：解析 JSON 输出
            if let Some(parsed) = output_parser::parse_user_prompt_submit(&run_result.stdout) {
                if parsed.should_block {
                    status = HookRunStatus::Blocked;
                    should_stop = true;
                }
            }
        }
        Some(2) => {
            // Exit code 2：从 stderr 读取阻断原因
            if let Some(reason) = common::trimmed_non_empty(&run_result.stderr) {
                status = HookRunStatus::Blocked;
                should_block = true;
            }
        }
        _ => { /* 失败 */ }
    }
}
```

#### Stop 事件处理

Stop 事件支持更复杂的聚合逻辑：

```rust
// events/stop.rs
fn aggregate_results(results: impl IntoIterator<Item = &StopHandlerData>) -> StopHandlerData {
    let should_stop = results.iter().any(|r| r.should_stop);
    let should_block = !should_stop && results.iter().any(|r| r.should_block);
    let block_reason = if should_block {
        // 合并多个阻断原因
        common::join_text_chunks(results.filter_map(|r| r.block_reason.clone()).collect())
    } else { None };
    /* ... */
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心文件结构

```
codex-rs/hooks/src/engine/
├── mod.rs              # 引擎主入口，ClaudeHooksEngine 定义
├── command_runner.rs   # 命令执行实现
├── config.rs           # 配置结构定义（HooksFile, HookHandlerConfig）
├── discovery.rs        # Handler 发现逻辑
├── dispatcher.rs       # Handler 选择与执行分发
├── output_parser.rs    # 输出解析逻辑
└── schema_loader.rs    # Schema 预加载
```

### 4.2 关键代码路径

| 功能 | 文件 | 关键函数/结构 |
|------|------|--------------|
| 引擎初始化 | `mod.rs` | `ClaudeHooksEngine::new()` |
| 配置发现 | `discovery.rs` | `discover_handlers()` |
| 命令执行 | `command_runner.rs` | `run_command()` |
| Handler 选择 | `dispatcher.rs` | `select_handlers()` |
| 批量执行 | `dispatcher.rs` | `execute_handlers()` |
| SessionStart | `events/session_start.rs` | `run()`, `parse_completed()` |
| UserPromptSubmit | `events/user_prompt_submit.rs` | `run()`, `parse_completed()` |
| Stop | `events/stop.rs` | `run()`, `parse_completed()`, `aggregate_results()` |
| 输出解析 | `output_parser.rs` | `parse_session_start()`, `parse_user_prompt_submit()`, `parse_stop()` |
| Schema 定义 | `schema.rs` | `SessionStartCommandInput`, `UserPromptSubmitCommandOutputWire` 等 |

### 4.3 调用链

```
codex::core::hook_runtime::run_pending_session_start_hooks()
    └── Hooks::run_session_start()
        └── ClaudeHooksEngine::run_session_start()
            └── session_start::run()
                ├── dispatcher::select_handlers()  // 选择匹配的 handlers
                └── dispatcher::execute_handlers() // 执行所有 handlers
                    └── command_runner::run_command() // 执行单个命令
                        └── parse_completed()       // 解析输出
```

---

## 5. 依赖与外部交互

### 5.1 内部依赖

| 依赖 | 用途 |
|------|------|
| `codex_config::ConfigLayerStack` | 配置层管理，用于发现 hooks.json |
| `codex_protocol::protocol::*` | Hook 事件协议类型（HookEventName, HookRunStatus 等） |
| `codex_protocol::ThreadId` | 会话/线程 ID 类型 |

### 5.2 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `tokio` | 异步运行时（process, io-util, time） |
| `serde`/`serde_json` | JSON 序列化/反序列化 |
| `schemars` | JSON Schema 生成 |
| `regex` | Matcher 正则匹配 |
| `chrono` | 时间戳处理 |
| `futures` | 异步工具（join_all） |

### 5.3 与 Core 模块的交互

```rust
// core/src/hook_runtime.rs
pub(crate) async fn run_pending_session_start_hooks(...) -> bool {
    let request = codex_hooks::SessionStartRequest { /* ... */ };
    let preview_runs = sess.hooks().preview_session_start(&request);
    let outcome = sess.hooks().run_session_start(request, Some(turn_id)).await;
    // 处理结果，注入上下文
}
```

### 5.4 配置文件位置

引擎通过 `ConfigLayerStack` 发现配置文件，按优先级顺序查找：
- 系统级配置目录
- 用户级配置目录（`~/.config/codex/`）
- 项目级配置目录（`.codex/`）

配置文件名固定为 `hooks.json`。

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 描述 | 严重程度 |
|------|------|----------|
| **超时处理** | Hook 命令默认 600 秒超时，过长可能导致用户体验差 | 中 |
| **正则性能** | SessionStart 的 matcher 使用正则，复杂模式可能影响启动速度 | 低 |
| **命令注入** | Hook 命令直接执行，配置文件被篡改可导致任意代码执行 | 高 |
| **JSON 解析失败** | 输出格式错误会导致 Hook 失败，但不会阻断主流程 | 低 |
| **并发执行** | 多个 handlers 并发执行，可能产生竞态条件 | 中 |

### 6.2 边界情况

1. **空命令处理**：`discovery.rs` 会跳过空命令的 handler
2. **无效正则**：matcher 正则无效时，整个 group 被跳过并记录警告
3. **Exit Code 2**：UserPromptSubmit 和 Stop 支持 exit code 2 作为阻断信号
4. **纯文本输出**：非 JSON 格式的 stdout 被作为 additionalContext 处理
5. **JSON 解析失败**：以 `{` 或 `[` 开头但解析失败的输出会导致 Hook 失败

### 6.3 改进建议

#### 6.3.1 安全性增强

```rust
// 建议：添加命令白名单或签名验证
pub(crate) fn verify_hook_command(command: &str) -> Result<(), HookError> {
    // 验证命令是否在白名单中
    // 或验证配置文件签名
}
```

#### 6.3.2 性能优化

```rust
// 建议：缓存正则编译结果
use regex::Regex;
use std::sync::OnceLock;

pub(crate) fn get_matcher(pattern: &str) -> Option<&Regex> {
    static CACHE: OnceLock<HashMap<String, Regex>> = OnceLock::new();
    // 缓存已编译的正则
}
```

#### 6.3.3 可观测性增强

```rust
// 建议：添加更详细的执行指标
pub(crate) struct CommandRunMetrics {
    pub handler_id: String,
    pub execution_time_ms: i64,
    pub memory_usage_kb: Option<u64>,
    pub io_read_bytes: Option<u64>,
    pub io_write_bytes: Option<u64>,
}
```

#### 6.3.4 功能扩展

1. **Async Hook 支持**：当前 `async: true` 的 handler 被跳过，建议实现真正的异步支持
2. **Prompt/Agent Hook**：当前仅支持 `Command` 类型，建议实现 `Prompt` 和 `Agent` 类型
3. **条件执行**：支持更复杂的条件判断（如基于环境变量、文件存在性等）
4. **Hook 链**：支持 Hook 之间的依赖关系和执行顺序控制

#### 6.3.5 错误处理改进

```rust
// 建议：更细粒度的错误类型
pub enum HookError {
    ConfigParseError { path: PathBuf, line: usize },
    CommandExecutionError { command: String, exit_code: i32 },
    TimeoutError { command: String, timeout_sec: u64 },
    InvalidOutputError { stdout: String, reason: String },
}
```

### 6.4 测试覆盖

当前测试覆盖：
- `discovery.rs`：matcher 忽略测试
- `dispatcher.rs`：handler 选择、顺序保持测试
- `output_parser.rs`：各事件输出解析测试
- `schema_loader.rs`：schema 加载测试
- `session_start.rs`：纯文本上下文、continue false、无效 JSON 测试
- `user_prompt_submit.rs`：block 决策、exit code 2 测试
- `stop.rs`：block 决策聚合、exit code 2 测试

建议补充：
- 超时场景测试
- 并发执行测试
- 大输出处理测试
- 特殊字符处理测试

---

## 7. 总结

`codex-rs/hooks/src/engine` 是一个设计精良的 Hook 执行引擎，实现了与 Claude CLI 兼容的 Hook 协议。其核心特点包括：

1. **配置驱动**：通过 `hooks.json` 灵活配置 Hook 行为
2. **事件丰富**：支持 SessionStart、UserPromptSubmit、Stop 三种事件
3. **阻断灵活**：支持 Stop（完全停止）和 Block（阻断并提示）两种语义
4. **上下文注入**：支持向模型注入额外上下文信息
5. **安全可靠**：具备超时控制、错误处理和警告机制

引擎代码结构清晰，职责分离明确（discovery、dispatcher、command_runner、output_parser），便于维护和扩展。
