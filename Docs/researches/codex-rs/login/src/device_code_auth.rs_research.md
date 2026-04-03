# device_code_auth.rs 研究文档

## 场景与职责

`device_code_auth.rs` 实现了 **OAuth 2.0 Device Authorization Grant**（设备授权码流程），这是一种专为输入受限设备（如 CLI 工具、智能电视、IoT 设备）设计的 OAuth 认证机制。

### 核心使用场景

1. **无浏览器环境登录**：当用户在没有图形界面的服务器或 SSH 会话中使用 Codex CLI 时
2. **受限输入设备**：无法方便地输入复杂 URL 或处理重定向的设备
3. **远程/Headless 环境**：CI/CD 管道、Docker 容器、远程开发环境

### 模块职责

- 实现完整的设备码授权流程（RFC 8628）
- 向用户展示验证 URL 和一次性用户码
- 轮询授权服务器获取访问令牌
- 与 PKCE 流程集成完成最终令牌交换
- 持久化认证凭据到本地存储

---

## 功能点目的

### 1. 设备码请求阶段 (`request_user_code`)

**目的**：向授权服务器注册设备，获取用户码和验证 URL

**关键行为**：
- POST 请求到 `{issuer}/api/accounts/deviceauth/usercode`
- 发送 `client_id` 标识应用
- 接收 `device_auth_id`（设备标识）、`user_code`（用户可见码）、`interval`（轮询间隔）

**错误处理**：
- `404 Not Found`：服务器未启用设备码登录，提示用户使用浏览器登录
- 其他非成功状态码：返回通用错误

### 2. 轮询令牌阶段 (`poll_for_token`)

**目的**：在用户在浏览器中完成授权后，获取授权码

**关键行为**：
- 轮询端点：`{issuer}/api/accounts/deviceauth/token`
- 发送 `device_auth_id` 和 `user_code`
- 最大等待时间：**15 分钟**（`Duration::from_secs(15 * 60)`）
- 轮询间隔：由服务器返回的 `interval` 字段控制

**状态处理**：
- `200 OK`：授权完成，返回 `authorization_code`、`code_challenge`、`code_verifier`
- `403 Forbidden` / `404 Not Found`：授权未完成，继续轮询
- 其他状态：立即失败

### 3. 用户交互 (`print_device_code_prompt`)

**目的**：向终端用户展示清晰的登录指引

**输出内容**：
- Codex 版本信息
- 验证 URL（蓝色高亮）
- 一次性用户码（蓝色高亮，15 分钟有效期提示）
- 安全警告（防止钓鱼攻击）

### 4. 完整登录流程 (`run_device_code_login`)

**目的**：编排完整的设备码登录流程

**执行顺序**：
1. `request_device_code` - 获取设备码
2. `print_device_code_prompt` - 展示指引
3. `complete_device_code_login` - 完成登录

### 5. 完成登录 (`complete_device_code_login`)

**目的**：将设备码流程获取的授权码交换为最终令牌

**执行流程**：
1. 轮询获取 `authorization_code`、`code_verifier`、`code_challenge`
2. 使用 `server::exchange_code_for_tokens` 交换令牌（OAuth 标准授权码流程）
3. 验证工作区限制（`ensure_workspace_allowed`）
4. 持久化令牌（`persist_tokens_async`）

---

## 具体技术实现

### 数据结构

```rust
/// 设备码信息（返回给调用方）
pub struct DeviceCode {
    pub verification_url: String,  // 用户需访问的验证页面
    pub user_code: String,         // 一次性用户码（如 CODE-12345）
    device_auth_id: String,        // 设备标识（内部使用）
    interval: u64,                 // 轮询间隔（秒）
}

/// 用户码响应（来自服务器）
struct UserCodeResp {
    device_auth_id: String,
    #[serde(alias = "user_code", alias = "usercode")]  // 兼容多种字段名
    user_code: String,
    #[serde(default, deserialize_with = "deserialize_interval")]
    interval: u64,  // 支持字符串或数字格式
}

/// 令牌轮询请求
struct TokenPollReq {
    device_auth_id: String,
    user_code: String,
}

/// 成功响应（包含 PKCE 参数）
struct CodeSuccessResp {
    authorization_code: String,
    code_challenge: String,
    code_verifier: String,
}
```

### 关键流程

#### 设备码请求流程
```
┌─────────────┐     POST /deviceauth/usercode      ┌─────────────┐
│   Client    │ ─────────────────────────────────> │    Auth     │
│  (Codex)    │                                    │   Server    │
│             │ <───────────────────────────────── │             │
└─────────────┘     device_auth_id, user_code,     └─────────────┘
                    interval, verification_url
```

#### 轮询流程
```
┌─────────────┐     POST /deviceauth/token         ┌─────────────┐
│   Client    │ ─────────────────────────────────> │    Auth     │
│  (Codex)    │     device_auth_id, user_code      │   Server    │
│             │ <───────────────────────────────── │             │
└─────────────┘     403/404: 继续轮询               └─────────────┘
                    200: authorization_code
```

#### 完整登录序列
```
request_device_code()
    ↓
print_device_code_prompt()  [用户访问 URL 并输入 code]
    ↓
poll_for_token()  [轮询直到授权完成或超时]
    ↓
exchange_code_for_tokens()  [PKCE 授权码交换]
    ↓
ensure_workspace_allowed()  [工作区验证]
    ↓
persist_tokens_async()  [持久化到 auth.json]
```

