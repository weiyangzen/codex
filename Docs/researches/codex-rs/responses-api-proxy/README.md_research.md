# README.md 研究文档

## 场景与职责

此文档是 `codex-responses-api-proxy` 的用户指南和架构说明。该组件是一个**安全隔离代理**，核心目的是解决多用户环境下的 API 密钥保护问题：让特权用户（如 root）持有敏感的 OpenAI API 密钥，同时允许非特权用户通过代理安全地调用 API，而无需接触或查看密钥。

## 功能点目的

### 核心安全目标

1. **密钥隔离**: 非特权用户无法通过 `/proc/<pid>/environ`、进程内存查看等方式获取 API 密钥
2. **最小权限**: 仅转发 `POST /v1/responses` 请求，拒绝所有其他路径和方法
3. **内存保护**: 使用 `mlock(2)` 防止密钥被交换到磁盘，使用 `zeroize` 清除临时缓冲区
4. **进程加固**: 禁用 core dump、ptrace attach 等潜在泄露途径

### 使用场景

- **企业/共享环境**: 管理员持有 API 密钥，开发人员通过代理使用
- **CI/CD 管道**: 密钥由 orchestrator 注入，构建任务通过代理访问
- **安全审计**: 所有 API 请求通过单一控制点，便于监控和审计

## 具体技术实现

### 启动流程

```bash
# 特权用户启动（密钥通过 stdin 传入，不在命令行暴露）
printenv OPENAI_API_KEY | env -u OPENAI_API_KEY codex-responses-api-proxy \
    --http-shutdown \
    --server-info /tmp/server-info.json
```

关键安全细节：
- `env -u OPENAI_API_KEY` 从子进程环境移除密钥
- 密钥通过管道从 stdin 读取，避免命令行历史记录
- `--server-info` 写入端口和 PID，便于客户端发现

### 客户端配置

```bash
# 读取代理端口
PROXY_PORT=$(jq .port /tmp/server-info.json)
PROXY_BASE_URL="http://127.0.0.1:${PROXY_PORT}"

# 配置 Codex CLI 使用代理
codex exec \
    -c "model_providers.openai-proxy={ name = 'OpenAI Proxy', base_url = '${PROXY_BASE_URL}/v1', wire_api='responses' }" \
    -c model_provider="openai-proxy" \
    'Your prompt here'
```

### 关闭机制

```bash
# 非特权用户可通过 HTTP 关闭（因为无法发送 SIGTERM）
curl --fail --silent --show-error "${PROXY_BASE_URL}/shutdown"
```

### 请求处理流程

```
Client Request
    ↓
POST /v1/responses (exact match, no query string)
    ↓
[Reject others with 403]
    ↓
Forward to https://api.openai.com/v1/responses
    ↓
Inject Authorization: Bearer <key>
    ↓
Forward all original headers (except Authorization, Host)
    ↓
Override Host header to api.openai.com
    ↓
Return upstream response (status, headers, body)
```

### CLI 参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--port <PORT>` | 监听端口 | 0（随机端口） |
| `--server-info <FILE>` | 写入服务器信息 JSON | 无 |
| `--http-shutdown` | 启用 GET /shutdown | 禁用 |
| `--upstream-url <URL>` | 上游 API 地址 | https://api.openai.com/v1/responses |

### Azure OpenAI 支持

```bash
printenv AZURE_OPENAI_API_KEY | env -u AZURE_OPENAI_API_KEY codex-responses-api-proxy \
    --http-shutdown \
    --server-info /tmp/server-info.json \
    --upstream-url "https://YOUR_PROJECT.openai.azure.com/openai/deployments/YOUR_DEPLOYMENT/responses?api-version=2025-04-01-preview"
```

## 关键代码路径与文件引用

### 源码结构

```
codex-rs/responses-api-proxy/src/
├── main.rs          # 二进制入口，初始化进程加固
├── lib.rs           # 核心逻辑：HTTP 服务器、请求转发
└── read_api_key.rs  # 安全的 API 密钥读取和内存保护
```

### 关键实现细节

#### 1. 密钥读取 (`read_api_key.rs`)

