# SDK Python Examples - 02_turn_run 深度研究文档

## 1. 场景与职责

### 1.1 定位与目标

`02_turn_run` 是 Codex Python SDK 的第二个示例，位于 `sdk/python/examples/02_turn_run/` 目录。该示例的核心目标是演示 **Turn 级别的细粒度控制** 和 **完整输出字段检查**，与 `01_quickstart_constructor` 的简化 API 形成对比。

### 1.2 与相邻示例的关系

| 示例 | 职责对比 |
|------|----------|
| `01_quickstart_constructor` | 使用 `thread.run("text")` 简化 API，隐藏 Turn 细节 |
| `02_turn_run` (本示例) | 显式创建 Turn，调用 `turn.run()` 获取完整 Turn 输出，展示底层数据模型 |
| `03_turn_stream_events` | 基于本示例扩展，展示事件流式消费而非阻塞式 `run()` |

### 1.3 使用场景

- **调试场景**: 需要检查 Turn 的完整状态（status, error, items 数量）
- **持久化验证**: 验证 Turn 数据是否正确持久化到 Thread 历史
- **教学场景**: 理解 SDK 内部 `Thread` → `TurnHandle` → `RunResult` 的调用链

---

## 2. 功能点目的

### 2.1 核心功能演示

本示例演示以下关键功能点：

1. **显式 Turn 创建**: 使用 `thread.turn(TextInput(...))` 而非简化的 `thread.run(...)`
2. **阻塞式执行**: 调用 `turn.run()` 等待 Turn 完成并获取完整结果
3. **持久化验证**: 通过 `thread.read(include_turns=True)` 读取持久化后的 Turn 数据
4. **字段级检查**: 打印 `thread_id`, `turn_id`, `status`, `error`, `text`, `items.count` 等完整字段

### 2.2 示例代码流程

```python
# 1. 创建 Thread（带模型配置）
thread = codex.thread_start(model="gpt-5.4", config={"model_reasoning_effort": "high"})

# 2. 显式创建 Turn（非简化 API）
turn = thread.turn(TextInput("Give 3 bullets about SIMD."))

# 3. 阻塞式执行并获取结果
result = turn.run()  # 返回 AppServerTurn 对象

# 4. 验证持久化状态
persisted = thread.read(include_turns=True)
persisted_turn = find_turn_by_id(persisted.thread.turns, result.id)

# 5. 输出完整字段信息
print("thread_id:", thread.id)
print("turn_id:", result.id)
print("status:", result.status)  # completed | failed | interrupted | in_progress
print("error:", result.error)    # TurnError | None
print("text:", assistant_text_from_turn(persisted_turn))
print("persisted.items.count:", len(persisted_turn.items or []))
```

---

## 3. 具体技术实现

### 3.1 关键流程

#### 3.1.1 Turn 生命周期流程

```
┌─────────────┐     ┌─────────────────┐     ┌──────────────────┐
│   Codex     │────▶│  thread_start   │────▶│     Thread       │
│  (client)   │     │  (RPC:thread/   │     │  (thread_id)     │
│             │     │      start)     │     │                  │
└─────────────┘     └─────────────────┘     └────────┬─────────┘
                                                     │
                                                     ▼
┌─────────────┐     ┌─────────────────┐     ┌──────────────────┐
│   result    │◀────│    turn.run()   │◀────│  thread.turn()   │
│(AppServer   │     │ (stream events  │     │  (RPC:turn/start)│
│   Turn)     │     │  → collect)     │     │                  │
└─────────────┘     └─────────────────┘     └──────────────────┘
```

#### 3.1.2 Turn.run() 内部实现

```python
# sdk/python/src/codex_app_server/api.py:671-684
@dataclass(slots=True)
class TurnHandle:
    def run(self) -> AppServerTurn:
        completed: TurnCompletedNotification | None = None
        stream = self.stream()  # 获取事件流迭代器
        try:
            for event in stream:
                payload = event.payload
                # 监听 turn/completed 通知
                if isinstance(payload, TurnCompletedNotification) and payload.turn.id == self.id:
                    completed = payload
        finally:
            stream.close()

        if completed is None:
            raise RuntimeError("turn completed event not received")
        return completed.turn  # 返回完整的 AppServerTurn 对象
```

#### 3.1.3 事件流收集机制

`turn.run()` 内部通过 `stream()` 方法消费事件流：

