# codex-rs/secrets/Cargo.toml 研究文档

## 场景与职责

`Cargo.toml` 是 Rust crate `codex-secrets` 的清单文件（manifest），定义了包的元数据、依赖关系和构建配置。该 crate 是 Codex 项目的密钥管理模块，负责：

1. **安全存储**: 使用 `age` 加密算法将敏感信息（API Key、Token 等）加密存储在本地文件系统
2. **密钥保护**: 通过 OS Keyring（macOS Keychain、Windows Credential Manager、Linux Secret Service）保护加密密钥
3. **敏感信息脱敏**: 提供 `redact_secrets` 函数，在日志、记忆中自动脱敏敏感信息

该 crate 是 `codex-core` 的关键依赖，被用于管理 OpenAI API Key 等敏感配置。

## 功能点目的

### 1. 包元数据

```toml
[package]
name = "codex-secrets"
version.workspace = true
edition.workspace = true
license.workspace = true
```

| 字段 | 值 | 说明 |
|------|-----|------|
| `name` | `codex-secrets` | crate 名称（kebab-case） |
| `version.workspace` | `true` | 从 workspace 继承版本号 |
| `edition.workspace` | `true` | 从 workspace 继承 Rust edition（通常为 2021） |
| `license.workspace` | `true` | 从 workspace 继承许可证（Apache-2.0） |

### 2. Lint 配置

```toml
[lints]
workspace = true
```

继承 workspace 级别的 lint 配置，确保代码风格一致性。

### 3. 依赖项

#### 核心依赖

| 依赖 | 来源 | 用途 |
|------|------|------|
| `age` | workspace | 现代加密工具，用于文件加密/解密（使用 scrypt 密钥派生） |
| `anyhow` | workspace | 简洁的错误处理 |
| `base64` | workspace | 密钥的 Base64 编码/解码 |
| `codex-keyring-store` | workspace | OS Keyring 抽象层，跨平台凭证存储 |
| `rand` | workspace | 加密安全随机数生成（生成 32 字节密钥） |
| `regex` | workspace | 脱敏正则表达式匹配 |
| `schemars` | workspace | 为配置类型生成 JSON Schema |
| `serde` | workspace | 数据结构序列化/反序列化 |
| `serde_json` | workspace | JSON 格式处理 |
| `sha2` | workspace | SHA-256 哈希（生成环境 ID 和 Keyring 账户名） |
| `tracing` | workspace | 结构化日志和追踪 |

#### 开发依赖

| 依赖 | 来源 | 用途 |
|------|------|------|
| `keyring` | workspace | 测试中使用真实的 OS Keyring 实现 |
| `pretty_assertions` | workspace | 测试断言美化输出 |
| `tempfile` | workspace | 测试时创建临时目录 |

## 具体技术实现

### 关键流程

#### 1. 密钥存储流程

```
用户输入密钥
    ↓
SecretName 验证（大写字母、数字、下划线）
    ↓
生成 canonical_key（如 "env/myrepo/GITHUB_TOKEN"）
    ↓
加载/创建加密密钥（从 OS Keyring 或生成新密钥）
    ↓
使用 age(scrypt) 加密密钥值
    ↓
原子写入 ~/.codex/secrets/local.age
```

#### 2. 密钥读取流程

```
请求密钥
    ↓
计算 canonical_key
    ↓
从 OS Keyring 加载加密密钥
    ↓
解密 local.age 文件
    ↓
返回密钥值
```

#### 3. 脱敏流程

```
输入文本
    ↓
依次应用 4 个正则表达式：
  - OpenAI Key: sk-[A-Za-z0-9]{20,}
  - AWS Access Key: AKIA[0-9A-Z]{16}
  - Bearer Token: Bearer\s+[A-Za-z0-9._\-]{16,}
  - Secret Assignment: (api_key|token|secret|password)[:=]...
    ↓
替换为 [REDACTED_SECRET]
    ↓
返回脱敏文本
```

### 数据结构

#### SecretName
```rust
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct SecretName(String);
```
- 验证规则：仅允许大写字母、数字、下划线
- 示例：`GITHUB_TOKEN`, `OPENAI_API_KEY`

#### SecretScope
```rust
pub enum SecretScope {
    Global,
    Environment(String),
}
```
- `Global`: 全局作用域，所有项目共享
- `Environment`: 特定环境（如 git 仓库名）

#### SecretsFile
```rust
struct SecretsFile {
    version: u8,              // 当前为 1
    secrets: BTreeMap<String, String>,  // canonical_key → 密钥值
}
```

### 协议/命令

