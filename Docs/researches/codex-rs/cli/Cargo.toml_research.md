# codex-rs/cli/Cargo.toml 研究文档

## 场景与职责

`Cargo.toml` 是 Codex CLI crate 的清单文件，定义了包的元数据、构建配置、依赖关系和特性标志。它是 Cargo 构建系统的核心配置文件，同时也被 Bazel 构建系统引用。

该 crate 是 Codex 项目的**主入口点**，提供了：
- 交互式 TUI（`codex` 无子命令时）
- 非交互式执行（`codex exec`）
- 会话管理（`codex resume`, `codex fork`）
- 认证管理（`codex login`, `codex logout`）
- MCP 服务器管理（`codex mcp`）
- 沙箱调试工具（`codex sandbox`）

## 功能点目的

### 1. 包元数据

```toml
[package]
name = "codex-cli"
version.workspace = true
edition.workspace = true
license.workspace = true
```

- 使用 Workspace 继承机制，与整个工作区保持版本一致
- `edition.workspace = true` 使用 2021/2024 Edition 的 Rust 特性

### 2. 双目标构建配置

```toml
[[bin]]
name = "codex"
path = "src/main.rs"

[lib]
name = "codex_cli"
path = "src/lib.rs"
```

- **二进制目标** (`codex`)：用户直接使用的 CLI 入口
- **库目标** (`codex_cli`)：供其他 crate 和集成测试使用，导出沙箱命令结构体

### 3. 依赖体系

#### 核心框架依赖
- `anyhow` - 错误处理
- `clap` + `clap_complete` - CLI 解析和 Shell 补全生成
- `tokio` - 异步运行时（多线程 + 进程管理 + 信号处理）
- `tracing` + `tracing-subscriber` + `tracing-appender` - 结构化日志

#### Codex 内部依赖
| Crate | 用途 |
|-------|------|
| `codex-core` | 核心配置、认证、功能标志 |
| `codex-tui` | 交互式终端界面 |
| `codex-tui-app-server` | App Server 模式的 TUI 后端 |
| `codex-exec` | 非交互式执行引擎 |
| `codex-app-server` | App Server 协议实现 |
| `codex-app-server-protocol` | App Server 协议定义 |
| `codex-protocol` | 核心协议类型 |
| `codex-login` | 认证流程（OAuth、API Key） |
| `codex-mcp-server` | MCP 服务器实现 |
| `codex-rmcp-client` | MCP 客户端 |
| `codex-state` | 会话状态持久化（SQLite） |
| `codex-execpolicy` | 执行策略检查 |
| `codex-cloud-tasks` | Codex Cloud 集成 |
| `codex-chatgpt` | ChatGPT 集成（apply 命令） |

#### 平台特定依赖
```toml
[target.'cfg(target_os = "windows")'.dependencies]
codex_windows_sandbox = { package = "codex-windows-sandbox", path = "../windows-sandbox-rs" }
```

Windows 平台独有的沙箱实现。

#### 开发依赖
- `assert_cmd` + `predicates` - CLI 集成测试
- `codex-utils-cargo-bin` - 测试时定位二进制文件
- `pretty_assertions` - 美观的测试断言差异
- `sqlx` - 数据库测试支持

### 4. 特性与 Lints

```toml
[lints]
workspace = true
```

继承工作区级别的 Clippy 和 Rustc lint 配置。

## 具体技术实现

### Tokio 运行时配置

```toml
tokio = { workspace = true, features = [
    "io-std",
    "macros",
    "process",
    "rt-multi-thread",
    "signal",
] }
```

- `rt-multi-thread`：多线程运行时，适合 CPU 密集型 + IO 密集型混合负载
- `process`：子进程管理（沙箱执行）
- `signal`：Unix/Windows 信号处理（优雅退出）
- `macros`：`#[tokio::main]` 等宏支持

### 配置覆盖系统

`codex-utils-cli` 提供了 `CliConfigOverrides` 结构体，允许通过 `-c key=value` 参数覆盖配置文件：

