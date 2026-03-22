# codex-rs/hooks/schema 深度研究文档

## 1. 场景与职责

### 1.1 定位与作用

`codex-rs/hooks/schema` 目录是 Codex CLI 项目中 **Claude Hooks 协议** 的 JSON Schema 定义仓库。它定义了 Hook 系统与外部命令行工具交互时的输入/输出数据契约，确保 Codex 与 Claude 官方 Hook 协议的兼容性。

### 1.2 核心职责

1. **协议契约定义**：为三种 Hook 事件（SessionStart、UserPromptSubmit、Stop）定义标准化的 JSON 输入/输出 Schema
2. **Claude 兼容性**：保持与 Claude Desktop/Claude Code 的 Hook 协议兼容，允许复用现有的 Claude Hook 脚本
3. **类型安全**：通过 Rust 类型系统生成 JSON Schema，确保运行时数据验证的可靠性
4. **文档化接口**：生成的 Schema 文件作为外部 Hook 开发者的接口文档

### 1.3 使用场景

- **Hook 脚本开发**：外部开发者参考 Schema 文件编写兼容的 Hook 脚本
- **输入验证**：Codex 在调用 Hook 前，按照 Schema 构造输入 JSON
- **输出解析**：Codex 按照 Schema 解析 Hook 脚本的输出，决定后续行为（继续、阻断、停止）
- **IDE 支持**：Schema 文件可用于 IDE 的 JSON 自动补全和验证

---

## 2. 功能点目的

### 2.1 生成的 Schema 文件

目录包含 6 个生成的 JSON Schema 文件，对应三种事件类型的输入和输出：

| 文件 | 事件类型 | 方向 | 用途 |
|------|---------|------|------|
| `session-start.command.input.schema.json` | SessionStart | Input | 会话启动时传递给 Hook 的上下文 |
| `session-start.command.output.schema.json` | SessionStart | Output | Hook 返回的会话控制指令 |
| `user-prompt-submit.command.input.schema.json` | UserPromptSubmit | Input | 用户提交提示时传递的上下文 |
| `user-prompt-submit.command.output.schema.json` | UserPromptSubmit | Output | Hook 返回的提示处理决策 |
| `stop.command.input.schema.json` | Stop | Input | 停止事件时传递的上下文 |
| `stop.command.output.schema.json` | Stop | Output | Hook 返回的停止处理决策 |

### 2.2 各 Schema 的核心字段

#### SessionStart Input（会话启动输入）
```json
{
  "session_id": "string",      // 会话唯一标识
  "transcript_path": "string|null",  // 会话记录文件路径
  "cwd": "string",             // 当前工作目录
  "hook_event_name": "SessionStart", // 固定值
  "model": "string",           // 使用的模型
  "permission_mode": "enum",   // default/acceptEdits/plan/dontAsk/bypassPermissions
  "source": "enum"             // startup/resume/clear
}
```

#### SessionStart Output（会话启动输出）
```json
{
  "continue": true,            // 是否继续处理（默认 true）
  "stopReason": "string|null", // 停止原因（当 continue=false）
  "suppressOutput": false,     // 是否抑制输出
  "systemMessage": "string|null", // 系统消息
  "hookSpecificOutput": {      // Hook 特定输出
    "hookEventName": "SessionStart",
    "additionalContext": "string|null" // 给模型的额外上下文
  }
}
```

#### UserPromptSubmit Input（用户提示提交输入）
```json
{
  "session_id": "string",
  "turn_id": "string",         // Codex 扩展：回合标识
  "transcript_path": "string|null",
  "cwd": "string",
  "hook_event_name": "UserPromptSubmit",
  "model": "string",
  "permission_mode": "enum",
  "prompt": "string"           // 用户输入的提示
}
```

#### UserPromptSubmit Output（用户提示提交输出）
```json
{
  "continue": true,
  "stopReason": "string|null",
  "suppressOutput": false,
  "systemMessage": "string|null",
  "decision": "block|null",    // 阻断决策
  "reason": "string|null",     // 阻断原因（decision=block 时必须）
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "string|null"
  }
}
```

