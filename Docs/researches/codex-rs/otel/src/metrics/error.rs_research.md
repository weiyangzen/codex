# error.rs 深度研究文档

## 场景与职责

`error.rs` 定义了 Codex 指标系统的错误类型和结果别名。它是整个指标模块的错误处理基础，负责：

1. **错误类型定义**：使用 `thiserror` 宏定义具体的错误变体
2. **结果别名**：提供 `Result<T>` 类型别名简化代码
3. **错误分类**：将指标相关的错误分为验证错误、配置错误、运行时错误等
4. **错误链**：通过 `#[source]` 属性保留底层错误上下文

该模块被 `client.rs`, `config.rs`, `validation.rs` 等所有指标子模块使用，是错误处理的统一出口。

## 功能点目的

### 1. Result 类型别名

```rust
pub type Result<T> = std::result::Result<T, MetricsError>;
```

简化函数签名，统一使用 `Result<T>` 替代 `std::result::Result<T, MetricsError>`。

### 2. MetricsError 枚举

| 错误变体 | 场景 | 字段 |
|----------|------|------|
| `EmptyMetricName` | 指标名为空 | - |
| `InvalidMetricName` | 指标名包含非法字符 | `name: String` |
| `EmptyTagComponent` | 标签 key 或 value 为空 | `label: String` |
| `InvalidTagComponent` | 标签包含非法字符 | `label: String`, `value: String` |
| `ExporterDisabled` | 导出器被禁用 | - |
| `NegativeCounterIncrement` | Counter 增量为负 | `name: String`, `inc: i64` |
| `ExporterBuild` | OTLP 导出器构建失败 | `source: ExporterBuildError` |
| `InvalidConfig` | 配置无效 | `message: String` |
| `ProviderShutdown` | Provider 关闭失败 | `source: OTelSdkError` |
| `RuntimeSnapshotUnavailable` | 运行时快照未启用 | - |
| `RuntimeSnapshotCollect` | 快照收集失败 | `source: OTelSdkError` |

### 3. 错误分类

**验证错误**（用户输入问题）：
- `EmptyMetricName`
- `InvalidMetricName`
- `EmptyTagComponent`
- `InvalidTagComponent`
- `NegativeCounterIncrement`

**配置错误**（设置问题）：
- `ExporterDisabled`
- `InvalidConfig`

**运行时错误**（系统问题）：
- `ExporterBuild`
- `ProviderShutdown`
- `RuntimeSnapshotUnavailable`
- `RuntimeSnapshotCollect`

## 具体技术实现

### thiserror 宏使用

```rust
use thiserror::Error;

#[derive(Debug, Error)]
pub enum MetricsError {
    #[error("metric name cannot be empty")]
    EmptyMetricName,
    
    #[error("metric name contains invalid characters: {name}")]
    InvalidMetricName { name: String },
    
    #[error("{label} cannot be empty")]
    EmptyTagComponent { label: String },
    
    #[error("{label} contains invalid characters: {value}")]
    InvalidTagComponent { label: String, value: String },
    
    #[error("metrics exporter is disabled")]
    ExporterDisabled,
    
    #[error("counter increment must be non-negative for {name}: {inc}")]
    NegativeCounterIncrement { name: String, inc: i64 },
    
    #[error("failed to build OTLP metrics exporter")]
    ExporterBuild {
        #[source]
        source: opentelemetry_otlp::ExporterBuildError,
    },
    
    #[error("invalid OTLP metrics configuration: {message}")]
    InvalidConfig { message: String },
    
    #[error("failed to flush or shutdown metrics provider")]
    ProviderShutdown {
        #[source]
        source: opentelemetry_sdk::error::OTelSdkError,
    },
    
    #[error("runtime metrics snapshot reader is not enabled")]
    RuntimeSnapshotUnavailable,
    
    #[error("failed to collect runtime metrics snapshot from metrics reader")]
    RuntimeSnapshotCollect {
        #[source]
        source: opentelemetry_sdk::error::OTelSdkError,
    },
}
```

