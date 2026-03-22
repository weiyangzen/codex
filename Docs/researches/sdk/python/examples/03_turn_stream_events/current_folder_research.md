# SDK Python Example 03: Turn Stream Events - 深度研究文档

## 1. 场景与职责

### 1.1 定位与目标

`03_turn_stream_events` 是 Codex Python SDK 的**核心流式处理示例**，位于 `sdk/python/examples/03_turn_stream_events/`。该示例演示了如何通过异步事件流（Server-Sent Events 风格的 JSON-RPC 通知）与 Codex Agent 进行实时交互。

**核心目标：**
- 展示如何使用 `turn.stream()` 方法消费流式事件
- 演示实时获取 Agent 消息增量（`item/agentMessage/delta`）
- 展示如何处理 Turn 生命周期事件（`turn/started`, `turn/completed`）
- 提供同步和异步两种编程模型的参考实现

### 1.2 在示例体系中的位置

```
01_quickstart_constructor/  → 基础连接与初始化
02_turn_run/                → 阻塞式 Turn 执行（简化接口）
03_turn_stream_events/      → 流式事件处理（本文档主题）★
04_models_and_metadata/     → 模型列表与元数据查询
05_existing_thread/         → 已有线程恢复
06_thread_lifecycle/        → 线程生命周期管理
07-08_image_and_text/       → 多模态输入处理
09_async_parity/            → 异步 API 一致性验证
10_error_handling/          → 错误处理与重试
11_cli_mini_app/            → 基于流式事件的交互式 CLI
12-14_turn_params_controls/ → 高级 Turn 参数与控制
```

**演进关系：** 从 `02_turn_run` 的阻塞式 `run()` 方法，演进为本示例的细粒度流式消费，为 `11_cli_mini_app` 等交互式应用奠定基础。

---

## 2. 功能点目的

### 2.1 主要功能

| 功能 | 说明 | 对应代码 |
|------|------|----------|
| **流式文本输出** | 实时显示 Agent 生成的文本增量 | `item/agentMessage/delta` 事件处理 |
| **生命周期追踪** | 检测 Turn 开始和完成状态 | `turn/started`, `turn/completed` |
| **降级回查** | 流式消费失败时回查持久化数据 | `thread.read(include_turns=True)` |
| **事件计数统计** | 记录处理的事件总数 | `event_count` 计数器 |

### 2.2 关键事件类型

示例中处理的核心事件（定义于 `sdk/python/src/codex_app_server/models.py`）：

```python
# 主要关注的事件类型
"turn/started"              → TurnStartedNotification
"item/agentMessage/delta"   → AgentMessageDeltaNotification  
"turn/completed"            → TurnCompletedNotification
```

---

## 3. 具体技术实现

### 3.1 架构概览

```
┌─────────────────────────────────────────────────────────────────┐
│                    Client Application                            │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────────┐  │
│  │  sync.py    │    │  async.py   │    │  _bootstrap.py      │  │
│  │  (同步示例)  │    │ (异步示例)   │    │ (共享工具函数)       │  │
│  └──────┬──────┘    └──────┬──────┘    └─────────────────────┘  │
│         │                  │                                     │
│         └──────────────────┬──────────────────┘                  │
│                            ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │              codex_app_server.api                        │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │    │
│  │  │    Codex     │  │  AsyncCodex  │  │  TurnHandle  │  │    │
│  │  └──────────────┘  └──────────────┘  └──────────────┘  │    │
│  └─────────────────────────┬───────────────────────────────┘    │
│                            │                                     │
│         ┌──────────────────┼──────────────────┐                  │
│         ▼                  ▼                  ▼                  │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐          │
│  │   client    │    │async_client │    │   models    │          │
│  │(同步传输层)  │    │(异步包装器)  │    │ (数据模型)   │          │
│  └──────┬──────┘    └──────┬──────┘    └─────────────┘          │
│         │                  │                                     │
└─────────┼──────────────────┼─────────────────────────────────────┘
          │                  │
          └──────────────────┘
                     │
                     ▼
          ┌─────────────────────┐
          │  codex app-server   │
          │   (stdio 子进程)     │
          │  ┌───────────────┐  │
          │  │ JSON-RPC 2.0  │  │
          │  │ over stdio    │  │
          │  └───────────────┘  │
          └─────────────────────┘
```

### 3.2 关键流程

#### 3.2.1 同步流式消费流程

**文件：** `sdk/python/examples/03_turn_stream_events/sync.py`

