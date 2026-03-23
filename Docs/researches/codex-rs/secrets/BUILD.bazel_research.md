# codex-rs/secrets/BUILD.bazel 研究文档

## 场景与职责

`BUILD.bazel` 是 Bazel 构建系统对 `codex-secrets` crate 的构建配置定义文件。它位于 `codex-rs/secrets/` 目录下，负责将该 Rust crate 注册到整个项目的 Bazel 构建体系中，使其能够被其他 crate 依赖，并参与统一的构建、测试和发布流程。

该 crate 的核心职责是提供安全的密钥管理功能，包括：
- 本地加密存储敏感信息（如 API Key、Token）
- 基于 OS Keyring 的密钥保护
- 敏感信息脱敏（redaction）功能

## 功能点目的

### 1. Bazel 目标定义

```bzl
codex_rust_crate(
    name = "secrets",
    crate_name = "codex_secrets",
)
```

| 参数 | 值 | 说明 |
|------|-----|------|
| `name` | `"secrets"` | Bazel 目标名称，用于在 BUILD 文件中引用 |
| `crate_name` | `"codex_secrets"` | Rust crate 的实际名称（Cargo.toml 中的 name 使用 kebab-case `codex-secrets`，但 Rust 代码中使用 snake_case） |

### 2. 构建系统集成

通过 `load("//:defs.bzl", "codex_rust_crate")` 引入项目统一的 Rust crate 构建宏，该宏封装了：
- `rust_library`: 构建 Rust 库
- `rust_test`: 构建单元测试和集成测试
- `rust_binary`: 构建可执行文件（如果有）
- 依赖管理（从 `@crates` 解析 Cargo.lock）
- 跨平台构建支持（Linux/macOS/Windows）

## 具体技术实现

### 关键流程

1. **依赖解析**: Bazel 通过 `all_crate_deps()` 从 `MODULE.bazel.lock` 中解析该 crate 的所有依赖
2. **源码收集**: 自动收集 `src/**/*.rs` 作为编译输入
3. **测试生成**: 自动生成单元测试目标（`*-unit-tests`）和集成测试目标（`*-test`）
4. **可见性**: 默认设置为 `//visibility:public`，允许任何其他目标依赖

### 数据结构

无特殊数据结构，配置完全委托给 `codex_rust_crate` 宏处理。

### 协议/命令

- **构建命令**: `bazel build //codex-rs/secrets:secrets`
- **测试命令**: `bazel test //codex-rs/secrets:secrets-unit-tests`
- **依赖查询**: `bazel query 'deps(//codex-rs/secrets:secrets)'`

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/secrets/BUILD.bazel` - 本文件

### 相关文件
- `/home/sansha/Github/codex/defs.bzl` - 定义 `codex_rust_crate` 宏
- `/home/sansha/Github/codex/codex-rs/secrets/Cargo.toml` - Cargo 配置（依赖声明）
- `/home/sansha/Github/codex/MODULE.bazel` - Bazel 模块定义
- `/home/sansha/Github/codex/MODULE.bazel.lock` - 依赖锁定文件

### 源码文件
- `/home/sansha/Github/codex/codex-rs/secrets/src/lib.rs` - 库入口
- `/home/sansha/Github/codex/codex-rs/secrets/src/local.rs` - 本地存储后端实现
- `/home/sansha/Github/codex/codex-rs/secrets/src/sanitizer.rs` - 敏感信息脱敏

## 依赖与外部交互

### 内部依赖（其他 codex-rs crates）
- `codex-keyring-store` - OS Keyring 抽象层

### 外部依赖（通过 Cargo/Bazel）
| 依赖 | 用途 |
|------|------|
| `age` | 文件加密（使用 scrypt 密钥派生） |
| `anyhow` | 错误处理 |
| `base64` | 密钥编码 |
| `rand` | 随机数生成 |
| `regex` | 脱敏正则匹配 |
| `schemars` | JSON Schema 生成 |
| `serde`/`serde_json` | 序列化 |
| `sha2` | 哈希计算（环境 ID） |
| `tracing` | 日志追踪 |

### 调用方
- `codex-rs/core` - 核心逻辑，使用 `SecretsManager` 管理密钥
- `codex-rs/core/src/memories/phase1.rs` - 使用 `redact_secrets` 脱敏记忆数据

### 被调用方
- `codex-rs/keyring-store` - 提供 `KeyringStore` trait 实现

## 风险、边界与改进建议

### 风险

1. **密钥泄露风险**
   - 加密密钥存储在 OS Keyring 中，如果 Keyring 被攻破，所有加密数据面临风险
   - 当前使用 `age` 的 scrypt 模式，依赖用户账户的安全性

2. **跨平台兼容性**
   - OS Keyring 在不同平台（macOS Keychain、Windows Credential Manager、Linux Secret Service）行为可能有差异
   - CI/无头环境可能无法访问 Keyring

3. **版本兼容性**
   - `SECRETS_VERSION = 1` 定义在代码中，未来升级需要处理向后兼容

### 边界

1. **仅支持 Local 后端**
   - `SecretsBackendKind` 目前只有 `Local` 变体，不支持云密钥管理服务（如 AWS KMS、Azure Key Vault）

2. **命名限制**
   - `SecretName` 只允许大写字母、数字和下划线（如 `GITHUB_TOKEN`）
   - 环境 ID 通过 git 仓库名或 CWD 哈希生成

3. **作用域限制**
   - 仅支持 `Global` 和 `Environment` 两种作用域

### 改进建议

1. **支持更多后端**
   ```rust
   pub enum SecretsBackendKind {
       Local,
       AwsKms,      // 新增
       AzureKeyVault, // 新增
       HashiCorpVault, // 新增
   }
   ```

2. **增强脱敏规则**
   - 当前 `sanitizer.rs` 只有 4 个正则规则，可以扩展支持更多密钥格式（如 GCP 服务账户、GitHub PAT 新格式等）

3. **密钥轮换支持**
   - 当前没有密钥版本管理，建议增加密钥轮换机制

4. **审计日志**
   - 增加密钥访问审计日志（谁、何时、访问了哪个密钥）

5. **Bazel 构建优化**
   - 当前配置没有特殊的 `rustc_flags` 或编译优化，可以考虑：
     - 启用 LTO（Link Time Optimization）减小二进制体积
     - 添加 `compile_data` 如果需要嵌入静态资源
