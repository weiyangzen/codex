# codex-rs/secrets/src/local.rs 研究文档

## 场景与职责

`local.rs` 实现了 `codex-secrets` crate 的本地机密后端（`LocalSecretsBackend`）。该后端将机密数据以加密形式存储在本地文件系统中，使用操作系统密钥环（keyring）管理加密密钥，实现了安全与便利的平衡。

主要使用场景：
1. **本地开发环境**：开发者需要在本地安全存储 API 密钥、访问令牌等敏感信息
2. **离线工作**：无需网络连接即可访问存储的机密
3. **多项目隔离**：通过 `codex_home` 和作用域实现不同项目间的机密隔离
4. **隐私优先**：所有数据本地存储，不上传到任何云服务

## 功能点目的

### 1. LocalSecretsBackend - 本地机密后端
- **目的**：提供基于本地加密文件的机密存储实现
- **核心特性**：
  - 使用 AGE 加密库进行强加密
  - 通过操作系统密钥环管理加密密钥
  - 原子文件写入防止数据损坏
  - 版本化的文件格式支持未来扩展

### 2. SecretsFile - 机密文件格式
- **目的**：定义磁盘上的机密数据存储结构
- **结构**：
  ```rust
  struct SecretsFile {
      version: u8,                    // 文件格式版本（当前为 1）
      secrets: BTreeMap<String, String>, // canonical_key → value 映射
  }
  ```
- **设计选择**：
  - 使用 `BTreeMap` 保证键的有序性（便于调试和版本控制）
  - JSON 序列化保证可读性和跨平台兼容性

### 3. 原子文件写入
- **目的**：防止写入过程中断导致的数据损坏
- **实现策略**：
  1. 创建临时文件（`.local.age.tmp-{pid}-{nonce}`）
  2. 写入并同步（`sync_all`）数据到磁盘
  3. 原子重命名到目标文件
  4. Windows 特殊处理：目标文件存在时需要先删除

### 4. 加密密钥管理
- **目的**：安全地生成、存储和获取加密密钥
- **策略**：
  - 密钥存储在操作系统密钥环中（服务名：`codex`）
  - 账户名基于 `codex_home` 路径哈希（`secrets|{hash}`）
  - 首次使用时自动生成 32 字节随机密钥（Base64 编码）
  - 使用 `SecretString` 类型防止密钥在内存中意外暴露

### 5. 内存安全擦除
- **目的**：防止加密密钥在内存中残留
- **实现**：
  - `wipe_bytes` 函数使用 `ptr::write_volatile` 进行内存擦除
  - `compiler_fence(Ordering::SeqCst)` 防止编译器优化掉擦除操作
  - 在密钥生成后立即擦除临时缓冲区

### 6. 版本兼容性
- **目的**：支持文件格式的向前兼容和向后兼容
- **策略**：
  - 写入时始终使用当前版本（`SECRETS_VERSION = 1`）
  - 读取时接受版本 0（迁移旧数据）
  - 拒绝高于当前版本的文件（防止数据损坏）

## 具体技术实现

### 关键数据结构

```rust
// 机密文件结构（序列化为 JSON 后加密存储）
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
struct SecretsFile {
    version: u8,
    secrets: BTreeMap<String, String>,
}

// 本地后端结构
#[derive(Debug, Clone)]
pub struct LocalSecretsBackend {
    codex_home: PathBuf,                    // 配置目录根路径
    keyring_store: Arc<dyn KeyringStore>,   // 密钥环存储抽象
}
```

### 关键流程

#### 1. 机密存储流程（set）
```
set(scope, name, value)
  ├── 验证 value 非空
  ├── 生成 canonical_key: scope.canonical_key(name)
  ├── load_file() ───────────────────────────────┐
  │   ├── 检查文件是否存在                        │
  │   ├── 读取加密文件内容                        │
  │   ├── load_or_create_passphrase()             │
  │   │   ├── 计算 keyring 账户名                 │
  │   │   ├── 尝试从 keyring 加载                 │
  │   │   └── 不存在则生成新密钥并保存            │
  │   ├── decrypt_with_passphrase()               │
  │   └── serde_json::from_slice()                │
  ├── 插入/更新 secrets[canonical_key] = value   │
  └── save_file(file) ───────────────────────────┘
      ├── 序列化为 JSON
      ├── encrypt_with_passphrase()
      └── write_file_atomically()
```