```python
# 1. 初始化客户端（启动 app-server 子进程）
with Codex(config=runtime_config()) as codex:
    # 2. 创建线程
    thread = codex.thread_start(model="gpt-5.4", config={...})
    
    # 3. 启动 Turn
    turn = thread.turn(TextInput("Explain SIMD in 3 short bullets."))
    
    # 4. 流式消费事件
    for event in turn.stream():
        if event.method == "turn/started":
            saw_started = True
        elif event.method == "item/agentMessage/delta":
            delta = getattr(event.payload, "delta", "")
            print(delta, end="", flush=True)  # 实时输出
        elif event.method == "turn/completed":
            completed_status = event.payload.turn.status
```

#### 3.2.2 异步流式消费流程

**文件：** `sdk/python/examples/03_turn_stream_events/async.py`

```python
async with AsyncCodex(config=runtime_config()) as codex:
    thread = await codex.thread_start(...)
    turn = await thread.turn(TextInput(...))
    
    # 异步迭代
    async for event in turn.stream():
        # 相同的事件处理逻辑
```

#### 3.2.3 TurnHandle.stream() 内部实现

**文件：** `sdk/python/src/codex_app_server/api.py` (Lines 655-669)

```python
@dataclass(slots=True)
class TurnHandle:
    _client: AppServerClient
    thread_id: str
    id: str

    def stream(self) -> Iterator[Notification]:
        # 获取独占消费锁（防止并发 Turn 消费）
        self._client.acquire_turn_consumer(self.id)
        try:
            while True:
                event = self._client.next_notification()
                yield event
                # 终止条件：当前 Turn 完成
                if (event.method == "turn/completed" 
                    and event.payload.turn.id == self.id):
                    break
        finally:
            self._client.release_turn_consumer(self.id)
```

### 3.3 数据结构详解

#### 3.3.1 Notification 结构

**文件：** `sdk/python/src/codex_app_server/models.py` (Lines 45-87)

```python
@dataclass(slots=True)
class Notification:
    method: str                    # 事件类型，如 "item/agentMessage/delta"
    payload: NotificationPayload   # 类型化的负载数据

NotificationPayload = (
    AgentMessageDeltaNotification
    | TurnCompletedNotification
    | TurnStartedNotification
    | ...  # 其他 30+ 种通知类型
)
```

#### 3.3.2 AgentMessageDeltaNotification

**文件：** `sdk/python/src/codex_app_server/generated/v2_all.py` (Lines 45-52)

```python
class AgentMessageDeltaNotification(BaseModel):
    delta: str                     # 文本增量内容
    item_id: str                   # 消息项 ID
    thread_id: str                 # 所属线程 ID
    turn_id: str                   # 所属 Turn ID
```

#### 3.3.3 TurnCompletedNotification

**文件：** `sdk/python/src/codex_app_server/generated/v2_all.py` (Lines 5210-5215)

```python
class TurnCompletedNotification(BaseModel):
    thread_id: str
    turn: Turn                     # 完整的 Turn 对象

class Turn(BaseModel):
    id: str
    status: TurnStatus             # completed | failed | interrupted | in_progress
    error: TurnError | None        # 失败时的错误信息
    items: list[ThreadItem]        # Turn 包含的所有项目
```

### 3.4 协议细节

#### 3.4.1 JSON-RPC 2.0 over stdio

**底层传输：** `sdk/python/src/codex_app_server/client.py` (Lines 512-536)

```python
def _write_message(self, payload: JsonObject) -> None:
    """发送 JSON-RPC 消息（追加换行符）"""
    with self._lock:
        self._proc.stdin.write(json.dumps(payload) + "\n")
        self._proc.stdin.flush()

def _read_message(self) -> dict[str, JsonValue]:
    """读取 JSON-RPC 响应/通知"""
    line = self._proc.stdout.readline()
    if not line:
        raise TransportClosedError("app-server closed stdout")
    return json.loads(line)
```

#### 3.4.2 通知注册表

**文件：** `sdk/python/src/codex_app_server/generated/notification_registry.py`

```python
NOTIFICATION_MODELS: dict[str, type[BaseModel]] = {
    "turn/started": TurnStartedNotification,
    "turn/completed": TurnCompletedNotification,
    "item/agentMessage/delta": AgentMessageDeltaNotification,
    "thread/tokenUsage/updated": ThreadTokenUsageUpdatedNotification,
    # ... 共 40+ 种通知类型
}
```

### 3.5 关键命令与配置

#### 3.5.1 启动配置

**文件：** `sdk/python/examples/_bootstrap.py` (Lines 50-55)

```python
def runtime_config():
    """返回示例友好的 AppServerConfig"""
    from codex_app_server import AppServerConfig
    ensure_runtime_package_installed(sys.executable, _SDK_PYTHON_DIR)
    return AppServerConfig()  # 使用默认配置
```

#### 3.5.2 模型配置

示例中使用的模型参数：

