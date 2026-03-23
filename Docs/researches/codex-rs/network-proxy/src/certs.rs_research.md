# certs.rs 深度研究文档

## 场景与职责

`certs.rs` 是 Codex 网络代理模块中的 **MITM (Man-In-The-Middle) 证书管理核心组件**，负责为 HTTPS 流量拦截功能提供动态 TLS 证书签发能力。该模块实现了自签名 CA 证书的生成、存储、加载以及基于该 CA 的主机证书动态签发功能。

### 核心使用场景
1. **Limited 模式下的 HTTPS 流量审计**：当代理运行在 Limited 模式（只读模式）时，需要通过 MITM 技术终止 TLS 连接，以便检查内部 HTTP 请求方法
2. **本地开发环境**：为本地代理提供可信的 TLS 证书链
3. **安全沙箱**：在受限网络环境中拦截和检查加密流量

---

## 功能点目的

### 1. ManagedMitmCa - 托管 CA 管理器

```rust
pub(super) struct ManagedMitmCa {
    issuer: Issuer<'static, KeyPair>,
}
```

**设计目的**：
- 提供单例模式的 CA 管理，确保整个进程生命周期使用同一 CA 证书
- 自动处理 CA 证书的生成、持久化和加载
- 为每个目标主机动态签发叶子证书

### 2. 证书存储位置

```rust
const MANAGED_MITM_CA_DIR: &str = "proxy";
const MANAGED_MITM_CA_CERT: &str = "ca.pem";
const MANAGED_MITM_CA_KEY: &str = "ca.key";
```

证书存储在 Codex Home 目录下的 `proxy/` 子目录中：
- `ca.pem`: CA 公钥证书（权限 0o644，世界可读）
- `ca.key`: CA 私钥（权限 0o600，仅所有者可读写）

### 3. 安全机制

| 机制 | 实现 | 目的 |
|------|------|------|
| 原子写入 | `write_atomic_create_new` | 防止证书文件写入过程中断导致损坏 |
| 权限控制 | `validate_existing_ca_key_file` | 确保私钥文件权限严格（Unix 下拒绝 group/world 可读） |
| 符号链接检测 | `fs::symlink_metadata` + `is_symlink()` | 防止通过符号链接劫持私钥文件 |
| 文件类型检查 | `metadata.is_file()` | 确保私钥是普通文件而非设备/管道等 |

---

## 具体技术实现

### 1. CA 证书生成流程

```rust
fn generate_ca() -> Result<(String, String)>
```

**实现细节**：
- 使用 `rcgen` crate 生成自签名 X.509 证书
- 密钥算法：**ECDSA P-256 SHA256**（现代、高效、安全）
- 证书用途：CA 证书（`IsCa::Ca(BasicConstraints::Unconstrained)`）
- 密钥用途：`KeyCertSign`, `DigitalSignature`, `KeyEncipherment`
- DN (Distinguished Name): `CN=network_proxy MITM CA`

### 2. 主机证书签发流程

```rust
fn issue_host_certificate_pem(host: &str, issuer: &Issuer<'_, KeyPair>) 
    -> Result<(String, String)>
```

**实现细节**：
- 支持 **IP 地址** 和 **域名** 两种主机类型
- IP 地址：使用 `SanType::IpAddress(ip)` 扩展
- 域名：使用 `CertificateParams::new(vec![host.to_string()])`
- 密钥算法：ECDSA P-256 SHA256（与 CA 一致）
- 扩展密钥用途：`ServerAuth`（仅用于服务器认证）
- 密钥用途：`DigitalSignature`, `KeyEncipherment`

### 3. TLS Acceptor 数据构建

```rust
pub(super) fn tls_acceptor_data_for_host(&self, host: &str) -> Result<TlsAcceptorData>
```

**流程**：
1. 调用 `issue_host_certificate_pem` 生成主机证书和私钥
2. 使用 `CertificateDer::from_pem_slice` 解析证书
3. 使用 `PrivateKeyDer::from_pem_slice` 解析私钥
4. 构建 `rustls::ServerConfig`：
   - 支持所有 TLS 版本 (`ALL_VERSIONS`)
   - 无客户端认证 (`with_no_client_auth`)
   - 单证书链 (`with_single_cert`)
   - ALPN 协议：`h2`, `http/1.1`
5. 转换为 `TlsAcceptorData` 供 Rama 框架使用

### 4. 原子文件写入实现

```rust
fn write_atomic_create_new(path: &Path, contents: &[u8], mode: u32) -> Result<()>
```

