# codex-rs/codex-client/src/bin 研究

## 场景与职责
目标目录 `codex-rs/codex-client/src/bin` 当前仅包含一个二进制入口：`custom_ca_probe.rs`（`codex-rs/codex-client/src/bin/custom_ca_probe.rs:1-29`）。

该入口不是面向终端用户的业务 CLI，而是 **测试探针（probe binary）**，用于把 `codex-client` 的自定义 CA 逻辑放到独立进程里验证，避免并行测试中的进程级环境变量污染。

职责边界：
1. 复用库内共享实现 `build_reqwest_client_for_subprocess_tests`，不复制 CA 构建逻辑。
2. 为 `tests/ca_env.rs` 提供稳定的进程协议：成功输出 `ok` 并返回 0，失败向 stderr 输出错误并返回 1。
3. 只覆盖“客户端构建阶段”行为（环境变量选择、PEM 解析、错误提示），不覆盖真实 TLS 握手。

## 功能点目的
1. 保障自定义 CA 语义在真实 `reqwest::Client` 构建路径下可验证。
- 入口直接调用 `codex_client::build_reqwest_client_for_subprocess_tests(reqwest::Client::builder())`（`custom_ca_probe.rs:20`）。

2. 保证测试的 hermetic（结果仅受测试输入控制）。
- `tests/ca_env.rs` 在启动子进程前显式 `env_remove(CODEX_CA_CERTIFICATE)` 与 `env_remove(SSL_CERT_FILE)`，再按用例注入目标值（`codex-rs/codex-client/tests/ca_env.rs:37-43`）。

3. 复现并规避平台相关构建干扰。
- 测试专用 helper 会在构建 reqwest client 时调用 `builder.no_proxy()`，避免代理自动探测导致的非业务噪声（`codex-rs/codex-client/src/custom_ca.rs:201-213`）。

4. 验证错误提示的人机可读性。
- 失败路径要求错误信息包含 `CODEX_CA_CERTIFICATE` / `SSL_CERT_FILE` 与修复提示（`ca_env.rs:94-123`，`custom_ca.rs:63,89-99`）。

## 具体技术实现（关键流程/数据结构/协议/命令）
### 1) 探针执行流程
`main` 非常薄：
1. 调用 `build_reqwest_client_for_subprocess_tests`。
2. `Ok(_)` => stdout 打印 `ok`。
3. `Err(error)` => stderr 打印错误文本，进程 `exit(1)`。

代码：`codex-rs/codex-client/src/bin/custom_ca_probe.rs:19-28`。

### 2) 底层 CA 构建流程（探针复用）
探针调用的 helper 位于 `custom_ca.rs`：
1. 入口：`build_reqwest_client_for_subprocess_tests(builder)`。
2. 立即对 builder 调 `no_proxy()`（测试专用行为）。
3. 复用 `build_reqwest_client_with_env(&ProcessEnv, builder.no_proxy())`。
4. 环境变量选择优先级：`CODEX_CA_CERTIFICATE` > `SSL_CERT_FILE`，空字符串按未设置处理。
5. 若命中 CA 文件：读取 PEM -> 解析证书 -> 逐个 `add_root_certificate` -> 构建 reqwest client。
6. 若未命中：直接系统 roots 构建 client。

代码：
- `codex-rs/codex-client/src/custom_ca.rs:209-213`
- `codex-rs/codex-client/src/custom_ca.rs:270-334`
- `codex-rs/codex-client/src/custom_ca.rs:338-377`

### 3) PEM 兼容与证书数据处理
该路径支持的“输入协议”是 PEM bundle：
1. 支持多证书 bundle。
2. 支持 OpenSSL `TRUSTED CERTIFICATE` 标签，内部归一化为 `CERTIFICATE`。
3. 支持忽略良构 `X509 CRL` section。
4. 对 trusted cert 的 DER 会裁掉尾部 `X509_AUX`，只保留首个 DER 对象给 reqwest。

代码：
- `codex-rs/codex-client/src/custom_ca.rs:533-613`
- `codex-rs/codex-client/src/custom_ca.rs:616-680`
- `codex-rs/codex-client/src/custom_ca.rs:436-490`

### 4) 错误模型与进程协议
错误类型：`BuildCustomCaTransportError`（`custom_ca.rs:74-145`），覆盖：
1. 读文件失败（`ReadCaFile`）
2. PEM 无效（`InvalidCaFile`）
3. 证书注册失败（`RegisterCertificate` / `RegisterRustlsCertificate`）
4. client 构建失败（`BuildClientWithCustomCa` / `BuildClientWithSystemRoots`）

探针本身不做错误分支判型，只输出 `Display` 文本并返回非零。测试用例通过 `status` + `stderr.contains(...)` 判定语义（`ca_env.rs:100-123`）。

### 5) 关键命令与测试入口
1. 全 crate：`cargo test -p codex-client`
2. 定向 subprocess CA 回归：`cargo test -p codex-client --test ca_env`
3. Bazel 侧数据可见性由 `compile_data = glob(["tests/fixtures/**"])` 提供，支持 `include_str!` fixture。
- 代码：`codex-rs/codex-client/BUILD.bazel:3-7`

