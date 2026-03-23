# log_db.rs 深度研究文档

## 场景与职责

`log_db.rs` 提供了将 tracing 日志事件捕获并持久化到专用 SQLite 数据库的能力。该模块实现了 `tracing_subscriber::Layer` trait，允许它作为 tracing 订阅者栈的一部分，异步地将日志事件写入数据库。

### 核心职责

1. **日志捕获**：通过 tracing Layer 接口捕获日志事件和 span 上下文
2. **异步写入**：在后台任务中批量写入日志，避免阻塞主线程
3. **日志保留**：自动清理过期日志（默认 10 天）
4. **反馈日志格式化**：生成与 feedback 格式化器兼容的日志格式

### 架构定位

```
┌─────────────────────────────────────────────────────────────┐
│                    Application Code                          │
│         tracing::info!("message") / span.in_scope()          │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│              tracing_subscriber Registry                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │  fmt Layer   │  │  LogDbLayer  │  │   other layers   │  │
│  └──────────────┘  └──────┬───────┘  └──────────────────┘  │
└───────────────────────────┼─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                    LogDbLayer                                │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │  on_event    │  │  on_new_span │  │   on_record      │  │
│  └──────┬───────┘  └──────────────┘  └──────────────────┘  │
│         │                                                   │
│         ▼                                                   │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              mpsc::channel (capacity: 512)            │  │
│  └──────────────────────────┬───────────────────────────┘  │
│                             │                               │
│                             ▼                               │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              run_inserter (tokio task)                │  │
│  │  ┌────────────┐  ┌────────────┐  ┌──────────────┐   │  │
│  │  │ batch: 128 │  │ interval:  │  │  flush()     │   │  │
│  │  │ entries    │  │ 2 seconds  │  │  oneshot     │   │  │
│  │  └────────────┘  └────────────┘  └──────────────┘   │  │
│  └──────────────────────────┬───────────────────────────┘  │
│                             │                               │
│                             ▼                               │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              run_retention_cleanup                    │  │
│  │         (delete logs older than 10 days)              │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
                   ┌────────────────┐
                   │  logs_1.sqlite │
                   └────────────────┘
```

## 功能点目的

### 1. `LogDbLayer` - 核心 Layer 结构

```rust
pub struct LogDbLayer {
    sender: mpsc::Sender<LogDbCommand>,
    process_uuid: String,
}
```

**设计要点**：
- 使用 `mpsc::channel` 与后台任务通信
- 每个进程有唯一的 `process_uuid`（格式：`pid:{pid}:{uuid}`）
- 实现 `Clone`，允许多个订阅者共享同一个后台写入器

### 2. `start` - 初始化函数

```rust
pub fn start(state_db: std::sync::Arc<StateRuntime>) -> LogDbLayer
```

**启动流程**：
1. 生成进程 UUID
2. 创建 MPSC 通道（容量 512）
3. 启动 `run_inserter` 后台任务
4. 启动 `run_retention_cleanup` 后台任务

### 3. `Layer` trait 实现

#### `on_new_span` - Span 创建处理

```rust
fn on_new_span(&self, attrs: &Attributes<'_>, id: &Id, ctx: Context<'_, S>)
```

- 提取 span 的字段值（特别是 `thread_id`）
- 将 `SpanLogContext` 存储到 span 的扩展中
- 格式化字段为字符串存储

#### `on_record` - Span 记录更新

```rust
fn on_record(&self, id: &Id, values: &Record<'_>, ctx: Context<'_, S>)
```

- 处理运行时添加到 span 的新字段
- 更新 `SpanLogContext` 中的字段和 thread_id

#### `on_event` - 事件处理

```rust
fn on_event(&self, event: &Event<'_>, ctx: Context<'_, S>)
```

核心处理逻辑：
1. 提取事件元数据（级别、目标、模块路径、文件、行号）
2. 提取消息内容（通过 `MessageVisitor`）
3. 获取 thread_id（从事件字段或 span 上下文）
4. 格式化 feedback 日志体（包含 span 层级信息）
5. 创建 `LogEntry` 并发送到后台通道

### 4. `LogDbLayer::flush` - 强制刷新

```rust
pub async fn flush(&self)
```

- 发送 Flush 命令到后台任务
- 等待 oneshot 确认完成
- 用于测试和优雅关闭场景

### 5. 后台任务

#### `run_inserter` - 批量写入器

```rust
async fn run_inserter(
    state_db: Arc<StateRuntime>,
    receiver: mpsc::Receiver<LogDbCommand>,
)
```

**批处理策略**：
- 批量大小：128 条
- 刷新间隔：2 秒
- 使用 `tokio::select!` 同时等待新消息和定时器

**流程**：
```
loop:
    ├─ 收到 Entry → 加入 buffer
    │   └─ buffer >= 128 → 立即 flush
    ├─ 收到 Flush → flush + 发送确认
    ├─ 通道关闭 → final flush + break
    └─ 定时器触发 → flush
```

#### `run_retention_cleanup` - 保留清理

```rust
async fn run_retention_cleanup(state_db: Arc<StateRuntime>)
```

- 单次执行（启动时）
- 删除 10 天前的日志
- 使用 `DateTime::checked_sub_signed` 安全计算

### 6. 字段访问器实现

#### `SpanFieldVisitor` - Span 字段访问

提取 `thread_id` 字段（支持多种类型：i64, u64, bool, f64, str, error, debug）。

#### `MessageVisitor` - 消息字段访问

提取 `message` 和 `thread_id` 字段。

### 7. 反馈日志格式化

#### `format_feedback_log_body` - 生成反馈格式

