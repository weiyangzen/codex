# session_start.rs 研究文档

## 场景与职责

`session_start.rs` 实现 Codex Hooks 协议中的 **SessionStart** 事件处理逻辑。该事件在以下场景触发：

1. **Startup** - 新会话启动时
2. **Resume** - 恢复已有会话时

作为 Claude Hooks 的兼容实现，该模块负责：
- 筛选匹配 `SessionStart` 事件的 handlers
- 执行命令式 hook（通过 shell 调用外部命令）
- 解析 hook 输出（支持 JSON 结构化输出和纯文本）
- 处理 `continue: false` 停止信号
- 收集 `additionalContext` 传递给模型

## 功能点目的

### 1. 事件源区分 (`SessionStartSource`)

```rust
pub enum SessionStartSource {
    Startup,  // 新会话启动
    Resume,   // 恢复会话
}
```

用于区分会话启动类型，并作为 matcher 的匹配输入。

### 2. 请求/响应结构

**`SessionStartRequest`** - 输入参数：
- `session_id`: 会话唯一标识
- `cwd`: 当前工作目录
- `transcript_path`: 对话记录文件路径（可选）
- `model`: 使用的模型名称
- `permission_mode`: 权限模式
- `source`: 启动来源（Startup/Resume）

**`SessionStartOutcome`** - 处理结果：
- `hook_events`: 所有 handler 的执行事件记录
- `should_stop`: 是否有 hook 要求停止
- `stop_reason`: 停止原因
- `additional_contexts`: 传递给模型的附加上下文

### 3. 双阶段处理模式

#### Preview 阶段（同步）
```rust
pub(crate) fn preview(handlers, request) -> Vec<HookRunSummary>
```
- 仅筛选匹配的 handlers
- 返回运行中状态摘要（用于 UI 展示）
- 不实际执行命令

#### Run 阶段（异步）
```rust
pub(crate) async fn run(handlers, shell, request, turn_id) -> SessionStartOutcome
```
- 序列化输入为 JSON
- 并行执行所有匹配的 handlers
- 解析输出并聚合结果

### 4. 输出解析策略

`parse_completed` 函数实现三级解析策略：

| 场景 | 处理方式 | 状态 |
|------|----------|------|
| 命令执行错误 | 记录错误信息 | Failed |
| exit_code = 0, 空输出 | 无操作 | Completed |
| exit_code = 0, 有效 JSON | 解析结构化输出 | 根据 `continue` 字段 |
| exit_code = 0, 无效 JSON | 记录 JSON 解析错误 | Failed |
| exit_code = 0, 纯文本 | 作为 additionalContext | Completed |
| exit_code ≠ 0 | 记录退出码 | Failed |

### 5. 结构化输出支持

支持 Claude Hooks 协议的标准输出格式：

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

同时保留向后兼容的纯文本输出支持。

## 具体技术实现

### 关键数据结构

```rust
// 内部 handler 数据聚合
struct SessionStartHandlerData {
    should_stop: bool,
    stop_reason: Option<String>,
    additional_contexts_for_model: Vec<String>,
}
```

### 核心流程

```
run() 执行流程:
┌─────────────────────────────────────┐
│ 1. select_handlers()                │
│    - 按 HookEventName::SessionStart │
│    - 按 source 匹配 matcher         │
└─────────────┬───────────────────────┘
              ▼
┌─────────────────────────────────────┐
│ 2. 序列化 SessionStartCommandInput  │
│    - session_id, cwd, model, etc.   │
└─────────────┬───────────────────────┘
              ▼
┌─────────────────────────────────────┐
│ 3. dispatcher::execute_handlers()   │
│    - 并行执行所有匹配的 handlers    │
│    - 通过 shell 调用外部命令        │
└─────────────┬───────────────────────┘
              ▼
┌─────────────────────────────────────┐
│ 4. parse_completed() 解析每个结果   │
│    - 处理 exit_code                 │
│    - 解析 stdout                    │
└─────────────┬───────────────────────┘
              ▼
┌─────────────────────────────────────┐
│ 5. 聚合结果                         │
│    - any(should_stop)               │
│    - find_map(stop_reason)          │
│    - flatten(additional_contexts)   │
└─────────────────────────────────────┘
```

### 输入 JSON Schema

```rust
SessionStartCommandInput {
    session_id: String,
    transcript_path: NullableString,  // 可能为 null
    cwd: String,
    hook_event_name: "SessionStart",  // 常量
    model: String,
    permission_mode: String,          // enum: default|acceptEdits|plan|dontAsk|bypassPermissions
    source: String,                   // enum: startup|resume|clear
}
```

## 关键代码路径与文件引用

### 内部依赖

