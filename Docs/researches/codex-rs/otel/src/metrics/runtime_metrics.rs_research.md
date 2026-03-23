# runtime_metrics.rs 深度研究文档

## 场景与职责

`runtime_metrics.rs` 实现了 Codex 运行时指标的快照和汇总功能。它是指标系统的查询层，负责：

1. **快照解析**：从 OpenTelemetry `ResourceMetrics` 快照中提取指标数据
2. **指标汇总**：将原始指标数据汇总为结构化的 `RuntimeMetricsSummary`
3. **性能统计**：计算工具调用、API 请求、WebSocket 等各类操作的次数和耗时
4. **数据转换**：处理 OTel SDK 的数据类型转换（f64 → u64）

该模块被 `SessionTelemetry` 和 TUI 组件使用，用于实时展示会话性能指标。

## 功能点目的

### 1. RuntimeMetricTotals - 单项指标统计

```rust
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct RuntimeMetricTotals {
    pub count: u64,        // 操作次数
    pub duration_ms: u64,  // 总耗时（毫秒）
}
```

- 记录某类操作的次数和总耗时
- 提供 `is_empty()` 和 `merge()` 方法用于汇总

### 2. RuntimeMetricsSummary - 完整运行时摘要

```rust
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct RuntimeMetricsSummary {
    pub tool_calls: RuntimeMetricTotals,           // 工具调用
    pub api_calls: RuntimeMetricTotals,            // API 调用
    pub streaming_events: RuntimeMetricTotals,     // SSE 流事件
    pub websocket_calls: RuntimeMetricTotals,      // WebSocket 请求
    pub websocket_events: RuntimeMetricTotals,     // WebSocket 事件
    pub responses_api_overhead_ms: u64,            // API 开销
    pub responses_api_inference_time_ms: u64,      // 推理时间
    pub responses_api_engine_iapi_ttft_ms: u64,    // 引擎 IAPI TTFT
    pub responses_api_engine_service_ttft_ms: u64, // 引擎服务 TTFT
    pub responses_api_engine_iapi_tbt_ms: u64,     // 引擎 IAPI TBT
    pub responses_api_engine_service_tbt_ms: u64,  // 引擎服务 TBT
    pub turn_ttft_ms: u64,                         // Turn TTFT
    pub turn_ttfm_ms: u64,                         // Turn TTFM
}
```

涵盖 Codex 所有关键性能指标，用于性能分析和监控。

### 3. 快照解析

```rust
pub(crate) fn from_snapshot(snapshot: &ResourceMetrics) -> Self {
    // 从 ResourceMetrics 中提取各类指标
    let tool_calls = RuntimeMetricTotals {
        count: sum_counter(snapshot, TOOL_CALL_COUNT_METRIC),
        duration_ms: sum_histogram_ms(snapshot, TOOL_CALL_DURATION_METRIC),
    };
    // ... 其他指标
}
```

## 具体技术实现

### 关键流程

#### 1. 快照解析流程

```rust
pub(crate) fn from_snapshot(snapshot: &ResourceMetrics) -> Self {
    // 1. 工具调用指标
    let tool_calls = RuntimeMetricTotals {
        count: sum_counter(snapshot, TOOL_CALL_COUNT_METRIC),
        duration_ms: sum_histogram_ms(snapshot, TOOL_CALL_DURATION_METRIC),
    };
    
    // 2. API 调用指标
    let api_calls = RuntimeMetricTotals {
        count: sum_counter(snapshot, API_CALL_COUNT_METRIC),
        duration_ms: sum_histogram_ms(snapshot, API_CALL_DURATION_METRIC),
    };
    
    // 3. 流事件指标
    let streaming_events = RuntimeMetricTotals {
        count: sum_counter(snapshot, SSE_EVENT_COUNT_METRIC),
        duration_ms: sum_histogram_ms(snapshot, SSE_EVENT_DURATION_METRIC),
    };
    
    // 4. WebSocket 指标
    let websocket_calls = RuntimeMetricTotals {
        count: sum_counter(snapshot, WEBSOCKET_REQUEST_COUNT_METRIC),
        duration_ms: sum_histogram_ms(snapshot, WEBSOCKET_REQUEST_DURATION_METRIC),
    };
    let websocket_events = RuntimeMetricTotals {
        count: sum_counter(snapshot, WEBSOCKET_EVENT_COUNT_METRIC),
        duration_ms: sum_histogram_ms(snapshot, WEBSOCKET_EVENT_DURATION_METRIC),
    };
    
    // 5. Responses API 详细指标（直方图单值）
    let responses_api_overhead_ms = sum_histogram_ms(snapshot, RESPONSES_API_OVERHEAD_DURATION_METRIC);
    // ... 其他 responses_api 指标
    
    // 6. Turn 指标
    let turn_ttft_ms = sum_histogram_ms(snapshot, TURN_TTFT_DURATION_METRIC);
    let turn_ttfm_ms = sum_histogram_ms(snapshot, TURN_TTFM_DURATION_METRIC);
    
    Self { ... }
}
```

