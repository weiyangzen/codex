# ChatgptAuthTokensRefreshResponse 类型研究文档

## 1. 场景与职责

### 1.1 使用场景

`ChatgptAuthTokensRefreshResponse` 是 ChatGPT 认证令牌刷新流程的响应类型，用于在 `account/login/start` 方法的 `chatgptAuthTokens` 变体中返回新的认证凭据。主要应用场景包括：

- **外部认证令牌刷新**：当客户端使用外部管理的 ChatGPT 认证令牌时，通过此响应返回刷新后的令牌信息
- **多账户切换**：支持返回新的账户标识和订阅计划类型，便于客户端管理多个工作区
- **会话恢复**：在令牌过期后恢复会话时，提供完整的认证上下文

### 1.2 核心职责

- 承载刷新后的访问令牌 (`accessToken`)
- 提供账户标识 (`chatgptAccountId`) 用于工作区识别
- 返回订阅计划类型 (`chatgptPlanType`) 用于功能限制判断

### 1.3 使用限制

与 `ChatgptAuthTokensRefreshReason` 相同，该类型属于 **实验性 API**，标记为 `[UNSTABLE] FOR OPENAI INTERNAL USE ONLY - DO NOT USE`。

---

## 2. 功能点目的

### 2.1 设计目标

| 目标 | 说明 |
|------|------|
| 完整凭据返回 | 提供刷新后的完整认证信息，避免多次往返请求 |
| 账户上下文传递 | 返回账户 ID 和计划类型，支持客户端的多账户管理 |
| 类型安全 | 通过强类型确保响应字段的完整性和正确性 |

### 2.2 字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `accessToken` | `string` | 是 | 刷新后的访问令牌 (JWT) |
| `chatgptAccountId` | `string` | 是 | ChatGPT 账户/工作区标识符 |
| `chatgptPlanType` | `string \| null` | 是 | 订阅计划类型（如 Plus、Enterprise 等），可能为 null |

### 2.3 与相关类型的关系

```
account/login/start (method)
├── Request: LoginAccountParams::ChatgptAuthTokens
│   ├── access_token: String
│   └── refresh_token: String
│
└── Response: ChatgptAuthTokensRefreshResponse  ← 本类型
    ├── accessToken: string
    ├── chatgptAccountId: string
    └── chatgptPlanType: string | null
```

---

## 3. 具体技术实现

### 3.1 TypeScript 类型定义

```typescript
export type ChatgptAuthTokensRefreshResponse = {
    accessToken: string;
    chatgptAccountId: string;
    chatgptPlanType: string | null;
};
```

### 3.2 Rust 源类型定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ChatgptAuthTokensRefreshResponse {
    pub access_token: String,
    pub chatgpt_account_id: String,
    pub chatgpt_plan_type: Option<String>,
}
```

### 3.3 序列化行为

- **命名规范**：Rust 使用 snake_case，通过 `#[serde(rename_all = "camelCase")]` 自动转换为 camelCase
- **TypeScript 映射**：`Option<String>` 映射为 `string | null`
- **空值处理**：`chatgpt_plan_type` 为 `Option`，序列化时可能为 `null`

### 3.4 与 PlanType 的关系

Rust 内部使用 `PlanType` 枚举表示计划类型，但在 API 边界转换为 `String`：

```rust
// codex_protocol::account::PlanType
pub enum PlanType {
    Plus,
    Team,
    Enterprise,
    Free,
    // ...
}
```

在 `ChatgptAuthTokensRefreshResponse` 中，计划类型被序列化为字符串，提供更灵活的客户端处理。

---

## 4. 关键代码路径与文件引用

