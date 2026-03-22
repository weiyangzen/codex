# codex-rs/hooks/schema/generated 目录研究文档

## 1. 场景与职责

### 1.1 目录定位

`codex-rs/hooks/schema/generated/` 目录是 Codex 项目中 **Hooks 系统** 的 JSON Schema 生成目录，存储了 6 个核心 Schema 文件，用于定义 Claude 风格 Hooks 的命令输入输出协议。

### 1.2 核心职责

该目录及其生成的 Schema 文件承担以下关键职责：

1. **协议契约定义**：为三种 Hook 事件（SessionStart、UserPromptSubmit、Stop）定义标准化的 JSON 输入输出格式
2. **运行时验证**：作为 Hook 命令行工具输入输出的结构验证依据
3. **文档化接口**：为 Hook 开发者提供清晰的接口规范
4. **编译时嵌入**：通过 `include_str!` 嵌入到二进制中，供 schema_loader 使用

### 1.3 使用场景

| 场景 | 说明 |
|------|------|
| Hook 命令执行 | 当 Codex 触发 Hook 时，将输入数据按 Schema 序列化为 JSON 通过 stdin 传递给 Hook 命令 |
| Hook 输出解析 | Hook 命令的 stdout 输出按 Schema 进行解析，提取控制指令（如 block、continue） |
| 配置验证 | 启动时验证 hooks.json 配置文件的语义有效性 |
| 开发文档 | 为第三方 Hook 开发者提供接口规范参考 |

---

## 2. 功能点目的

### 2.1 Schema 文件清单

| 文件 | 用途 | 对应 Rust 类型 |
|------|------|---------------|
| `session-start.command.input.schema.json` | SessionStart Hook 输入 | `SessionStartCommandInput` |
| `session-start.command.output.schema.json` | SessionStart Hook 输出 | `SessionStartCommandOutputWire` |
| `user-prompt-submit.command.input.schema.json` | UserPromptSubmit Hook 输入 | `UserPromptSubmitCommandInput` |
| `user-prompt-submit.command.output.schema.json` | UserPromptSubmit Hook 输出 | `UserPromptSubmitCommandOutputWire` |
| `stop.command.input.schema.json` | Stop Hook 输入 | `StopCommandInput` |
| `stop.command.output.schema.json` | Stop Hook 输出 | `StopCommandOutputWire` |

### 2.2 输入 Schema 通用字段

所有输入 Schema 共享以下核心字段：

```json
{
  "session_id": "string",           // 会话唯一标识
  "turn_id": "string",              // Codex 扩展：当前 turn ID（UserPromptSubmit/Stop）
  "cwd": "string",                  // 当前工作目录
  "hook_event_name": "const string", // 事件名称常量（如 "SessionStart"）
  "model": "string",                // 使用的模型名称
  "permission_mode": "enum",        // 权限模式：default/acceptEdits/plan/dontAsk/bypassPermissions
  "transcript_path": "string|null"  // 对话记录文件路径
}
```

**特殊字段**：
- `SessionStart.source`: 枚举 `startup|resume|clear`，标识会话启动来源
- `UserPromptSubmit.prompt`: 用户提交的原始提示文本
- `Stop.stop_hook_active`: 布尔值，标识 Stop Hook 是否处于激活状态
- `Stop.last_assistant_message`: 最后一条助手消息内容

### 2.3 输出 Schema 通用字段

所有输出 Schema 共享 `HookUniversalOutputWire` 结构：

```json
{
  "continue": "boolean (default: true)",      // 是否继续处理
  "stopReason": "string|null",                // 停止原因（当 continue=false 时）
  "suppressOutput": "boolean (default: false)", // 是否抑制输出
  "systemMessage": "string|null"              // 系统消息（显示为警告）
}
```

**事件特定输出字段**：

| 事件 | 特定字段 | 说明 |
|------|---------|------|
| SessionStart | `hookSpecificOutput.additionalContext` | 注入到模型上下文的附加信息 |
| UserPromptSubmit | `decision` ("block"), `reason`, `hookSpecificOutput.additionalContext` | 可阻止提示提交 |
| Stop | `decision` ("block"), `reason` | 可阻止/拦截停止操作 |

