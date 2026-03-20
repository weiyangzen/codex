# codex-rs/codex-client/src 研究

## 场景与职责
`codex-client` 是 `codex-rs` 中的通用传输层 crate：它不关心具体 OpenAI/Codex 业务语义，只负责把“请求对象 -> HTTP/SSE/WS 传输结果”这层抽象做稳定。

核心职责：

1. 提供统一传输接口 `HttpTransport` 及默认实现 `ReqwestTransport`，为上层（`codex-api`/`core`）屏蔽 reqwest 细节。
2. 提供请求/响应基础模型（`Request`/`Response`/`StreamResponse`）和错误模型（`TransportError`/`StreamError`）。
3. 提供可配置重试能力（`RetryPolicy`/`RetryOn`/`run_with_retry`）。
4. 提供 SSE 原始帧转发 helper（`sse_stream`）。
5. 统一企业网络场景下的自定义 CA 处理（`CODEX_CA_CERTIFICATE`、`SSL_CERT_FILE`）。
6. 在默认请求构建器层注入 OpenTelemetry trace header，保证跨服务追踪延续。

模块导出总入口在 `codex-rs/codex-client/src/lib.rs:1-36`，对外 re-export 了上述关键能力。

## 功能点目的
1. **传输解耦**
- 通过 `HttpTransport` trait（`codex-rs/codex-client/src/transport.rs:27-29`），上层可以在测试中替换 transport，避免和真实网络耦合。

2. **统一请求表达**
- `Request` 将 method/url/headers/body/compression/timeout 放在一个值对象里（`codex-rs/codex-client/src/request.rs:16-23`），便于重试时重复构造。

3. **请求压缩（zstd）**
- 为 Responses 等大 body 场景减少带宽与延迟，在 transport 层自动设置 `Content-Encoding: zstd`（`codex-rs/codex-client/src/transport.rs:63-104`）。

4. **重试策略下沉**
- 避免每个业务 endpoint 重复写 backoff/重试判定；上层只给出策略参数（`codex-rs/codex-client/src/retry.rs:9-36,49-74`）。

5. **自定义 CA 一致性**
- HTTP（reqwest）与 websocket（rustls）共享同一 CA 环境变量语义，防止“HTTP 能连、WS 证书失败”的分裂行为（`codex-rs/codex-client/src/custom_ca.rs:179-199`）。

6. **可观测性基础设施**
- `CodexRequestBuilder::send` 在请求前注入 trace header，在请求完成/失败时统一打 debug 日志（`codex-rs/codex-client/src/default_client.rs:113-166`）。

## 具体技术实现（关键流程/数据结构/协议/命令）
### 1) 传输主流程（Unary + Stream）
入口：`ReqwestTransport::execute/stream`（`codex-rs/codex-client/src/transport.rs:124-188`）

流程：
1. 从 `Request` 组装 builder（`build`，`codex-rs/codex-client/src/transport.rs:44-111`）。
2. 若存在 `timeout`，写入 reqwest builder（`transport.rs:58-60`）。
3. 若有 `body` 且启用压缩：
- 先把 JSON 序列化为 bytes。
- 用 zstd level=3 压缩。
- 设置 `Content-Encoding: zstd`；若缺失 `Content-Type` 则补 `application/json`（`transport.rs:74-97`）。
4. 发送请求并做错误映射：timeout -> `TransportError::Timeout`，其余 reqwest 错误 -> `TransportError::Network`（`transport.rs:114-120`）。
5. 非 2xx：组装 `TransportError::Http {status, url, headers, body}`（`transport.rs:142-147,173-178`）。
6. 2xx：
- unary 返回 `Response { status, headers, body: Bytes }`；
- stream 返回 `StreamResponse { status, headers, bytes: ByteStream }`。

相关协议/头：
- 方法：`http::Method`（由 `Request.method` 驱动）。
- 压缩协议：`Content-Encoding: zstd`。
- SSE 场景通常由上层设置 `Accept: text/event-stream`（在 `codex-api` 中，见 `codex-rs/codex-api/src/endpoint/responses.rs:129-137`）。

