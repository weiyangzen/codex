# types.rs 研究文档

## 场景与职责

`types.rs` 是 codex-hooks crate 的核心类型定义模块，负责定义钩子系统的**基础数据结构和行为契约**。它是整个钩子系统的基石，被 `registry.rs`、`legacy_notify.rs`、事件处理模块和引擎模块广泛依赖。

该模块定义的类型涵盖：
- 钩子执行模型（`Hook`、`HookFn`）
- 事件负载结构（`HookPayload`、`HookEvent`）
- 执行结果语义（`HookResult`、`HookResponse`）
- 工具调用相关类型（`HookToolInput`、`HookToolKind` 等）

## 功能点目的

### 1. 钩子执行模型

#### `HookFn` - 钩子函数类型

```rust
pub type HookFn = Arc<dyn for<'a> Fn(&'a HookPayload) -> BoxFuture<'a, HookResult> + Send + Sync>;
```

**设计意图**：
- 使用 `Arc` 实现共享所有权，支持多线程克隆
- `for<'a>` 高阶 trait bound 确保生命周期正确
- `BoxFuture` 允许异步执行
- `Send + Sync` 保证线程安全

#### `Hook` - 钩子结构体

```rust
pub struct Hook {
    pub name: String,
    pub func: HookFn,
}
```

**核心方法**：
- `execute(&self, payload: &HookPayload) -> HookResponse`: 执行钩子

### 2. 执行结果语义

#### `HookResult` - 执行结果枚举

```rust
pub enum HookResult {
    Success,                                    // 成功，继续执行
    FailedContinue(Box<dyn Error + Send + Sync>), // 失败，但继续其他钩子
    FailedAbort(Box<dyn Error + Send + Sync>),    // 失败，中断所有钩子
}
```

**关键方法**：
- `should_abort_operation()`: 判断是否应中断操作

**设计考量**：
- 三种状态覆盖所有执行场景
- 错误类型使用 trait object 允许灵活的错误类型
- `FailedContinue` 用于非致命错误（如通知失败不应阻止操作）
- `FailedAbort` 用于致命错误（如安全策略检查失败）

#### `HookResponse` - 执行响应

```rust
pub struct HookResponse {
    pub hook_name: String,
    pub result: HookResult,
}
```

简单的包装结构，关联钩子名称与执行结果。

### 3. 事件负载结构

#### `HookPayload` - 钩子执行负载

```rust
pub struct HookPayload {
    pub session_id: ThreadId,
    pub cwd: PathBuf,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub client: Option<String>,
    #[serde(serialize_with = "serialize_triggered_at")]
    pub triggered_at: DateTime<Utc>,
    pub hook_event: HookEvent,
}
```

**字段说明**：
- `session_id`: 会话唯一标识（来自 `codex_protocol::ThreadId`）
- `cwd`: 当前工作目录（钩子执行的上下文）
- `client`: 客户端标识（如 "codex-tui"）
- `triggered_at`: 触发时间戳（RFC 3339 格式序列化）
- `hook_event`: 具体事件类型（AfterAgent 或 AfterToolUse）

#### `HookEvent` - 事件类型枚举

```rust
#[serde(tag = "event_type", rename_all = "snake_case")]
pub enum HookEvent {
    AfterAgent { event: HookEventAfterAgent },
    AfterToolUse { event: HookEventAfterToolUse },
}
```

**序列化特性**：
- 使用 `event_type` 作为标签字段
- snake_case 命名风格

### 4. 具体事件结构

#### `HookEventAfterAgent` - Agent 完成后事件

```rust
pub struct HookEventAfterAgent {
    pub thread_id: ThreadId,
    pub turn_id: String,
    pub input_messages: Vec<String>,
    pub last_assistant_message: Option<String>,
}
```

**用途**：
- 遗留通知系统使用
- 记录用户输入和助手回复

#### `HookEventAfterToolUse` - 工具使用后事件

```rust
pub struct HookEventAfterToolUse {
    pub turn_id: String,
    pub call_id: String,
    pub tool_name: String,
    pub tool_kind: HookToolKind,
    pub tool_input: HookToolInput,
    pub executed: bool,           // 是否实际执行
    pub success: bool,            // 执行是否成功
    pub duration_ms: u64,         // 执行耗时
    pub mutating: bool,           // 是否为变更操作
    pub sandbox: String,          // 沙箱类型
    pub sandbox_policy: String,   // 沙箱策略
    pub output_preview: String,   // 输出预览
}
```

**用途**：
- 工具执行审计
- 安全策略评估
- 执行性能分析

### 5. 工具相关类型

#### `HookToolKind` - 工具类型枚举

