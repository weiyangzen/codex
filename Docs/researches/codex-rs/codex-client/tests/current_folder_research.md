# DIR `codex-rs/codex-client/tests` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/codex-client/tests`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 关联 crate：`codex-client`

## 场景与职责

`codex-rs/codex-client/tests` 的职责是做“进程级（subprocess）”CA 行为回归测试，验证 `codex-client` 的自定义 CA 逻辑在真实 `reqwest::Client` 构建路径上可用，并且不受父进程环境变量污染。

该目录不是通用单元测试集合，而是专门补齐 `src/custom_ca.rs` 中“hermetic 测试”契约的第二层：
- 单元层：`custom_ca.rs` 内部测试覆盖 env 优先级与部分解析逻辑。
- 进程层：`tests/ca_env.rs` 通过独立二进制 `custom_ca_probe` 验证真实客户端构建与错误文案。

关键依据：
- `codex-rs/codex-client/tests/ca_env.rs:1-9,32-46`
- `codex-rs/codex-client/src/bin/custom_ca_probe.rs:1-29`
- `codex-rs/codex-client/src/custom_ca.rs:22-41,201-213`

## 功能点目的

本目录当前只有 `ca_env.rs`，覆盖 8 个核心场景：

1. `uses_codex_ca_cert_env`：验证 `CODEX_CA_CERTIFICATE` 生效（`ca_env.rs:48-56`）。
2. `falls_back_to_ssl_cert_file`：验证 `SSL_CERT_FILE` 作为回退（`ca_env.rs:58-66`）。
3. `prefers_codex_ca_cert_over_ssl_cert_file`：验证优先级 `CODEX_CA_CERTIFICATE > SSL_CERT_FILE`（`ca_env.rs:68-80`）。
4. `handles_multi_certificate_bundle`：验证 PEM 多证书 bundle 可加载（`ca_env.rs:82-91`）。
5. `rejects_empty_pem_file_with_hint`：验证空 PEM 报错，并给出环境变量修复提示（`ca_env.rs:93-105`）。
6. `rejects_malformed_pem_with_hint`：验证 malformed PEM 报错与提示（`ca_env.rs:107-123`）。
7. `accepts_openssl_trusted_certificate`：验证 OpenSSL `TRUSTED CERTIFICATE` 兼容（`ca_env.rs:125-133`）。
8. `accepts_bundle_with_crl`：验证证书+CRL bundle 不会误失败（`ca_env.rs:135-145`）。

测试夹具职责：
- `fixtures/test-ca.pem`：单证书正例。
- `fixtures/test-intermediate.pem`：第二张合法证书，覆盖 bundle。
- `fixtures/test-ca-trusted.pem`：OpenSSL `-trustout` 产物，覆盖 X509_AUX 裁剪路径。

关键依据：
- `codex-rs/codex-client/tests/fixtures/test-ca.pem:1-3`
- `codex-rs/codex-client/tests/fixtures/test-intermediate.pem:1-2`
- `codex-rs/codex-client/tests/fixtures/test-ca-trusted.pem:1-7`

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 关键流程

1. 用例通过 `include_str!` 载入 fixture PEM 文本（`ca_env.rs:20-22`）。
2. 每个测试写入临时目录文件（`write_cert_file`，`ca_env.rs:24-30`）。
3. `run_probe` 启动 `custom_ca_probe` 子进程前，先 `env_remove` 清理继承变量，再按用例注入目标 env（`ca_env.rs:32-43`）。
4. `custom_ca_probe` 仅调用 `codex_client::build_reqwest_client_for_subprocess_tests(reqwest::Client::builder())`：
   - 成功输出 `ok`；
   - 失败将结构化错误打印到 stderr 并 `exit(1)`（`custom_ca_probe.rs:19-27`）。
5. 被测实现在 `build_reqwest_client_for_subprocess_tests` 中对 builder 增加 `no_proxy()`，避免测试环境代理探测导致的非目标失败（`custom_ca.rs:209-213`）。
6. CA 选择和解析链路：
   - env 选择：`CODEX_CA_CERTIFICATE` 优先，其次 `SSL_CERT_FILE`，空字符串视为 unset（`custom_ca.rs:353-377`）；
   - PEM 解析：读取文件、按 section 迭代，`Certificate` 入库，`Crl` 忽略（`custom_ca.rs:442-490`）；
   - OpenSSL `TRUSTED CERTIFICATE`：标签归一化 + 首个 DER item 裁剪（`custom_ca.rs:570-612,628-680`）。

### 2) 关键数据结构

- 测试输入模型：`run_probe(envs: &[(&str, &Path)])`，使用“环境变量键 + 路径”的简单 tuple 数组表达场景（`ca_env.rs:32`）。
- 错误模型：`BuildCustomCaTransportError`，将读文件、PEM 解析、证书注册、client build 失败区分为不同 variant（`custom_ca.rs:73-145`）。
- PEM 归一化模型：`NormalizedPem::{Standard, TrustedCertificate}`，负责兼容非标准标签（`custom_ca.rs:538-543`）。

### 3) 协议与约定