## 关键代码路径与文件引用
目录内与直接上下文：
1. `codex-rs/codex-client/src/bin/custom_ca_probe.rs`：探针主程序（本目录核心）。
2. `codex-rs/codex-client/src/lib.rs:11-19`：将 `build_reqwest_client_for_subprocess_tests` 以 `#[doc(hidden)]` 形式暴露给 bin 目标。
3. `codex-rs/codex-client/src/custom_ca.rs:201-213`：测试专用 reqwest 构建入口。
4. `codex-rs/codex-client/src/custom_ca.rs:264-334`：通用 reqwest client 构建主路径。
5. `codex-rs/codex-client/src/custom_ca.rs:338-377`：环境变量优先级与空值处理。
6. `codex-rs/codex-client/tests/ca_env.rs:32-145`：通过 `cargo_bin("custom_ca_probe")` 驱动进程级用例矩阵。
7. `codex-rs/codex-client/tests/fixtures/test-ca*.pem`：证书输入夹具。
8. `codex-rs/codex-client/BUILD.bazel:3-7`：为 Bazel 暴露测试证书数据。

跨 crate 传播（用于理解该探针为何重要）：
1. HTTP 客户端统一入口被 `core/login/backend-client/rmcp-client/cloud-tasks/tui` 等消费。
- 示例：`codex-rs/core/src/default_client.rs:204-216`
- 示例：`codex-rs/backend-client/src/client.rs:124`
- 示例：`codex-rs/login/src/device_code_auth.rs:160,177`
- 示例：`codex-rs/rmcp-client/src/rmcp_client.rs:136-139`
2. websocket 也走同一 custom CA 语义。
- `codex-rs/codex-api/src/endpoint/responses_websocket.rs:357-363`
- `codex-rs/codex-api/src/endpoint/realtime_websocket/methods.rs:479-483`

## 依赖与外部交互
### 代码依赖
1. 运行时依赖：`reqwest`、`rustls`、`rustls-native-certs`、`rustls-pki-types`（`codex-rs/codex-client/Cargo.toml:15-18`）。
2. 测试依赖：`codex-utils-cargo-bin`（定位 workspace binary）、`tempfile`（临时证书文件）等（`Cargo.toml:31-35`）。

### 外部交互面
1. 环境变量：`CODEX_CA_CERTIFICATE`、`SSL_CERT_FILE`（`custom_ca.rs:61-63`）。
2. 文件系统：读取 PEM 文件、测试写入临时证书。
3. 进程边界：`ca_env.rs` 使用 `std::process::Command` 启动探针进程（`ca_env.rs:33-45`）。
4. 标准输出协议：
- 成功：stdout `ok`。
- 失败：stderr 输出错误信息并 exit code 1。

### 文档与配置上下文
1. `docs/config.md` 明确了 custom CA 的用户契约：优先级、空值语义、TRUSTED CERTIFICATE/CRL 兼容与错误行为（`docs/config.md:39-59`）。
2. `codex-rs/codex-client/README.md` 说明该 crate 是通用 transport 层，不绑定具体 API 业务（`codex-rs/codex-client/README.md:1-8`）。

### 脚本上下文
未发现直接调用 `custom_ca_probe` 的仓库脚本；该二进制主要由 Rust 测试进程通过 `cargo_bin` 间接触发。研究流程层面，todo/checklist 更新由 `.ops/generate_daily_research_todo.sh` 管理。

## 风险、边界与改进建议
### 风险与边界
1. 覆盖边界仅到“client 构建成功/失败”，不覆盖真实网络握手。
- 当前测试目标是解析/注册/报错语义，不是端到端 TLS 连通性。

2. 子进程协议较简化。
- 只有 `ok` 或 stderr 文本；若未来需要细粒度断言（如错误分类），文本匹配会较脆弱。

3. 已知 CRL 边界：
- 注释已说明 malformed CRL 可能在分类前触发解析失败，即“含有效 cert + 损坏 CRL”的 bundle 仍可能失败（`custom_ca.rs:450-457`）。

4. `build_reqwest_client_for_subprocess_tests` 是 `#[doc(hidden)] pub` 导出。
- 设计上为测试服务，但依旧是可链接符号，存在被误用到生产路径的潜在风险。

### 改进建议
1. 为探针增加可选结构化输出模式（如 `--json`）并在测试中优先断言错误类别，降低纯文本耦合。
2. 增加一条回归用例：`valid cert + malformed CRL`，明确预期策略（严格失败 or 容忍忽略）。
3. 在 `build_reqwest_client_for_subprocess_tests` 文档注释中继续强化“仅测试使用”的约束，并在调用点保持最小暴露面。
4. 若后续需要验证握手级行为，可新增独立 e2e 测试目标，与当前“构建级”测试分层，而不是扩展现有 probe 责任。
