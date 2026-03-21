# codex-rs/keyring-store 研究文档

## 概述

`codex-keyring-store` 是 Codex CLI 的凭证存储抽象层，提供跨平台的操作系统密钥环（keyring）访问能力。它封装了底层 `keyring` crate，为上层模块提供统一的凭证存取接口。

---

## 场景与职责

### 核心职责

1. **跨平台凭证存储抽象**：屏蔽不同操作系统密钥环实现的差异（macOS Keychain、Windows Credential Manager、Linux Secret Service/Keyutils）
2. **安全凭证管理**：为敏感数据（API密钥、OAuth令牌、加密密钥）提供安全的持久化存储
3. **测试支持**：提供 Mock 实现，便于单元测试中的凭证操作模拟

### 使用场景

| 场景 | 说明 |
|------|------|
| CLI 认证存储 | 存储 OpenAI API Key、OAuth Token (`core/src/auth/storage.rs`) |
| Secrets 加密密钥 | 保护 `local.age` 文件的加密密钥 (`secrets/src/local.rs`) |
| MCP OAuth 凭证 | 存储 MCP 服务器的 OAuth 令牌 (`rmcp-client/src/oauth.rs`) |

---

## 功能点目的

### 1. `KeyringStore` Trait

定义凭证存储的标准接口：

```rust
pub trait KeyringStore: Debug + Send + Sync {
    fn load(&self, service: &str, account: &str) -> Result<Option<String>, CredentialStoreError>;
    fn save(&self, service: &str, account: &str, value: &str) -> Result<(), CredentialStoreError>;
    fn delete(&self, service: &str, account: &str) -> Result<bool, CredentialStoreError>;
}
```

**设计意图**：
- 通过 trait 抽象允许不同的存储后端实现（真实 keyring / Mock）
- `service` + `account` 组合作为唯一键，类似钥匙串的条目组织方式
- 返回 `Option<String>` 区分"不存在"和"出错"两种情况

### 2. `DefaultKeyringStore`

生产环境使用的默认实现，直接委托给 `keyring` crate：

- **load**: 调用 `Entry::new(service, account).get_password()`
- **save**: 调用 `Entry::new(service, account).set_password(value)`
- **delete**: 调用 `Entry::new(service, account).delete_credential()`

**错误处理**：
- `keyring::Error::NoEntry` 映射为 `Ok(None)` 或 `Ok(false)`
- 其他错误包装为 `CredentialStoreError`

### 3. `MockKeyringStore` (测试模块)

基于内存 HashMap 的 Mock 实现：

```rust
pub struct MockKeyringStore {
    credentials: Arc<Mutex<HashMap<String, Arc<MockCredential>>>>,
}
```

**测试能力**：
- `set_error(account, error)`: 模拟特定账户的 keyring 错误
- `saved_value(account)`: 验证保存的值
- `contains(account)`: 检查账户是否存在
- `credential(account)`: 获取底层 MockCredential 进行细粒度控制

---

## 具体技术实现

### 关键数据结构

#### `CredentialStoreError`

```rust
#[derive(Debug)]
pub enum CredentialStoreError {
    Other(KeyringError),
}
```

- 简单包装 `keyring::Error`，提供 `message()` 和 `into_error()` 方法
- 实现 `Display` 和 `std::error::Error` trait

#### 平台特定的依赖配置

```toml
# Cargo.toml
[target.'cfg(target_os = "linux")'.dependencies]
keyring = { workspace = true, features = ["linux-native-async-persistent"] }

[target.'cfg(target_os = "macos")'.dependencies]
keyring = { workspace = true, features = ["apple-native"] }

[target.'cfg(target_os = "windows")'.dependencies]
keyring = { workspace = true, features = ["windows-native"] }

[target.'cfg(any(target_os = "freebsd", target_os = "openbsd"))'.dependencies]
keyring = { workspace = true, features = ["sync-secret-service"] }
```

### 关键流程

#### 凭证加载流程

```
KeyringStore::load(service, account)
    ├── Entry::new(service, account)  // 创建 keyring 条目
    ├── entry.get_password()          // 获取密码
    │       ├── Ok(password) -> Ok(Some(password))
    │       ├── Err(NoEntry) -> Ok(None)
    │       └── Err(other) -> Err(CredentialStoreError)
    └── trace! 日志记录
```

#### 凭证保存流程

```
KeyringStore::save(service, account, value)
    ├── Entry::new(service, account)  // 创建 keyring 条目
    ├── entry.set_password(value)     // 设置密码
    │       ├── Ok(()) -> Ok(())
    │       └── Err(error) -> Err(CredentialStoreError)
    └── trace! 日志记录 (包含 value_len)
```

#### 凭证删除流程

```
KeyringStore::delete(service, account)
    ├── Entry::new(service, account)  // 创建 keyring 条目
    ├── entry.delete_credential()     // 删除凭证
    │       ├── Ok(()) -> Ok(true)
    │       ├── Err(NoEntry) -> Ok(false)
    │       └── Err(other) -> Err(CredentialStoreError)
    └── trace! 日志记录
```

### 调用方使用模式

#### 1. Secrets 模块 (`secrets/src/lib.rs`)

```rust
const KEYRING_SERVICE: &str = "codex";

pub(crate) fn compute_keyring_account(codex_home: &Path) -> String {
    // SHA256(codex_home_path) 前16位
    format!("secrets|{short_hash}")
}

// 使用
let keyring_store: Arc<dyn KeyringStore> = Arc::new(DefaultKeyringStore);
keyring_store.load(keyring_service(), &account)
```

