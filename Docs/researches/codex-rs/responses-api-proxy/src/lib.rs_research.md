# codex-rs/responses-api-proxy/src/lib.rs 研究文档

## 场景与职责

`lib.rs` 是 `codex-responses-api-proxy` crate 的核心库文件，实现了一个**最小化的 OpenAI Responses API HTTP 代理服务器**。该代理的主要设计目标是在**特权用户**（拥有 API key）和**非特权用户**之间建立一个安全隔离层：

- **特权用户**（如 root）启动代理，通过 stdin 传入 API key
- **非特权用户**通过本地 HTTP 接口访问 OpenAI API，无需直接接触 API key
- 代理仅允许 `POST /v1/responses` 请求，其他所有请求返回 403 Forbidden

这种设计模式解决了多用户环境下 API key 安全分发的问题，同时通过严格的请求过滤最小化攻击面。

## 功能点目的

### 1. CLI 参数解析 (`Args`)
| 参数 | 用途 |
|------|------|
| `--port` | 监听端口，未指定时使用临时端口 |
| `--server-info` | 写入启动信息（JSON 格式包含 port 和 pid） |
| `--http-shutdown` | 启用 `GET /shutdown` 端点，允许非特权用户关闭代理 |
| `--upstream-url` | 上游 API 地址，默认 OpenAI |

### 2. 请求转发核心逻辑
- **严格路径检查**：仅允许 `POST /v1/responses`，不允许 query string
- **Header 处理**：
  - 移除客户端传入的 `Authorization` 和 `Host`
  - 注入从 stdin 读取的 `Authorization: Bearer <key>`
  - 设置正确的 `Host` 指向 upstream
- **流式响应支持**：使用 `reqwest::blocking::Response` 的 `Read` trait 直接作为响应体

### 3. 服务器生命周期管理
- 支持动态端口绑定（`bind_listener`）
- 启动信息持久化（`write_server_info`）便于进程间协调
- 每个请求在独立线程中处理（`std::thread::spawn`）

## 具体技术实现

### 关键数据结构

```rust
// 服务器配置
pub struct Args {
    pub port: Option<u16>,
    pub server_info: Option<PathBuf>,
    pub http_shutdown: bool,
    pub upstream_url: String,
}

// 内部转发配置（Arc 共享）
struct ForwardConfig {
    upstream_url: Url,
    host_header: HeaderValue,
}

// 启动信息输出
#[derive(Serialize)]
struct ServerInfo {
    port: u16,
    pid: u32,
}
```

### 核心流程

```
run_main()
├── read_auth_header_from_stdin()     # 从 stdin 读取 API key（见 read_api_key.rs）
├── 解析 upstream_url，构建 Host header
├── bind_listener()                   # 绑定 TCP 监听
├── write_server_info()               # 可选：写入启动信息
├── Server::from_listener()           # 创建 tiny_http 服务器
│
└── 请求处理循环
    ├── 检查 http_shutdown 请求 → process::exit(0)
    └── forward_request()
        ├── 验证 method == POST && path == "/v1/responses"
        ├── 读取请求体
        ├── 构建 upstream headers（过滤 auth/host，注入新 auth）
        ├── reqwest::blocking::Client::post()
        └── 流式返回响应
```

### 安全相关的 Header 处理

```rust
// 构建 upstream 请求头时：
1. 遍历客户端 headers，跳过 authorization 和 host
2. 使用 HeaderValue::from_static() + set_sensitive(true) 保护 API key
3. 强制设置 Host header 为 upstream 主机

let mut auth_header_value = HeaderValue::from_static(auth_header);
auth_header_value.set_sensitive(true);
headers.insert(AUTHORIZATION, auth_header_value);
```

### 响应头过滤

转发 upstream 响应时，跳过 tiny_http 自动管理的头：
- `content-length`
- `transfer-encoding`
- `connection`
- `trailer`
- `upgrade`

## 关键代码路径与文件引用

| 路径 | 说明 |
|------|------|
| `src/lib.rs:66-116` | `run_main()` 主入口 |
| `src/lib.rs:118-123` | `bind_listener()` TCP 绑定 |
| `src/lib.rs:125-141` | `write_server_info()` 启动信息写入 |
| `src/lib.rs:143-237` | `forward_request()` 请求转发核心 |
| `src/lib.rs:186-188` | 敏感 header 处理（set_sensitive） |
| `src/read_api_key.rs` | API key 读取与安全存储（模块引用） |

## 依赖与外部交互

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `tiny_http` | 轻量级 HTTP 服务器 |
| `reqwest` (blocking) | 同步 HTTP 客户端，转发请求到 upstream |
| `clap` | CLI 参数解析 |
| `serde`/`serde_json` | 启动信息 JSON 序列化 |
| `anyhow` | 错误处理 |

### 内部 crate 依赖

| Crate | 用途 |
|-------|------|
| `codex-process-hardening` | 进程安全加固（在 main.rs 中通过 ctor 调用） |

### 外部系统交互

1. **文件系统**：写入 `--server-info` 指定的 JSON 文件
2. **网络**：
   - 监听 `127.0.0.1:<port>`（仅本地）
   - 连接到 `api.openai.com` 或自定义 upstream
3. **标准输入**：从 stdin 读取 API key（通过 `read_api_key` 模块）

## 风险、边界与改进建议

### 已知风险

1. **线程模型风险**：每个请求 spawn 一个新线程（`std::thread::spawn`），在高并发场景下可能导致资源耗尽。建议考虑使用线程池。

2. **缺乏请求超时**：`reqwest::Client` 设置了 `.timeout(None)` 以支持长连接流式响应，但这也意味着恶意慢速连接可能占用资源。

3. **shutdown 端点安全性**：`--http-shutdown` 允许任何能访问 localhost 的用户关闭代理，虽然符合设计目标，但在共享机器上需要谨慎使用。

4. **请求体大小限制**：当前实现读取整个请求体到内存（`Vec::new()`），大请求可能导致内存问题。

### 边界条件

| 场景 | 行为 |
|------|------|
| 非 POST 请求 | 返回 403 |
| 非 /v1/responses 路径 | 返回 403 |
| 路径带 query string | 返回 403（严格字符串匹配） |
| upstream 不可达 | 错误打印到 stderr，客户端无响应 |
| API key 验证失败 | 由 upstream 返回错误，代理透明转发 |

### 改进建议

1. **添加请求/响应日志**：当前实现完全静默，调试困难。可考虑添加可选的日志级别。

2. **支持配置最大请求体大小**：防止内存耗尽攻击。

3. **考虑异步化**：使用 `tokio` 替代 `reqwest::blocking` 和手动线程管理，提升性能。

4. **健康检查端点**：除 shutdown 外，添加 `/health` 用于监控。

5. ** graceful shutdown**：当前 `GET /shutdown` 直接调用 `process::exit(0)`，正在处理的请求可能被中断。

6. **连接池优化**：`reqwest::Client` 已经内置连接池，但每个请求在新线程中使用可能无法充分利用。