```rust
fn format_feedback_log_body<S>(event: &Event<'_>, ctx: Context<'_, S>) -> String
```

**格式**：
```
span1{field1=value1}:span2{field2=value2}: event_message
```

示例：
```
feedback-thread{thread_id=thread-1, turn=1}: thread-scoped
```

#### `event_thread_id` - 从 Span 上下文获取 thread_id

遍历 span 层级，从 `SpanLogContext` 中提取 thread_id。

## 具体技术实现

### 关键常量

```rust
const LOG_QUEUE_CAPACITY: usize = 512;      // MPSC 通道容量
const LOG_BATCH_SIZE: usize = 128;          // 批量写入大小
const LOG_FLUSH_INTERVAL: Duration = Duration::from_secs(2);  // 刷新间隔
const LOG_RETENTION_DAYS: i64 = 10;         // 日志保留天数
```

### 命令类型

```rust
enum LogDbCommand {
    Entry(Box<LogEntry>),           // 日志条目
    Flush(oneshot::Sender<()>),     // 刷新命令
}
```

### SpanLogContext 结构

```rust
struct SpanLogContext {
    name: String,           // Span 名称
    formatted_fields: String,  // 格式化的字段
    thread_id: Option<String>, // Thread ID
}
```

### 进程 UUID 生成

```rust
fn current_process_log_uuid() -> &'static str
```

格式：`pid:{process_id}:{random_uuid}`
- 使用 `OnceLock` 确保只生成一次
- 结合 PID 和 UUID 确保进程唯一性

## 关键代码路径与文件引用

### 内部依赖

| 文件 | 用途 |
|------|------|
| `model/log.rs` | `LogEntry`, `LogQuery`, `LogRow` 定义 |
| `runtime/logs.rs` | `StateRuntime::insert_logs`, `delete_logs_before` |
| `lib.rs` | 模块导出 |

### 外部依赖

| Crate | 模块/类型 | 用途 |
|-------|----------|------|
| `tracing` | `Event`, `Span`, `Layer`, `Visit` | Tracing 核心 |
| `tracing-subscriber` | `Layer`, `FormattedFields`, `DefaultFields` | 订阅者基础设施 |
| `tokio` | `mpsc`, `oneshot`, `time` | 异步通道和定时器 |
| `chrono` | `Duration`, `Utc` | 时间计算 |
| `uuid` | `Uuid` | UUID 生成 |

### 数据流

```
Tracing Event
    │
    ├──► on_new_span ──► SpanLogContext (存储到 span extensions)
    │
    ├──► on_record ──► 更新 SpanLogContext
    │
    └──► on_event
            │
            ├──► MessageVisitor ──► 提取 message, thread_id
            │
            ├──► event_thread_id ──► 从 span 层级获取 thread_id
            │
            ├──► format_feedback_log_body ──► 生成反馈格式
            │
            └──► LogEntry ──► mpsc::Sender ──► run_inserter
                                                    │
                                                    ▼
                                            StateRuntime::insert_logs
                                                    │
                                                    ▼
                                              logs_1.sqlite
```

## 依赖与外部交互

### 上游调用方

1. **应用代码**：通过 tracing 宏触发
2. **codex-tui/codex-cli**：初始化 tracing subscriber 时使用

### 下游被调用方

1. **runtime/logs.rs**：`insert_logs`, `delete_logs_before`

### 配置与初始化示例

```rust
use codex_state::log_db;
use tracing_subscriber::prelude::*;

let layer = log_db::start(state_runtime);
tracing_subscriber::registry()
    .with(layer)
    .with(tracing_subscriber::fmt::layer())
    .init();
```

## 风险、边界与改进建议

### 潜在风险

1. **通道满阻塞**：`try_send` 失败时日志会丢失（使用 `let _ =` 忽略错误）
2. **内存泄漏风险**：如果 `run_inserter` 崩溃，channel 可能堆积
3. **时钟回拨**：`LOG_RETENTION_DAYS` 计算在时钟回拨时可能异常
4. **数据库连接失败**：`flush` 中的错误被忽略

### 边界情况

1. **空消息处理**：`message` 字段为 None 时，使用 `feedback_log_body` 回退
2. **Thread ID 优先级**：事件字段 > Span 上下文
3. **Span 层级深度**：无限制，但过深层级可能影响性能
4. **超大字段值**：字段格式化没有长度限制

### 改进建议

1. **背压处理**：
   - 考虑使用 `send` 而非 `try_send` 并处理背压
   - 或添加溢出计数器监控

2. **错误处理增强**：
   - 记录 `try_send` 失败的次数
   - 添加数据库写入失败的错误处理

3. **性能优化**：
   - 考虑使用 `parking_lot` 替代标准锁
   - 批量大小可配置

4. **可观测性**：
   - 添加内部指标（队列深度、批处理延迟）
   - 导出 flush 延迟直方图

5. **测试覆盖**：
   - 增加压力测试（高并发日志）
   - 测试通道满时的行为
   - 测试时钟回拨场景

### 代码质量评估

- **正确性**：★★★★☆ - 核心逻辑正确，但错误处理可加强
- **性能**：★★★★☆ - 批量写入设计良好，但可配置性不足
- **可维护性**：★★★★☆ - 结构清晰，文档完善
- **测试覆盖**：★★★★☆ - 有基础测试，但边界情况可加强

### 关键测试

1. `sqlite_feedback_logs_match_feedback_formatter_shape`：验证 SQLite 日志与 feedback 格式化器输出一致
2. `flush_persists_logs_for_query`：验证 flush 命令正确工作

测试使用 `SharedWriter` 模拟写入器，对比 SQLite 输出和格式化器输出。
