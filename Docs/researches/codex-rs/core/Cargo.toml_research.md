# codex-rs/core/Cargo.toml 研究文档

## 场景与职责

`Cargo.toml` 是 Rust crate `codex-core` 的包清单文件，定义了 crate 的元数据、依赖项、构建配置和功能特性。作为 Codex 项目的核心业务逻辑 crate，它承载了 AI 编程助手的核心功能，包括配置管理、工具执行、沙箱安全、MCP 集成等。

该 crate 被设计为多平台支持（macOS、Linux、Windows），并提供：
- 库 (`lib`)：供 TUI、CLI、App Server 等前端使用
- 二进制 (`bin`)：`codex-write-config-schema` 用于生成配置 Schema

## 功能点目的

### 1. 包元数据

```toml
[package]
edition.workspace = true
license.workspace = true
name = "codex-core"
version.workspace = true
```

- **edition.workspace**：使用工作区统一的 Rust Edition（2021）
- **license.workspace**：继承工作区许可证配置
- **name**：crate 名称 `codex-core`，库名 `codex_core`

### 2. 库定义

```toml
[lib]
doctest = false
name = "codex_core"
path = "src/lib.rs"
```

- `doctest = false`：禁用文档测试，减少构建时间
- 显式指定库名和入口路径

### 3. 二进制定义

```toml
[[bin]]
name = "codex-write-config-schema"
path = "src/bin/config_schema.rs"
```

- 提供配置 Schema 生成工具
- 由 `just write-config-schema` 调用

### 4. 依赖项架构

依赖分为以下几类：

#### 4.1 工作区依赖 (workspace = true)

| 类别 | 依赖示例 | 用途 |
|------|----------|------|
| 异步运行时 | `tokio`, `futures` | 异步 I/O 和任务调度 |
| HTTP 客户端 | `reqwest` | OpenAI API 通信 |
| 序列化 | `serde`, `serde_json`, `serde_yaml`, `toml` | 配置和数据序列化 |
| 错误处理 | `anyhow`, `thiserror` | 错误传播和定义 |
| 日志/追踪 | `tracing` | 结构化日志 |
| CLI | `clap` | 命令行解析 |

#### 4.2 内部 Workspace Crates

```toml
codex-api = { workspace = true }
codex-app-server-protocol = { workspace = true }
codex-apply-patch = { workspace = true }
# ... 共 30+ 个内部 crate
```

内部 crate 按功能域划分：
- **API/协议**：`codex-api`, `codex-protocol`, `codex-app-server-protocol`
- **工具/执行**：`codex-apply-patch`, `codex-shell-command`, `codex-execpolicy`
- **安全/沙箱**：`codex-secrets`, `codex-keyring-store`
- **平台特定**：`codex-windows-sandbox`, `codex-linux-sandbox` (通过路径引用)
- **基础设施**：`codex-async-utils`, `codex-utils-*`

#### 4.3 外部关键依赖

| 依赖 | 版本/特性 | 用途 |
|------|-----------|------|
| `askama` | workspace | 模板引擎（提示模板） |
| `rmcp` | base64, macros, schemars, server | MCP (Model Context Protocol) 实现 |
| `landlock` | workspace | Linux 沙箱 (文件系统隔离) |
| `seccompiler` | workspace | Linux seccomp BPF 编译 |
| `keyring` | crypto-rust | 凭据安全存储 |
| `schemars` | workspace | JSON Schema 生成 |
| `tokio-tungstenite` | workspace | WebSocket 支持 (Realtime API) |
| `image` | jpeg, png, webp | 图像处理 |

### 5. 平台特定依赖

#### Linux
```toml
[target.'cfg(target_os = "linux")'.dependencies]
keyring = { workspace = true, features = ["linux-native-async-persistent"] }
landlock = { workspace = true }
seccompiler = { workspace = true }
```

- `landlock`：文件系统沙箱
- `seccompiler`：系统调用过滤

#### macOS
```toml
[target.'cfg(target_os = "macos")'.dependencies]
core-foundation = "0.9"
keyring = { workspace = true, features = ["apple-native"] }
```

- `core-foundation`：macOS 系统 API
- Apple Keychain 集成

#### musl (静态链接)
```toml
[target.x86_64-unknown-linux-musl.dependencies]
openssl-sys = { workspace = true, features = ["vendored"] }

[target.aarch64-unknown-linux-musl.dependencies]
openssl-sys = { workspace = true, features = ["vendored"] }
```

- 静态链接 OpenSSL 以支持 musl 目标

#### Windows
```toml
[target.'cfg(target_os = "windows")'.dependencies]
keyring = { workspace = true, features = ["windows-native"] }
windows-sys = { version = "0.52", features = [...] }
```

- Windows Credential Manager 集成
- Win32 API 访问

#### BSD
```toml
[target.'cfg(any(target_os = "freebsd", target_os = "openbsd"))'.dependencies]
keyring = { workspace = true, features = ["sync-secret-service"] }
```

#### Unix (通用)
```toml
[target.'cfg(unix)'.dependencies]
codex-shell-escalation = { workspace = true }
```

- Unix 特权提升支持

### 6. 开发依赖

```toml
[dev-dependencies]
assert_cmd = { workspace = true }
insta = { workspace = true }
wiremock = { workspace = true }
# ...
```

- `insta`：快照测试（UI 输出验证）
- `wiremock`：HTTP 服务模拟（API 测试）
- `assert_cmd`/`predicates`：CLI 测试

## 具体技术实现

### 依赖版本管理

所有依赖版本都在工作区根 `Cargo.toml` 中统一定义，通过 `workspace = true` 继承：