- 环境变量协议：`CODEX_CA_CERTIFICATE`、`SSL_CERT_FILE`；优先级与空值语义在实现与文档一致（`custom_ca.rs:61-63,361-377`；`docs/config.md:47-53`）。
- 子进程协议：退出码 `0` 表示 CA 配置可构建 client；非零表示 stderr 中携带用户可读修复提示（`custom_ca_probe.rs:20-27`；`ca_env.rs:100-104,118-122`）。
- Bazel/Cargo 运行协议：`cargo_bin("custom_ca_probe")` 自动兼容 `CARGO_BIN_EXE_*` 与 Bazel runfiles（`utils/cargo-bin/src/lib.rs:33-69,88-107`）。

### 4) 常用命令

- 运行该目录集成测试：`cargo test -p codex-client --test ca_env`
- 运行 crate 全部测试（含 `custom_ca.rs` 内单测与集成测试）：`cargo test -p codex-client`

## 关键代码路径与文件引用

### 目录内核心文件

1. `codex-rs/codex-client/tests/ca_env.rs:1-145`
- 主体集成测试文件；定义场景矩阵、子进程隔离、错误断言。

2. `codex-rs/codex-client/tests/fixtures/test-ca.pem:1-24`
- 单证书 fixture。

3. `codex-rs/codex-client/tests/fixtures/test-intermediate.pem:1-24`
- bundle 第二证书 fixture。

4. `codex-rs/codex-client/tests/fixtures/test-ca-trusted.pem:1-30`
- OpenSSL trusted-certificate fixture。

### 直接被调用方

5. `codex-rs/codex-client/src/bin/custom_ca_probe.rs:19-27`
- 集成测试实际执行入口。

6. `codex-rs/codex-client/src/custom_ca.rs:201-213,264-334,336-377,442-490,570-680`
- 被测逻辑主干（test-only builder、env 选择、PEM 解析、trusted cert 兼容）。

7. `codex-rs/codex-client/src/lib.rs:10-19`
- 导出 `build_reqwest_client_for_subprocess_tests`（`#[doc(hidden)]`，仅测试二进制复用）。

### 配置、构建与文档

8. `codex-rs/codex-client/BUILD.bazel:3-7`
- `compile_data = glob(["tests/fixtures/**"])`，保证 Bazel 下 fixture 可读。

9. `codex-rs/codex-client/Cargo.toml:31-36`
- `dev-dependencies` 声明 `codex-utils-cargo-bin`、`tempfile` 等测试依赖。

10. `docs/config.md:39-59`
- 对外文档声明 CA 环境变量语义，和测试断言目标一致。

### 代表性调用方（上下文依赖）

11. HTTP 客户端调用方：
- `codex-rs/backend-client/src/client.rs:7,111-125`
- `codex-rs/login/src/device_code_auth.rs:159-178`
- `codex-rs/login/src/server.rs:695-703`
- `codex-rs/cloud-tasks/src/env_detect.rs:147-153`
- `codex-rs/rmcp-client/src/rmcp_client.rs:136-139`
- `codex-rs/tui/src/voice.rs:955-957`

12. WebSocket TLS 调用方：
- `codex-rs/codex-api/src/endpoint/realtime_websocket/methods.rs:479-484`
- `codex-rs/codex-api/src/endpoint/responses_websocket.rs:357-363`

## 依赖与外部交互

1. 进程与环境
- `std::process::Command` 启动子进程；通过 `env_remove` 去除父进程污染（`ca_env.rs:37-43`）。

2. 文件系统
- 测试在 `TempDir` 下动态落盘证书文件并读取（`ca_env.rs:24-30`；`custom_ca.rs:497-503`）。

3. 运行时解析库
- `rustls-pki-types` 的 PEM section 迭代器用于解析 mixed PEM（`custom_ca.rs:54-56,599-600`）。
- `reqwest::Certificate::from_der` 用于根证书注册（`custom_ca.rs:277-297`）。

4. Cargo/Bazel 互操作
- `codex_utils_cargo_bin::cargo_bin` 负责测试二进制定位（`ca_env.rs:11,34-35`；`utils/cargo-bin/src/lib.rs:33-69`）。

5. 网络边界
- 本目录测试仅断言“client 构建成功/失败”与错误文本，不发起 TLS 握手、不访问外网（`ca_env.rs:7-9`）。

## 风险、边界与改进建议

1. 覆盖边界：未做握手级验证
- 当前只验证证书加载和 client 构建，不验证证书链在真实 TLS 会话中的信任结果。
- 建议：新增本地 TLS 测试服务器（自签链）做端到端握手测试。

2. 已知解析边界：Malformed CRL 可能导致整体失败
- `custom_ca.rs` 注释说明：当 CRL section 本身 malformed 时，可能在分类前就被解析错误中断（`custom_ca.rs:451-454`）。
- 建议：新增显式回归测试，固定该行为（允许失败并校验错误文案），避免未来误变更。

3. 错误断言粒度偏粗
- 目前对失败场景主要断言 `stderr.contains(...)`，未约束完整错误结构。
- 建议：增加关键前缀或 variant 级断言（例如约束 `InvalidCaFile` 路径上下文），降低误报。

4. 场景仍缺少 I/O 类异常
- 目前未覆盖“文件不存在 / 权限不足 / 目录路径”等 `ReadCaFile` 分支。
- 建议：补充不可读路径与不存在路径测试，确保用户提示可诊断。

5. 调用面扩散风险
- 该目录测试主要覆盖 `reqwest` 分支，WebSocket rustls 分支依赖其他 crate 测试兜底。
- 建议：在 `codex-api` websocket 测试中增加一条 `maybe_build_rustls_client_config_with_custom_ca` 的集成覆盖，保持 HTTP/WS 策略一致性。
