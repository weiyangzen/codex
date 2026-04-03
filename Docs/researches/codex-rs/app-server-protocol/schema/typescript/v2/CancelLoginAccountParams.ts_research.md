# CancelLoginAccountParams 类型研究文档

## 1. 场景与职责

### 使用场景
`CancelLoginAccountParams` 是 Codex App-Server Protocol v2 中用于取消正在进行的账户登录流程的请求参数类型。当用户启动了一个 OAuth 登录流程（如 ChatGPT 登录）但决定取消或超时时，客户端可以通过 `account/login/cancel` RPC 方法发送此参数来通知服务器清理相关的登录状态。

### 主要职责
- **登录取消通知**：通知服务器用户已取消登录流程
- **资源清理**：触发服务器清理与登录 ID 关联的临时资源
- **状态同步**：确保客户端和服务器在登录状态上保持一致
- **超时处理**：支持登录流程的超时取消场景

### 使用场景示例
```typescript
// 场景 1：用户主动取消登录
async function cancelLogin(loginId: string) {
    const params: CancelLoginAccountParams = {
        loginId: loginId,
    };
    
    const response = await client.request('account/login/cancel', params);
    
    if (response.status === 'canceled') {
        console.log('登录已成功取消');
    } else if (response.status === 'notFound') {
        console.log('登录流程已过期或不存在');
    }
}

// 场景 2：登录超时处理
function handleLoginTimeout(loginId: string) {
    cancelLogin(loginId);
    showNotification('登录已超时，请重试');
}

// 场景 3：用户关闭登录窗口
loginWindow.onClose = () => {
    if (loginInProgress) {
        cancelLogin(currentLoginId);
    }
};
```

---

## 2. 功能点目的

### 2.1 登录 ID 标识（`loginId`）
- **目的**：唯一标识要取消的登录流程
- **来源**：由 `account/login/start` 返回的 `LoginAccountResponse::Chatgpt { login_id, ... }`
- **格式**：字符串类型的 UUID 或唯一标识符
- **生命周期**：与登录流程绑定，流程结束后失效

### 2.2 取消流程
```
1. 用户启动登录流程
   ↓ account/login/start
2. 服务器返回 login_id 和 auth_url
   ↓
3. 用户打开浏览器进行 OAuth
   ↓
4. 用户决定取消 / 超时 / 关闭窗口
   ↓ account/login/cancel (CancelLoginAccountParams)
5. 服务器清理登录状态
   ↓
6. 返回 CancelLoginAccountResponse
```

### 2.3 与登录流程的关联
| 阶段 | 方法 | 参数/响应 | 说明 |
|------|------|----------|------|
| 开始 | `account/login/start` | `LoginAccountParams` | 启动登录 |
| | | `LoginAccountResponse::Chatgpt { login_id, auth_url }` | 返回登录 ID |
| 进行 | 浏览器 OAuth | - | 用户在外部完成授权 |
| 取消 | `account/login/cancel` | `CancelLoginAccountParams { login_id }` | 本类型 |
| | | `CancelLoginAccountResponse` | 取消结果 |
| 完成 | 回调/轮询 | - | 正常完成登录 |

---

## 3. 具体技术实现

### 3.1 TypeScript 类型定义
```typescript
export type CancelLoginAccountParams = { 
    loginId: string, 
};
```