```rust
// 典型用法（来自 main.rs）
let cli_kv_overrides = root_config_overrides.parse_overrides()?;
let config = Config::load_with_cli_overrides(cli_kv_overrides).await?;
```

### 沙箱命令导出

`lib.rs` 导出了三个沙箱命令结构体，供其他 crate 使用：

```rust
pub struct SeatbeltCommand { ... }   // macOS Seatbelt
pub struct LandlockCommand { ... }   // Linux Landlock
pub struct WindowsCommand { ... }    // Windows Restricted Token
```

## 关键代码路径与文件引用

### 入口点

| 文件 | 类型 | 说明 |
|------|------|------|
| `src/main.rs` | bin | CLI 主入口，命令路由 |
| `src/lib.rs` | lib | 库入口，导出沙箱命令 |

### 子命令实现

| 文件 | 子命令 |
|------|--------|
| `src/main.rs` | `exec`, `review`, `resume`, `fork`, `login`, `logout`, `completion`, `features` |
| `src/mcp_cmd.rs` | `mcp`（add, remove, list, get, login, logout） |
| `src/login.rs` | 登录流程的具体实现 |
| `src/debug_sandbox.rs` | `sandbox`（macOS/Linux/Windows） |
| `src/app_cmd.rs` | `app`（macOS 桌面应用） |
| `src/desktop_app/mac.rs` | macOS 桌面应用下载安装逻辑 |

### 测试文件

| 文件 | 测试范围 |
|------|----------|
| `tests/debug_clear_memories.rs` | `debug clear-memories` 命令 |
| `tests/execpolicy.rs` | `execpolicy check` 命令 |
| `tests/features.rs` | `features` 子命令 |
| `tests/mcp_add_remove.rs` | MCP 添加/删除 |
| `tests/mcp_list.rs` | MCP 列表/获取 |

## 依赖与外部交互

### 运行时依赖图

```
codex-cli (binary)
├── codex-core (配置、认证、功能标志)
├── codex-tui / codex-tui-app-server (交互界面)
├── codex-exec (非交互执行)
├── codex-app-server (App Server 模式)
├── codex-login (OAuth/API Key 认证)
├── codex-mcp-server / codex-rmcp-client (MCP 协议)
├── codex-state (SQLite 持久化)
└── codex-execpolicy (执行策略)
```

### 外部系统交互

1. **文件系统**：
   - `~/.codex/` - 配置、凭证、状态数据库
   - 工作目录 - 代码操作目标

2. **网络**：
   - OpenAI API（Responses API）
   - OAuth 认证端点
   - MCP 服务器（stdio / streamable HTTP）

3. **系统命令**：
   - `sandbox-exec`（macOS）
   - `codex-linux-sandbox`（Linux）
   - Windows 沙箱 API

## 风险、边界与改进建议

### 风险点

1. **依赖膨胀**：当前依赖 20+ 个内部 crate，构建时间较长
2. **平台差异**：Windows 依赖单独管理，容易遗漏
3. **功能标志复杂度**：`codex-core` 的功能标志影响 CLI 行为，调试困难

### 边界条件

- **最低 Rust 版本**：由 Workspace 定义（通常为最新 stable）
- **平台支持**：
  - Tier 1: macOS (x86_64, ARM64), Linux (x86_64, ARM64 musl)
  - Tier 2: Windows (x86_64, ARM64)

### 改进建议

1. **依赖优化**：
   - 考虑将 `cloud-tasks` 等功能设为可选特性（feature flag）
   - 评估 `owo-colors` 和 `supports-color` 是否可以合并

2. **构建优化**：
   - 启用 `tokio` 的 `parking_lot` 特性提升性能
   - 考虑使用 `cargo-chef` 或 Bazel 远程缓存加速 CI

3. **文档改进**：
   - 在 `Cargo.toml` 中添加各依赖的用途注释
   - 记录平台特定依赖的添加流程

4. **测试覆盖**：
   - 当前集成测试主要覆盖 MCP 和 features，建议增加：
     - 登录流程的 mock 测试
     - 沙箱执行的端到端测试
