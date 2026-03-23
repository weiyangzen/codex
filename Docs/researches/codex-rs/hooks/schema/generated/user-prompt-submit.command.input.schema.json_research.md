# user-prompt-submit.command.input.schema.json 研究文档

## 场景与职责

`user-prompt-submit.command.input.schema.json` 是 Codex Hooks 系统中 **UserPromptSubmit** 事件的命令输入 JSON Schema 定义文件。它定义了当用户提交提示（prompt）时，Codex 向外部钩子命令传递的输入数据结构。

UserPromptSubmit 是一个 **Turn-scoped（回合级）** 钩子，在每个用户输入提交给模型之前触发。它允许钩子审查、修改或阻止用户输入，是实现输入过滤、安全检查或提示增强的关键机制。

## 功能点目的

### 核心功能
1. **输入审查**: 在用户提示发送给模型前进行审查
2. **安全检查**: 检测潜在的有害或敏感输入
3. **提示增强**: 通过钩子添加额外上下文或修改提示内容
4. **输入阻止**: 阻止某些类型的输入到达模型
5. **回合追踪**: 通过 `turn_id` 支持回合级的钩子追踪

### 核心字段

| 字段 | 类型 | 说明 |
|------|------|------|
| `prompt` | string | 用户提交的原始提示内容（UserPromptSubmit 特有） |
| `turn_id` | string | 当前回合唯一标识（Codex 扩展） |
| `session_id` | string | 会话唯一标识 |
| `cwd` | string | 当前工作目录 |
| `model` | string | 目标模型名称 |
| `permission_mode` | enum | 当前权限模式 |
| `transcript_path` | NullableString | 转录文件路径 |

## 具体技术实现

### 数据结构定义

```json
{
  "properties": {
    "cwd": { "type": "string" },
    "hook_event_name": { "const": "UserPromptSubmit" },
    "model": { "type": "string" },
    "permission_mode": {
      "enum": ["default", "acceptEdits", "plan", "dontAsk", "bypassPermissions"]
    },
    "prompt": { "type": "string" },  // 核心字段
    "session_id": { "type": "string" },
    "transcript_path": { "$ref": "#/definitions/NullableString" },
    "turn_id": {
      "description": "Codex extension: expose the active turn id to internal turn-scoped hooks.",
      "type": "string"
    }
  },
  "required": [
    "cwd", "hook_event_name", "model", "permission_mode",
    "prompt", "session_id", "transcript_path", "turn_id"
  ]
}
```

### Rust 结构体定义

```rust
#[derive(Debug, Clone, Serialize, JsonSchema)]
#[serde(deny_unknown_fields)]
#[schemars(rename = "user-prompt-submit.command.input")]
pub(crate) struct UserPromptSubmitCommandInput {
    pub session_id: String,
    /// Codex extension: expose the active turn id to internal turn-scoped hooks.
    pub turn_id: String,
    pub transcript_path: NullableString,
    pub cwd: String,
    #[schemars(schema_with = "user_prompt_submit_hook_event_name_schema")]
    pub hook_event_name: String,
    pub model: String,
    #[schemars(schema_with = "permission_mode_schema")]
    pub permission_mode: String,
    pub prompt: String,  // 用户提示内容
}
```

### 关键流程

1. **输入构造** (`codex-rs/hooks/src/events/user_prompt_submit.rs` 第 79-97 行):
   ```rust
   let input_json = match serde_json::to_string(&UserPromptSubmitCommandInput {
       session_id: request.session_id.to_string(),
       turn_id: request.turn_id.clone(),
       transcript_path: NullableString::from_path(request.transcript_path.clone()),
       cwd: request.cwd.display().to_string(),
       hook_event_name: "UserPromptSubmit".to_string(),
       model: request.model.clone(),
       permission_mode: request.permission_mode.clone(),
       prompt: request.prompt.clone(),  // 用户提示
   })
   ```

2. **钩子选择** (`codex-rs/hooks/src/engine/dispatcher.rs`):
   ```rust
   HookEventName::UserPromptSubmit | HookEventName::Stop => true,
   ```
   UserPromptSubmit 忽略 matcher，所有配置的钩子都会执行

3. **作用域标识** (`codex-rs/hooks/src/engine/dispatcher.rs` 第 109-114 行):
   ```rust
   fn scope_for_event(event_name: HookEventName) -> HookScope {
       match event_name {
           HookEventName::SessionStart => HookScope::Thread,
           HookEventName::UserPromptSubmit | HookEventName::Stop => HookScope::Turn,
       }
   }
   ```

### 与 Stop 输入的对比

| 特性 | UserPromptSubmit | Stop |
|------|------------------|------|
| 触发时机 | 用户提交提示前 | 用户请求停止时 |
| 特有字段 | `prompt` | `stop_hook_active`, `last_assistant_message` |
| 用途 | 输入审查/增强 | 停止确认/清理 |
| Scope | Turn | Turn |

## 关键代码路径与文件引用

### Schema 生成
| 文件 | 职责 |
|------|------|
| `codex-rs/hooks/src/schema.rs` (176-191行) | `UserPromptSubmitCommandInput` 结构体 |
| `codex-rs/hooks/src/schema.rs` (298-300行) | `user_prompt_submit_hook_event_name_schema()` |

### 事件处理
| 文件 | 职责 |
|------|------|
| `codex-rs/hooks/src/events/user_prompt_submit.rs` (20-29行) | `UserPromptSubmitRequest` 定义 |
| `codex-rs/hooks/src/events/user_prompt_submit.rs` (31-37行) | `UserPromptSubmitOutcome` 定义 |
| `codex-rs/hooks/src/events/user_prompt_submit.rs` (60-125行) | `run()` 主执行函数 |
| `codex-rs/hooks/src/events/user_prompt_submit.rs` (127-258行) | `parse_completed()` 结果解析 |

