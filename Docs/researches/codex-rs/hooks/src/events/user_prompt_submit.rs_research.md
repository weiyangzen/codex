# user_prompt_submit.rs 研究文档

## 场景与职责

`user_prompt_submit.rs` 实现 Codex Hooks 协议中的 **UserPromptSubmit** 事件处理逻辑。该事件在用户提交提示（prompt）后、发送给模型前触发，用于：

1. **输入审查** - 检查用户输入是否符合安全策略
2. **输入增强** - 通过 `additionalContext` 为模型提供额外上下文
3. **流程控制** - 决定是否阻止该提示的处理（block）
4. **实时反馈** - 向用户显示警告或错误信息

作为 Turn 级别的事件（与 Session 级别的 `SessionStart` 相对），它在每次用户交互时都可能触发。

## 功能点目的

### 1. 请求/响应结构

**`UserPromptSubmitRequest`** - 输入参数：
```rust
pub struct UserPromptSubmitRequest {
    pub session_id: ThreadId,
    pub turn_id: String,              // Turn 级别事件
    pub cwd: PathBuf,
    pub transcript_path: Option<PathBuf>,
    pub model: String,
    pub permission_mode: String,
    pub prompt: String,               // 用户提交的提示内容
}
```

**`UserPromptSubmitOutcome`** - 处理结果：
```rust
pub struct UserPromptSubmitOutcome {
    pub hook_events: Vec<HookCompletedEvent>,
    pub should_stop: bool,            // 是否阻止处理（block）
    pub stop_reason: Option<String>,  // 阻止原因
    pub additional_contexts: Vec<String>, // 传递给模型的上下文
}
```

### 2. 与 Stop 事件的对比

| 特性 | UserPromptSubmit | Stop |
|------|------------------|------|
| 触发时机 | 用户提交提示后 | 助手响应生成后 |
| 处理对象 | 用户输入 | 助手输出 |
| Exit Code 2 | ✅ 支持 | ✅ 支持 |
| 纯文本输出 | ✅ 支持（作为 additionalContext）| ❌ 不支持 |
| Block 决策 | ✅ 是 | ✅ 是 |
| Stop 决策 | ✅ 是（continue: false）| ✅ 是（continue: false）|
| 结果聚合 | 简单（3 字段）| 复杂（5 字段）|
| 特有字段 | `prompt` | `stop_hook_active`, `last_assistant_message` |

### 3. 输出解析策略

`parse_completed` 实现与 `SessionStart` 类似的解析策略，但增加了 Block 决策支持：

| 场景 | 处理方式 | 状态 |
|------|----------|------|
| exit_code = 0, 空输出 | 无操作 | Completed |
| exit_code = 0, 有效 JSON | 解析结构化输出 | 根据 `continue`/`decision` |
| exit_code = 0, 无效 JSON（以 `{`/`[` 开头）| JSON 解析错误 | Failed |
| exit_code = 0, 纯文本 | 作为 additionalContext | Completed |
| exit_code = 2 | 从 stderr 读取 block reason | Blocked |
| exit_code ≠ 0,2 | 记录退出码 | Failed |

### 4. 结构化输出支持

支持 Claude Hooks 协议的标准输出格式：

```json
{
  "continue": true,
  "stopReason": null,
  "suppressOutput": false,
  "systemMessage": null,
  "decision": "block",
  "reason": "此操作需要确认",
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "补充上下文信息"
  }
}
```

**关键字段**：
- `decision: "block"` - 阻止该提示的处理
- `reason` - 阻止原因（必须非空）
- `hookSpecificOutput.additionalContext` - 传递给模型的上下文

### 5. 纯文本向后兼容

与 `Stop` 不同，`UserPromptSubmit` 支持纯文本输出：

```rust
// 纯文本作为 additionalContext
let additional_context = trimmed_stdout.to_string();
common::append_additional_context(
    &mut entries,
    &mut additional_contexts_for_model,
    additional_context,
);
```

这允许简单的 shell 脚本无需处理 JSON 即可添加上下文。

## 具体技术实现

### 关键数据结构

```rust
// 内部 handler 数据聚合
struct UserPromptSubmitHandlerData {
    should_stop: bool,                // 对应 block 决策
    stop_reason: Option<String>,
    additional_contexts_for_model: Vec<String>,
}
```

注意：`should_stop` 在此上下文中实际表示 "should_block"，因为 `UserPromptSubmit` 的 block 会阻止该 turn 的继续处理。