#### 加密协议
- **算法**: age (https://age-encryption.org/)
- **密钥派生**: scrypt
- **密钥长度**: 32 字节（256 位）
- **密钥编码**: Base64
- **文件格式**: JSON（序列化后加密）

#### 文件位置
```
~/.codex/secrets/local.age      # 加密存储文件
~/.codex/                       # codex_home（可配置）
```

#### Keyring 账户名格式
```
service: "codex"
account: "secrets|{sha256(codex_home)[:16]}"
```

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/secrets/Cargo.toml` - 本文件

### 源码文件
- `/home/sansha/Github/codex/codex-rs/secrets/src/lib.rs` (245 行)
  - `SecretName` 定义和验证
  - `SecretScope` 定义
  - `SecretsManager` 主入口
  - `SecretsBackend` trait
  - `environment_id_from_cwd()` - 从当前目录生成环境 ID
  - `compute_keyring_account()` - 计算 Keyring 账户名

- `/home/sansha/Github/codex/codex-rs/secrets/src/local.rs` (411 行)
  - `LocalSecretsBackend` 实现
  - `SecretsFile` 序列化/反序列化
  - `encrypt_with_passphrase()` / `decrypt_with_passphrase()`
  - `write_file_atomically()` - 原子文件写入
  - `generate_passphrase()` - 生成 32 字节随机密钥
  - `wipe_bytes()` - 安全擦除内存

- `/home/sansha/Github/codex/codex-rs/secrets/src/sanitizer.rs` (41 行)
  - `redact_secrets()` - 敏感信息脱敏
  - 4 个静态正则表达式

### 依赖 crate
- `/home/sansha/Github/codex/codex-rs/keyring-store/src/lib.rs` (226 行)
  - `KeyringStore` trait
  - `DefaultKeyringStore` - 默认 OS Keyring 实现
  - `MockKeyringStore` - 测试用 mock

### 调用方
- `/home/sansha/Github/codex/codex-rs/core/src/memories/phase1.rs`
  - 使用 `redact_secrets()` 脱敏记忆数据
  - 防止敏感信息泄露到长期记忆中

## 依赖与外部交互

### 内部依赖（codex-rs workspace）

```
codex-secrets
    ↓
codex-keyring-store
```

### 外部依赖（crates.io）

| 依赖 | 版本 | 功能特性 |
|------|------|----------|
| `age` | workspace | 加密/解密 |
| `keyring` | workspace | OS Keyring 访问（仅测试） |

### OS Keyring 平台支持

| 平台 | 后端 |
|------|------|
| macOS | Keychain Services |
| Windows | Windows Credential Manager |
| Linux | Secret Service API / kwallet |

### 被依赖关系

```
codex-core
    ↓
codex-secrets
```

## 风险、边界与改进建议

### 风险

#### 1. 安全相关

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| 密钥泄露 | OS Keyring 被攻破导致所有密钥泄露 | 使用系统级访问控制，定期轮换 |
| 内存残留 | 密钥可能在内存中残留 | `wipe_bytes()` 使用 `write_volatile` 和 `compiler_fence` |
| 临时文件 | 原子写入过程中临时文件可能残留 | 使用唯一命名的临时文件，失败时清理 |
| 正则绕过 | 脱敏正则可能遗漏新型密钥格式 | 定期更新正则规则 |

#### 2. 可靠性相关

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| Keyring 不可用 | CI/无头环境无 Keyring | 测试使用 `MockKeyringStore` |
| 文件损坏 | local.age 损坏导致所有密钥丢失 | 版本检查，优雅降级 |
| 并发写入 | 多进程同时写入可能冲突 | 原子文件替换 |

### 边界

1. **仅支持本地存储**
   - 无云 KMS 支持（AWS KMS、GCP KMS、Azure Key Vault）
   - 无密钥共享/同步机制

2. **命名限制**
   - `SecretName` 严格限制为 `[A-Z0-9_]+`
   - 不支持小写字母、连字符等

3. **作用域限制**
   - 环境 ID 基于 git 仓库名或 CWD 哈希
   - 不支持自定义环境标识

4. **脱敏限制**
   - 仅支持 4 种预定义模式
   - 无法检测所有可能的敏感信息格式

### 改进建议

#### 1. 增强安全性

```rust
// 建议：支持硬件安全模块（HSM）
pub enum SecretsBackendKind {
    Local,
    #[cfg(feature = "hsm")]
    Hsm(HsmConfig),
}
```

#### 2. 扩展脱敏规则

```rust
// 建议：支持配置化脱敏规则
pub struct RedactionConfig {
    patterns: Vec<Regex>,
    replacement: String,
}
```

#### 3. 密钥版本管理

```rust
// 建议：支持密钥版本
struct SecretsFile {
    version: u8,
    key_id: String,  // 新增：密钥标识
    secrets: BTreeMap<String, VersionedSecret>,
}

struct VersionedSecret {
    value: String,
    created_at: u64,
    version: u32,
}
```

#### 4. 备份与恢复

```rust
// 建议：导出/导入功能
impl SecretsManager {
    pub fn export(&self, scope: &SecretScope) -> Result<EncryptedExport>;
    pub fn import(&self, export: &EncryptedExport) -> Result<()>;
}
```

#### 5. 审计日志

```rust
// 建议：记录密钥访问日志
trait SecretsBackend {
    fn audit_log(&self, action: AuditAction, name: &SecretName);
}
```

#### 6. 依赖优化

当前 `Cargo.toml` 中 `regex` 是完整依赖，如果仅用于简单模式匹配，可以考虑：
- 使用 `regex-lite` 减小二进制体积
- 或使用 `aho-corasick` 进行多模式匹配（性能更好）

#### 7. 测试覆盖

当前测试主要覆盖：
- ✅ 密钥读写删列
- ✅ 版本兼容性
- ✅ Keyring 错误处理
- ✅ 原子写入

建议增加：
- 并发写入测试
- 大密钥值测试
- 特殊字符处理测试
- 跨平台 Keyring 测试