### 调度与执行
| 文件 | 职责 |
|------|------|
| `codex-rs/hooks/src/engine/dispatcher.rs` (24-44行) | `select_handlers()` 忽略 matcher |
| `codex-rs/hooks/src/engine/dispatcher.rs` (109-114行) | `scope_for_event()` 返回 `HookScope::Turn` |

### 测试覆盖
| 文件 | 测试内容 |
|------|----------|
| `codex-rs/hooks/src/schema.rs` (413-436行) | `turn_scoped_hook_inputs_include_codex_turn_id_extension` |
| `codex-rs/hooks/src/events/user_prompt_submit.rs` (284-318行) | `continue_false_preserves_context_for_later_turns` |
| `codex-rs/hooks/src/events/user_prompt_submit.rs` (320-354行) | `claude_block_decision_blocks_processing` |
| `codex-rs/hooks/src/events/user_prompt_submit.rs` (356-385行) | `claude_block_decision_requires_reason` |
| `codex-rs/hooks/src/events/user_prompt_submit.rs` (387-411行) | `exit_code_two_blocks_processing` |

## 依赖与外部交互

### 上游依赖
1. **codex_protocol::HookEventName::UserPromptSubmit**: 事件类型标识
2. **codex_protocol::HookScope::Turn**: 作用域定义
3. **schemars**: Schema 生成

### 下游消费者
1. **外部钩子命令**: 接收用户提示进行审查
2. **ClaudeHooksEngine**: 通过 `run_user_prompt_submit()` 触发

### 协议层级
```
User Input (Prompt)
    ↓
Codex Core
    ↓
ClaudeHooksEngine::run_user_prompt_submit(UserPromptSubmitRequest)
    ↓
UserPromptSubmitCommandInput (JSON)
    ↓
External Hook Commands (stdin)
    ↓
UserPromptSubmitCommandOutput (JSON Response)
    ↓
UserPromptSubmitOutcome (Block/Continue Decision)
    ↓
Model (if not blocked)
```

### 相关 Schema
- `user-prompt-submit.command.output.schema.json`: 对应的输出 Schema（支持 block 决策和上下文注入）
- `stop.command.input.schema.json`: 类似的 Turn-scoped 输入结构

## 风险、边界与改进建议

### 当前风险

1. **Prompt 内容可能很大**:
   - 用户可能粘贴大量文本作为提示
   - 无长度限制，可能导致 JSON 序列化/传输开销
   - 风险: 内存压力、传输延迟

2. **敏感信息泄露**:
   - `prompt` 字段包含用户原始输入
   - 可能包含密码、API 密钥等敏感信息
   - 风险: 钩子命令可能无意中记录或泄露这些信息

3. **循环触发**:
   - 钩子修改后的提示如果再次触发 UserPromptSubmit
   - 可能导致无限循环
   - 当前无递归深度限制

### 边界情况

1. **空 Prompt**:
   - Schema 允许空字符串
   - 实际场景中可能发生（用户只发送空白字符）

2. **特殊字符**:
   - Prompt 可能包含任意 Unicode 字符
   - JSON 序列化需要正确处理转义

3. **并发提交**:
   - 快速连续提交多个提示
   - 每个提示触发独立的钩子执行

### 改进建议

1. **添加 Prompt 长度限制**:
   ```rust
   const MAX_PROMPT_LENGTH: usize = 100000; // 100KB
   prompt: if request.prompt.len() > MAX_PROMPT_LENGTH {
       format!("{}... [truncated {} chars]", 
           &request.prompt[..MAX_PROMPT_LENGTH/2],
           request.prompt.len() - MAX_PROMPT_LENGTH/2)
   } else {
       request.prompt.clone()
   }
   ```

2. **敏感信息过滤**:
   ```rust
   // 添加敏感信息检测和标记
   fn sanitize_prompt(prompt: &str) -> (String, Vec<SensitiveContentWarning>) {
       // 检测 API 密钥、密码模式等
   }
   ```

3. **递归保护**:
   ```rust
   // 在 ClaudeHooksEngine 中添加递归深度追踪
   prompt_submit_depth: Arc<AtomicUsize>,
   const MAX_PROMPT_SUBMIT_DEPTH: usize = 3;
   ```

4. **字段文档化**:
   ```json
   "prompt": {
     "type": "string",
     "description": "The user's raw input prompt. May contain sensitive information. Hooks should handle with care."
   }
   ```

5. **添加元数据字段**:
   ```json
   {
     "prompt_length": 1234,
     "prompt_hash": "sha256:abc...",
     "contains_code": true,
     "estimated_tokens": 300
   }
   ```

### 测试覆盖分析

| 测试场景 | 覆盖状态 | 说明 |
|----------|----------|------|
| 基本输入序列化 | ✅ | schema.rs 集成测试 |
| turn_id 存在性 | ✅ | turn_scoped_hook_inputs_include_codex_turn_id_extension |
| continue=false | ✅ | continue_false_preserves_context_for_later_turns |
| Block 决策 | ✅ | claude_block_decision_blocks_processing |
| Block 无 reason | ✅ | claude_block_decision_requires_reason |
| 退出码 2 | ✅ | exit_code_two_blocks_processing |
| 大 Prompt | ❌ | 未覆盖 |
| 敏感字符 | ❌ | 未覆盖 |
| 空 Prompt | ⚠️ | 间接覆盖 |

建议添加针对大 Prompt 和特殊字符的测试用例。
