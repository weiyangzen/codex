# test-ca-trusted.pem 研究文档

## 场景与职责

`test-ca-trusted.pem` 是 Codex 客户端测试套件中的特殊测试证书文件，专门用于验证 **OpenSSL TRUSTED CERTIFICATE 格式** 的处理能力。这是三种测试证书中最具技术特殊性的一种，用于测试系统对非标准 PEM 标签的兼容性。

该证书的核心价值在于验证 `custom_ca.rs` 模块中的 **X509_AUX 修剪路径（trimming path）**，确保系统能够正确处理 OpenSSL 生成的带有信任元数据的证书文件。

## 功能点目的

### 1. 核心测试目标
- **TRUSTED CERTIFICATE 格式支持**：验证系统能解析 `-----BEGIN TRUSTED CERTIFICATE-----` 标签
- **X509_AUX 数据修剪**：验证系统能正确移除 OpenSSL 附加的信任元数据
- **标签规范化**：验证 PEM 标签从 `TRUSTED CERTIFICATE` 到 `CERTIFICATE` 的转换

### 2. 测试覆盖场景
该证书被用于以下测试场景（定义在 `tests/ca_env.rs` 中）：
- `accepts_openssl_trusted_certificate`：验证 OpenSSL TRUSTED CERTIFICATE 格式被接受

```rust
#[test]
fn accepts_openssl_trusted_certificate() {
    let temp_dir = TempDir::new().expect("tempdir");
    let cert_path = write_cert_file(&temp_dir, "trusted.pem", TRUSTED_TEST_CERT);
    let output = run_probe(&[(CODEX_CA_CERT_ENV, cert_path.as_path())]);
    assert!(output.status.success());
}
```

### 3. 证书特性
- **类型**：OpenSSL TRUSTED CERTIFICATE 格式
- **标签**：`-----BEGIN TRUSTED CERTIFICATE-----`
- **特殊数据**：包含 X509_AUX 信任元数据（trailing bytes）
- **用途**：验证 X509_AUX 修剪路径
- **有效期**：与 `test-ca.pem` 相同（2025-12-11 至 2035-12-09）
- **主题**：CN=test-ca（与 `test-ca.pem` 相同的基础证书）

## 具体技术实现

### 1. 证书生成过程

```bash
# 从 test-ca.pem 生成 TRUSTED CERTIFICATE
openssl x509 -in test-ca.pem -addtrust serverAuth -trustout -out test-ca-trusted.pem
```

生成参数说明：
- `-addtrust serverAuth`：添加服务器认证信任用途
- `-trustout`：输出 TRUSTED CERTIFICATE 格式

### 2. 格式差异对比

#### 标准 CERTIFICATE（test-ca.pem）
```
-----BEGIN CERTIFICATE-----
MIIDBTCCAe2gAwIBAgIUZYhGvBUG7SucNzYh9VIeZ7b9zHowDQYJKoZIhvcNAQEL
...
-----END CERTIFICATE-----
```

#### TRUSTED CERTIFICATE（test-ca-trusted.pem）
```
-----BEGIN TRUSTED CERTIFICATE-----
MIIDBTCCAe2gAwIBAgIUZYhGvBUG7SucNzYh9VIeZ7b9zHowDQYJKoZIhvcNAQEL
...
SprtRUBjlWzjMAwwCgYIKwYBBQUHAwE=
-----END TRUSTED CERTIFICATE-----
```

**关键区别**：
1. PEM 标签不同：`TRUSTED CERTIFICATE` vs `CERTIFICATE`
2. 末尾附加 X509_AUX 数据（Base64 编码的 `MAwwCgYIKwYBBQUHAwE=`）
3. 文件大小略大（1539 vs 1273 bytes）

### 3. X509_AUX 数据结构

OpenSSL 的 X509_AUX 结构包含：
- 信任用途（trust purposes）
- 拒绝用途（reject purposes）
- 别名（alias）
- 其他 OpenSSL 特定的信任元数据

```c
// OpenSSL 内部结构（简化）
typedef struct X509_CERT_AUX_st {
    STACK_OF(ASN1_OBJECT) *trust;    // 信任用途
    STACK_OF(ASN1_OBJECT) *reject;   // 拒绝用途
    ASN1_UTF8STRING *alias;          // 别名
    ASN1_OCTET_STRING *keyid;        // 密钥 ID
    OTHERNAME *other;                // 其他数据
} X509_CERT_AUX;
```

### 4. 处理流程

```
test-ca-trusted.pem (TRUSTED CERTIFICATE)
    ↓
include_str! 编译时嵌入
    ↓
TRUSTED_TEST_CERT 常量
    ↓
NormalizedPem::from_pem_data
    ↓
检测到 "TRUSTED CERTIFICATE" 标签
    ↓
标签规范化：替换为 "CERTIFICATE"
    ↓
创建 NormalizedPem::TrustedCertificate 变体
    ↓
PemSection::pem_slice_iter 解析
    ↓
获取 DER 数据（包含 X509_AUX 后缀）
    ↓
normalized_pem.certificate_der(&der)
    ↓
first_der_item(der) 修剪 X509_AUX
    ↓
返回第一个 DER 对象的长度
    ↓
reqwest::Certificate::from_der (修剪后的数据)
    ↓
注册到根证书存储
```

