# storage.rs 研究文档

## 场景与职责

`storage.rs` 是 Codex CLI 认证系统的核心存储模块，负责管理用户认证凭证（API Key、OAuth Token 等）的持久化存储。该模块提供了多种存储后端支持，以适应不同安全需求和部署环境：

- **File 模式**：将凭证存储在 `CODEX_HOME/auth.json` 文件中
- **Keyring 模式**：使用操作系统密钥环（Keyring/Keychain）存储凭证
- **Auto 模式**：优先尝试 Keyring，失败时回退到文件存储
- **Ephemeral 模式**：仅内存存储，进程结束后凭证消失

该模块是 `auth.rs` 的子模块，被 `AuthManager` 和 `ChatgptAuth` 等高层认证组件使用。

## 功能点目的

### 1. AuthCredentialsStoreMode（存储模式枚举）
定义了四种凭证存储模式，通过 `#[serde(rename_all = "lowercase")]` 支持配置文件中的小写字符串解析：
- `File`：文件存储，默认模式
- `Keyring`：系统密钥环存储
- `Auto`：自动选择（Keyring 优先，失败回退文件）
- `Ephemeral`：内存存储

### 2. AuthDotJson（凭证数据结构）
定义了 `auth.json` 文件的序列化/反序列化结构：
- `auth_mode`: 认证模式（API Key 或 ChatGPT OAuth）
- `openai_api_key`: OpenAI API 密钥
- `tokens`: OAuth Token 数据（包含 id_token、access_token、refresh_token）
- `last_refresh`: 上次刷新时间

### 3. AuthStorageBackend Trait（存储后端抽象）
定义了存储后端的统一接口：
- `load()`: 加载凭证
- `save()`: 保存凭证
- `delete()`: 删除凭证

### 4. 四种存储后端实现

#### FileAuthStorage
- 将凭证以 JSON 格式写入 `CODEX_HOME/auth.json`
- Unix 系统设置文件权限为 `0o600`（仅所有者可读写）
- 使用 `serde_json::to_string_pretty` 生成格式化 JSON

#### KeyringAuthStorage
- 使用 `codex_keyring_store` crate 与系统密钥环交互
- 通过 `compute_store_key()` 基于 `codex_home` 路径生成唯一键
- 使用 SHA-256 哈希生成 16 字符短键，格式为 `cli|{hash_prefix}`
- 保存时自动清理遗留的 `auth.json` 文件

#### AutoAuthStorage
- 组合 Keyring 和 File 两种存储
- 加载时优先尝试 Keyring，失败或为空时回退到文件
- 保存时优先尝试 Keyring，失败时回退到文件并记录警告

#### EphemeralAuthStorage
- 使用全局静态 `EPHEMERAL_AUTH_STORE`（`Lazy<Mutex<HashMap>>`）存储凭证
- 完全内存驻留，适合临时认证或测试场景
- 同样使用 `compute_store_key()` 生成键

## 具体技术实现

### 关键流程

#### 凭证加载流程
```rust
// FileAuthStorage::load
1. 获取 auth.json 文件路径
2. 尝试读取并解析 JSON
3. 文件不存在返回 Ok(None)
4. 解析错误返回 Err
```

#### 凭证保存流程（File）
```rust
// FileAuthStorage::save
1. 确保父目录存在（create_dir_all）
2. 序列化 AuthDotJson 为格式化 JSON
3. 创建/截断文件，Unix 设置 0o600 权限
4. 写入数据并 flush
```

#### Keyring 键生成算法
```rust
fn compute_store_key(codex_home: &Path) -> String {
    1. 规范化路径（canonicalize）
    2. 转为字符串
    3. SHA-256 哈希
    4. 取前 16 字符十六进制
    5. 格式化为 "cli|{hash_prefix}"
}
```

### 数据结构

```rust
// 存储模式枚举
pub enum AuthCredentialsStoreMode {
    File,
    Keyring,
    Auto,
    Ephemeral,
}

// 凭证数据结构
pub struct AuthDotJson {
    pub auth_mode: Option<AuthMode>,
    pub openai_api_key: Option<String>,
    pub tokens: Option<TokenData>,
    pub last_refresh: Option<DateTime<Utc>>,
}

// 存储后端 Trait
pub(super) trait AuthStorageBackend: Debug + Send + Sync {
    fn load(&self) -> std::io::Result<Option<AuthDotJson>>;
    fn save(&self, auth: &AuthDotJson) -> std::io::Result<()>;
    fn delete(&self) -> std::io::Result<bool>;
}
```