### 3.2 Rust 源类型定义
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct CancelLoginAccountParams {
    pub login_id: String,
}
```

### 3.3 序列化特性
| 特性 | 说明 |
|------|------|
| `rename_all = "camelCase"` | 字段使用 camelCase（`login_id` → `loginId`） |
| `String` | 登录 ID 使用字符串类型，避免 UUID 类型的序列化问题 |
| 无 `Option` 包装 | `login_id` 是必填字段 |

### 3.4 关联类型
| 类型 | 文件 | 说明 |
|------|------|------|
| `CancelLoginAccountResponse` | `CancelLoginAccountResponse.ts` | 取消操作响应 |
| `CancelLoginAccountStatus` | `CancelLoginAccountStatus.ts` | 取消状态枚举 |
| `LoginAccountParams` | `LoginAccountParams.ts` | 登录请求参数 |
| `LoginAccountResponse` | `LoginAccountResponse.ts` | 登录响应（包含 `login_id`） |

---

## 4. 关键代码路径与文件引用

### 4.1 源文件位置
| 文件 | 路径 | 说明 |
|------|------|------|
| v2.rs | `codex-rs/app-server-protocol/src/protocol/v2.rs:1625-1630` | Rust 源类型定义 |

### 4.2 生成文件位置
| 文件 | 路径 | 说明 |
|------|------|------|
| CancelLoginAccountParams.ts | `codex-rs/app-server-protocol/schema/typescript/v2/CancelLoginAccountParams.ts` | TypeScript 类型定义 |
| JSON Schema | `codex-rs/app-server-protocol/schema/json/v2/CancelLoginAccountParams.json` | JSON Schema 定义 |

### 4.3 使用位置
| 文件 | 路径 | 用途 |
|------|------|------|
| common.rs | `codex-rs/app-server-protocol/src/protocol/common.rs:436-439` | 注册 `CancelLoginAccount` RPC 方法 |

### 4.4 RPC 方法注册
```rust
// common.rs
CancelLoginAccount => "account/login/cancel" {
    params: v2::CancelLoginAccountParams,
    response: v2::CancelLoginAccountResponse,
},
```

### 4.5 代码引用链
```
ClientRequest::CancelLoginAccount
    ├── params: CancelLoginAccountParams
    │       └── login_id: String
    └── response: CancelLoginAccountResponse
            └── status: CancelLoginAccountStatus
                    ├── Canceled
                    └── NotFound
```

---

## 5. 依赖与外部交互

### 5.1 直接依赖
`CancelLoginAccountParams` 是基础参数类型，不依赖其他自定义类型。

### 5.2 上游依赖
| 依赖 | 来源 | 用途 |
|------|------|------|
| `ts-rs` | Rust crate | 生成 TypeScript 类型 |
| `schemars` | Rust crate | 生成 JSON Schema |
| `serde` | Rust crate | 序列化/反序列化 |

### 5.3 外部交互
| 交互方 | 交互方式 | 说明 |
|--------|----------|------|
| Login API | `account/login/cancel` | 主要使用场景 |
| Auth Service | 内部调用 | 服务器端认证服务 |
| Session Manager | 内部调用 | 清理登录会话状态 |

### 5.4 数据流
```
客户端
    ↓ CancelLoginAccountParams { login_id }
App-Server
    ↓ 验证 login_id
    ├─ 存在 → 清理登录状态 → CancelLoginAccountStatus::Canceled
    └─ 不存在 → CancelLoginAccountStatus::NotFound
    ↓
CancelLoginAccountResponse
    ↓
客户端
```

---

## 6. 风险、边界与改进建议

### 6.1 潜在风险

#### 风险 1：登录 ID 泄露
- **问题**：`login_id` 如果泄露，可能被恶意取消他人的登录流程
- **影响**：拒绝服务攻击，阻止合法用户登录
- **缓解**：
  - 登录 ID 应具有足够的随机性（UUID）
  - 服务器应验证请求来源
  - 登录 ID 应具有短生命周期

#### 风险 2：竞态条件
- **问题**：取消请求和登录完成可能同时发生
- **影响**：状态不一致
- **场景**：
  1. 用户完成 OAuth 授权
  2. 同时发送取消请求
  3. 结果不确定
- **缓解**：
  - 服务器应使用原子操作处理状态变更
  - 明确定义竞态条件下的行为

#### 风险 3：重复取消
- **问题**：客户端可能多次发送取消请求
- **影响**：
  - 第一次：返回 `Canceled`
  - 后续：返回 `NotFound`
- **缓解**：这是预期行为，客户端应正确处理

### 6.2 边界情况

| 场景 | 预期行为 | 说明 |
|------|----------|------|
| `login_id` 为空字符串 | 验证错误 | 应该拒绝 |
| `login_id` 格式无效 | 返回 `NotFound` | 视为不存在 |
| `login_id` 已过期 | 返回 `NotFound` | 登录流程已超时 |
| `login_id` 已完成登录 | 返回 `NotFound` | 登录流程已结束 |
| 重复取消同一 `login_id` | 首次 `Canceled`，后续 `NotFound` | 幂次行为 |
| 取消不存在的 `login_id` | 返回 `NotFound` | 优雅处理 |

### 6.3 改进建议

#### 建议 1：添加取消原因
```rust
pub struct CancelLoginAccountParams {
    pub login_id: String,
    
