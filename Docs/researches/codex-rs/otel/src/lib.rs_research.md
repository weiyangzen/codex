# codex-rs/otel/src/lib.rs 研究文档

## 场景与职责

`lib.rs` 是 `codex-otel` crate 的入口模块，负责模块组织和公共 API 导出。它定义了整个 crate 的模块结构，并重新导出关键类型供外部使用。

**核心职责：**
1. 声明和暴露 crate 的公共模块（config、metrics、provider、trace_context）
2. 声明内部模块（events、otlp、targets）
3. 重新导出关键类型，简化外部使用
4. 定义全局指标计时器便捷函数
5. 定义遥测相关的业务枚举（ToolDecisionSource、TelemetryAuthMode）

## 功能点目的

### 1. 模块组织结构

**公共模块（`pub mod`）：**
- `config`: OTEL 导出器配置（OtelSettings、OtelExporter 等）
- `metrics`: 指标收集客户端（MetricsClient、MetricsConfig 等）
- `provider`: OTEL Provider 主入口（OtelProvider）
- `trace_context`: W3C Trace Context 传播支持

**内部模块（`mod`）：**
- `events`: 会话遥测事件（SessionTelemetry）
- `otlp`: OTLP 协议实现细节（TLS、HTTP 客户端构建）
- `targets`: 日志目标过滤常量

### 2. 公共类型重新导出

```rust
// 事件相关
pub use events::session_telemetry::{AuthEnvTelemetryMetadata, SessionTelemetry, SessionTelemetryMetadata};

// 指标相关
pub use metrics::runtime_metrics::{RuntimeMetricTotals, RuntimeMetricsSummary};
pub use metrics::timer::Timer;

// Provider
pub use provider::OtelProvider;

// Trace Context
pub use trace_context::{
    context_from_w3c_trace_context,
    current_span_trace_id,
    current_span_w3c_trace_context,
    set_parent_from_context,
    set_parent_from_w3c_trace_context,
    span_w3c_trace_context,
    traceparent_context_from_env,
};

// 工具函数
pub use codex_utils_string::sanitize_metric_tag_value;
```

### 3. 业务枚举定义

**`ToolDecisionSource`**: 工具决策来源
- `Config`: 来自配置文件
- `User`: 来自用户交互

**`TelemetryAuthMode`**: 认证模式（避免循环依赖，复制自 codex-core）
- `ApiKey`: API Key 认证
- `Chatgpt`: ChatGPT 认证

### 4. 全局指标计时器

```rust
pub fn start_global_timer(name: &str, tags: &[(&str, &str)]) -> MetricsResult<Timer> {
    let Some(metrics) = crate::metrics::global() else {
        return Err(MetricsError::ExporterDisabled);
    };
    metrics.start_timer(name, tags)
}
```

这个函数允许在任何地方启动一个计时器，无需持有 MetricsClient 实例，依赖于全局安装的指标客户端。

## 具体技术实现

### 模块声明模式

```rust
pub mod config;      // 公共配置模块
mod events;          // 内部事件模块
pub mod metrics;     // 公共指标模块
pub mod provider;    // 公共 Provider 模块
pub mod trace_context; // 公共 Trace Context 模块

mod otlp;            // 内部 OTLP 实现
mod targets;         // 内部目标过滤
```

### 类型导出链

```
metrics/mod.rs 导出 → lib.rs 重新导出 → 外部使用
    MetricsClient ──────→ pub use ─────→ codex_otel::MetricsClient
    MetricsConfig ──────→ pub use ─────→ codex_otel::metrics::MetricsConfig
```

### 全局状态访问

```rust
use crate::metrics::MetricsError;
use crate::metrics::Result as MetricsResult;

pub fn start_global_timer(...) -> MetricsResult<Timer> {
    // 访问 metrics::global() 获取全局客户端
}
```

## 关键代码路径与文件引用

### 模块树
```
codex_otel (crate root)
├── config/          (pub)
│   └── OtelSettings, OtelExporter, OtelTlsConfig
├── events/          (private)
│   └── session_telemetry/
│       └── SessionTelemetry
├── metrics/         (pub)
│   ├── client.rs    → MetricsClient
│   ├── config.rs    → MetricsConfig
│   ├── names.rs     → 指标名称常量
│   ├── tags.rs      → 标签管理
│   ├── timer.rs     → Timer
│   └── runtime_metrics.rs → RuntimeMetricsSummary
├── provider.rs      (pub) → OtelProvider
├── trace_context.rs (pub) → W3C Trace Context 函数
├── otlp.rs          (private) → OTLP 实现
└── targets.rs       (private) → 目标常量
```

### 外部使用方

**`codex-rs/core/src/otel_init.rs`:**
```rust
use codex_otel::OtelProvider;
use codex_otel::config::{OtelExporter, OtelHttpProtocol, OtelSettings, OtelTlsConfig};
```

**`codex-rs/core/src/codex.rs`:**
```rust
use codex_otel::SessionTelemetry;
use codex_otel::start_global_timer;
```

**`codex-rs/tui/src/app.rs`:**
```rust
use codex_otel::OtelProvider;
use codex_otel::config::{OtelExporter, OtelSettings};
```

**`codex-rs/exec/src/lib.rs`:**
```rust
use codex_otel::trace_context::current_span_w3c_trace_context;
```

## 依赖与外部交互

### 内部依赖
- `codex_utils_string::sanitize_metric_tag_value`: 指标标签值清理

### 外部 crate 依赖
- `serde::Serialize`: 用于 `ToolDecisionSource` 序列化
- `strum_macros::Display`: 用于枚举的 Display 实现

### 类型别名
```rust
pub use crate::metrics::Result as MetricsResult;
```

## 风险、边界与改进建议

### 设计风险
1. **全局状态依赖**: `start_global_timer` 依赖全局安装的指标客户端，如果未安装会返回错误
   - 建议：考虑提供无操作（no-op）实现，避免调用方处理错误

2. **模块可见性**: `events` 模块是私有的，但 `SessionTelemetry` 被重新导出
   - 这可能导致文档和实际模块结构不一致

### 边界情况
1. **循环依赖避免**: `TelemetryAuthMode` 是 `codex_core::AuthMode` 的复制，明确注释了避免循环依赖
   - 如果 `AuthMode` 变更，需要同步更新这里

2. **类型重命名**: `MetricsResult` 是 `metrics::Result` 的别名，保持了命名一致性

### 改进建议
1. **文档组织**: 考虑使用 `#[doc(inline)]` 或 `#[doc(no_inline)]` 控制重新导出类型的文档显示
2. **Feature Gate**: 某些模块（如 `trace_context`）可以考虑添加 feature flag，减少编译依赖
3. **全局初始化检查**: `start_global_timer` 可以添加调试日志，帮助诊断全局客户端未安装的问题
4. **Prelude 模块**: 考虑添加 `prelude` 模块，方便外部用户一次性导入常用类型

### 代码组织
当前模块组织清晰，但可以考虑：
- 将 `ToolDecisionSource` 和 `TelemetryAuthMode` 移动到 `config` 模块
- 将 `start_global_timer` 移动到 `metrics` 模块的根
