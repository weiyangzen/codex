# stop.rs 研究文档

## 场景与职责

`stop.rs` 实现 Codex Hooks 协议中的 **Stop** 事件处理逻辑。该事件在助手响应生成完成后触发，用于：

1. **内容审查** - 检查生成的响应是否符合策略
2. **流程控制** - 决定是否继续对话或暂停等待用户输入
3. **阻塞反馈** - 当需要用户确认时提供继续提示

与 `SessionStart` 和 `UserPromptSubmit` 不同，`Stop` 事件支持两种阻塞机制：
- **Stop**: 完全停止会话（`continue: false`）
- **Block**: 暂停并等待用户反馈（`decision: block`）

## 功能点目的

### 1. 请求/响应结构

**`StopRequest`** - 输入参数：
```rust
pub struct StopRequest {
    pub session_id: ThreadId,
    pub turn_id: String,              // Turn 级别事件，需要 turn_id
    pub cwd: PathBuf,
    pub transcript_path: Option<PathBuf>,
    pub model: String,
    pub permission_mode: String,
    pub stop_hook_active: bool,       // 标识 Stop hook 是否激活
    pub last_assistant_message: Option<String>, // 助手最后一条消息
}
```

**`StopOutcome`** - 处理结果：
```rust
pub struct StopOutcome {
    pub hook_events: Vec<HookCompletedEvent>,
    pub should_stop: bool,            // 是否完全停止
    pub stop_reason: Option<String>,
    pub should_block: bool,           // 是否阻塞等待反馈
    pub block_reason: Option<String>,
    pub continuation_prompt: Option<String>, // 给用户显示的继续提示
}
```

### 2. 双模式阻塞机制

#### 模式 A: JSON 结构化输出（Exit Code 0）
```json
{
  "continue": false,
  "stopReason": "pause",
  "decision": "block",
  "reason": "请确认此操作"
}
```

**优先级规则**：
- `continue: false` > `decision: block`
- 如果同时存在，`should_stop=true`, `should_block=false`

#### 模式 B: 简化输出（Exit Code 2）
- 退出码为 2 时，从 stderr 读取阻塞原因
- 无需 JSON 解析，适合简单脚本

```rust
// exit_code = 2 的处理逻辑
if let Some(reason) = common::trimmed_non_empty(&run_result.stderr) {
    status = HookRunStatus::Blocked;
    should_block = true;
    block_reason = Some(reason.clone());
    continuation_prompt = Some(reason.clone());
}
```

### 3. 结果聚合策略

`aggregate_results` 函数实现多 handler 结果的智能合并：

| 字段 | 聚合规则 | 说明 |
|------|----------|------|
| `should_stop` | `any(should_stop)` | 任一 handler 要求停止即停止 |
| `stop_reason` | `find_map(stop_reason)` | 取第一个停止原因 |
| `should_block` | `!should_stop && any(should_block)` | 未停止时才阻塞 |
| `block_reason` | `join_text_chunks(reasons)` | 合并所有阻塞原因 |
| `continuation_prompt` | `join_text_chunks(prompts)` | 合并所有提示 |

**关键设计**：`should_stop` 优先于 `should_block`，避免同时处于两种状态。

### 4. 与 Claude 协议的兼容性

`Stop` 事件是 Claude Hooks 的扩展，用于实现：
- **Claude Code 的 `--dangerous` 模式检测**
- **自动确认高风险操作**
- **工作流暂停和恢复**

## 具体技术实现

### 关键数据结构

```rust
// 内部 handler 数据聚合
#[derive(Debug, Default, PartialEq, Eq)]
struct StopHandlerData {
    should_stop: bool,
    stop_reason: Option<String>,
    should_block: bool,
    block_reason: Option<String>,
    continuation_prompt: Option<String>,
}
```

### 核心流程

