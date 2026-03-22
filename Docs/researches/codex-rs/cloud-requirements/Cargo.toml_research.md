# cloud-requirements/Cargo.toml 研究文档

## 场景与职责

`Cargo.toml` 是 Rust 包管理工具 Cargo 的配置清单文件，定义了 `codex-cloud-requirements` crate 的元数据、依赖关系和构建配置。该 crate 是 Codex 项目中负责**从云端获取企业级托管配置**的核心组件。

主要使用场景：
1. **企业用户配置管理**: ChatGPT Business/Enterprise 账户通过云端 `requirements.toml` 统一管理组织内的 Codex 使用策略
2. **本地缓存与刷新**: 将云端配置缓存到本地，定期后台刷新
3. **安全策略下发**: 支持管理员控制沙箱模式、审批策略、网络代理等企业级安全设置

## 功能点目的

### 1. 包元数据声明

```toml
[package]
name = "codex-cloud-requirements"
version.workspace = true
edition.workspace = true
license.workspace = true
```

- **name**: 遵循 `codex-*` 命名规范的 crate 名称
- **version.workspace**: 继承工作区统一版本号
- **edition.workspace**: 继承工作区 Rust 版本（2021 edition）
- **license.workspace**: 继承工作区许可证声明

### 2. 代码质量保障

```toml
[lints]
workspace = true
```

继承工作区级别的 Clippy lint 配置，确保代码风格一致性。

### 3. 运行时依赖管理

| 依赖 | 版本/来源 | 功能用途 |
|------|----------|----------|
| `async-trait` | workspace | 异步 trait 支持 |
| `base64` | workspace | 缓存签名 base64 编解码 |
| `chrono` | workspace + serde | 时间戳处理与序列化 |
| `codex-backend-client` | workspace | 后端 HTTP API 客户端 |
| `codex-core` | workspace | 认证管理、配置加载基础设施 |
| `codex-otel` | workspace | OpenTelemetry 指标上报 |
| `codex-protocol` | workspace | 协议类型（PlanType 等）|
| `hmac` | 0.12.1 | HMAC-SHA256 签名计算 |
| `serde` | workspace + derive | 序列化/反序列化 |
| `serde_json` | workspace | JSON 处理 |
| `sha2` | workspace | SHA256 哈希 |
| `thiserror` | workspace | 错误类型定义 |
| `tokio` | workspace + fs,sync,time | 异步运行时 |
| `toml` | workspace | TOML 解析 |
| `tracing` | workspace | 结构化日志 |

### 4. 开发依赖

```toml
[dev-dependencies]
pretty_assertions = { workspace = true }
tempfile = { workspace = true }
tokio = { workspace = true, features = ["macros", "rt", "test-util", "time"] }
```

- **pretty_assertions**: 测试失败时提供美观的 diff 输出
- **tempfile**: 测试时创建临时目录存放缓存文件
- **tokio**: 测试所需的异步运行时和工具

## 具体技术实现

### 依赖版本策略

该 crate 采用**工作区继承（workspace inheritance）**策略：
- 大多数依赖使用 `workspace = true` 继承统一版本
- 仅 `hmac` 指定固定版本 `0.12.1`，因其为安全相关依赖，需精确控制

### 特性标志（Features）

Tokio 启用的特性：
- `fs`: 异步文件系统操作（缓存读写）
- `sync`: 同步原语（`Mutex`, `Arc`）
- `time`: 异步定时器（超时、刷新间隔）

测试专用特性：
- `macros`: `#[tokio::test]` 宏
- `rt`: 运行时支持
- `test-util`: 测试工具（如 `tokio::time::advance`）
- `time`: 测试时间控制

### 关键数据结构

```rust
// 缓存文件结构（对应 JSON 序列化）
CloudRequirementsCacheFile {
    signed_payload: CloudRequirementsCacheSignedPayload,
    signature: String,  // HMAC-SHA256 base64
}

CloudRequirementsCacheSignedPayload {
    cached_at: DateTime<Utc>,
    expires_at: DateTime<Utc>,
    chatgpt_user_id: Option<String>,
    account_id: Option<String>,
    contents: Option<String>,  // TOML 内容
}
```

## 关键代码路径与文件引用

### 源码结构

```
codex-rs/cloud-requirements/
├── Cargo.toml          # 本文件
├── BUILD.bazel         # Bazel 构建规则
└── src/
    └── lib.rs          # 单一源文件（1930 行，含测试）
```

### 核心模块（lib.rs 内）

| 模块/结构 | 行号范围 | 职责 |
|----------|---------|------|
| 常量定义 | 45-58 | 超时、重试、缓存文件名等配置 |
| `RetryableFailureKind` | 67-80 | 可重试失败分类 |
| `FetchAttemptError` | 82-89 | 获取尝试错误类型 |
| `CacheLoadStatus` | 91-109 | 缓存加载状态（错误枚举）|
| `CloudRequirementsCacheFile` | 117-121 | 缓存文件结构 |
| `RequirementsFetcher` trait | 184-193 | 获取器抽象接口 |
| `BackendRequirementsFetcher` | 195-245 | 后端 HTTP 实现 |
| `CloudRequirementsService` | 247-687 | 核心服务逻辑 |
| `cloud_requirements_loader` | 689-721 | 公开 API 入口 |
| 测试模块 | 818-1930 | 单元测试（~1100 行）|

