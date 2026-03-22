# cloud-requirements/BUILD.bazel 研究文档

## 场景与职责

`BUILD.bazel` 是 Bazel 构建系统中用于定义 `cloud-requirements` crate 构建规则的构建配置文件。该文件位于 `codex-rs/cloud-requirements/` 目录下，负责声明如何将 Rust 源代码编译成可重用的库 crate。

该 crate 的核心职责是为 Codex CLI/TUI 提供**云端配置需求获取能力**，支持从 OpenAI 后端服务动态拉取企业级用户的托管配置（requirements.toml）。

## 功能点目的

### 1. Bazel 构建规则定义

```bazel
load("//:defs.bzl", "codex_rust_crate")

codex_rust_crate(
    name = "cloud-requirements",
    crate_name = "codex_cloud_requirements",
)
```

- **name**: Bazel 目标名称，在构建图中标识此 crate
- **crate_name**: 编译后的 Rust crate 名称，遵循 `codex_*` 命名规范

### 2. 与 Cargo 的互操作

通过 `codex_rust_crate` 宏（定义于 `//:defs.bzl`），该构建规则实现了：
- 自动从 `Cargo.toml` 解析依赖
- 生成与 Cargo 兼容的库目标
- 支持单元测试和集成测试的 Bazel 化执行
- 处理 `INSTA_WORKSPACE_ROOT` 等快照测试环境变量

## 具体技术实现

### 关键流程

1. **构建脚本处理**: 如果存在 `build.rs`，会自动创建 build script 目标
2. **源码收集**: 通过 `native.glob(["src/**/*.rs"])` 自动收集所有 Rust 源文件
3. **依赖解析**: 从 `@crates` 工作区解析 `Cargo.lock` 定义的依赖
4. **测试目标生成**: 自动生成单元测试二进制和 workspace-root 测试启动器

### 数据结构

```bazel
# 关键常量（来自 defs.bzl）
PLATFORMS = [
    "linux_arm64_musl",
    "linux_amd64_musl", 
    "macos_amd64",
    "macos_arm64",
    "windows_amd64",
    "windows_arm64",
]
```

### 路径重映射

为确保 Bazel 和 Cargo 的兼容性，构建时注入以下 `rustc_flags`：
```bazel
"--remap-path-prefix=../codex-rs=",
"--remap-path-prefix=codex-rs=",
```

## 关键代码路径与文件引用

### 直接依赖

| 文件 | 说明 |
|------|------|
| `//:defs.bzl` | 定义 `codex_rust_crate` 宏，包含完整的 Rust crate 构建逻辑 |
| `Cargo.toml` | 声明 crate 元数据和依赖（见同目录 `Cargo.toml_research.md`） |
| `src/lib.rs` | 唯一的源文件，包含云端配置获取的完整实现 |

### 上游调用方

- `codex-rs/core/src/config_loader/mod.rs` - 通过 `CloudRequirementsLoader` 集成
- `codex-rs/tui/src/lib.rs` - TUI 启动时初始化云端配置
- `codex-rs/tui_app_server/src/lib.rs` - 应用服务器初始化
- `codex-rs/exec/src/lib.rs` - 执行器初始化

### 下游被调用方

- `codex-rs/backend-client` - HTTP 客户端，提供 `get_config_requirements_file()` API
- `codex-rs/core` - 提供 `AuthManager` 和配置加载基础设施
- `codex-rs/protocol` - 提供 `PlanType` 等协议类型

## 依赖与外部交互

### Bazel 工作区依赖

```
@crates//:defs.bzl          # Cargo 依赖解析
@crates//:data.bzl          # 二进制文件元数据
@rules_rust//rust:defs.bzl  # Rust 规则
@rules_platform//...        # 平台数据规则
```

### 运行时依赖（通过 Cargo.toml）

| Crate | 用途 |
|-------|------|
| `codex-backend-client` | 后端 HTTP API 调用 |
| `codex-core` | 认证管理、配置加载 |
| `codex-otel` | 可观测性指标上报 |
| `codex-protocol` | 协议类型定义 |
| `hmac` + `sha2` | 缓存文件签名验证 |
| `tokio` | 异步运行时 |

## 风险、边界与改进建议

### 风险点

1. **缓存签名密钥硬编码**: `CLOUD_REQUIREMENTS_CACHE_WRITE_HMAC_KEY` 在源码中硬编码，虽使用 UUID 命名空间区分版本，但理论上存在被提取的风险
2. **单文件实现**: 整个 crate 仅 `src/lib.rs` 一个文件（1930 行），包含实现和测试，维护性较差
3. **全局静态状态**: `refresher_task_slot()` 使用 `OnceLock<Mutex<...>>` 存储后台刷新任务，测试隔离可能受影响

### 边界条件

1. **仅支持 Business/Enterprise 计划**: 通过 `PlanType::Business | PlanType::Enterprise` 过滤
2. **仅支持 ChatGPT 认证**: 通过 `auth.is_chatgpt_auth()` 检查
3. **失败闭合（Fail-closed）**: 对于符合条件的账户，云端配置获取失败会导致整个配置加载失败

### 改进建议

1. **代码拆分**: 将 `src/lib.rs` 拆分为多个模块：
   - `fetcher.rs` - 获取逻辑
   - `cache.rs` - 缓存管理
   - `metrics.rs` - 指标上报
   - `tests/` - 测试文件分离

2. **配置化密钥**: 考虑支持从环境变量或配置文件读取 HMAC 密钥，便于密钥轮换

3. **增加熔断机制**: 当前实现有重试（5 次）和超时（15s），但可考虑增加基于失败率的熔断

4. **Bazel 优化**: 考虑添加 `tags = ["requires-network"]` 标记需要网络的测试

### 监控指标

该 crate 通过 `codex_otel` 上报以下指标：
- `codex.cloud_requirements.fetch_attempt` - 单次获取尝试
- `codex.cloud_requirements.fetch_final` - 最终获取结果
- `codex.cloud_requirements.load` - 加载结果
- `codex.cloud_requirements.fetch.duration_ms` - 获取耗时
