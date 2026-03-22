# test-ca.pem 研究文档

## 场景与职责

`test-ca.pem` 是 Codex 客户端测试套件中的核心测试证书文件，用于验证自定义 CA（Certificate Authority）证书加载功能的正确性。它是整个自定义 CA 测试体系的基础测试夹具（test fixture），专门用于测试单证书加载场景。

该文件位于 `codex-rs/codex-client/tests/fixtures/` 目录下，是 `codex-client` crate 的集成测试基础设施的重要组成部分。

## 功能点目的

### 1. 核心测试目标
- **单证书加载验证**：测试从 PEM 文件加载单个自签名 CA 证书的基本功能
- **PEM 解析验证**：确保证书解析器能够正确处理标准 PEM 格式的证书
- **根证书注册验证**：验证解析后的证书能够成功注册到 reqwest 客户端的根证书存储中

### 2. 测试覆盖场景
该证书被用于以下测试场景（定义在 `tests/ca_env.rs` 中）：
- `uses_codex_ca_cert_env`：验证 `CODEX_CA_CERTIFICATE` 环境变量指定的证书加载
- `falls_back_to_ssl_cert_file`：验证 `SSL_CERT_FILE` 环境变量的回退机制
- `prefers_codex_ca_cert_over_ssl_cert_file`：验证环境变量优先级
- `handles_multi_certificate_bundle`：与 `test-intermediate.pem` 组合测试多证书包
- `accepts_bundle_with_crl`：与 CRL 内容组合测试混合包处理

### 3. 证书特性
- **类型**：自签名 CA 证书（self-signed CA）
- **格式**：标准 PEM 格式（`-----BEGIN CERTIFICATE-----`）
- **用途**：仅用于测试，不用于实际 TLS 握手验证
- **有效期**：2025-12-11 至 2035-12-09（10 年有效期）
- **主题**：CN=test-ca

## 具体技术实现

### 1. 证书结构分析

```
证书版本：X.509 v3
签名算法：RSA-SHA256 (sha256WithRSAEncryption)
主题（Subject）：CN=test-ca
颁发者（Issuer）：CN=test-ca（自签名）
有效期：
  - 生效：2025-12-11 23:12:51 UTC
  - 过期：2035-12-09 23:12:51 UTC
公钥算法：RSA (2048-bit)
```

### 2. 测试代码中的使用方式

```rust
// tests/ca_env.rs
const TEST_CERT_1: &str = include_str!("fixtures/test-ca.pem");

#[test]
fn uses_codex_ca_cert_env() {
    let temp_dir = TempDir::new().expect("tempdir");
    let cert_path = write_cert_file(&temp_dir, "ca.pem", TEST_CERT_1);
    let output = run_probe(&[(CODEX_CA_CERT_ENV, cert_path.as_path())]);
    assert!(output.status.success());
}
```

### 3. 证书加载流程

```
test-ca.pem
    ↓
include_str! 编译时嵌入
    ↓
TEST_CERT_1 常量
    ↓
write_cert_file 写入临时文件
    ↓
run_probe 启动 custom_ca_probe 子进程
    ↓
build_reqwest_client_for_subprocess_tests
    ↓
build_reqwest_client_with_env
    ↓
ConfiguredCaBundle::load_certificates
    ↓
NormalizedPem::from_pem_data (标准 PEM，无需规范化)
    ↓
PemSection::pem_slice_iter 解析
    ↓
reqwest::Certificate::from_der 注册
    ↓
reqwest::ClientBuilder::add_root_certificate
    ↓
reqwest::ClientBuilder::build
```

### 4. 关键数据结构

```rust
// 证书加载结果类型
pub enum BuildCustomCaTransportError {
    ReadCaFile { source_env, path, source },
    InvalidCaFile { source_env, path, detail },
    RegisterCertificate { source_env, path, certificate_index, source },
    BuildClientWithCustomCa { source_env, path, source },
    BuildClientWithSystemRoots(source),
    RegisterRustlsCertificate { source_env, path, certificate_index, source },
}

// 环境变量优先级
const CODEX_CA_CERT_ENV: &str = "CODEX_CA_CERTIFICATE";
const SSL_CERT_FILE_ENV: &str = "SSL_CERT_FILE";
// 优先级：CODEX_CA_CERTIFICATE > SSL_CERT_FILE
```

## 关键代码路径与文件引用

### 1. 证书文件本身
- **路径**：`codex-rs/codex-client/tests/fixtures/test-ca.pem`
- **大小**：1273 bytes
- **格式**：X.509 PEM

### 2. 测试代码
- **集成测试**：`codex-rs/codex-client/tests/ca_env.rs`
  - 第 20 行：`const TEST_CERT_1: &str = include_str!("fixtures/test-ca.pem");`
  - 第 697 行（单元测试）：`const TEST_CERT: &str = include_str!("../tests/fixtures/test-ca.pem");`

