# stop.command.input.schema.json 研究文档

## 场景与职责

`stop.command.input.schema.json` 是 Codex Hooks 系统中 **Stop** 事件的命令输入 JSON Schema 定义文件。它定义了当用户请求停止/中断当前对话回合时，Codex 向外部钩子命令传递的输入数据结构。

Stop 事件是一个 **Turn-scoped（回合级）** 钩子，与 SessionStart（Thread-scoped）不同，它在每个用户回合结束时触发，用于执行清理、验证或拦截操作。

## 功能点目的

### 核心功能
1. **停止事件触发**: 用户主动中断对话时触发钩子执行
2. **上下文传递**: 提供停止时的完整会话和回合上下文
3. **最后消息传递**: 包含助手的最后一条消息内容（用于分析停止原因）
4. **停止钩子激活状态**: 标识当前是否处于停止钩子处理流程中
5. **回合标识**: 通过 `turn_id` 支持回合级的钩子追踪

### 与 SessionStart 输入的区别

| 特性 | SessionStart | Stop |
|------|--------------|------|
| Scope | Thread | Turn |
| 触发时机 | 会话开始 | 回合停止 |
| 特有字段 | `source` | `turn_id`, `stop_hook_active`, `last_assistant_message` |
| 必填字段 | 7个 | 8个（含 `turn_id`） |

## 具体技术实现

### 数据结构定义

```json
{
  "properties": {
    "cwd": { "type": "string" },
    "hook_event_name": { "const": "Stop" },
    "last_assistant_message": { "$ref": "#/definitions/NullableString" },
    "model": { "type": "string" },
    "permission_mode": {
      "enum": ["default", "acceptEdits", "plan", "dontAsk", "bypassPermissions"]
    },
    "session_id": { "type": "string" },
    "stop_hook_active": { "type": "boolean" },
    "transcript_path": { "$ref": "#/definitions/NullableString" },
    "turn_id": { 
      "description": "Codex extension: expose the active turn id to internal turn-scoped hooks.",
      "type": "string" 
    }
  },
  "required": [
    "cwd", "hook_event_name", "last_assistant_message", "model",
    "permission_mode", "session_id", "stop_hook_active", "transcript_path", "turn_id"
  ]
}
```

### Rust 结构体定义

```rust
#[derive(Debug, Clone, Serialize, JsonSchema)]
#[serde(deny_unknown_fields)]
#[schemars(rename = "stop.command.input")]
pub(crate) struct StopCommandInput {
    pub session_id: String,
    pub turn_id: String,  // Codex 扩展字段
    pub transcript_path: NullableString,
    pub cwd: String,
    #[schemars(schema_with = "stop_hook_event_name_schema")]
    pub hook_event_name: String,
    pub model: String,
    #[schemars(schema_with = "permission_mode_schema")]
    pub permission_mode: String,
    pub stop_hook_active: bool,
    pub last_assistant_message: NullableString,
}
```

### 关键流程

1. **输入构造** (`codex-rs/hooks/src/events/stop.rs` 第 79-98 行):
   ```rust
   let input_json = match serde_json::to_string(&StopCommandInput {
       session_id: request.session_id.to_string(),
       turn_id: request.turn_id.clone(),
       transcript_path: NullableString::from_path(request.transcript_path.clone()),
       cwd: request.cwd.display().to_string(),
       hook_event_name: "Stop".to_string(),
       model: request.model.clone(),
       permission_mode: request.permission_mode.clone(),
       stop_hook_active: request.stop_hook_active,
       last_assistant_message: NullableString::from_string(request.last_assistant_message.clone()),
   })
   ```

2. **回合 ID 扩展**:
   - Stop 事件是 Turn-scoped，必须包含 `turn_id`
   - 这是 Codex 对 Claude 原始 Hook 协议的扩展
   - 测试验证: `schema.rs` 第 413-436 行 `turn_scoped_hook_inputs_include_codex_turn_id_extension`

3. **钩子选择** (`codex-rs/hooks/src/engine/dispatcher.rs`):
   ```rust
   HookEventName::UserPromptSubmit | HookEventName::Stop => true,
   ```
   Stop 事件忽略 matcher，所有 Stop 钩子都会被执行

### 停止钩子激活状态

`stop_hook_active` 字段用于防止递归调用：
- 当值为 `true` 时，表示当前已经在 Stop 钩子处理流程中
- 钩子可以根据此状态决定是否执行某些操作
- 避免在 Stop 钩子内部再次触发 Stop 逻辑

## 关键代码路径与文件引用

### Schema 生成
| 文件 | 职责 |
|------|------|
| `codex-rs/hooks/src/schema.rs` (195-209行) | `StopCommandInput` 结构体定义 |
| `codex-rs/hooks/src/schema.rs` (302-304行) | `stop_hook_event_name_schema()` 构造器 |

