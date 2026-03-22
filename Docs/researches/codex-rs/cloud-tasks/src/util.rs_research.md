# util.rs 研究文档

## 场景与职责

`util.rs` 是 Codex Cloud Tasks 的**工具函数模块**，提供跨功能的辅助功能：

- **HTTP 客户端配置**: User-Agent 设置、请求头构建
- **认证管理**: JWT 解析、AuthManager 加载、ChatGPT 账户 ID 提取
- **URL 处理**: 后端 base URL 规范化、任务 URL 构建
- **时间格式化**: 相对时间显示（"2m ago", "3h ago"）
- **错误日志**: 本地错误日志追加写入

该模块被 `lib.rs`、`env_detect.rs` 和 `ui.rs` 广泛依赖，是连接核心逻辑与基础设施的桥梁。

## 功能点目的

### 1. User-Agent 管理

```rust
pub fn set_user_agent_suffix(suffix: &str)
```

**设计意图**：
- 允许不同子命令（`exec`, `list`, `tui`）设置特定的 UA 后缀
- 通过全局锁 `USER_AGENT_SUFFIX` 安全共享
- 用于后端统计和调试

### 2. 错误日志记录

```rust
pub fn append_error_log(message: impl AsRef<str>)
```

**特点**：
- 写入当前目录 `error.log`
- 带 UTC 时间戳（RFC3339 格式）
- 静默失败（不返回错误，避免中断主流程）
- 用于调试生产环境问题

### 3. Base URL 规范化

```rust
pub fn normalize_base_url(input: &str) -> String
```

**处理逻辑**：
1. 去除尾部斜杠
2. ChatGPT 主机自动补全 `/backend-api`：
   - `https://chatgpt.com` → `https://chatgpt.com/backend-api`
   - `https://chat.openai.com` → `https://chat.openai.com/backend-api`

**用途**：统一不同配置方式（用户输入、环境变量）的 URL 格式。

### 4. JWT 账户 ID 提取

```rust
pub fn extract_chatgpt_account_id(token: &str) -> Option<String>
```

**实现细节**：
- 解析 JWT 结构（header.payload.signature）
- Base64 URL_SAFE_NO_PAD 解码 payload
- 提取 `https://api.openai.com/auth.chatgpt_account_id` 字段

**用途**：当 AuthManager 未提供账户 ID 时，从 token 中回退获取。

### 5. 认证管理器加载

```rust
pub async fn load_auth_manager() -> Option<AuthManager>
```

**当前限制**：
- TODO 注释表明计划支持 CLI 覆盖参数
- 目前传入空向量 `Vec::new()`

### 6. ChatGPT 请求头构建

```rust
pub async fn build_chatgpt_headers() -> HeaderMap
```

**构建的头信息**：
- `User-Agent`: 带后缀的 Codex UA
- `Authorization`: `Bearer {token}`（如果已认证）
- `ChatGPT-Account-Id`: 账户标识（如果可用）

**异步原因**：需要调用 `load_auth_manager().await` 获取认证状态。

### 7. 任务 URL 构建

```rust
pub fn task_url(base_url: &str, task_id: &str) -> String
```

**路径映射规则**：

| Base URL 模式 | 生成的 URL |
|--------------|-----------|
| `*/backend-api` | `{root}/codex/tasks/{task_id}` |
| `*/api/codex` | `{root}/codex/tasks/{task_id}` |
| `*/codex` | `{base}/tasks/{task_id}` |
| 其他 | `{base}/codex/tasks/{task_id}` |

**用途**：生成用户可在浏览器中打开的任务详情链接。

### 8. 相对时间格式化

```rust
pub fn format_relative_time(reference: DateTime<Utc>, ts: DateTime<Utc>) -> String
pub fn format_relative_time_now(ts: DateTime<Utc>) -> String
```

**输出格式**：
- `< 60s`: `"{secs}s ago"`
- `< 60m`: `"{mins}m ago"`
- `< 24h`: `"{hours}h ago"`
- `>= 24h`: `"{Mon} {Day} {HH:MM}"`（本地时区）

**负时间处理**：
```rust
if secs < 0 { secs = 0; }  // 未来时间显示为 "0s ago"
```

## 具体技术实现

### 关键数据结构

```rust
// 来自 codex_core::default_client
static USER_AGENT_SUFFIX: Mutex<Option<String>>
```

### 函数调用关系

```
build_chatgpt_headers()
├── set_user_agent_suffix("codex_cloud_tasks_tui")
├── codex_core::default_client::get_codex_user_agent()
└── load_auth_manager()
    ├── Config::load_with_cli_overrides(Vec::new())
    └── AuthManager::new(codex_home, false, credentials_store_mode)
        └── auth.get_token()
        └── auth.get_account_id()
            └── extract_chatgpt_account_id(token) [fallback]

task_url()
└── normalize_base_url()

append_error_log()
└── std::fs::OpenOptions::new()
    .create(true)
    .append(true)
    .open("error.log")
```

### 错误处理策略

| 函数 | 错误处理 |
|------|----------|
| `set_user_agent_suffix` | 静默忽略（lock 失败） |
| `append_error_log` | 静默忽略（所有 IO 错误） |
| `extract_chatgpt_account_id` | 返回 `Option`（解析失败返回 None） |
| `load_auth_manager` | 返回 `Option`（加载失败返回 None） |
| `build_chatgpt_headers` | 部分构建（认证失败仍返回基础头） |

