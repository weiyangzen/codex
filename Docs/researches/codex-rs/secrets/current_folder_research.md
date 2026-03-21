# codex-rs/secrets 研究文档

## 概述

`codex-rs/secrets` 是 Codex 项目的本地机密管理模块，负责安全地存储、检索和管理用户机密（如 API 密钥、访问令牌等）。该模块采用分层架构设计，支持基于作用域的机密隔离，并使用 age 加密算法对存储的机密进行加密保护。

---

## 场景与职责

### 核心职责

1. **机密存储管理**：提供安全的本地机密存储机制，支持增删改查操作
2. **作用域隔离**：支持全局作用域和基于环境的作用域，实现机密的多租户隔离
3. **加密保护**：使用 age 加密算法和 scrypt 密钥派生，确保机密数据在静态存储时的安全性
4. **密钥管理**：通过 OS Keyring（系统钥匙串）安全存储加密密钥，避免密钥泄露
5. **敏感信息脱敏**：提供基于正则表达式的敏感信息检测和脱敏功能

### 使用场景

- **用户 API 密钥存储**：存储 OpenAI API Key、AWS Access Key 等第三方服务凭证
- **项目级机密隔离**：不同 Git 仓库/项目使用独立的机密空间
- **日志和内存脱敏**：在日志记录和 AI 记忆生成时自动脱敏敏感信息
- **CI/CD 环境**：在自动化流程中安全地注入和使用机密

---

## 功能点目的

### 1. SecretName - 机密名称规范

**目的**：确保机密名称符合安全规范，避免注入攻击和命名冲突。

**约束规则**：
- 只能包含大写字母 (A-Z)、数字 (0-9) 和下划线 (_)
- 不能为空字符串
- 自动去除首尾空白字符

**设计理由**：
- 使用大写字母和下划线符合环境变量命名惯例（如 `GITHUB_TOKEN`）
- 严格的字符集限制防止路径遍历和注入攻击
- 规范化处理确保名称的一致性

### 2. SecretScope - 机密作用域

**目的**：实现机密的多级隔离，支持全局共享和项目级隔离两种模式。

**作用域类型**：

| 类型 | 说明 | 键格式 |
|------|------|--------|
| `Global` | 全局作用域，所有项目共享 | `global/{name}` |
| `Environment(String)` | 环境特定作用域，基于项目/环境隔离 | `env/{environment_id}/{name}` |

**环境 ID 生成策略**：
1. 优先使用 Git 仓库根目录名称（如 `my-project`）
2. 非 Git 目录使用当前工作目录路径的 SHA256 哈希前 12 位（格式：`cwd-{hash}`）

### 3. LocalSecretsBackend - 本地机密后端

**目的**：提供基于文件系统的本地机密存储实现，支持加密和原子写入。

**核心特性**：
- **加密存储**：使用 age 库进行基于口令的加密
- **原子写入**：通过临时文件 + 重命名实现原子性写入，防止数据损坏
- **版本控制**：支持文件格式版本升级（当前版本：1）
- **跨平台兼容**：处理 Windows 平台的文件替换特殊逻辑

### 4. SecretsManager - 机密管理器

**目的**：作为统一的入口点，封装后端实现细节，提供类型安全的 API。

**设计模式**：
- 使用 `Arc<dyn SecretsBackend>` 实现后端可替换性
- 支持依赖注入（`new_with_keyring_store`）便于测试
- 当前仅支持 `Local` 后端，预留扩展接口

### 5. redact_secrets - 敏感信息脱敏

**目的**：在日志、AI 记忆等输出中自动检测并脱敏敏感信息，防止机密泄露。

**检测规则**：

| 正则表达式 | 匹配内容 | 脱敏结果 |
|-----------|---------|---------|
| `sk-[A-Za-z0-9]{20,}` | OpenAI API Key | `[REDACTED_SECRET]` |
| `\bAKIA[0-9A-Z]{16}\b` | AWS Access Key ID | `[REDACTED_SECRET]` |
| `(?i)\bBearer\s+[A-Za-z0-9._\-]{16,}\b` | Bearer Token | `Bearer [REDACTED_SECRET]` |
| `(?i)\b(api[_-]?key\|token\|secret\|password)\b(\s*[:=]\s*)(["']?)[^\s"']{8,}` | 通用密钥赋值 | 保留键名，脱敏值 |

---

## 具体技术实现

### 关键数据结构

```rust
// 机密名称（规范化包装类型）
pub struct SecretName(String);

// 机密作用域
pub enum SecretScope {
    Global,
    Environment(String),
}

// 机密列表条目
pub struct SecretListEntry {
    pub scope: SecretScope,
    pub name: SecretName,
}

// 后端类型枚举（预留扩展）
pub enum SecretsBackendKind {
    Local,
}

// 机密后端 trait（可扩展）
pub trait SecretsBackend: Send + Sync {
    fn set(&self, scope: &SecretScope, name: &SecretName, value: &str) -> Result<()>;
    fn get(&self, scope: &SecretScope, name: &SecretName) -> Result<Option<String>>;
    fn delete(&self, scope: &SecretScope, name: &SecretName) -> Result<bool>;
    fn list(&self, scope_filter: Option<&SecretScope>) -> Result<Vec<SecretListEntry>>;
}

// 管理器（统一入口）
pub struct SecretsManager {
    backend: Arc<dyn SecretsBackend>,
}

// 本地后端实现
pub struct LocalSecretsBackend {
    codex_home: PathBuf,
    keyring_store: Arc<dyn KeyringStore>,
}

// 机密文件格式（序列化结构）
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
struct SecretsFile {
    version: u8,
    secrets: BTreeMap<String, String>,
}
```