#### Stop Input（停止事件输入）
```json
{
  "session_id": "string",
  "turn_id": "string",
  "transcript_path": "string|null",
  "cwd": "string",
  "hook_event_name": "Stop",
  "model": "string",
  "permission_mode": "enum",
  "stop_hook_active": "boolean",     // 停止 Hook 是否激活
  "last_assistant_message": "string|null"
}
```

#### Stop Output（停止事件输出）
```json
{
  "continue": true,
  "stopReason": "string|null",
  "suppressOutput": false,
  "systemMessage": "string|null",
  "decision": "block|null",
  "reason": "string|null"
}
```

### 2.3 关键行为控制

| 输出字段 | 行为影响 |
|---------|---------|
| `continue: false` | 停止后续 Hook 执行，可能终止当前操作 |
| `decision: "block"` | 阻断当前操作（如阻止提示提交），需要 `reason` |
| `additionalContext` | 注入到模型上下文中，影响 AI 回复 |
| `systemMessage` | 向用户显示系统级消息 |
| `suppressOutput` | 抑制 Hook 的标准输出显示 |

---

## 3. 具体技术实现

### 3.1 核心数据结构（Rust 类型定义）

Schema 生成位于 `codex-rs/hooks/src/schema.rs`：

#### 3.1.1 通用输出结构
```rust
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
#[serde(deny_unknown_fields)]
pub(crate) struct HookUniversalOutputWire {
    #[serde(default = "default_continue")]
    pub r#continue: bool,              // 是否继续（默认 true）
    #[serde(default)]
    pub stop_reason: Option<String>,   // 停止原因
    #[serde(default)]
    pub suppress_output: bool,         // 抑制输出
    #[serde(default)]
    pub system_message: Option<String>, // 系统消息
}
```

#### 3.1.2 事件名称枚举
```rust
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, PartialEq, Eq)]
pub(crate) enum HookEventNameWire {
    #[serde(rename = "SessionStart")]
    SessionStart,
    #[serde(rename = "UserPromptSubmit")]
    UserPromptSubmit,
    #[serde(rename = "Stop")]
    Stop,
}
```

#### 3.1.3 阻断决策枚举
```rust
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, PartialEq, Eq)]
pub(crate) enum BlockDecisionWire {
    #[serde(rename = "block")]
    Block,
}
```

#### 3.1.4 输入结构
```rust
// SessionStart 输入
#[derive(Debug, Clone, Serialize, JsonSchema)]
#[serde(deny_unknown_fields)]
#[schemars(rename = "session-start.command.input")]
pub(crate) struct SessionStartCommandInput {
    pub session_id: String,
    pub transcript_path: NullableString,
    pub cwd: String,
    #[schemars(schema_with = "session_start_hook_event_name_schema")]
    pub hook_event_name: String,  // 固定为 "SessionStart"
    pub model: String,
    #[schemars(schema_with = "permission_mode_schema")]
    pub permission_mode: String,  // 枚举值
    #[schemars(schema_with = "session_start_source_schema")]
    pub source: String,           // 枚举值
}

// UserPromptSubmit 输入（Codex 扩展包含 turn_id）
#[derive(Debug, Clone, Serialize, JsonSchema)]
#[serde(deny_unknown_fields)]
#[schemars(rename = "user-prompt-submit.command.input")]
pub(crate) struct UserPromptSubmitCommandInput {
    pub session_id: String,
    pub turn_id: String,  // Codex 扩展字段
    pub transcript_path: NullableString,
    pub cwd: String,
    pub hook_event_name: String,
    pub model: String,
    pub permission_mode: String,
    pub prompt: String,
}

// Stop 输入
#[derive(Debug, Clone, Serialize, JsonSchema)]
#[serde(deny_unknown_fields)]
#[schemars(rename = "stop.command.input")]
pub(crate) struct StopCommandInput {
    pub session_id: String,
    pub turn_id: String,
    pub transcript_path: NullableString,
    pub cwd: String,
    pub hook_event_name: String,
    pub model: String,
    pub permission_mode: String,
    pub stop_hook_active: bool,
    pub last_assistant_message: NullableString,
}
```