### 2) 数据结构与错误模型
`RequestCompression`（`codex-rs/codex-client/src/request.rs:9-13`）：当前支持 `None`、`Zstd`。

`Request`（`request.rs:16-23`）：
- `method: Method`
- `url: String`
- `headers: HeaderMap`
- `body: Option<Value>`
- `compression: RequestCompression`
- `timeout: Option<Duration>`

`TransportError`（`codex-rs/codex-client/src/error.rs:6-23`）：
- `Http{...}`：服务器返回非 2xx
- `RetryLimit`：重试穷尽
- `Timeout` / `Network` / `Build`

`StreamError`（`error.rs:25-30`）：SSE helper 使用，区分流错误与 idle timeout。

### 3) 重试机制
`RetryPolicy` + `RetryOn`（`codex-rs/codex-client/src/retry.rs:9-36`）定义“最多尝试次数、基础延迟、针对哪些错误重试”。

`run_with_retry`（`retry.rs:49-74`）流程：
1. 每轮调用 `make_req()` 重新构造请求，避免重用消耗态对象。
2. 调用实际操作 `op(req, attempt)`。
3. 若命中 `RetryOn::should_retry`，sleep(backoff) 后继续。
4. 否则返回成功或失败。

`backoff`（`retry.rs:38-47`）为指数退避 + 0.9~1.1 jitter，避免 thundering herd。

### 4) SSE helper（底层原始 data 帧）
`sse_stream`（`codex-rs/codex-client/src/sse.rs:12-48`）会：
1. 把 `ByteStream` 包装成 `eventsource_stream`。
2. 循环 `timeout(idle_timeout, stream.next())`。
3. 将 `ev.data` 原样转发到 `mpsc::Sender<Result<String, StreamError>>`。
4. 对 stream error/提前关闭/idle timeout 发送 `Err(...)` 并退出。

说明：目前仓库内主要 SSE 业务解析在 `codex-api/src/sse/responses.rs`，`codex-client::sse_stream` 更偏通用低层能力（`codex-rs/codex-api/src/sse/responses.rs:357-430`）。

### 5) 默认 HTTP 客户端包装与 trace 注入
`CodexHttpClient` / `CodexRequestBuilder`（`codex-rs/codex-client/src/default_client.rs:17-166`）本质是 reqwest 薄封装：
- 保留 method/url 用于日志。
- `send()` 前调用 `trace_headers()` 注入 W3C trace context（`default_client.rs:113-166`）。
- 请求完成或失败时输出结构化 debug 日志（method/url/status）。

trace 注入实现：
- `HeaderMapInjector` + `opentelemetry::global::get_text_map_propagator`（`default_client.rs:143-166`）。

### 6) 自定义 CA（HTTP + Websocket 一致）
`custom_ca.rs` 是该目录最复杂模块（`codex-rs/codex-client/src/custom_ca.rs:1-788`）。

关键语义：
1. 环境变量优先级：`CODEX_CA_CERTIFICATE` > `SSL_CERT_FILE`；空字符串视为未设置（`custom_ca.rs:338-377`）。
2. 读取 PEM 证书 bundle 并提取所有可解析 certificate。
3. 兼容 OpenSSL `TRUSTED CERTIFICATE` 标签，并裁剪 X509_AUX 尾部（`custom_ca.rs:541-611,628-676`）。
4. 忽略 CRL section（`custom_ca.rs:473-482`）。
5. reqwest 构建失败与证书注册失败均返回带修复提示的结构化错误（`BuildCustomCaTransportError`，`custom_ca.rs:74-145`）。
6. websocket 场景走 `maybe_build_rustls_client_config_with_custom_ca`，在系统 roots 基础上叠加 custom roots（`custom_ca.rs:215-262`）。