```
run() 执行流程:
┌─────────────────────────────────────┐
│ 1. select_handlers()                │
│    - 按 HookEventName::Stop 筛选    │
│    - 忽略 matcher（Stop 无 matcher）│
└─────────────┬───────────────────────┘
              ▼
┌─────────────────────────────────────┐
│ 2. 序列化 StopCommandInput          │
│    - 包含 stop_hook_active 标志     │
│    - 包含 last_assistant_message    │
└─────────────┬───────────────────────┘
              ▼
┌─────────────────────────────────────┐
│ 3. dispatcher::execute_handlers()   │
│    - 并行执行所有 Stop handlers     │
└─────────────┬───────────────────────┘
              ▼
┌─────────────────────────────────────┐
│ 4. parse_completed() 解析每个结果   │
│    - exit_code = 0: JSON 解析       │
│    - exit_code = 2: stderr 读取     │
│    - 其他: 失败                     │
└─────────────┬───────────────────────┘
              ▼
┌─────────────────────────────────────┐
│ 5. aggregate_results() 聚合         │
│    - 优先 should_stop               │
│    - 合并 block reasons             │
└─────────────┬───────────────────────┘
              ▼
┌─────────────────────────────────────┐
│ 6. 返回 StopOutcome                 │
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
│   │   └── status = Blocked, should_block = true
│   ├── decision = block + empty reason
│   │   └── status = Failed (invalid block)
│   └── default
│       └── status = Completed
├── stdout 是无效 JSON（以 { 或 [ 开头）
│   └── status = Failed
└── stdout 是纯文本
    └── status = Failed (Stop 不支持纯文本上下文)

exit_code = 2
├── stderr 非空
│   └── status = Blocked, should_block = true
└── stderr 为空/空白
    └── status = Failed

exit_code = other
└── status = Failed
```

### 输入 JSON Schema

```rust
StopCommandInput {
    session_id: String,
    turn_id: String,                  // Turn 级别事件特有
    transcript_path: NullableString,
    cwd: String,
    hook_event_name: "Stop",
    model: String,
    permission_mode: String,
    stop_hook_active: bool,           // Stop 特有字段
    last_assistant_message: NullableString,  // Stop 特有字段
}
```

## 关键代码路径与文件引用

### 内部依赖

| 依赖 | 路径 | 用途 |
|------|------|------|
| `common` | `events/common.rs` | `join_text_chunks`, `trimmed_non_empty`, `serialization_failure_hook_events` |
| `dispatcher` | `engine/dispatcher.rs` | handler 筛选、执行、摘要生成 |
| `output_parser` | `engine/output_parser.rs` | `parse_stop()` 解析 JSON 输出 |
| `schema` | `schema.rs` | `StopCommandInput`, `NullableString` |

### 外部协议类型

- `codex_protocol::protocol::HookEventName::Stop`
- `codex_protocol::protocol::HookRunStatus` - 包含 `Blocked` 状态（Stop 特有）
- `codex_protocol::protocol::HookOutputEntryKind::Feedback` - 用于 block 反馈

### 调用方

| 调用方 | 路径 | 调用方式 |
|--------|------|----------|
| `ClaudeHooksEngine` | `engine/mod.rs:120` | `preview_stop()` |
| `ClaudeHooksEngine` | `engine/mod.rs:124` | `run_stop()` |

## 依赖与外部交互

### 模块依赖图

```
stop.rs
├── common
│   ├── join_text_chunks()          // 合并多个 block reason
│   ├── trimmed_non_empty()         // 验证 reason 非空
│   └── serialization_failure_hook_events()
├── dispatcher
│   ├── select_handlers()           // 无 matcher 筛选
│   ├── execute_handlers()
│   ├── running_summary()
│   └── completed_summary()
├── output_parser
│   └── parse_stop()                // 解析 StopCommandOutputWire
└── schema
    ├── StopCommandInput
    └── NullableString
```

### 与 UserPromptSubmit 的对比