#### 3.1.5 输出结构
```rust
// SessionStart 输出
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
#[serde(deny_unknown_fields)]
#[schemars(rename = "session-start.command.output")]
pub(crate) struct SessionStartCommandOutputWire {
    #[serde(flatten)]
    pub universal: HookUniversalOutputWire,
    #[serde(default)]
    pub hook_specific_output: Option<SessionStartHookSpecificOutputWire>,
}

// UserPromptSubmit 输出（支持阻断决策）
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
#[serde(deny_unknown_fields)]
#[schemars(rename = "user-prompt-submit.command.output")]
pub(crate) struct UserPromptSubmitCommandOutputWire {
    #[serde(flatten)]
    pub universal: HookUniversalOutputWire,
    #[serde(default)]
    pub decision: Option<BlockDecisionWire>,  // block 或 null
    #[serde(default)]
    pub reason: Option<String>,               // 阻断原因
    #[serde(default)]
    pub hook_specific_output: Option<UserPromptSubmitHookSpecificOutputWire>,
}

// Stop 输出
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
#[serde(deny_unknown_fields)]
#[schemars(rename = "stop.command.output")]
pub(crate) struct StopCommandOutputWire {
    #[serde(flatten)]
    pub universal: HookUniversalOutputWire,
    #[serde(default)]
    pub decision: Option<BlockDecisionWire>,
    pub reason: Option<String>,  // Claude 要求 decision=block 时必须有 reason
}
```

#### 3.1.6 NullableString 类型
```rust
#[derive(Debug, Clone, Serialize)]
#[serde(transparent)]
pub(crate) struct NullableString(Option<String>);

impl JsonSchema for NullableString {
    fn schema_name() -> String {
        "NullableString".to_string()
    }

    fn json_schema(_gen: &mut SchemaGenerator) -> Schema {
        Schema::Object(SchemaObject {
            instance_type: Some(vec![InstanceType::String, InstanceType::Null].into()),
            ..Default::default()
        })
    }
}
```

### 3.2 Schema 生成流程

#### 3.2.1 生成入口
```rust
// codex-rs/hooks/src/schema.rs
pub fn write_schema_fixtures(schema_root: &Path) -> anyhow::Result<()> {
    let generated_dir = schema_root.join(GENERATED_DIR);
    ensure_empty_dir(&generated_dir)?;

    write_schema(
        &generated_dir.join(SESSION_START_INPUT_FIXTURE),
        schema_json::<SessionStartCommandInput>()?,
    )?;
    // ... 其他 5 个 schema 文件
}
```

#### 3.2.2 生成逻辑
```rust
fn schema_json<T>() -> anyhow::Result<Vec<u8>>
where
    T: JsonSchema,
{
    let schema = schema_for_type::<T>();
    let value = serde_json::to_value(schema)?;
    let value = canonicalize_json(&value);  // 规范化 JSON（排序键）
    Ok(serde_json::to_vec_pretty(&value)?)
}

fn schema_for_type<T>() -> RootSchema
where
    T: JsonSchema,
{
    SchemaSettings::draft07()
        .with(|settings| {
            settings.option_add_null_type = false;  // Option<T> 不添加 null 类型
        })
        .into_generator()
        .into_root_schema_for::<T>()
}

// JSON 规范化：递归排序对象键，确保生成稳定的输出
fn canonicalize_json(value: &Value) -> Value {
    match value {
        Value::Array(items) => Value::Array(items.iter().map(canonicalize_json).collect()),
        Value::Object(map) => {
            let mut entries: Vec<_> = map.iter().collect();
            entries.sort_by(|(left, _), (right, _)| left.cmp(right));
            let mut sorted = Map::with_capacity(map.len());
            for (key, child) in entries {
                sorted.insert(key.clone(), canonicalize_json(child));
            }
            Value::Object(sorted)
        }
        _ => value.clone(),
    }
}
```

