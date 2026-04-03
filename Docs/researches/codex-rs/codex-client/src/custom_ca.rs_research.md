# custom_ca.rs 深度研究文档

## 场景与职责

`custom_ca.rs` 是 Codex 客户端的自定义证书颁发机构（CA）处理模块，专门用于解决企业环境中代理或网关拦截 TLS 流量的场景。在企业网络中，HTTPS 流量经常通过代理服务器进行中间人检查，这些代理使用自签名 CA 证书重新加密流量。标准系统根证书无法验证这些重新签名的证书，导致 TLS 握手失败。

该模块的核心职责：
1. **统一信任存储策略**：为 reqwest HTTP 客户端和 rustls WebSocket 连接提供一致的 CA 证书配置
2. **环境变量驱动的 CA 配置**：支持 `CODEX_CA_CERTIFICATE`（Codex 专用）和 `SSL_CERT_FILE`（通用标准）两个环境变量
3. **PEM 格式兼容性**：处理标准证书格式和 OpenSSL 特有的 `TRUSTED CERTIFICATE` 格式
4. **用户友好的错误报告**：当 CA 配置错误时，提供清晰的错误信息和修复指导

## 功能点目的

### 1. 环境变量优先级管理
- `CODEX_CA_CERTIFICATE` 优先于 `SSL_CERT_FILE`
- 空字符串被视为未设置，避免 `VAR=""` 被错误解析为当前工作目录
- 保留环境变量来源信息用于日志和诊断

### 2. 多格式 PEM 证书支持
- **标准证书**：`BEGIN CERTIFICATE` / `END CERTIFICATE`
- **OpenSSL 信任证书**：`BEGIN TRUSTED CERTIFICATE` / `END TRUSTED CERTIFICATE`
- **CRL 忽略**：自动忽略证书吊销列表（X509 CRL）条目
- **多证书包**：支持包含多个证书的 PEM 文件

### 3. X509_AUX 元数据处理
OpenSSL 的 `TRUSTED CERTIFICATE` 格式在证书 DER 数据后附加 X509_AUX 信任元数据。模块通过 DER 长度解析提取纯证书部分，丢弃尾部元数据。

### 4. 双重传输层支持
- **HTTP 客户端**：通过 `reqwest::ClientBuilder::add_root_certificate` 添加自定义 CA
- **WebSocket TLS**：构建自定义 `rustls::ClientConfig`，合并系统根证书和自定义 CA

## 具体技术实现

### 关键数据结构

```rust
/// CA 配置错误类型
pub enum BuildCustomCaTransportError {
    ReadCaFile { source_env, path, source },      // 文件读取失败
    InvalidCaFile { source_env, path, detail },   // 证书解析失败
    RegisterCertificate { source_env, path, certificate_index, source },  // reqwest 注册失败
    RegisterRustlsCertificate { source_env, path, certificate_index, source },  // rustls 注册失败
    BuildClientWithCustomCa { source_env, path, source },  // 客户端构建失败
    BuildClientWithSystemRoots(source),  // 系统根证书模式失败
}

/// 环境变量抽象 trait（支持测试注入）
trait EnvSource {
    fn var(&self, key: &str) -> Option<String>;
    fn non_empty_path(&self, key: &str) -> Option<PathBuf>;
    fn configured_ca_bundle(&self) -> Option<ConfiguredCaBundle>;
}

/// 已配置的 CA 包信息
struct ConfiguredCaBundle {
    source_env: &'static str,  // "CODEX_CA_CERTIFICATE" 或 "SSL_CERT_FILE"
    path: PathBuf,
}

/// 标准化后的 PEM 内容
enum NormalizedPem {
    Standard(String),           // 标准格式
    TrustedCertificate(String), // OpenSSL TRUSTED CERTIFICATE 格式
}
```

### 核心流程

#### 1. HTTP 客户端构建流程 (`build_reqwest_client_with_custom_ca`)
```
1. 检查环境变量（CODEX_CA_CERTIFICATE > SSL_CERT_FILE）
2. 如未配置，使用系统根证书构建客户端
3. 如已配置：
   a. 读取 PEM 文件内容
   b. 标准化 PEM 标签（TRUSTED CERTIFICATE → CERTIFICATE）
   c. 解析所有证书段落
   d. 忽略 CRL 段落
   e. 将每个证书转换为 reqwest::Certificate
   f. 添加到 ClientBuilder
   g. 构建最终客户端
```