    /// 取消原因（可选，用于分析）
    #[ts(optional = nullable)]
    pub reason: Option<CancelReason>,
}

pub enum CancelReason {
    UserCancelled,      // 用户主动取消
    Timeout,            // 超时
    WindowClosed,       // 登录窗口关闭
    Error,              // 发生错误
    Other(String),      // 其他原因
}
```

#### 建议 2：添加请求标识
```rust
pub struct CancelLoginAccountParams {
    pub login_id: String,
    
    /// 客户端请求 ID，用于幂等性控制
    #[ts(optional = nullable)]
    pub request_id: Option<String>,
}
```

#### 建议 3：增强响应信息
```rust
pub struct CancelLoginAccountResponse {
    pub status: CancelLoginAccountStatus,
    
    /// 额外信息
    #[ts(optional = nullable)]
    pub message: Option<String>,
    
    /// 登录流程的当前状态（如果仍可知）
    #[ts(optional = nullable)]
    pub login_state: Option<LoginState>,
}

pub enum LoginState {
    Pending,        // 等待用户授权
    Authorizing,    // 正在授权
    Completing,     // 即将完成
    Completed,      // 已完成
    Cancelled,      // 已取消
    Expired,        // 已过期
}
```

#### 建议 4：批量取消支持
```rust
pub struct CancelLoginAccountParams {
    /// 支持取消多个登录流程
    pub login_ids: Vec<String>,
}

pub struct CancelLoginAccountResponse {
    /// 每个 login_id 的取消结果
    pub results: Vec<CancelResult>,
}

pub struct CancelResult {
    pub login_id: String,
    pub status: CancelLoginAccountStatus,
}
```

#### 建议 5：添加超时参数
```rust
pub struct CancelLoginAccountParams {
    pub login_id: String,
    
    /// 取消操作的超时时间（秒）
    #[serde(default = "default_cancel_timeout")]
    pub timeout_secs: u32,
}

const fn default_cancel_timeout() -> u32 {
    5  // 默认 5 秒
}
```

### 6.4 安全建议

#### 建议 6：请求签名验证
```rust
pub struct CancelLoginAccountParams {
    pub login_id: String,
    
    /// 请求签名，防止伪造
    #[ts(optional = nullable)]
    pub signature: Option<String>,
}

// 服务器验证
fn verify_cancel_request(params: &CancelLoginAccountParams, client_token: &str) -> bool {
    let expected = hmac_sha256(&params.login_id, client_token);
    params.signature.as_ref() == Some(&expected)
}
```

#### 建议 7：速率限制
- 对 `account/login/cancel` 接口实施速率限制
- 防止恶意客户端频繁取消登录

#### 建议 8：审计日志
```rust
fn cancel_login(params: CancelLoginAccountParams, client_info: ClientInfo) {
    audit_log.record(AuditEvent::LoginCancelled {
        login_id: params.login_id,
        client_ip: client_info.ip,
        timestamp: now(),
        result: status,
    });
}
```

### 6.5 与登录流程的完整交互

```
正常登录流程：
┌─────────┐    account/login/start    ┌─────────┐
│ Client  │ ─────────────────────────> │ Server  │
│         │ <───────────────────────── │         │
│         │    { login_id, auth_url }  │         │
│         │                            │         │
│         │    [用户完成 OAuth]         │         │
│         │                            │         │
│         │    [回调/轮询获取 token]     │         │
│         │ <───────────────────────── │         │
│         │    { access_token, ... }   │         │
└─────────┘                            └─────────┘

取消登录流程：
┌─────────┐    account/login/start    ┌─────────┐
│ Client  │ ─────────────────────────> │ Server  │
│         │ <───────────────────────── │         │
│         │    { login_id, auth_url }  │         │
│         │                            │         │
│         │    [用户决定取消]           │         │
│         │                            │         │
│         │    account/login/cancel    │         │
│         │ ─────────────────────────> │         │
│         │ <───────────────────────── │         │
│         │    { status: "canceled" }  │         │
└─────────┘                            └─────────┘
```
