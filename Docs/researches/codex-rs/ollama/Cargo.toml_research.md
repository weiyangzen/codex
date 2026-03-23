# Cargo.toml 研究文档

## 场景与职责

该文件定义了 `codex-ollama` crate 的元数据、依赖关系和构建设置。作为 OpenAI Codex CLI 的 Ollama 集成模块，它提供了与本地 Ollama 服务通信的能力，支持模型发现、拉取和版本检查等功能。

## 功能点目的

1. **Crate 元数据定义**: 设置 crate 名称、版本、edition 和许可证信息
2. **库目标配置**: 定义库入口文件为 `src/lib.rs`，库名称为 `codex_ollama`
3. **依赖管理**: 声明运行时依赖和开发依赖，支持异步 HTTP 通信、JSON 处理、版本解析等功能
4. **Lint 配置**: 继承工作空间的 lint 规则，确保代码质量一致性

## 具体技术实现

### 包元数据

```toml
[package]
name = "codex-ollama"           # Crate 名称（Cargo 注册表使用）
version.workspace = true        # 继承工作空间版本（0.0.0）
edition.workspace = true        # 继承工作空间 edition（2024）
license.workspace = true        # 继承工作空间许可证（Apache-2.0）
```

### 库配置

```toml
[lib]
name = "codex_ollama"           # 库 crate 名称（Rust 代码中使用）
path = "src/lib.rs"             # 库入口文件
```

### 依赖分析

#### 运行时依赖

| 依赖 | 用途 | 关键特性 |
|------|------|----------|
| `async-stream` | 生成异步流 | 用于 `pull_model_stream()` 的 SSE 流处理 |
| `bytes` | 字节缓冲区管理 | 处理 HTTP 响应流的块数据 |
| `codex-core` | 核心类型和配置 | `ModelProviderInfo`, `Config`, `OLLAMA_OSS_PROVIDER_ID` |
| `futures` | 异步 trait 支持 | `StreamExt` 用于流处理 |
| `reqwest` | HTTP 客户端 | `json`, `stream` 特性支持 JSON API 和流式响应 |
| `semver` | 语义化版本解析 | 解析 Ollama 服务器版本号 |
| `serde_json` | JSON 序列化/反序列化 | 解析 Ollama API 响应 |
| `tokio` | 异步运行时 | `rt-multi-thread`, `process`, `signal` 等特性 |
| `tracing` | 结构化日志 | `log` 特性集成 |
| `wiremock` | HTTP mock（测试用） | 用于单元测试中的 mock 服务器 |

#### 开发依赖

| 依赖 | 用途 |
|------|------|
| `assert_matches` | 模式匹配断言（测试中） |
| `pretty_assertions` | 美观的断言差异显示 |

### Tokio 特性详解

```toml
tokio = { workspace = true, features = [
    "io-std",           # 标准输入输出异步支持
    "macros",           # 异步测试宏支持
    "process",          # 异步进程管理
    "rt-multi-thread",  # 多线程运行时
    "signal",           # 异步信号处理
] }
```

## 关键代码路径与文件引用

### 源码结构
```
codex-rs/ollama/src/
├── lib.rs           # 库入口，导出公共 API
├── client.rs        # OllamaClient 实现
├── parser.rs        # 拉取事件解析
├── pull.rs          # 进度报告 trait 和实现
└── url.rs           # URL 处理工具
```

### 公共 API 导出（lib.rs）

```rust
pub use client::OllamaClient;           # 主客户端
pub use pull::CliProgressReporter;      # CLI 进度报告器
pub use pull::PullEvent;                # 拉取事件枚举
pub use pull::PullProgressReporter;     # 进度报告 trait
pub use pull::TuiProgressReporter;      # TUI 进度报告器

pub const DEFAULT_OSS_MODEL: &str = "gpt-oss:20b";  # 默认模型

pub async fn ensure_oss_ready(config: &Config) -> std::io::Result<()>;  # 准备 OSS 环境
pub async fn ensure_responses_supported(provider: &ModelProviderInfo) -> std::io::Result<()>;  # 版本检查
```

### 依赖使用场景

1. **HTTP 通信** (`reqwest`):
   - `client.rs:84` - `probe_server()` 探测服务器健康状态
   - `client.rs:104` - `fetch_models()` 获取模型列表
   - `client.rs:130` - `fetch_version()` 获取版本信息
   - `client.rs:161` - `pull_model_stream()` 流式拉取模型