#### 2. Counter 汇总

```rust
fn sum_counter(snapshot: &ResourceMetrics, name: &str) -> u64 {
    snapshot
        .scope_metrics()                          // 获取所有 ScopeMetrics
        .flat_map(|sm| sm.metrics())              // 扁平化为 Metric 迭代器
        .filter(|m| m.name() == name)             // 过滤指定名称
        .map(sum_counter_metric)                  // 汇总每个 metric
        .sum()                                    // 求和
}

fn sum_counter_metric(metric: &Metric) -> u64 {
    match metric.data() {
        AggregatedMetrics::U64(MetricData::Sum(sum)) => {
            sum.data_points()
                .map(|dp| dp.value())             // 获取每个数据点的值
                .sum()
        }
        _ => 0,
    }
}
```

#### 3. Histogram 汇总

```rust
fn sum_histogram_ms(snapshot: &ResourceMetrics, name: &str) -> u64 {
    snapshot
        .scope_metrics()
        .flat_map(|sm| sm.metrics())
        .filter(|m| m.name() == name)
        .map(sum_histogram_metric_ms)
        .sum()
}

fn sum_histogram_metric_ms(metric: &Metric) -> u64 {
    match metric.data() {
        AggregatedMetrics::F64(MetricData::Histogram(histogram)) => {
            histogram
                .data_points()
                .map(|point| f64_to_u64(point.sum()))  // 转换 sum 字段
                .sum()
        }
        _ => 0,
    }
}
```

#### 4. f64 到 u64 的安全转换

```rust
fn f64_to_u64(value: f64) -> u64 {
    // 1. 过滤非有限数和负数
    if !value.is_finite() || value <= 0.0 {
        return 0;
    }
    // 2. 防止溢出
    let clamped = value.min(u64::MAX as f64);
    // 3. 四舍五入转换
    clamped.round() as u64
}
```

### 关键数据结构

```rust
// 单项统计
pub struct RuntimeMetricTotals {
    pub count: u64,        // 操作次数
    pub duration_ms: u64,  // 总耗时
}

// 完整摘要
pub struct RuntimeMetricsSummary {
    pub tool_calls: RuntimeMetricTotals,
    pub api_calls: RuntimeMetricTotals,
    pub streaming_events: RuntimeMetricTotals,
    pub websocket_calls: RuntimeMetricTotals,
    pub websocket_events: RuntimeMetricTotals,
    pub responses_api_overhead_ms: u64,
    pub responses_api_inference_time_ms: u64,
    pub responses_api_engine_iapi_ttft_ms: u64,
    pub responses_api_engine_service_ttft_ms: u64,
    pub responses_api_engine_iapi_tbt_ms: u64,
    pub responses_api_engine_service_tbt_ms: u64,
    pub turn_ttft_ms: u64,
    pub turn_ttfm_ms: u64,
}
```

### 汇总方法

```rust
impl RuntimeMetricTotals {
    pub fn is_empty(self) -> bool {
        self.count == 0 && self.duration_ms == 0
    }
    
    pub fn merge(&mut self, other: Self) {
        self.count = self.count.saturating_add(other.count);
        self.duration_ms = self.duration_ms.saturating_add(other.duration_ms);
    }
}

impl RuntimeMetricsSummary {
    pub fn is_empty(self) -> bool {
        // 检查所有字段是否为 0/empty
    }
    
    pub fn merge(&mut self, other: Self) {
        // 合并所有字段（Totals 用 saturating_add，单值用覆盖）
    }
    
    pub fn responses_api_summary(&self) -> RuntimeMetricsSummary {
        // 只返回 Responses API 相关指标
    }
}
```

