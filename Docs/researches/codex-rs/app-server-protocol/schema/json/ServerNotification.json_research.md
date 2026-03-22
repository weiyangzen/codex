# ServerNotification.json 研究文档

## 1. 场景与职责

### 1.1 文件定位

`ServerNotification.json` 是 Codex App-Server Protocol 的核心 JSON Schema 文件，位于 `codex-rs/app-server-protocol/schema/json/` 目录下。该文件定义了**服务器向客户端发送的所有通知消息**的数据结构。

### 1.2 核心职责

- **协议契约**：定义服务器→客户端通信的完整通知类型系统
- **多语言绑定**：作为 TypeScript 类型定义和 Rust 结构体的共同来源
- **运行时验证**：为客户端提供 JSON Schema 验证能力
- **文档生成**：自动生成 API 文档和开发者参考

### 1.3 使用场景

| 场景 | 说明 |
|------|------|
| Thread 生命周期 | 线程启动、状态变更、归档、关闭等事件通知 |
| Turn 执行流程 | 回合开始、完成、中断、错误等状态通知 |
| Item 级事件 | 消息项开始/完成、流式增量更新、工具调用进度 |
| 账户相关 | 登录完成、账户信息更新、速率限制变更 |
| 配置警告 | 配置文件解析警告、弃用通知 |
| 实时会话 | 实时语音/文本会话的音频流、错误、关闭事件 |
| 命令执行 | 独立命令执行的输出流式传输 |

---

## 2. 功能点目的

### 2.1 通知分类体系

ServerNotification 采用 **tagged union** 设计，通过 `method` 字段区分 40+ 种通知类型：

```json
{
  "method": "thread/started",
  "params": { ... }
}
```

### 2.2 主要通知类别

#### 2.2.1 Thread 生命周期通知 (8种)

| 通知 | 方法名 | 目的 |
|------|--------|------|
| ThreadStarted | `thread/started` | 新线程创建成功 |
| ThreadStatusChanged | `thread/status/changed` | 线程状态变更（idle/active/systemError） |
| ThreadArchived | `thread/archived` | 线程已归档 |
| ThreadUnarchived | `thread/unarchived` | 线程已取消归档 |
| ThreadClosed | `thread/closed` | 线程已关闭 |
| ThreadNameUpdated | `thread/name/updated` | 线程标题更新 |
| ThreadTokenUsageUpdated | `thread/tokenUsage/updated` | Token 使用量更新 |
| ContextCompacted | `thread/compacted` | 上下文压缩完成（已弃用） |

#### 2.2.2 Turn 执行通知 (6种)

| 通知 | 方法名 | 目的 |
|------|--------|------|
| TurnStarted | `turn/started` | 新回合开始 |
| TurnCompleted | `turn/completed` | 回合完成 |
| TurnDiffUpdated | `turn/diff/updated` | 回合级统一差异更新 |
| TurnPlanUpdated | `turn/plan/updated` | 执行计划更新 |
| Error | `error` | 回合执行错误 |
| ModelRerouted | `model/rerouted` | 模型因安全原因切换 |

#### 2.2.3 Item 级通知 (12种)

| 通知 | 方法名 | 目的 |
|------|--------|------|
| ItemStarted | `item/started` | 消息项开始处理 |
| ItemCompleted | `item/completed` | 消息项完成 |
| AgentMessageDelta | `item/agentMessage/delta` | AI 消息流式增量 |
| PlanDelta | `item/plan/delta` | 计划项流式增量（实验性） |
| CommandExecutionOutputDelta | `item/commandExecution/outputDelta` | 命令执行输出增量 |
| TerminalInteraction | `item/commandExecution/terminalInteraction` | 终端交互输入 |
| FileChangeOutputDelta | `item/fileChange/outputDelta` | 文件变更输出增量 |
| ReasoningTextDelta | `item/reasoning/textDelta` | 推理文本增量 |
| ReasoningSummaryTextDelta | `item/reasoning/summaryTextDelta` | 推理摘要增量 |
| ReasoningSummaryPartAdded | `item/reasoning/summaryPartAdded` | 推理摘要部分添加 |
| ItemGuardianApprovalReviewStarted | `item/autoApprovalReview/started` | Guardian 审核开始（不稳定） |
| ItemGuardianApprovalReviewCompleted | `item/autoApprovalReview/completed` | Guardian 审核完成（不稳定） |

