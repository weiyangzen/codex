# DIR Research: codex-rs/hooks/src/events

## 概述

`codex-rs/hooks/src/events` 目录实现了 Codex 的 Hook 事件处理系统，负责在会话生命周期关键节点（SessionStart、UserPromptSubmit、Stop）触发和执行外部命令钩子。该模块是 Codex 扩展机制的核心，允许用户通过配置自定义脚本在特定事件点介入会话流程。

---

## 场景与职责

### 核心场景

1. **会话启动钩子 (SessionStart)**
   - 在会话启动或恢复时触发
   - 支持基于来源的匹配过滤（startup/resume）
   - 用于注入初始上下文、环境检查、前置条件验证

2. **用户提示提交钩子 (UserPromptSubmit)**
   - 在用户输入提交后、AI 处理前触发
   - 支持拦截和阻断用户输入（block 决策）
   - 用于输入审查、策略检查、内容过滤

3. **停止钩子 (Stop)**
   - 在 AI 响应生成后触发
   - 支持阻断决策和继续提示（continuation prompt）
   - 用于输出审查、后处理、质量检查

### 职责边界

| 职责 | 说明 |
|------|------|
| 事件分发 | 根据事件类型选择匹配的处理器 |
| 命令执行 | 通过 shell 执行外部钩子命令 |
| 输出解析 | 解析钩子 stdout/stderr 输出 |
| 状态管理 | 跟踪钩子执行状态（Running/Completed/Failed/Blocked/Stopped） |
| 上下文注入 | 将钩子输出作为开发者消息注入会话 |

---

## 功能点目的

### 1. SessionStart 事件 (`session_start.rs`)

**目的**: 在会话生命周期开始时执行初始化逻辑。

**关键特性**:
- 支持 `startup` 和 `resume` 两种来源的区分匹配
- 通过正则表达式 `matcher` 过滤来源
- 输出支持两种格式：
  - **纯文本**: 直接作为 additional context 注入
  - **JSON**: 结构化输出，支持 `systemMessage`、`additionalContext`、`continue`、`stopReason`

**决策逻辑**:
- `continue: false` → 停止会话，记录 `stopReason`
- `exit_code != 0` → 标记为 Failed
- 无效 JSON 且以 `{` 或 `[` 开头 → 标记为 Failed（避免将错误 JSON 当作文本）

### 2. UserPromptSubmit 事件 (`user_prompt_submit.rs`)

**目的**: 审查和拦截用户输入。

**关键特性**:
- 支持 `decision: "block"` 决策阻断输入
- `exit_code = 2` 时从 stderr 读取阻断原因
- 支持 `additionalContext` 注入额外上下文

**决策优先级**:
1. `continue: false` > `decision: block`（停止优先于阻断）
2. 无效 block 决策（无 reason）→ Failed
3. `exit_code = 2` + stderr → Blocked

### 3. Stop 事件 (`stop.rs`)

**目的**: 审查 AI 输出并决定是否阻断。

**关键特性**:
- 与 UserPromptSubmit 类似的 block 决策机制
- 支持 `continuationPrompt` 用于提示用户修改输入
- 多钩子结果聚合：多个 block 原因用 `\n\n` 连接

**聚合逻辑**:
```rust
should_stop = any(result.should_stop)
should_block = !should_stop && any(result.should_block)  // stop 优先
block_reason = join_text_chunks(all block reasons)
```

### 4. 通用工具函数 (`common.rs`)

**功能**:
- `join_text_chunks`: 用双换行连接文本块
- `trimmed_non_empty`: 去除空白后检查非空
- `append_additional_context`: 添加上下文条目
- `flatten_additional_contexts`: 扁平化多钩子上下文
- `serialization_failure_hook_events`: 序列化失败时生成错误事件

---

## 具体技术实现

### 关键数据结构

#### SessionStartRequest
```rust
pub struct SessionStartRequest {
    pub session_id: ThreadId,
    pub cwd: PathBuf,
    pub transcript_path: Option<PathBuf>,
    pub model: String,
    pub permission_mode: String,
    pub source: SessionStartSource,  // Startup | Resume
}
```

