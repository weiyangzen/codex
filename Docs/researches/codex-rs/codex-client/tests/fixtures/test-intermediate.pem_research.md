# test-intermediate.pem 研究文档

## 场景与职责

`test-intermediate.pem` 是 Codex 客户端测试套件中的第二个测试证书文件，专门用于验证**多证书包（multi-certificate bundle）**的处理能力。它与 `test-ca.pem` 配合使用，测试系统能否正确解析和加载包含多个证书的 PEM 文件。

该文件的设计意图是作为一个与 `test-ca.pem` 不同的独立证书，用于模拟真实场景中多个 CA 证书被打包在同一个 PEM 文件中的情况（常见于企业环境的证书链配置）。

## 功能点目的

### 1. 核心测试目标
- **多证书包加载验证**：测试系统能否正确处理包含多个证书的 PEM 文件
- **证书区分验证**：确保证书解析器能够区分不同的证书条目
- **证书计数验证**：验证所有证书都被正确加载到根证书存储中

### 2. 测试覆盖场景
该证书被用于以下测试场景（定义在 `tests/ca_env.rs` 中）：
- `handles_multi_certificate_bundle`：核心测试，将 `test-ca.pem` 和 `test-intermediate.pem` 合并为一个包进行测试

```rust
#[test]
fn handles_multi_certificate_bundle() {
    let temp_dir = TempDir::new().expect("tempdir");
    let bundle = format!("{TEST_CERT_1}\n{TEST_CERT_2}");  // 合并两个证书
    let cert_path = write_cert_file(&temp_dir, "bundle.pem", &bundle);
    let output = run_probe(&[(CODEX_CA_CERT_ENV, cert_path.as_path())]);
    assert!(output.status.success());
}
```

### 3. 证书特性
- **类型**：中间 CA 证书（intermediate CA）
- **格式**：标准 PEM 格式（`-----BEGIN CERTIFICATE-----`）
- **用途**：仅用于测试，不用于实际 TLS 握手验证
- **有效期**：2025-11-19 至 2026-11-19（1 年有效期，与 test-ca.pem 不同）
- **主题**：CN=test-intermediate
- **关键区别**：与 `test-ca.pem` 使用不同的密钥对和主题名

## 具体技术实现

### 1. 证书结构分析

```
证书版本：X.509 v3
签名算法：RSA-SHA256 (sha256WithRSAEncryption)
主题（Subject）：CN=test-intermediate
颁发者（Issuer）：CN=test-intermediate（自签名）
有效期：
  - 生效：2025-11-19 15:50:23 UTC
  - 过期：2026-11-19 15:50:23 UTC
公钥算法：RSA
```

### 2. 与 test-ca.pem 的对比

| 属性 | test-ca.pem | test-intermediate.pem |
|------|-------------|----------------------|
| 主题名 | CN=test-ca | CN=test-intermediate |
| 有效期开始 | 2025-12-11 | 2025-11-19 |
| 有效期结束 | 2035-12-09 | 2026-11-19 |
| 证书类型 | 根 CA | 中间 CA |
| 序列号 | 不同 | 不同 |
| 公钥 | 不同密钥对 | 不同密钥对 |

### 3. 多证书包处理流程

```
test-ca.pem + test-intermediate.pem
    ↓
format!("{TEST_CERT_1}\n{TEST_CERT_2}")  // 字符串拼接
    ↓
write_cert_file 写入临时文件 bundle.pem
    ↓
run_probe 启动子进程
    ↓
build_reqwest_client_for_subprocess_tests
    ↓
ConfiguredCaBundle::load_certificates
    ↓
NormalizedPem::from_pem_data
    ↓
PemSection::pem_slice_iter  // 迭代解析多个证书段
    ↓
遍历每个 SectionKind::Certificate
    ↓
reqwest::Certificate::from_der (每个证书)
    ↓
builder.add_root_certificate (每个证书)
    ↓
builder.build
```

### 4. 关键代码实现

```rust
// custom_ca.rs: ConfiguredCaBundle::parse_certificates
fn parse_certificates(&self) -> Result<Vec<CertificateDer<'static>>, BuildCustomCaTransportError> {
    let pem_data = self.read_pem_data()?;
    let normalized_pem = NormalizedPem::from_pem_data(self.source_env, &self.path, &pem_data);

    let mut certificates = Vec::new();
    for section_result in normalized_pem.sections() {
        let (section_kind, der) = match section_result {
            Ok(section) => section,
            Err(error) => return Err(self.pem_parse_error(&error)),
        };
        match section_kind {
            SectionKind::Certificate => {
                let cert_der = normalized_pem.certificate_der(&der).ok_or_else(|| ...)?;
                certificates.push(CertificateDer::from(cert_der.to_vec()));
            }
            SectionKind::Crl => { /* 忽略 CRL */ }
            _ => {}
        }
    }

    if certificates.is_empty() {
        return Err(self.pem_parse_error(&pem::Error::NoItemsFound));
    }

    Ok(certificates)
}
```

### 5. PEM 解析器行为

```rust
// rustls-pki-types 的 PemObject trait 实现
impl PemObject for (SectionKind, Vec<u8>) {
    fn from_pem_slice(pem: &[u8]) -> Result<Self, pem::Error> {
        // 解析单个 PEM 段
    }
    
    fn pem_slice_iter(pem: &[u8]) -> impl Iterator<Item = Result<Self, pem::Error>> {
        // 返回迭代器，可遍历多个 PEM 段
    }
}
```