### 2.4 关键行为控制

1. **阻止提示提交**（UserPromptSubmit）：
   - 设置 `decision: "block"` 并提供 `reason`
   - 可选提供 `additionalContext` 作为持久化上下文

2. **阻止会话启动**（SessionStart）：
   - 设置 `continue: false` 并提供 `stopReason`
   - 可选提供 `additionalContext` 作为模型上下文

3. **拦截停止操作**（Stop）：
   - Exit code 2 + stderr 输出：转换为 block 状态
   - 或设置 `decision: "block"` + `reason`
   - `continue: false` 优先级高于 block

---

## 3. 具体技术实现

### 3.1 Schema 生成流程

```
Rust 类型定义 (schema.rs)
    ↓
schemars 派生宏生成 JSON Schema
    ↓
canonicalize_json() 排序规范化
    ↓
写入 schema/generated/*.json
```

**关键代码路径**：`codex-rs/hooks/src/schema.rs:211-241`

```rust
pub fn write_schema_fixtures(schema_root: &Path) -> anyhow::Result<()> {
    let generated_dir = schema_root.join(GENERATED_DIR);
    ensure_empty_dir(&generated_dir)?;

    write_schema(
        &generated_dir.join(SESSION_START_INPUT_FIXTURE),
        schema_json::<SessionStartCommandInput>()?,
    )?;
    // ... 其他 5 个 schema
}
```

### 3.2 核心数据结构

#### 3.2.1 输入类型（Input Types）

```rust
// SessionStartCommandInput
pub(crate) struct SessionStartCommandInput {
    pub session_id: String,
    pub transcript_path: NullableString,
    pub cwd: String,
    pub hook_event_name: String,  // 固定为 "SessionStart"
    pub model: String,
    pub permission_mode: String,
    pub source: String,  // startup/resume/clear
}

// UserPromptSubmitCommandInput
pub(crate) struct UserPromptSubmitCommandInput {
    pub session_id: String,
    pub turn_id: String,  // Codex 扩展
    pub transcript_path: NullableString,
    pub cwd: String,
    pub hook_event_name: String,  // 固定为 "UserPromptSubmit"
    pub model: String,
    pub permission_mode: String,
    pub prompt: String,
}

// StopCommandInput
pub(crate) struct StopCommandInput {
    pub session_id: String,
    pub turn_id: String,  // Codex 扩展
    pub transcript_path: NullableString,
    pub cwd: String,
    pub hook_event_name: String,  // 固定为 "Stop"
    pub model: String,
    pub permission_mode: String,
    pub stop_hook_active: bool,
    pub last_assistant_message: NullableString,
}
```

#### 3.2.2 输出类型（Output Types）

```rust
// 通用输出结构
pub(crate) struct HookUniversalOutputWire {
    #[serde(default = "default_continue")]
    pub r#continue: bool,  // 默认 true
    #[serde(default)]
    pub stop_reason: Option<String>,
    #[serde(default)]
    pub suppress_output: bool,
    #[serde(default)]
    pub system_message: Option<String>,
}

// SessionStart 特定输出
pub(crate) struct SessionStartCommandOutputWire {
    #[serde(flatten)]
    pub universal: HookUniversalOutputWire,
    pub hook_specific_output: Option<SessionStartHookSpecificOutputWire>,
}

pub(crate) struct SessionStartHookSpecificOutputWire {
    pub hook_event_name: HookEventNameWire,
    pub additional_context: Option<String>,
}

// UserPromptSubmit 特定输出
pub(crate) struct UserPromptSubmitCommandOutputWire {
    #[serde(flatten)]
    pub universal: HookUniversalOutputWire,
    pub decision: Option<BlockDecisionWire>,  // "block"
    pub reason: Option<String>,
    pub hook_specific_output: Option<UserPromptSubmitHookSpecificOutputWire>,
}

// Stop 特定输出
pub(crate) struct StopCommandOutputWire {
    #[serde(flatten)]
    pub universal: HookUniversalOutputWire,
    pub decision: Option<BlockDecisionWire>,  // "block"
    pub reason: Option<String>,
}
```