#### 2. rustls 配置构建流程 (`maybe_build_rustls_client_config_with_custom_ca`)
```
1. 检查环境变量
2. 如未配置，返回 Ok(None)（调用方使用默认连接器）
3. 如已配置：
   a. 初始化 rustls 加密提供者
   b. 加载系统原生根证书
   c. 解析自定义 CA 证书
   d. 添加到根证书存储
   e. 构建 ClientConfig
```

#### 3. PEM 标准化与解析 (`NormalizedPem`)
```rust
fn from_pem_data(source_env, path, pem_data) -> Self {
    if pem.contains("TRUSTED CERTIFICATE") {
        // 替换标签并标记为 TrustedCertificate 变体
        pem.replace("BEGIN TRUSTED CERTIFICATE", "BEGIN CERTIFICATE")
           .replace("END TRUSTED CERTIFICATE", "END CERTIFICATE")
    }
}

fn parse_certificates(&self) -> Result<Vec<CertificateDer>, _> {
    for section in self.sections() {
        match section.kind {
            Certificate => {
                // 对于 TrustedCertificate 变体，需要截断 X509_AUX
                let cert_der = self.certificate_der(&der)?;
                certificates.push(cert_der);
            }
            Crl => { /* 忽略 */ }
            _ => { /* 忽略其他类型 */ }
        }
    }
}
```

#### 4. DER 长度解析 (`der_item_length`)
用于从 OpenSSL TRUSTED CERTIFICATE 中提取纯证书数据：
- 支持 DER 短格式（长度直接存储在第二字节）
- 支持 DER 长格式（第二字节指示后续多少字节存储长度值）
- 拒绝不定长格式（DER 不允许）
- 边界检查防止越界

```rust
fn der_item_length(der: &[u8]) -> Option<usize> {
    let length_octet = der.get(1)?;
    if length_octet & 0x80 == 0 {
        // 短格式：长度 = 2 (tag + length) + content
        return Some(2 + usize::from(length_octet));
    }
    // 长格式处理...
}
```

### 测试策略

模块采用分层测试策略解决环境敏感性问题：

1. **单元测试**（模块内）：
   - 使用 `MapEnv` 注入模拟环境变量
   - 测试环境变量优先级逻辑
   - 不构建真实 reqwest 客户端

2. **子进程集成测试**（`tests/ca_env.rs`）：
   - 通过 `custom_ca_probe` 二进制在独立进程中测试
   - 清除继承的环境变量确保测试隔离性
   - 测试真实客户端构建、PEM 解析、错误报告

3. **测试夹具**（`tests/fixtures/`）：
   - `test-ca.pem`：标准自签名 CA 证书
   - `test-ca-trusted.pem`：OpenSSL TRUSTED CERTIFICATE 格式
   - `test-intermediate.pem`：中间证书，用于测试多证书包

## 关键代码路径与文件引用

### 本模块关键函数
| 函数 | 行号 | 用途 |
|------|------|------|
| `build_reqwest_client_with_custom_ca` | 179-183 | 主入口：构建支持自定义 CA 的 reqwest 客户端 |
| `maybe_build_rustls_client_config_with_custom_ca` | 196-199 | WebSocket 入口：构建 rustls 配置 |
| `build_reqwest_client_for_subprocess_tests` | 209-213 | 测试专用：禁用代理自动检测 |
| `EnvSource::configured_ca_bundle` | 364-377 | 环境变量优先级决策 |
| `ConfiguredCaBundle::parse_certificates` | 442-489 | PEM 解析核心逻辑 |
| `NormalizedPem::from_pem_data` | 570-585 | OpenSSL 格式标准化 |
| `der_item_length` | 656-680 | DER 长度解析 |

