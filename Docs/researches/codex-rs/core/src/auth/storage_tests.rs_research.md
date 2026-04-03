# storage_tests.rs 研究文档

## 场景与职责

`storage_tests.rs` 是 `storage.rs` 模块的单元测试文件，使用 `#[path = "storage_tests.rs"]` 属性在 `storage.rs` 中条件编译引入（`#[cfg(test)]`）。该测试文件负责验证认证存储系统的核心功能，包括：

- 文件存储后端的正确性
- 内存存储（Ephemeral）的完整生命周期
- 密钥环存储（Keyring）的集成（使用 Mock）
- 自动存储（Auto）的回退逻辑
- 存储键生成算法的一致性

测试使用 `tempfile::tempdir()` 创建隔离的临时目录，确保测试之间不会相互影响。

## 功能点目的

### 1. File 存储测试
验证 `FileAuthStorage` 的基本操作：
- `file_storage_load_returns_auth_dot_json`：验证加载已保存的凭证
- `file_storage_save_persists_auth_dot_json`：验证保存后能通过 `try_read_auth_json` 读取
- `file_storage_delete_removes_auth_file`：验证删除操作正确移除文件

### 2. Ephemeral 存储测试
验证内存存储的隔离性和生命周期：
- `ephemeral_storage_save_load_delete_is_in_memory_only`：验证数据仅存于内存，不写入文件

### 3. Keyring 存储测试
使用 `MockKeyringStore` 验证 `KeyringAuthStorage`：
- `keyring_auth_storage_load_returns_deserialized_auth`：验证从 Keyring 加载并反序列化
- `keyring_auth_storage_compute_store_key_for_home_directory`：验证存储键生成的一致性
- `keyring_auth_storage_save_persists_and_removes_fallback_file`：验证保存时清理遗留文件
- `keyring_auth_storage_delete_removes_keyring_and_file`：验证删除操作清理 Keyring 和文件

### 4. Auto 存储测试
验证自动存储的智能回退逻辑：
- `auto_auth_storage_load_prefers_keyring_value`：Keyring 有数据时优先使用
- `auto_auth_storage_load_uses_file_when_keyring_empty`：Keyring 为空时使用文件
- `auto_auth_storage_load_falls_back_when_keyring_errors`：Keyring 出错时回退到文件
- `auto_auth_storage_save_prefers_keyring`：保存优先尝试 Keyring
- `auto_auth_storage_save_falls_back_when_keyring_errors`：Keyring 保存失败回退到文件
- `auto_auth_storage_delete_removes_keyring_and_file`：删除操作清理两者

### 5. 辅助测试工具
- `seed_keyring_and_fallback_auth_file_for_delete`：为删除测试准备 Keyring 和文件数据
- `seed_keyring_with_auth`：向 Mock Keyring 写入测试凭证
- `assert_keyring_saved_auth_and_removed_fallback`：验证 Keyring 保存成功且文件被清理
- `id_token_with_prefix`：生成伪造 JWT ID Token
- `auth_with_prefix`：生成带有前缀的测试 `AuthDotJson`

## 具体技术实现

### 测试框架与依赖

```rust
// 测试依赖
use tempfile::tempdir;  // 临时目录
use pretty_assertions::assert_eq;  // 更好的断言输出
use anyhow::Context;  // 错误处理
use base64::Engine;  // JWT 编码
use serde_json::json;  // JSON 构造

// 被测模块
use super::*;  // storage.rs 的所有导出
use codex_keyring_store::tests::MockKeyringStore;  // Mock 密钥环
use keyring::Error as KeyringError;  // 密钥环错误类型
```

### 关键测试模式

#### 临时目录隔离
```rust
let codex_home = tempdir()?;  // 创建临时目录
let storage = FileAuthStorage::new(codex_home.path().to_path_buf());
// 测试操作...
// 目录在 test 结束时自动清理
```

#### Mock Keyring 错误注入
```rust
let mock_keyring = MockKeyringStore::default();
let key = compute_store_key(codex_home.path())?;
mock_keyring.set_error(&key, KeyringError::Invalid("error".into(), "load".into()));
// 后续操作将触发错误
```

#### 伪造 JWT 生成
```rust
fn id_token_with_prefix(prefix: &str) -> IdTokenInfo {
    // 构造 JWT 三部分：header.payload.signature
    let header_b64 = encode(&serde_json::to_vec(&header)?);
    let payload_b64 = encode(&serde_json::to_vec(&json!({...}))?);
    let fake_jwt = format!("{header_b64}.{payload_b64}.{signature_b64}");
    parse_chatgpt_jwt_claims(&fake_jwt).expect("fake JWT should parse")
}
```

### 测试数据结构