#### 2. Auth Storage (`core/src/auth/storage.rs`)

```rust
const KEYRING_SERVICE: &str = "Codex Auth";

fn compute_store_key(codex_home: &Path) -> String {
    format!("cli|{short_hash}")  // SHA256 前16位
}

// KeyringAuthStorage 包装
struct KeyringAuthStorage {
    codex_home: PathBuf,
    keyring_store: Arc<dyn KeyringStore>,
}
```

#### 3. MCP OAuth (`rmcp-client/src/oauth.rs`)

```rust
const KEYRING_SERVICE: &str = "Codex MCP Credentials";

fn compute_store_key(server_name: &str, url: &str) -> String {
    // SHA256(server_name + "|" + url) 前16位
}

// 支持 fallback 到文件存储
fn load_oauth_tokens_from_keyring_with_fallback_to_file<K: KeyringStore>(...)
```

---

## 关键代码路径与文件引用

### 本 crate 文件

| 文件 | 说明 |
|------|------|
| `codex-rs/keyring-store/src/lib.rs` | 主库代码，包含 trait、DefaultKeyringStore、MockKeyringStore |
| `codex-rs/keyring-store/Cargo.toml` | 包配置，平台特定依赖 |
| `codex-rs/keyring-store/BUILD.bazel` | Bazel 构建配置 |

### 调用方文件

| 文件 | 用途 |
|------|------|
| `codex-rs/secrets/src/lib.rs` | SecretsManager，使用 keyring 存储加密密钥 |
| `codex-rs/secrets/src/local.rs` | LocalSecretsBackend，load_or_create_passphrase |
| `codex-rs/core/src/auth/storage.rs` | CLI 认证存储，KeyringAuthStorage |
| `codex-rs/core/src/auth/storage_tests.rs` | 认证存储测试，使用 MockKeyringStore |
| `codex-rs/rmcp-client/src/oauth.rs` | MCP OAuth 令牌存储 |

---

## 依赖与外部交互

### 外部依赖

| Crate | 用途 |
|-------|------|
| `keyring` (v3.6) | 底层操作系统密钥环访问 |
| `tracing` | 日志追踪 |

### 平台特定后端

| 平台 | 后端 | 说明 |
|------|------|------|
| macOS | `apple-native` | macOS Keychain |
| Windows | `windows-native` | Windows Credential Manager |
| Linux | `linux-native-async-persistent` | keyutils + async-secret-service |
| FreeBSD/OpenBSD | `sync-secret-service` | DBus Secret Service |

### 上游依赖关系

```
codex-keyring-store
    ├── keyring crate (系统密钥环)
    └── tracing (日志)

调用方:
    ├── codex-secrets (加密密钥存储)
    ├── codex-core (CLI 认证)
    └── codex-rmcp-client (OAuth 令牌)
```

---

## 风险、边界与改进建议

### 已知风险

1. **Linux 依赖 DBus**
   - Linux 平台依赖 DBus Secret Service，在无桌面环境的服务器可能不可用
   - 调用方已实现 fallback 到文件存储的机制

2. **并发访问**
   - `MockKeyringStore` 使用 `Mutex` 保护 HashMap，但真实 keyring 的并发行为取决于 OS 实现
   - 无分布式锁机制，多进程同时修改同一 key 的行为未定义

3. **密钥丢失风险**
   - 用户清除 keyring 或重置系统后，存储的密钥会丢失
   - `secrets` 模块的加密文件将无法解密（设计如此，无后门）

### 边界情况

| 场景 | 行为 |
|------|------|
| Keyring 服务不可用 | 返回错误，由调用方决定 fallback 策略 |
| 条目不存在 | `load` 返回 `Ok(None)`，`delete` 返回 `Ok(false)` |
| 空值存储 | 允许存储空字符串（由 keyring crate 决定） |
| 特殊字符 | service/account 字符串直接传递给 keyring，无额外转义 |

### 改进建议

1. **错误类型细化**
   - 当前 `CredentialStoreError` 仅简单包装 `KeyringError`
   - 建议区分：ServiceUnavailable、PermissionDenied、NotFound 等具体错误类型

2. **重试机制**
   - keyring 操作可能因临时资源锁定失败
   - 建议增加指数退避重试（特别是 Linux Secret Service）

3. **缓存层**
   - 高频读取场景（如每次请求都需解密 secrets）可考虑内存缓存
   - 需注意安全：缓存需有 TTL，进程退出时清理

4. **监控指标**
   - 当前仅有 trace 日志
   - 建议增加指标：操作成功率、延迟分布、fallback 触发次数

5. **Mock 增强**
   - 当前 Mock 仅支持按 account 设置错误
   - 建议增加：按 service 设置错误、模拟延迟、并发访问计数

---

## 总结

`codex-keyring-store` 是一个简洁但关键的抽象层，它将平台特定的凭证存储能力统一为 Rust trait 接口。设计上遵循了以下原则：

1. **最小化抽象**：仅暴露必要的 CRUD 操作，不泄漏 keyring 实现细节
2. **可测试性**：提供完善的 Mock 实现，支持错误注入
3. **可观测性**：关键路径有 trace 日志
4. **零配置**：生产实现 `DefaultKeyringStore` 无参数构造，开箱即用

该 crate 本身不处理 fallback 逻辑，将策略决策留给调用方，这种设计保持了单一职责，但要求调用方理解 keyring 可能的失败场景。