## 关键代码路径与文件引用

### 内部依赖

| 文件 | 用途 |
|------|------|
| `names.rs` | 指标名称常量 |

### 外部依赖

| Crate | 用途 |
|-------|------|
| `opentelemetry_sdk::metrics::data::*` | ResourceMetrics, Metric, AggregatedMetrics 等 |

### 调用方

| 文件 | 使用场景 |
|------|----------|
| `events/session_telemetry.rs` | `runtime_metrics_summary()` 方法 |
| `lib.rs` | 重新导出 `RuntimeMetricTotals`, `RuntimeMetricsSummary` |
| `tui/src/history_cell.rs` | 在 UI 中展示运行时指标 |
| `tui_app_server/src/history_cell.rs` | 在 app server UI 中展示 |
| `tui/src/chatwidget/tests.rs` | 测试验证 |

## 依赖与外部交互

### 数据流

```
MetricsClient::snapshot() (client.rs)
    ↓
ResourceMetrics (OpenTelemetry SDK)
    ↓
RuntimeMetricsSummary::from_snapshot() (runtime_metrics.rs)
    ↓
RuntimeMetricsSummary
    ↓
SessionTelemetry::runtime_metrics_summary() (session_telemetry.rs)
    ↓
TUI 展示 / 日志记录
```

### OTel 数据结构映射

```
ResourceMetrics
└── scope_metrics: Vec<ScopeMetrics>
    └── metrics: Vec<Metric>
        ├── name: &str                    ← 匹配指标名
        └── data: AggregatedMetrics
            ├── U64(MetricData::Sum)      ← Counter 数据
            │   └── data_points
            │       └── value: u64        ← 累加
            └── F64(MetricData::Histogram) ← Histogram 数据
                └── data_points
                    └── sum: f64          ← 转换后累加
```

## 风险、边界与改进建议

### 当前风险

1. **f64 精度丢失**: 直方图 sum 从 f64 转 u64 可能丢失小数部分
2. **溢出风险**: 虽然使用 `saturating_add`，但极端情况下数据会饱和
3. **指标名硬编码**: 依赖 `names.rs` 的常量，改名时需同步更新
4. **单值覆盖**: `merge` 方法对单值字段（如 `responses_api_overhead_ms`）使用覆盖而非累加

### 边界情况

1. **空快照**: `from_snapshot` 返回全 0 的 summary
2. **缺失指标**: 未找到的指标贡献 0 值
3. **多数据点**: Counter/Histogram 可能有多个数据点（不同标签组合），全部累加
4. **非预期类型**: 数据类型不匹配时返回 0

### 改进建议

1. **类型安全**:
   ```rust
   // 使用 newtype 包装毫秒值
   pub struct Milliseconds(u64);
   pub struct Count(u64);
   ```

2. **保留精度**:
   ```rust
   // 对关键指标保留 f64
   pub responses_api_overhead_ms: f64,
   ```

3. **增量更新**:
   ```rust
   // 支持增量更新而非全量替换
   pub fn update_from_snapshot(&mut self, snapshot: &ResourceMetrics) {
       let delta = Self::from_snapshot(snapshot);
       self.merge(delta);
   }
   ```

4. **指标发现**:
   ```rust
   // 动态发现快照中的所有指标
   pub fn available_metrics(snapshot: &ResourceMetrics) -> Vec<&str> {
       // 返回所有发现的指标名
   }
   ```

5. **验证**:
   ```rust
   // 验证指标名存在
   debug_assert!(
       metric_exists(snapshot, TOOL_CALL_COUNT_METRIC),
       "Expected metric not found: {}", TOOL_CALL_COUNT_METRIC
   );
   ```

6. **文档**:
   ```rust
   /// Time To First Token (TTFT) for the turn.
   /// 
   /// This measures the time from sending the user message
   /// to receiving the first token of the response.
   pub turn_ttft_ms: u64,
   ```
