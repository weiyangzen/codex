# CodexErrorInfo 类型研究文档

## 1. 场景与职责

### 1.1 使用场景

`CodexErrorInfo` 是 Codex 系统向客户端暴露错误信息的核心类型，广泛应用于以下场景：

- **API 错误响应**：当 App Server 处理请求失败时，返回结构化的错误信息
- **流式响应中断**：在 SSE (Server-Sent Events) 流中报告连接或处理错误
- **Turn 执行失败**：标记某个 Turn（对话轮次）因错误而失败
- **客户端错误处理**：为 CLI/TUI 客户端提供用户友好的错误分类和显示

### 1.2 核心职责

- **错误分类**：将各种底层错误归类为语义明确的错误类型
- **HTTP 状态透传**：在相关变体中透传上游 HTTP 状态码，便于客户端诊断
- **Turn 状态影响判断**：提供 `affects_turn_status()` 方法判断错误是否应标记 Turn 为失败
- **序列化兼容性**：通过 camelCase 命名规范确保与 TypeScript 客户端的兼容性

### 1.3 重要性

该类型是 Codex 错误处理体系的**核心组件**，直接影响：
- 用户体验（错误提示的清晰度）
- 调试效率（错误信息的完整性）
- 系统稳定性（错误恢复策略的制定）

---

## 2. 功能点目的

### 2.1 设计目标

| 目标 | 说明 |
|------|------|
| 语义化错误 | 将底层技术错误（HTTP 状态码、连接异常）映射为业务语义错误 |
| 可诊断性 | 保留原始 HTTP 状态码，便于问题追踪 |
| 类型安全 | 使用 Rust 枚举确保错误处理的完备性 |
| 序列化友好 | 支持 JSON 序列化和 TypeScript 类型生成 |

### 2.2 错误类型详解

| 错误类型 | 说明 | HTTP 状态码 |
|----------|------|-------------|
| `contextWindowExceeded` | 上下文窗口超出限制 | - |
| `usageLimitExceeded` | 使用配额已耗尽 | - |
| `serverOverloaded` | 服务器过载 | - |
| `httpConnectionFailed` | HTTP 连接失败 | 可选 |
| `responseStreamConnectionFailed` | 响应 SSE 流连接失败 | 可选 |
| `internalServerError` | 内部服务器错误 | - |
| `unauthorized` | 未授权（认证失败） | - |
| `badRequest` | 请求参数错误 | - |
| `threadRollbackFailed` | 线程回滚失败 | - |
| `sandboxError` | 沙箱执行错误 | - |
| `responseStreamDisconnected` | 响应流中途断开 | 可选 |
| `responseTooManyFailedAttempts` | 响应重试次数耗尽 | 可选 |
| `other` | 其他未分类错误 | - |

### 2.3 Turn 状态影响

```rust
impl CodexErrorInfo {
    /// Whether this error should mark the current turn as failed when replaying history.
    pub fn affects_turn_status(&self) -> bool {
        match self {
            Self::ThreadRollbackFailed => false,  // 回滚失败不影响 Turn 状态
            Self::ContextWindowExceeded | ... | Self::Other => true,
        }
    }
}
```

---

## 3. 具体技术实现

### 3.1 TypeScript 类型定义

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

