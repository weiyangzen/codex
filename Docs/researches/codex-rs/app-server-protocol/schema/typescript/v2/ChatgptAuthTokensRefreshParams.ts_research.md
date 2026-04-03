# ChatgptAuthTokensRefreshParams.ts 研究文档

## 场景与职责

`ChatgptAuthTokensRefreshParams.ts` 定义了 ChatGPT 认证令牌刷新请求的类型，用于 `account/chatgptAuthTokens/refresh` API。当 Codex 使用 ChatGPT Auth Tokens 登录模式时，如果后端请求收到 401 Unauthorized 响应，客户端需要通过此 API 请求令牌刷新。

该类型是 Codex 内部使用的认证机制（标记为 FOR OPENAI INTERNAL USE ONLY），用于管理多工作区/多账户场景下的令牌生命周期。

## 功能点目的

### 核心功能

1. **令牌刷新触发**：客户端通知服务器需要刷新访问令牌
2. **账户关联**：通过 `previousAccountId` 帮助服务器识别正确的账户/工作区
3. **失败原因传递**：告知服务器刷新触发的原因（目前仅支持 Unauthorized）

### 类型定义

```typescript
import type { ChatgptAuthTokensRefreshReason } from "./ChatgptAuthTokensRefreshReason";

export type ChatgptAuthTokensRefreshParams = { 
  reason: ChatgptAuthTokensRefreshReason, 
  /**
   * Workspace/account identifier that Codex was previously using.
   *
   * Clients that manage multiple accounts/workspaces can use this as a hint
   * to refresh the token for the correct workspace.
   *
   * This may be `null` when the prior auth state did not include a workspace
   * identifier (`chatgpt_account_id`).
   */
  previousAccountId?: string | null, 
};
```

### 字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `reason` | `ChatgptAuthTokensRefreshReason` | 是 | 刷新原因，当前仅 `"unauthorized"` |
| `previousAccountId` | `string \| null` | 否 | 之前使用的工作区/账户标识符，用于多账户场景 |

### 刷新原因枚举

```typescript
type ChatgptAuthTokensRefreshReason = "unauthorized";
```

当前仅支持一种原因：
- `unauthorized`：Codex 尝试后端请求时收到 401 Unauthorized

## 具体技术实现

### 代码生成来源

**Rust 源码位置**：`codex-rs/app-server-protocol/src/protocol/v2.rs` (行 1653-1675)

```rust
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum ChatgptAuthTokensRefreshReason {
    /// Codex attempted a backend request and received `401 Unauthorized`.
    Unauthorized,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ChatgptAuthTokensRefreshParams {
    pub reason: ChatgptAuthTokensRefreshReason,
    /// Workspace/account identifier that Codex was previously using.
    ///
    /// Clients that manage multiple accounts/workspaces can use this as a hint
    /// to refresh the token for the correct workspace.
    ///
    /// This may be `null` when the prior auth state did not include a workspace
    /// identifier (`chatgpt_account_id`).
    #[ts(optional = nullable)]
    pub previous_account_id: Option<String>,
}
```

### 实验性标记

该 API 被标记为实验性：
```rust
/// [UNSTABLE] FOR OPENAI INTERNAL USE ONLY - DO NOT USE.
/// The access token must contain the same scopes that Codex-managed ChatGPT auth tokens have.
#[experimental("account/login/start.chatgptAuthTokens")]
```

### 响应类型

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ChatgptAuthTokensRefreshResponse {
    pub access_token: String,
    pub chatgpt_account_id: String,
    pub chatgpt_plan_type: Option<String>,
}
```

## 关键代码路径与文件引用

### 依赖关系

```
ChatgptAuthTokensRefreshParams.ts
  └── ChatgptAuthTokensRefreshReason.ts
```

### 相关文件

| 文件 | 说明 |
|------|------|
| `ChatgptAuthTokensRefreshReason.ts` | 刷新原因枚举 |
| `ChatgptAuthTokensRefreshResponse.ts` | 刷新响应类型 |
| `LoginAccountParams.ts` | 登录参数（包含 chatgptAuthTokens 模式） |

### 使用流程

```
Client                              Server
  |                                    |
  |-- account/login/start ----------->|
  |   (type: "chatgptAuthTokens")      |
  |<-- LoginAccountResponse -----------|
  |                                    |
  |-- Backend API call (with token) -->|
  |<-- 401 Unauthorized ----------------
  |                                    |
  |-- account/chatgptAuthTokens/refresh->
  |   ChatgptAuthTokensRefreshParams   |
  |<-- ChatgptAuthTokensRefreshResponse|
  |   (new access_token)               |
```

## 依赖与外部交互

### 认证流程集成

该类型是 ChatGPT Auth Tokens 登录模式的一部分：

1. **初始登录**：
   - 客户端通过 `account/login/start` 提供 `access_token` 和 `chatgpt_account_id`
   - 服务器验证令牌并建立会话

2. **令牌过期处理**：
   - 后端 API 返回 401
   - 客户端调用刷新端点
   - 服务器返回新的访问令牌

3. **多账户支持**：
   - `previousAccountId` 帮助服务器在多个账户中识别正确的刷新目标
   - 适用于管理多个工作区的客户端

### 安全考虑

1. **令牌范围**：访问令牌必须包含与 Codex 管理的 ChatGPT 认证令牌相同的权限范围
2. **内部使用**：该 API 仅用于 OpenAI 内部场景，不推荐外部使用
3. **令牌传输**：新的访问令牌在响应中明文传输，需要 HTTPS 保护

## 风险、边界与改进建议

### 潜在风险

1. **令牌泄露**：刷新响应包含新的访问令牌，需要确保传输安全
2. **竞态条件**：多个并发刷新请求可能导致令牌状态不一致
3. **账户混淆**：在多账户场景中，错误的 `previousAccountId` 可能导致刷新错误的账户

### 边界情况

1. **空 previousAccountId**：
   - 当之前的认证状态不包含工作区标识符时
   - 服务器可能需要依赖其他上下文（如会话 ID）

2. **账户已删除**：
   - 刷新时账户可能已被删除或禁用
   - 应返回适当的错误信息

3. **令牌已撤销**：
   - 原始令牌可能已被用户撤销
   - 刷新应失败并引导重新登录

### 改进建议

1. **扩展刷新原因**：
   ```typescript
   type ChatgptAuthTokensRefreshReason = 
     | "unauthorized"      // 401 响应
     | "expiringSoon"      // 令牌即将过期（预防性刷新）
     | "userRequested";    // 用户手动触发
   ```

2. **添加刷新元数据**：
   ```typescript
   interface ChatgptAuthTokensRefreshParams {
     reason: ChatgptAuthTokensRefreshReason;
     previousAccountId?: string | null;
     requestedScopes?: string[];  // 请求的权限范围
   }
   ```

3. **支持批量刷新**：
   - 允许一次刷新多个账户的令牌
   - 适用于管理大量账户的企业场景

4. **刷新策略配置**：
   - 允许配置自动刷新的阈值（如过期前 5 分钟）
   - 支持后台静默刷新

### 版本兼容性

- 当前版本：v2
- 稳定性：**UNSTABLE / FOR OPENAI INTERNAL USE ONLY**
- 访问控制：需要特定权限才能使用
- 变更风险：高（内部 API 可能随时变更）

### 替代方案

对于外部用户，推荐使用：
- **API Key 模式**：更简单，无需刷新机制
- **ChatGPT OAuth 模式**：标准的 OAuth 2.0 流程，自动处理令牌刷新
