# codex-rs/exec/Cargo.toml 研究文档

## 场景与职责

`Cargo.toml` 是 `codex-exec` crate 的 Rust 包管理清单文件，定义了：

- 包元数据（名称、版本、许可证）
- 构建目标（二进制 + 库）
- 依赖项（生产依赖 + 开发依赖）
- 功能特性（features）

该 crate 是 Codex CLI 的非交互式执行入口，提供 `codex-exec` 二进制命令，用于在终端/CI 环境中运行 Codex 代理。

## 功能点目的

### 1. 包元数据

```toml
[package]
name = "codex-exec"
version.workspace = true
edition.workspace = true
license.workspace = true
```

- 版本、Rust 版本、许可证从工作区继承，确保多 crate 一致性

### 2. 双目标构建

```toml
[[bin]]
name = "codex-exec"
path = "src/main.rs"

[lib]
name = "codex_exec"
path = "src/lib.rs"
```

| 目标 | 名称 | 路径 | 用途 |
|------|------|------|------|
| 二进制 | `codex-exec` | `src/main.rs` | CLI 入口 |
| 库 | `codex_exec` | `src/lib.rs` | 可复用逻辑、测试 |

### 3. 依赖架构

生产依赖分为几个层次：

**核心协议与配置**
- `codex-core` - 核心功能（配置、认证、Git 操作）
- `codex-protocol` - 协议定义（事件、消息类型）
- `codex-app-server-protocol` - App Server 通信协议
- `codex-app-server-client` - App Server 客户端

**工具库**
- `codex-arg0` - arg0 分发（支持 `codex-linux-sandbox` 别名调用）
- `codex-utils-*` - 各种工具（路径、CLI、耗时格式化等）
- `codex-feedback` - 用户反馈收集
- `codex-otel` - OpenTelemetry 遥测

**外部 crate**
- `tokio` - 异步运行时
- `clap` - 命令行解析
- `serde`/`serde_json` - 序列化
- `tracing`/`tracing-subscriber` - 日志与追踪
- `owo-colors` - 终端颜色
- `ts-rs` - TypeScript 类型生成

### 4. 开发依赖

```toml
[dev-dependencies]
assert_cmd = { workspace = true }
codex-apply-patch = { workspace = true }
codex-utils-cargo-bin = { workspace = true }
core_test_support = { workspace = true }
# ...
```

- `assert_cmd` - CLI 测试断言
- `core_test_support` - 项目内部测试支持库
- `wiremock` - HTTP mock 服务器
- `tempfile` - 临时文件/目录

## 具体技术实现

### 依赖版本管理

所有依赖使用 `workspace = true`，版本在根目录 `Cargo.toml` 中统一管理：

```toml
[dependencies]
anyhow = { workspace = true }
```

### Tokio 特性选择

```toml
tokio = { workspace = true, features = [
    "io-std",
    "macros",
    "process",
    "rt-multi-thread",
    "signal",
] }
```

| 特性 | 用途 |
|------|------|
| `io-std` | 异步标准 IO |
| `macros` | `#[tokio::main]` 等宏 |
| `process` | 异步进程管理（执行 shell 命令）|
| `rt-multi-thread` | 多线程运行时 |
| `signal` | 信号处理（Ctrl+C）|

### ts-rs 配置

```toml
ts-rs = { workspace = true, features = [
    "uuid-impl",
    "serde-json-impl",
    "no-serde-warnings",
] }
```

用于从 Rust 类型生成 TypeScript 定义，支持：
- UUID 类型映射
- Serde JSON 兼容
- 抑制警告

## 关键代码路径与文件引用

### 源文件结构

```
codex-rs/exec/src/
├── main.rs          # 二进制入口
├── lib.rs           # 库入口（主要逻辑）
├── cli.rs           # CLI 参数定义
├── event_processor.rs           # 事件处理器 trait
├── event_processor_with_human_output.rs    # 人类可读输出
├── event_processor_with_jsonl_output.rs    # JSONL 输出
└── exec_events.rs   # 执行事件类型定义
```

### 测试结构

```
codex-rs/exec/tests/
├── all.rs           # 测试聚合入口
├── event_processor_with_json_output.rs
└── suite/           # 测试套件
    ├── mod.rs
    ├── add_dir.rs
    ├── apply_patch.rs
    ├── auth_env.rs
    ├── ephemeral.rs
    ├── mcp_required_exit.rs
    ├── originator.rs
    ├── output_schema.rs
    ├── resume.rs
    ├── sandbox.rs
    └── server_error_exit.rs
```

## 依赖与外部交互

### 内部 crate 依赖图

```
codex-exec
├── codex-core (配置、认证、Git)
├── codex-protocol (事件协议)
├── codex-app-server-protocol (RPC 协议)
├── codex-app-server-client (App Server 客户端)
├── codex-arg0 (arg0 分发)
├── codex-utils-* (工具库)
└── codex-otel (遥测)
```

### 外部系统交互

| 依赖 | 交互对象 | 用途 |
|------|----------|------|
| `tokio::process` | 操作系统 | 执行 shell 命令 |
| `tokio::signal` | 操作系统 | 捕获 Ctrl+C |
| `clap` | 用户 | 解析 CLI 参数 |
| `tracing` | 日志系统 | 结构化日志 |

## 风险、边界与改进建议

### 风险

1. **依赖膨胀**
   - 依赖 20+ 个内部 crate，变更传播风险高
   - 任何 `codex-core` 的破坏性变更都会影响此 crate

2. **功能耦合**
   - `ts-rs` 仅用于生成 TypeScript 类型，但出现在生产依赖中
   - 可考虑改为构建依赖（如果仅编译时生成）

3. **平台特定代码**
   - 沙箱功能依赖 Linux Landlock / macOS Seatbelt
   - 测试需要条件编译（`#[cfg(unix)]`）

### 边界

- 该 crate 是**无头（headless）**模式，不提供 TUI
- 输出通过 `event_processor`  trait 抽象，支持人类可读和 JSONL 两种格式
- 不支持交互式审批（所有审批请求自动拒绝）

### 改进建议

1. **依赖优化**
   ```toml
   # 考虑将 ts-rs 移到 [build-dependencies]
   # 如果 TypeScript 类型仅在构建时生成
   ```

2. **功能门控**
   - 为 OSS 模式添加可选特性，减少闭源依赖
   - 为遥测添加可选特性，允许禁用 `codex-otel`

3. **文档依赖**
   - 添加注释说明关键依赖的用途
   - 例如 `codex-arg0` 的 arg0 分发机制

4. **测试依赖分离**
   - `codex-apply-patch` 仅在测试中使用，可考虑移到 dev-dependencies
   - 检查 `libc` 是否仅在测试中使用

### 相关配置

- `BUILD.bazel` - Bazel 构建配置
- `.bazelrc` - Bazel 全局选项
- `MODULE.bazel` - Bazel 模块定义