## 关键代码路径与文件引用

### 1. 证书文件本身
- **路径**：`codex-rs/codex-client/tests/fixtures/test-intermediate.pem`
- **大小**：1310 bytes
- **格式**：X.509 PEM

### 2. 测试代码
- **集成测试**：`codex-rs/codex-client/tests/ca_env.rs`
  - 第 21 行：`const TEST_CERT_2: &str = include_str!("fixtures/test-intermediate.pem");`
  - 第 83-91 行：`handles_multi_certificate_bundle` 测试函数

### 3. 被测代码
- **核心模块**：`codex-rs/codex-client/src/custom_ca.rs`
  - `ConfiguredCaBundle::parse_certificates()` - 多证书解析
  - `NormalizedPem::sections()` - PEM 段迭代
  - 第 448-489 行：证书解析循环逻辑

### 4. 类型定义
- **PemSection 类型别名**：`type PemSection = (SectionKind, Vec<u8>);`
- **SectionKind 枚举**：
  - `Certificate` - 标准证书
  - `Crl` - 证书吊销列表
  - 其他类型（私钥等，在 CA 包中忽略）

## 依赖与外部交互

### 1. 与 test-ca.pem 的协作

```rust
// 测试中的协作方式
const TEST_CERT_1: &str = include_str!("fixtures/test-ca.pem");
const TEST_CERT_2: &str = include_str!("fixtures/test-intermediate.pem");

// 合并为证书包
let bundle = format!("{TEST_CERT_1}\n{TEST_CERT_2}");
```

### 2. 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `rustls-pki-types` | `SectionKind` 枚举和 `PemObject` trait |
| `rustls` | `CertificateDer` 类型 |
| `reqwest` | 证书注册到 HTTP 客户端 |

### 3. PEM 解析流程

```
PEM 文件内容
    ↓
NormalizedPem::from_pem_data
    ↓
PemSection::pem_slice_iter
    ↓
迭代器产生多个 Result<PemSection, pem::Error>
    ↓
每个 PemSection = (SectionKind, Vec<u8>)
    ↓
根据 SectionKind 分类处理
    ├── Certificate → 转换为 CertificateDer
    ├── Crl → 记录日志后忽略
    └── 其他 → 忽略
```

## 风险、边界与改进建议

### 1. 已知风险

#### 风险 1：证书有效期较短
- **问题**：有效期仅 1 年（2025-2026），比 `test-ca.pem` 短得多
- **影响**：2026 年 11 月后证书过期，虽然不影响加载测试，但可能影响完整性验证
- **建议**：重新生成时统一使用更长的有效期（如 10 年）

#### 风险 2：证书链验证的误解
- **问题**：文件注释明确指出 "chain validation is not part of these tests"
- **潜在误解**：开发者可能误以为这两个证书构成有效证书链
- **澄清**：两个证书是完全独立的自签名证书，没有签发关系

### 2. 边界情况

| 边界情况 | 当前处理 | 测试覆盖 |
|----------|----------|----------|
| 两个相同证书 | 会加载两次（冗余但无害） | 未明确测试 |
| 证书 + 私钥混合 | 私钥段被忽略 | 未测试 |
| 证书 + CRL 混合 | CRL 被记录日志后忽略 | 有专门测试 |
| 空行分隔 | 解析器自动处理 | 隐式覆盖 |
| 注释行 | 解析器自动处理 | 隐式覆盖 |

### 3. 改进建议

#### 建议 1：添加证书链测试证书
- **现状**：两个独立证书，无链关系
- **建议**：创建真正的证书链（根 CA → 中间 CA → 叶子证书）
- **用途**：测试完整的证书链验证功能

#### 建议 2：增加性能测试
- **建议**：创建包含大量证书（如 100 个）的测试包
- **目的**：验证大证书包的加载性能

#### 建议 3：统一证书有效期
- **现状**：`test-ca.pem` 10 年，`test-intermediate.pem` 1 年
- **建议**：统一使用相同的长期有效期，减少维护负担

#### 建议 4：添加证书指纹验证
- **建议**：在测试中验证加载的证书指纹与预期一致
- **代码示例**：
  ```rust
  use sha2::{Sha256, Digest};
  let fingerprint = Sha256::digest(&cert_der);
  assert_eq!(fingerprint, expected_fingerprint);
  ```

### 4. 相关文档和参考

- **PEM 格式 RFC**：RFC 7468
- **X.509 标准**：ITU-T X.509 / RFC 5280
- **rustls-pki-types 文档**：https://docs.rs/rustls-pki-types
- **OpenSSL x509 文档**：https://docs.openssl.org/master/man1/openssl-x509/

### 5. 证书生成参考命令

```bash
# 生成中间 CA 证书的参考命令
openssl req -x509 -newkey rsa:2048 -keyout test-intermediate.key \
  -out test-intermediate.pem -days 365 -nodes \
  -subj "/CN=test-intermediate"

# 查看证书信息
openssl x509 -in test-intermediate.pem -text -noout

# 验证证书格式
openssl x509 -in test-intermediate.pem -noout
```
