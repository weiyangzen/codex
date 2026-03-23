# names.rs 深度研究文档

## 场景与职责

`names.rs` 定义了 Codex 指标系统中使用的所有指标名称常量。它是指标命名规范的集中管理文件，负责：

1. **命名标准化**：统一指标命名格式（`codex.{component}.{metric}`）
2. **命名发现**：提供单一位置查找所有可用指标
3. **命名一致性**：避免硬编码字符串导致的拼写错误和不一致
4. **文档化**：通过常量名自文档化指标用途

该模块被 `events/session_telemetry.rs` 和 `runtime_metrics.rs` 大量使用，是指标系统的命名权威源。

## 功能点目的

### 1. 指标命名规范

所有指标遵循统一命名模式：

```
codex.{component}.{metric_name}
codex.{component}.{metric_name}.duration_ms  // 持续时间指标
```

示例：
- `codex.tool.call` - 工具调用计数
- `codex.tool.call.duration_ms` - 工具调用耗时

### 2. 指标分类

| 类别 | 指标 | 用途 |
|------|------|------|
| **Tool** | `TOOL_CALL_COUNT_METRIC` | 工具调用次数 |
| | `TOOL_CALL_DURATION_METRIC` | 工具调用耗时 |
| **API** | `API_CALL_COUNT_METRIC` | API 请求次数 |
| | `API_CALL_DURATION_METRIC` | API 请求耗时 |
| **SSE** | `SSE_EVENT_COUNT_METRIC` | SSE 事件次数 |
| | `SSE_EVENT_DURATION_METRIC` | SSE 事件处理耗时 |
| **WebSocket** | `WEBSOCKET_REQUEST_COUNT_METRIC` | WebSocket 请求次数 |
| | `WEBSOCKET_REQUEST_DURATION_METRIC` | WebSocket 请求耗时 |
| | `WEBSOCKET_EVENT_COUNT_METRIC` | WebSocket 事件次数 |
| | `WEBSOCKET_EVENT_DURATION_METRIC` | WebSocket 事件处理耗时 |
| **Responses API** | `RESPONSES_API_OVERHEAD_DURATION_METRIC` | API 开销耗时 |
| | `RESPONSES_API_INFERENCE_TIME_DURATION_METRIC` | 推理时间 |
| | `RESPONSES_API_ENGINE_IAPI_TTFT_DURATION_METRIC` | 引擎 IAPI TTFT |
| | `RESPONSES_API_ENGINE_SERVICE_TTFT_DURATION_METRIC` | 引擎服务 TTFT |
| | `RESPONSES_API_ENGINE_IAPI_TBT_DURATION_METRIC` | 引擎 IAPI TBT |
| | `RESPONSES_API_ENGINE_SERVICE_TBT_DURATION_METRIC` | 引擎服务 TBT |
| **Turn** | `TURN_E2E_DURATION_METRIC` | 端到端耗时 |
| | `TURN_TTFT_DURATION_METRIC` | 首 token 时间 |
| | `TURN_TTFM_DURATION_METRIC` | 首消息时间 |
| | `TURN_NETWORK_PROXY_METRIC` | 网络代理指标 |
| | `TURN_TOOL_CALL_METRIC` | Turn 工具调用 |
| | `TURN_TOKEN_USAGE_METRIC` | Token 使用量 |
| **Startup** | `STARTUP_PREWARM_DURATION_METRIC` | 预热耗时 |
| | `STARTUP_PREWARM_AGE_AT_FIRST_TURN_METRIC` | 预热年龄 |
| **Thread** | `THREAD_STARTED_METRIC` | 线程启动次数 |

### 3. 命名约定

- 使用 `snake_case` 常量名
- 以 `_METRIC` 后缀标识指标常量
- 持续时间指标以 `.duration_ms` 后缀
- 计数指标无单位后缀

## 具体技术实现

### 常量定义

```rust
pub const TOOL_CALL_COUNT_METRIC: &str = "codex.tool.call";
pub const TOOL_CALL_DURATION_METRIC: &str = "codex.tool.call.duration_ms";
pub const API_CALL_COUNT_METRIC: &str = "codex.api_request";
pub const API_CALL_DURATION_METRIC: &str = "codex.api_request.duration_ms";
// ... 更多常量
```

所有常量都是 `&'static str` 类型，编译期确定，零运行时开销。

### 使用示例