#### 3.2.3 自定义 Schema 生成器
```rust
// 固定字符串常量（如 hook_event_name）
fn string_const_schema(value: &str) -> Schema {
    let mut schema = SchemaObject {
        instance_type: Some(InstanceType::String.into()),
        ..Default::default()
    };
    schema.const_value = Some(Value::String(value.to_string()));
    Schema::Object(schema)
}

// 字符串枚举（如 permission_mode、source）
fn string_enum_schema(values: &[&str]) -> Schema {
    let mut schema = SchemaObject {
        instance_type: Some(InstanceType::String.into()),
        ..Default::default()
    };
    schema.enum_values = Some(
        values
            .iter()
            .map(|value| Value::String((*value).to_string()))
            .collect(),
    );
    Schema::Object(schema)
}
```

### 3.3 Schema 加载与使用

Schema 文件通过 `schema_loader.rs` 在编译时嵌入到二进制中：

```rust
// codex-rs/hooks/src/engine/schema_loader.rs
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

### 3.4 输出解析逻辑

Hook 输出解析位于 `output_parser.rs`：

```rust
pub(crate) fn parse_session_start(stdout: &str) -> Option<SessionStartOutput> {
    let wire: SessionStartCommandOutputWire = parse_json(stdout)?;
    let additional_context = wire
        .hook_specific_output
        .and_then(|output| output.additional_context);
    Some(SessionStartOutput {
        universal: UniversalOutput::from(wire.universal),
        additional_context,
    })
}

