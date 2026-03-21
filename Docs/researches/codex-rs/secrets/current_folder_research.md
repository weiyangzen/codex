# codex-rs/secrets 研究文档

## 概述

`codex-secrets` 是 Codex 项目的 secrets 管理 crate，提供本地加密存储、密钥管理和敏感信息脱敏功能。它是 Codex 安全基础设施的核心组件，负责安全地存储 API 密钥、访问令牌等敏感数据。

---

## 场景与职责

### 核心职责

1. **安全存储管理**: 提供加密存储机制，使用 age 加密算法保护本地 secrets 文件
2. **密钥派生与管理**: 通过 OS 密钥环（keyring）管理加密密钥，确保密钥不落盘
3. **作用域隔离**: 支持 Global 和 Environment 两种作用域，实现 secrets 的精细化隔离
4. **敏感信息脱敏**: 提供运行时敏感信息检测与脱敏功能，防止 secrets 泄露到日志或输出

### 使用场景

| 场景 | 说明 |
|------|------|
| CLI 工具存储 API Key | 用户通过 CLI 设置 OpenAI API Key，加密存储在本地 |
| 项目级 Secrets 隔离 | 不同 Git 仓库使用独立的 environment scope 存储 secrets |
| 日志脱敏 | 在生成记忆、输出日志时自动脱敏敏感信息 |
| 安全审计 | 通过作用域过滤列出特定范围的 secrets |

---

## 功能点目的

### 1. SecretName - 强类型密钥名称

```rust
pub struct SecretName(String);
```

**设计目的**:
- 强制命名规范：仅允许大写字母、数字和下划线（如 `GITHUB_TOKEN`）
- 编译期类型安全，防止非法密钥名流入系统
- 与 shell 环境变量命名规范保持一致

### 2. SecretScope - 作用域隔离

```rust
pub enum SecretScope {
    Global,                    // 全局作用域: global/{name}
    Environment(String),       // 环境作用域: env/{environment_id}/{name}
}
```

**设计目的**:
- **Global**: 跨所有项目共享的 secrets（如用户级 API Key）
- **Environment**: 基于 Git 仓库或工作目录隔离的 secrets
- 通过 `canonical_key` 生成稳定的存储键，格式：`{scope}/{name}`

### 3. LocalSecretsBackend - 本地加密存储后端

**设计目的**:
- 完全离线，不依赖外部服务
- 使用 age 的 scrypt 方案进行密码学加密
- 密钥通过 OS 密钥环管理（macOS Keychain、Windows Credential Manager、Linux Secret Service）

### 4. SecretsManager - 统一管理层

**设计目的**:
- 提供后端无关的统一接口
- 支持可插拔的 backend 实现（当前仅 Local，预留扩展）
- 线程安全（`Arc<dyn SecretsBackend> + Send + Sync`）

### 5. redact_secrets - 敏感信息脱敏

**设计目的**:
- 防止 secrets 意外泄露到日志、记忆或网络传输
- 基于正则表达式的最佳-effort检测
- 覆盖常见密钥格式：OpenAI API Key、AWS Access Key、Bearer Token 等

---

## 具体技术实现

### 1. 存储格式与加密方案

**文件位置**: `{codex_home}/secrets/local.age`

**加密方案**:
```rust
// 使用 age 库的 scrypt 方案
let recipient = ScryptRecipient::new(passphrase);
encrypt(&recipient, plaintext)
```

**文件格式** (解密后):
```json
{
  "version": 1,
  "secrets": {
    "global/OPENAI_API_KEY": "sk-...",
    "env/my-project/GITHUB_TOKEN": "ghp_..."
  }
}
```

### 2. 密钥派生流程

```
┌─────────────────┐
│   codex_home    │──┐
│  (e.g. ~/.codex)│  │
└─────────────────┘  │  SHA256
                     ├────────►  secrets|{hash_16}  ──────►  OS Keyring
                     │                                      (service="codex")
┌─────────────────┐  │
│   "secrets|"    │──┘
│   (prefix)      │
└─────────────────┘
```

**代码路径**: `lib.rs:180-192`
```rust
pub(crate) fn compute_keyring_account(codex_home: &Path) -> String {
    let canonical = codex_home.canonicalize().unwrap_or_else(|_| codex_home.to_path_buf());
    let mut hasher = Sha256::new();
    hasher.update(canonical.as_bytes());
    let digest = hasher.finalize();
    let hex = format!("{digest:x}");
    let short = hex.get(..16).unwrap_or(hex.as_str());
    format!("secrets|{short}")
}
```