### 4.1 类型定义位置

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` (L1677-L1684) | Rust 源类型定义 |
| `codex-rs/app-server-protocol/schema/typescript/v2/ChatgptAuthTokensRefreshResponse.ts` | 生成的 TypeScript 类型 |

### 4.2 相关类型定义

| 文件路径 | 相关类型 |
|----------|----------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` (L1656-L1659) | `ChatgptAuthTokensRefreshReason` |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` (L1661-L1675) | `ChatgptAuthTokensRefreshParams` |
| `codex-rs/protocol/src/account.rs` | `PlanType` 枚举定义 |

### 4.3 代码生成链

```
Rust 源类型 (v2.rs)
    ↓ ts-rs 宏 (#[ts(export_to = "v2/")])
TypeScript 定义 (*.ts)
    ↓ 导出到
schema/typescript/v2/
```

---

## 5. 依赖与外部交互

### 5.1 内部依赖

| 依赖项 | 说明 |
|--------|------|
| `serde` | 序列化/反序列化 |
| `schemars::JsonSchema` | JSON Schema 生成 |
| `ts_rs::TS` | TypeScript 类型生成 |
| `codex_protocol::account::PlanType` | 计划类型内部表示 |

### 5.2 协议交互

```
┌─────────────────────────────────────────────────────────────┐
│                    account/login/start                       │
├─────────────────────────────────────────────────────────────┤
│  Request: LoginAccountParams::ChatgptAuthTokens             │
│  ├── access_token: String                                   │
│  └── refresh_token: String                                  │
├─────────────────────────────────────────────────────────────┤
│  Response: ChatgptAuthTokensRefreshResponse                 │
│  ├── accessToken: string         ← 新的访问令牌             │
│  ├── chatgptAccountId: string    ← 账户标识                 │
│  └── chatgptPlanType: string|null ← 计划类型                │
└─────────────────────────────────────────────────────────────┘
```

### 5.3 认证流程

```
┌─────────┐     ┌──────────────┐     ┌─────────────┐
│ Client  │────→│  App Server  │────→│  Codex Core │
│         │     │              │     │             │
│         │←────│              │←────│             │
│         │     │  Returns     │     │  Validates  │
│         │     │  ChatgptAuth │     │  & issues   │
│         │     │  TokensRefresh│    │  new token  │
│         │     │  Response    │     │             │
└─────────┘     └──────────────┘     └─────────────┘
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 严重程度 | 说明 |
|------|----------|------|
| 实验性 API | 高 | 标记为 `#[experimental(...)]`，API 可能变更 |
| 令牌安全 | 高 | `accessToken` 为敏感信息，需要确保传输和存储安全 |
| 计划类型字符串化 | 中 | 使用 `String` 而非枚举，可能引入无效值 |

### 6.2 边界条件

- **空字符串**：`accessToken` 和 `chatgptAccountId` 为必填字段，空字符串是否有效取决于服务端验证
- **null 处理**：`chatgptPlanType` 可为 `null`，客户端需要处理此情况
- **令牌格式**：`accessToken` 预期为 JWT 格式，但类型定义不强制此约束

### 6.3 改进建议

1. **增强类型安全**
   ```rust
   // 使用 newtype 模式包装令牌
   pub struct AccessToken(String);
   pub struct AccountId(String);
   
   pub struct ChatgptAuthTokensRefreshResponse {
       pub access_token: AccessToken,
       pub chatgpt_account_id: AccountId,
       pub chatgpt_plan_type: Option<PlanType>, // 使用枚举而非 String
   }
   ```

2. **添加元数据字段**
   ```rust
   pub struct ChatgptAuthTokensRefreshResponse {
       // ... 现有字段
       /// 令牌过期时间（Unix 时间戳）
       pub expires_at: i64,
       /// 令牌作用域
       pub scope: Vec<String>,
       /// 令牌类型（通常为 "Bearer"）
       pub token_type: String,
   }
   ```

3. **TypeScript 类型增强**
   ```typescript
   // 添加品牌类型防止误用
   type AccessToken = string & { readonly __brand: unique symbol };
   type AccountId = string & { readonly __brand: unique symbol };
   
   export type ChatgptAuthTokensRefreshResponse = {
       accessToken: AccessToken;
       chatgptAccountId: AccountId;
       chatgptPlanType: "plus" | "team" | "enterprise" | "free" | null;
   };
   ```

4. **安全建议**
   - 确保响应通过 HTTPS 传输
   - 考虑添加令牌指纹或部分掩码，便于日志记录而不泄露完整令牌
   - 实现令牌轮换机制，同时返回新的刷新令牌

---

## 附录：相关类型速查

```typescript
// ChatgptAuthTokensRefreshReason.ts
export type ChatgptAuthTokensRefreshReason = "unauthorized";

// ChatgptAuthTokensRefreshParams (Rust 内部)
// pub struct ChatgptAuthTokensRefreshParams {
//     pub reason: ChatgptAuthTokensRefreshReason,
//     pub previous_account_id: Option<String>,
// }
```
