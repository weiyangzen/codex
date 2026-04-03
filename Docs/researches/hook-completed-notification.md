# HookCompletedNotification 研究报告

## 1. 场景与职责

`HookCompletedNotification` 是 Codex App Server Protocol v2 中的服务器通知类型，用于向客户端报告 Hook（钩子）执行完成的状态和结果。Hook 系统允许在特定事件点（如会话开始、用户提交提示）执行自定义逻辑，实现工作流扩展和自动化。

### 主要使用场景

- **Hook 执行监控**：客户端实时跟踪 Hook 的执行状态和进度
- **结果展示**：向用户展示 Hook 执行产生的输出（警告、反馈、上下文等）
- **工作流集成**：根据 Hook 执行结果决定后续操作（如阻止继续执行）
- **调试和审计**：记录 Hook 执行历史，用于故障排查和合规审计
- **异步处理**：支持异步 Hook 的完成通知，避免阻塞主流程

### 职责边界

- 作为服务器到客户端的单向通知，仅报告 Hook 执行完成状态
- 承载 Hook 执行的完整元数据（时间、状态、输出等）
- 不直接触发客户端操作，仅提供信息供客户端决策
- 支持同步和异步两种执行模式的状态报告

---

## 2. 功能点目的

### 2.1 Hook 执行摘要（HookRunSummary）

`HookRunSummary` 是通知的核心 payload，包含 Hook 执行的完整信息：

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | `string` | Hook 执行实例的唯一标识 |
| `eventName` | `HookEventName` | 触发 Hook 的事件名称 |
| `handlerType` | `HookHandlerType` | 处理器类型（Command/Prompt/Agent） |
| `executionMode` | `HookExecutionMode` | 执行模式（Sync/Async） |
| `scope` | `HookScope` | 作用域（Thread/Turn） |
| `sourcePath` | `string` | Hook 配置文件路径 |
| `displayOrder` | `integer` | 显示顺序 |
| `status` | `HookRunStatus` | 执行状态 |
| `statusMessage` | `string \| null` | 状态描述信息 |
| `startedAt` | `integer` | 开始时间（Unix 时间戳） |
| `completedAt` | `integer \| null` | 完成时间 |
| `durationMs` | `integer \| null` | 执行耗时（毫秒） |
| `entries` | `HookOutputEntry[]` | 输出条目列表 |

### 2.2 事件类型（HookEventName）

| 事件 | 触发时机 |
|------|---------|
| `sessionStart` | 会话开始时 |
| `userPromptSubmit` | 用户提交提示时 |
| `stop` | 会话停止时 |

#### 功能目的

- **生命周期覆盖**：覆盖会话的主要生命周期节点
- **扩展点提供**：允许在这些关键点插入自定义逻辑
- **条件触发**：支持基于事件的条件 Hook 执行

### 2.3 处理器类型（HookHandlerType）

| 类型 | 说明 |
|------|------|
| `command` | 执行 shell 命令 |
| `prompt` | 发送提示到模型 |
| `agent` | 调用子代理 |

#### 功能目的

- **多样化处理**：支持不同类型的 Hook 实现方式
- **灵活性**：根据场景选择最合适的处理方式
- **能力扩展**：通过 agent 类型实现复杂的 AI 驱动 Hook

### 2.4 执行模式（HookExecutionMode）

| 模式 | 说明 |
|------|------|
| `sync` | 同步执行，阻塞主流程 |
| `async` | 异步执行，不阻塞主流程 |

#### 功能目的

- **性能优化**：异步 Hook 避免阻塞用户操作
- **可靠性**：同步 Hook 确保关键检查在继续前完成
- **用户体验**：根据 Hook 重要性选择执行模式

### 2.5 作用域（HookScope）

| 作用域 | 说明 |
|--------|------|
| `thread` | 会话级别，影响整个会话 |
| `turn` | 轮次级别，仅影响当前轮次 |

#### 功能目的

- **粒度控制**：区分全局和局部的 Hook 效果
- **资源管理**：会话级 Hook 可能长期运行
- **隔离性**：轮次级 Hook 不影响其他轮次

### 2.6 执行状态（HookRunStatus）

| 状态 | 说明 |
|------|------|
| `running` | 正在执行 |
| `completed` | 成功完成 |
| `failed` | 执行失败 |
| `blocked` | 被阻止（如安全策略） |
| `stopped` | 被用户或系统停止 |

### 2.7 输出条目（HookOutputEntry）

| 字段 | 类型 | 说明 |
|------|------|------|
| `kind` | `HookOutputEntryKind` | 输出类型 |
| `text` | `string` | 输出内容 |

#### 输出类型（HookOutputEntryKind）