### 关键流程

#### 1. 机密存储流程

```
用户调用 set(scope, name, value)
    ↓
验证 value 非空
    ↓
生成 canonical_key（如 "env/my-project/GITHUB_TOKEN"）
    ↓
加载现有 SecretsFile（解密）
    ↓
插入/更新键值对
    ↓
序列化并加密
    ↓
原子写入文件（临时文件 → 重命名）
```

#### 2. 密钥派生流程

```
需要加密/解密时
    ↓
计算 keyring_account（基于 codex_home 路径的 SHA256 哈希）
    ↓
查询 OS Keyring（service="codex", account="secrets|{hash}"）
    ↓
如果存在 → 返回现有密钥
如果不存在 → 生成 32 字节随机密钥 → Base64 编码 → 存入 Keyring
    ↓
使用密钥通过 age/scrypt 进行加密/解密
```

#### 3. 文件原子写入流程

```
写入内容
    ↓
生成临时文件路径：.{filename}.tmp-{pid}-{timestamp}
    ↓
创建新文件（O_CREATE | O_EXCL）
    ↓
写入内容
    ↓
调用 sync_all() 确保数据落盘
    ↓
重命名临时文件到目标路径
    ↓
Windows 特殊处理：如果目标存在，先删除再重命名
    ↓
清理临时文件（失败时）
```

#### 4. 敏感信息脱敏流程

```
输入文本
    ↓
顺序应用多个正则表达式替换：
  1. OpenAI Key 模式 → [REDACTED_SECRET]
  2. AWS Key 模式 → [REDACTED_SECRET]
  3. Bearer Token 模式 → Bearer [REDACTED_SECRET]
  4. 通用密钥赋值模式 → 保留键名和分隔符，脱敏值
    ↓
返回脱敏后的文本
```

### 加密实现细节

**使用的加密库**：`age` crate（版本 0.11.1）

**加密方案**：
- **算法**：age 格式（基于 X25519 + ChaCha20-Poly1305）
- **密钥派生**：scrypt（内存困难型 KDF，抵抗硬件暴力破解）
- **密钥来源**：32 字节随机数，Base64 编码后存储于 OS Keyring

**文件格式**：
- 存储路径：`{codex_home}/secrets/local.age`
- 文件内容：加密后的 JSON（SecretsFile 结构）
- 明文结构：`{"version": 1, "secrets": {"key": "value", ...}}`

### 安全考虑

1. **内存安全**：
   - 使用 `age::secrecy::SecretString` 包装敏感字符串
   - 生成密钥后使用 `wipe_bytes()` 清零临时缓冲区
   - 使用 `compiler_fence(Ordering::SeqCst)` 防止编译器优化掉清零操作

2. **存储安全**：
   - 加密密钥与数据分离（密钥在 Keyring，数据在文件）
   - 原子写入防止数据损坏
   - 文件权限由操作系统保证（建议设置 umask）

3. **传输安全**：
   - 脱敏功能防止机密通过日志/AI 响应泄露

---

## 关键代码路径与文件引用

### 文件结构

```
codex-rs/secrets/
├── Cargo.toml              # 包配置和依赖
├── BUILD.bazel             # Bazel 构建配置
└── src/
    ├── lib.rs              # 公共 API（SecretsManager、SecretName、SecretScope）
    ├── local.rs            # LocalSecretsBackend 实现
    └── sanitizer.rs        # 敏感信息脱敏功能
```

### 关键代码路径

| 功能 | 文件 | 行号范围 |
|------|------|---------|
| SecretName 验证 | `src/lib.rs` | 24-48 |
| SecretScope 定义 | `src/lib.rs` | 50-73 |
| SecretsBackend trait | `src/lib.rs` | 88-93 |
| SecretsManager 实现 | `src/lib.rs` | 96-139 |
| 环境 ID 生成 | `src/lib.rs` | 141-162 |
| Keyring 账户计算 | `src/lib.rs` | 180-192 |
| LocalSecretsBackend 结构 | `src/local.rs` | 54-58 |
| set/get/delete/list 实现 | `src/local.rs` | 68-108 |
| 文件加载/保存 | `src/local.rs` | 118-157 |
| 密钥派生 | `src/local.rs` | 159-181 |
| 原子写入 | `src/local.rs` | 201-271 |
| 加密/解密 | `src/local.rs` | 293-301 |
| 正则脱敏规则 | `src/sanitizer.rs` | 4-11 |
| redact_secrets 函数 | `src/sanitizer.rs` | 15-22 |

### 外部调用点

**被调用方**（使用 secrets 的代码）：