**算法**：
1. 生成临时文件路径：`.{filename}.tmp.{pid}.{nanos}`
2. 使用 `O_CREAT | O_EXCL` 标志创建临时文件（防止竞争条件）
3. 写入内容并调用 `fsync` 确保数据落盘
4. 使用 `hard_link` 创建硬链接到目标路径（原子操作）
5. 如果硬链接失败（如不支持），回退到 `rename`（带存在性检查）
6. 打开父目录并 `fsync` 确保目录项持久化
7. 清理临时文件

---

## 关键代码路径与文件引用

### 核心调用链

```
mitm::MitmState::new()
  └── ManagedMitmCa::load_or_create()
      ├── load_or_create_ca()
      │   ├── managed_ca_paths() -> (cert_path, key_path)
      │   ├── validate_existing_ca_key_file() [Unix only]
      │   ├── generate_ca() [如果不存在]
      │   └── write_atomic_create_new() [持久化]
      └── Issuer::from_ca_cert_pem()

mitm::mitm_tunnel()
  └── ManagedMitmCa::tls_acceptor_data_for_host(host)
      └── issue_host_certificate_pem(host, issuer)
```

### 依赖关系

| 依赖 | 用途 |
|------|------|
| `codex_utils_home_dir::find_codex_home` | 定位证书存储目录 |
| `rama_tls_rustls::dep::rcgen` | 证书生成 |
| `rama_tls_rustls::dep::rustls` | TLS 配置 |
| `rama_tls_rustls::dep::pki_types` | 证书/密钥类型 |

### 被调用方

- `mitm.rs`: `MitmState::new()` 初始化 CA，`mitm_tunnel()` 获取主机证书

---

## 依赖与外部交互

### 文件系统交互

| 路径 | 操作 | 权限 |
|------|------|------|
| `$CODEX_HOME/proxy/` | 创建目录 | 默认 |
| `$CODEX_HOME/proxy/ca.pem` | 读取/创建 | 0o644 |
| `$CODEX_HOME/proxy/ca.key` | 读取/创建 | 0o600 |

### 环境变量

- `CODEX_HOME`: 确定证书存储根目录（通过 `find_codex_home()`）

### 平台特定行为

| 平台 | 行为差异 |
|------|----------|
| Unix | 严格权限检查、符号链接检测、自定义 mode 创建文件 |
| Windows | 无权限检查、无符号链接检测、标准文件创建 |

---

## 风险、边界与改进建议

### 安全风险

1. **CA 私钥泄露风险**
   - 私钥存储在用户主目录，如果系统被入侵，攻击者可签发任意域名的伪造证书
   - **缓解**：0o600 权限、符号链接检测、原子写入

2. **DNS 重绑定攻击**
   - 虽然证书签发时验证了主机名，但后续连接可能遭遇 DNS 重绑定
   - **缓解**：在 `mitm.rs` 中重新检查 `host_blocked`

3. **TOCTOU 竞争条件**
   - `write_atomic_create_new` 的回退路径使用 `path.exists()` 检查后再 `rename`
   - **缓解**：优先使用硬链接（原子操作），回退路径仅在硬链接不支持时启用

### 边界条件

| 场景 | 行为 |
|------|------|
| CA 证书存在但私钥缺失 | 报错：要求两者同时存在或同时不存在 |
| CA 私钥权限过于宽松 | 报错：拒绝使用 group/world 可读的私钥 |
| CA 私钥是符号链接 | 报错：拒绝使用符号链接 |
| 主机名是 IPv6 地址 | 正确处理：使用 `SanType::IpAddress` |
| 并发初始化 | 安全：原子文件创建防止竞争 |

### 改进建议

1. **证书轮换机制**
   - 当前 CA 证书永久有效，建议添加过期检测和自动轮换
   ```rust
   // 建议添加
   fn should_rotate_ca(cert: &Certificate) -> bool {
       cert.not_after() < SystemTime::now() + Duration::days(30)
   }
   ```

2. **硬件安全模块 (HSM) 支持**
   - 对于高安全场景，支持将 CA 私钥存储在系统钥匙串或 HSM 中

3. **证书透明度 (CT) 日志**
   - 考虑将签发的叶子证书提交到私有 CT 日志，便于审计

4. **内存安全**
   - 私钥在内存中以 `String` 形式存在，考虑使用 `secrecy` crate 进行内存保护

5. **测试覆盖**
   - 当前测试仅覆盖权限检查，建议添加：
     - 并发初始化测试
     - 磁盘满/权限拒绝错误处理测试
     - 大主机名/特殊字符处理测试