### 3. 原子写入机制

**目的**: 防止写入过程中断导致文件损坏

**实现** (`local.rs:201-271`):
```rust
fn write_file_atomically(path: &Path, contents: &[u8]) -> Result<()> {
    // 1. 创建临时文件 (exclusive create)
    let tmp_path = dir.join(format!(".{LOCAL_SECRETS_FILENAME}.tmp-{pid}-{nonce}"));
    
    // 2. 写入并强制 sync
    tmp_file.write_all(contents)?;
    tmp_file.sync_all()?;
    
    // 3. 原子重命名
    fs::rename(&tmp_path, path)?;
    
    // Windows 特殊处理: 如果目标存在，先删除再重命名
}
```

### 4. Environment ID 生成

**代码路径**: `lib.rs:141-162`

```rust
pub fn environment_id_from_cwd(cwd: &Path) -> String {
    // 策略1: 使用 Git 仓库名
    if let Some(repo_root) = get_git_repo_root(cwd)
        && let Some(name) = repo_root.file_name() {
        return name.to_string_lossy().trim().to_string();
    }
    
    // 策略2: 使用工作目录路径哈希
    let canonical = cwd.canonicalize().unwrap_or_else(|_| cwd.to_path_buf());
    let mut hasher = Sha256::new();
    hasher.update(canonical.as_bytes());
    let digest = hasher.finalize();
    let short = hex.get(..12).unwrap_or(hex.as_str());
    format!("cwd-{short}")
}
```

### 5. 脱敏正则表达式

**代码路径**: `sanitizer.rs:4-11`

| 正则 | 匹配内容 | 替换结果 |
|------|----------|----------|
| `sk-[A-Za-z0-9]{20,}` | OpenAI API Key | `[REDACTED_SECRET]` |
| `\bAKIA[0-9A-Z]{16}\b` | AWS Access Key ID | `[REDACTED_SECRET]` |
| `(?i)\bBearer\s+[A-Za-z0-9._\-]{16,}\b` | Bearer Token | `Bearer [REDACTED_SECRET]` |
| `(?i)\b(api[_-]?key\|token\|secret\|password)\b(\s*[:=]\s*)(["']?)[^\s"']{8,}` | 赋值语句 | `$1$2$3[REDACTED_SECRET]` |

### 6. 内存安全处理

**密钥擦除** (`local.rs:284-291`):
```rust
fn wipe_bytes(bytes: &mut [u8]) {
    for byte in bytes {
        // 使用 volatile write 防止编译器优化掉擦除操作
        unsafe { std::ptr::write_volatile(byte, 0) };
    }
    compiler_fence(Ordering::SeqCst);
}
```

---

## 关键代码路径与文件引用

### 文件结构

```
codex-rs/secrets/
├── Cargo.toml           # 依赖: age, keyring, regex, sha2, etc.
├── BUILD.bazel          # Bazel 构建配置
└── src/
    ├── lib.rs           # 公共 API: SecretsManager, SecretName, SecretScope
    ├── local.rs         # LocalSecretsBackend 实现
    └── sanitizer.rs     # redact_secrets 脱敏实现
```

### 关键类型与方法

| 类型/方法 | 文件 | 行号 | 说明 |
|-----------|------|------|------|
| `SecretName` | lib.rs | 23-48 | 强类型密钥名，强制大写+下划线规范 |
| `SecretScope` | lib.rs | 50-73 | 作用域枚举，支持 Global/Environment |
| `SecretsBackend` trait | lib.rs | 88-93 | 后端抽象接口 |
| `SecretsManager` | lib.rs | 95-139 | 统一管理器，线程安全 |
| `environment_id_from_cwd` | lib.rs | 141-162 | 基于 CWD 生成环境 ID |
| `compute_keyring_account` | lib.rs | 180-192 | 派生 keyring 账户名 |
| `LocalSecretsBackend` | local.rs | 54-199 | 本地加密存储实现 |
| `write_file_atomically` | local.rs | 201-271 | 原子文件写入 |
| `generate_passphrase` | local.rs | 273-282 | 生成 32 字节随机密钥 |
| `wipe_bytes` | local.rs | 284-291 | 安全擦除内存 |
| `encrypt/decrypt_with_passphrase` | local.rs | 293-301 | age 加密/解密 |
| `redact_secrets` | sanitizer.rs | 15-22 | 敏感信息脱敏 |

### 调用方引用

