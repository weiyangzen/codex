# Device Code Login 测试研究文档

## 场景与职责

`device_code_login.rs` 是 Codex CLI 登录模块的集成测试文件，专注于测试**设备码授权流程（Device Code Authorization Flow）**。该测试文件验证用户在没有浏览器或无法使用浏览器回调的场景下，通过设备码完成 OAuth 登录的完整流程。

### 核心职责
1. **验证设备码登录流程**：测试从请求用户码到获取令牌的完整流程
2. **测试错误处理**：验证各种失败场景（HTTP 错误、授权拒绝、工作区不匹配等）
3. **验证凭证持久化**：确保登录成功后凭证正确写入 `auth.json`
4. **测试工作区限制**：验证强制工作区 ID 功能的行为

---

## 功能点目的

### 1. 设备码登录流程测试
设备码流程适用于无头环境或无法打开浏览器的场景，流程如下：
1. 客户端请求用户码（user code）和设备授权 ID
2. 服务器返回验证码和验证 URL
3. 用户在浏览器中打开 URL 并输入验证码
4. 客户端轮询令牌端点等待授权完成
5. 获取访问令牌、刷新令牌和 ID 令牌

### 2. 测试覆盖场景
| 测试函数 | 目的 |
|---------|------|
| `device_code_login_integration_succeeds` | 验证正常登录流程成功完成 |
| `device_code_login_rejects_workspace_mismatch` | 验证强制工作区 ID 不匹配时拒绝登录 |
| `device_code_login_integration_handles_usercode_http_failure` | 验证用户码请求 HTTP 失败处理 |
| `device_code_login_integration_persists_without_api_key_on_exchange_failure` | 验证 API key 交换失败时仍持久化令牌 |
| `device_code_login_integration_handles_error_payload` | 验证授权拒绝错误处理 |

---

## 具体技术实现

### 关键流程

#### 1. JWT 生成辅助函数
```rust
fn make_jwt(payload: serde_json::Value) -> String
```
- 生成用于测试的 JWT 令牌（无签名，alg="none"）
- 使用 URL-safe base64 编码
- 允许自定义 payload 内容

#### 2. Mock 服务器设置

**用户码端点 Mock** (`mock_usercode_success`):
```rust
POST /api/accounts/deviceauth/usercode
Response: {
    "device_auth_id": "device-auth-123",
    "user_code": "CODE-12345",
    "interval": "0"  // 测试时设为0避免等待
}
```

**令牌轮询端点 Mock** (`mock_poll_token_two_step`):
```rust
POST /api/accounts/deviceauth/token
// 第一次返回 404 (等待中)
// 第二次返回授权码
Response: {
    "authorization_code": "poll-code-321",
    "code_challenge": "code-challenge-321",
    "code_verifier": "code-verifier-321"
}
```

**OAuth 令牌端点 Mock** (`mock_oauth_token_single`):
```rust
POST /oauth/token
Response: {
    "id_token": "<JWT>",
    "access_token": "access-token-123",
    "refresh_token": "refresh-token-123"
}
```

#### 3. 测试配置构建
```rust
fn server_opts(
    codex_home: &tempfile::TempDir,
    issuer: String,
    cli_auth_credentials_store_mode: AuthCredentialsStoreMode,
) -> ServerOptions
```
- 使用临时目录作为 `codex_home`
- 配置 mock 服务器地址作为 issuer
- 禁用浏览器自动打开

### 数据结构

#### DeviceCode 结构（来自被测代码）
```rust
pub struct DeviceCode {
    pub verification_url: String,
    pub user_code: String,
    device_auth_id: String,
    interval: u64,
}
```

#### 测试使用的 JWT Claims 结构
```rust
{
    "https://api.openai.com/auth": {
        "chatgpt_account_id": "acct_321",
        "organization_id": "org-xxx"  // 可选
    }
}
```

---

## 关键代码路径与文件引用

### 被测代码路径

| 文件 | 职责 |
|------|------|
| `codex-rs/login/src/device_code_auth.rs` | 设备码登录核心实现 |
| `codex-rs/login/src/server.rs` | 令牌交换和持久化逻辑 |
| `codex-rs/login/src/pkce.rs` | PKCE 代码生成 |
| `codex-rs/core/src/auth/storage.rs` | 凭证存储实现 |
| `codex-rs/core/src/token_data.rs` | 令牌数据结构 |