### 核心流程

```
run() 执行流程:
┌─────────────────────────────────────┐
│ 1. select_handlers()                │
│    - 按 HookEventName::UserPromptSubmit │
│    - 忽略 matcher（无 matcher 支持）│
└─────────────┬───────────────────────┘
              ▼
┌─────────────────────────────────────┐
│ 2. 序列化 UserPromptSubmitCommandInput │
│    - 包含 prompt 内容               │
└─────────────┬───────────────────────┘
              ▼
┌─────────────────────────────────────┐
│ 3. dispatcher::execute_handlers()   │
│    - 并行执行所有 handlers          │
└─────────────┬───────────────────────┘
              ▼
┌─────────────────────────────────────┐
│ 4. parse_completed() 解析每个结果   │
│    - exit_code = 0: JSON/纯文本     │
│    - exit_code = 2: stderr block    │
└─────────────┬───────────────────────┘
              ▼
┌─────────────────────────────────────┐
│ 5. 聚合结果                         │
│    - any(should_stop)               │
│    - find_map(stop_reason)          │
│    - flatten(additional_contexts)   │
└─────────────────────────────────────┘
```

### 输出解析状态机

```
parse_completed() 状态转换:

exit_code = 0
├── stdout 为空
│   └── status = Completed
├── stdout 是有效 JSON
│   ├── continue = false
│   │   └── status = Stopped, should_stop = true
│   ├── decision = block + valid reason
│   │   └── status = Blocked, should_stop = true
│   │   └── stop_reason = reason
│   ├── decision = block + empty reason
│   │   └── status = Failed
│   └── default
│       └── status = Completed
│       └── 收集 additional_context
├── stdout 是无效 JSON（以 { 或 [ 开头）
│   └── status = Failed
└── stdout 是纯文本
    └── status = Completed
    └── 文本作为 additional_context

exit_code = 2
├── stderr 非空
│   └── status = Blocked
│   └── should_stop = true
│   └── stop_reason = stderr 内容
└── stderr 为空/空白
    └── status = Failed

exit_code = other
└── status = Failed
```

### 输入 JSON Schema

```rust
UserPromptSubmitCommandInput {
    session_id: String,
    turn_id: String,                  // Turn 级别特有
    transcript_path: NullableString,
    cwd: String,
    hook_event_name: "UserPromptSubmit",
    model: String,
    permission_mode: String,
    prompt: String,                   // UserPromptSubmit 特有
}
```

## 关键代码路径与文件引用

### 内部依赖

| 依赖 | 路径 | 用途 |
|------|------|------|
| `common` | `events/common.rs` | `flatten_additional_contexts`, `trimmed_non_empty`, `append_additional_context`, `serialization_failure_hook_events` |
| `dispatcher` | `engine/dispatcher.rs` | handler 筛选、执行、摘要生成 |
| `output_parser` | `engine/output_parser.rs` | `parse_user_prompt_submit()` |
| `schema` | `schema.rs` | `UserPromptSubmitCommandInput`, `NullableString` |

### 外部协议类型

- `codex_protocol::protocol::HookEventName::UserPromptSubmit`
- `codex_protocol::protocol::HookRunStatus` - `Blocked` 状态
- `codex_protocol::protocol::HookOutputEntryKind::Feedback` - 用于 block 反馈

### 调用方

| 调用方 | 路径 | 调用方式 |
|--------|------|----------|
| `ClaudeHooksEngine` | `engine/mod.rs:108` | `preview_user_prompt_submit()` |
| `ClaudeHooksEngine` | `engine/mod.rs:116` | `run_user_prompt_submit()` |

## 依赖与外部交互

### 模块依赖图

```
user_prompt_submit.rs
├── common
│   ├── flatten_additional_contexts()
│   ├── trimmed_non_empty()
│   ├── append_additional_context()
│   └── serialization_failure_hook_events()
├── dispatcher
│   ├── select_handlers()
│   ├── execute_handlers()
│   ├── running_summary()
│   └── completed_summary()
├── output_parser
│   └── parse_user_prompt_submit()
│       ├── UserPromptSubmitCommandOutputWire
│       ├── UniversalOutput
│       └── BlockDecisionWire
└── schema
    ├── UserPromptSubmitCommandInput
    └── NullableString
```

### 与 output_parser 的交互