```python
thread = codex.thread_start(
    model="gpt-5.4",
    config={"model_reasoning_effort": "high"}
)
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心文件清单

| 文件路径 | 职责 | 关键行号 |
|----------|------|----------|
| `sdk/python/examples/03_turn_stream_events/sync.py` | 同步流式示例 | 1-55 |
| `sdk/python/examples/03_turn_stream_events/async.py` | 异步流式示例 | 1-63 |
| `sdk/python/examples/_bootstrap.py` | 共享启动工具 | 1-152 |
| `sdk/python/src/codex_app_server/api.py` | 高层 API（Codex/Thread/TurnHandle） | 1-735 |
| `sdk/python/src/codex_app_server/client.py` | 同步 JSON-RPC 客户端 | 1-540 |
| `sdk/python/src/codex_app_server/async_client.py` | 异步客户端包装器 | 1-208 |
| `sdk/python/src/codex_app_server/models.py` | 核心数据模型（Notification 等） | 1-99 |
| `sdk/python/src/codex_app_server/generated/v2_all.py` | 自动生成的协议模型 | 1-5500+ |
| `sdk/python/src/codex_app_server/generated/notification_registry.py` | 通知类型注册表 | 1-106 |
| `sdk/python/src/codex_app_server/_inputs.py` | 输入类型定义 | 1-63 |
| `sdk/python/src/codex_app_server/_run.py` | RunResult 收集逻辑 | 1-112 |

### 4.2 调用链追踪

**流式事件消费完整调用链：**

```
sync.py:28  for event in turn.stream():
    ↓
api.py:655  TurnHandle.stream()
    ↓
api.py:660  self._client.next_notification()
    ↓
client.py:275  AppServerClient.next_notification()
    ↓
client.py:280  self._read_message()  ← 从 stdio 读取 JSON-RPC
    ↓
client.py:455  self._coerce_notification()  ← 解析为类型化 Notification
    ↓
notification_registry.py:57  NOTIFICATION_MODELS[method]  ← 查找模型类
```

### 4.3 降级回查逻辑

**文件：** `sync.py` (Lines 47-51)

```python
if saw_delta:
    print()
else:
    # 流式未收到增量，回查持久化数据
    persisted = thread.read(include_turns=True)
    persisted_turn = find_turn_by_id(persisted.thread.turns, turn.id)
    final_text = assistant_text_from_turn(persisted_turn)
```

---

## 5. 依赖与外部交互

### 5.1 内部依赖

```
03_turn_stream_events/
    ├── sync.py ─────────────────┐
    │   └── _bootstrap.py ───────┤
    │       ├── _runtime_setup.py│
    │       └── codex_app_server─┤
    │           ├── __init__.py  │
    │           ├── api.py       │
    │           ├── client.py    │
    │           ├── async_client.py
    │           ├── models.py    │
    │           ├── _inputs.py   │
    │           ├── _run.py      │
    │           └── generated/   │
    │               ├── v2_all.py│
    │               └── notification_registry.py
    └── async.py ────────────────┘
```

### 5.2 外部依赖

| 依赖 | 用途 | 版本 |
|------|------|------|
| `pydantic` | 数据模型验证与序列化 | ^2.0 |
| `codex-cli-bin` | Codex 运行时二进制（子进程） | 内置 |

### 5.3 子进程交互

**启动命令：**

```bash
# 由 AppServerClient.start() 自动生成
codex app-server --listen stdio://
```

**文件：** `client.py` (Lines 161-189)

```python
self._proc = subprocess.Popen(
    args,  # [codex_bin, "app-server", "--listen", "stdio://"]
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    bufsize=1,  # 行缓冲
)
```

### 5.4 与 Rust 后端的协议

Python SDK 通过 JSON-RPC 与 Rust 实现的 `codex app-server` 通信：

```rust
// Rust 端（codex-rs/app-server）发送通知
// Python 端接收并解析

// 示例：AgentMessageDeltaNotification
{
    "method": "item/agentMessage/delta",
    "params": {
        "delta": "增量文本",
        "itemId": "item-xxx",
        "threadId": "thread-xxx",
        "turnId": "turn-xxx"
    }
}
```

---

## 6. 风险、边界与改进建议

### 6.1 已知限制

#### 6.1.1 并发限制

**文件：** `client.py` (Lines 288-301)

```python
def acquire_turn_consumer(self, turn_id: str) -> None:
    with self._turn_consumer_lock:
        if self._active_turn_consumer is not None:
            raise RuntimeError(
                "Concurrent turn consumers are not yet supported..."
            )
        self._active_turn_consumer = turn_id