### 错误转换示例

```rust
// client.rs 中的错误转换
self.meter_provider
    .shutdown()
    .map_err(|source| MetricsError::ProviderShutdown { source })?;

// 底层错误自动转换
opentelemetry_otlp::MetricExporter::builder()
    .build()
    .map_err(|source| MetricsError::ExporterBuild { source })?;
```

## 关键代码路径与文件引用

### 内部依赖

| 文件 | 用途 |
|------|------|
| `mod.rs` | 导出 `MetricsError`, `Result` |

### 外部依赖

| Crate | 用途 |
|-------|------|
| `thiserror::Error` | 派生 Error trait 和 Display |
| `opentelemetry_otlp::ExporterBuildError` | 导出器构建错误源 |
| `opentelemetry_sdk::error::OTelSdkError` | SDK 错误源 |

### 调用方

| 文件 | 使用场景 |
|------|----------|
| `validation.rs` | 返回验证错误 |
| `config.rs` | `with_tag()` 验证失败 |
| `client.rs` | 各种操作错误 |
| `timer.rs` | `Timer::record()` 错误 |
| `tests/suite/validation.rs` | 测试错误匹配 |

## 依赖与外部交互

### 错误传播链

```
用户调用
    ↓
MetricsClient::counter() (client.rs)
    ↓
validate_metric_name() (validation.rs)
    ↓
Err(MetricsError::InvalidMetricName { name })
    ↓
返回给调用方
```

### SDK 错误包装

```
opentelemetry_sdk::error::OTelSdkError
    ↓
MetricsError::ProviderShutdown { source }
    ↓
保留原始错误信息 + 添加上下文
```

## 风险、边界与改进建议

### 当前风险

1. **错误粒度**: 部分错误信息不够具体（如 `InvalidConfig` 只有 message 字符串）
2. **错误暴露**: 所有字段都是 `pub`（通过派生），外部可以构造任意错误
3. **缺少重试相关错误**: 网络错误被包装在 SDK 错误中，无法区分可重试错误

### 边界情况

1. **空字符串处理**: `InvalidMetricName` 和 `EmptyMetricName` 是分开的，确保空字符串有明确错误
2. **标签组件区分**: `EmptyTagComponent` 和 `InvalidTagComponent` 通过 `label` 字段区分 key/value
3. **负值处理**: `NegativeCounterIncrement` 捕获负增量但允许零

### 改进建议

1. **错误分类枚举**:
   ```rust
   #[derive(Debug, Clone, Copy, PartialEq, Eq)]
   pub enum MetricsErrorKind {
       Validation,
       Configuration,
       Runtime,
       Network,
   }
   
   impl MetricsError {
       pub fn kind(&self) -> MetricsErrorKind { ... }
   }
   ```

2. **结构化配置错误**:
   ```rust
   #[error("invalid OTLP metrics configuration")]
   InvalidConfig {
       field: &'static str,
       expected: &'static str,
       actual: String,
   },
   ```

3. **添加错误代码**:
   ```rust
   impl MetricsError {
       pub fn code(&self) -> &'static str {
           match self {
               Self::EmptyMetricName => "METRICS_EMPTY_NAME",
               Self::InvalidMetricName { .. } => "METRICS_INVALID_NAME",
               // ...
           }
       }
   }
   ```

4. **限制字段可见性**:
   ```rust
   #[derive(Debug, Error)]
   #[non_exhaustive]  // 防止外部匹配所有变体
   pub enum MetricsError {
       // 字段使用 pub(crate) 或私有
   }
   ```

5. **添加帮助信息**:
   ```rust
   #[error("metric name contains invalid characters: {name}")]
   #[error_doc("Metric names can only contain alphanumeric characters, '.', '_', and '-'")]
   InvalidMetricName { name: String },
   ```