```rust
// session_telemetry.rs
use crate::metrics::names::TOOL_CALL_COUNT_METRIC;
use crate::metrics::names::TOOL_CALL_DURATION_METRIC;

self.counter(TOOL_CALL_COUNT_METRIC, 1, &[("tool", tool_name), ("success", success_str)]);
self.record_duration(TOOL_CALL_DURATION_METRIC, duration, &[("tool", tool_name)]);
```

```rust
// runtime_metrics.rs
use crate::metrics::names::API_CALL_COUNT_METRIC;
use crate::metrics::names::API_CALL_DURATION_METRIC;

let api_calls = RuntimeMetricTotals {
    count: sum_counter(snapshot, API_CALL_COUNT_METRIC),
    duration_ms: sum_histogram_ms(snapshot, API_CALL_DURATION_METRIC),
};
```

## 关键代码路径与文件引用

### 内部依赖

无内部依赖，纯常量定义文件。

### 调用方

| 文件 | 使用场景 |
|------|----------|
| `events/session_telemetry.rs` | 记录各类指标时使用 |
| `runtime_metrics.rs` | 从快照汇总指标时使用 |
| `tests/suite/runtime_summary.rs` | 测试验证指标名称 |

### 外部导出

```rust
// lib.rs
pub use crate::metrics::names;  // 公开导出 names 模块
```

使用者可以通过 `codex_otel::metrics::names::TOOL_CALL_COUNT_METRIC` 访问。

## 依赖与外部交互

### 指标命名空间

```
codex
├── tool
│   ├── call
│   └── call.duration_ms
├── api_request
│   └── duration_ms
├── sse_event
│   └── duration_ms
├── websocket
│   ├── request
│   ├── request.duration_ms
│   ├── event
│   └── event.duration_ms
├── responses_api_*
├── turn_*
├── startup_prewarm_*
└── thread.started
```

### 指标与标签配合

```rust
// 计数指标 + 状态标签
codex.tool.call{tool="shell", success="true"} 1
codex.tool.call{tool="shell", success="false"} 1

// 持续时间指标 + 状态标签
codex.tool.call.duration_ms{tool="shell"} 250
```

## 风险、边界与改进建议

### 当前风险

1. **命名冲突**: 所有指标共享 `codex` 前缀，可能与其他系统冲突
2. **硬编码前缀**: 前缀 `codex` 分散在各常量中，修改困难
3. **缺乏验证**: 常量值是字符串，编译期无法验证格式

### 边界情况

1. **指标数量增长**: 当前 27 个常量，持续增加可能导致文件膨胀
2. **命名长度**: 部分指标名较长（如 `RESPONSES_API_ENGINE_SERVICE_TBT_DURATION_METRIC`）
3. **文档缺失**: 常量只有名称，缺乏详细说明

### 改进建议

1. **前缀常量**:
   ```rust
   const METRIC_PREFIX: &str = "codex";
   
   pub const TOOL_CALL_COUNT_METRIC: &str = const_format::formatcp!("{}.{}", METRIC_PREFIX, "tool.call");
   ```

2. **结构化指标名**:
   ```rust
   pub struct MetricName {
       pub component: &'static str,
       pub name: &'static str,
       pub unit: Option<&'static str>,
   }
   
   impl MetricName {
       pub const TOOL_CALL: Self = Self {
           component: "tool",
           name: "call",
           unit: None,
       };
       
       pub fn as_str(&self) -> String {
           format!("codex.{}.{}{}", 
               self.component, 
               self.name,
               self.unit.map(|u| format!(".{}"), u).unwrap_or_default()
           )
       }
   }
   ```

3. **分组组织**:
   ```rust
   pub mod tool {
       pub const CALL_COUNT: &str = "codex.tool.call";
       pub const CALL_DURATION: &str = "codex.tool.call.duration_ms";
   }
   
   pub mod api {
       pub const REQUEST_COUNT: &str = "codex.api_request";
       pub const REQUEST_DURATION: &str = "codex.api_request.duration_ms";
   }
   ```

4. **文档注释**:
   ```rust
   /// Count of tool calls, tagged by tool name and success status.
   /// 
   /// Tags:
   /// - `tool`: The tool name (e.g., "shell", "file_write")
   /// - `success`: "true" or "false"
   pub const TOOL_CALL_COUNT_METRIC: &str = "codex.tool.call";
   ```

5. **生成器宏**:
   ```rust
   define_metrics! {
       tool {
           call: counter,
           call.duration_ms: histogram,
       }
       api_request {
           count: counter,
           duration_ms: histogram,
       }
   }
   ```