### 3.2 Rust 源类型定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs (L131-L171)
/// This translation layer make sure that we expose codex error code in camel case.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum CodexErrorInfo {
    ContextWindowExceeded,
    UsageLimitExceeded,
    ServerOverloaded,
    HttpConnectionFailed {
        #[serde(rename = "httpStatusCode")]
        #[ts(rename = "httpStatusCode")]
        http_status_code: Option<u16>,
    },
    /// Failed to connect to the response SSE stream.
    ResponseStreamConnectionFailed {
        #[serde(rename = "httpStatusCode")]
        #[ts(rename = "httpStatusCode")]
        http_status_code: Option<u16>,
    },
    InternalServerError,
    Unauthorized,
    BadRequest,
    ThreadRollbackFailed,
    SandboxError,
    /// The response SSE stream disconnected in the middle of a turn before completion.
    ResponseStreamDisconnected {
        #[serde(rename = "httpStatusCode")]
        #[ts(rename = "httpStatusCode")]
        http_status_code: Option<u16>,
    },
    /// Reached the retry limit for responses.
    ResponseTooManyFailedAttempts {
        #[serde(rename = "httpStatusCode")]
        #[ts(rename = "httpStatusCode")]
        http_status_code: Option<u16>,
    },
    Other,
}
```

### 3.3 核心协议层定义

```rust
// codex-rs/protocol/src/protocol.rs (L1541-L1589)
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "snake_case")]
#[ts(rename_all = "snake_case")]
pub enum CodexErrorInfo {
    ContextWindowExceeded,
    UsageLimitExceeded,
    ServerOverloaded,
    HttpConnectionFailed { http_status_code: Option<u16> },
    ResponseStreamConnectionFailed { http_status_code: Option<u16> },
    InternalServerError,
    Unauthorized,
    BadRequest,
    SandboxError,
    ResponseStreamDisconnected { http_status_code: Option<u16> },
    ResponseTooManyFailedAttempts { http_status_code: Option<u16> },
    ThreadRollbackFailed,
    Other,
}
```

### 3.4 类型转换层

```rust
// v2.rs (L173-L199)
impl From<CoreCodexErrorInfo> for CodexErrorInfo {
    fn from(value: CoreCodexErrorInfo) -> Self {
        match value {
            CoreCodexErrorInfo::ContextWindowExceeded => CodexErrorInfo::ContextWindowExceeded,
            CoreCodexErrorInfo::UsageLimitExceeded => CodexErrorInfo::UsageLimitExceeded,
            // ... 其他变体映射
            CoreCodexErrorInfo::Other => CodexErrorInfo::Other,
        }
    }
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 类型定义位置

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/protocol/src/protocol.rs` (L1541-L1589) | 核心协议层定义（snake_case） |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` (L131-L199) | v2 API 层定义（camelCase） |
| `codex-rs/app-server-protocol/schema/typescript/v2/CodexErrorInfo.ts` | 生成的 TypeScript 类型 |

### 4.2 使用位置

| 文件路径 | 使用场景 |
|----------|----------|
| `codex-rs/core/src/error.rs` | 错误转换和处理 |
| `codex-rs/core/src/codex.rs` | Codex 主逻辑错误处理 |
| `codex-rs/tui/src/chatwidget.rs` | TUI 错误显示 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | App Server 适配器错误处理 |
| `codex-rs/app-server/src/bespoke_event_handling.rs` | 自定义事件错误处理 |

### 4.3 测试覆盖

| 文件路径 | 测试内容 |
|----------|----------|
| `codex-rs/core/src/error_tests.rs` | 错误类型单元测试 |
| `codex-rs/core/src/codex_tests.rs` | 集成测试中的错误场景 |

---

## 5. 依赖与外部交互

### 5.1 内部依赖

| 依赖项 | 说明 |
|--------|------|
| `serde` | 序列化/反序列化 |
| `schemars::JsonSchema` | JSON Schema 生成 |
| `ts_rs::TS` | TypeScript 类型生成 |
| `thiserror::Error` | 错误派生宏 |

### 5.2 错误传播链

```
┌─────────────────┐
│  OpenAI API     │ ← 原始 HTTP 错误
│  (Responses API)│
└────────┬────────┘
         │ HTTP Status Code
         ▼
┌─────────────────┐
│  Codex Core     │ ← 转换为 CoreCodexErrorInfo
│  (protocol.rs)  │
└────────┬────────┘
         │ 类型转换
         ▼
┌─────────────────┐
│  App Server     │ ← 转换为 CodexErrorInfo (v2)
│  (v2.rs)        │
└────────┬────────┘
         │ JSON + TypeScript
         ▼
┌─────────────────┐
│  Client         │ ← 消费错误信息
│  (CLI/TUI)      │
└─────────────────┘
```

### 5.3 与 TurnError 的关系

```typescript
// TurnError.ts
export type TurnError = {
    code: CodexErrorInfo;
    message: string;
};
```

`CodexErrorInfo` 作为 `TurnError` 的 `code` 字段，提供机器可读的错误分类。

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 严重程度 | 说明 |
|------|----------|------|
| 变体膨胀 | 中 | 错误类型较多，可能导致 match 语句冗长 |
| HTTP 状态码可选 | 低 | 部分变体缺少 HTTP 状态码时诊断信息不足 |
| 字符串错误信息 | 低 | `Other` 变体无法携带额外上下文 |

### 6.2 边界条件

- **HTTP 状态码范围**：`httpStatusCode` 使用 `u16`，有效范围 100-599
- **null vs undefined**：TypeScript 类型使用 `number | null`，需明确处理 `null` 情况
- **序列化格式**：带数据的变体序列化为对象格式，需与简单字符串变体区分处理

### 6.3 改进建议

1. **统一错误数据结构**
   ```rust
   pub enum CodexErrorInfo {
       ContextWindowExceeded { details: Option<String> },
       HttpConnectionFailed { 
           http_status_code: Option<u16>,
           message: Option<String>,  // 添加可读错误信息
       },
       // ...
   }
   ```

2. **添加错误代码枚举**
   ```typescript
   export const CodexErrorCode = {
       ContextWindowExceeded: "contextWindowExceeded",
       // ...
   } as const;
   
   export type CodexErrorCode = typeof CodexErrorCode[keyof typeof CodexErrorCode];
   ```

3. **改进 TypeScript 类型**
   ```typescript
   // 使用 discriminated union 增强类型安全
   export type CodexErrorInfo = 
       | { type: "contextWindowExceeded" }
       | { type: "httpConnectionFailed"; httpStatusCode: number | null }
       // ...
   ```

4. **添加重试建议**
   ```rust
   impl CodexErrorInfo {
       pub fn is_retryable(&self) -> bool {
           matches!(self, 
               Self::ServerOverloaded |
               Self::HttpConnectionFailed { .. } |
               Self::ResponseStreamDisconnected { .. }
           )
       }
   }
   ```

5. **国际化支持**
   - 添加错误代码到本地化消息的映射
   - 支持客户端根据错误代码显示翻译后的消息

---

## 附录：JSON Schema 示例

```json
{
    "oneOf": [
        { "type": "string", "enum": ["contextWindowExceeded", "usageLimitExceeded", ...] },
        {
            "type": "object",
            "properties": {
                "httpConnectionFailed": {
                    "type": "object",
                    "properties": {
                        "httpStatusCode": { "type": ["integer", "null"] }
                    }
                }
            }
        }
    ]
}
```
