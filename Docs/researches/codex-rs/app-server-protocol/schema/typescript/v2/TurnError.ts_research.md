# TurnError.ts Research

## 场景与职责

`TurnError` 是 App-Server Protocol v2 中用于表示回合（Turn）执行错误的结构化错误类型。它提供了详细的错误信息，包括用户友好的错误消息、机器可处理的错误代码分类以及可选的额外详情，用于故障诊断和错误处理。

主要使用场景包括：
- **错误报告**：当回合执行失败时，向客户端提供结构化的错误信息
- **错误分类**：通过 `CodexErrorInfo` 提供机器可处理的错误类型分类
- **故障诊断**：`additionalDetails` 提供技术细节，帮助调试问题
- **用户反馈**：`message` 提供用户友好的错误描述
- **错误处理策略**：客户端根据错误类型决定重试、降级或终止策略

## 功能点目的

该类型的核心目的是：

1. **结构化错误信息**：将错误信息组织为多个层次，便于不同用途
2. **错误分类标准化**：通过 `CodexErrorInfo` 枚举提供统一的错误分类体系
3. **可恢复性判断**：结合 `ErrorNotification` 中的 `will_retry` 字段，指示错误是否可恢复
4. **调试支持**：提供额外的技术详情，便于开发和运维人员诊断问题
5. **国际化准备**：结构化的错误信息便于后续添加多语言支持

与其他类型的关系：
- 作为 `Turn.error` 字段的类型，当 `TurnStatus` 为 `Failed` 时填充
- 被 `ErrorNotification` 包含，用于服务器向客户端报告错误
- 与 `CodexErrorInfo` 紧密关联，后者提供错误分类详情

## 具体技术实现

### TypeScript 类型定义

```typescript
export type TurnError = { 
  message: string, 
  codexErrorInfo: CodexErrorInfo | null, 
  additionalDetails: string | null, 
};
```

### Rust 源码定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS, Error)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
#[error("{message}")]
pub struct TurnError {
    pub message: String,
    pub codex_error_info: Option<CodexErrorInfo>,
    #[serde(default)]
    pub additional_details: Option<String>,
}
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `message` | string | 用户友好的错误消息，可直接展示给终端用户 |
| `codexErrorInfo` | CodexErrorInfo \| null | 机器可处理的错误分类信息，包含具体的错误类型和 HTTP 状态码（如适用） |
| `additionalDetails` | string \| null | 可选的额外技术详情，用于调试和故障诊断 |

### CodexErrorInfo 类型

`CodexErrorInfo` 提供标准化的错误分类：

```typescript
export type CodexErrorInfo = 
  | "contextWindowExceeded"
  | "usageLimitExceeded"
  | "serverOverloaded"
  | { "httpConnectionFailed": { httpStatusCode: number | null } }
  | { "responseStreamConnectionFailed": { httpStatusCode: number | null } }
  | "internalServerError"
  | "unauthorized"
  | "badRequest"
  | "threadRollbackFailed"
  | "sandboxError"
  | { "responseStreamDisconnected": { httpStatusCode: number | null } }
  | { "responseTooManyFailedAttempts": { httpStatusCode: number | null } }
  | "other";
```

### 派生宏特性

- `#[error("{message}")]`: 实现 `std::error::Error` trait，使用 message 作为错误描述
- `#[serde(default)]`: 为 `additional_details` 提供默认值（空字符串或 null）

## 关键代码路径与文件引用

### 协议定义

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs:3632-3641` | Rust 结构体定义 |
| `codex-rs/app-server-protocol/schema/typescript/v2/TurnError.ts` | TypeScript 类型定义 |
| `codex-rs/app-server-protocol/schema/typescript/v2/CodexErrorInfo.ts` | 错误分类枚举定义 |

### 错误使用场景

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs:3643-3653` | ErrorNotification 结构体，包含 TurnError |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Turn 结构体的 error 字段定义 |
| `codex-rs/app-server/src/bespoke_event_handling.rs` | 错误处理和通知发送 |

### 客户端处理

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui_app_server/src/chatwidget.rs` | TUI 错误展示处理 |
| `codex-rs/app-server-client/src/lib.rs` | 客户端错误处理 |

### 测试覆盖

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server/tests/` | 各种错误场景的集成测试 |

## 依赖与外部交互

### 内部依赖

```
TurnError
├── message: String
├── codex_error_info: Option<CodexErrorInfo>
│   ├── contextWindowExceeded
│   ├── usageLimitExceeded
│   ├── serverOverloaded
│   ├── httpConnectionFailed { httpStatusCode }
│   ├── responseStreamConnectionFailed { httpStatusCode }
│   ├── internalServerError
│   ├── unauthorized
│   ├── badRequest
│   ├── threadRollbackFailed
│   ├── sandboxError
│   ├── responseStreamDisconnected { httpStatusCode }
│   ├── responseTooManyFailedAttempts { httpStatusCode }
│   └── other
├── additional_details: Option<String>
├── std::error::Error (派生)
├── serde (Serialize, Deserialize)
├── schemars (JsonSchema)
└── ts_rs (TS)
```

### 协议集成

- **使用位置**：
  - `Turn.error`: 当回合失败时填充
  - `ErrorNotification.error`: 服务器主动报告错误时发送
- **关联字段**：`ErrorNotification.will_retry` 指示是否自动重试

### 错误分类映射

| 错误类型 | 典型场景 | 建议处理 |
|---------|---------|---------|
| `contextWindowExceeded` | 上下文窗口超限 | 提示用户简化输入或开启 compaction |
| `usageLimitExceeded` | 使用配额耗尽 | 提示用户检查配额或升级套餐 |
| `serverOverloaded` | 服务器过载 | 自动重试或提示稍后重试 |
| `httpConnectionFailed` | HTTP 连接失败 | 检查网络连接 |
| `unauthorized` | 认证失败 | 提示重新登录或检查 API Key |
| `sandboxError` | 沙箱执行错误 | 检查命令或文件权限 |

## 风险、边界与改进建议

### 潜在风险

1. **敏感信息泄露**：`additionalDetails` 可能包含敏感信息（如文件路径、内部状态），需要谨慎处理
2. **错误信息不一致**：不同错误场景下 message 的质量可能不一致
3. **国际化缺失**：当前错误消息为英文，缺乏多语言支持
4. **错误分类粒度**：某些错误可能被归类为过于宽泛的 "other"

### 边界情况

| 场景 | 行为 |
|------|------|
| 错误无分类 | `codexErrorInfo` 为 null 或 "other" |
| 无额外详情 | `additionalDetails` 为 null |
| 嵌套错误 | 可能包含多个层级的错误信息 |
| 网络错误 | HTTP 状态码可能为 null（连接未建立） |

### 改进建议

1. **敏感信息过滤**：在 `additionalDetails` 中添加自动过滤机制，移除敏感信息
2. **错误码体系**：引入数字错误码，便于客户端程序化处理和国际化
3. **错误恢复指南**：为每种错误类型添加建议的恢复操作
4. **错误追踪 ID**：添加唯一的错误追踪 ID，便于服务端日志关联
5. **错误频率限制**：对重复错误进行节流，避免错误风暴
6. **分级错误信息**：根据用户类型（终端用户/开发者）提供不同详细程度的错误信息
7. **错误上报机制**：客户端可选择将错误详情上报给服务端用于改进

### 监控指标建议

- 各错误类型的发生频率
- 错误恢复成功率
- 错误通知发送延迟
- 包含 `additionalDetails` 的错误比例
