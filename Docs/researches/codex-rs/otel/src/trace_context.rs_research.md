# codex-rs/otel/src/trace_context.rs 研究文档

## 场景与职责

`trace_context.rs` 是 `codex-otel` crate 的 W3C Trace Context 传播模块。它实现了分布式追踪上下文在进程内和进程间的传播，支持从环境变量、HTTP header 和当前 span 中提取/注入 trace context。

**核心职责：**
1. 从当前 span 提取 W3C Trace Context（traceparent/tracestate）
2. 从环境变量加载 Trace Context（`TRACEPARENT`/`TRACESTATE`）
3. 将 W3C Trace Context 注入到 span 作为 parent
4. 提供当前 span 的 trace ID 提取
5. 支持跨异步边界的 context 传播

## 功能点目的

### 1. W3C Trace Context 标准

W3C Trace Context 是 W3C 标准化的分布式追踪传播格式：
- **traceparent**: 格式 `00-{trace-id}-{parent-id}-{trace-flags}`
  - 示例: `00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01`
- **tracestate**: 厂商特定的扩展信息
  - 示例: `vendor=value1,othervendor=value2`

### 2. 跨进程传播

**使用场景：**
- CLI 启动时从环境变量继承 trace context（如被其他系统调用）
- Server 从 HTTP header 提取 trace context
- 向外部系统发送请求时注入 trace context

**核心类型（来自 `codex_protocol::protocol::W3cTraceContext`）：**
```rust
pub struct W3cTraceContext {
    pub traceparent: Option<String>,
    pub tracestate: Option<String>,
}
```

### 3. 跨异步边界传播

在 Codex 的 SQ/EQ (Submission Queue/Event Queue) 架构中，操作可能跨越异步边界：

```rust
// 在发送操作前提取 context
let trace_context = current_span_w3c_trace_context();

// 将 context 随操作一起传递
queue.send(Op { ..., trace: trace_context });

// 在处理端恢复 context
set_parent_from_w3c_trace_context(&span, &op.trace);
```

### 4. 环境变量继承

```rust
const TRACEPARENT_ENV_VAR: &str = "TRACEPARENT";
const TRACESTATE_ENV_VAR: &str = "TRACESTATE";
static TRACEPARENT_CONTEXT: OnceLock<Option<Context>> = OnceLock::new();

pub fn traceparent_context_from_env() -> Option<Context>
```

**用途：**
- 当 Codex CLI 被其他已追踪系统调用时，自动继承 trace context
- 使用 `OnceLock` 确保只解析一次

## 具体技术实现

### 核心数据结构

```rust
use opentelemetry::Context;
use opentelemetry_sdk::propagation::TraceContextPropagator;
use std::collections::HashMap;

const TRACEPARENT_ENV_VAR: &str = "TRACEPARENT";
const TRACESTATE_ENV_VAR: &str = "TRACESTATE";
static TRACEPARENT_CONTEXT: OnceLock<Option<Context>> = OnceLock::new();
```

### 从 Span 提取 Trace Context

```rust
pub fn current_span_w3c_trace_context() -> Option<W3cTraceContext> {
    span_w3c_trace_context(&Span::current())
}

pub fn span_w3c_trace_context(span: &Span) -> Option<W3cTraceContext> {
    let context = span.context();
    if !context.span().span_context().is_valid() {
        return None;
    }

    let mut headers = HashMap::new();
    TraceContextPropagator::new().inject_context(&context, &mut headers);

    Some(W3cTraceContext {
        traceparent: headers.remove("traceparent"),
        tracestate: headers.remove("tracestate"),
    })
}
```

**关键点：**
- 检查 span context 是否有效（非零 trace ID）
- 使用 `TraceContextPropagator` 注入到 HashMap
- 返回 `W3cTraceContext` 结构体

### 从环境变量加载

```rust
pub fn traceparent_context_from_env() -> Option<Context> {
    TRACEPARENT_CONTEXT
        .get_or_init(load_traceparent_context)
        .clone()
}

fn load_traceparent_context() -> Option<Context> {
    let traceparent = env::var(TRACEPARENT_ENV_VAR).ok()?;
    let tracestate = env::var(TRACESTATE_ENV_VAR).ok();

    match context_from_trace_headers(Some(&traceparent), tracestate.as_deref()) {
        Some(context) => {
            debug!("TRACEPARENT detected; continuing trace from parent context");
            Some(context)
        }
        None => {
            warn!("TRACEPARENT is set but invalid; ignoring trace context");
            None
        }
    }
}
```

### 从 Header 解析 Context

```rust
pub(crate) fn context_from_trace_headers(
    traceparent: Option<&str>,
    tracestate: Option<&str>,
) -> Option<Context> {
    let traceparent = traceparent?;
    let mut headers = HashMap::new();
    headers.insert("traceparent".to_string(), traceparent.to_string());
    if let Some(tracestate) = tracestate {
        headers.insert("tracestate".to_string(), tracestate.to_string());
    }

    let context = TraceContextPropagator::new().extract(&headers);
    if !context.span().span_context().is_valid() {
        return None;
    }
    Some(context)
}
```

### 设置 Span Parent

```rust
pub fn set_parent_from_w3c_trace_context(span: &Span, trace: &W3cTraceContext) -> bool {
    if let Some(context) = context_from_w3c_trace_context(trace) {
        set_parent_from_context(span, context);
        true
    } else {
        false
    }
}

pub fn set_parent_from_context(span: &Span, context: Context) {
    let _ = span.set_parent(context);
}
```

### 提取 Trace ID

