# codex-rs/codex-client/tests/fixtures 研究

## 场景与职责

目标目录 `codex-rs/codex-client/tests/fixtures` 只包含 3 个 PEM 夹具文件，用于驱动 `codex-client` 的 custom CA 解析与容错测试，职责是提供**稳定、可重复、无网络依赖**的证书输入样本，而不是做真实 TLS 握手验证。

目录内文件：

1. `test-ca.pem`：单证书正例，验证“能解析并注册根证书”。
2. `test-intermediate.pem`：第二张不同证书，验证多证书 bundle 场景。
3. `test-ca-trusted.pem`：OpenSSL `TRUSTED CERTIFICATE` 产物，携带 `X509_AUX` 尾部，验证兼容/裁剪路径。

直接证据：

- `codex-rs/codex-client/tests/fixtures/test-ca.pem:1-3`
- `codex-rs/codex-client/tests/fixtures/test-intermediate.pem:1-2`
- `codex-rs/codex-client/tests/fixtures/test-ca-trusted.pem:1-7`

## 功能点目的

该目录服务于 `codex-client` 的 CA 处理契约，覆盖以下目的：

1. **环境变量驱动的 CA 选择行为可回归**：
   `CODEX_CA_CERTIFICATE` 优先于 `SSL_CERT_FILE`，空字符串视为未设置。
2. **PEM 输入形态兼容性**：
   支持标准 `CERTIFICATE`、OpenSSL `TRUSTED CERTIFICATE`，并容忍 bundle 中的 `X509 CRL`（良构时忽略）。
3. **错误提示质量**：
   空 PEM / malformed PEM 时，错误文案需包含修复提示与环境变量名。
4. **Bazel/Cargo 双运行链路稳定**：
   fixture 必须作为编译/运行数据可见（`compile_data` + `cargo_bin` 解析）。

这些目标与 `docs/config.md` 对外文档保持一致（`docs/config.md:39-59`）。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 关键流程

`fixtures/*` -> `tests/ca_env.rs` -> `custom_ca_probe` 子进程 -> `codex_client::build_reqwest_client_for_subprocess_tests` -> `custom_ca` 解析/注册流程。

详细链路：

1. `tests/ca_env.rs` 用 `include_str!` 读入 3 个 fixture（`codex-rs/codex-client/tests/ca_env.rs:20-22`）。
2. 用例将 PEM 写入 `TempDir` 临时文件，再通过 `run_probe` 启动子进程（`ca_env.rs:24-46`）。
3. 子进程入口 `custom_ca_probe` 调用共享构建函数（`codex-rs/codex-client/src/bin/custom_ca_probe.rs:19-27`）。
4. 构建函数内部读取 env、加载 PEM、解析 section、注册 reqwest root CA（`codex-rs/codex-client/src/custom_ca.rs:270-334,442-490`）。
5. 成功返回 0；失败 stderr 输出用户可读错误并返回 1（`custom_ca_probe.rs:20-27`）。

### 2) 关键数据结构

1. `BuildCustomCaTransportError`：统一描述读取、解析、注册、构建阶段错误（`custom_ca.rs:74-145`）。
2. `ConfiguredCaBundle { source_env, path }`：保存“哪个环境变量选中了哪个路径”（`custom_ca.rs:397-402`）。
3. `NormalizedPem`：
   - `Standard(String)`：标准标签；
   - `TrustedCertificate(String)`：将 OpenSSL 标签归一化后继续解析（`custom_ca.rs:538-543`）。
4. `PemSection = (SectionKind, Vec<u8>)`：通过 `rustls_pki_types::pem` 迭代 mixed sections（`custom_ca.rs:64,599-601`）。

### 3) 协议与规则

1. 环境变量协议：
   - `CODEX_CA_CERTIFICATE`（优先）
   - `SSL_CERT_FILE`（回退）
   - 空值按 unset 处理（`custom_ca.rs:353-377`）。
2. PEM 语义协议：
   - `SectionKind::Certificate` -> 纳入 root store；
   - `SectionKind::Crl` -> 记录日志后忽略；
   - 其他 section 忽略（`custom_ca.rs:459-482`）。
3. `TRUSTED CERTIFICATE` 特殊处理：
   - 文本标签替换为 `CERTIFICATE`；
   - DER 仅截取首个 ASN.1 对象，去掉尾部 `X509_AUX`（`custom_ca.rs:570-612,628-680`）。

### 4) 相关命令与运行方式

1. OpenSSL 生成 trusted fixture（文件注释给出的来源命令）：
   - `openssl x509 -addtrust serverAuth -trustout`
2. 定向测试：
   - `cargo test -p codex-client --test ca_env`
3. 子进程二进制定位：
   - `codex_utils_cargo_bin::cargo_bin("custom_ca_probe")`（`codex-rs/utils/cargo-bin/src/lib.rs:33-69`）。

## 关键代码路径与文件引用

### 目录内文件（被研究对象）

