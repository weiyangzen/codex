# GetAccountParams.ts 研究文档

## 场景与职责

`GetAccountParams.ts` 定义了获取账户信息请求的参数类型，用于查询当前用户的账户状态和认证信息。这是账户管理 API 的核心功能，支持会话管理和令牌刷新。

该类型在登录状态检查、令牌刷新、账户信息展示等场景中发挥作用。

## 功能点目的

1. **账户查询**: 获取当前用户的账户信息
2. **令牌刷新**: 支持主动刷新访问令牌
3. **认证状态**: 检查是否需要 OpenAI 认证

## 具体技术实现

### 数据结构定义

```typescript
export type GetAccountParams = { 
  /**
   * When `true`, requests a proactive token refresh before returning.
   *
   * In managed auth mode this triggers the normal refresh-token flow. In
   * external auth mode this flag is ignored. Clients should refresh tokens
   * themselves and call `account/login/start` with `chatgptAuthTokens`.
   */
  refreshToken: boolean, 
};
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `refreshToken` | `boolean` | 是否在返回前主动刷新令牌 |

### 响应类型

```typescript
export type GetAccountResponse = {
  account: Account | null;           // 账户信息
  requiresOpenaiAuth: boolean;       // 是否需要 OpenAI 认证
};

export type Account = 
  | { type: "apiKey" }
  | { type: "chatgpt"; email: string; plan_type: PlanType };
```

### 使用示例

```typescript
// 普通查询
const params: GetAccountParams = {
  refreshToken: false
};

const response: GetAccountResponse = await client.sendRequest('account/get', params);

if (response.account) {
  console.log('已登录:', response.account);
} else {
  console.log('未登录，需要认证:', response.requiresOpenaiAuth);
}

// 主动刷新令牌
const refreshParams: GetAccountParams = {
  refreshToken: true
};
```

## 关键代码路径与文件引用

### Rust 源码定义

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 1696-1707)

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct GetAccountParams {
    /// When `true`, requests a proactive token refresh before returning.
    #[serde(default)]
    pub refresh_token: bool,
}
```

### 响应类型

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 1709-1715)

```rust
pub struct GetAccountResponse {
    pub account: Option<Account>,
    pub requires_openai_auth: bool,
}
```

### 账户类型

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 1554-1566)

```rust
pub enum Account {
    #[serde(rename = "apiKey", rename_all = "camelCase")]
    ApiKey {},
    #[serde(rename = "chatgpt", rename_all = "camelCase")]
    Chatgpt { email: String, plan_type: PlanType },
}
```

## 依赖与外部交互

### 上游依赖

| 依赖 | 说明 |
|------|------|
| `ts-rs` | TypeScript 类型生成 |
| `serde` | 序列化/反序列化 |
| `schemars` | JSON Schema 生成 |

### 下游消费者

- **账户 API**: `account/get` RPC 方法
- **登录流程**: 检查登录状态
- **令牌管理**: 刷新访问令牌

## 风险、边界与改进建议

### 已知风险

1. **刷新失败**: 令牌刷新可能失败，需要错误处理
2. **外部认证**: 外部认证模式下 `refreshToken` 被忽略
3. **并发刷新**: 并发调用可能导致重复刷新

### 边界情况

1. **令牌过期**: 令牌已过期时的行为
2. **网络中断**: 刷新过程中网络中断
3. **多设备**: 多设备登录时的令牌状态

### 改进建议

1. **刷新状态**: 返回令牌刷新状态
2. **过期时间**: 返回令牌过期时间
3. **刷新令牌**: 返回新的刷新令牌
4. **自动刷新**: 支持自动检测并刷新即将过期的令牌

### 扩展示例

```typescript
export type GetAccountParams = { 
  refreshToken: boolean,
  // 新增字段
  includeRateLimits?: boolean;  // 是否包含速率限制信息
  includeCredits?: boolean;     // 是否包含积分信息
};

export type GetAccountResponse = {
  account: Account | null;
  requiresOpenaiAuth: boolean;
  tokenExpiresAt?: number;      // 令牌过期时间
  rateLimits?: RateLimitSnapshot;
  credits?: CreditsSnapshot;
};
```
