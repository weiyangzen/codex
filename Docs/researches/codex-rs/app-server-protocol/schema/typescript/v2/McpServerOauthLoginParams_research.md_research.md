# McpServerOauthLoginParams 研究文档

## 场景与职责

`McpServerOauthLoginParams` 是 app-server v2 API 中 ClientRequest 的 `mcpServer/oauth/login` 方法的参数类型。它用于触发指定 MCP 服务器的 OAuth 登录流程，获取用户授权以访问 MCP 服务器提供的资源。

该类型是 MCP 服务器认证体系的关键组成部分，支持需要 OAuth 授权的 MCP 服务器（如 GitHub、Google 等第三方服务集成）。

## 功能点目的

### 核心功能
1. **触发 OAuth 流程**：启动指定 MCP 服务器的 OAuth 登录/授权流程
2. **指定授权范围**：通过 `scopes` 字段请求特定的 OAuth 权限范围
3. **超时控制**：通过 `timeout_secs` 设置登录流程的超时时间

### 使用场景
- 用户首次使用需要 OAuth 授权的 MCP 服务器
- 现有 OAuth token 过期，需要重新授权
- 需要申请额外的 OAuth scopes 权限

## 具体技术实现

### 数据结构定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs (lines 2080-2092)
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct McpServerOauthLoginParams {
    /// MCP 服务器名称
    pub name: String,
    /// 请求的 OAuth scopes（可选）
    #[ts(optional = nullable)]
    pub scopes: Option<Vec<String>>,
    /// 超时时间（秒）（可选）
    #[ts(optional = nullable)]
    pub timeout_secs: Option<u64>,
}
```

### 生成的 TypeScript 类型

```typescript
// schema/typescript/v2/McpServerOauthLoginParams.ts
export type McpServerOauthLoginParams = { 
    name: string, 
    scopes?: Array<string> | null, 
    timeoutSecs?: bigint | null, 
};
```

### 对应的响应类型

```rust
// McpServerOauthLoginResponse (lines 2093-2106)
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct McpServerOauthLoginResponse {
    /// 授权 URL，客户端应引导用户访问
    pub auth_url: String,
    /// 用于验证回调的 state 参数
    pub state: String,
    /// 过期时间戳
    pub expires_at: i64,
}
```

## 关键代码路径与文件引用

### 定义位置
- **Rust 定义**：`codex-rs/app-server-protocol/src/protocol/v2.rs`
  - 行 2080-2092：`McpServerOauthLoginParams` 结构体
  - 行 2093-2106：`McpServerOauthLoginResponse` 响应类型

### 协议注册
```rust
// codex-rs/app-server-protocol/src/protocol/common.rs (lines 410-413)
client_request_definitions! {
    McpServerOauthLogin => "mcpServer/oauth/login" {
        params: v2::McpServerOauthLoginParams,
        response: v2::McpServerOauthLoginResponse,
    },
}
```

### 相关类型定义
| 类型 | 文件 | 行号 | 说明 |
|------|------|------|------|
| `McpServerOauthLoginResponse` | v2.rs | 2093-2106 | 对应的响应类型 |
| `McpServerOauthLoginCompletedNotification` | v2.rs | 4960-4980 | 登录完成通知 |
| `McpAuthStatus` | v2.rs | 334-340 | MCP 服务器认证状态 |
| `McpServerStatus` | v2.rs | 1908-1918 | MCP 服务器状态 |

### 状态追踪
```rust
// McpAuthStatus 枚举 (lines 334-340)
pub enum McpAuthStatus {
    Unsupported,    // 服务器不支持认证
    NotLoggedIn,    // 未登录
    BearerToken,    // 使用 Bearer Token
    OAuth,          // 使用 OAuth
}
```

### 生成的 TypeScript 文件
- `codex-rs/app-server-protocol/schema/typescript/v2/McpServerOauthLoginParams.ts`
- `codex-rs/app-server-protocol/schema/typescript/v2/McpServerOauthLoginResponse.ts`（配对）
- `codex-rs/app-server-protocol/schema/typescript/v2/McpServerOauthLoginCompletedNotification.ts`（通知）

## 依赖与外部交互

### 内部依赖
1. **ts-rs**：TypeScript 类型导出，`#[ts(optional = nullable)]` 标记可选字段
2. **schemars**：JSON Schema 生成
3. **serde**：`#[serde(rename_all = "camelCase")]` 驼峰命名

### 外部交互流程
```
Client
    ↓
McpServerOauthLoginParams { name, scopes, timeout_secs }
    ↓
POST mcpServer/oauth/login
    ↓
McpServerOauthLoginResponse { auth_url, state, expires_at }
    ↓
Client 打开浏览器访问 auth_url
    ↓
用户完成授权
    ↓
回调到本地服务器
    ↓
McpServerOauthLoginCompletedNotification { success, error? }
```

### 与 McpServerStatus 的关联
```rust
pub struct McpServerStatus {
    pub name: String,
    pub tools: HashMap<String, McpTool>,
    pub resources: Vec<McpResource>,
    pub resource_templates: Vec<McpResourceTemplate>,
    pub auth_status: McpAuthStatus,  // 反映当前认证状态
}
```

## 风险、边界与改进建议

### 潜在风险
1. **超时处理**：`timeout_secs` 为可选字段，服务端需要设置合理的默认值
2. **Scope 验证**：`scopes` 为可选字段，但某些 MCP 服务器可能要求特定 scope
3. **并发登录**：同一服务器的并发 OAuth 请求可能导致 state 冲突

### 边界情况
1. **空 scopes**：`scopes: Some([])` 与 `scopes: None` 的语义差异
2. **超时为 0**：`timeout_secs: Some(0)` 应视为无效还是立即超时？
3. **不存在的服务器**：`name` 指向未配置的 MCP 服务器时的错误处理

### 改进建议
1. **添加验证**：
   ```rust
   impl McpServerOauthLoginParams {
       pub fn validate(&self) -> Result<(), ValidationError> {
           if self.name.is_empty() {
               return Err(ValidationError::EmptyServerName);
           }
           if let Some(timeout) = self.timeout_secs {
               if timeout == 0 {
                   return Err(ValidationError::ZeroTimeout);
               }
           }
           Ok(())
       }
   }
   ```

2. **添加服务器存在性检查**：在请求处理时验证 `name` 对应的 MCP 服务器是否已配置

3. **支持强制重新授权**：添加 `force: bool` 字段，允许用户强制重新登录即使已有有效 token

4. **PKCE 支持**：添加 `pkce_challenge` 字段以增强 OAuth 安全性

### 测试覆盖
建议测试场景：
1. 正常 OAuth 流程（含 scopes 和 timeout）
2. 最小参数调用（仅 name）
3. 无效服务器名称的错误处理
4. 并发登录请求处理
5. 超时后的清理逻辑

### API 稳定性
- 此类型属于稳定 API（无 `#[experimental]` 标记）
- 作为 ClientRequest 的方法参数，变更会影响客户端实现
- 建议通过添加可选字段来扩展功能

### 安全考虑
1. **State 参数**：响应中的 `state` 必须随机生成且单次有效
2. **CSRF 防护**：验证回调中的 state 与请求时一致
3. **Token 存储**：获取的 OAuth token 应安全存储，避免泄露