```rust
pub enum HookToolKind {
    Function,
    Custom,
    LocalShell,
    Mcp,
}
```

#### `HookToolInput` - 工具输入枚举

```rust
#[serde(tag = "input_type", rename_all = "snake_case")]
pub enum HookToolInput {
    Function { arguments: String },
    Custom { input: String },
    LocalShell { params: HookToolInputLocalShell },
    Mcp { server: String, tool: String, arguments: String },
}
```

#### `HookToolInputLocalShell` - 本地 Shell 工具参数

```rust
pub struct HookToolInputLocalShell {
    pub command: Vec<String>,
    pub workdir: Option<String>,
    pub timeout_ms: Option<u64>,
    pub sandbox_permissions: Option<SandboxPermissions>,
    pub prefix_rule: Option<Vec<String>>,
    pub justification: Option<String>,
}
```

## 具体技术实现

### 序列化实现

#### 时间戳序列化

```rust
fn serialize_triggered_at<S>(value: &DateTime<Utc>, serializer: S) -> Result<S::Ok, S::Error>
where
    S: Serializer,
{
    serializer.serialize_str(&value.to_rfc3339_opts(SecondsFormat::Secs, true))
}
```

**输出格式**：`"2025-01-01T00:00:00Z"`

### 默认实现

```rust
impl Default for Hook {
    fn default() -> Self {
        Self {
            name: "default".to_string(),
            func: Arc::new(|_| Box::pin(async { HookResult::Success })),
        }
    }
}
```

**用途**：测试和占位场景

## 关键代码路径与文件引用

### 当前文件关键代码

| 行号 | 代码 | 说明 |
|------|------|------|
| 13 | `HookFn` 类型别名 | 异步钩子函数类型定义 |
| 15-31 | `HookResult` | 执行结果枚举 |
| 33-37 | `HookResponse` | 响应结构体 |
| 39-61 | `Hook` | 钩子结构体及实现 |
| 63-73 | `HookPayload` | 负载结构体 |
| 75-82 | `HookEventAfterAgent` | Agent 事件详情 |
| 84-91 | `HookToolKind` | 工具类型枚举 |
| 93-121 | `HookToolInput` / `HookToolInputLocalShell` | 工具输入类型 |
| 123-138 | `HookEventAfterToolUse` | 工具使用事件详情 |
| 140-145 | `serialize_triggered_at` | 时间戳序列化 |
| 147-158 | `HookEvent` | 事件类型枚举 |

### 跨文件引用

| 类型 | 被引用位置 | 用途 |
|------|-----------|------|
| `Hook` | `registry.rs`, `legacy_notify.rs` | 钩子存储和执行 |
| `HookFn` | `registry.rs` | 类型约束 |
| `HookResult` | 全模块 | 执行结果传递 |
| `HookResponse` | `registry.rs` | 响应收集 |
| `HookPayload` | 全模块 | 负载传递 |
| `HookEvent` | `registry.rs`, `legacy_notify.rs` | 事件路由 |
| `HookEventAfterAgent` | `legacy_notify.rs` | 遗留通知 |
| `HookEventAfterToolUse` | (预留) | 工具事件 |
| `HookToolKind/Input` | (预留) | 工具信息 |

### 外部依赖

| Crate | 类型 | 用途 |
|-------|------|------|
| `chrono` | `DateTime<Utc>` | 时间戳 |
| `codex_protocol` | `ThreadId`, `SandboxPermissions` | 协议类型 |
| `futures` | `BoxFuture` | 异步 trait |
| `serde` | `Serialize`, `Serializer` | 序列化 |
| `std::path::PathBuf` | `PathBuf` | 路径 |
| `std::sync::Arc` | `Arc` | 共享所有权 |

## 依赖与外部交互

### 类型依赖图

```
types.rs 定义的基础类型
  │
  ├─> registry.rs: Hook, HookResult, HookResponse, HookPayload, HookEvent
  ├─> legacy_notify.rs: HookPayload, HookEvent, HookEventAfterAgent, HookResult
  ├─> engine/*: (通过 registry 间接使用)
  └─> events/*: (Claude Hooks 使用独立类型)
```

### 与 codex_protocol 的关系

```
codex_protocol::ThreadId
  └─> types.rs: HookPayload.session_id
  └─> types.rs: HookEventAfterAgent.thread_id

codex_protocol::models::SandboxPermissions
  └─> types.rs: HookToolInputLocalShell.sandbox_permissions
```

### 序列化输出示例

#### HookPayload (AfterAgent)