1. `codex-rs/codex-client/tests/fixtures/test-ca.pem`
2. `codex-rs/codex-client/tests/fixtures/test-intermediate.pem`
3. `codex-rs/codex-client/tests/fixtures/test-ca-trusted.pem`

### 直接调用方 / 使用方

1. `codex-rs/codex-client/tests/ca_env.rs:20-22`
   - 以 `include_str!` 直接引用 3 个 fixture，构造用例输入。
2. `codex-rs/codex-client/src/custom_ca.rs:697`
   - 单元测试内直接 `include_str!("../tests/fixtures/test-ca.pem")`。
3. `codex-rs/codex-client/BUILD.bazel:6`
   - `compile_data = glob(["tests/fixtures/**"])`，确保 Bazel 下编译期/运行期可访问 fixture。

### 关键中间执行路径

1. `codex-rs/codex-client/src/bin/custom_ca_probe.rs:19-27`
2. `codex-rs/codex-client/src/custom_ca.rs:209-213`（subprocess test 专用入口）
3. `codex-rs/codex-client/src/custom_ca.rs:270-334`（reqwest client 构建主路径）
4. `codex-rs/codex-client/src/custom_ca.rs:442-490`（证书解析主路径）
5. `codex-rs/codex-client/src/custom_ca.rs:570-612,628-680`（trusted cert + DER 裁剪）

### 上下文依赖（上游调用）

1. HTTP 调用方示例：
   - `codex-rs/core/src/default_client.rs:190-216`
   - `codex-rs/backend-client/src/client.rs:124`
   - `codex-rs/cloud-tasks/src/env_detect.rs:77,151`
   - `codex-rs/login/src/device_code_auth.rs:160,177`
   - `codex-rs/login/src/server.rs:695,1064`
   - `codex-rs/rmcp-client/src/rmcp_client.rs:138`
   - `codex-rs/tui/src/voice.rs:955`
   - `codex-rs/tui_app_server/src/voice.rs:793`
2. Websocket TLS 调用方示例：
   - `codex-rs/codex-api/src/endpoint/realtime_websocket/methods.rs:479-483`
   - `codex-rs/codex-api/src/endpoint/responses_websocket.rs:357-363`

## 依赖与外部交互

### 代码依赖

`codex-client` 与该目录相关的关键依赖：

1. `reqwest`：注册 `add_root_certificate` 与构建 client（`custom_ca.rs:278-299`）。
2. `rustls` + `rustls-native-certs`：websocket TLS root store 组装（`custom_ca.rs:227-260`）。
3. `rustls-pki-types`：PEM section 解析（`custom_ca.rs:53-56,599-601`）。
4. `codex-utils-rustls-provider`：确保 rustls crypto provider 初始化（`custom_ca.rs:50,222`）。
5. `tempfile` + `std::process::Command`：测试落盘与子进程执行（`ca_env.rs:14-15,24-46`）。
6. `codex_utils_cargo_bin`：跨 Cargo/Bazel 定位测试二进制（`ca_env.rs:11,34-35`；`utils/cargo-bin/src/lib.rs:33-69`）。

### 外部交互面

1. 文件系统：读取 PEM、写临时证书文件。
2. 进程环境：读取/清理 `CODEX_CA_CERTIFICATE`、`SSL_CERT_FILE`。
3. 子进程模型：`custom_ca_probe` 作为测试进程协议载体。
4. 文档契约：`docs/config.md` 对外声明 custom CA 行为（`docs/config.md:39-59`）。
5. OpenSSL 生态兼容：兼容 trusted cert 与 `X509_AUX` 现实格式。

注意：该目录对应测试默认不做真实外网 TLS 握手，重点是“配置与解析路径”的可重复性。

## 风险、边界与改进建议

### 风险与边界

1. **覆盖边界**：当前 fixture 驱动的测试主要断言“能否构建 client + 错误文案”，不验证真实握手成功（`ca_env.rs:7-9`）。
2. **CRL 边界**：实现注释明确存在限制，若 bundle 含 malformed CRL，可能在分类前即失败（`custom_ca.rs:451-454`）。
3. **样本多样性不足**：`TRUSTED CERTIFICATE` 仅 1 份样本，尚未覆盖多 trusted blocks、混合注释/空行/异常拼接等复杂输入。
4. **证书演进风险**：fixture 是静态文本，缺少统一再生成脚本与指纹校验，长期维护易出现“来源不明”问题。

### 改进建议

1. 为 `tests/fixtures` 增加 `README` 或生成脚本，记录证书生成参数、有效期、指纹与再生方式。
2. 增加 fixture 组合：
   - 多个 `TRUSTED CERTIFICATE` block；
   - cert + 多 CRL + 注释噪声；
   - 明确覆盖 malformed CRL 与预期行为。
3. 在 `codex-api` 侧补 1 条最小 websocket 集成验证，确认 custom CA 与 HTTP 路径长期一致。
4. 若未来需要更强保障，可新增“本地自签 TLS 服务 + custom CA 握手成功”端到端用例（与当前无网络要求不冲突，可在本地回环完成）。
