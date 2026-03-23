# mod.rs 深度研究文档

## 场景与职责

`mod.rs` 是 Codex 指标模块的入口文件，负责：

1. **模块组织**：声明子模块（client, config, error, names, runtime_metrics, tags, timer, validation）
2. **公共导出**：选择性地导出内部类型到模块外部
3. **全局状态**：管理全局 `MetricsClient` 实例（`OnceLock` 模式）
4. **访问接口**：提供 `global()` 函数获取全局指标客户端

该模块是指标系统的门面（Facade），对外隐藏内部实现细节，提供简洁的公共 API。

## 功能点目的

### 1. 子模块声明

```rust
mod client;
mod config;
mod error;
pub mod names;           // 公开：指标名常量
pub(crate) mod runtime_metrics;  // crate 内：运行时指标汇总
pub mod tags;            // 公开：标签常量
pub(crate) mod timer;    // crate 内：计时器
pub(crate) mod validation;  // crate 内：验证函数
```

访问控制策略：
- `mod`: 私有，仅模块内部使用
- `pub mod`: 完全公开，外部可访问
- `pub(crate)`: crate 内可见，不对外暴露

### 2. 公共类型导出

```rust
pub use crate::metrics::client::MetricsClient;
pub use crate::metrics::config::MetricsConfig;
pub use crate::metrics::config::MetricsExporter;
pub use crate::metrics::error::MetricsError;
pub use crate::metrics::error::Result;
```

这些类型是指标模块的主要公共 API，使用者只需导入 `metrics` 模块即可。

### 3. 全局指标客户端

```rust
static GLOBAL_METRICS: OnceLock<MetricsClient> = OnceLock::new();

pub(crate) fn install_global(metrics: MetricsClient) {
    let _ = GLOBAL_METRICS.set(metrics);
}

pub fn global() -> Option<MetricsClient> {
    GLOBAL_METRICS.get().cloned()
}
```

- **单例模式**: 使用 `std::sync::OnceLock` 实现线程安全的懒加载单例
- **安装**: `install_global()` 由 `provider.rs` 在初始化时调用
- **访问**: `global()` 返回克隆的 `Option<MetricsClient>`，允许全局访问

## 具体技术实现

### OnceLock 单例模式

```rust
use std::sync::OnceLock;

// 静态全局变量，延迟初始化
static GLOBAL_METRICS: OnceLock<MetricsClient> = OnceLock::new();

// 安装全局实例（只能成功一次）
pub(crate) fn install_global(metrics: MetricsClient) {
    // set 返回 Result，已初始化时返回 Err（忽略）
    let _ = GLOBAL_METRICS.set(metrics);
}

// 获取全局实例
pub fn global() -> Option<MetricsClient> {
    // get 返回 Option<&MetricsClient>
    // cloned 将 &MetricsClient 转为 Option<MetricsClient>
    GLOBAL_METRICS.get().cloned()
}
```

### 模块导出策略

```
codex_otel::metrics
    ├─ MetricsClient (pub)          ← 主要 API
    ├─ MetricsConfig (pub)          ← 配置构建
    ├─ MetricsExporter (pub)        ← 导出器类型
    ├─ MetricsError (pub)           ← 错误处理
    ├─ Result (pub)                 ← 结果类型
    ├─ names (pub mod)              ← 指标名常量
    │   ├─ TOOL_CALL_COUNT_METRIC
    │   ├─ API_CALL_DURATION_METRIC
    │   └─ ...
    ├─ tags (pub mod)               ← 标签常量
    │   ├─ AUTH_MODE_TAG
    │   ├─ MODEL_TAG
    │   └─ ...
    ├─ runtime_metrics (pub(crate) mod)  ← 运行时指标
    │   ├─ RuntimeMetricsSummary
    │   └─ RuntimeMetricTotals
    ├─ timer (pub(crate) mod)       ← 计时器（内部使用）
    ├─ validation (pub(crate) mod)  ← 验证函数（内部使用）
    ├─ client (private mod)         ← 客户端实现
    ├─ config (private mod)         ← 配置实现
    └─ error (private mod)          ← 错误定义
```