#### 2.2.4 账户与配置通知 (6种)

| 通知 | 方法名 | 目的 |
|------|--------|------|
| AccountLoginCompleted | `account/login/completed` | 账户登录完成 |
| AccountUpdated | `account/updated` | 账户信息更新 |
| AccountRateLimitsUpdated | `account/rateLimits/updated` | 速率限制更新 |
| ConfigWarning | `configWarning` | 配置警告 |
| DeprecationNotice | `deprecationNotice` | 弃用通知 |
| SkillsChanged | `skills/changed` | Skill 文件变更 |

#### 2.2.5 实时会话通知 (5种，实验性)

| 通知 | 方法名 | 目的 |
|------|--------|------|
| ThreadRealtimeStarted | `thread/realtime/started` | 实时会话启动 |
| ThreadRealtimeItemAdded | `thread/realtime/itemAdded` | 实时会话原始项添加 |
| ThreadRealtimeOutputAudioDelta | `thread/realtime/outputAudio/delta` | 实时音频输出增量 |
| ThreadRealtimeError | `thread/realtime/error` | 实时会话错误 |
| ThreadRealtimeClosed | `thread/realtime/closed` | 实时会话关闭 |

#### 2.2.6 其他通知 (5种)

| 通知 | 方法名 | 目的 |
|------|--------|------|
| CommandExecOutputDelta | `command/exec/outputDelta` | 独立命令执行输出 |
| ServerRequestResolved | `serverRequest/resolved` | 服务器请求已解决 |
| McpToolCallProgress | `item/mcpToolCall/progress` | MCP 工具调用进度 |
| McpServerOauthLoginCompleted | `mcpServer/oauthLogin/completed` | MCP OAuth 登录完成 |
| AppListUpdated | `app/list/updated` | 应用列表更新（实验性） |
| WindowsWorldWritableWarning | `windows/worldWritableWarning` | Windows 可写目录警告 |
| WindowsSandboxSetupCompleted | `windowsSandbox/setupCompleted` | Windows 沙盒设置完成 |
| HookStarted | `hook/started` | Hook 执行开始 |
| HookCompleted | `hook/completed` | Hook 执行完成 |
| RawResponseItemCompleted | `rawResponseItem/completed` | 原始响应项完成（内部使用） |
| FuzzyFileSearchSessionUpdated | `fuzzyFileSearch/sessionUpdated` | 模糊文件搜索会话更新 |
| FuzzyFileSearchSessionCompleted | `fuzzyFileSearch/sessionCompleted` | 模糊文件搜索会话完成 |

---

## 3. 具体技术实现

### 3.1 架构分层