| 调用方 | 用途 |
|--------|------|
| `codex-core/src/memories/phase1.rs:26` | `use codex_secrets::redact_secrets` |
| `codex-core/src/memories/phase1.rs:385-387` | 记忆生成时脱敏 raw_memory, rollout_summary, rollout_slug |
| `codex-core/Cargo.toml:57` | 依赖 `codex-secrets` |

### 被调用方（依赖）

| 依赖 | 用途 |
|------|------|
| `codex-keyring-store` | OS 密钥环抽象，存储加密密钥 |
| `age` | 现代加密库，提供文件加密 |
| `sha2` | SHA256 哈希，用于派生 keyring 账户名 |
| `regex` | 脱敏正则匹配 |
| `rand` | 生成高熵随机密钥 |
| `serde/json` | secrets 文件序列化 |

---

## 依赖与外部交互

### 内部依赖

```
codex-secrets
├── codex-keyring-store (workspace)
│   ├── keyring crate (OS keyring bindings)
│   └── 支持 MockKeyringStore (测试)
```

### 外部依赖

| Crate | 版本 | 用途 |
|-------|------|------|
| `age` | 0.11.1 | 现代加密，scrypt 密钥派生 |
| `keyring` | 3.6 | OS 密钥环访问 |
| `regex` | 1.12.3 | 脱敏正则 |
| `sha2` | 0.10 | SHA256 哈希 |
| `rand` | 0.9 | 安全随机数生成 |
| `base64` | 0.22.1 | 密钥编码 |
| `schemars` | 0.8.22 | JSON Schema 生成 |
| `serde` | 1 | 序列化 |

### OS 密钥环集成

| 平台 | 后端 | 说明 |
|------|------|------|
| macOS | Keychain | `apple-native` feature |
| Windows | Credential Manager | `windows-native` feature |
| Linux | Secret Service | `linux-native-async-persistent` feature |
| FreeBSD/OpenBSD | Secret Service | `sync-secret-service` feature |

---

## 风险、边界与改进建议

### 当前风险

1. **密钥丢失风险**
   - 如果 OS 密钥环中的密钥被删除，所有 secrets 将永久无法解密
   - 没有密钥备份或恢复机制

2. **正则脱敏局限**
   - 基于正则的脱敏是 best-effort，可能漏检新型密钥格式
   - 高熵字符串可能被误报或漏报

3. **单点故障**
   - 所有 secrets 存储在单个加密文件中
   - 文件损坏导致全部 secrets 丢失

4. **并发访问**
   - 当前实现没有文件级锁
   - 多进程并发写入可能导致数据丢失

### 边界条件

| 边界 | 行为 |
|------|------|
| 空密钥名 | `SecretName::new("")` 返回 Err |
| 非法字符 | 包含小写字母返回 Err |
| 空密钥值 | `set()` 返回 Err |
| 密钥不存在 | `get()` 返回 `Ok(None)` |
| 文件版本不兼容 | `load_file()` 返回 Err |
| keyring 不可用 | 操作返回 Err，提示用户 |

### 改进建议

1. **备份与恢复**
   - 提供密钥导出/导入功能（如 QR 码、助记词）
   - 支持云备份（可选，加密后上传）

2. **增强脱敏**
   - 引入 ML 模型检测敏感信息
   - 支持用户自定义脱敏规则

3. **并发安全**
   - 添加文件级锁（如 `fs2::FileExt::lock`）
   - 考虑使用 SQLite 替代 JSON 文件

4. **审计日志**
   - 记录 secrets 访问日志（只记录访问行为，不记录值）
   - 支持 SIEM 集成

5. **扩展后端**
   - 实现 `CloudSecretsBackend`（如 AWS Secrets Manager、Azure Key Vault）
   - 支持团队级 secrets 共享

6. **密钥轮换**
   - 支持加密密钥自动轮换
   - 旧密钥解密后使用新密钥重新加密

---

## 测试覆盖

| 测试文件 | 测试内容 |
|----------|----------|
| `lib.rs:199-245` | manager_round_trips_local_backend, environment_id_fallback_has_cwd_prefix |
| `local.rs:332-410` | load_file_rejects_newer_schema_versions, set_fails_when_keyring_is_unavailable, save_file_does_not_leave_temp_files |
| `sanitizer.rs:32-40` | load_regex (编译期正则验证) |

---

## 相关文档

- `codex-rs/keyring-store/src/lib.rs`: 密钥环存储抽象
- `codex-rs/core/src/memories/phase1.rs`: 脱敏调用方
- `codex-rs/core/src/memories/README.md`: 记忆系统文档

---

*研究日期: 2026-03-21*
*版本: 基于 codex-rs/secrets 当前 main 分支*