| 依赖 | 路径 | 用途 |
|------|------|------|
| `common` | `events/common.rs` | 序列化失败处理、上下文展平 |
| `dispatcher` | `engine/dispatcher.rs` | handler 筛选、执行、摘要生成 |
| `output_parser` | `engine/output_parser.rs` | 解析 SessionStart 输出 |
| `schema` | `schema.rs` | `SessionStartCommandInput` 定义 |

### 外部协议类型

- `codex_protocol::ThreadId` - 会话 ID 类型
- `codex_protocol::protocol::HookEventName::SessionStart` - 事件类型标识
- `codex_protocol::protocol::HookRunStatus` - 运行状态枚举
- `codex_protocol::protocol::HookOutputEntryKind` - 输出条目类型

### 调用方

| 调用方 | 路径 | 调用方式 |
|--------|------|----------|
| `ClaudeHooksEngine` | `engine/mod.rs:94` | `preview_session_start()` |
| `ClaudeHooksEngine` | `engine/mod.rs:102` | `run_session_start()` |

## 依赖与外部交互

### 模块依赖图

```
session_start.rs
├── common
│   ├── serialization_failure_hook_events()
│   ├── flatten_additional_contexts()
│   └── append_additional_context()
├── dispatcher
│   ├── select_handlers()
│   ├── execute_handlers()
│   ├── running_summary()
│   └── completed_summary()
├── output_parser
│   └── parse_session_start()
└── schema
    └── SessionStartCommandInput
```

### 与 Engine 的交互

```
ClaudeHooksEngine::run_session_start(request, turn_id)
    │
    ▼
session_start::run(&handlers, &shell, request, turn_id)
    │
    ├──► dispatcher::select_handlers(...) 
    │         - 筛选 event_name == SessionStart
    │         - 对 Startup/Resume 应用 matcher 正则匹配
    │
    ├──► dispatcher::execute_handlers(...)
    │         - 调用 command_runner::run_command() 并行执行
    │         - 每个 handler 接收 JSON 输入 via stdin
    │
    └──► parse_completed()
              - 调用 output_parser::parse_session_start() 解析 JSON
              - 或作为纯文本处理
```

### 与 Protocol 的交互

```
输入: SessionStartCommandInput (JSON)
    ├── session_id
    ├── cwd
    ├── model
    ├── permission_mode
    └── source ("startup" | "resume")

输出: HookCompletedEvent
    ├── turn_id: Option<String>
    └── run: HookRunSummary
        ├── status: Running | Completed | Failed | Stopped
        └── entries: Vec<HookOutputEntry>
            └── HookOutputEntry { kind, text }
```

## 风险、边界与改进建议

### 已知风险

1. **Matcher 正则编译失败静默处理**
   ```rust
   // dispatcher.rs:34-36
   regex::Regex::new(matcher)
       .map(|regex| regex.is_match(input))
       .unwrap_or(false)  // 编译失败时返回 false，可能意外跳过 handler
   ```

2. **JSON 与纯文本的模糊边界**
   - 以 `{` 或 `[` 开头但解析失败的输出被视为错误
   - 这可能误判某些有效的纯文本（如 "{not json"）

3. **additional_context 在停止时的处理**
   - 即使 `continue: false`，`additional_context` 仍被收集
   - 测试用例 `continue_false_preserves_context_for_later_turns` 确认了此行为
   - 需确保调用方正确处理停止时的上下文

### 边界情况

1. **空 handlers 列表**
   ```rust
   if matched.is_empty() {
       return SessionStartOutcome { /* 全空/默认值 */ };
   }
   ```

2. **序列化失败**
   - 使用 `common::serialization_failure_hook_events` 生成失败事件
   - 所有 handlers 标记为 Failed，duration_ms = 0

3. **命令执行错误**
   - 进程启动失败、stdin 写入失败、超时等
   - 统一记录为 Failed 状态

### 改进建议

1. **增强错误报告**
   - 为正则编译失败添加警告日志
   - 区分 "无效 JSON" 和 "非 JSON 文本" 的错误信息

2. **性能优化**
   - 考虑缓存已编译的正则表达式（matcher）
   - 当前每次 `select_handlers` 都重新编译

3. **测试覆盖**
   - 已覆盖：纯文本输出、JSON 输出、continue=false、无效 JSON
   - 缺失：matcher 匹配失败场景、多 handler 聚合、超时场景

4. **文档完善**
   - 添加关于 `additional_context` 在停止时仍被保留的设计说明
   - 说明 `source` 字段的 "clear" 值（schema 中定义但未在 enum 中使用）

5. **类型安全**
   - `permission_mode` 和 `source` 使用 String 而非枚举
   - 考虑在解析阶段就验证有效性