| 类型 | 用途 |
|------|------|
| `warning` | 警告信息，提醒用户注意 |
| `stop` | 阻止继续执行 |
| `feedback` | 反馈信息，展示给用户 |
| `context` | 上下文信息，供后续处理使用 |
| `error` | 错误信息 |

#### 功能目的

- **结构化输出**：不同类型的输出有不同的处理方式
- **用户交互**：`warning` 和 `feedback` 直接展示给用户
- **流程控制**：`stop` 类型可以中断后续操作
- **调试支持**：`error` 类型帮助排查问题

---

## 3. 具体技术实现

### 3.1 数据结构定义

#### JSON Schema 定义

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "definitions": {
    "HookEventName": { "enum": ["sessionStart", "userPromptSubmit", "stop"], "type": "string" },
    "HookExecutionMode": { "enum": ["sync", "async"], "type": "string" },
    "HookHandlerType": { "enum": ["command", "prompt", "agent"], "type": "string" },
    "HookOutputEntry": {
      "properties": {
        "kind": { "$ref": "#/definitions/HookOutputEntryKind" },
        "text": { "type": "string" }
      },
      "required": ["kind", "text"],
      "type": "object"
    },
    "HookOutputEntryKind": { "enum": ["warning", "stop", "feedback", "context", "error"], "type": "string" },
    "HookRunStatus": { "enum": ["running", "completed", "failed", "blocked", "stopped"], "type": "string" },
    "HookRunSummary": {
      "properties": {
        "completedAt": { "format": "int64", "type": ["integer", "null"] },
        "displayOrder": { "format": "int64", "type": "integer" },
        "durationMs": { "format": "int64", "type": ["integer", "null"] },
        "entries": { "items": { "$ref": "#/definitions/HookOutputEntry" }, "type": "array" },
        "eventName": { "$ref": "#/definitions/HookEventName" },
        "executionMode": { "$ref": "#/definitions/HookExecutionMode" },
        "handlerType": { "$ref": "#/definitions/HookHandlerType" },
        "id": { "type": "string" },
        "scope": { "$ref": "#/definitions/HookScope" },
        "sourcePath": { "type": "string" },
        "startedAt": { "format": "int64", "type": "integer" },
        "status": { "$ref": "#/definitions/HookRunStatus" },
        "statusMessage": { "type": ["string", "null"] }
      },
      "required": ["displayOrder", "entries", "eventName", "executionMode", "handlerType", "id", "scope", "sourcePath", "startedAt", "status"],
      "type": "object"
    },
    "HookScope": { "enum": ["thread", "turn"], "type": "string" }
  },
  "properties": {
    "run": { "$ref": "#/definitions/HookRunSummary" },
    "threadId": { "type": "string" },
    "turnId": { "type": ["string", "null"] }
  },
  "required": ["run", "threadId"],
  "title": "HookCompletedNotification",
  "type": "object"
}
```

#### Rust 结构体定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs

/// Hook 执行完成通知
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct HookCompletedNotification {
    pub thread_id: String,
    pub turn_id: Option<String>,
    pub run: HookRunSummary,
}

/// Hook 执行摘要
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct HookRunSummary {
    pub id: String,
    pub event_name: HookEventName,
    pub handler_type: HookHandlerType,
    pub execution_mode: HookExecutionMode,
    pub scope: HookScope,
    pub source_path: PathBuf,
    pub display_order: i64,
    pub status: HookRunStatus,
    pub status_message: Option<String>,
    pub started_at: i64,
    pub completed_at: Option<i64>,
    pub duration_ms: Option<i64>,
    pub entries: Vec<HookOutputEntry>,
}

/// Hook 输出条目
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct HookOutputEntry {
    pub kind: HookOutputEntryKind,
    pub text: String,
}

// 枚举类型定义
v2_enum_from_core! {
    pub enum HookEventName from CoreHookEventName {
        SessionStart, UserPromptSubmit, Stop
    }
}

v2_enum_from_core! {
    pub enum HookHandlerType from CoreHookHandlerType {
        Command, Prompt, Agent
    }
}

v2_enum_from_core! {
    pub enum HookExecutionMode from CoreHookExecutionMode {
        Sync, Async
    }
}

v2_enum_from_core! {
    pub enum HookScope from CoreHookScope {
        Thread, Turn
    }
}

v2_enum_from_core! {
    pub enum HookRunStatus from CoreHookRunStatus {
        Running, Completed, Failed, Blocked, Stopped
    }
}

v2_enum_from_core! {
    pub enum HookOutputEntryKind from CoreHookOutputEntryKind {
        Warning, Stop, Feedback, Context, Error
    }
}
```

#### 核心协议类型