```toml
# 根 Cargo.toml
[workspace.dependencies]
anyhow = "1.0"
tokio = { version = "1.35", features = ["full"] }
# ...

# codex-rs/core/Cargo.toml
[dependencies]
anyhow = { workspace = true }
tokio = { workspace = true, features = ["io-std", "macros", "process", "rt-multi-thread", "signal"] }
```

### 特性组合

| 依赖 | 显式特性 | 说明 |
|------|----------|------|
| `tokio` | `io-std`, `macros`, `process`, `rt-multi-thread`, `signal` | 完整异步运行时 |
| `reqwest` | `json`, `stream` | HTTP JSON 和流支持 |
| `image` | `jpeg`, `png`, `webp` | 图像格式支持 |
| `chrono` | `serde` | 时间序列化 |
| `keyring` | 平台特定 | 凭据存储 |

### MCP (Model Context Protocol) 配置

```toml
rmcp = { workspace = true, default-features = false, features = [
    "base64",
    "macros",
    "schemars",
    "server",
] }
```

- `default-features = false`：精简构建
- `server`：启用 MCP 服务器功能
- `schemars`：支持 JSON Schema 生成

## 关键代码路径与文件引用

### 内部 Crate 依赖图

```
codex-core
├── codex-api (API 类型定义)
├── codex-protocol (核心协议)
├── codex-app-server-protocol (App Server 协议)
├── codex-apply-patch (补丁应用)
├── codex-client (API 客户端)
├── codex-config (配置管理)
├── codex-execpolicy (执行策略)
├── codex-file-search (文件搜索)
├── codex-git (Git 集成)
├── codex-hooks (生命周期钩子)
├── codex-mcp-client (MCP 客户端)
├── codex-secrets (密钥管理)
├── codex-skills (技能系统)
├── codex-state (状态管理)
└── codex-utils-* (工具库)
```

### 关键源文件

| 模块 | 文件路径 | 说明 |
|------|----------|------|
| 库入口 | `src/lib.rs` | 模块声明和公共导出 |
| 配置 | `src/config/mod.rs` | 配置加载和验证 |
| 配置 Schema | `src/config/schema.rs` | JSON Schema 生成 |
| 特性标志 | `src/features.rs` | 功能开关定义 |
| 主逻辑 | `src/codex.rs` | Codex 核心实现 |
| 工具注册 | `src/tools/mod.rs` | 工具系统 |
| 沙箱 | `src/sandboxing/mod.rs` | 沙箱抽象 |
| MCP | `src/mcp/mod.rs` | MCP 集成 |
| 二进制 | `src/bin/config_schema.rs` | Schema 生成工具 |

## 依赖与外部交互

### 运行时依赖

| 外部系统 | 依赖 crate | 交互方式 |
|----------|------------|----------|
| OpenAI API | `reqwest`, `serde_json` | HTTP/JSON API |
| MCP Servers | `rmcp` | stdio/HTTP 传输 |
| 操作系统沙箱 | `landlock`, `seccompiler`, `core-foundation` | 平台特定 API |
| 凭据存储 | `keyring` | OS Keychain/Keystore |
| SQLite | `codex-state` | 本地状态存储 |

### 构建时依赖

- `openssl-sys` (musl)：静态链接需要源码构建
- `schemars`：生成 `config.schema.json`

### 可选/条件依赖

| 条件 | 依赖 | 说明 |
|------|------|------|
| `cfg(target_os = "linux")` | `landlock`, `seccompiler` | Linux 沙箱 |
| `cfg(target_os = "macos")` | `core-foundation` | macOS API |
| `cfg(target_os = "windows")` | `windows-sys` | Windows API |
| `cfg(unix)` | `codex-shell-escalation` | Unix 特权提升 |

## 风险、边界与改进建议

### 依赖风险

1. **依赖数量庞大**（60+ 直接依赖）：
   - 增加编译时间和二进制体积
   - 建议：评估是否可以精简或合并某些内部 crate

2. **平台特定依赖复杂**：
   - 5 个不同的 `target.'cfg(...)'` 块
   - 维护成本高，CI 需要覆盖所有平台

3. **`openssl-sys` 静态链接**：
   - musl 构建需要从源码编译 OpenSSL
   - 增加构建时间，可能引入安全更新延迟

### 版本管理

1. **Workspace 依赖集中管理**：
   - 优点：版本一致性
   - 风险：单点更新可能影响多个 crate

2. **`cargo-shear` 忽略**：
   ```toml
   [package.metadata.cargo-shear]
   ignored = ["openssl-sys"]
   ```
   - `openssl-sys` 被标记为忽略，因为它只在特定目标使用
   - 需要确保不会误删实际需要的依赖

### 改进建议

1. **依赖分组文档化**：
   ```toml
   # 当前：所有依赖混在一起
   # 建议：按功能分组注释
   
   # === 异步运行时 ===
   tokio = { ... }
   futures = { ... }
   
   # === HTTP/Web ===
   reqwest = { ... }
   tokio-tungstenite = { ... }
   
   # === 安全/沙箱 ===
   landlock = { ... }
   seccompiler = { ... }
   ```

2. **特性门控优化**：
   - 某些功能（如 `realtime_conversation`）可以通过 Cargo features 可选编译
   - 减少基础二进制体积

3. **开发依赖精简**：
   - `test-log`, `tracing-test` 等功能可能重叠
   - 评估是否可以合并

4. **平台依赖自动化测试**：
   - 确保所有 `cfg` 条件在 CI 中都有覆盖
   - 考虑使用 `cargo check --all-targets` 验证

5. **MCP 版本锁定**：
   - `rmcp` 是快速发展的协议实现
   - 建议明确版本约束，避免意外破坏
