# mod_tests.rs 研究文档

## 场景与职责

`mod_tests.rs` 是 `tasks/mod.rs` 的配套单元测试模块，负责验证任务模块中的指标收集功能。该测试文件通过 `#[path = "mod_tests.rs"]` 属性在 `mod.rs` 中内联包含。

### 测试范围
- `emit_turn_network_proxy_metric` 函数的正确性
- 遥测指标的标签和值验证
- OpenTelemetry 指标导出验证

## 功能点目的

### 1. 验证网络代理指标记录
确保 `emit_turn_network_proxy_metric` 函数正确记录网络代理使用状态到 OpenTelemetry 指标系统。

### 2. 验证指标属性
确保指标包含正确的标签（labels/attributes）：
- `active`：网络代理是否活跃（"true"/"false"）
- `tmp_mem_enabled`：临时内存功能是否启用

## 具体技术实现

### 测试基础设施

```rust
fn test_session_telemetry() -> SessionTelemetry {
    let exporter = InMemoryMetricExporter::default();
    let metrics = MetricsClient::new(
        MetricsConfig::in_memory("test", "codex-core", env!("CARGO_PKG_VERSION"), exporter)
            .with_runtime_reader(),
    )
    .expect("in-memory metrics client");
    
    SessionTelemetry::new(
        ThreadId::new(),
        "gpt-5.1",
        "gpt-5.1",
        None, None, None,
        "test_originator".to_string(),
        false,
        "tty".to_string(),
        SessionSource::Cli,
    )
    .with_metrics_without_metadata_tags(metrics)
}
```

**关键组件**：
- `InMemoryMetricExporter`：内存中的指标导出器，用于测试验证
- `MetricsConfig::in_memory`：配置内存指标后端
- `SessionTelemetry::with_metrics_without_metadata_tags`：创建带内存后端的遥测实例

### 辅助函数

```rust
fn find_metric<'a>(resource_metrics: &'a ResourceMetrics, name: &str) -> &'a Metric
```
在导出的指标中按名称查找特定指标。

```rust
fn attributes_to_map<'a>(
    attributes: impl Iterator<Item = &'a KeyValue>,
) -> BTreeMap<String, String>
```
将 OpenTelemetry 属性转换为可比较的 `BTreeMap`。

```rust
fn metric_point(resource_metrics: &ResourceMetrics) -> (BTreeMap<String, String>, u64)
```
提取指标的第一个数据点及其属性。

### 测试用例 1：`emit_turn_network_proxy_metric_records_active_turn`

```rust
#[test]
fn emit_turn_network_proxy_metric_records_active_turn() {
    let session_telemetry = test_session_telemetry();

    emit_turn_network_proxy_metric(&session_telemetry, true, ("tmp_mem_enabled", "true"));

    let snapshot = session_telemetry
        .snapshot_metrics()
        .expect("runtime metrics snapshot");
    let (attrs, value) = metric_point(&snapshot);

    assert_eq!(value, 1);
    assert_eq!(
        attrs,
        BTreeMap::from([
            ("active".to_string(), "true".to_string()),
            ("tmp_mem_enabled".to_string(), "true".to_string()),
        ])
    );
}
```

**验证点**：
- 指标值为 1（计数器增量）
- `active` 属性为 "true"
- `tmp_mem_enabled` 属性为 "true"

### 测试用例 2：`emit_turn_network_proxy_metric_records_inactive_turn`

```rust
#[test]
fn emit_turn_network_proxy_metric_records_inactive_turn() {
    let session_telemetry = test_session_telemetry();

    emit_turn_turn_network_proxy_metric(&session_telemetry, false, ("tmp_mem_enabled", "false"));
    // ... 类似验证，但属性值为 "false"
}
```

**验证点**：
- 指标值为 1
- `active` 属性为 "false"
- `tmp_mem_enabled` 属性为 "false"

## 关键代码路径与文件引用

### 文件关系
```
tasks/mod.rs
  ├── fn emit_turn_network_proxy_metric (被测函数)
  └── mod tests
        └── mod_tests.rs (本文件)
```