#### 2. 机密读取流程（get）
```
get(scope, name)
  ├── 生成 canonical_key
  ├── load_file() [同上]
  └── 从 BTreeMap 获取值
```

#### 3. 原子文件写入流程
```
write_file_atomically(path, contents)
  ├── 生成临时文件路径: .local.age.tmp-{pid}-{nonce}
  ├── 创建新文件（O_CREATE | O_EXCL）
  ├── 写入内容
  ├── sync_all() 确保落盘
  ├── rename(tmp_path, target_path)
  │   └── Windows 特殊处理：
  │       ├── 如果目标存在，先删除
  │       └── 再次尝试 rename
  └── 失败时清理临时文件
```

#### 4. 加密流程（AGE）
```
encrypt_with_passphrase(plaintext, passphrase)
  ├── 创建 ScryptRecipient（基于 passphrase）
  └── age::encrypt(&recipient, plaintext)
      └── 使用 scrypt 密钥派生 + ChaCha20-Poly1305

decrypt_with_passphrase(ciphertext, passphrase)
  ├── 创建 ScryptIdentity（基于 passphrase）
  └── age::decrypt(&identity, ciphertext)
```

#### 5. 密钥生成流程
```
generate_passphrase()
  ├── OsRng.try_fill_bytes(&mut [0u8; 32])
  ├── BASE64_STANDARD.encode(bytes)
  ├── wipe_bytes(&mut bytes)  // 安全擦除
  └── SecretString::from(encoded)
```

### 文件路径结构

```
{codex_home}/
└── secrets/
    └── local.age          # 加密的机密文件
```

临时文件命名：`.local.age.tmp-{pid}-{nonce}`
- `pid`：进程 ID
- `nonce`：纳秒级时间戳

## 关键代码路径与文件引用

### 核心方法
| 方法 | 位置 | 说明 |
|------|------|------|
| `LocalSecretsBackend::new` | `local.rs:61-66` | 后端实例化 |
| `set` | `local.rs:68-74` | 存储机密 |
| `get` | `local.rs:76-80` | 读取机密 |
| `delete` | `local.rs:82-90` | 删除机密 |
| `list` | `local.rs:92-108` | 列出机密 |
| `load_file` | `local.rs:118-144` | 加载并解密文件 |
| `save_file` | `local.rs:146-157` | 加密并保存文件 |
| `load_or_create_passphrase` | `local.rs:159-180` | 密钥管理 |

### 工具函数
| 函数 | 位置 | 说明 |
|------|------|------|
| `write_file_atomically` | `local.rs:201-271` | 原子文件写入 |
| `generate_passphrase` | `local.rs:273-282` | 随机密钥生成 |
| `wipe_bytes` | `local.rs:284-291` | 安全内存擦除 |
| `encrypt_with_passphrase` | `local.rs:293-296` | AGE 加密 |
| `decrypt_with_passphrase` | `local.rs:298-301` | AGE 解密 |
| `parse_canonical_key` | `local.rs:303-330` | 解析 canonical_key |

### 常量定义
| 常量 | 位置 | 值 | 说明 |
|------|------|-----|------|
| `SECRETS_VERSION` | `local.rs:36` | `1` | 文件格式版本 |
| `LOCAL_SECRETS_FILENAME` | `local.rs:37` | `"local.age"` | 机密文件名 |

## 依赖与外部交互

### 内部依赖
| 模块/Crate | 用途 |
|------------|------|
| `super::{SecretListEntry, SecretName, SecretScope}` | 核心类型定义 |
| `super::{compute_keyring_account, keyring_service}` | 密钥环辅助函数 |
| `codex_keyring_store::KeyringStore` | 密钥环存储抽象 |

### 外部 Crate 依赖
| Crate | 用途 |
|-------|------|
| `age` | AGE 加密库（文件加密/解密） |
| `anyhow` | 错误处理 |
| `base64` | Base64 编码（密钥存储） |
| `rand` | 密码学安全随机数生成 |
| `serde`/`serde_json` | JSON 序列化 |
| `tracing` | 日志记录（warn） |