```rust
// codex-rs/protocol/src/protocol.rs

#[derive(Debug, Clone, Copy, Deserialize, Serialize, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "snake_case")]
pub enum HookEventName {
    SessionStart,
    UserPromptSubmit,
    Stop,
}

#[derive(Debug, Clone, Copy, Deserialize, Serialize, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "snake_case")]
pub enum HookHandlerType {
    Command,
    Prompt,
    Agent,
}

#[derive(Debug, Clone, Copy, Deserialize, Serialize, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "snake_case")]
pub enum HookExecutionMode {
    Sync,
    Async,
}

#[derive(Debug, Clone, Copy, Deserialize, Serialize, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "snake_case")]
pub enum HookScope {
    Thread,
    Turn,
}

#[derive(Debug, Clone, Copy, Deserialize, Serialize, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "snake_case")]
pub enum HookRunStatus {
    Running,
    Completed,
    Failed,
    Blocked,
    Stopped,
}

#[derive(Debug, Clone, Copy, Deserialize, Serialize, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "snake_case")]
pub enum HookOutputEntryKind {
    Warning,
    Stop,
    Feedback,
    Context,
    Error,
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "snake_case")]
pub struct HookOutputEntry {
    pub kind: HookOutputEntryKind,
    pub text: String,
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "snake_case")]
pub struct HookRunSummary {
    pub id: String,
    pub event_name: HookEventName,
    pub handler_type: HookHandlerType,
    pub execution_mode: HookExecutionMode,
    pub scope: HookScope,
    pub source_path: PathBuf,
    pub display_order: i64,
    pub status: HookRunStatus,
    pub status_message: Option<String>,
    #[ts(type = "number")]
    pub started_at: i64,
    #[ts(type = "number | null")]
    pub completed_at: Option<i64>,
    #[ts(type = "number | null")]
    pub duration_ms: Option<i64>,
    pub entries: Vec<HookOutputEntry>,
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "snake_case")]
pub struct HookCompletedEvent {
    pub turn_id: Option<String>,
    pub run: HookRunSummary,
}
```

### 3.2 协议集成

```rust
// codex-rs/app-server-protocol/src/protocol/common.rs
server_notification_definitions! {
    // ...
    HookCompleted => "hook/completed" (v2::HookCompletedNotification),
    // ...
}
```

### 3.3 序列化示例

```json
{
  "method": "hook/completed",
  "params": {
    "threadId": "thread-123",
    "turnId": "turn-456",
    "run": {
      "id": "hook-run-789",
      "eventName": "userPromptSubmit",
      "handlerType": "command",
      "executionMode": "sync",
      "scope": "turn",
      "sourcePath": "/path/to/hook.yaml",
      "displayOrder": 1,
      "status": "completed",
      "statusMessage": null,
      "startedAt": 1704067200,
      "completedAt": 1704067201,
      "durationMs": 1000,
      "entries": [
        {
          "kind": "feedback",
          "text": "代码检查通过"
        },
        {
          "kind": "context",
          "text": "检测到 Python 文件"
        }
      ]
    }
  }
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 协议定义文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | v2 API 类型定义（第 4702-4709 行） |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 通知注册（第 888 行） |
| `codex-rs/protocol/src/protocol.rs` | 核心协议类型（第 1341-1430 行） |

### 4.2 Schema 文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/schema/json/v2/HookCompletedNotification.json` | JSON Schema 定义 |
| `codex-rs/app-server-protocol/schema/typescript/v2/HookCompletedNotification.ts` | TypeScript 类型定义 |

### 4.3 服务端实现

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server/src/bespoke_event_handling.rs` | Hook 事件处理 |
| `codex-rs/app-server/src/codex_message_processor.rs` | Codex 消息处理 |
| `codex-rs/app-server/src/outgoing_message.rs` | 出站消息处理 |

### 4.4 消费端代码

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui/src/` | TUI 客户端 Hook 处理 |
| `codex-rs/tui_app_server/src/` | TUI App Server Hook 处理 |

---

## 5. 依赖与外部交互

### 5.1 内部依赖关系

```
HookCompletedNotification
├── thread_id: String
├── turn_id: Option<String>
└── run: HookRunSummary
    ├── id: String
    ├── event_name: HookEventName
    ├── handler_type: HookHandlerType
    ├── execution_mode: HookExecutionMode
    ├── scope: HookScope
    ├── source_path: PathBuf
    ├── display_order: i64
    ├── status: HookRunStatus
    ├── status_message: Option<String>
    ├── started_at: i64
    ├── completed_at: Option<i64>
    ├── duration_ms: Option<i64>
    └── entries: Vec<HookOutputEntry>
        ├── kind: HookOutputEntryKind
        └── text: String
```

### 5.2 Hook 系统架构