### 全局内存存储
```rust
static EPHEMERAL_AUTH_STORE: Lazy<Mutex<HashMap<String, AuthDotJson>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));
```

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/core/src/auth/storage.rs`（336 行）

### 相关文件
- `/home/sansha/Github/codex/codex-rs/core/src/auth/storage_tests.rs` - 单元测试
- `/home/sansha/Github/codex/codex-rs/core/src/auth.rs` - 父模块，AuthManager 实现
- `/home/sansha/Github/codex/codex-rs/core/src/token_data.rs` - TokenData 定义
- `/home/sansha/Github/codex/codex-rs/keyring-store/src/lib.rs` - KeyringStore trait 和实现
- `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/common.rs` - AuthMode 定义

### 关键函数引用路径
```
auth.rs
├── storage.rs
│   ├── AuthCredentialsStoreMode（枚举）
│   ├── AuthDotJson（结构体）
│   ├── AuthStorageBackend（trait）
│   ├── FileAuthStorage（结构体 + 实现）
│   ├── KeyringAuthStorage（结构体 + 实现）
│   ├── AutoAuthStorage（结构体 + 实现）
│   ├── EphemeralAuthStorage（结构体 + 实现）
│   ├── create_auth_storage()（工厂函数）
│   └── compute_store_key()（辅助函数）
```

## 依赖与外部交互

### 外部 Crate 依赖
| Crate | 用途 |
|-------|------|
| `chrono` | 时间戳处理（DateTime<Utc>） |
| `serde` | JSON 序列化/反序列化 |
| `schemars` | JSON Schema 生成 |
| `sha2` | SHA-256 哈希计算 |
| `tracing` | 日志记录（warn!） |
| `once_cell` | 全局静态延迟初始化（Lazy） |
| `codex_keyring_store` | 密钥环存储抽象 |
| `codex_app_server_protocol` | AuthMode 类型 |

### 操作系统交互
- **文件系统**：创建目录、读写文件、设置 Unix 权限（0o600）
- **密钥环**：通过 `keyring` crate 与 OS Keyring/Keychain 交互

### 调用方
- `auth.rs` 中的 `create_auth_storage()` 被以下函数调用：
  - `CodexAuth::from_auth_dot_json()` - 从凭证创建认证实例
  - `logout()` - 登出时清理凭证
  - `login_with_api_key()` - API Key 登录
  - `load_auth_dot_json()` - 加载凭证（测试用）
  - `AuthManager::new()` - 初始化认证管理器

## 风险、边界与改进建议

### 安全风险

1. **文件权限**
   - 当前仅在 Unix 系统设置 0o600 权限
   - Windows 系统没有等效的文件权限保护
   - **建议**：Windows 下使用 ACL 或考虑使用 DPAPI 加密

2. **密钥环失败回退**
   - Auto 模式下 Keyring 失败会静默回退到文件存储
   - 用户可能误以为凭证被安全存储
   - **建议**：增加显式警告或要求用户确认

3. **内存存储安全性**
   - Ephemeral 模式使用全局静态变量，可能被进程内其他代码访问
   - **建议**：考虑使用更安全的内存隔离机制

### 边界情况

1. **并发访问**
   - File 存储没有文件锁机制，多进程并发写入可能损坏文件
   - **建议**：增加文件锁（flock）或使用原子写入（写入临时文件后重命名）

2. **路径规范化失败**
   - `compute_store_key()` 中 `canonicalize()` 失败时使用原始路径
   - 符号链接可能导致不同路径产生相同键
   - **建议**：记录警告或统一使用绝对路径

3. **密钥环键冲突**
   - 16 字符哈希前缀存在理论上的碰撞可能
   - **建议**：使用完整哈希或增加盐值

### 改进建议

1. **加密支持**
   - 文件存储目前明文保存凭证
   - **建议**：支持可选的密码加密或系统密钥加密（如 macOS Keychain、Windows DPAPI）

2. **备份与恢复**
   - 没有凭证备份机制
   - **建议**：保存前创建备份文件，损坏时可恢复

3. **审计日志**
   - 缺少凭证访问/修改的审计记录
   - **建议**：增加结构化日志记录关键操作

4. **配置热重载**
   - 存储模式配置变更需要重启生效
   - **建议**：支持配置变更时迁移存储后端

### 测试覆盖
- 单元测试位于 `storage_tests.rs`，覆盖：
  - File 存储的加载、保存、删除
  - Ephemeral 存储的完整生命周期
  - Keyring 存储（使用 MockKeyringStore）
  - Auto 存储的回退逻辑
  - 存储键计算的一致性