```python
# sdk/python/src/codex_app_server/api.py:655-669
def stream(self) -> Iterator[Notification]:
    self._client.acquire_turn_consumer(self.id)  # 获取独占消费锁
    try:
        while True:
            event = self._client.next_notification()
            yield event
            # 终止条件：收到当前 Turn 的 completed 通知
            if (event.method == "turn/completed" 
                and isinstance(event.payload, TurnCompletedNotification)
                and event.payload.turn.id == self.id):
                break
    finally:
        self._client.release_turn_consumer(self.id)  # 释放锁
```

### 3.2 关键数据结构

#### 3.2.1 AppServerTurn (Turn 结果)

```python
# sdk/python/src/codex_app_server/generated/v2_all.py
class Turn(BaseModel):
    id: str
    status: TurnStatus  # Enum: completed | interrupted | failed | in_progress
    error: TurnError | None = None
    # ... 其他字段

class TurnStatus(Enum):
    completed = "completed"
    interrupted = "interrupted"
    failed = "failed"
    in_progress = "inProgress"

class TurnError(BaseModel):
    message: str
    additional_details: str | None = None
    codex_error_info: CodexErrorInfo | None = None
```

#### 3.2.2 TurnStartParams (Turn 启动参数)

```python
# sdk/python/src/codex_app_server/generated/v2_all.py
class TurnStartParams(BaseModel):
    thread_id: str
    input: list[UserInput]  # 标准化后的输入项列表
    approval_policy: AskForApproval | None = None
    approvals_reviewer: ApprovalsReviewer | None = None
    cwd: str | None = None
    effort: ReasoningEffort | None = None
    model: str | None = None
    output_schema: dict | None = None
    personality: Personality | None = None
    sandbox_policy: SandboxPolicy | None = None
    service_tier: ServiceTier | None = None
    summary: ReasoningSummary | None = None
```

#### 3.2.3 输入类型系统

```python
# sdk/python/src/codex_app_server/_inputs.py
@dataclass(slots=True)
class TextInput:
    text: str

@dataclass(slots=True)
class ImageInput:
    url: str

@dataclass(slots=True)
class LocalImageInput:
    path: str

@dataclass(slots=True)
class SkillInput:
    name: str
    path: str

@dataclass(slots=True)
class MentionInput:
    name: str
    path: str

InputItem = TextInput | ImageInput | LocalImageInput | SkillInput | MentionInput
Input = list[InputItem] | InputItem
```

输入到 Wire 格式的转换：

```python
def _to_wire_item(item: InputItem) -> JsonObject:
    if isinstance(item, TextInput):
        return {"type": "text", "text": item.text}
    if isinstance(item, ImageInput):
        return {"type": "image", "url": item.url}
    # ... 其他类型
```

### 3.3 协议与通信

#### 3.3.1 JSON-RPC 方法

| 方法 | 方向 | 用途 |
|------|------|------|
| `turn/start` | Client → Server | 启动新 Turn |
| `turn/interrupt` | Client → Server | 中断正在执行的 Turn |
| `turn/steer` | Client → Server | 向执行中的 Turn 发送额外输入 |
| `turn/completed` | Server → Client (Notification) | Turn 完成通知 |
| `turn/started` | Server → Client (Notification) | Turn 开始通知 |

#### 3.3.2 通知类型

```python
# sdk/python/src/codex_app_server/models.py
NotificationPayload = (
    TurnCompletedNotification
    | TurnStartedNotification
    | AgentMessageDeltaNotification
    | ItemCompletedNotification
    | ThreadTokenUsageUpdatedNotification
    | ...
)

@dataclass(slots=True)
class Notification:
    method: str
    payload: NotificationPayload
```

### 3.4 并发控制

#### 3.4.1 Turn 消费者锁

```python
# sdk/python/src/codex_app_server/client.py:288-301
class AppServerClient:
    def acquire_turn_consumer(self, turn_id: str) -> None:
        with self._turn_consumer_lock:
            if self._active_turn_consumer is not None:
                raise RuntimeError(
                    "Concurrent turn consumers are not yet supported in the experimental SDK. "
                    f"Client is already streaming turn {self._active_turn_consumer!r}; "
                    f"cannot start turn {turn_id!r} until the active consumer finishes."
                )
            self._active_turn_consumer = turn_id

    def release_turn_consumer(self, turn_id: str) -> None:
        with self._turn_consumer_lock:
            if self._active_turn_consumer == turn_id:
                self._active_turn_consumer = None
```