### 自定义反序列化

```rust
/// 处理 interval 字段可能是字符串或数字的情况
fn deserialize_interval<'de, D>(deserializer: D) -> Result<u64, D::Error>
where
    D: Deserializer<'de>,
{
    let s = String::deserialize(deserializer)?;
    s.trim().parse::<u64>().map_err(de::Error::custom)
}
```

---

## 关键代码路径与文件引用

### 内部依赖

| 依赖项 | 路径 | 用途 |
|--------|------|------|
| `PkceCodes` | `crate::pkce` | PKCE 码对结构体 |
| `ServerOptions` | `crate::server` | 服务器配置选项 |
| `exchange_code_for_tokens` | `crate::server` | OAuth 授权码交换 |
| `ensure_workspace_allowed` | `crate::server` | 工作区权限验证 |
| `persist_tokens_async` | `crate::server` | 令牌持久化 |
| `build_reqwest_client_with_custom_ca` | `codex_client` | 带自定义 CA 的 HTTP 客户端 |

### 外部 API 端点

| 端点 | 方法 | 用途 |
|------|------|------|
| `{issuer}/api/accounts/deviceauth/usercode` | POST | 请求用户码 |
| `{issuer}/api/accounts/deviceauth/token` | POST | 轮询授权码 |
| `{issuer}/oauth/token` | POST | 交换访问令牌（通过 server.rs） |

### 公开 API

```rust
// 请求设备码（用于需要自定义 UI 的场景）
pub async fn request_device_code(opts: &ServerOptions) -> std::io::Result<DeviceCode>

// 完成设备码登录（给定已获取的 DeviceCode）
pub async fn complete_device_code_login(
    opts: ServerOptions,
    device_code: DeviceCode,
) -> std::io::Result<()>

// 运行完整的设备码登录流程
pub async fn run_device_code_login(opts: ServerOptions) -> std::io::Result<()>
```

---

## 依赖与外部交互

### 直接依赖 crate

| Crate | 用途 |
|-------|------|
| `reqwest` | HTTP 客户端（异步） |
| `serde` | JSON 序列化/反序列化 |
| `tokio` | 异步运行时（`tokio::time::sleep`） |
| `codex_client` | 自定义 CA 证书支持 |
| `codex_core` | 核心认证类型（`AuthCredentialsStoreMode`） |

### 环境变量

| 变量 | 来源 | 用途 |
|------|------|------|
| `CARGO_PKG_VERSION` | 编译时 | 显示 Codex 版本 |

### 终端输出

使用 ANSI 转义码进行颜色输出：
- `\x1b[94m` - 亮蓝色（URL、用户码）
- `\x1b[90m` - 灰色（辅助信息）
- `\x1b[0m` - 重置

---

## 风险、边界与改进建议

### 已知风险

1. **超时硬编码**
   - 15 分钟超时是硬编码的（`Duration::from_secs(15 * 60)`）
   - 风险：某些企业环境可能需要更长授权时间
   - 建议：考虑通过配置或环境变量暴露此参数

2. **轮询间隔不可配置**
   - 完全依赖服务器返回的 `interval`
   - 风险：服务器返回的间隔可能不适合所有网络环境
   - 建议：添加最小/最大间隔限制

3. **状态验证缺失**
   - 设备码流程没有使用 `state` 参数进行 CSRF 防护
   - 风险：较低（设备码本身已提供一定安全性）
   - 现状：依赖 `device_auth_id` 和 `user_code` 的组合

4. **错误信息暴露**
   - 部分错误直接返回服务器响应内容
   - 风险：可能泄露敏感信息
   - 缓解：server.rs 中有 URL 敏感信息脱敏逻辑

### 边界情况

| 场景 | 行为 |
|------|------|
| 服务器返回 404 | 提示用户使用浏览器登录 |
| 用户 15 分钟内未完成授权 | 返回超时错误 |
| 服务器返回非标准 interval | 通过 `deserialize_interval` 处理字符串/数字 |
| 工作区不匹配 | 返回 `PermissionDenied` 错误，不保存凭据 |
| API Key 交换失败 | 继续保存其他令牌（`ok()` 忽略错误） |

### 改进建议

1. **可配置超时**
   ```rust
   // 建议添加
   pub struct DeviceCodeOptions {
       pub max_wait_duration: Duration,
       pub min_poll_interval: Duration,
   }
   ```

2. **进度指示**
   - 当前：静默轮询
   - 建议：添加可选的进度回调或日志输出

3. **取消支持**
   - 当前：只能通过进程终止取消
   - 建议：接受 `CancellationToken` 参数

4. **重试策略**
   - 当前：网络错误立即失败
   - 建议：对 transient 错误实施指数退避重试

5. **测试覆盖**
   - 当前：集成测试在 `tests/suite/device_code_login.rs`
   - 建议：添加单元测试覆盖错误处理路径

### 安全考虑

1. **用户码展示**：确保在共享终端环境中不会泄露
2. **验证 URL 验证**：用户应被教育验证域名真实性（防止钓鱼）
3. **TLS 验证**：依赖 `codex_client` 的自定义 CA 支持，确保企业环境可用