### 事件处理
| 文件 | 职责 |
|------|------|
| `codex-rs/hooks/src/events/stop.rs` (20-50行) | `StopRequest` 和 `StopOutcome` 定义 |
| `codex-rs/hooks/src/events/stop.rs` (61-120行) | `run()` 主执行函数 |
| `codex-rs/hooks/src/events/stop.rs` (122-253行) | `parse_completed()` 结果解析 |

### 调度与执行
| 文件 | 职责 |
|------|------|
| `codex-rs/hooks/src/engine/dispatcher.rs` (24-44行) | `select_handlers()` 钩子选择逻辑 |
| `codex-rs/hooks/src/engine/dispatcher.rs` (109-114行) | `scope_for_event()` 返回 `HookScope::Turn` |

### 测试
| 文件 | 测试内容 |
|------|----------|
| `codex-rs/hooks/src/schema.rs` (413-436行) | `turn_scoped_hook_inputs_include_codex_turn_id_extension` |
| `codex-rs/hooks/src/events/stop.rs` (319-424行) | 各种输出解析场景测试 |

## 依赖与外部交互

### 上游依赖
1. **codex_protocol::HookEventName::Stop**: 事件类型标识
2. **codex_protocol::HookScope::Turn**: 作用域定义
3. **schemars**: Schema 生成

### 下游消费者
1. **外部钩子命令**: 接收 Stop 事件输入
2. **ClaudeHooksEngine**: 通过 `run_stop()` 触发

### 协议层级
```
User Action (Stop/Ctrl+C)
    ↓
Codex Core
    ↓
ClaudeHooksEngine::run_stop(StopRequest)
    ↓
StopCommandInput (JSON)
    ↓
External Hook Commands (stdin)
    ↓
StopCommandOutput (JSON Response)
    ↓
StopOutcome (Flow Decision)
```

### 相关 Schema
- `stop.command.output.schema.json`: 对应的输出 Schema（支持 block 决策）
- `user-prompt-submit.command.input.schema.json`: 类似的 Turn-scoped 输入

## 风险、边界与改进建议

### 当前风险

1. **turn_id 强制要求**:
   - 作为必填字段，但某些旧版本钩子可能不期望此字段
   - 风险: 向后兼容性问题
   - 缓解: 这是 Codex 扩展，Claude 原始协议无此字段

2. **stop_hook_active 语义不清**:
   - 字段名可能误导，实际含义是"当前是否在停止钩子处理中"
   - 建议: 更名为 `in_stop_hook_context` 或 `is_stop_hook_invocation`

3. **last_assistant_message 可能很大**:
   - 无长度限制，可能包含完整助手回复
   - 风险: 大消息导致 JSON 序列化/传输开销

### 边界情况

1. **快速连续停止**: 用户快速多次触发停止，可能导致并发执行
2. **空 last_assistant_message**: 助手尚未回复时停止，字段为 null
3. **长时间运行的 Stop 钩子**: 默认 600 秒超时，但可能阻塞用户界面

### 改进建议

1. **字段文档化**:
   ```json
   "stop_hook_active": {
     "type": "boolean",
     "description": "Indicates whether the current execution context is already inside a Stop hook handler. Used to prevent recursive hook invocations."
   }
   ```

2. **添加消息长度限制**:
   ```rust
   const MAX_LAST_MESSAGE_LENGTH: usize = 10000;
   last_assistant_message: NullableString::from_string(
       request.last_assistant_message.map(|m| {
           if m.len() > MAX_LAST_MESSAGE_LENGTH {
               format!("{}... [truncated]", &m[..MAX_LAST_MESSAGE_LENGTH])
           } else {
               m
           }
       })
   ),
   ```

3. **添加停止原因字段**:
   ```json
   "stop_reason": {
     "enum": ["user_interrupt", "timeout", "error", "completion"],
     "description": "The reason why the stop event was triggered"
   }
   ```

4. **并发控制**:
   ```rust
   // 在 ClaudeHooksEngine 中添加停止钩子执行锁
   stop_hook_executing: Arc<AtomicBool>,
   ```

5. **Schema 版本标识**:
   ```json
   {
     "$schema": "http://json-schema.org/draft-07/schema#",
     "$id": "https://codex.openai.com/schemas/hooks/stop.input.v1.json",
     "version": "1.0.0"
   }
   ```

### 测试覆盖分析

| 测试场景 | 覆盖状态 | 说明 |
|----------|----------|------|
| 基本输入序列化 | ✅ | schema.rs 集成测试 |
| turn_id 存在性 | ✅ | turn_scoped_hook_inputs_include_codex_turn_id_extension |
| 空 last_assistant_message | ⚠️ | 依赖 NullableString 测试 |
| 大消息处理 | ❌ | 未覆盖 |
| 并发停止 | ❌ | 未覆盖 |

建议添加针对大消息和并发场景的测试用例。