```
┌─────────────────────────────────────────────────────────────┐
│                    应用层 (App-Server)                       │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ Thread Mgmt │  │ Turn Exec   │  │ Command Exec        │  │
│  └──────┬──────┘  └──────┬──────┘  └──────────┬──────────┘  │
└─────────┼────────────────┼────────────────────┼─────────────┘
          │                │                    │
          ▼                ▼                    ▼
┌─────────────────────────────────────────────────────────────┐
│              协议层 (app-server-protocol)                    │
│  ┌───────────────────────────────────────────────────────┐  │
│  │           ServerNotification (Rust Enum)              │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌───────────────┐  │  │
│  │  │ ThreadStarted│  │ TurnCompleted│  │ AgentMessageDelta│  │  │
│  │  └─────────────┘  └─────────────┘  └───────────────┘  │  │
│  └───────────────────────────────────────────────────────┘  │
│                          │                                  │
│                          ▼                                  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │         JSON Schema Generation (schemars)             │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│              序列化层 (JSON-RPC 2.0-like)                   │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  { "method": "thread/started", "params": {...} }       │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 Rust 实现核心

#### 3.2.1 ServerNotification 枚举定义

```rust
// codex-rs/app-server-protocol/src/protocol/common.rs
#[derive(Serialize, Deserialize, Debug, Clone, JsonSchema, TS, Display, ExperimentalApi)]
#[serde(tag = "method", content = "params", rename_all = "camelCase")]
#[strum(serialize_all = "camelCase")]
pub enum ServerNotification {
    Error => "error" (v2::ErrorNotification),
    ThreadStarted => "thread/started" (v2::ThreadStartedNotification),
    ThreadStatusChanged => "thread/status/changed" (v2::ThreadStatusChangedNotification),
    // ... 40+ variants
}
```

#### 3.2.2 宏生成机制

使用 `server_notification_definitions!` 宏自动生成：

```rust
macro_rules! server_notification_definitions {
    (
        $(
            $(#[$variant_meta:meta])*
            $variant:ident $(=> $wire:literal)? ( $payload:ty )
        ),* $(,)?
    ) => {
        #[derive(..., JsonSchema, TS, ...)]
        #[serde(tag = "method", content = "params", rename_all = "camelCase")]
        pub enum ServerNotification {
            $(
                $(#[$variant_meta])*
                $(#[serde(rename = $wire)] #[ts(rename = $wire)] #[strum(serialize = $wire)])?
                $variant($payload),
            )*
        }
        // ... 自动生成导出函数
    };
}
```

### 3.3 JSON Schema 生成流程

```rust
// codex-rs/app-server-protocol/src/export.rs
pub fn generate_json_with_experimental(out_dir: &Path, experimental_api: bool) -> Result<()> {
    // 1. 生成信封类型 Schema
    let envelope_emitters: Vec<JsonSchemaEmitter> = vec![
        |d| write_json_schema_with_return::<ServerNotification>(d, "ServerNotification"),
        // ...
    ];
    
    // 2. 收集所有 Schema
    let mut schemas: Vec<GeneratedSchema> = Vec::new();
    for emit in &envelope_emitters {
        schemas.push(emit(out_dir)?);
    }
    
    // 3. 扩展参数/响应 Schema
    schemas.extend(export_server_notification_schemas(out_dir)?);
    
    // 4. 构建 Schema Bundle
    let mut bundle = build_schema_bundle(schemas)?;
    
    // 5. 过滤实验性 API（如需要）
    if !experimental_api {
        filter_experimental_schema(&mut bundle)?;
    }
    
    // 6. 写入文件
    write_pretty_json(out_dir.join("ServerNotification.json"), &bundle)?;
}
```

### 3.4 关键数据结构

#### 3.4.1 ThreadItem 联合类型

ThreadItem 是 ServerNotification 中最复杂的数据结构之一，表示线程中的各类消息项：

```json
{
  "oneOf": [
    { "title": "UserMessageThreadItem", "type": "object", ... },
    { "title": "AgentMessageThreadItem", "type": "object", ... },
    { "title": "PlanThreadItem", "type": "object", ... },
    { "title": "ReasoningThreadItem", "type": "object", ... },
    { "title": "CommandExecutionThreadItem", "type": "object", ... },
    { "title": "FileChangeThreadItem", "type": "object", ... },
    { "title": "McpToolCallThreadItem", "type": "object", ... },
    { "title": "DynamicToolCallThreadItem", "type": "object", ... },
    { "title": "CollabAgentToolCallThreadItem", "type": "object", ... },
    { "title": "WebSearchThreadItem", "type": "object", ... },
    { "title": "ImageViewThreadItem", "type": "object", ... },
    { "title": "ImageGenerationThreadItem", "type": "object", ... },
    { "title": "EnteredReviewModeThreadItem", "type": "object", ... },
    { "title": "ExitedReviewModeThreadItem", "type": "object", ... },
    { "title": "ContextCompactionThreadItem", "type": "object", ... }
  ]
}
```

#### 3.4.2 ThreadStatus 状态机

```json
{
  "oneOf": [
    { "title": "NotLoadedThreadStatus", "properties": { "type": { "enum": ["notLoaded"] } } },
    { "title": "IdleThreadStatus", "properties": { "type": { "enum": ["idle"] } } },
    { "title": "SystemErrorThreadStatus", "properties": { "type": { "enum": ["systemError"] } } },
    { "title": "ActiveThreadStatus", "properties": { 
        "type": { "enum": ["active"] },
        "activeFlags": { "items": { "$ref": "#/definitions/ThreadActiveFlag" } }
    }}
  ]
}
```

### 3.5 实验性 API 标记

部分通知被标记为实验性，使用 `#[experimental("...")]` 属性：

```rust
#[experimental("thread/realtime/started")]
ThreadRealtimeStarted => "thread/realtime/started" (v2::ThreadRealtimeStartedNotification),

#[experimental("thread/realtime/itemAdded")]
ThreadRealtimeItemAdded => "thread/realtime/itemAdded" (v2::ThreadRealtimeItemAddedNotification),
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心实现文件

| 文件路径 | 职责 |
|----------|------|
| `codex-rs/app-server-protocol/src/protocol/common.rs` | ServerNotification 枚举定义、宏实现 |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | 所有 v2 通知 payload 结构体定义 |
| `codex-rs/app-server-protocol/src/export.rs` | Schema 生成、过滤、导出逻辑 |
| `codex-rs/app-server-protocol/src/schema_fixtures.rs` | Schema fixture 读写、测试支持 |
| `codex-rs/app-server-protocol/src/jsonrpc_lite.rs` | JSON-RPC 基础类型定义 |

### 4.2 消费端文件

| 文件路径 | 职责 |
|----------|------|
| `codex-rs/app-server/src/outgoing_message.rs` | 服务器端通知发送实现 |
| `codex-rs/app-server/src/message_processor.rs` | 消息处理、通知路由 |
| `codex-rs/app-server-client/src/lib.rs` | 客户端通知接收处理 |
| `codex-rs/debug-client/src/reader.rs` | 调试客户端通知解析 |

### 4.3 测试与脚本

| 文件路径 | 职责 |
|----------|------|
| `codex-rs/app-server-protocol/tests/schema_fixtures.rs` | Schema fixture 一致性测试 |
| `codex-rs/app-server-protocol/src/bin/write_schema_fixtures.rs` | Schema 生成工具 |
| `codex-rs/app-server-protocol/src/bin/export.rs` | TypeScript/JSON 导出工具 |

### 4.4 生成产物

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/app-server-protocol/schema/json/ServerNotification.json` | 本研究文档目标文件 |
| `codex-rs/app-server-protocol/schema/typescript/ServerNotification.ts` | TypeScript 类型定义 |
| `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.schemas.json` | 完整 Schema Bundle |

---

## 5. 依赖与外部交互

### 5.1 上游依赖

```
ServerNotification
├── codex_protocol (核心协议类型)
│   ├── ThreadId, TurnId, ItemId
│   ├── TokenUsage, RateLimitSnapshot
│   ├── SandboxPolicy, ApprovalConfig
│   └── HookRunSummary, etc.
├── schemars (JSON Schema 生成)
├── ts_rs (TypeScript 类型生成)
├── serde (序列化/反序列化)
├── strum (字符串枚举宏)
└── codex_experimental_api_macros (实验性 API 标记)
```

### 5.2 下游消费者

```
ServerNotification
├── codex_app_server (服务器实现)
│   ├── 通知发送 (outgoing_message.rs)
│   ├── 消息处理 (message_processor.rs)
│   └── 线程管理 (thread_status.rs)
├── codex_app_server_client (客户端库)
│   └── 通知接收与解析
├── codex_tui (终端 UI)
│   └── 通知渲染处理
└── codex_vscode (VSCode 扩展)
    └── 通知处理与状态同步
```

### 5.3 协议版本兼容

- **v1 API**: 遗留 API，逐渐弃用
- **v2 API**: 当前主要开发版本，所有新功能在此添加
- **实验性 API**: 通过 `#[experimental("...")]` 标记，默认不暴露

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 Schema 膨胀风险

- **问题**: ServerNotification.json 已超 4500 行，包含 100+ 个定义
- **影响**: 生成时间增加，客户端解析负担加重
- **缓解**: 实验性 API 过滤机制，按需加载

#### 6.1.2 破坏性变更风险

- **问题**: ThreadItem 等核心类型的变更影响广泛
- **影响**: 客户端兼容性问题
- **缓解**: 严格的 fixture 测试，版本控制

#### 6.1.3 序列化性能

- **问题**: 大型通知（如包含完整 Thread 的 ThreadStarted）序列化开销大
- **影响**: 高并发场景性能瓶颈
- **缓解**: 使用 `#[serde(skip_serializing_if = "Option::is_none")]` 减少 payload

### 6.2 边界情况

#### 6.2.1 连接断开处理

```rust
// outgoing_message.rs
pub(crate) async fn connection_closed(&self, connection_id: ConnectionId) {
    let mut request_contexts = self.request_contexts.lock().await;
    request_contexts.retain(|request_id, _| request_id.connection_id != connection_id);
}
```

连接断开时，相关请求上下文被清理，但已发送的通知不会重传。

#### 6.2.2 实验性字段过滤

```rust
// export.rs
if !experimental_api {
    filter_experimental_schema(&mut bundle)?;
    filter_experimental_ts_tree(&mut files)?;
}
```

非实验性构建会完全移除实验性字段，可能导致数据丢失。

#### 6.2.3 通知顺序保证

- 同一连接内的通知按发送顺序到达
- 跨连接的通知顺序不保证
- 流式增量通知（如 AgentMessageDelta）必须按序处理

### 6.3 改进建议

#### 6.3.1 短期改进

1. **添加通知优先级标记**
   ```rust
   pub enum NotificationPriority {
       Critical,  // Error, ThreadClosed
       High,      // TurnCompleted, ItemCompleted
       Normal,    // 大多数通知
       Low,       // TokenUsageUpdated
   }
   ```

2. **优化大型 payload**
   - ThreadStartedNotification 中的 `turns` 字段默认空，仅在特定响应中填充
   - 考虑分页或延迟加载机制

3. **增强可观测性**
   - 添加通知发送/接收的 metrics
   - 记录通知丢弃率（当客户端缓冲区满时）

#### 6.3.2 中期改进

1. **通知压缩**
   - 对高频增量通知（AgentMessageDelta）启用压缩
   - 使用增量编码减少重复数据

2. **订阅机制**
   - 允许客户端订阅特定通知类型
   - 减少不必要的网络传输

3. **Schema 版本协商**
   - Initialize 时协商支持的 Schema 版本
   - 支持向后兼容的字段添加

#### 6.3.3 长期改进

1. **协议演进**
   - 考虑迁移到 gRPC 或 WebSocket 二进制协议
   - 保持 JSON 作为调试/开发选项

2. **类型安全增强**
   - 使用 Rust 的 typestate 模式确保通知发送时机正确
   - 编译期验证通知 payload 完整性

3. **文档自动化**
   - 从 Schema 自动生成交互式 API 文档
   - 集成示例代码和用例说明

---

## 7. 附录

### 7.1 通知方法名完整列表

```
error
thread/started
thread/status/changed
thread/archived
thread/unarchived
thread/closed
skills/changed
thread/name/updated
thread/tokenUsage/updated
turn/started
hook/started
turn/completed
hook/completed
turn/diff/updated
turn/plan/updated
item/started
item/autoApprovalReview/started
item/autoApprovalReview/completed
item/completed
item/agentMessage/delta
item/plan/delta
command/exec/outputDelta
item/commandExecution/outputDelta
item/commandExecution/terminalInteraction
item/fileChange/outputDelta
serverRequest/resolved
item/mcpToolCall/progress
mcpServer/oauthLogin/completed
account/updated
account/rateLimits/updated
app/list/updated
item/reasoning/summaryTextDelta
item/reasoning/summaryPartAdded
item/reasoning/textDelta
thread/compacted (deprecated)
model/rerouted
deprecationNotice
configWarning
fuzzyFileSearch/sessionUpdated
fuzzyFileSearch/sessionCompleted
thread/realtime/started (experimental)
thread/realtime/itemAdded (experimental)
thread/realtime/outputAudio/delta (experimental)
thread/realtime/error (experimental)
thread/realtime/closed (experimental)
windows/worldWritableWarning
windowsSandbox/setupCompleted
account/login/completed
rawResponseItem/completed (internal)
```

### 7.2 相关命令

```bash
# 重新生成 Schema
just write-app-server-schema

# 运行 Schema 测试
cargo test -p codex-app-server-protocol

# 生成实验性 Schema
just write-app-server-schema --experimental
```

### 7.3 参考文档

- `codex-rs/app-server-protocol/README.md`
- `codex-rs/app-server/README.md`
- `AGENTS.md` (App-Server API Development Best Practices 章节)