错误提示统一包含 `CA_CERT_HINT`（`custom_ca.rs:63`），直接引导用户检查 PEM 内容或取消覆盖。

### 7) 测试与命令
测试分层：
1. `custom_ca.rs` 内部单测：验证 env 优先级、空值处理、rustls config 行为（`custom_ca.rs:682-788`）。
2. 进程级集成测试：`tests/ca_env.rs` 通过 `cargo_bin("custom_ca_probe")` 启动子进程，规避并行测试下环境变量污染（`codex-rs/codex-client/tests/ca_env.rs:32-45`，`src/bin/custom_ca_probe.rs:1-29`）。

典型命令：
- `cargo test -p codex-client`
- 定向：`cargo test -p codex-client --test ca_env`

构建系统注意点：
- `BUILD.bazel` 显式把 `tests/fixtures/**` 放进 `compile_data`，确保 Bazel 下 `include_str!` 可访问 fixture（`codex-rs/codex-client/BUILD.bazel:4-6`）。

## 关键代码路径与文件引用
### 目录内关键文件
1. `codex-rs/codex-client/src/lib.rs`：crate 统一导出面（尤其 `custom_ca` 能力对外暴露）。
2. `codex-rs/codex-client/src/transport.rs`：HTTP 执行、stream、压缩、错误映射。
3. `codex-rs/codex-client/src/request.rs`：Request/Response 模型。
4. `codex-rs/codex-client/src/retry.rs`：重试策略与执行器。
5. `codex-rs/codex-client/src/default_client.rs`：带 trace 注入的 reqwest 包装。
6. `codex-rs/codex-client/src/custom_ca.rs`：企业网络/证书兼容核心。
7. `codex-rs/codex-client/src/sse.rs`：通用 SSE data 帧转发。
8. `codex-rs/codex-client/src/error.rs`、`telemetry.rs`：错误与 telemetry trait。
9. `codex-rs/codex-client/src/bin/custom_ca_probe.rs`：给 subprocess 测试复用的探针二进制。
10. `codex-rs/codex-client/tests/ca_env.rs`：CA 行为进程级回归测试。

### 典型调用路径（上游 -> 本目录 -> 下游）
1. `codex-core` Responses 流式调用：
- 上游创建 `ReqwestTransport::new(build_reqwest_client())`（`codex-rs/core/src/client.rs:1026`）。
- `codex-api` 的 `EndpointSession::stream_with` 调用 `run_with_request_telemetry`（`codex-rs/codex-api/src/endpoint/session.rs:109-136`）。
- `run_with_request_telemetry` 再调用 `codex_client::run_with_retry`（`codex-rs/codex-api/src/telemetry.rs:68-95`）。
- 最终落到 `ReqwestTransport::stream`（`codex-rs/codex-client/src/transport.rs:156-188`）。

2. Responses 请求压缩路径：
- `codex-api` 把业务 `Compression::Zstd` 转成 `RequestCompression::Zstd`（`codex-rs/codex-api/src/endpoint/responses.rs:124`）。
- `ReqwestTransport::build` 执行 zstd 压缩和头设置（`codex-rs/codex-client/src/transport.rs:63-104`）。

3. Websocket TLS custom CA 路径：
- `responses_websocket`/`realtime_websocket` 调用 `maybe_build_rustls_client_config_with_custom_ca`（`codex-rs/codex-api/src/endpoint/responses_websocket.rs:360`，`codex-rs/codex-api/src/endpoint/realtime_websocket/methods.rs:481`）。
- 由 `custom_ca.rs` 统一完成证书加载与 root store 组装（`codex-rs/codex-client/src/custom_ca.rs:215-262`）。

4. 通用 reqwest 客户端构建路径：
- `core::default_client::try_build_reqwest_client` 调 `build_reqwest_client_with_custom_ca`（`codex-rs/core/src/default_client.rs:204-215`）。
- `login`/`backend-client`/`cloud-tasks`/`rmcp-client` 也直接复用同一入口（如 `codex-rs/login/src/server.rs:695`，`codex-rs/backend-client/src/client.rs:124`，`codex-rs/cloud-tasks/src/env_detect.rs:77`，`codex-rs/rmcp-client/src/rmcp_client.rs:138`）。

