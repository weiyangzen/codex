# McpToolCallProgressNotification.json 研究文档

## 场景与职责

`McpToolCallProgressNotification.json` 是 Codex 应用服务器协议 v2 的 JSON Schema 定义文件，用于描述 MCP (Model Context Protocol) 工具调用进度通知的结构。

该通知用于向客户端实时推送 MCP 工具调用的执行进度，支持长时间运行的工具调用场景，提供用户反馈和进度追踪能力。

## 功能点目的

1. **进度实时推送**: 在 MCP 工具调用执行过程中，向客户端发送进度更新
2. **用户体验优化**: 为长时间运行的工具调用提供视觉反馈
3. **调试支持**: 帮助开发者和用户了解工具调用的执行状态
4. **上下文关联**: 通过 `threadId`、`turnId` 和 `itemId` 精确定位到具体的调用上下文

## 具体技术实现

### 数据结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "properties": {
    "itemId": { "type": "string" },
    "message": { "type": "string" },
    "threadId": { "type": "string" },
    "turnId": { "type": "string" }
  },
  "required": ["itemId", "message", "threadId", "turnId"],
  "title": "McpToolCallProgressNotification",
  "type": "object"
}
```

### 字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `itemId` | string | 是 | MCP 工具调用项的唯一标识符，用于关联到具体的工具调用 |
| `message` | string | 是 | 进度消息，描述当前执行状态或进度信息 |
| `threadId` | string | 是 | 所属线程 ID，标识对话上下文 |
| `turnId` | string | 是 | 所属回合 ID，标识具体的对话回合 |

### Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs:4950
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct McpToolCallProgressNotification {
    pub item_id: String,
    pub message: String,
    pub thread_id: String,
    pub turn_id: String,
}
```

### 通知注册

```rust
// common.rs 行 906
McpToolCallProgress => "item/mcpToolCall/progress" (v2::McpToolCallProgressNotification)
```

## 关键代码路径与文件引用

### 协议定义
- **Rust 结构体**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 4950-4958)
- **JSON Schema**: `codex-rs/app-server-protocol/schema/json/v2/McpToolCallProgressNotification.json`
- **通知注册**: `codex-rs/app-server-protocol/src/protocol/common.rs` (行 906)

### 发送方
- **MCP 工具执行器**: 在工具调用执行过程中发送进度更新
- **服务器通知系统**: 通过 `ServerNotification` 枚举分发

### 接收方
- **客户端通知处理器**: 实现 `ServerNotification` 的处理逻辑
- **UI 组件**: 显示进度消息给用户

## 依赖与外部交互

### 上游依赖
1. **MCP 协议实现**: 依赖 MCP 协议的工具调用机制
2. **通知基础设施**: 依赖服务器的 WebSocket/SSE 通知通道
3. **线程/回合管理**: 需要准确的线程和回合上下文

### 下游使用方
1. **客户端 UI**: 显示进度指示器和消息
2. **日志系统**: 记录工具调用执行过程
3. **调试工具**: 用于问题诊断和性能分析

### 相关数据结构
- **McpToolCallThreadItem**: 表示 MCP 工具调用的线程项
- **McpToolCallStatus**: 工具调用状态枚举 (`inProgress`, `completed`, `failed`)

## 风险、边界与改进建议

### 潜在风险
1. **消息频率**: 高频进度更新可能导致网络拥塞或 UI 卡顿
2. **消息大小**: `message` 字段无长度限制，可能包含大量文本
3. **时序问题**: 进度通知可能在工具调用完成后才到达客户端

### 边界情况
1. **重复通知**: 同一 `itemId` 可能收到多个进度通知
2. **空消息**: `message` 字段理论上可能为空字符串
3. **过期通知**: 客户端可能收到已关闭线程的进度通知

### 改进建议

#### 1. 添加进度百分比
```json
{
  "itemId": "...",
  "message": "Processing...",
  "progressPercent": 45,
  "threadId": "...",
  "turnId": "..."
}
```

#### 2. 添加时间戳
```json
{
  "itemId": "...",
  "message": "...",
  "timestamp": 1712345678,
  "threadId": "...",
  "turnId": "..."
}
```

#### 3. 添加阶段信息
```json
{
  "itemId": "...",
  "message": "...",
  "stage": "validation",
  "stages": ["validation", "execution", "cleanup"],
  "threadId": "...",
  "turnId": "..."
}
```

#### 4. 节流机制
建议实现客户端或服务器端的通知节流机制，限制单位时间内的通知数量。

### 最佳实践
1. **消息简洁**: 保持进度消息简洁明了
2. **国际化准备**: 考虑消息内容的国际化支持
3. **日志级别**: 区分用户可见进度和调试信息
4. **超时处理**: 客户端应实现通知超时机制，避免无限等待

### 相关通知
- `ItemStartedNotification` - 工具调用开始
- `ItemCompletedNotification` - 工具调用完成
- `McpServerOauthLoginCompletedNotification` - OAuth 登录完成