#### UserPromptSubmitRequest
```rust
pub struct UserPromptSubmitRequest {
    pub session_id: ThreadId,
    pub turn_id: String,
    pub cwd: PathBuf,
    pub transcript_path: Option<PathBuf>,
    pub model: String,
    pub permission_mode: String,
    pub prompt: String,  // 用户输入内容
}
```

#### StopRequest
```rust
pub struct StopRequest {
    pub session_id: ThreadId,
    pub turn_id: String,
    pub cwd: PathBuf,
    pub transcript_path: Option<PathBuf>,
    pub model: String,
    pub permission_mode: String,
    pub stop_hook_active: bool,
    pub last_assistant_message: Option<String>,
}
```

#### 输出结构 (schema.rs)

**通用输出** (所有事件共享):
```rust
pub struct HookUniversalOutputWire {
    pub r#continue: bool,      // 默认 true
    pub stop_reason: Option<String>,
    pub suppress_output: bool,
    pub system_message: Option<String>,
}
```

**SessionStart 特有**:
```rust
pub struct SessionStartHookSpecificOutputWire {
    pub hook_event_name: HookEventNameWire,
    pub additional_context: Option<String>,
}
```

**UserPromptSubmit/Stop 特有**:
```rust
pub struct UserPromptSubmitCommandOutputWire {
    pub universal: HookUniversalOutputWire,
    pub decision: Option<BlockDecisionWire>,  // "block"
    pub reason: Option<String>,
    pub hook_specific_output: Option<UserPromptSubmitHookSpecificOutputWire>,
}
```

### 关键流程

#### 1. 事件处理流程

```
preview() -> Vec<HookRunSummary>
   ↓
run() -> Outcome
   ↓
   ├─> select_handlers()  [dispatcher.rs]  // 按事件类型和 matcher 过滤
   ├─> execute_handlers() [dispatcher.rs]  // 并发执行命令
   │       └─> run_command() [command_runner.rs]
   │               ├─> 构建 shell 命令
   │               ├─> 写入 input_json 到 stdin
   │               ├─> 等待执行（带超时）
   │               └─> 返回 CommandRunResult
   └─> parse_completed()  // 解析输出，生成 HookCompletedEvent
```

#### 2. 输出解析流程

```
parse_completed(run_result)
   ↓
   ├─> run_result.error? → Failed
   ├─> exit_code match
   │       ├─> Some(0) → 解析 stdout
   │       │       ├─> 空 → Completed
   │       │       ├─> 有效 JSON → 按事件类型解析
   │       │       ├─> 无效 JSON 但以 {/[ 开头 → Failed
   │       │       └─> 其他 → 作为纯文本 context
   │       ├─> Some(2) → 从 stderr 读取阻断原因 (Blocked)
   │       └─> 其他 → Failed
   └─> 生成 HookCompletedEvent
```

#### 3. SessionStart 特有解析逻辑

```rust
if let Some(parsed) = output_parser::parse_session_start(&stdout) {
    // 处理 system_message → Warning 条目
    // 处理 additional_context → Context 条目
    // 处理 continue: false → Stopped 状态
}
```

### 协议与命令

#### 输入协议 (JSON via stdin)

**SessionStartCommandInput**:
```json
{
  "sessionId": "uuid",
  "transcriptPath": "/path/to/transcript.jsonl" | null,
  "cwd": "/current/working/dir",
  "hookEventName": "SessionStart",
  "model": "gpt-4o",
  "permissionMode": "default",
  "source": "startup" | "resume"
}
```

**UserPromptSubmitCommandInput**:
```json
{
  "sessionId": "uuid",
  "turnId": "turn-uuid",
  "transcriptPath": "...",
  "cwd": "...",
  "hookEventName": "UserPromptSubmit",
  "model": "...",
  "permissionMode": "...",
  "prompt": "用户输入内容"
}
```

**StopCommandInput**:
```json
{
  "sessionId": "uuid",
  "turnId": "turn-uuid",
  "transcriptPath": "...",
  "cwd": "...",
  "hookEventName": "Stop",
  "model": "...",
  "permissionMode": "...",
  "stopHookActive": true,
  "lastAssistantMessage": "AI 最后回复"
}
```

#### 输出协议

**成功响应**:
```json
{
  "continue": true,
  "systemMessage": "可选系统消息",
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "注入模型的上下文"
  }
}
```