```json
{
  "session_id": "uuid-string",
  "cwd": "/project/path",
  "triggered_at": "2025-01-01T00:00:00Z",
  "hook_event": {
    "event_type": "after_agent",
    "thread_id": "uuid-string",
    "turn_id": "turn-1",
    "input_messages": ["hello"],
    "last_assistant_message": "hi"
  }
}
```

#### HookPayload (AfterToolUse)

```json
{
  "session_id": "uuid-string",
  "cwd": "/project/path",
  "triggered_at": "2025-01-01T00:00:00Z",
  "hook_event": {
    "event_type": "after_tool_use",
    "turn_id": "turn-2",
    "call_id": "call-1",
    "tool_name": "local_shell",
    "tool_kind": "local_shell",
    "tool_input": {
      "input_type": "local_shell",
      "params": {
        "command": ["cargo", "fmt"],
        "workdir": "codex-rs",
        "timeout_ms": 60000,
        "sandbox_permissions": "use_default",
        "justification": null,
        "prefix_rule": null
      }
    },
    "executed": true,
    "success": true,
    "duration_ms": 42,
    "mutating": true,
    "sandbox": "none",
    "sandbox_policy": "danger-full-access",
    "output_preview": "ok"
  }
}
```

## 风险、边界与改进建议

### 已知风险

1. **`AfterToolUse` 未实际使用**
   - 类型已定义但 `registry.rs` 中 `after_tool_use: Vec<Hook>` 始终为空
   - 可能导致开发者误以为功能已实现
   - 建议：添加 `#[doc(hidden)]` 或实现 TODO 注释

2. **`HookEventAfterToolUse` 字段冗余**
   - `sandbox` 和 `sandbox_policy` 可能重复
   - `output_preview` 可能包含敏感信息
   - 建议：审计字段必要性，添加敏感信息过滤

3. **错误类型擦除**
   - `HookResult` 使用 `Box<dyn Error>` 擦除具体错误类型
   - 不利于调用方进行精细化错误处理
   - 建议：考虑使用具体错误枚举或保留错误链

### 边界情况

| 场景 | 行为 |
|------|------|
| `client = None` | 序列化时省略该字段（`skip_serializing_if`） |
| `last_assistant_message = None` | 序列化为 `null` |
| `input_messages` 为空 | 序列化为空数组 `[]` |
| `command` 为空数组 | 允许（但可能导致 shell 错误） |
| `duration_ms = 0` | 有效值，表示执行极快或计时失败 |

### 测试覆盖

当前测试：
- `hook_payload_serializes_stable_wire_shape`: 验证 AfterAgent 序列化
- `after_tool_use_payload_serializes_stable_wire_shape`: 验证 AfterToolUse 序列化

测试特点：
- 使用 `pretty_assertions::assert_eq` 进行清晰 diff
- 验证完整 JSON 结构而非单个字段
- 使用固定时间戳确保可重复性

建议增加：
- 反序列化测试（JSON -> Rust 结构）
- 边界值测试（空字符串、极大值）
- 错误类型测试（`FailedContinue`/`FailedAbort`）

### 改进建议

1. **错误类型改进**
   ```rust
   pub enum HookError {
       Io(std::io::Error),
       Timeout { duration: Duration },
       InvalidOutput(String),
       // ...
   }
   
   pub enum HookResult {
       Success,
       FailedContinue(HookError),
       FailedAbort(HookError),
   }
   ```

2. **工具输入验证**
   ```rust
   impl HookToolInputLocalShell {
       pub fn validate(&self) -> Result<(), ValidationError> {
           if self.command.is_empty() {
               return Err(ValidationError::EmptyCommand);
           }
           // ...
       }
   }
   ```

3. **敏感信息处理**
   ```rust
   impl HookEventAfterToolUse {
       pub fn sanitize(mut self) -> Self {
           // 移除或脱敏敏感字段
           self.output_preview = sanitize_output(&self.output_preview);
           self
       }
   }
   ```

4. **文档完善**
   - 为每个公共类型添加详细 rustdoc
   - 包含序列化示例
   - 说明字段含义和取值范围

### 代码统计

| 指标 | 数值 |
|------|------|
| 总行数 | ~290 行 |
| 结构体 | 5 个 |
| 枚举 | 3 个 |
| 类型别名 | 1 个 |
| 测试函数 | 2 个 |

### 架构建议

当前 `types.rs` 承担了过多的类型定义职责，随着功能扩展可能需要拆分：

```
types/
├── mod.rs          # 公共导出
├── hook.rs         # Hook, HookFn, HookResult, HookResponse
├── payload.rs      # HookPayload, HookEvent
├── tool.rs         # HookToolKind, HookToolInput
└── legacy.rs       # HookEventAfterAgent (仅遗留系统使用)
```

但当前规模（290 行）尚不需要拆分，保持单文件即可。