```rust
// output_parser.rs
pub(crate) fn parse_user_prompt_submit(stdout: &str) -> Option<UserPromptSubmitOutput> {
    let wire: UserPromptSubmitCommandOutputWire = parse_json(stdout)?;
    let should_block = matches!(wire.decision, Some(BlockDecisionWire::Block));
    let invalid_block_reason = if should_block && reason_is_empty {
        Some(invalid_block_message("UserPromptSubmit"))
    } else {
        None
    };
    let additional_context = wire
        .hook_specific_output
        .and_then(|output| output.additional_context);
    
    Some(UserPromptSubmitOutput {
        universal: UniversalOutput::from(wire.universal),
        should_block: should_block && invalid_block_reason.is_none(),
        reason: wire.reason,
        invalid_block_reason,
        additional_context,
    })
}
```

### 与 Protocol 的交互

```
输入: UserPromptSubmitCommandInput (JSON)
    ├── session_id
    ├── turn_id
    ├── cwd
    ├── model
    ├── permission_mode
    └── prompt: string           // 用户输入内容

输出: HookCompletedEvent
    ├── turn_id: Option<String>
    └── run: HookRunSummary
        ├── status: Running | Completed | Failed | Stopped | Blocked
        └── entries: Vec<HookOutputEntry>
            ├── Context: additional_context
            ├── Stop: stop_reason (when continue=false)
            ├── Feedback: block_reason (when decision=block)
            ├── Warning: system_message
            └── Error: error_message
```

## 风险、边界与改进建议

### 已知风险

1. **命名混淆**
   ```rust
   // UserPromptSubmitHandlerData 使用 should_stop 表示 block
   // 但实际上在 UserPromptSubmit 上下文中，block 就是阻止该 turn
   struct UserPromptSubmitHandlerData {
       should_stop: bool,  // 实际是 should_block
       ...
   }
   ```
   建议：考虑重命名为 `should_block` 以提高清晰度。

2. **纯文本与 JSON 的边界模糊**
   - 以 `{` 或 `[` 开头但解析失败的输出被视为错误
   - 这可能误判某些有效的纯文本（如 "{not json"）
   - 与 `SessionStart` 相同的问题

3. **Block 原因验证**
   ```rust
   // 与 Stop 相同的验证逻辑
   if should_block && reason.trim().is_empty() {
       invalid_block_reason = Some(...)
   }
   ```
   配置错误的 hook 会静默失败（标记为 Failed 而非 Blocked）。

### 边界情况

1. **Continue=false 与 Block 的交互**
   ```rust
   // 测试用例验证：continue=false 优先
   // 即使同时有 decision:block，也走 stop 路径
   ```

2. **Exit Code 2 处理**
   ```rust
   // stderr 内容直接作为 stop_reason
   // 不需要 JSON 解析
   ```

3. **多 handler 上下文收集**
   ```rust
   // 所有 handler 的 additional_context 都被收集
   // 即使某个 handler 触发 block
   ```

4. **空 prompt 处理**
   - 当前实现未对空 prompt 做特殊处理
   - 由 hook 自行决定是否阻止

### 改进建议

1. **命名澄清**
   ```rust
   // 建议修改
   struct UserPromptSubmitHandlerData {
       should_block: bool,  // 替代 should_stop
       block_reason: Option<String>,  // 替代 stop_reason
       ...
   }
   ```
   注意：这需要同步修改 `UserPromptSubmitOutcome` 的字段名。

2. **增强错误报告**
   - 区分 "无效 JSON" 和 "缺少 block reason"
   - 添加 hook 配置建议

3. **测试覆盖**
   已覆盖：
   - Continue=false 保留上下文
   - Block 决策与 reason
   - Block 缺少 reason 的验证
   - Exit code 2 处理
   
   缺失：
   - 纯文本作为 additional_context
   - 多 handler 聚合场景
   - 超时处理
   - 序列化失败

4. **性能优化**
   - `flatten_additional_contexts` 创建中间 Vec
   - 可考虑使用迭代器链

5. **安全考虑**
   - `prompt` 字段直接传递给 hook 的 stdin
   - 考虑对特殊字符进行转义或验证
   - 防止命令注入（虽然通过 stdin 传递相对安全）

6. **文档完善**
   - 说明 `should_stop` 在 `UserPromptSubmitOutcome` 中实际表示 block
   - 添加关于纯文本输出的示例
   - 解释 `additional_contexts` 如何传递给模型

7. **与 Claude 协议的兼容性**
   - 确认 Codex 扩展的 `turn_id` 字段不影响 Claude 兼容性
   - 文档化 Codex 特有的扩展