### 3.3 输出解析流程

**代码路径**：`codex-rs/hooks/src/engine/output_parser.rs`

```rust
pub(crate) fn parse_user_prompt_submit(stdout: &str) -> Option<UserPromptSubmitOutput> {
    let wire: UserPromptSubmitCommandOutputWire = parse_json(stdout)?;
    let should_block = matches!(wire.decision, Some(BlockDecisionWire::Block));
    let invalid_block_reason = if should_block && reason_is_empty(&wire.reason) {
        Some(invalid_block_message("UserPromptSubmit"))
    } else {
        None
    };
    Some(UserPromptSubmitOutput {
        universal: UniversalOutput::from(wire.universal),
        should_block: should_block && invalid_block_reason.is_none(),
        reason: wire.reason,
        invalid_block_reason,
        additional_context: wire.hook_specific_output
            .and_then(|o| o.additional_context),
    })
}
```

### 3.4 Schema 加载与嵌入

**代码路径**：`codex-rs/hooks/src/engine/schema_loader.rs`

```rust
pub(crate) fn generated_hook_schemas() -> &'static GeneratedHookSchemas {
    static SCHEMAS: OnceLock<GeneratedHookSchemas> = OnceLock::new();
    SCHEMAS.get_or_init(|| GeneratedHookSchemas {
        session_start_command_input: parse_json_schema(
            "session-start.command.input",
            include_str!("../../schema/generated/session-start.command.input.schema.json"),
        ),
        // ... 其他 5 个
    })
}
```

### 3.5 命令执行流程

**代码路径**：`codex-rs/hooks/src/engine/command_runner.rs:24-101`

```rust
pub(crate) async fn run_command(
    shell: &CommandShell,
    handler: &ConfiguredHandler,
    input_json: &str,
    cwd: &Path,
) -> CommandRunResult {
    // 1. 构建命令（支持自定义 shell 或默认 shell）
    let mut command = build_command(shell, handler);
    
    // 2. 启动子进程
    let mut child = command.spawn()?;
    
    // 3. 写入输入 JSON 到 stdin
    if let Some(mut stdin) = child.stdin.take() {
        stdin.write_all(input_json.as_bytes()).await?;
    }
    
    // 4. 带超时等待执行结果
    let timeout_duration = Duration::from_secs(handler.timeout_sec);
    match timeout(timeout_duration, child.wait_with_output()).await {
        Ok(Ok(output)) => { /* 解析输出 */ },
        Ok(Err(err)) => { /* 执行错误 */ },
        Err(_) => { /* 超时 */ }
    }
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 文件结构

```
codex-rs/hooks/
├── schema/
│   └── generated/                    # 生成的 Schema 文件目录
│       ├── session-start.command.input.schema.json
│       ├── session-start.command.output.schema.json
│       ├── user-prompt-submit.command.input.schema.json
│       ├── user-prompt-submit.command.output.schema.json
│       ├── stop.command.input.schema.json
│       └── stop.command.output.schema.json
├── src/
│   ├── bin/
│   │   └── write_hooks_schema_fixtures.rs  # Schema 生成工具
│   ├── engine/
│   │   ├── mod.rs                    # ClaudeHooksEngine 主入口
│   │   ├── command_runner.rs         # 命令执行器
│   │   ├── dispatcher.rs             # Hook 调度器
│   │   ├── output_parser.rs          # 输出解析器
│   │   ├── schema_loader.rs          # Schema 加载器（嵌入 generated/）
│   │   ├── discovery.rs              # Hook 发现（读取 hooks.json）
│   │   └── config.rs                 # 配置类型定义
│   ├── events/
│   │   ├── session_start.rs          # SessionStart 事件处理
│   │   ├── user_prompt_submit.rs     # UserPromptSubmit 事件处理
│   │   ├── stop.rs                   # Stop 事件处理
│   │   └── common.rs                 # 事件处理公共逻辑
│   ├── schema.rs                     # Schema 类型定义与生成逻辑
│   ├── types.rs                      # Hook 核心类型（HookPayload 等）
│   ├── registry.rs                   # Hooks 注册表
│   └── lib.rs                        # 库入口
├── Cargo.toml
└── BUILD.bazel
```

### 4.2 关键代码引用链

#### Schema 生成

```
just write-hooks-schema
    ↓