### 3. 被测代码
- **核心模块**：`codex-rs/codex-client/src/custom_ca.rs`
  - `build_reqwest_client_with_custom_ca()` - 公开 API
  - `build_reqwest_client_for_subprocess_tests()` - 测试专用 API
  - `ConfiguredCaBundle::load_certificates()` - 证书加载逻辑
  - `NormalizedPem::from_pem_data()` - PEM 规范化

### 4. 辅助二进制文件
- **路径**：`codex-rs/codex-client/src/bin/custom_ca_probe.rs`
- **用途**：子进程探针，用于隔离环境变量测试

### 5. 模块导出
- **路径**：`codex-rs/codex-client/src/lib.rs`
  - 第 11-17 行：导出 `build_reqwest_client_for_subprocess_tests`
  - 第 18 行：导出 `build_reqwest_client_with_custom_ca`

## 依赖与外部交互

### 1. 内部依赖
| 依赖项 | 用途 |
|--------|------|
| `codex_utils_cargo_bin::cargo_bin` | 定位 custom_ca_probe 二进制文件 |
| `tempfile::TempDir` | 创建临时目录存放测试证书 |
| `std::fs::write` | 写入临时证书文件 |
| `std::process::Command` | 启动子进程进行隔离测试 |

### 2. 外部 crate 依赖
| Crate | 用途 |
|-------|------|
| `reqwest` | HTTP 客户端构建和证书注册 |
| `rustls` | TLS 配置和根证书存储 |
| `rustls-pki-types` | PEM 解析和证书类型 |
| `rustls-native-certs` | 加载系统原生根证书 |

### 3. 环境变量交互
| 环境变量 | 作用 |
|----------|------|
| `CODEX_CA_CERTIFICATE` | 首选的自定义 CA 证书路径 |
| `SSL_CERT_FILE` | 回退的 SSL 证书文件路径 |

### 4. 与其他测试证书的关系
```
test-ca.pem (本文件)
    ├── 与 test-intermediate.pem 组合 → 多证书包测试
    ├── 与 CRL 内容组合 → 混合包测试
    └── 与 test-ca-trusted.pem 对比 → OpenSSL TRUSTED CERTIFICATE 格式测试
```

## 风险、边界与改进建议

### 1. 已知风险

#### 风险 1：证书过期
- **问题**：证书有效期至 2035-12-09，届时测试将失败
- **缓解**：测试仅验证证书加载和解析，不验证 TLS 握手，过期证书仍可加载
- **建议**：在证书过期前（2035 年）重新生成测试证书

#### 风险 2：测试环境污染
- **问题**：子进程继承父进程环境变量可能导致测试结果不稳定
- **缓解**：`ca_env.rs` 中的 `run_probe()` 函数会显式清除 `CODEX_CA_CERTIFICATE` 和 `SSL_CERT_FILE`
- **代码**：
  ```rust
  cmd.env_remove(CODEX_CA_CERT_ENV);
  cmd.env_remove(SSL_CERT_FILE_ENV);
  ```

#### 风险 3：并发测试冲突
- **问题**：环境变量是进程全局的，并行测试可能互相干扰
- **缓解**：使用子进程隔离，每个测试在独立进程中执行

### 2. 边界情况

| 边界情况 | 处理方式 |
|----------|----------|
| 空证书文件 | `rejects_empty_pem_file_with_hint` 测试验证 |
| 畸形 PEM | `rejects_malformed_pem_with_hint` 测试验证 |
| 多证书包 | `handles_multi_certificate_bundle` 测试验证 |
| 包含 CRL | `accepts_bundle_with_crl` 测试验证 |

### 3. 改进建议

#### 建议 1：动态证书生成
- **现状**：使用静态 PEM 文件
- **建议**：考虑使用 `rcgen` crate 在测试时动态生成证书，避免过期问题
- **参考**：`network-proxy/src/certs.rs` 已实现类似功能

#### 建议 2：扩展测试覆盖
- **建议**：增加对以下场景的测试：
  - 证书链验证（目前明确不测试）
  - 不同密钥算法（ECDSA、Ed25519）
  - 大证书包（100+ 证书）

#### 建议 3：文档完善
- **建议**：在证书文件中添加生成命令记录，便于后续重新生成：
  ```bash
  # 生成命令示例：
  openssl req -x509 -newkey rsa:2048 -keyout test-ca.key -out test-ca.pem \
    -days 3650 -nodes -subj "/CN=test-ca"
  ```

### 4. 相关文档
- **模块文档**：`codex-rs/codex-client/src/custom_ca.rs` 第 1-41 行的详细注释
- **README**：`codex-rs/codex-client/README.md`
- **AGENTS.md**：项目根目录下的 Rust 开发规范