2. **版本解析** (`semver`):
   - `lib.rs:52` - `min_responses_version()` 定义最低版本要求
   - `lib.rs:55` - `supports_responses()` 检查版本兼容性
   - `client.rs:143` - `fetch_version()` 解析版本字符串

3. **异步流** (`async-stream`, `futures`):
   - `client.rs:178` - `pull_model_stream()` 使用 `async_stream::stream!` 生成事件流

4. **JSON 处理** (`serde_json`):
   - `parser.rs:6` - `pull_events_from_value()` 解析拉取事件
   - `client.rs` 多处用于 API 响应解析

## 依赖与外部交互

### 工作空间依赖

该 crate 使用 `workspace = true` 继承父工作空间的依赖版本，确保整个项目依赖一致性：

```toml
# 来自 codex-rs/Cargo.toml
async-stream = "0.3.6"
bytes = "1.10.1"
reqwest = "0.12"
semver = "1.0"
serde_json = "1"
tokio = "1"
tracing = "0.1.44"
wiremock = "0.6"
```

### 内部依赖

- **`codex-core`**: 提供核心类型
  - `ModelProviderInfo` - 模型提供者配置
  - `Config` - 应用配置
  - `OLLAMA_OSS_PROVIDER_ID` - 提供者标识符常量

### 调用方

- **`codex-utils-oss`**: 调用 `ensure_oss_ready()` 和 `ensure_responses_supported()`
- **`codex-tui`**: 通过 `codex-utils-oss` 间接使用
- **`codex-exec`**: 通过 `codex-utils-oss` 间接使用

## 风险、边界与改进建议

### 风险点

1. **依赖版本冲突**:
   - `wiremock` 被声明为运行时依赖而非仅开发依赖，这可能导致生产构建包含不必要的测试库
   - 建议：将 `wiremock` 移至 `[dev-dependencies]`

2. **Tokio 特性过度配置**:
   - 启用了 `process` 和 `signal` 特性，但当前代码中未见使用
   - 建议：审查实际使用场景，移除未使用的特性以减少编译时间和二进制大小

3. **版本硬编码**:
   - `DEFAULT_OSS_MODEL = "gpt-oss:20b"` 是硬编码的默认模型
   - 如果该模型在 Ollama 注册表中更名或下线，用户体验将受影响

### 边界条件

1. **网络超时**:
   - `reqwest` 客户端配置了 5 秒连接超时（`client.rs:65`）
   - 在慢网络环境下可能过于严格

2. **版本兼容性**:
   - 最低支持版本 0.13.4 硬编码在 `lib.rs:52`
   - 如果 Ollama 发布 1.0 版本，版本比较逻辑可能需要调整

3. **内存使用**:
   - `bytes` 缓冲区在流式处理中累积数据直到找到换行符
   - 极端情况下（无换行符的长响应）可能导致内存增长

### 改进建议

1. **依赖优化**:
   ```toml
   # 建议将 wiremock 移至 dev-dependencies
   [dev-dependencies]
   wiremock = { workspace = true }
   assert_matches = { workspace = true }
   pretty_assertions = { workspace = true }
   ```

2. **特性精简**:
   ```toml
   # 如果未使用 process 和 signal，可精简为：
   tokio = { workspace = true, features = [
       "io-std",
       "macros",
       "rt-multi-thread",
   ] }
   ```

3. **可配置默认模型**:
   - 考虑通过环境变量或配置文件允许用户覆盖 `DEFAULT_OSS_MODEL`
   - 示例：`CODEX_DEFAULT_OSS_MODEL` 环境变量

4. **增加可选特性**:
   ```toml
   [features]
   default = []
   # 可选：添加 tls-rustls 特性以支持不同的 TLS 后端
   tls-rustls = ["reqwest/rustls-tls"]
   tls-native = ["reqwest/native-tls"]
   ```

5. **文档依赖**:
   - 考虑添加 `tracing-subscriber` 作为 dev-dependency 以支持测试中的日志输出

6. **版本声明**:
   - 当前 `version.workspace = true` 继承 0.0.0，如果计划发布到 crates.io，需要独立版本管理