```

**风险：** 当前实现不支持同时消费多个 Turn 的事件流。

#### 6.1.2 实验性 API 标记

**文件：** `client.py` (Line 133)

```python
experimental_api: bool = True  # AppServerConfig 默认值
```

流式事件 API 仍处于实验阶段，协议可能变更。

### 6.2 边界情况

| 场景 | 行为 | 处理建议 |
|------|------|----------|
| 网络中断 | `TransportClosedError` | 捕获异常并重建连接 |
| 服务器过载 | `ServerBusyError` | 使用 `retry_on_overload()` 装饰器 |
| 空增量事件 | `delta` 字段为空字符串 | 示例中已过滤处理 |
| Turn 失败 | `turn.status == "failed"` | 检查 `turn.error.message` |
| 流式超时 | 无内置超时 | 应用层实现超时逻辑 |

### 6.3 改进建议

#### 6.3.1 短期改进

1. **添加流式超时控制**
   ```python
   # 建议增加 timeout 参数
   for event in turn.stream(timeout=30.0):
       ...
   ```

2. **支持选择性事件订阅**
   ```python
   # 建议 API
   turn.stream(events=["item/agentMessage/delta", "turn/completed"])
   ```

3. **增强错误上下文**
   ```python
   # 当前：简单的 RuntimeError
   # 建议：包含 turn_id、已处理事件数等上下文
   ```

#### 6.3.2 中长期改进

1. **并发 Turn 支持**
   - 移除 `acquire_turn_consumer` 单消费者限制
   - 实现基于 `turn_id` 的事件路由/多路复用

2. **背压机制**
   - 当客户端处理速度低于事件产生速度时，实现流量控制
   - 参考：`docs/tui-stream-chunking-review.md` 中的自适应策略

3. **类型安全增强**
   - 使用 TypedDict 或更精确的 Union 类型替代 `getattr` 访问
   - 示例中 `getattr(event.payload, "delta", "")` 可改为结构化模式匹配

4. **可观测性**
   ```python
   # 建议增加指标暴露
   turn.stream(metrics_collector=collector)
   # 事件延迟、处理速率、队列深度等
   ```

### 6.4 相关文档

| 文档 | 说明 |
|------|------|
| `docs/tui-stream-chunking-review.md` | TUI 流式分块策略设计 |
| `docs/tui-stream-chunking-tuning.md` | 流式性能调优参数 |
| `AGENTS.md` | Rust/codex-rs 开发规范 |
| `sdk/python/examples/11_cli_mini_app/sync.py` | 基于流式事件的完整 CLI 示例 |

---

## 7. 附录：事件类型完整列表

**来源：** `sdk/python/src/codex_app_server/generated/notification_registry.py`

### 7.1 Turn 相关事件

| 事件方法 | 模型类 | 说明 |
|----------|--------|------|
| `turn/started` | `TurnStartedNotification` | Turn 开始处理 |
| `turn/completed` | `TurnCompletedNotification` | Turn 完成（成功/失败/中断） |
| `turn/diff/updated` | `TurnDiffUpdatedNotification` | 代码差异更新 |
| `turn/plan/updated` | `TurnPlanUpdatedNotification` | 执行计划更新 |

### 7.2 Item 相关事件

| 事件方法 | 模型类 | 说明 |
|----------|--------|------|
| `item/agentMessage/delta` | `AgentMessageDeltaNotification` | Agent 消息文本增量 |
| `item/started` | `ItemStartedNotification` | 处理项开始 |
| `item/completed` | `ItemCompletedNotification` | 处理项完成 |
| `item/plan/delta` | `PlanDeltaNotification` | 计划文本增量 |
| `item/reasoning/textDelta` | `ReasoningTextDeltaNotification` | 推理文本增量 |
| `item/commandExecution/outputDelta` | `CommandExecutionOutputDeltaNotification` | 命令输出增量 |
| `item/fileChange/outputDelta` | `FileChangeOutputDeltaNotification` | 文件变更增量 |

### 7.3 Thread 相关事件

| 事件方法 | 模型类 | 说明 |
|----------|--------|------|
| `thread/started` | `ThreadStartedNotification` | 线程启动 |
| `thread/tokenUsage/updated` | `ThreadTokenUsageUpdatedNotification` | Token 使用量更新 |
| `thread/status/changed` | `ThreadStatusChangedNotification` | 线程状态变更 |
| `thread/compacted` | `ContextCompactedNotification` | 上下文压缩 |

---

## 8. 总结

`03_turn_stream_events` 示例是理解 Codex Python SDK 流式架构的关键入口。它展示了：

1. **事件驱动架构**：基于 JSON-RPC 通知的实时双向通信
2. **分层设计**：高层 API (`TurnHandle.stream()`) → 传输层 (`AppServerClient`) → 协议层 (JSON-RPC)
3. **生产就绪模式**：降级回查、错误处理、资源清理 (`try/finally`)

该示例为构建交互式 Agent 应用（如 `11_cli_mini_app`）提供了坚实基础，同时也是理解 Codex 事件协议的最佳参考实现。
