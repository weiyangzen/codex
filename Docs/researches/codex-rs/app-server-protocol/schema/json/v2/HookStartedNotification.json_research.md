# HookStartedNotification.json 研究文档

## 场景与职责

`HookStartedNotification` 是 Codex App Server Protocol v2 中定义的服务器通知类型，用于在 Hook（钩子）开始执行时向客户端发送通知。Hook 系统是 Codex 提供的扩展机制，允许在特定事件（如会话开始、用户提示提交、停止等）发生时执行自定义逻辑。

该通知属于服务器主动推送给客户端的消息流，用于实时同步 Hook 的执行状态。

## 功能点目的

1. **Hook 生命周期管理**：通知客户端某个 Hook 开始执行，使客户端能够跟踪 Hook 的执行进度
2. **执行上下文传递**：提供 Hook 的完整执行上下文，包括事件类型、处理器类型、执行模式等
3. **UI 状态同步**：支持客户端 UI 展示 Hook 执行状态（如加载指示器、进度条等）
4. **调试和监控**：为开发者提供 Hook 执行的详细元数据，便于调试和性能监控

## 具体技术实现

### 数据结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "properties": {
    "run": { "$ref": "#/definitions/HookRunSummary" },
    "threadId": { "type": "string" },
    "turnId": { "type": ["string", "null"] }
  },
  "required": ["run", "threadId"]
}
```

### 核心定义

**HookRunSummary** 包含以下关键字段：

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | string | Hook 执行实例的唯一标识 |
| `eventName` | enum | 触发 Hook 的事件名称：`sessionStart`, `userPromptSubmit`, `stop` |
| `handlerType` | enum | 处理器类型：`command`, `prompt`, `agent` |
| `executionMode` | enum | 执行模式：`sync`（同步）, `async`（异步） |
| `scope` | enum | 作用域：`thread`（线程级）, `turn`（回合级） |
| `sourcePath` | string | Hook 定义文件的路径 |
| `displayOrder` | int64 | 显示顺序，用于 UI 排序 |
| `status` | enum | 状态：`running`, `completed`, `failed`, `blocked`, `stopped` |
| `startedAt` | int64 | 开始时间戳（Unix 毫秒） |
| `completedAt` | int64/null | 完成时间戳（可选） |
| `durationMs` | int64/null | 执行时长（可选） |
| `entries` | array | Hook 输出条目列表 |

**HookOutputEntry** 结构：
- `kind`: 条目类型 - `warning`, `stop`, `feedback`, `context`, `error`
- `text`: 文本内容

### 协议映射

在 Rust 源码中对应类型：

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct HookStartedNotification {
    pub thread_id: String,
    pub turn_id: Option<String>,
    pub run: HookRunSummary,
}
```

服务器通知枚举定义（common.rs）：
```rust
server_notification_definitions! {
    HookStarted => "hook/started" (v2::HookStartedNotification),
    HookCompleted => "hook/completed" (v2::HookCompletedNotification),
    // ...
}
```

## 关键代码路径与文件引用

### 核心定义文件

1. **JSON Schema**: `codex-rs/app-server-protocol/schema/json/v2/HookStartedNotification.json`
2. **Rust 结构体**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 4679-4683)
3. **协议枚举**: `codex-rs/app-server-protocol/src/protocol/common.rs` (行 886-888)

### 相关类型定义

- `HookRunSummary`: `v2.rs` 行 404-418
- `HookOutputEntry`: `v2.rs` 行 387-390
- `HookEventName`: `v2.rs` 行 349-352（枚举定义）
- `HookHandlerType`: `v2.rs` 行 355-358
- `HookExecutionMode`: `v2.rs` 行 361-364
- `HookScope`: `v2.rs` 行 367-370
- `HookRunStatus`: `v2.rs` 行 373-376
- `HookOutputEntryKind`: `v2.rs` 行 379-382

### 使用场景

Hook 通知在以下场景触发：
- 会话开始时（`sessionStart`）
- 用户提交提示时（`userPromptSubmit`）
- 会话停止时（`stop`）

## 依赖与外部交互

### 内部依赖

1. **核心协议库**: `codex_protocol::protocol::HookRunSummary` 等核心类型
2. **序列化**: `serde` 用于 JSON 序列化/反序列化
3. **TypeScript 生成**: `ts-rs` 用于生成 TypeScript 类型定义
4. **JSON Schema**: `schemars` 用于生成 JSON Schema

### 外部交互

- **客户端**: 通过 WebSocket/SSE 接收通知
- **Hook 系统**: 由 Hook 执行器触发通知
- **TUI 应用**: `tui_app_server` 消费通知更新界面

### 生成文件

- TypeScript: `codex-rs/app-server-protocol/schema/typescript/v2/HookStartedNotification.ts`
- 合并 Schema: `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json`

## 风险、边界与改进建议

### 潜在风险

1. **状态不一致**: `turnId` 为可选字段，在 thread-scoped Hook 中可能为 null，客户端需正确处理
2. **时间戳精度**: `startedAt` 使用 int64 毫秒时间戳，需注意时区和精度问题
3. **输出条目膨胀**: `entries` 数组可能包含大量条目，需考虑传输性能和存储成本

### 边界情况

1. **重复通知**: 同一 Hook 可能因重试机制发送多次 started 通知
2. **并发执行**: 多个 Hook 可能同时执行，客户端需正确处理并发通知
3. **长时间运行**: async 模式的 Hook 可能长时间运行，需考虑连接超时

### 改进建议

1. **添加版本字段**: 考虑添加 Hook 定义版本，便于兼容性处理
2. **压缩输出**: 对于大量 entries，考虑使用压缩或分页机制
3. **心跳机制**: 对于长时间运行的 Hook，添加心跳通知防止连接超时
4. **元数据扩展**: 考虑添加用户自定义元数据字段，增强扩展性
5. **性能指标**: 添加更多性能指标（如 CPU/内存使用），便于监控

### 相关 TODO

源码中的 TODO 注释（`ItemGuardianApprovalReviewStartedNotification` 等）提到：
> Attach guardian review state to the reviewed tool item's lifecycle instead of sending separate standalone review notifications

这表明未来可能将类似的审查状态直接附加到工具项生命周期中，而不是发送独立的通知。
