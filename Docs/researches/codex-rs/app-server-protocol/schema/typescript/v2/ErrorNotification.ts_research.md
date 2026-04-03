# ErrorNotification.ts Research Document

## 场景与职责

`ErrorNotification` 是 Codex App-Server Protocol v2 API 中用于向客户端通知错误事件的数据结构。当服务器在处理线程（Thread）或回合（Turn）过程中遇到错误时，会通过此通知类型将错误信息推送给客户端。

与普通的错误响应不同，`ErrorNotification` 是一种服务器主动推送的通知（Notification），用于处理异步流程中发生的错误，特别是那些可能在请求-响应周期之外发生的错误。

## 功能点目的

该类型的主要目的是：

1. **异步错误报告**: 在异步处理流程中向客户端报告错误，不阻塞主流程
2. **错误上下文传递**: 提供完整的错误上下文，包括关联的线程 ID 和回合 ID
3. **重试意图指示**: 通过 `willRetry` 字段告知客户端服务器是否会自动重试
4. **结构化错误信息**: 使用 `TurnError` 类型提供结构化的错误详情

## 具体技术实现

### 数据结构定义

```typescript
// ErrorNotification.ts
import type { TurnError } from "./TurnError";

export type ErrorNotification = { 
  error: TurnError, 
  willRetry: boolean, 
  threadId: string, 
  turnId: string, 
};
```

### 关键字段说明

| 字段名 | 类型 | 必填 | 说明 |
|--------|------|------|------|
| `error` | `TurnError` | 是 | 详细的错误信息，包含错误消息、Codex 错误代码和附加详情 |
| `willRetry` | `boolean` | 是 | 指示服务器是否会自动重试该操作。如果为 `true`，此错误不会中断回合 |
| `threadId` | `string` | 是 | 发生错误的线程标识符 |
| `turnId` | `string` | 是 | 发生错误的回合标识符 |

#### error 字段详细说明

`TurnError` 是一个结构化的错误类型：

```typescript
export type TurnError = { 
  message: string, 
  codexErrorInfo: CodexErrorInfo | null, 
  additionalDetails: string | null, 
};
```

- `message`: 人类可读的错误描述
- `codexErrorInfo`: Codex 特定的错误代码信息，包含具体的错误类型（如 `contextWindowExceeded`, `serverOverloaded` 等）
- `additionalDetails`: 额外的错误详情，可能包含技术调试信息

#### willRetry 字段详细说明

- `true`: 错误是暂时的（如网络超时、服务器过载），服务器将自动重试，客户端可以继续等待
- `false`: 错误是致命的（如无效参数、权限不足），服务器不会重试，客户端应该中断当前操作或通知用户

### Rust 端对应实现

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ErrorNotification {
    pub error: TurnError,
    // Set to true if the error is transient and the app-server process will automatically retry.
    // If true, this will not interrupt a turn.
    pub will_retry: bool,
    pub thread_id: String,
    pub turn_id: String,
}

// TurnError 定义
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct TurnError {
    pub message: String,
    pub codex_error_info: Option<CodexErrorInfo>,
    pub additional_details: Option<String>,
}
```

## 关键代码路径与文件引用

- **TypeScript 源文件**: `codex-rs/app-server-protocol/schema/typescript/v2/ErrorNotification.ts`
- **TypeScript 依赖**: 
  - `codex-rs/app-server-protocol/schema/typescript/v2/TurnError.ts`
  - `codex-rs/app-server-protocol/schema/typescript/v2/CodexErrorInfo.ts`
- **Rust 源文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs`
  - `ErrorNotification` 结构体定义（约第 3646-3653 行）
  - `TurnError` 结构体定义

## 依赖与外部交互

### 上游依赖

1. **TurnError**: 包含具体的错误信息
2. **CodexErrorInfo**: 定义了 Codex 特定的错误代码枚举

### 下游消费

1. **客户端错误处理**: 客户端根据此通知更新 UI，显示错误信息
2. **日志系统**: 错误通知被记录用于调试和监控
3. **重试逻辑**: 客户端根据 `willRetry` 决定是否显示重试按钮或自动重试

### 相关通知类型

- `ThreadRealtimeErrorNotification`: 实时音频会话的错误通知
- `ConfigWarningNotification`: 配置警告通知

### 序列化行为

- 使用 camelCase 命名规范
- 作为服务器推送通知的一部分，通常通过 WebSocket 或 SSE 发送

## 风险、边界与改进建议

### 潜在风险

1. **通知丢失**: 如果客户端在错误发生时未连接，可能错过错误通知
2. **重复通知**: 重试机制可能导致同一错误的多次通知
3. **敏感信息泄露**: `additionalDetails` 可能包含敏感信息，需要注意过滤
4. **客户端处理不一致**: 不同客户端可能对 `willRetry` 的处理逻辑不同

### 边界情况

1. **未知线程/回合**: 如果客户端收到不认识的 `threadId` 或 `turnId`，应优雅处理
2. **嵌套错误**: 错误处理过程中可能发生新的错误，需要防止无限循环
3. **大量错误**: 系统故障时可能产生大量错误通知，需要限流机制

### 改进建议

1. **添加错误 ID**: 添加唯一错误标识符，便于追踪和去重
2. **添加时间戳**: 记录错误发生的时间
3. **错误分级**: 添加 `severity` 字段（error/warning/info）区分错误严重程度
4. **建议操作**: 添加 `suggestedAction` 字段指导用户如何处理错误
5. **错误聚合**: 对于重复错误，考虑聚合发送而非逐个通知
6. **国际化支持**: 错误消息支持多语言

### 扩展示例

```typescript
// 建议的扩展版本
export type ErrorNotification = { 
  errorId: string;  // 新增：唯一错误 ID
  error: TurnError;
  willRetry: boolean;
  threadId: string;
  turnId: string;
  timestamp: number;  // 新增：错误发生时间戳
  severity: "critical" | "error" | "warning" | "info";  // 新增：严重程度
  suggestedAction?: string;  // 新增：建议操作
  retryCount?: number;  // 新增：已重试次数
  maxRetries?: number;  // 新增：最大重试次数
};
```
