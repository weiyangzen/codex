# codex-rs/otel/Cargo.toml 研究文档

## 场景与职责

`Cargo.toml` 是 Rust crate `codex-otel` 的清单文件，定义了 crate 的元数据、依赖关系、特性和构建配置。该文件是 Cargo 和 Bazel 双构建系统的基础，Bazel 通过 `crate.from_cargo` 机制从该文件解析依赖信息。

在 Codex 项目中，`codex-otel` 作为可观测性基础设施 crate，其 Cargo.toml 需要精心配置以支持：
- OpenTelemetry 日志、追踪、指标三大支柱
- 多种导出协议（OTLP/gRPC、OTLP/HTTP、Statsig）
- 与 `tracing` 生态的深度集成
- 测试隔离能力

## 功能点目的

### 1. 基础元数据
- 定义 crate 名称、版本、edition、license
- 配置库入口（`src/lib.rs`）
- 禁用 doctests 以提高构建速度

### 2. 特性（Features）
- `disable-default-metrics-exporter`：允许测试禁用默认指标导出器，防止测试期间尝试网络连接

### 3. 依赖管理
- 声明 OTEL 生态依赖（`opentelemetry*` crates）
- 声明 `tracing` 生态依赖
- 声明内部 `codex-*` crates 依赖
- 声明 HTTP/WebSocket 客户端依赖

## 具体技术实现

### 包元数据配置

```toml
[package]
name = "codex-otel"
version.workspace = true      # 继承工作区版本
edition.workspace = true      # 继承工作区 edition（2021）
license.workspace = true      # 继承工作区 license

[lib]
doctest = false               # 禁用文档测试
name = "codex_otel"           # crate 名称（下划线）
path = "src/lib.rs"           # 库入口
```

### 特性定义

```toml
[features]
disable-default-metrics-exporter = []
```

**设计意图**：
- 在 `dev-dependencies` 中启用此特性，确保单元/集成测试不会尝试导出指标到网络
- 通过条件编译 `cfg!(feature = "disable-default-metrics-exporter")` 在 `config.rs` 中检查

### 核心依赖分析

#### OpenTelemetry 生态

| 依赖 | 版本 | 特性 | 用途 |
|------|------|------|------|
| `opentelemetry` | workspace | `logs`, `metrics`, `trace` | OTEL API |
| `opentelemetry-appender-tracing` | workspace | - | `tracing` → OTEL 桥接 |
| `opentelemetry-otlp` | workspace | `grpc-tonic`, `http-proto`, `http-json`, `logs`, `metrics`, `trace`, `reqwest-*` | OTLP 导出器 |
| `opentelemetry-semantic-conventions` | workspace | - | 标准属性名 |
| `opentelemetry_sdk` | workspace | `experimental_trace_batch_span_processor_with_async_runtime`, `experimental_metrics_custom_reader`, `rt-tokio`, `testing` | OTEL SDK |

**关键特性说明**：
- `experimental_trace_batch_span_processor_with_async_runtime`：支持 Tokio 运行时的批量 Span 处理器
- `experimental_metrics_custom_reader`：支持自定义指标读取器（用于运行时指标快照）
- `rt-tokio`：Tokio 运行时集成

#### Tracing 生态

| 依赖 | 用途 |
|------|------|
| `tracing` | 结构化日志框架 |
| `tracing-opentelemetry` | `tracing` → OTEL 桥接 |
| `tracing-subscriber` | 日志订阅者实现 |

#### HTTP/WebSocket

| 依赖 | 用途 |
|------|------|
| `reqwest` | HTTP 客户端（阻塞和异步） |
| `tokio-tungstenite` | WebSocket 客户端（用于遥测事件） |
| `http` | HTTP 类型 |

#### 内部依赖

| 依赖 | 用途 |
|------|------|
| `codex-utils-absolute-path` | 绝对路径类型 |
| `codex-utils-string` | 字符串工具（`sanitize_metric_tag_value`） |
| `codex-api` | API 错误类型 |
| `codex-protocol` | 协议类型（`W3cTraceContext`, `ThreadId` 等） |

#### 其他工具依赖

| 依赖 | 用途 |
|------|------|
| `chrono` | 时间戳格式化 |
| `gethostname` | 主机名获取 |
| `os_info` | 操作系统信息 |
| `serde`/`serde_json` | 序列化 |
| `strum_macros` | 枚举宏（`Display` 派生） |
| `thiserror` | 错误类型定义 |
| `eventsource-stream` | SSE 事件流 |