| 特性 | Stop | UserPromptSubmit |
|------|------|------------------|
| Exit Code 2 支持 | ✅ 是 | ✅ 是 |
| 纯文本输出 | ❌ 不支持 | ✅ 支持（作为 additionalContext）|
| Block 决策 | ✅ 是 | ✅ 是 |
| Stop 决策 | ✅ 是（continue: false）| ✅ 是（continue: false）|
| 结果聚合 | 复杂（5 个字段）| 简单（3 个字段）|
| Matcher 支持 | ❌ 无 | ❌ 无 |
| 特有字段 | `stop_hook_active`, `last_assistant_message` | `prompt` |

### 与 Protocol 的交互

```
输入: StopCommandInput (JSON)
    ├── session_id
    ├── turn_id
    ├── cwd
    ├── model
    ├── permission_mode
    ├── stop_hook_active: bool
    └── last_assistant_message: string|null

输出: HookCompletedEvent
    ├── turn_id: Option<String>
    └── run: HookRunSummary
        ├── status: Running | Completed | Failed | Stopped | Blocked
        │   └── Stop 特有 Blocked 状态
        └── entries: Vec<HookOutputEntry>
            ├── Error: 执行错误
            ├── Stop: 停止原因
            └── Feedback: 阻塞反馈信息
```

## 风险、边界与改进建议

### 已知风险

1. **Block 原因验证严格**
   ```rust
   // 必须提供非空 reason，否则标记为 Failed
   if should_block && reason.trim().is_empty() {
       invalid_block_reason = Some(...)
   }
   ```
   这可能导致配置错误的 hook 静默失败。

2. **Exit Code 2 的 stderr 必须非空**
   ```rust
   // 如果 stderr 为空或仅空白，标记为 Failed
   if let Some(reason) = common::trimmed_non_empty(&run_result.stderr)
   ```
   脚本开发者可能忘记写入 stderr。

3. **纯文本输出不被支持**
   - 与 `SessionStart` 和 `UserPromptSubmit` 不同，`Stop` 将纯文本视为错误
   - 这可能破坏期望纯文本行为的 Claude Hooks 兼容脚本

### 边界情况

1. **多 handler 阻塞原因合并**
   ```rust
   // 使用 "\n\n" 连接多个原因
   block_reason: Some("first\n\nsecond".to_string())
   ```
   测试用例验证了声明顺序保留。

2. **Stop 优先于 Block**
   ```rust
   let should_block = !should_stop && results.iter().any(|r| r.should_block);
   ```
   即使多个 handler 要求 block，只要一个要求 stop，最终状态是 stop。

3. **空 handlers 列表**
   ```rust
   if matched.is_empty() {
       return StopOutcome { /* 全 false/None */ };
   }
   ```

### 改进建议

1. **增强错误诊断**
   - 区分 "block 无 reason" 和 "exit code 2 无 stderr" 的错误信息
   - 添加建议修复提示（如 "请确保 stderr 包含阻塞原因"）

2. **配置验证**
   - 在配置加载阶段验证 Stop handler 是否可能产生有效输出
   - 警告用户关于纯文本输出不被支持

3. **测试覆盖**
   已覆盖：
   - Block 决策与 reason
   - Continue=false 覆盖 Block
   - Exit code 2 处理
   - 多 handler 聚合
   
   缺失：
   - 超时场景
   - 命令执行错误（进程启动失败）
   - 序列化失败场景

4. **文档完善**
   - 明确说明 `Stop` 与 `UserPromptSubmit` 在纯文本处理上的差异
   - 解释 `stop_hook_active` 字段的用途（似乎用于防止递归）
   - 添加关于多 handler 结果合并的示例

5. **性能考虑**
   - `aggregate_results` 创建多个中间 Vec
   - 可考虑使用迭代器链减少分配

6. **API 一致性**
   - `Stop` 使用 `invalid_block_reason` 字段（来自 output_parser）
   - 考虑统一 `UserPromptSubmit` 和 `Stop` 的 block 验证逻辑