### 相关文件
| 文件 | 关系 |
|------|------|
| `src/bin/custom_ca_probe.rs` | 子进程测试辅助二进制 |
| `tests/ca_env.rs` | 集成测试 |
| `tests/fixtures/*.pem` | 测试证书夹具 |
| `../core/src/default_client.rs` | 调用方：构建默认 HTTP 客户端 |
| `../codex-api/src/provider.rs` | 调用方：API 提供者配置 |

## 依赖与外部交互

### 外部 crate 依赖
| Crate | 用途 |
|-------|------|
| `reqwest` | HTTP 客户端构建和证书注册 |
| `rustls` | TLS 配置和根证书存储 |
| `rustls-native-certs` | 加载系统原生根证书 |
| `rustls-pki-types` | PEM 解析和证书类型 |
| `codex-utils-rustls-provider` | 确保 rustls 加密提供者初始化 |
| `tracing` | 结构化日志记录 |
| `thiserror` | 错误类型定义 |

### 环境变量交互
| 变量 | 来源 | 用途 |
|------|------|------|
| `CODEX_CA_CERTIFICATE` | 用户/管理员 | Codex 专用 CA 包路径 |
| `SSL_CERT_FILE` | 用户/系统 | 通用 SSL CA 包路径（后备） |

### 与系统证书存储的交互
- 使用 `rustls_native_certs::load_native_certs()` 加载系统根证书
- 在 macOS 上可能遇到 `system-configuration` 代理探测 panic（通过 `no_proxy()` 在测试中规避）

## 风险、边界与改进建议

### 已知风险

1. **macOS Seatbelt 兼容性问题**
   - 现象：`reqwest::Client::builder().build()` 在 seatbelt 沙箱中可能 panic
   - 原因：`system-configuration` 库探测平台代理设置时失败
   - 缓解：测试使用 `build_reqwest_client_for_subprocess_tests` 禁用代理检测

2. **CRL 解析限制**
   - 现象：包含格式错误 CRL 的证书包会加载失败
   - 原因：`rustls-pki-types` 在分类前解析 CRL 失败
   - 当前行为：整体加载失败而非忽略单个错误 CRL

3. **环境变量继承污染**
   - 现象：子进程测试可能受父进程环境变量影响
   - 缓解：测试显式清除 `CODEX_CA_CERTIFICATE` 和 `SSL_CERT_FILE`

### 边界条件

| 场景 | 行为 |
|------|------|
| 空 PEM 文件 | 返回 `InvalidCaFile` 错误，提示 "no certificates found" |
| 仅包含 CRL 的 PEM | 同上（无证书段落） |
| 空环境变量值 | 视为未设置，使用系统根证书 |
| 不存在的文件路径 | 返回 `ReadCaFile` 错误，保留原始 IO 错误类型 |
| 无效 DER 数据 | 返回 `InvalidCaFile` 错误，包含详细解析失败信息 |
| 混合标准/信任证书 | 全部标准化后处理，X509_AUX 仅对信任证书截断 |

### 改进建议

1. **缓存机制**
   - 当前：每次构建客户端都重新读取和解析 CA 文件
   - 建议：添加 CA 证书缓存，避免重复文件 IO 和解析
   - 注意：需考虑文件修改检测或提供缓存刷新 API

2. **热重载支持**
   - 当前：CA 配置在进程启动时确定
   - 建议：支持配置文件变更通知和动态重载

3. **更灵活的 CRL 处理**
   - 当前：格式错误的 CRL 导致整体失败
   - 建议：记录警告但继续加载有效证书

4. **证书过期检查**
   - 当前：不验证证书有效期
   - 建议：在加载时检查并警告即将过期或已过期的 CA 证书

5. **Windows 证书存储集成**
   - 当前：仅支持 PEM 文件路径
   - 建议：支持 Windows 证书存储（CERT_SYSTEM_STORE_LOCAL_MACHINE）

6. **指标和可观测性**
   - 当前：仅有基本日志
   - 建议：添加 CA 加载成功/失败指标，证书数量统计

### 安全考虑

1. **文件权限检查**
   - 建议：验证 CA 文件权限，警告世界可写的证书文件

2. **证书固定（Pinning）**
   - 建议：支持公钥固定，防止恶意 CA 被添加到自定义包

3. **审计日志**
   - 建议：记录 CA 证书指纹（SHA-256）用于安全审计