cargo run -p codex-hooks --bin write_hooks_schema_fixtures
    ↓
codex-rs/hooks/src/bin/write_hooks_schema_fixtures.rs
    ↓
codex_hooks::write_schema_fixtures()
    ↓
codex-rs/hooks/src/schema.rs:write_schema_fixtures()
    ↓
生成 6 个 schema 文件到 schema/generated/
```

#### Schema 使用（运行时）

```
ClaudeHooksEngine::new()
    ↓
schema_loader::generated_hook_schemas()
    ↓
include_str!("../../schema/generated/*.schema.json")
    ↓
编译时嵌入二进制
```

#### Hook 执行

```
Hooks::run_session_start() / run_user_prompt_submit() / run_stop()
    ↓
ClaudeHooksEngine::run_*()
    ↓
events::*::run()
    ↓
dispatcher::execute_handlers()
    ↓
command_runner::run_command()  --stdin-->  Hook 脚本
    ↓
output_parser::parse_*()  <--stdout--  解析输出
    ↓
events::*::parse_completed()
    ↓
返回 Outcome 结构
```

### 4.3 测试覆盖

| 测试文件 | 测试内容 |
|---------|---------|
| `codex-rs/hooks/src/schema.rs` (tests) | Schema 生成一致性测试、turn_id 扩展测试 |
| `codex-rs/hooks/src/engine/schema_loader.rs` (tests) | Schema 加载测试 |
| `codex-rs/hooks/src/events/session_start.rs` (tests) | SessionStart 输出解析测试 |
| `codex-rs/hooks/src/events/user_prompt_submit.rs` (tests) | UserPromptSubmit block 逻辑测试 |
| `codex-rs/hooks/src/events/stop.rs` (tests) | Stop block/exit code 2 逻辑测试 |
| `codex-rs/core/tests/suite/hooks.rs` | 端到端集成测试 |

---

## 5. 依赖与外部交互

### 5.1 内部依赖

| 依赖 crate | 用途 |
|-----------|------|
| `codex-protocol` | `HookEventName`, `HookRunStatus`, `HookCompletedEvent` 等协议类型 |
| `codex-config` | 配置层栈（`ConfigLayerStack`）用于发现 hooks.json |
| `schemars` | JSON Schema 生成 |
| `serde/serde_json` | 序列化/反序列化 |

### 5.2 外部交互

#### 5.2.1 配置文件交互

**hooks.json** 配置文件格式：

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
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "python3 /path/to/hook.py"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "python3 /path/to/stop_hook.py"
          }
        ]
      }
    ]
  }
}
```

#### 5.2.2 Hook 命令交互

**输入**（通过 stdin 传递 JSON）：

```json
{
  "session_id": "sess-xxx",
  "turn_id": "turn-yyy",
  "cwd": "/home/user/project",
  "hook_event_name": "UserPromptSubmit",
  "model": "gpt-4",
  "permission_mode": "default",
  "prompt": "Hello, world!",
  "transcript_path": "/home/user/.codex/transcript.jsonl"
}
```

**输出**（通过 stdout 返回 JSON）：

```json
{
  "continue": true,
  "decision": "block",
  "reason": "This prompt violates policy",
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "User attempted to ask about restricted topic"
  }
}
```

#### 5.2.3 与 core crate 交互

```
codex-core/src/hook_runtime.rs
    ↓
调用 codex_hooks::SessionStartRequest/UserPromptSubmitRequest/StopRequest
    ↓
接收 Outcome 并转换为 Runtime 决策
```

### 5.3 Bazel 集成

**BUILD.bazel**：