pub(crate) fn parse_user_prompt_submit(stdout: &str) -> Option<UserPromptSubmitOutput> {
    let wire: UserPromptSubmitCommandOutputWire = parse_json(stdout)?;
    let should_block = matches!(wire.decision, Some(BlockDecisionWire::Block));
    // 验证：decision=block 时必须提供非空 reason
    let invalid_block_reason = if should_block
        && match wire.reason.as_deref() {
            Some(reason) => reason.trim().is_empty(),
            None => true,
        } {
        Some(invalid_block_message("UserPromptSubmit"))
    } else {
        None
    };
    // ...
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 文件结构

```
codex-rs/hooks/schema/
└── generated/                          # 生成的 Schema 文件目录
    ├── session-start.command.input.schema.json
    ├── session-start.command.output.schema.json
    ├── user-prompt-submit.command.input.schema.json
    ├── user-prompt-submit.command.output.schema.json
    ├── stop.command.input.schema.json
    └── stop.command.output.schema.json

codex-rs/hooks/src/
├── schema.rs                           # Schema 类型定义与生成逻辑（437 行）
├── engine/
│   ├── schema_loader.rs               # Schema 加载器（66 行）
│   ├── output_parser.rs               # 输出解析器（121 行）
│   ├── command_runner.rs              # 命令执行器（135 行）
│   ├── dispatcher.rs                  # 事件分发器（209 行）
│   ├── discovery.rs                   # Hook 发现（245 行）
│   ├── config.rs                      # 配置解析（44 行）
│   └── mod.rs                         # 引擎模块入口（126 行）
├── events/
│   ├── session_start.rs               # SessionStart 事件处理（376 行）
│   ├── user_prompt_submit.rs          # UserPromptSubmit 事件处理（436 行）
│   ├── stop.rs                        # Stop 事件处理（518 行）
│   ├── common.rs                      # 事件处理公共函数（69 行）
│   └── mod.rs                         # 事件模块入口（4 行）
├── bin/
│   └── write_hooks_schema_fixtures.rs # Schema 生成 CLI 工具（9 行）
├── types.rs                           # 旧版 Hook 类型定义（290 行）
├── registry.rs                        # Hook 注册表（137 行）
├── lib.rs                             # 库入口（30 行）
├── Cargo.toml                         # 包配置
└── BUILD.bazel                        # Bazel 构建配置
```

### 4.2 关键代码路径

#### 4.2.1 Schema 生成路径
```
just write-hooks-schema
  → cargo run -p codex-hooks --bin write_hooks_schema_fixtures
    → codex-rs/hooks/src/bin/write_hooks_schema_fixtures.rs
      → codex_hooks::write_schema_fixtures()
        → codex-rs/hooks/src/schema.rs:write_schema_fixtures()
          → 生成 6 个 JSON Schema 文件到 schema/generated/
```

#### 4.2.2 Hook 调用路径
```
ClaudeHooksEngine::run_session_start()
  → events/session_start.rs:run()
    → 构造 SessionStartCommandInput
    → serde_json::to_string() 生成输入 JSON
    → dispatcher::execute_handlers()
      → command_runner::run_command() 执行 Hook 命令
      → 解析输出：output_parser::parse_session_start()
        → 反序列化为 SessionStartCommandOutputWire
        → 转换为 SessionStartOutput
```

#### 4.2.3 Schema 嵌入路径
```
ClaudeHooksEngine::new()
  → schema_loader::generated_hook_schemas()
    → include_str!() 嵌入 6 个 JSON 文件
    → 编译时静态包含 Schema 内容
```

### 4.3 测试覆盖

Schema 相关测试位于：

1. **`schema.rs` 内联测试**（行 347-437）：
   - `generated_hook_schemas_match_fixtures`：验证生成的 Schema 与 fixture 文件一致
   - `turn_scoped_hook_inputs_include_codex_turn_id_extension`：验证 Codex 扩展字段（turn_id）

2. **`schema_loader.rs` 内联测试**（行 50-66）：
   - `loads_generated_hook_schemas`：验证 Schema 加载成功

---

## 5. 依赖与外部交互

### 5.1 内部依赖

| 依赖模块 | 用途 |
|---------|------|
| `codex-config` | 读取配置层栈，发现 hooks.json 文件 |
| `codex-protocol` | Hook 事件协议类型（HookEventName、HookRunStatus 等） |

### 5.2 外部依赖（Cargo）

| Crate | 用途 |
|-------|------|
| `schemars` | JSON Schema 生成 |
| `serde` | 序列化/反序列化 |
| `serde_json` | JSON 处理 |
| `anyhow` | 错误处理 |
| `chrono` | 时间戳处理 |
| `tokio` | 异步运行时 |
| `futures` | 异步工具 |
| `regex` | 正则匹配（SessionStart matcher） |

### 5.3 与 Claude 协议的兼容性

Schema 设计遵循 Claude 官方 Hook 协议，关键兼容点：

1. **字段命名**：使用 `camelCase`（如 `hookEventName`、`stopReason`）
2. **枚举值**：与 Claude 保持一致（如 `permission_mode` 的值）
3. **行为语义**：
   - `continue: false` 表示停止处理
   - `decision: "block"` 表示阻断操作
   - `reason` 在阻断时必需

4. **Codex 扩展**：
   - `turn_id` 字段：Codex 特有，用于回合级 Hook 追踪
   - 注释标记：`"Codex extension: expose the active turn id to internal turn-scoped hooks."`

### 5.4 配置文件交互

Hook 配置通过 `hooks.json` 文件定义：

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
            "timeout": 30
          }
        ]
      }
    ],
    "UserPromptSubmit": [...],
    "Stop": [...]
  }
}
```

配置解析位于 `engine/config.rs` 和 `engine/discovery.rs`。

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 Schema 漂移风险
- **风险**：Rust 类型修改后，若未重新生成 Schema，可能导致 fixture 文件与实际代码不一致
- **缓解**：CI 应运行 `just write-hooks-schema` 并检查是否有未提交的变更
- **测试覆盖**：`generated_hook_schemas_match_fixtures` 测试会在类型变更时失败

#### 6.1.2 阻断决策缺少 reason 的验证
- **风险**：`decision: "block"` 时如果 `reason` 为空，Hook 会失败而不是阻断
- **当前行为**：输出解析器会设置 `invalid_block_reason`，状态变为 `Failed` 而非 `Blocked`
- **代码位置**：`output_parser.rs:52-60`（UserPromptSubmit）、`stop.rs:165-191`（Stop）

#### 6.1.3 JSON 解析失败降级
- **风险**：Hook 输出非 JSON 且以 `{` 或 `[` 开头时，会被视为无效 JSON 而非纯文本上下文
- **代码位置**：`session_start.rs:190-202`、`user_prompt_submit.rs:196-209`
- **行为**：返回 `Failed` 状态而非将输出作为上下文

### 6.2 边界情况

#### 6.2.1 空输出处理
- **SessionStart**：空 stdout 被视为无操作（无上下文添加）
- **UserPromptSubmit/Stop**：空 stdout 同样无操作

#### 6.2.2 Exit Code 处理
| Exit Code | 行为 |
|-----------|------|
| 0 | 正常处理，解析 stdout |
| 2 | 特殊处理：从 stderr 读取阻断原因（UserPromptSubmit/Stop） |
| 其他非 0 | 标记为 Failed |

#### 6.2.3 超时处理
- 默认超时：600 秒（`timeout_sec.unwrap_or(600)`）
- 最小超时：1 秒（`.max(1)`）
- 超时后：状态为 Failed，错误信息包含超时时间

### 6.3 改进建议

#### 6.3.1 Schema 版本管理
- **建议**：为 Schema 添加版本字段，便于未来协议演进
- **实现**：在输入/输出结构中添加 `schema_version: u32` 字段

#### 6.3.2 更严格的输入验证
- **建议**：使用生成的 Schema 在运行时验证 Hook 输出
- **当前**：仅依赖 serde 反序列化，不验证是否符合 Schema
- **实现**：在 `output_parser.rs` 中添加 JSON Schema 验证步骤

#### 6.3.3 异步 Hook 支持
- **当前**：仅支持同步 Hook（`execute_handlers` 使用 `join_all` 并发执行）
- **建议**：`discovery.rs` 中已预留 `r#async` 字段，但标记为不支持
- **实现**：需要设计异步 Hook 的生命周期管理（何时认为完成？）

#### 6.3.4 Prompt/Agent Hook 支持
- **当前**：`config.rs` 中定义了 `Prompt` 和 `Agent` 类型，但 `discovery.rs` 中跳过并警告
- **建议**：实现完整的 Hook 类型支持

#### 6.3.5 Schema 文档生成
- **建议**：从 Schema 自动生成 Markdown 文档，便于外部开发者参考
- **实现**：添加 `write_hooks_schema_docs` 二进制工具

#### 6.3.6 性能优化
- **建议**：`canonicalize_json` 在大型 Schema 时可能有性能影响
- **实现**：考虑使用 `serde_json::Value` 的排序替代方案，或缓存结果

### 6.4 测试建议

1. **添加负面测试**：验证无效 Schema 输入的处理
2. **添加兼容性测试**：验证与 Claude 官方 Hook 脚本的兼容性
3. **添加性能测试**：大规模 Hook 配置下的性能基准
4. **添加模糊测试**：使用 `arbitrary` 生成随机输入测试鲁棒性

---

## 7. 总结

`codex-rs/hooks/schema` 是 Codex CLI Hook 系统的核心协议层，负责：

1. **定义数据契约**：通过 JSON Schema 明确 Hook 输入/输出格式
2. **保证 Claude 兼容性**：复用 Claude 生态的 Hook 脚本
3. **类型安全**：Rust 类型驱动 Schema 生成，避免手写错误
4. **可扩展性**：Codex 扩展（如 `turn_id`）在保持兼容的同时增加功能

关键设计决策：
- 使用 `schemars` 从 Rust 类型自动生成 Schema
- 编译时嵌入 Schema 文件，避免运行时文件依赖
- 输出解析时进行语义验证（如 block 必须带 reason）
- 支持纯文本和结构化 JSON 两种输出模式