### AGE 加密详解

使用的 `age` crate 特性：
- **`age::scrypt::ScryptRecipient/Identity`**：基于密码的加密
  - 使用 scrypt 进行密钥派生（抗 GPU/ASIC 破解）
  - 使用 ChaCha20-Poly1305 进行 AEAD 加密
- **`age::secrecy::SecretString`**：防止密钥在日志/调试中意外泄露

### 操作系统密钥环交互

通过 `KeyringStore` trait：
```rust
// 服务名固定为 "codex"
const KEYRING_SERVICE: &str = "codex";

// 账户名基于 codex_home 路径哈希
account = format!("secrets|{}", &hash[..16]);

// 存储值：32 字节随机数的 Base64 编码
value = BASE64_STANDARD.encode(random_bytes);
```

## 风险、边界与改进建议

### 风险点

1. **密钥环不可用**
   - 在无头服务器、Docker 容器或 CI 环境中，操作系统密钥环可能不可用
   - **当前影响**：首次初始化会失败，无法创建加密密钥
   - **缓解**：测试中使用 `MockKeyringStore`，生产环境需确保密钥环可用

2. **文件损坏风险**
   - 虽然使用了原子写入，但极端情况下（系统崩溃、磁盘满）仍可能损坏
   - **当前处理**：版本检查拒绝无法解析的文件
   - **建议**：添加文件备份/恢复机制

3. **并发写入冲突**
   - 多个进程同时写入同一文件可能导致数据丢失
   - **当前状态**：未实现文件级锁定
   - **风险等级**：中等（Codex 通常为单实例运行）

4. **内存中的明文机密**
   - 机密值在 `SecretsFile.secrets` 中以 `String` 形式存储
   - 虽然加密密钥有安全擦除，但机密值本身没有
   - **缓解**：依赖 Rust 的内存安全，进程结束后由 OS 回收

5. **Scrypt 性能**
   - AGE 的 scrypt 模式在每次加解密时都会进行密钥派生
   - 大量机密操作时可能成为性能瓶颈
   - **缓解**：机密文件通常较小，操作频率低

### 边界条件

1. **空值处理**
   - `set` 方法明确拒绝空字符串值（`anyhow::ensure!(!value.is_empty())`）
   - 空值可能表示删除意图，但 API 要求使用 `delete` 方法

2. **文件不存在**
   - `load_file` 在文件不存在时返回空 `SecretsFile`（版本 1，空映射）
   - 这是正常的新用户初始化路径

3. **版本兼容性**
   - 版本 0 被接受并自动升级到版本 1
   - 版本 > 1 被拒绝并返回错误

4. **Windows 原子写入**
   - Windows 不支持原子覆盖重命名
   - 特殊处理：先删除目标文件，再重命名
   - 极端情况下可能丢失数据（删除后、重命名前崩溃）

### 改进建议

1. **并发安全**
   - 添加文件级锁定（如 `fs2::FileLock`）防止多进程并发写入
   - 或使用 SQLite 等支持并发的存储后端

2. **备份机制**
   - 写入前创建备份文件
   - 检测到损坏时自动从备份恢复
   - 保留最近 N 个版本的备份

3. **密钥环降级**
   - 支持环境变量或配置文件指定的主密码
   - 在密钥环不可用时作为回退

4. **内存安全增强**
   - 使用 `secrecy::SecretString` 存储机密值
   - 实现 `Zeroize` trait 确保内存安全擦除

5. **性能优化**
   - 考虑缓存解密后的 `SecretsFile` 避免重复解密
   - 添加批量操作 API 减少文件 I/O

6. **审计日志**
   - 记录机密访问日志（读取/写入/删除）
   - 支持可选的详细日志模式

7. **导入/导出**
   - 添加明文导入/导出功能（用于备份和迁移）
   - 支持其他格式（如 `.env` 文件）

### 测试覆盖

当前测试：
- `load_file_rejects_newer_schema_versions`：版本兼容性
- `set_fails_when_keyring_is_unavailable`：密钥环错误处理
- `save_file_does_not_leave_temp_files`：原子写入清理

建议补充：
- 并发写入测试
- 大文件性能测试
- 密钥环模拟的边界情况
- 文件损坏恢复测试
