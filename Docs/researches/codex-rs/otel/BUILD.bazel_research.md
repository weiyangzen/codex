# codex-rs/otel/BUILD.bazel 研究文档

## 场景与职责

`BUILD.bazel` 是 Bazel 构建系统中用于定义 `codex-otel` crate 构建规则的构建配置文件。该文件位于 `codex-rs/otel/` 目录下，负责声明如何将 Rust 源代码编译为可重用的库 crate。

在 Codex 项目的整体架构中，`codex-otel` 是一个核心的可观测性（Observability）基础设施 crate，为其他组件（如 TUI、exec、core、app-server 等）提供 OpenTelemetry 集成能力。该 BUILD 文件的作用是将这些源代码打包为 Bazel 可识别的目标。

## 功能点目的

该 BUILD 文件的核心目的是：

1. **声明库目标**：使用 `codex_rust_crate` 宏定义一个名为 `otel` 的 Rust 库
2. **指定 crate 名称**：将 Rust crate 名称设为 `codex_otel`（遵循 `codex-*` 前缀的命名约定）
3. **继承构建规则**：通过 `load("//:defs.bzl", "codex_rust_crate")` 引入项目统一的 Rust crate 构建宏

## 具体技术实现

### 构建规则定义

```bazel
load("//:defs.bzl", "codex_rust_crate")

codex_rust_crate(
    name = "otel",
    crate_name = "codex_otel",
)
```

### 关键参数说明

| 参数 | 值 | 说明 |
|------|-----|------|
| `name` | `"otel"` | Bazel 目标名称，在构建命令中使用（如 `bazel build //codex-rs/otel`） |
| `crate_name` | `"codex_otel"` | 生成的 Rust crate 名称，符合 `codex-<name>` 的命名规范 |

### 底层构建逻辑（通过 codex_rust_crate 宏）

`codex_rust_crate` 宏定义在 `//:defs.bzl` 中，它为 `codex-otel` 自动完成以下工作：

1. **库编译**：使用 `rust_library` 规则编译 `src/lib.rs` 及其依赖模块
2. **源码收集**：通过 `glob(["src/**/*.rs"])` 自动收集所有 Rust 源文件
3. **依赖解析**：从 `@crates` 外部仓库解析 Cargo.toml 中声明的依赖
4. **单元测试**：创建 `otel-unit-tests` 测试目标，运行 `src/` 中的 `#[cfg(test)]` 模块
5. **集成测试**：自动发现并构建 `tests/*.rs` 中的集成测试
6. **特性传递**：支持通过 `crate_features` 参数启用 Cargo features

### 目录结构约定

```
codex-rs/otel/
├── BUILD.bazel          # 本文件
├── Cargo.toml           # Cargo 配置（依赖声明）
├── src/
│   ├── lib.rs           # 库入口
│   ├── config.rs        # OTEL 配置
│   ├── provider.rs      # Provider 实现
│   ├── otlp.rs          # OTLP 协议支持
│   ├── trace_context.rs # Trace 上下文
│   ├── targets.rs       # 日志目标定义
│   ├── metrics/         # 指标子模块
│   └── events/          # 事件子模块
└── tests/               # 集成测试（如有）
```

## 关键代码路径与文件引用

### 直接依赖的源文件

- `src/lib.rs` - 库入口，模块声明和公共导出
- `src/config.rs` - `OtelSettings`、`OtelExporter` 等配置类型
- `src/provider.rs` - `OtelProvider` 主实现
- `src/otlp.rs` - OTLP/gRPC/HTTP 导出器构建
- `src/trace_context.rs` - W3C Trace Context 传播
- `src/targets.rs` - 日志目标过滤
- `src/metrics/*.rs` - 指标客户端实现
- `src/events/*.rs` - Session 遥测事件

### 依赖的构建脚本

- 如果存在 `build.rs`，`codex_rust_crate` 会自动检测并配置 `cargo_build_script`

### 测试目标生成

- `otel-unit-tests-bin`：单元测试二进制
- `otel-unit-tests`：带工作区根启动器的单元测试包装器
- `otel-<test-name>-test`：每个 `tests/*.rs` 文件的集成测试

## 依赖与外部交互

### Bazel 外部依赖

| 依赖 | 来源 | 用途 |
|------|------|------|
| `@crates` | `MODULE.bazel` 中的 `crate.from_cargo` | 所有 Rust crates.io 依赖 |
| `//:defs.bzl` | 项目根目录 | 统一的 Rust crate 构建宏 |

### Cargo.toml 依赖（通过 Bazel 转换）

主要依赖包括：
- `opentelemetry` 系列 crates（核心 OTEL 实现）
- `tracing` 系列 crates（日志/追踪集成）
- `tokio`（异步运行时）
- `reqwest`（HTTP 客户端）
- `codex-*` 内部 crates（协议、工具等）

### 反向依赖（调用方）

以下 crates 通过 Bazel 依赖 `codex-otel`：
- `//codex-rs/tui` - TUI 应用的遥测
- `//codex-rs/exec` - Exec 模式的遥测
- `//codex-rs/core` - 核心库的可观测性
- `//codex-rs/app-server` - 应用服务器的遥测
- `//codex-rs/tui_app_server` - TUI 应用服务器的遥测
- `//codex-rs/cloud-requirements` - 云需求检查的遥测

## 风险、边界与改进建议

### 风险点

1. **硬编码 API Key**：`src/config.rs` 中包含硬编码的 Statsig API key（`STATSIG_API_KEY`），虽然这是设计上的便利，但存在泄露风险
2. **TLS 配置复杂性**：`otlp.rs` 中处理多种 TLS 场景（gRPC/HTTP、同步/异步），容易引入安全漏洞
3. **测试隔离**：`disable-default-metrics-exporter` feature 用于测试隔离，但如果忘记启用可能导致测试试图连接真实网络端点

### 边界条件

1. **Tokio 运行时检测**：`otlp.rs` 中的 `current_tokio_runtime_is_multi_thread()` 决定了使用同步还是异步 HTTP 客户端，在边缘运行时环境下可能行为不一致
2. **指标名称/标签验证**：`validation.rs` 对指标名称和标签字符有严格限制（仅允许 ASCII 字母数字和 `._-/`），非 ASCII 字符会被拒绝
3. **全局状态**：`metrics/mod.rs` 使用 `OnceLock` 存储全局指标客户端，一旦设置不可更改

### 改进建议

1. **增强文档**：在 BUILD 文件中添加注释说明 `codex_rust_crate` 宏的行为
2. **安全审计**：考虑将 Statsig API key 移至构建时注入而非源码硬编码
3. **测试覆盖**：添加更多边界条件测试（如特殊字符处理、TLS 错误场景）
4. **性能优化**：考虑为高频指标操作添加批处理或采样机制
5. **可观测性增强**：为 OTEL 导出器本身添加健康检查和重试指标