### 被测函数定义
```rust
// tasks/mod.rs:63-78
fn emit_turn_network_proxy_metric(
    session_telemetry: &SessionTelemetry,
    network_proxy_active: bool,
    tmp_mem: (&str, &str),
) {
    let active = if network_proxy_active { "true" } else { "false" };
    session_telemetry.counter(
        TURN_NETWORK_PROXY_METRIC,
        /*inc*/ 1,
        &[("active", active), tmp_mem],
    );
}
```

### 相关常量
- `codex_otel::metrics::names::TURN_NETWORK_PROXY_METRIC`：指标名称 `"turn.network_proxy"`

## 依赖与外部交互

### 测试依赖
| Crate/模块 | 用途 |
|-----------|------|
| `codex_otel::SessionTelemetry` | 被测函数的参数类型 |
| `codex_otel::metrics::MetricsClient` | 创建内存指标客户端 |
| `codex_otel::metrics::MetricsConfig` | 配置内存指标 |
| `codex_otel::metrics::names::TURN_NETWORK_PROXY_METRIC` | 指标名称常量 |
| `codex_protocol::ThreadId` | 创建测试会话 ID |
| `codex_protocol::protocol::SessionSource` | 会话来源枚举 |
| `opentelemetry::KeyValue` | OpenTelemetry 属性类型 |
| `opentelemetry_sdk::metrics::InMemoryMetricExporter` | 内存指标导出器 |
| `opentelemetry_sdk::metrics::data::*` | 指标数据结构 |
| `pretty_assertions::assert_eq` | 清晰的断言输出 |

### 被测模块
- `tasks/mod.rs`：通过 `use super::emit_turn_network_proxy_metric` 访问

## 风险、边界与改进建议

### 当前测试覆盖缺口

| 功能 | 测试状态 | 风险等级 |
|------|---------|---------|
| `spawn_task` | ❌ 未覆盖 | 高 |
| `abort_all_tasks` | ❌ 未覆盖 | 高 |
| `on_task_finished` | ❌ 未覆盖 | 高 |
| `handle_task_abort` | ❌ 未覆盖 | 中 |
| `emit_turn_network_proxy_metric` | ✅ 已覆盖 | 低 |
| Token 使用指标 | ❌ 未覆盖 | 中 |
| Tool call 指标 | ❌ 未覆盖 | 中 |

### 建议添加的测试

1. **任务生命周期测试**
   ```rust
   #[tokio::test]
   async fn spawn_task_registers_active_task() {
       // 验证 spawn_task 后 ActiveTurn 包含任务
   }
   
   #[tokio::test]
   async fn task_completion_clears_active_turn() {
       // 验证任务完成后 ActiveTurn 被清除
   }
   ```

2. **取消机制测试**
   ```rust
   #[tokio::test]
   async fn abort_all_tasks_cancels_running_task() {
       // 验证取消令牌被触发
   }
   
   #[tokio::test]
   async fn abort_sends_turn_aborted_event() {
       // 验证取消后发送正确事件
   }
   ```

3. **指标收集测试**
   ```rust
   #[tokio::test]
   async fn on_task_finished_records_token_usage() {
       // 验证 token 使用指标被记录
   }
   ```

4. **并发测试**
   ```rust
   #[tokio::test]
   async fn concurrent_task_replacement() {
       // 验证任务替换的线程安全
   }
   ```

### 测试基础设施改进

1. **Mock Session**
   ```rust
   struct MockSession {
       events: Arc<Mutex<Vec<EventMsg>>>,
       metrics: Arc<Mutex<Vec<RecordedMetric>>>,
   }
   ```

2. **Fake Task 实现**
   ```rust
   struct FakeTask {
       run_duration: Duration,
       should_panic: bool,
   }
   #[async_trait]
   impl SessionTask for FakeTask { ... }
   ```

3. **指标断言宏**
   ```rust
   macro_rules! assert_metric {
       ($snapshot:expr, $name:expr, $value:expr, $($attr:expr),*) => { ... }
   }
   ```

### 边界条件测试

| 场景 | 建议测试 |
|------|---------|
| 任务 panic | 验证 `AbortOnDropHandle` 清理 |
| 快速连续 spawn | 验证无竞态条件 |
| 取消后快速 spawn | 验证状态一致性 |
| 空输入 | 验证任务正常执行 |
| 超长任务 | 验证指标计时准确性 |