**阻断响应**:
```json
{
  "continue": true,
  "decision": "block",
  "reason": "阻断原因说明"
}
```

**停止响应**:
```json
{
  "continue": false,
  "stopReason": "停止原因"
}
```

---

## 关键代码路径与文件引用

### 核心文件

| 文件 | 职责 | 关键函数/结构 |
|------|------|--------------|
| `events/mod.rs` | 模块入口 | 导出子模块 |
| `events/common.rs` | 通用工具 | `join_text_chunks`, `append_additional_context`, `serialization_failure_hook_events` |
| `events/session_start.rs` | 会话启动事件 | `SessionStartRequest`, `SessionStartOutcome`, `preview()`, `run()`, `parse_completed()` |
| `events/stop.rs` | 停止事件 | `StopRequest`, `StopOutcome`, `aggregate_results()` |
| `events/user_prompt_submit.rs` | 用户提示提交事件 | `UserPromptSubmitRequest`, `UserPromptSubmitOutcome` |

### 依赖文件

| 文件 | 职责 | 关键导出 |
|------|------|----------|
| `engine/mod.rs` | 引擎入口 | `ClaudeHooksEngine`, `ConfiguredHandler`, `CommandShell` |
| `engine/dispatcher.rs` | 处理器调度 | `select_handlers()`, `execute_handlers()`, `running_summary()`, `completed_summary()` |
| `engine/command_runner.rs` | 命令执行 | `run_command()`, `CommandRunResult` |
| `engine/output_parser.rs` | 输出解析 | `parse_session_start()`, `parse_user_prompt_submit()`, `parse_stop()` |
| `schema.rs` | 数据结构定义 | `SessionStartCommandInput`, `UserPromptSubmitCommandInput`, `StopCommandInput`, 输出结构 |
| `registry.rs` | 注册表 | `Hooks`, `HooksConfig` |
| `lib.rs` | 库入口 | 公开 API 导出 |

### 调用方文件

| 文件 | 使用方式 |
|------|----------|
| `core/src/hook_runtime.rs` | 调用 `run_session_start()`, `run_user_prompt_submit()`，处理 `SessionStartOutcome`, `UserPromptSubmitOutcome` |
| `core/src/codex.rs` | 通过 `Hooks` 注册表间接调用 |
| `hooks/src/engine/mod.rs` | 委托调用各事件处理函数 |
| `hooks/src/registry.rs` | 暴露预览和执行接口 |

---

## 依赖与外部交互

### 内部依赖

```
events/
  ├─> engine/
  │     ├─> dispatcher (处理器选择、执行、结果汇总)
  │     ├─> command_runner (shell 命令执行)
  │     └─> output_parser (stdout 解析)
  ├─> schema (输入/输出数据结构)
  └─> registry (通过 engine 间接依赖)
```

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `codex_protocol` | `HookEventName`, `HookCompletedEvent`, `HookRunSummary`, `HookOutputEntry`, `HookRunStatus`, `ThreadId` |
| `codex_config` | 配置层栈 (`ConfigLayerStack`) |
| `tokio` | 异步运行时、进程管理、超时控制 |
| `serde`/`serde_json` | JSON 序列化/反序列化 |
| `chrono` | 时间戳处理 |
| `futures` | 并发执行 (`join_all`) |
| `regex` | SessionStart matcher 正则匹配 |

### 协议类型定义 (codex_protocol)

```rust
// protocol.rs
pub enum HookEventName {
    SessionStart,
    UserPromptSubmit,
    Stop,
}

pub enum HookRunStatus {
    Running,
    Completed,
    Failed,
    Blocked,
    Stopped,
}

pub enum HookOutputEntryKind {
    Warning,
    Stop,
    Feedback,
    Context,
    Error,
}

pub struct HookOutputEntry {
    pub kind: HookOutputEntryKind,
    pub text: String,
}

pub struct HookRunSummary {
    pub id: String,
    pub event_name: HookEventName,
    pub handler_type: HookHandlerType,
    pub execution_mode: HookExecutionMode,
    pub scope: HookScope,  // Thread | Turn
    pub source_path: PathBuf,
    pub display_order: i64,
    pub status: HookRunStatus,
    pub status_message: Option<String>,
    pub started_at: i64,
    pub completed_at: Option<i64>,
    pub duration_ms: Option<i64>,
    pub entries: Vec<HookOutputEntry>,
}
```