```rust
pub fn current_span_trace_id() -> Option<String> {
    let context = Span::current().context();
    let span = context.span();
    let span_context = span.span_context();
    if !span_context.is_valid() {
        return None;
    }

    Some(span_context.trace_id().to_string())
}
```

## 关键代码路径与文件引用

### 模块依赖

```
trace_context.rs
├── codex_protocol::protocol::W3cTraceContext
├── opentelemetry::Context
├── opentelemetry::propagation::TextMapPropagator
├── opentelemetry_sdk::propagation::TraceContextPropagator
└── tracing_opentelemetry::OpenTelemetrySpanExt
```

### 外部调用方

**`codex-rs/core/src/codex_thread.rs`:**
```rust
use codex_otel::trace_context::current_span_w3c_trace_context;
use codex_otel::trace_context::set_parent_from_w3c_trace_context;
// 在 SQ/EQ 操作中传播 trace context
```

**`codex-rs/core/src/thread_manager.rs`:**
```rust
use codex_otel::trace_context::set_parent_from_w3c_trace_context;
```

**`codex-rs/exec/src/lib.rs`:**
```rust
use codex_otel::trace_context::current_span_w3c_trace_context;
// 获取当前 trace context 用于外部调用
```

**`codex-rs/app-server/src/outgoing_message.rs`:**
```rust
use codex_otel::trace_context::current_span_w3c_trace_context;
// 在 outgoing message 中包含 trace context
```

**`codex-rs/core/src/client.rs`:**
```rust
use codex_otel::current_span_trace_id;
// 获取 trace ID 用于日志关联
```

## 依赖与外部交互

### 外部 crate 依赖

**OpenTelemetry:**
- `opentelemetry::Context`: OTEL context 类型
- `opentelemetry::propagation::TextMapPropagator`: 传播器 trait
- `opentelemetry_sdk::propagation::TraceContextPropagator`: W3C 实现

**Tracing:**
- `tracing::Span`: tracing span
- `tracing_opentelemetry::OpenTelemetrySpanExt`: span 扩展方法

**协议:**
- `codex_protocol::protocol::W3cTraceContext`: 跨 crate 共享的类型

### 标准库
- `std::collections::HashMap`: header 存储
- `std::env`: 环境变量读取
- `std::sync::OnceLock`: 懒加载环境变量 context

## 风险、边界与改进建议

### 传播风险

1. **Context 丢失**: 如果异步任务没有正确传递 context，会导致 trace 断裂
   - 建议：在 SQ/EQ 操作中强制包含 trace context

2. **无效的 Traceparent**: 环境变量中的 TRACEPARENT 可能格式错误
   - 当前处理：记录警告并忽略
   - 建议：提供更详细的错误信息

3. **并发修改**: `OnceLock` 确保环境变量只读取一次，但如果环境变量在运行时改变不会感知
   - 这是设计决策，通常环境变量在启动时确定

### 边界情况

1. **空 Traceparent**: `context_from_trace_headers` 返回 `None` 如果 traceparent 是 `None`

2. **无效格式**: OpenTelemetry SDK 会验证 traceparent 格式，无效时返回无效 context
   - 通过 `is_valid()` 检查过滤

3. **Tracestate 限制**: W3C 标准对 tracestate 有长度和条目限制
   - 当前依赖 OpenTelemetry SDK 处理

### 测试覆盖

**当前测试：**
```rust
#[test]
fn parses_valid_w3c_trace_context() {
    let trace_id = "00000000000000000000000000000001";
    let span_id = "0000000000000002";
    let context = context_from_w3c_trace_context(&W3cTraceContext {
        traceparent: Some(format!("00-{trace_id}-{span_id}-01")),
        tracestate: None,
    }).expect("trace context");
    // 验证 trace_id 和 span_id
}

#[test]
fn invalid_traceparent_returns_none() {
    assert!(context_from_trace_headers(Some("not-a-traceparent"), None).is_none());
}

#[test]
fn missing_traceparent_returns_none() {
    assert!(context_from_w3c_trace_context(&W3cTraceContext {
        traceparent: None,
        tracestate: Some("vendor=value".to_string()),
    }).is_none());
}

#[test]
fn current_span_trace_id_returns_hex_trace_id() {
    // 验证 trace ID 格式（32 位十六进制）
}
```

**缺失测试：**
- tracestate 传播
- 环境变量读取（需要隔离测试）
- span parent 设置
- 无效 tracestate 处理

### 改进建议

1. **错误详情**: 在解析失败时提供更详细的错误信息（如格式错误位置）
2. **Metrics**: 暴露 context 解析成功/失败的指标
3. **日志关联**: 提供方法将 trace ID 自动添加到所有日志
4. **Baggage 支持**: 考虑支持 W3C Baggage 传播（键值对）
5. **多 propagator**: 支持多种 propagator（B3、Jaeger 等）

### 架构建议

当前设计简单有效，但可以增强：

1. **Context 管理器**: 提供高层次的 context 管理 API
   ```rust
   pub struct TraceContextManager {
       // 管理 context 的保存和恢复
   }
   ```

2. **中间件集成**: 提供 tower/http 中间件自动处理 propagation

3. **类型安全**: 使用类型系统确保 context 不被遗忘
   ```rust
   pub struct TracedOp<T> {
       op: T,
       context: W3cTraceContext,
   }
   ```

### 相关标准

- **W3C Trace Context**: https://www.w3.org/TR/trace-context/
- **OpenTelemetry Propagators**: https://opentelemetry.io/docs/specs/otel/context/api-propagators/