### 5. 关键代码实现

#### 标签规范化
```rust
// custom_ca.rs: NormalizedPem::from_pem_data
fn from_pem_data(source_env: &'static str, path: &Path, pem_data: &[u8]) -> Self {
    let pem = String::from_utf8_lossy(pem_data);
    if pem.contains("TRUSTED CERTIFICATE") {
        info!(... "normalizing OpenSSL TRUSTED CERTIFICATE labels");
        Self::TrustedCertificate(
            pem.replace("BEGIN TRUSTED CERTIFICATE", "BEGIN CERTIFICATE")
                .replace("END TRUSTED CERTIFICATE", "END CERTIFICATE")
        )
    } else {
        Self::Standard(pem.into_owned())
    }
}
```

#### DER 修剪
```rust
// custom_ca.rs: NormalizedPem::certificate_der
fn certificate_der<'a>(&self, der: &'a [u8]) -> Option<&'a [u8]> {
    match self {
        Self::Standard(_) => Some(der),  // 标准格式无需修剪
        Self::TrustedCertificate(_) => first_der_item(der),  // 需要修剪
    }
}

// 获取第一个 DER 项目的长度
fn first_der_item(der: &[u8]) -> Option<&[u8]> {
    der_item_length(der).map(|length| &der[..length])
}
```

#### DER 长度解析
```rust
// custom_ca.rs: der_item_length
fn der_item_length(der: &[u8]) -> Option<usize> {
    let &length_octet = der.get(1)?;
    
    // 短形式：长度直接存储在第二个字节
    if length_octet & 0x80 == 0 {
        return Some(2 + usize::from(length_octet))
            .filter(|length| *length <= der.len());
    }
    
    // 长形式：第二个字节表示后续多少字节存储长度值
    let length_octets = usize::from(length_octet & 0x7f);
    if length_octets == 0 {
        return None;  // 无限长度（DER 不允许）
    }
    
    // 解析长度字节
    let length_start = 2usize;
    let length_end = length_start.checked_add(length_octets)?;
    let length_bytes = der.get(length_start..length_end)?;
    let mut content_length = 0usize;
    for &byte in length_bytes {
        content_length = content_length
            .checked_mul(256)?
            .checked_add(usize::from(byte))?;
    }
    
    length_end
        .checked_add(content_length)
        .filter(|length| *length <= der.len())
}
```

## 关键代码路径与文件引用

### 1. 证书文件本身
- **路径**：`codex-rs/codex-client/tests/fixtures/test-ca-trusted.pem`
- **大小**：1539 bytes（比标准格式多 266 bytes）
- **格式**：OpenSSL TRUSTED CERTIFICATE PEM

### 2. 测试代码
- **集成测试**：`codex-rs/codex-client/tests/ca_env.rs`
  - 第 22 行：`const TRUSTED_TEST_CERT: &str = include_str!("fixtures/test-ca-trusted.pem");`
  - 第 126-133 行：`accepts_openssl_trusted_certificate` 测试函数

### 3. 被测代码
- **核心模块**：`codex-rs/codex-client/src/custom_ca.rs`
  - `NormalizedPem` 枚举（第 538-543 行）
    - `Standard(String)` - 标准 PEM
    - `TrustedCertificate(String)` - 规范化后的 TRUSTED CERTIFICATE
  - `NormalizedPem::from_pem_data()` - 标签规范化（第 570-585 行）
  - `NormalizedPem::certificate_der()` - DER 数据提取（第 608-613 行）
  - `first_der_item()` - X509_AUX 修剪（第 628-630 行）
  - `der_item_length()` - DER 长度解析（第 656-680 行）

### 4. 相关注释和文档
- **文件头注释**（第 1-6 行）：
  ```
  # Test-only OpenSSL trusted-certificate fixture generated from test-ca.pem with
  # `openssl x509 -addtrust serverAuth -trustout`.
  # The extra trailing bytes model the OpenSSL X509_AUX data that follows the
  # certificate DER in real TRUSTED CERTIFICATE bundles.
  # This fixture exists to validate the X509_AUX trimming path against a real
  # OpenSSL-generated artifact, not just label normalization.
  ```

### 5. 代码中的参考链接

```rust
// custom_ca.rs: NormalizedPem::from_pem_data 中的文档注释
/// See also:
/// - rustls/pemfile issue #52, closed as not planned, documenting that
///   `BEGIN TRUSTED CERTIFICATE` blocks are ignored upstream
/// - OpenSSL `x509 -trustout`, which emits `TRUSTED CERTIFICATE` PEM blocks
/// - OpenSSL PEM readers, which document that plain `PEM_read_bio_X509()` 
///   discards auxiliary trust settings
```

