# ChatgptAuthTokensRefreshReason 类型研究文档

## 1. 场景与职责

### 1.1 使用场景

`ChatgptAuthTokensRefreshReason` 是一个枚举类型，用于描述 ChatGPT 认证令牌刷新请求的原因。它主要应用于以下场景：

- **外部认证模式下的令牌刷新**：当 Codex 使用外部管理的 ChatGPT 认证令牌（而非内部管理的 OAuth 流程）时，需要明确告知客户端刷新令牌的原因
- **401 Unauthorized 错误处理**：当 Codex 向后端服务发起请求时收到 401 未授权响应，触发令牌刷新流程
- **多账户/多工作区管理**：帮助客户端识别需要刷新哪个账户的令牌

### 1.2 核心职责

- 为 `account/login/start` 方法的 `chatgptAuthTokens` 变体提供刷新原因的标准化枚举
- 支持客户端理解令牌刷发的触发条件，以便做出适当的用户界面响应
- 作为 `ChatgptAuthTokensRefreshParams` 结构体的核心字段，构成完整的刷新请求参数

### 1.3 使用限制

该类型标记为 **实验性 API**，文档中明确标注 `[UNSTABLE] FOR OPENAI INTERNAL USE ONLY - DO NOT USE`，表示仅供 OpenAI 内部使用，外部开发者不应依赖此 API。

---

## 2. 功能点目的

### 2.1 设计目标

| 目标 | 说明 |
|------|------|
| 标准化刷新原因 | 将令牌刷新触发条件编码为类型安全的枚举，避免使用魔法字符串 |
| 支持诊断和调试 | 客户端可以根据刷新原因记录日志、展示提示信息或执行特定的恢复逻辑 |
| 向后兼容扩展 | 枚举结构便于未来添加新的刷新原因而不破坏现有接口 |

### 2.2 当前支持的刷新原因

| 枚举值 | 说明 |
|--------|------|
| `unauthorized` | Codex 尝试后端请求时收到 401 Unauthorized 响应，表明当前访问令牌已过期或无效 |

### 2.3 与相关类型的关系

```
ChatgptAuthTokensRefreshParams
├── reason: ChatgptAuthTokensRefreshReason  ← 本类型
└── previous_account_id: Option<String>

LoginAccountParams::ChatgptAuthTokens
├── access_token: String
└── refresh_token: String
```

---

## 3. 具体技术实现

### 3.1 TypeScript 类型定义

```typescript
export type ChatgptAuthTokensRefreshReason = "unauthorized";
```

### 3.2 Rust 源类型定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum ChatgptAuthTokensRefreshReason {
    /// Codex attempted a backend request and received `401 Unauthorized`.
    Unauthorized,
}
```

### 3.3 序列化行为

- **JSON 表示**：使用 camelCase 命名规范，序列化为 `"unauthorized"`
- **TypeScript 生成**：通过 `ts-rs` 库自动生成，导出为字符串字面量联合类型

### 3.4 相关结构体

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ChatgptAuthTokensRefreshParams {
    pub reason: ChatgptAuthTokensRefreshReason,
    /// Workspace/account identifier that Codex was previously using.
    #[ts(optional = nullable)]
    pub previous_account_id: Option<String>,
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 类型定义位置

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` (L1653-L1659) | Rust 源类型定义 |
| `codex-rs/app-server-protocol/schema/typescript/v2/ChatgptAuthTokensRefreshReason.ts` | 生成的 TypeScript 类型 |
| `codex-rs/app-server-protocol/schema/json/v2/` | JSON Schema 定义（自动生成） |

### 4.2 使用位置

| 文件路径 | 使用场景 |
|----------|----------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` (L1664) | 作为 `ChatgptAuthTokensRefreshParams` 的字段 |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` (L1585-L1588) | `LoginAccountParams::ChatgptAuthTokens` 变体（实验性） |

### 4.3 代码生成链

```
Rust 源类型 (v2.rs)
    ↓ ts-rs 宏处理
TypeScript 定义 (*.ts)
    ↓ 导出到
schema/typescript/v2/
```

---

## 5. 依赖与外部交互

### 5.1 内部依赖

| 依赖项 | 说明 |
|--------|------|
| `serde` | 序列化/反序列化支持 |
| `schemars` | JSON Schema 生成 |
| `ts-rs` | TypeScript 类型生成 |

### 5.2 协议交互

该类型属于 **App-Server Protocol v2** 的一部分，通过 JSON-RPC 风格的 API 进行通信：

```
Client ←→ App Server ←→ Codex Core
```

### 5.3 认证流程交互

```
┌─────────┐                    ┌──────────┐
│  Client │ ── 1. API Call ──→ │  Codex   │
│         │                    │  Server  │
│         │ ←─ 2. 401 Error ── │          │
│         │                    │          │
│         │ ── 3. Refresh ───→ │          │
│         │    (with reason)   │          │
│         │                    │          │
│         │ ←─ 4. New Token ── │          │
└─────────┘                    └──────────┘
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 严重程度 | 说明 |
|------|----------|------|
| 实验性 API | 高 | 标记为 `#[experimental("account/login/start.chatgptAuthTokens")]`，可能随时变更或移除 |
| 内部使用限制 | 高 | 文档明确标注仅供 OpenAI 内部使用 |
| 单一枚举值 | 低 | 目前仅支持 `unauthorized` 一种原因，扩展性受限 |

### 6.2 边界条件

- **空值处理**：该枚举为必填字段，不接受 `null` 或 `undefined`
- **未知值处理**：由于 TypeScript 是字符串字面量类型，传入未知字符串将在类型检查时报错
- **大小写敏感**：序列化使用 camelCase，`"unauthorized"` 与 `"Unauthorized"` 被视为不同值

### 6.3 改进建议

1. **扩展枚举值**
   - 添加 `tokenExpiringSoon`：令牌即将过期，建议主动刷新
   - 添加 `userRequested`：用户手动触发刷新
   - 添加 `securityPolicy`：安全策略要求刷新（如密码更改后）

2. **添加元数据字段**
   ```rust
   pub enum ChatgptAuthTokensRefreshReason {
       Unauthorized {
           /// HTTP 响应头中的具体错误信息
           error_detail: Option<String>,
           /// 建议的重试延迟（毫秒）
           retry_after_ms: Option<u64>,
       },
       // ...
   }
   ```

3. **稳定化路径**
   - 如果计划对外开放，需要移除 `ExperimentalApi` 标记
   - 添加完整的错误处理文档和示例代码

4. **TypeScript 类型增强**
   ```typescript
   // 添加 JSDoc 注释和常量
   export const ChatgptAuthTokensRefreshReason = {
       Unauthorized: "unauthorized",
   } as const;
   
   export type ChatgptAuthTokensRefreshReason = 
       typeof ChatgptAuthTokensRefreshReason[keyof typeof ChatgptAuthTokensRefreshReason];
   ```

---

## 附录：相关类型速查

```typescript
// ChatgptAuthTokensRefreshResponse.ts
export type ChatgptAuthTokensRefreshResponse = {
    accessToken: string;
    chatgptAccountId: string;
    chatgptPlanType: string | null;
};
```