## 关键代码路径与文件引用

### 内部依赖

| 文件 | 用途 |
|------|------|
| `client.rs` | `MetricsClient` 实现 |
| `config.rs` | `MetricsConfig`, `MetricsExporter` |
| `error.rs` | `MetricsError`, `Result` |
| `names.rs` | 指标名常量（pub） |
| `runtime_metrics.rs` | 运行时指标类型（pub(crate)） |
| `tags.rs` | 标签常量（pub） |
| `timer.rs` | `Timer` 结构（pub(crate)） |
| `validation.rs` | 验证函数（pub(crate)） |

### 调用方

| 文件 | 使用方式 |
|------|----------|
| `lib.rs` | `pub use crate::metrics::...` 重新导出 |
| `provider.rs` | `install_global()` 安装全局实例 |
| `events/session_telemetry.rs` | `global()` 获取全局实例 |
| `lib.rs` | `start_global_timer()` 使用全局实例 |

## 依赖与外部交互

### 全局实例生命周期

```
1. 应用启动
   ↓
2. OtelProvider::from(settings) (provider.rs)
   ↓
3. MetricsClient::new(config) (client.rs)
   ↓
4. install_global(metrics.clone()) (mod.rs)
   ↓
5. 全局实例可用
   ↓
6. global() -> Option<MetricsClient> (随处可用)
   ↓
7. 应用关闭
   ↓
8. OtelProvider::shutdown() / Drop
```

### 模块层次

```
codex_otel (crate)
    ├─ lib.rs (门面)
    │   └─ 重新导出 metrics 的公共类型
    ├─ metrics (模块)
    │   └─ mod.rs (本文件)
    │       ├─ 组织子模块
    │       └─ 管理全局状态
    ├─ provider.rs
    │   └─ 调用 install_global()
    └─ events/session_telemetry.rs
        └─ 调用 global()
```

## 风险、边界与改进建议

### 当前风险

1. **全局状态**: 使用全局变量可能导致测试间状态污染
2. **忽略安装失败**: `install_global` 忽略 `set` 的返回值，重复安装无提示
3. **克隆开销**: `global()` 克隆 `MetricsClient`（内部是 Arc，成本较低）

### 边界情况

1. **未初始化访问**: `global()` 返回 `None`，调用方需处理
2. **重复安装**: 第二次 `install_global` 被静默忽略
3. **线程安全**: `OnceLock` 保证线程安全，但 `global()` 的克隆不是原子操作

### 改进建议

1. **显式初始化检查**:
   ```rust
   pub enum GlobalInstallError {
       AlreadyInitialized,
   }
   
   pub(crate) fn install_global(metrics: MetricsClient) -> Result<(), GlobalInstallError> {
       GLOBAL_METRICS.set(metrics).map_err(|_| GlobalInstallError::AlreadyInitialized)
   }
   ```

2. **测试隔离**:
   ```rust
   #[cfg(test)]
   pub(crate) fn reset_global_for_test() {
       // 使用可变的静态变量或线程局部存储
   }
   ```

3. **延迟初始化回调**:
   ```rust
   pub fn global_or_init<F>(init: F) -> MetricsClient 
   where F: FnOnce() -> MetricsClient {
       GLOBAL_METRICS.get_or_init(init).clone()
   }
   ```

4. **文档增强**:
   ```rust
   /// Returns the globally installed metrics client, if any.
   /// 
   /// The global client is installed by `OtelProvider` during initialization.
   /// Returns `None` if metrics are disabled or not yet initialized.
   pub fn global() -> Option<MetricsClient> { ... }
   ```

5. **类型安全包装**:
   ```rust
   // 考虑使用 wrapper 类型避免直接暴露 Option
   pub struct GlobalMetrics;
   
   impl GlobalMetrics {
       pub fn counter(name: &str, inc: i64, tags: &[(&str, &str)]) {
           if let Some(m) = global() {
               let _ = m.counter(name, inc, tags);
           }
       }
   }
   ```