具体链接：
- rustls/pemfile issue #52: https://github.com/rustls/pemfile/issues/52
- OpenSSL x509: https://docs.openssl.org/master/man1/openssl-x509/
- OpenSSL PEM: https://docs.openssl.org/master/man3/PEM_read_bio_PrivateKey/

## 依赖与外部交互

### 1. 与 test-ca.pem 的关系

```
test-ca.pem (标准格式)
    ↓
openssl x509 -addtrust serverAuth -trustout
    ↓
test-ca-trusted.pem (TRUSTED CERTIFICATE 格式)
    ↓
测试验证两者在功能上等价
```

### 2. 外部依赖

| 依赖 | 用途 |
|------|------|
| OpenSSL | 生成 TRUSTED CERTIFICATE 格式 |
| rustls-pki-types | PEM 解析（不支持 TRUSTED CERTIFICATE） |
| reqwest | 证书注册（需要标准 DER） |

### 3. 上游限制

**重要**：`rustls-pemfile` crate 明确不支持 `TRUSTED CERTIFICATE` 格式：
- GitHub Issue #52 被标记为 "not planned"
- 因此 Codex 需要在本地实现标签规范化和 X509_AUX 修剪

## 风险、边界与改进建议

### 1. 已知风险

#### 风险 1：DER 长度解析的健壮性
- **问题**：`der_item_length` 函数只解析外层 DER 长度，不验证内部结构
- **潜在问题**：如果 DER 结构异常，可能导致错误的长度计算
- **缓解**：函数返回 `Option<usize>`，失败时返回 `None` 而非 panic

#### 风险 2：X509_AUX 格式变化
- **问题**：OpenSSL 未来版本可能改变 X509_AUX 格式
- **影响**：当前的修剪逻辑可能失效
- **缓解**：使用真实的 OpenSSL 生成文件进行测试，能及时发现格式变化

#### 风险 3：多证书 TRUSTED CERTIFICATE 包
- **问题**：当前测试仅覆盖单证书场景
- **潜在问题**：多证书 TRUSTED CERTIFICATE 包的处理未经验证
- **建议**：添加多证书 TRUSTED CERTIFICATE 包测试

### 2. 边界情况

| 边界情况 | 当前处理 | 风险等级 |
|----------|----------|----------|
| 空 X509_AUX | 正常处理（无额外数据） | 低 |
| 大 X509_AUX | 正常处理（DER 长度计算正确） | 低 |
| 损坏的 DER | 返回 None，测试失败 | 低 |
| 无限长度 DER | 返回 None（DER 不允许） | 低 |
| 部分截断 | 返回 None（长度检查） | 低 |

### 3. 改进建议

#### 建议 1：添加更多 TRUSTED CERTIFICATE 变体
```bash
# 不同的信任用途
openssl x509 -addtrust clientAuth -trustout ...
openssl x509 -addtrust emailProtection -trustout ...
openssl x509 -addtrust codeSigning -trustout ...
```

#### 建议 2：验证修剪后的证书等价性
```rust
// 建议添加的测试
#[test]
fn trusted_certificate_produces_same_der() {
    let standard = parse_cert("test-ca.pem");
    let trusted = parse_and_trim("test-ca-trusted.pem");
    assert_eq!(standard.der, trusted.der);
}
```

#### 建议 3：添加 DER 解析的单元测试
```rust
#[test]
fn der_item_length_handles_short_form() {
    // 测试短形式长度（< 128）
}

#[test]
fn der_item_length_handles_long_form() {
    // 测试长形式长度（>= 128）
}

#[test]
fn der_item_length_rejects_indefinite() {
    // 测试拒绝无限长度
}
```

#### 建议 4：性能优化
- **现状**：每个 TRUSTED CERTIFICATE 都进行字符串替换和 DER 解析
- **建议**：如果性能成为问题，可以考虑缓存规范化结果

### 4. 相关标准和文档

- **DER 编码规则**：ITU-T X.690
- **ASN.1 基本编码规则**：BER/DER/CER
- **OpenSSL X509_AUX**：crypto/x509/x_x509.c 中的实现
- **RFC 5280**：X.509 证书和 CRL 配置文件

### 5. 调试技巧

```bash
# 查看 TRUSTED CERTIFICATE 的详细信息
openssl x509 -in test-ca-trusted.pem -text -noout

# 提取并查看 X509_AUX 数据
openssl asn1parse -in test-ca-trusted.pem

# 比较两个证书的 DER 内容
openssl x509 -in test-ca.pem -outform DER | xxd > standard.der
openssl x509 -in test-ca-trusted.pem -outform DER | xxd > trusted.der
diff standard.der trusted.der

# 验证证书信任设置
openssl x509 -in test-ca-trusted.pem -purpose -noout
```

### 6. 维护注意事项

1. **重新生成证书时**：必须使用相同的 OpenSSL 命令和参数
2. **测试失败时**：首先检查 DER 长度解析逻辑是否正确
3. **升级 rustls-pki-types 时**：注意其 PEM 解析行为的变化
4. **添加新格式支持时**：参考 TRUSTED CERTIFICATE 的实现模式