### 关键函数调用链

```
run_device_code_login(opts)
  ├── request_device_code(opts)
  │     ├── request_user_code() -> POST /deviceauth/usercode
  │     └── 打印验证码提示
  └── complete_device_code_login(opts, device_code)
        ├── poll_for_token() -> POST /deviceauth/token (轮询)
        ├── exchange_code_for_tokens() -> POST /oauth/token
        ├── ensure_workspace_allowed() (验证工作区)
        └── persist_tokens_async() (持久化凭证)
```

### 测试断言要点

1. **成功登录断言**:
   - `auth.json` 存在且可加载
   - `tokens.access_token` 匹配预期值
   - `tokens.refresh_token` 匹配预期值
   - `tokens.id_token.raw_jwt` 匹配预期值
   - `tokens.account_id` 从 JWT 正确提取

2. **失败场景断言**:
   - 错误类型为 `PermissionDenied` 或包含特定错误消息
   - `auth.json` 不存在（登录失败不创建凭证文件）

---

## 依赖与外部交互

### 测试依赖

| 依赖 | 用途 |
|------|------|
| `wiremock` | HTTP Mock 服务器，模拟 OAuth 服务端点 |
| `tempfile` | 创建临时目录作为 `codex_home` |
| `core_test_support` | 提供 `skip_if_no_network!` 宏 |
| `anyhow` | 错误处理 |
| `base64` | JWT 编码 |
| `serde_json` | JSON 处理 |

### 网络依赖

测试使用 `skip_if_no_network!` 宏检测沙箱环境：
```rust
skip_if_no_network!(Ok(()));
```
- 当 `CODEX_SANDBOX_NETWORK_DISABLED=1` 时跳过测试
- 这是因为在沙箱中无法发起网络请求

### Mock 服务器交互

测试启动 WireMock 服务器模拟以下端点：
- `POST /api/accounts/deviceauth/usercode` - 用户码请求
- `POST /api/accounts/deviceauth/token` - 令牌轮询
- `POST /oauth/token` - OAuth 令牌交换

---

## 风险、边界与改进建议

### 已知风险

1. **网络依赖**
   - 测试需要网络功能，在沙箱环境中被跳过
   - 可能导致 CI 覆盖率下降

2. **时间敏感测试**
   - `mock_poll_token_two_step` 依赖请求顺序
   - 并发测试可能导致竞争条件

3. **JWT 安全**
   - 测试使用 `alg: "none"` 的 JWT，仅用于测试
   - 生产环境必须使用标准 JWT 验证

### 边界情况

1. **轮询超时**
   - 生产代码有 15 分钟超时限制
   - 测试通过设置 `interval: 0` 避免实际等待

2. **错误状态码处理**
   - 403/404 表示继续轮询
   - 其他错误状态码表示流程失败

3. **凭证存储模式**
   - 测试使用 `AuthCredentialsStoreMode::File`
   - 未测试 `Keyring` 和 `Auto` 模式

### 改进建议

1. **增加测试覆盖率**
   - 添加 `Keyring` 存储模式的测试
   - 测试 `Auto` 模式的回退行为
   - 添加并发登录测试

2. **增强错误场景**
   - 测试网络超时场景
   - 测试无效 JSON 响应处理
   - 测试 JWT 解析失败场景

3. **代码重构建议**
   - 将 Mock 设置逻辑提取到共享模块
   - 添加更多辅助函数减少重复代码
   - 考虑使用快照测试验证错误消息

4. **文档改进**
   - 添加设备码流程的序列图
   - 说明测试与生产环境的差异
   - 记录 Mock 服务器的预期请求/响应格式

### 相关配置

测试涉及的关键配置项：
- `CODEX_HOME` - 凭证存储目录
- `AuthCredentialsStoreMode` - 存储模式（File/Keyring/Auto/Ephemeral）
- `forced_chatgpt_workspace_id` - 强制工作区 ID
- `issuer` - OAuth 发行方 URL