```
┌─────────────────────────────────────────────────────────────┐
│                        Hook System                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Event Trigger        Hook Registry       Hook Executor     │
│  ─────────────        ─────────────       ─────────────     │
│  sessionStart    ──▶  Load Config    ──▶  Execute Hook      │
│  userPromptSubmit     Find Handlers       (sync/async)      │
│  stop                                          │            │
│                                                ▼            │
│                                          HookRunSummary     │
│                                                │            │
│                                                ▼            │
│                                    HookCompletedNotification│
│                                                │            │
│                                                ▼            │
│                                              Client         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 5.3 与 Turn 生命周期的集成

```
Turn 开始
    │
    ▼
触发 userPromptSubmit Hook
    │
    ├── 同步执行 ──▶ 等待完成 ──▶ HookCompletedNotification
    │
    └── 异步执行 ──▶ 继续主流程
                         │
                         ▼
                    Hook 完成
                         │
                         ▼
                    HookCompletedNotification
```

### 5.4 相关通知

| 通知 | 触发时机 |
|------|---------|
| `HookStarted` | Hook 开始执行时 |
| `HookCompleted` | Hook 执行完成时 |

---

## 6. 风险、边界与改进建议

### 6.1 潜在风险

| 风险点 | 描述 | 影响 | 缓解措施 |
|--------|------|------|---------|
| 输出过大 | `entries` 可能包含大量文本，导致消息过大 | 网络/内存压力 | 设置输出大小限制，提供截断机制 |
| 敏感信息泄露 | Hook 输出可能包含敏感信息 | 安全风险 | 输出内容审查，敏感信息脱敏 |
| 状态不一致 | 异步 Hook 完成时，相关 Turn 可能已结束 | 数据不一致 | 添加 Turn 状态校验 |
| 重复通知 | 网络重连可能导致重复接收通知 | 重复处理 | 客户端实现幂等处理 |
| 时序问题 | 多个 Hook 并发执行时的通知顺序 | 显示混乱 | 使用 `displayOrder` 排序 |

### 6.2 边界情况

1. **Hook 执行超时**
   - 同步 Hook 超时后状态应为 `failed` 或 `stopped`
   - `durationMs` 应反映实际执行时间

2. **Hook 被阻止**
   - 安全策略阻止 Hook 执行
   - 状态为 `blocked`，`statusMessage` 包含阻止原因

3. **空输出**
   - Hook 执行成功但无输出
   - `entries` 为空数组

4. **大量输出条目**
   - 单个 Hook 产生数百条输出
   - 考虑分页或截断策略

5. **Turn 已结束**
   - 异步 Hook 完成时，对应的 Turn 可能已结束
   - 客户端应优雅处理这种情况

### 6.3 改进建议

#### 短期改进

1. **添加 Hook 配置标识**
   ```rust
   pub struct HookRunSummary {
       // ...
       /// Hook 配置的唯一标识
       pub hook_id: String,
   }
   ```

2. **扩展状态信息**
   ```rust
   pub struct HookRunSummary {
       // ...
       /// 详细的退出码或错误码
       pub exit_code: Option<i32>,
   }
   ```

3. **输出条目元数据**
   ```rust
   pub struct HookOutputEntry {
       pub kind: HookOutputEntryKind,
       pub text: String,
       /// 输出时间戳
       pub timestamp: Option<i64>,
   }
   ```

#### 中期改进

1. **Hook 链支持**
   ```rust
   pub struct HookRunSummary {
       // ...
       /// 父 Hook ID（如果是链式调用）
       pub parent_id: Option<String>,
       /// 链中的位置
       pub chain_position: Option<u32>,
   }
   ```

2. **资源使用统计**
   ```rust
   pub struct HookRunSummary {
       // ...
       /// CPU 使用时间（毫秒）
       pub cpu_time_ms: Option<i64>,
       /// 内存使用峰值（字节）
       pub memory_peak_bytes: Option<i64>,
   }
   ```

3. **条件执行信息**
   ```rust
   pub struct HookRunSummary {
       // ...
       /// 触发条件详情
       pub trigger_condition: Option<String>,
   }
   ```

#### 长期改进

1. **Hook 实时流式输出**
   - 对于长时间运行的 Hook，支持流式输出通知
   - 避免等待 Hook 完成才能看到输出

2. **Hook 调试模式**
   - 添加 `debug` 标志，包含更多调试信息
   - 环境变量、输入参数等

3. **Hook 性能分析**
   - 收集 Hook 执行的性能指标
   - 提供优化建议

4. **Hook 版本控制**
   ```rust
   pub struct HookRunSummary {
       // ...
       /// Hook 配置版本
       pub hook_version: String,
   }
   ```

### 6.4 兼容性考虑

- **新增字段**：所有新增字段应为 `Option<T>`，使用 `#[serde(default)]`
- **新增枚举变体**：使用 `#[serde(other)]` 处理未知变体
- **输出格式**：保持 `text` 字段的纯文本格式，避免引入复杂格式
- **时间戳精度**：Unix 时间戳使用秒级精度，与现有 API 保持一致