```starlark
SCHEMA_FIXTURES = glob(["schema/generated/*.json"], allow_empty=False)

codex_rust_crate(
    name = "hooks",
    crate_name = "codex_hooks",
    compile_data = SCHEMA_FIXTURES,          # 编译时数据
    integration_compile_data_extra = SCHEMA_FIXTURES,
    test_data_extra = SCHEMA_FIXTURES,
)
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 Schema 漂移风险

**风险**：当 `schema.rs` 中的 Rust 类型发生变化时，如果忘记运行 `just write-hooks-schema`，生成的 JSON Schema 将与实际代码不匹配。

**缓解措施**：
- `schema.rs` 中的测试 `generated_hook_schemas_match_fixtures` 会在测试时验证一致性
- CI 应运行该测试确保 Schema 最新

#### 6.1.2 Hook 命令安全风险

**风险**：Hook 命令以用户 shell 执行，可能执行恶意代码。

**缓解措施**：
- Hook 配置来自受信任的配置文件（hooks.json）
- 建议对 Hook 脚本进行代码审查
- 超时机制防止无限挂起

#### 6.1.3 JSON 解析失败处理

**边界**：
- 非 JSON 格式的 stdout（纯文本）在 SessionStart/UserPromptSubmit 中被视为 `additionalContext`
- Stop Hook 要求严格的 JSON 格式（或 exit code 2 + stderr）
- 以 `{` 或 `[` 开头但无效的 JSON 会导致 Hook 失败

### 6.2 边界条件

| 边界 | 行为 |
|------|------|
| Hook 超时 | 默认 600 秒，可配置，超时后标记为 Failed |
| Exit code 2 (Stop) | 特殊处理：从 stderr 读取 block reason |
| Exit code 2 (UserPromptSubmit) | 同上，标记为 Blocked |
| 空 stdout | 视为成功，无附加操作 |
| 空 `reason` + `decision: block` | 验证失败，Hook 标记为 Failed |
| `continue: false` + `decision: block` | `continue: false` 优先级更高 |

### 6.3 改进建议

#### 6.3.1 Schema 版本控制

**建议**：为 Schema 添加版本字段，便于未来协议演进时保持向后兼容。

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "version": "1.0",
  ...
}
```

#### 6.3.2 增强验证

**建议**：在 `schema_loader.rs` 中添加运行时 Schema 验证，确保 Hook 输出符合 Schema 后再进行业务逻辑解析。

#### 6.3.3 异步 Hook 支持

**现状**：当前仅支持同步 Hook（`async: false`），`async: true` 会被跳过并记录警告。

**建议**：实现异步 Hook 支持，允许 Hook 在后台执行不阻塞主流程。

#### 6.3.4 Prompt/Agent Hook 类型

**现状**：`Prompt` 和 `Agent` 类型的 Hook 被跳过。

**建议**：实现这些 Hook 类型，特别是 Prompt Hook 可用于动态提示修改。

#### 6.3.5 Schema 文档生成

**建议**：从生成的 JSON Schema 自动生成 Markdown 文档，便于 Hook 开发者参考。

#### 6.3.6 更丰富的输入上下文

**建议**：考虑在输入中添加更多上下文信息，如：
- 历史消息摘要
- 当前计划状态
- 工具调用历史

### 6.4 测试建议

1. **添加模糊测试**：对 `output_parser.rs` 进行模糊测试，确保各种畸形输入不会导致 panic
2. **集成测试覆盖**：扩展 `codex-rs/core/tests/suite/hooks.rs` 覆盖更多边界场景
3. **性能测试**：大量 Hook 配置时的启动和执行性能

---

## 7. 总结

`codex-rs/hooks/schema/generated/` 目录是 Codex Hooks 系统的核心协议定义，通过 6 个 JSON Schema 文件标准化了 SessionStart、UserPromptSubmit、Stop 三种事件的输入输出格式。这些 Schema 由 Rust 类型通过 `schemars` 生成，编译时嵌入二进制，运行时用于验证和解析 Hook 命令的输入输出。

理解该目录的关键在于把握：
1. **生成机制**：Rust 类型 → schemars → JSON Schema → 编译嵌入
2. **使用场景**：Hook 命令执行时的 stdin 输入和 stdout 输出验证
3. **控制语义**：`continue`、`decision: block`、`reason` 等字段的行为逻辑
4. **扩展点**：Codex 特有的 `turn_id` 扩展支持 turn-scoped Hook