### 开发依赖

```toml
[dev-dependencies]
opentelemetry_sdk = { workspace = true, features = ["experimental_metrics_custom_reader", "testing"] }
pretty_assertions = { workspace = true }
```

- `experimental_metrics_custom_reader`：测试中使用 `InMemoryMetricExporter`
- `testing`：OTEL SDK 测试工具

## 关键代码路径与文件引用

### 依赖使用的代码位置

| 依赖 | 使用位置 | 用途 |
|------|----------|------|
| `opentelemetry` | `src/lib.rs`, `src/metrics/*.rs`, `src/trace_context.rs` | 核心 API |
| `opentelemetry-otlp` | `src/provider.rs`, `src/metrics/client.rs` | 导出器构建 |
| `opentelemetry-appender-tracing` | `src/provider.rs` | 日志层 |
| `tracing` | `src/events/shared.rs`, `src/events/session_telemetry.rs` | 事件记录 |
| `tracing-opentelemetry` | `src/provider.rs` | 追踪层 |
| `reqwest` | `src/otlp.rs` | HTTP 客户端构建 |
| `tokio` | `src/otlp.rs` | 运行时检测 |
| `chrono` | `src/events/shared.rs` | 时间戳 |
| `serde` | `src/events/session_telemetry.rs` | JSON 解析 |

### 特性检查代码

```rust
// src/config.rs
pub(crate) fn resolve_exporter(exporter: &OtelExporter) -> OtelExporter {
    match exporter {
        OtelExporter::Statsig => {
            if cfg!(test) || cfg!(feature = "disable-default-metrics-exporter") {
                return OtelExporter::None;
            }
            // ...
        }
        // ...
    }
}
```

## 依赖与外部交互

### 工作区依赖解析

所有依赖使用 `workspace = true`，实际版本在 `codex-rs/Cargo.toml` 的 `[workspace.dependencies]` 中定义：

```toml
# codex-rs/Cargo.toml (工作区根)
[workspace.dependencies]
opentelemetry = "0.29.0"
opentelemetry-otlp = "0.29.0"
# ...
```

### Bazel 集成

Bazel 通过以下方式使用此 Cargo.toml：

1. `MODULE.bazel` 中的 `crate.from_cargo` 规则解析 Cargo.lock
2. 生成 `@crates` 外部仓库，包含所有依赖的 Bazel 目标
3. `defs.bzl` 中的 `all_crate_deps()` 函数根据 Cargo.toml 生成 `deps` 列表

### 特性传播

- `disable-default-metrics-exporter` 需要在 `dev-dependencies` 中显式启用
- Bazel 构建时通过 `crate_features` 参数传递特性

## 风险、边界与改进建议

### 风险点

1. **版本漂移**：工作区依赖版本更新可能影响此 crate 的兼容性，特别是 OTEL 生态的快速迭代
2. **特性冲突**：`opentelemetry_sdk` 的实验性特性可能在升级时发生破坏性变更
3. **TLS 配置**：`reqwest` 的 `rustls-tls` 特性与系统 OpenSSL 的选择可能影响兼容性

### 边界条件

1. **测试隔离**：`disable-default-metrics-exporter` 仅影响 `Statsig` 导出器的解析，其他 OTLP 导出器仍需网络隔离
2. **Tokio 运行时**：`rt-tokio` 特性假设 Tokio 运行时可用，在非 Tokio 环境下可能无法工作
3. **平台限制**：`gethostname` 和 `os_info` 在某些平台（如 WASM）上可能行为异常

### 改进建议

1. **依赖分组**：将依赖按功能分组（core、metrics、tracing、testing），使用可选特性控制
   ```toml
   [features]
   default = ["metrics", "tracing"]
   metrics = ["opentelemetry/metrics", "opentelemetry-otlp/metrics"]
   tracing = ["opentelemetry/trace", "opentelemetry-otlp/trace"]
   ```

2. **版本锁定**：考虑为关键 OTEL 依赖添加更严格的版本约束

3. **文档增强**：为每个依赖添加注释说明其具体用途

4. **测试特性**：扩展 `disable-default-metrics-exporter` 以覆盖所有网络导出器，或添加 `testing` 特性统一控制

5. **可选依赖**：将 `tokio-tungstenite`、`eventsource-stream` 等可选功能改为可选依赖