**注意**: 当前实现限制同一时间只能有一个 Turn 处于流式消费状态。

---

## 4. 关键代码路径与文件引用

### 4.1 示例文件

| 文件 | 职责 |
|------|------|
| `sdk/python/examples/02_turn_run/sync.py` | 同步版本示例 |
| `sdk/python/examples/02_turn_run/async.py` | 异步版本示例 |
| `sdk/python/examples/_bootstrap.py` | 运行时引导和辅助函数 |

### 4.2 SDK 核心文件

| 文件 | 职责 |
|------|------|
| `sdk/python/src/codex_app_server/api.py` | 高级 API (`Codex`, `Thread`, `TurnHandle`, `AsyncCodex`, `AsyncThread`, `AsyncTurnHandle`) |
| `sdk/python/src/codex_app_server/client.py` | 同步 JSON-RPC 客户端 (`AppServerClient`) |
| `sdk/python/src/codex_app_server/async_client.py` | 异步包装器 (`AsyncAppServerClient`) |
| `sdk/python/src/codex_app_server/_inputs.py` | 输入类型定义和转换 |
| `sdk/python/src/codex_app_server/_run.py` | `RunResult` 和结果收集逻辑 |
| `sdk/python/src/codex_app_server/models.py` | 核心数据模型 (`Notification`, `InitializeResponse`) |
| `sdk/python/src/codex_app_server/generated/v2_all.py` | 从协议生成的 Pydantic 模型 |

### 4.3 关键代码行引用

```
api.py:
  - Line 467-539: Thread 类定义，包含 turn() 方法
  - Line 643-684: TurnHandle 类定义，包含 run() 和 stream() 方法
  - Line 687-735: AsyncTurnHandle 类定义

client.py:
  - Line 352-363: turn_start() RPC 方法
  - Line 365-370: turn_interrupt() RPC 方法
  - Line 372-386: turn_steer() RPC 方法
  - Line 288-301: Turn 消费者锁机制

_run.py:
  - Line 20-23: RunResult 数据类
  - Line 59-83: _collect_run_result() 同步结果收集
  - Line 86-112: _collect_async_run_result() 异步结果收集

_inputs.py:
  - Line 8-37: 输入类型定义
  - Line 40-57: Wire 格式转换函数
```

---

## 5. 依赖与外部交互

### 5.1 运行时依赖

| 依赖 | 用途 |
|------|------|
| `codex-cli-bin` | Codex 运行时二进制，通过 `pip install codex-cli-bin` 安装 |
| `pydantic` | 数据验证和序列化 |
| Python >= 3.10 | 类型注解支持 (`|`, `ParamSpec` 等) |

### 5.2 进程间通信

```
Python SDK Process                    Codex CLI Process (app-server)
       │                                        │
       │── subprocess.Popen(stdin/stdout/stderr)▶│
       │                                        │
       │── JSON-RPC Request (turn/start)───────▶│
       │                                        │
       │◀── JSON-RPC Response (TurnStartResponse)│
       │                                        │
       │◀── Notification (turn/started)─────────│
       │◀── Notification (item/agentMessage/delta)│
       │◀── Notification (turn/completed)───────│
```

### 5.3 配置系统

```python
# sdk/python/src/codex_app_server/client.py:123-133
@dataclass(slots=True)
class AppServerConfig:
    codex_bin: str | None = None           # 自定义二进制路径
    launch_args_override: tuple[str, ...] | None = None  # 完全自定义启动参数
    config_overrides: tuple[str, ...] = ()  # --config 覆盖
    cwd: str | None = None                  # 工作目录
    env: dict[str, str] | None = None       # 环境变量
    client_name: str = "codex_python_sdk"
    client_title: str = "Codex Python SDK"
    client_version: str = "0.2.0"
    experimental_api: bool = True           # 启用实验性 API
```

---

## 6. 风险、边界与改进建议

### 6.1 已知限制

#### 6.1.1 并发限制

```python
# 当前实现限制：同一时间只能流式消费一个 Turn
# sdk/python/src/codex_app_server/client.py:290-295
raise RuntimeError(
    "Concurrent turn consumers are not yet supported in the experimental SDK. "
    f"Client is already streaming turn {self._active_turn_consumer!r}; "
    f"cannot start turn {turn_id!r} until the active consumer finishes."
)
```

