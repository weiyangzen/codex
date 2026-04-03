# ItemCompletedNotification.json 研究文档

## 场景与职责

`ItemCompletedNotification` 是 Codex App Server Protocol v2 中的核心服务器通知类型，用于通知客户端某个 ThreadItem（线程项）已完成执行。ThreadItem 代表对话线程中的各种操作单元，包括用户消息、代理消息、命令执行、文件变更、MCP 工具调用等。

该通知是 Codex 事件流的核心组成部分，使客户端能够实时跟踪对话中各项操作的完成状态。

## 功能点目的

1. **操作完成通知**：通知客户端特定操作项已完成（成功或失败）
2. **状态同步**：同步操作项的最终状态、输出结果和元数据
3. **历史记录构建**：客户端通过收集 completed 通知构建对话历史
4. **UI 更新**：触发客户端 UI 更新，显示操作结果（如命令输出、文件变更等）
5. **流程控制**：支持基于操作完成的后续流程触发

## 具体技术实现

### 数据结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "properties": {
    "item": { "$ref": "#/definitions/ThreadItem" },
    "threadId": { "type": "string" },
    "turnId": { "type": "string" }
  },
  "required": ["item", "threadId", "turnId"]
}
```

### ThreadItem 类型定义

`ItemCompletedNotification` 包含一个完整的 `ThreadItem`，支持以下类型（通过 `type` 字段区分）：

| 类型 | 说明 | 关键字段 |
|------|------|----------|
| `userMessage` | 用户消息 | `content` (UserInput 数组) |
| `agentMessage` | 代理消息 | `text`, `phase`, `memoryCitation` |
| `plan` | 计划项（实验性） | `text` |
| `reasoning` | 推理过程 | `content`, `summary` |
| `commandExecution` | 命令执行 | `command`, `cwd`, `status`, `exitCode`, `aggregatedOutput` |
| `fileChange` | 文件变更 | `changes`, `status` |
| `mcpToolCall` | MCP 工具调用 | `server`, `tool`, `arguments`, `result`, `error` |
| `dynamicToolCall` | 动态工具调用 | `tool`, `arguments`, `contentItems`, `success` |
| `collabAgentToolCall` | 协作代理工具调用 | `tool`, `senderThreadId`, `receiverThreadIds`, `agentsStates` |
| `webSearch` | 网页搜索 | `query`, `action` |
| `imageView` | 图片查看 | `path` |
| `imageGeneration` | 图片生成 | `status`, `result`, `revisedPrompt` |

### 关键枚举类型

**CommandExecutionStatus**: `inProgress`, `completed`, `failed`, `declined`

**PatchApplyStatus**: `inProgress`, `completed`, `failed`, `declined`

**McpToolCallStatus**: `inProgress`, `completed`, `failed`

**DynamicToolCallStatus**: `inProgress`, `completed`, `failed`

**CollabAgentToolCallStatus**: `inProgress`, `completed`, `failed`

**CollabAgentTool**: `spawnAgent`, `sendInput`, `resumeAgent`, `wait`, `closeAgent`

**CommandAction**（命令解析结果）：
- `read`: 读取文件操作
- `listFiles`: 列出文件
- `search`: 搜索操作
- `unknown`: 未知操作

### 协议映射

Rust 结构体定义（v2.rs）：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ItemCompletedNotification {
    pub item: ThreadItem,
    pub thread_id: String,
    pub turn_id: String,
}
```

服务器通知枚举（common.rs）：
```rust
server_notification_definitions! {
    ItemStarted => "item/started" (v2::ItemStartedNotification),
    ItemCompleted => "item/completed" (v2::ItemCompletedNotification),
    // ...
}
```

Wire 格式：`method: "item/completed"`

## 关键代码路径与文件引用

### 核心定义文件

1. **JSON Schema**: `codex-rs/app-server-protocol/schema/json/v2/ItemCompletedNotification.json`
2. **Rust 结构体**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 4814-4818)
3. **ThreadItem 枚举**: `v2.rs` 行 4117-4258
4. **协议枚举**: `codex-rs/app-server-protocol/src/protocol/common.rs` (行 891-894)

### 事件处理代码

**bespoke_event_handling.rs** 中的关键处理逻辑：

1. **DynamicToolCallResponse 处理**（行 899-937）：
   - 将动态工具调用响应转换为 `ItemCompletedNotification`
   - 设置状态（`Completed` 或 `Failed`）
   - 包含执行时长和内容项

2. **McpToolCallEnd 处理**（行 951-960）：
   - 构造 MCP 工具调用完成通知
   - 包含结果或错误信息

3. **CollabAgentSpawnEnd 处理**（行 983-999）：
   - 处理协作代理工具调用完成
   - 更新代理状态映射

### 测试文件

- `codex-rs/app-server/tests/suite/v2/turn_start.rs`
- `codex-rs/app-server/tests/suite/v2/thread_shell_command.rs`
- `codex-rs/app-server/tests/suite/v2/review.rs`
- `codex-rs/tui_app_server/src/chatwidget/tests.rs`

## 依赖与外部交互

### 内部依赖

1. **核心协议**: `codex_protocol::items::TurnItem`, `codex_protocol::protocol::EventMsg`
2. **MCP 集成**: `rmcp` 库用于 MCP 工具调用
3. **序列化**: `serde`, `serde_json`
4. **类型生成**: `ts-rs`, `schemars`

### 外部交互

| 组件 | 交互方式 | 说明 |
|------|----------|------|
| TUI 客户端 | WebSocket | 实时显示操作结果 |
| VSCode 扩展 | JSON-RPC | 更新编辑器状态 |
| 测试框架 | 事件断言 | 验证操作完成 |

### 生成产物

- TypeScript: `typescript/v2/ItemCompletedNotification.ts`
- 合并 Schema: `json/codex_app_server_protocol.v2.schemas.json`

## 风险、边界与改进建议

### 潜在风险

1. **大负载传输**: `aggregatedOutput` 可能包含大量命令输出数据，可能导致：
   - 网络传输延迟
   - 内存占用过高
   - JSON 序列化/反序列化性能问题

2. **状态竞争**: 客户端可能同时收到 `ItemStarted` 和 `ItemCompleted`，需正确处理时序

3. **错误处理**: `error` 字段格式不一致（McpToolCallError vs 简单字符串）

### 边界情况

1. **空结果**: 某些操作可能返回空结果，客户端需优雅处理
2. **部分失败**: 批量操作（如多个文件变更）可能部分成功
3. **超时**: 长时间运行的操作可能超时，状态为 `failed`
4. **并发**: 同一 turn 中多个 item 可能并发完成

### 改进建议

1. **分页/流式传输**: 对于大输出，考虑分片传输或提供单独的资源端点
2. **压缩**: 对 `aggregatedOutput` 启用压缩
3. **摘要模式**: 提供摘要模式，只返回关键信息，详情按需获取
4. **统一错误格式**: 标准化所有 error 字段格式
5. **进度通知**: 对于长时间运行的操作，添加进度百分比
6. **幂等性**: 添加唯一标识防止重复处理

### 性能优化

```rust
// 当前：完整输出内联在通知中
pub struct CommandExecutionThreadItem {
    pub aggregated_output: Option<String>,  // 可能很大
}

// 建议：可选引用，大输出单独获取
pub struct CommandExecutionThreadItem {
    pub output_summary: Option<String>,
    pub output_ref: Option<String>,  // 引用 ID，按需获取完整输出
}
```

### 监控指标

建议添加的指标：
- Item 类型分布
- 平均完成时间
- 失败率
- 输出大小分布
- 通知延迟