```rust
// 栈缓冲区读取，避免堆分配中间副本
let mut buf = [0u8; BUFFER_SIZE];  // 1024 字节
buf[..AUTH_HEADER_PREFIX.len()].copy_from_slice(b"Bearer ");

// 低层 read(2) 调用，绕过 std::io::stdin() 的 BufReader
// 避免 BufReader 内部缓冲导致的密钥残留
libc::read(STDIN_FILENO, buffer, buffer.len());

// 验证密钥格式：/^[a-zA-Z0-9_-]+$/
validate_auth_header_bytes(key_bytes)?;

// 创建 String 后立即清零栈缓冲区
let header_value = String::from(header_str);
buf.zeroize();

// 内存泄漏以获得 'static 生命周期，然后 mlock
let leaked: &'static mut str = header_value.leak();
mlock_str(leaked);
```

#### 2. 请求转发 (`lib.rs`)

```rust
fn forward_request(...) -> Result<()> {
    // 严格路径检查
    let allow = method == Method::Post && url_path == "/v1/responses";
    if !allow {
        return respond_with(403);
    }
    
    // 构建上游请求头
    let mut auth_header_value = HeaderValue::from_static(auth_header);
    auth_header_value.set_sensitive(true);  // 标记敏感头
    headers.insert(AUTHORIZATION, auth_header_value);
    
    // 转发请求
    client.post(upstream_url).headers(headers).body(body).send()
}
```

#### 3. 进程加固 (`main.rs`)

```rust
#[ctor::ctor]
fn pre_main() {
    codex_process_hardening::pre_main_hardening();
    // 禁用 core dump
    // 禁用 ptrace attach
    // 移除 LD_PRELOAD, DYLD_* 等危险环境变量
}
```

## 依赖与外部交互

### 运行时依赖

| 组件 | 交互方式 | 目的 |
|------|----------|------|
| OpenAI API | HTTPS POST | 转发请求到 api.openai.com |
| stdin | 管道读取 | 安全接收 API 密钥 |
| mlock(2) | 系统调用 | 锁定密钥内存 |
| tiny_http | 库 | 接收客户端请求 |
| reqwest | 库 | 转发到上游 |

### 调用方

- **Codex CLI**: 通过 `--model_provider` 配置使用代理
- **其他 HTTP 客户端**: 任何能发送 POST /v1/responses 的客户端

### 被调用方

- **OpenAI API**: `https://api.openai.com/v1/responses`
- **Azure OpenAI**: 可配置的自定义上游 URL

## 风险、边界与改进建议

### 安全风险

1. **内存残留风险**: 虽然使用了 `mlock` 和 `zeroize`，但 HTTP 库 (`reqwest`, `tiny_http`) 可能在内部缓冲中复制数据
2. **侧信道攻击**: 未防御时序攻击（密钥验证时间可能泄露长度信息）
3. **DoS 风险**: 无速率限制，恶意客户端可耗尽代理资源

### 功能边界

1. **单端点限制**: 仅支持 `/v1/responses`，不支持其他 OpenAI API（如 /v1/chat/completions）
2. **无 TLS 终止**: 代理本身使用 HTTP，依赖本地网络隔离
3. **无认证**: 代理本身无客户端认证，依赖网络隔离
4. **单密钥**: 不支持多租户或多密钥轮换

### 改进建议

#### 高优先级

1. **添加速率限制**: 防止资源耗尽
```rust
// 建议添加基于 IP 或全局的请求速率限制
```

2. **请求/响应日志**: 可选的审计日志（注意避免记录敏感头）
```rust
// 记录时间戳、客户端 IP、请求大小，但不记录 Authorization
```

3. **健康检查端点**: 添加 `/health` 用于监控

#### 中优先级

4. **配置热重载**: 支持不重启更新上游 URL

5. **多上游支持**: 支持故障转移或负载均衡

6. **Prometheus 指标**: 暴露请求延迟、错误率等指标

#### 低优先级

7. **Unix Socket 支持**: 替代 TCP，提供更好的本地隔离

8. **请求大小限制**: 防止大请求导致的内存问题

### 代码改进

1. **错误处理细化**: 当前直接返回 403，可区分 403/405/400 提供更精确的错误
2. **超时配置**: 当前 `reqwest` 禁用超时，应可配置流式响应超时
3. **连接池调优**: 当前使用默认连接池配置，可能需要针对高并发调整