### 作用域定义

| 事件 | 作用域 | 说明 |
|------|--------|------|
| SessionStart | `Thread` | 会话级别，不绑定特定 turn |
| UserPromptSubmit | `Turn` | 回合级别，绑定 turn_id |
| Stop | `Turn` | 回合级别，绑定 turn_id |

---

## 风险、边界与改进建议

### 已知风险

1. **命令注入风险**
   - 钩子命令通过 shell 执行，若配置中包含用户可控输入可能导致注入
   - **缓解**: 命令字符串来自配置文件，非直接用户输入

2. **超时处理**
   - 默认超时 600 秒，长时间运行的钩子会阻塞会话
   - **风险**: 恶意或错误配置可能导致 DoS

3. **JSON 解析歧义**
   - 纯文本输出和 JSON 输出的区分依赖启发式（是否以 `{` 或 `[` 开头）
   - **边界**: 以 `{` 开头的纯文本会被误判为无效 JSON 而失败

4. **并发执行顺序**
   - 多钩子并发执行，结果按声明顺序聚合
   - **风险**: 聚合逻辑（如 block reason 连接）可能产生非预期结果

### 边界条件

| 场景 | 行为 |
|------|------|
| 无匹配处理器 | 返回空结果，继续执行 |
| 序列化失败 | 生成 Failed 状态事件，返回空 outcome |
| 命令执行错误（spawn 失败） | Failed 状态，error 条目包含错误信息 |
| 超时 | Failed 状态，error 条目包含超时信息 |
| exit_code = 2 (Stop/UserPromptSubmit) | 从 stderr 读取阻断原因，Blocked 状态 |
| exit_code = 0 + 空 stdout | Completed 状态，无条目 |
| block 决策无 reason | Failed 状态，拒绝阻断 |
| continue=false + block 同时存在 | Stopped 优先，忽略 block |

### 改进建议

1. **增强错误上下文**
   - 当前错误信息较简略，建议包含处理器 ID、命令片段、执行时间等
   - 便于调试复杂钩子链

2. **支持异步钩子**
   - 当前仅支持同步执行 (`HookExecutionMode::Sync`)
   - 未来可考虑支持异步回调模式

3. **钩子链依赖**
   - 当前钩子间无依赖关系，全部并发
   - 可考虑支持 `depends_on` 声明，实现有序执行

4. **输出大小限制**
   - 当前无 stdout/stderr 大小限制
   - 建议添加最大输出限制，防止内存溢出

5. **Metrics 与可观测性**
   - 当前仅记录基本时间戳
   - 建议添加钩子执行 histogram、失败率等指标

6. **Schema 版本控制**
   - 输入/输出 schema 目前无版本标识
   - 建议添加 `schemaVersion` 字段便于演进

7. **测试覆盖**
   - 当前单元测试覆盖主要路径
   - 建议添加集成测试验证完整钩子链行为

---

## 附录：测试用例概览

### session_start.rs 测试
- `plain_stdout_becomes_model_context`: 纯文本输出作为上下文
- `continue_false_preserves_context_for_later_turns`: 停止时保留上下文
- `invalid_json_like_stdout_fails_instead_of_becoming_model_context`: 无效 JSON 失败而非作为文本

### stop.rs 测试
- `block_decision_with_reason_sets_continuation_prompt`: block 决策设置继续提示
- `block_decision_without_reason_is_invalid`: 无 reason 的 block 无效
- `continue_false_overrides_block_decision`: continue=false 优先于 block
- `exit_code_two_uses_stderr_feedback_only`: exit_code=2 使用 stderr
- `exit_code_two_without_stderr_does_not_block`: exit_code=2 但空 stderr 不阻断
- `aggregate_results_concatenates_blocking_reasons`: 多结果聚合

### user_prompt_submit.rs 测试
- `continue_false_preserves_context_for_later_turns`: 停止保留上下文
- `claude_block_decision_blocks_processing`: block 决策阻断处理
- `claude_block_decision_requires_reason`: block 需要 reason
- `exit_code_two_blocks_processing`: exit_code=2 阻断

---

*Generated: 2026-03-21*
*Research Scope: codex-rs/hooks/src/events/*
