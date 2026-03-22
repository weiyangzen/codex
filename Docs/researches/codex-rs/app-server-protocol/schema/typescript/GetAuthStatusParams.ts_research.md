# GetAuthStatusParams Research Document

## 1. 场景与职责 (Usage Scenario and Responsibility)

`GetAuthStatusParams` 是 Codex 应用服务器协议中用于**获取认证状态请求**的参数类型。它允许客户端查询当前会话的认证状态，包括认证方式、令牌信息等。

**典型使用场景：**
- 应用启动时检查认证状态
- 用户点击"账户"页面时获取认证信息
- 定期检查令牌是否需要刷新
- 在需要令牌的操作前验证认证状态

**职责：**
- 控制是否包含敏感令牌信息
- 控制是否刷新过期的令牌
- 提供灵活的认证状态查询选项

## 2. 功能点目的 (Purpose of This Type)

该类型的设计目的是：

1. **安全控制**：通过 `includeToken` 控制敏感信息的返回
2. **令牌管理**：通过 `refreshToken` 支持主动刷新
3. **状态查询**：提供当前认证状态的完整视图
4. **灵活性**：允许客户端根据需求定制查询

## 3. 具体技术实现 (Technical Implementation Details)

### TypeScript 定义

```typescript
export type GetAuthStatusParams = { 
  includeToken: boolean | null, 
  refreshToken: boolean | null, 
};
```

### Rust 定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
pub struct GetAuthStatusParams {
    pub include_token: Option<bool>,
    pub refresh_token: Option<bool>,
}
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `includeToken` | `boolean \| null` | 是否包含认证令牌在响应中 |
| `refreshToken` | `boolean \| null` | 是否在返回前刷新过期的令牌 |

### 参数组合

| includeToken | refreshToken | 行为 |
|--------------|--------------|------|
| `null` / `false` | `null` / `false` | 只返回认证方式，不包含令牌 |
| `true` | `null` / `false` | 返回认证方式和当前令牌（即使过期） |
| `null` / `false` | `true` | 刷新令牌（如果需要），但不返回 |
| `true` | `true` | 刷新令牌（如果需要），并返回新令牌 |

### 使用示例

```typescript
// 基本查询（不包含敏感信息）
const params1: GetAuthStatusParams = {
  includeToken: null,
  refreshToken: null
};

// 获取令牌（用于 API 调用）
const params2: GetAuthStatusParams = {
  includeToken: true,
  refreshToken: true  // 确保令牌有效
};

// 后台刷新令牌
const params3: GetAuthStatusParams = {
  includeToken: false,
  refreshToken: true
};
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### 类型定义
- **TypeScript**: `/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/typescript/GetAuthStatusParams.ts`
- **Rust**: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v1.rs` (lines 169-174)

### 相关类型
- `GetAuthStatusResponse` - 对应的响应类型
- `AuthMode` - 认证模式枚举

### 使用位置

1. **客户端请求定义**（`common.rs`）：
   ```rust
   client_request_definitions! {
       // ...
       /// DEPRECATED in favor of GetAccount
       GetAuthStatus {
           params: v1::GetAuthStatusParams,
           response: v1::GetAuthStatusResponse,
       },
       // ...
   }
   ```

2. **请求方法**：`getAuthStatus`

### 请求-响应流程

```
ClientRequest::GetAuthStatus
  params: GetAuthStatusParams { include_token, refresh_token }
  ↓
Server 检查认证状态
  ↓
GetAuthStatusResponse
  { auth_method, auth_token, requires_openai_auth }
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### 协议集成
- 属于 app-server-protocol v1 类型（在 `v1.rs` 中定义）
- 通过 `ts-rs` 自动生成 TypeScript 类型
- 使用 camelCase 序列化
- 标记为 **DEPRECATED**，推荐使用 `GetAccount`

### 与 GetAccount 的关系

```rust
// DEPRECATED in favor of GetAccount
GetAuthStatus {
    params: v1::GetAuthStatusParams,
    response: v1::GetAuthStatusResponse,
},

// 推荐的替代
GetAccount => "account/read" {
    params: v2::GetAccountParams,
    response: v2::GetAccountResponse,
},
```

### 外部交互

1. **客户端 → 服务器**：发送认证状态查询
2. **服务器 → 认证服务**：检查/刷新令牌
3. **服务器 → 客户端**：返回认证状态
4. **令牌存储**：访问持久化的令牌

### 安全考虑

- `includeToken` 默认为 `false`，防止意外泄露
- 令牌应该只在需要时获取
- 刷新操作需要适当的权限验证

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### 风险与边界

1. **已弃用状态**：
   - 该 API 已标记为 DEPRECATED
   - 新代码应使用 v2 的 `GetAccount`
   - 可能在未来的版本中被移除

2. **可选字段的语义**：
   - `null` 和 `false` 的行为相同
   - 可能令人困惑

3. **刷新失败处理**：
   - 如果刷新失败，响应如何处理？
   - 错误信息可能不明确

4. **并发刷新**：
   - 多个并发的 `refreshToken: true` 请求可能导致竞态
   - 需要服务器端的刷新锁定

5. **令牌泄露风险**：
   - `includeToken: true` 可能导致敏感信息泄露
   - 客户端需要安全存储返回的令牌

### 改进建议

1. **迁移到 v2 API**：
   - 新客户端应实现 `GetAccount` 替代 `GetAuthStatus`
   - v2 API 可能提供更好的安全模型

2. **明确默认值**：
   ```rust
   pub struct GetAuthStatusParams {
       #[serde(default)]
       pub include_token: bool,  // 默认 false
       #[serde(default)]
       pub refresh_token: bool,  // 默认 false
   }
   ```

3. **添加错误详情**：
   ```rust
   pub struct GetAuthStatusResponse {
       // ... existing fields
       pub error: Option<AuthError>,
   }
   
   pub enum AuthError {
       TokenExpired,
       RefreshFailed(String),
       NetworkError,
   }
   ```

4. **细粒度权限**：
   ```rust
   pub struct GetAuthStatusParams {
       pub include_token: Option<bool>,
       pub refresh_token: Option<bool>,
       pub token_format: Option<TokenFormat>,  // 新：完整/掩码/哈希
   }
   ```

5. **审计日志**：
   - 记录令牌的访问和刷新操作
   - 帮助检测异常访问模式

### 测试建议
- 测试各种参数组合的行为
- 验证令牌刷新的正确性
- 测试过期令牌的处理
- 验证并发请求的处理
- 测试无认证状态的情况

### 安全建议
- 避免在日志中记录令牌
- 使用安全的存储机制保存令牌
- 实现令牌过期提醒
- 考虑使用短期令牌 + 刷新令牌的模型