| 调用方 | 用途 |
|--------|------|
| `codex-rs/core/src/memories/phase1.rs` | AI 记忆生成时脱敏敏感信息（`redact_secrets`） |

**注意**：当前 `SecretsManager` 和 `SecretsBackend` 主要在模块内部使用，尚未发现外部直接调用的代码。这可能是预留的扩展接口，用于未来实现 CLI 机密管理命令或配置中的机密引用功能。

---

## 依赖与外部交互

### 内部依赖

| 依赖包 | 用途 |
|--------|------|
| `codex-keyring-store` | OS Keyring 抽象接口（`KeyringStore`、`DefaultKeyringStore`、`MockKeyringStore`） |

### 外部依赖

| 依赖 | 版本 | 用途 |
|------|------|------|
| `age` | 0.11.1 | 现代加密文件格式，用于机密文件加密 |
| `anyhow` | 1.x | 错误处理和传播 |
| `base64` | 0.22.1 | 密钥的 Base64 编码 |
| `rand` | 0.9 | 生成高熵随机密钥 |
| `regex` | 1.12.3 | 敏感信息检测模式 |
| `schemars` | 0.8.22 | JSON Schema 生成 |
| `serde` | 1.x | 机密文件序列化 |
| `serde_json` | 1.x | JSON 格式处理 |
| `sha2` | 0.10 | 路径哈希计算 |
| `tracing` | 0.1.44 | 日志追踪 |

### OS Keyring 交互

通过 `codex-keyring-store` 抽象层与系统钥匙串交互：

- **macOS**：Keychain Services（`apple-native` feature）
- **Linux**：Secret Service API（`linux-native-async-persistent` feature）
- **Windows**：Windows Credential Manager（`windows-native` feature）
- **FreeBSD/OpenBSD**：同步 Secret Service（`sync-secret-service` feature）

**Keyring 条目结构**：
- Service: `"codex"`
- Account: `"secrets|{hash}"`（基于 codex_home 路径的 SHA256 前 16 位）
- Value: Base64 编码的 32 字节随机密钥

---

## 风险、边界与改进建议

### 已知风险

1. **密钥丢失风险**：
   - 如果 OS Keyring 中的密钥被删除，所有已存储的机密将无法解密
   - 没有密钥备份/恢复机制

2. **正则脱敏局限**：
   - 基于正则的脱敏是启发式的，可能漏检或误报
   - 新型机密格式（如新版本的 API Key）可能无法识别

3. **并发访问**：
   - 当前实现没有文件级锁，多进程并发写入可能导致数据丢失
   - 依赖原子写入的 last-write-wins 语义

4. **内存泄露**：
   - 尽管有清零措施，但 Rust 的内存模型无法保证绝对安全
   - SecretString 的底层实现可能存在内存复制

### 边界条件

1. **空值处理**：
   - 机密值不能为空字符串（`set` 会返回错误）
   - 机密名称不能为空或仅包含空白字符

2. **文件版本**：
   - 支持的最大版本号为 1
   - 遇到更高版本会返回错误（向前兼容性保护）

3. **路径长度**：
   - 临时文件名包含 PID 和时间戳，在极端路径长度下可能失败

4. **Keyring 限制**：
   - 某些 CI 环境或容器可能没有可用的 Keyring 服务
   - 测试环境使用 `MockKeyringStore` 模拟

### 改进建议

1. **功能扩展**：
   - 实现 CLI 命令（`codex secrets set/get/list/delete`）
   - 支持机密引用语法（如 `${secrets.GITHUB_TOKEN}`）
   - 添加机密过期和轮换机制

2. **安全增强**：
   - 添加密钥备份/恢复功能（如助记词）
   - 实现文件级锁，支持多进程安全访问
   - 定期密钥轮换机制

3. **可观测性**：
   - 添加审计日志（机密访问记录）
   - 脱敏统计（检测到的敏感信息数量）

4. **性能优化**：
   - 缓存解密后的 SecretsFile，减少重复解密
   - 延迟加载（首次访问时才初始化）

5. **测试覆盖**：
   - 添加并发写入测试
   - 添加故障恢复测试（损坏文件、Keyring 不可用等场景）
   - 跨平台测试（特别是 Windows 原子写入逻辑）

6. **文档完善**：
   - 添加架构决策记录（ADR）
   - 编写用户-facing 的机密管理指南
   - 记录威胁模型和安全假设

---

## 附录：配置示例

### 机密文件位置

```
~/.codex/
└── secrets/
    └── local.age          # 加密的机密存储文件
```

### Keyring 条目示例

```
Service: codex
Account: secrets|a1b2c3d4e5f67890
Value:   base64_encoded_random_key_32_bytes...
```

### 使用示例（假设的 CLI）

```bash
# 设置全局机密
codex secrets set GITHUB_TOKEN ghp_xxxxxxxx --global

# 设置项目级机密
codex secrets set AWS_ACCESS_KEY_ID AKIA... --env

# 列出当前环境的机密
codex secrets list

# 删除机密
codex secrets delete GITHUB_TOKEN
```

---

*文档生成时间：2026-03-21*
*基于代码版本：codex-rs/secrets @ main*