## 依赖与外部交互
### 代码依赖（Cargo）
见 `codex-rs/codex-client/Cargo.toml:1-35`，关键依赖包括：
- `reqwest`：HTTP 客户端。
- `eventsource-stream` + `futures`：SSE byte stream 解析。
- `tokio`：异步 runtime、timeout、sleep、channel。
- `rustls`/`rustls-native-certs`/`rustls-pki-types`：TLS root store 与证书处理。
- `zstd`：请求体压缩。
- `opentelemetry` + `tracing-opentelemetry`：trace header 注入。

### 外部交互面
1. **网络**
- HTTP 请求（reqwest）。
- websocket TLS 配置（供 tungstenite connector 使用）。

2. **环境变量**
- `CODEX_CA_CERTIFICATE`、`SSL_CERT_FILE`（custom CA 选择来源，`custom_ca.rs:61-62`）。

3. **文件系统**
- 读取 PEM CA 文件（`custom_ca.rs:497-503`）。
- 测试读取 fixture（`tests/fixtures/*` + `compile_data`）。

4. **可观测性**
- tracing info/warn/debug。
- OpenTelemetry trace context 注入 HTTP headers。

### 文档与脚本上下文
1. `codex-rs/codex-client/README.md:1-8`：说明 crate 目标为通用 transport 层。
2. `codex-rs/codex-api/README.md:3,37`：明确 `codex-api` 构建在 `codex-client` 之上。
3. 本次研究流程相关脚本：`.ops/generate_daily_research_todo.sh`（按要求执行）。

## 风险、边界与改进建议
### 风险与边界
1. **`Request::with_json` 静默丢弃序列化错误**
- 代码：`self.body = serde_json::to_value(body).ok();`（`codex-rs/codex-client/src/request.rs:37-39`）。
- 风险：序列化失败时 body 会变成 `None`，调用方难以定位问题。

2. **未知 HTTP method 默认降级为 GET**
- 代码：`Method::from_bytes(...).unwrap_or(Method::GET)`（`codex-rs/codex-client/src/transport.rs:54-56`）。
- 风险：method 解析异常时可能发送到错误语义的请求路径。

3. **重试 attempt 语义易误解**
- `run_with_retry` 的 attempt 从 0 开始，但 backoff 使用 `attempt + 1`（`retry.rs:58,67`）。
- 风险：调用方做 attempt 级 telemetry/报警时需要理解“第 0 次是首次请求”。

4. **`sse_stream` 当前在仓库内部复用有限**
- 搜索显示仅定义与导出，主要业务 SSE 解析在 `codex-api`（`codex-rs/codex-api/src/sse/responses.rs:357-430`）。
- 风险：若长期无调用，可能演化为低覆盖路径。

5. **PEM 兼容策略仍有已知限制**
- 注释明确：如果 bundle 中 CRL section 本身 malformed，当前仍可能提前失败（`custom_ca.rs:450-456`）。

### 改进建议
1. 将 `Request::with_json` 从静默 `.ok()` 改为返回 `Result<Self, TransportError>` 或新增 `try_with_json`，避免无声失败。
2. `transport` 中 method 解析失败建议返回 `TransportError::Build`，不再隐式 fallback GET。
3. 统一 SSE 抽象边界：评估 `codex-client::sse_stream` 与 `codex-api::process_sse` 的职责关系，避免双实现长期分叉。
4. 为 custom CA 增加“malformed CRL + valid cert”回归用例，明确未来是否要做到“忽略 malformed CRL 但保留 cert”。
5. 为 `RequestCompression` 预留可扩展策略（如阈值压缩、按 content-type 压缩），减少上层重复控制逻辑。