```rust
// 标准测试 AuthDotJson
AuthDotJson {
    auth_mode: Some(AuthMode::ApiKey),  // 或 Chatgpt
    openai_api_key: Some("test-key".to_string()),
    tokens: Some(TokenData { ... }),  // 或 None
    last_refresh: Some(Utc::now()),  // 或 None
}

// TokenData 结构
TokenData {
    id_token: IdTokenInfo { ... },  // 解析后的 JWT 声明
    access_token: String,
    refresh_token: String,
    account_id: Option<String>,
}
```

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/core/src/auth/storage_tests.rs`（415 行）

### 被测文件
- `/home/sansha/Github/codex/codex-rs/core/src/auth/storage.rs` - 主实现

### 依赖文件
- `/home/sansha/Github/codex/codex-rs/keyring-store/src/lib.rs` - `MockKeyringStore` 定义
- `/home/sansha/Github/codex/codex-rs/core/src/token_data.rs` - `IdTokenInfo` 和 JWT 解析
- `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/common.rs` - `AuthMode` 定义

### 测试引入路径
```rust
// storage.rs 末尾
#[cfg(test)]
#[path = "storage_tests.rs"]
mod tests;
```

### 辅助函数引用关系
```
storage_tests.rs
├── seed_keyring_and_fallback_auth_file_for_delete()  // 用于删除测试准备
├── seed_keyring_with_auth()                          // 用于 Keyring 测试准备
├── assert_keyring_saved_auth_and_removed_fallback()  // 用于验证保存行为
├── id_token_with_prefix()                            // 生成测试用 JWT
└── auth_with_prefix()                                // 生成测试用 AuthDotJson
```

## 依赖与外部交互

### 测试专用依赖
| Crate | 用途 |
|-------|------|
| `tempfile` | 创建隔离的临时目录 |
| `pretty_assertions` | 提供更清晰的断言失败输出 |
| `anyhow` | 测试函数错误处理 |
| `base64` | JWT 编码 |
| `serde_json` | JSON 构造和比较 |

### Mock 系统
- `MockKeyringStore`：内存中的密钥环模拟，支持：
  - 保存/加载/删除凭证
  - 错误注入（`set_error`）
  - 状态查询（`contains`, `saved_value`）

### 测试与生产代码交互
```rust
// 测试通过 super::* 访问被测模块的 internal 项
use super::*;  // 包括 FileAuthStorage, KeyringAuthStorage 等

// 被测函数签名（internal visibility）
pub(super) fn create_auth_storage(...)  // 测试可直接调用
pub(super) fn compute_store_key(...)    // 测试可直接调用
pub(super) fn get_auth_file(...)        // 测试可直接调用
```

## 风险、边界与改进建议

### 测试覆盖分析

#### 已覆盖场景
| 场景 | 测试用例 |
|------|----------|
| File 存储基本 CRUD | 3 个测试 |
| Ephemeral 存储生命周期 | 1 个测试 |
| Keyring 存储基本操作 | 4 个测试 |
| Auto 存储回退逻辑 | 6 个测试 |
| 存储键生成一致性 | 1 个测试 |

#### 未覆盖/薄弱场景
1. **并发测试**
   - 缺少多线程并发读写测试
   - 缺少多进程文件锁测试
   - **风险**：生产环境可能出现竞态条件

2. **错误处理测试**
   - 磁盘满（ENOSPC）场景未测试
   - 权限拒绝（EACCES）场景未测试
   - 损坏的 JSON 解析错误未测试

3. **平台特定测试**
   - Windows 文件权限未测试
   - 不同密钥环后端（macOS/Windows/Linux）未区分测试

4. **边界条件**
   - 超长路径处理未测试
   - 特殊字符路径未测试
   - 空凭证数据未测试

### 测试代码质量

#### 优点
1. **良好的隔离性**：每个测试使用独立的临时目录
2. **清晰的断言**：使用 `pretty_assertions` 和 `anyhow::Context`
3. **辅助函数复用**：`auth_with_prefix` 等减少重复代码
4. **Mock 使用恰当**：避免测试依赖真实密钥环

#### 可改进点

1. **测试数据构造**
   ```rust
   // 当前：每个测试重复构造 AuthDotJson
   let auth_dot_json = AuthDotJson { ... };
   
   // 建议：使用 Builder 模式或 fixture
   let auth_dot_json = AuthDotJsonBuilder::api_key("test-key").build();
   ```

2. **测试命名一致性**
   - 部分使用 `snake_case`，部分混合描述
   - 建议统一为 `{component}_{action}_{expected_result}` 格式

3. **缺失的断言细节**
   ```rust
   // 当前：仅验证 loaded == expected
   assert_eq!(Some(auth_dot_json), loaded);
   
   // 建议：增加更多字段级断言，便于定位失败
   assert_eq!(loaded.auth_mode, expected.auth_mode);
   ```

4. **测试文档**
   - 缺少测试的 doc comment 说明测试目的
   - 建议为复杂测试添加 `// Given / When / Then` 注释

### 改进建议

1. **增加属性测试（Property Testing）**
   ```rust
   // 使用 proptest 验证存储键生成的一致性
   proptest! {
       #[test]
       fn compute_store_key_is_deterministic(path in "\\A[^\\0]+\\z") {
           let key1 = compute_store_key(Path::new(&path))?;
           let key2 = compute_store_key(Path::new(&path))?;
           assert_eq!(key1, key2);
       }
   }
   ```

2. **增加基准测试**
   - 测量不同存储后端的性能差异
   - 测量存储键计算的性能

3. **增加集成测试**
   - 测试真实密钥环（在 CI 中条件执行）
   - 测试跨进程文件锁行为

4. **改进 Mock**
   - `MockKeyringStore` 当前使用 `Mutex`，可考虑 `RwLock` 优化读多写少场景
   - 增加延迟模拟，测试超时处理

### 潜在 Bug 风险

1. **测试间状态泄漏**
   - `EPHEMERAL_AUTH_STORE` 是全局静态变量
   - 测试执行顺序可能影响结果（虽然当前测试使用不同前缀）
   - **建议**：每个测试后清理全局状态

2. **时间敏感测试**
   - `auth_with_prefix` 使用 `Utc::now()`，快速连续调用可能产生相同时间戳
   - **建议**：使用固定时间或注入 Clock trait

3. **平台假设**
   - `compute_store_key` 测试使用 `"~/.codex"` 路径
   - Windows 上 `~` 不会展开为用户目录
   - **建议**：使用 `std::env::home_dir()` 或临时路径