**影响**: 无法同时流式消费多个 Turn 的事件。

#### 6.1.2 阻塞式 API 限制

`turn.run()` 是阻塞调用，在 Turn 执行期间会占用线程/事件循环。对于长时运行的 Turn，建议使用 `turn.stream()` 进行事件流式处理（如 `03_turn_stream_events` 示例所示）。

### 6.2 错误处理边界

#### 6.2.1 Turn 失败检测

```python
# sdk/python/src/codex_app_server/_run.py:51-56
def _raise_for_failed_turn(turn: AppServerTurn) -> None:
    if turn.status != TurnStatus.failed:
        return
    if turn.error is not None and turn.error.message:
        raise RuntimeError(turn.error.message)
    raise RuntimeError(f"turn failed with status {turn.status.value}")
```

**注意**: 当前 `turn.run()` 在 Turn 失败时抛出 `RuntimeError`，但 `RunResult` 收集器（`Thread.run()` 使用）会处理更多字段。

#### 6.2.2 传输层错误

```python
# sdk/python/src/codex_app_server/errors.py
class TransportClosedError(AppServerError):
    """Raised when the app-server transport closes unexpectedly."""

class ServerBusyError(AppServerRpcError):
    """Server is overloaded / unavailable and caller should retry."""
```

### 6.3 改进建议

#### 6.3.1 API 设计层面

1. **支持并发 Turn 消费**: 当前的全局锁限制 (`acquire_turn_consumer`) 应该改为基于 Turn ID 的事件多路复用。

2. **添加超时控制**: `turn.run()` 当前没有内置超时参数，建议添加：
   ```python
   turn.run(timeout=timedelta(seconds=60))
   ```

3. **更细粒度的进度回调**: 当前只能消费完整事件流，建议添加回调式 API：
   ```python
   turn.run(on_delta=lambda delta: print(delta, end=""))
   ```

#### 6.3.2 错误处理层面

1. **Typed TurnError**: 当前 `turn.error` 是通用结构，建议根据 `codex_error_info` 提供更具体的异常类型。

2. **自动重试机制**: 对于 `ServerBusyError`，SDK 可以内置指数退避重试（当前仅在 `request_with_retry_on_overload` 中实现）。

#### 6.3.3 文档层面

1. **状态机文档**: Turn 状态转换图 (`in_progress` → `completed`/`failed`/`interrupted`) 应该更清晰文档化。

2. **事件顺序保证**: 明确文档化通知事件的顺序保证（如 `turn/started` 总是在 `item/*` 之前）。

### 6.4 测试覆盖建议

```python
# 建议添加的测试场景（参考 sdk/python/tests/）

# 1. Turn 失败场景
def test_turn_run_raises_on_failure():
    """Verify RuntimeError is raised when turn fails."""

# 2. Turn 中断场景  
def test_turn_run_handles_interruption():
    """Verify behavior when turn is interrupted."""

# 3. 并发 Turn 尝试场景
def test_concurrent_turn_stream_raises():
    """Verify RuntimeError on concurrent turn consumption."""

# 4. 持久化一致性验证
def test_turn_persisted_fields_match():
    """Verify persisted turn matches returned turn."""
```

---

## 7. 附录：完整调用链

### 7.1 同步调用链

```
sync.py:21
  thread.turn(TextInput(...))
    └─▶ api.py:507-538 Thread.turn()
          └─▶ _inputs.py:54-57 _to_wire_input()
          └─▶ client.py:352-363 turn_start() [RPC: turn/start]
          └─▶ api.py:643 TurnHandle 实例化

sync.py:21
  turn.run()
    └─▶ api.py:671-684 TurnHandle.run()
          └─▶ api.py:655-669 TurnHandle.stream()
                └─▶ client.py:288-296 acquire_turn_consumer()
                └─▶ client.py:275-286 next_notification() [循环消费]
                └─▶ client.py:298-301 release_turn_consumer()
```

### 7.2 异步调用链

```
async.py:25
  await turn.run()
    └─▶ api.py:722-735 AsyncTurnHandle.run()
          └─▶ api.py:705-720 AsyncTurnHandle.stream()
                └─▶ async_client.py:184-185 next_notification()
                      └─▶ async_client.py:54-62 _call_sync() [线程卸载]
```

---

*文档生成时间: 2026-03-22*
*基于代码版本: sdk/python @ 0.2.0*