### 调用关系

```
调用方:
  codex_core::config_loader::load_config_layers_state()
    └─> cloud_requirements_loader()
        └─> CloudRequirementsService::fetch_with_timeout()
            ├─> load_cache()          // 本地缓存
            └─> fetch_with_retries()  // 后端获取
                └─> BackendRequirementsFetcher::fetch_requirements()
                    └─> codex_backend_client::get_config_requirements_file()
```

## 依赖与外部交互

### 内部 Workspace 依赖

```
codex-backend-client  提供 HTTP 客户端和 API 调用
codex-core           提供 AuthManager、配置加载
codex-otel           提供指标上报（counter、timer）
codex-protocol       提供 PlanType、AskForApproval 等类型
codex-config         提供 ConfigRequirementsToml、CloudRequirementsLoader
```

### 外部 Crate 依赖

**安全/加密**:
- `hmac` + `sha2`: 缓存文件完整性保护（HMAC-SHA256）
- `base64`: 签名 base64 编解码

**异步运行时**:
- `tokio`: 文件 IO、定时器、任务调度
- `async-trait`: 异步 trait 支持

**序列化**:
- `serde` + `serde_json`: 缓存文件 JSON 格式
- `toml`: 云端配置 TOML 解析
- `chrono` + serde: 时间戳处理

**错误处理**:
- `thiserror`: 声明式错误类型

**可观测性**:
- `tracing`: 结构化日志

## 风险、边界与改进建议

### 风险点

1. **HMAC 密钥硬编码**: 
   ```rust
   const CLOUD_REQUIREMENTS_CACHE_WRITE_HMAC_KEY: &[u8] =
       b"codex-cloud-requirements-cache-v3-064f8542-75b4-494c-a294-97d3ce597271";
   ```
   - 密钥虽使用 UUID 区分版本，但仍为硬编码
   - 建议：支持环境变量覆盖，便于密钥轮换

2. **单一文件过大**: `lib.rs` 1930 行，维护困难
   - 建议：拆分为 `service.rs`, `cache.rs`, `fetcher.rs`, `metrics.rs`

3. **测试依赖真实时间**: 部分测试使用 `tokio::time::advance`，但缓存过期测试依赖 `Utc::now()`
   - 建议：注入时钟抽象，支持完全可控的时间测试

### 边界条件

| 边界 | 处理 |
|------|------|
| 非 ChatGPT 认证 | 直接返回 `Ok(None)`，不获取云端配置 |
| 非 Business/Enterprise 计划 | 直接返回 `Ok(None)` |
| 身份不完整（缺少 user_id/account_id）| 跳过缓存读取，但仍尝试获取并写入缓存 |
| 缓存签名无效 | 忽略缓存，重新获取 |
| 缓存过期 | 忽略缓存，重新获取 |
| 身份不匹配 | 忽略缓存，重新获取 |
| 获取超时（15s）| 失败闭合，返回错误 |
| 重试耗尽（5 次）| 失败闭合，返回错误 |
| 401 Unauthorized | 尝试认证恢复，失败则返回错误 |

### 改进建议

1. **模块化重构**:
   ```
   src/
   ├── lib.rs           # 公开 API
   ├── service.rs       # CloudRequirementsService
   ├── fetcher.rs       # RequirementsFetcher trait + BackendRequirementsFetcher
   ├── cache.rs         # 缓存读写、签名验证
   ├── metrics.rs       # 指标上报
   └── tests/
       └── mod.rs       # 测试分离
   ```

2. **配置化超时和重试**:
   ```toml
   [features]
   custom-timeouts = []
   ```
   允许通过环境变量或 feature 调整超时参数。

3. **增强缓存安全性**:
   - 考虑使用平台密钥链（keyring）存储加密密钥
   - 或支持从环境变量 `CODEX_CLOUD_REQ_HMAC_KEY` 读取密钥

4. **指标增强**:
   - 当前仅上报 counter，建议增加 histogram 记录获取耗时分布
   - 增加缓存命中率指标

5. **Cargo.toml 优化**:
   ```toml
   [features]
   default = []
   integration-tests = []  # 隔离需要真实网络的测试
   ```

### 版本演进建议

当前缓存版本为 v3（从密钥 UUID 可见）。未来版本升级时：
1. 更新 `CLOUD_REQUIREMENTS_CACHE_WRITE_HMAC_KEY` 的 UUID
2. 将旧密钥加入 `CLOUD_REQUIREMENTS_CACHE_READ_HMAC_KEYS` 保持向后兼容
3. 在 CHANGELOG 中记录缓存格式变更