## 关键代码路径与文件引用

### User-Agent 设置

**文件**: `lib.rs:48`
```rust
set_user_agent_suffix("codex_cloud_tasks_tui");
```

**文件**: `lib.rs:158`
```rust
set_user_agent_suffix("codex_cloud_tasks_exec");
```

### 错误日志写入

**文件**: `lib.rs`（多处）
```rust
append_error_log(format!("startup: base_url={base_url} path_style={style}"));
append_error_log(format!("auth: mode=ChatGPT account_id={acc}"));
append_error_log(format!("refresh.apply: env={} count={}", ...));
```

### 请求头构建

**文件**: `env_detect.rs:47-48`
```rust
let headers = util::build_chatgpt_headers().await;
match get_json::<Vec<CodeEnvironment>>(&url, &headers).await { ... }
```

**文件**: `lib.rs:846`
```rust
let headers = crate::util::build_chatgpt_headers().await;
```

### 任务 URL 生成

**文件**: `lib.rs:178`
```rust
let url = util::task_url(&ctx.base_url, &created.id.0);
println!("{url}");
```

**文件**: `ui.rs:808`
```rust
let when = format_relative_time_now(t.updated_at).dim();
```

## 依赖与外部交互

### 外部 Crate

| Crate | 用途 |
|-------|------|
| `base64` | JWT payload Base64 解码 |
| `chrono` | UTC/Local 时间处理 |
| `reqwest` | HTTP HeaderMap 类型 |
| `codex_core` | User-Agent 全局状态、Config |
| `codex_login` | AuthManager 认证管理 |

### 内部模块交互

```
util.rs
├── codex_core::default_client
│   ├── USER_AGENT_SUFFIX (全局锁)
│   └── get_codex_user_agent()
├── codex_core::config::Config
│   └── load_with_cli_overrides()
├── codex_login::AuthManager
│   ├── auth().await
│   ├── get_token()
│   └── get_account_id()
└── 被以下模块使用:
    ├── lib.rs (主逻辑)
    ├── env_detect.rs (环境检测)
    └── ui.rs (时间格式化)
```

## 风险、边界与改进建议

### 当前风险

1. **全局可变状态**
   ```rust
   static USER_AGENT_SUFFIX: Mutex<Option<String>>
   ```
   - 进程级共享，多实例测试可能相互影响
   - 没有重置机制

2. **错误日志路径硬编码**
   ```rust
   .open("error.log")  // 当前工作目录
   ```
   - 可能写入意外位置（如果 CWD 变化）
   - 没有大小限制，可能无限增长
   - 没有轮转机制

3. **JWT 解析脆弱**
   ```rust
   let (_h, payload_b64, _s) = match (parts.next(), parts.next(), parts.next()) {
       (Some(h), Some(p), Some(s)) if !h.is_empty() && !p.is_empty() && !s.is_empty() => ...
   ```
   - 不验证签名
   - 不处理 Base64 padding 变体
   - 假设特定 JWT 结构

4. **URL 规范化过于特定**
   - 仅处理 ChatGPT 特定主机
   - 其他 OpenAI 兼容端点可能需要额外规则

### 边界情况

| 场景 | 当前行为 |
|------|----------|
| 空 token | `extract_chatgpt_account_id` 返回 None |
| 无效 JWT 格式 | 返回 None |
| JWT payload 非 JSON | 返回 None |
| 缺少 account_id 字段 | 返回 None |
| 未来时间戳 | 显示 "0s ago" |
| 空 base_url | `normalize_base_url` 返回空字符串 |
| 认证管理器加载失败 | `build_chatgpt_headers` 返回无认证头 |

### 改进建议

1. **配置化错误日志**
   ```rust
   pub fn append_error_log_with_path(message: &str, path: Option<&Path>) {
       let path = path.unwrap_or_else(|| Path::new("error.log"));
       // 支持配置路径和大小限制
   }
   ```

2. **日志轮转**
   ```rust
   // 当文件超过 10MB 时重命名
   if file.metadata()?.len() > 10_000_000 {
       fs::rename("error.log", "error.log.old")?;
   }
   ```

3. **JWT 解析增强**
   ```rust
   // 使用标准 JWT 库
   use jsonwebtoken::{decode, DecodingKey, Validation};
   
   pub fn extract_chatgpt_account_id(token: &str) -> Option<String> {
       // 虽然不验证签名，但使用标准解析更安全
   }
   ```

4. **URL 规范化配置化**
   ```rust
   lazy_static! {
       static ref URL_RULES: Vec<(Regex, Box<dyn Fn(&str) -> String>)> = vec![...];
   }
   ```

5. **时间格式化国际化**
   ```rust
   // 支持多语言相对时间
   pub fn format_relative_time_i18n(
       reference: DateTime<Utc>, 
       ts: DateTime<Utc>,
       locale: &str
   ) -> String
   ```

6. **认证缓存**
   ```rust
   // 避免每次 build_chatgpt_headers 都重新加载配置
   static AUTH_CACHE: RwLock<Option<(AuthManager, Instant)>> = ...;
   ```

7. **单元测试覆盖**
   - 当前模块无直接测试
   - 建议添加：
     - `normalize_base_url` 各种输入组合
     - `extract_chatgpt_account_id` 有效/无效 JWT
     - `format_relative_time` 边界值
