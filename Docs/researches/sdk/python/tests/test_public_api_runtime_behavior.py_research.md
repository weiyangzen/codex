# test_public_api_runtime_behavior.py 研究文档

## 场景与职责

本测试文件是 Python SDK 中最全面的测试文件之一，专注于验证公共 API 层（`api.py`）的运行时行为。它测试了同步和异步客户端的生命周期管理、线程和 Turn 的操作流程、流式处理、错误处理等核心功能。

## 功能点目的

### 1. 客户端生命周期管理
- **目的**: 确保客户端初始化和关闭的正确性
- **测试内容**:
  - 初始化失败时自动关闭客户端
  - 异步客户端的延迟初始化（lazy initialization）
  - 并发场景下的单次初始化保证

### 2. Turn 流式处理控制
- **目的**: 确保 Turn 流式处理的并发控制
- **测试内容**:
  - 拒绝第二个活跃消费者（并发流限制）
  - 同步和异步场景的流式处理

### 3. Thread.run() 结果收集
- **目的**: 验证 `Thread.run()` 和 `AsyncThread.run()` 的结果收集逻辑
- **测试内容**:
  - 字符串输入的处理
  - 最终响应的提取（最后一条助手消息）
  - 空消息的处理
  - `MessagePhase` 的处理（优先使用 `final_answer`）
  - 纯 commentary 消息的处理
  - 失败 Turn 的错误抛出

### 4. 错误处理示例验证
- **目的**: 确保示例代码使用正确的错误处理方式
- **测试内容**: 验证示例代码使用 `TurnStatus.failed` 枚举而非字符串比较

## 具体技术实现

### 客户端初始化失败处理
```python
def test_codex_init_failure_closes_client(monkeypatch: pytest.MonkeyPatch) -> None:
    closed: list[bool] = []

    class FakeClient:
        def __init__(self, config=None) -> None: ...
        def start(self) -> None: ...
        def initialize(self) -> InitializeResponse:
            return InitializeResponse.model_validate({})  # 空响应，缺少元数据
        def close(self) -> None:
            self._closed = True
            closed.append(True)

    monkeypatch.setattr(public_api_module, "AppServerClient", FakeClient)

    with pytest.raises(RuntimeError, match="missing required metadata"):
        Codex()  # 初始化应失败

    assert closed == [True]  # 验证 close() 被调用
```

**关键机制**:
- 使用 `monkeypatch` 替换 `AppServerClient` 为模拟实现
- 模拟返回缺少元数据的 `InitializeResponse`
- 验证 `Codex.__init__` 在异常时调用 `close()`

### 异步客户端并发初始化
```python
def test_async_codex_initializes_only_once_under_concurrency() -> None:
    async def scenario() -> None:
        codex = AsyncCodex()
        start_calls = 0
        initialize_calls = 0
        ready = asyncio.Event()

        async def fake_start() -> None:
            nonlocal start_calls
            start_calls += 1

        async def fake_initialize() -> InitializeResponse:
            nonlocal initialize_calls
            initialize_calls += 1
            ready.set()
            await asyncio.sleep(0.02)  # 模拟耗时初始化
            return InitializeResponse.model_validate({...})

        async def fake_model_list(include_hidden: bool = False):
            await ready.wait()  # 等待初始化完成信号
            return object()

        codex._client.start = fake_start
        codex._client.initialize = fake_initialize
        codex._client.model_list = fake_model_list

        await asyncio.gather(codex.models(), codex.models())  # 并发调用

        assert start_calls == 1  # 只启动一次
        assert initialize_calls == 1  # 只初始化一次
```

**关键机制**:
- 使用 `asyncio.Lock()` 保护初始化过程
- 使用 `asyncio.Event()` 协调并发调用
- 验证即使并发调用 API，初始化也只执行一次

### Turn 并发消费者限制
```python
def test_turn_stream_rejects_second_active_consumer() -> None:
    client = AppServerClient()
    notifications: deque[Notification] = deque([
        _delta_notification(turn_id="turn-1"),
        _completed_notification(turn_id="turn-1"),
    ])
    client.next_notification = notifications.popleft  # 模拟通知序列

    first_stream = TurnHandle(client, "thread-1", "turn-1").stream()
    assert next(first_stream).method == "item/agentMessage/delta"  # 第一个消费者开始

    second_stream = TurnHandle(client, "thread-1", "turn-2").stream()
    with pytest.raises(RuntimeError, match="Concurrent turn consumers are not yet supported"):
        next(second_stream)  # 第二个消费者应被拒绝

    first_stream.close()
```

**关键机制**:
- `AppServerClient` 维护 `_active_turn_consumer` 状态
- `acquire_turn_consumer()` 在已有活跃消费者时抛出异常
- `release_turn_consumer()` 在流结束时释放锁

### RunResult 收集逻辑
```python
def test_thread_run_uses_last_completed_assistant_message_as_final_response() -> None:
    client = AppServerClient()
    first_item_notification = _item_completed_notification(text="First message")
    second_item_notification = _item_completed_notification(text="Second message")
    notifications: deque[Notification] = deque([
        first_item_notification,
        second_item_notification,
        _completed_notification(),
    ])
    client.next_notification = notifications.popleft
    client.turn_start = lambda ...: SimpleNamespace(turn=SimpleNamespace(id="turn-1"))

    result = Thread(client, "thread-1").run("hello")

    assert result.final_response == "Second message"  # 使用最后一条消息
    assert result.items == [first_item_notification.payload.item, second_item_notification.payload.item]
```

**关键机制**:
- `_collect_run_result()` 遍历通知流
- `_final_assistant_response_from_items()` 从后向前查找助手消息
- 优先返回 `phase == MessagePhase.final_answer` 的消息

### MessagePhase 处理
```python
def test_thread_run_prefers_explicit_final_answer_over_later_commentary() -> None:
    final_answer_notification = _item_completed_notification(
        text="Final answer",
        phase=MessagePhase.final_answer,
    )
    commentary_notification = _item_completed_notification(
        text="Commentary",
        phase=MessagePhase.commentary,
    )
    # ... 即使 commentary 在后，也优先使用 final_answer
    assert result.final_response == "Final answer"
```

**MessagePhase 优先级**:
1. `final_answer`: 最高优先级，作为最终响应
2. `None` (未设置): 次高优先级，如果后面没有 `final_answer`
3. `commentary`: 最低优先级，不用于最终响应

## 关键代码路径与文件引用

### 被测试的核心文件
| 文件路径 | 相关实现 |
|---------|---------|
| `sdk/python/src/codex_app_server/api.py` | `Codex`, `AsyncCodex`, `Thread`, `AsyncThread`, `TurnHandle`, `AsyncTurnHandle` |
| `sdk/python/src/codex_app_server/client.py` | `AppServerClient` |
| `sdk/python/src/codex_app_server/async_client.py` | `AsyncAppServerClient` |
| `sdk/python/src/codex_app_server/_run.py` | `_collect_run_result()`, `_collect_async_run_result()` |
| `sdk/python/src/codex_app_server/models.py` | `InitializeResponse`, `Notification` |

### 通知辅助函数
```python
def _delta_notification(*, thread_id: str = "thread-1", turn_id: str = "turn-1", text: str = "delta-text") -> Notification:
    return Notification(
        method="item/agentMessage/delta",
        payload=AgentMessageDeltaNotification.model_validate({...})
    )

def _completed_notification(*, thread_id: str = "thread-1", turn_id: str = "turn-1", status: str = "completed") -> Notification:
    return Notification(
        method="turn/completed",
        payload=TurnCompletedNotification.model_validate({...})
    )

def _item_completed_notification(*, thread_id: str = "thread-1", turn_id: str = "turn-1", text: str = "final text", phase: MessagePhase | None = None) -> Notification:
    return Notification(
        method="item/completed",
        payload=ItemCompletedNotification.model_validate({...})
    )
```

### 关键测试断言
| 测试函数 | 关键断言 | 验证目标 |
|---------|---------|---------|
| `test_codex_init_failure_closes_client` | `closed == [True]` | 失败时关闭客户端 |
| `test_async_codex_init_failure_closes_client` | `close_calls == 1` | 异步失败时关闭 |
| `test_async_codex_initializes_only_once_under_concurrency` | `start_calls == 1` | 并发单次初始化 |
| `test_turn_stream_rejects_second_active_consumer` | `RuntimeError` | 并发消费者限制 |
| `test_thread_run_accepts_string_input_and_returns_run_result` | `seen["wire_input"] == [{"type": "text", "text": "hello"}]` | 字符串输入转换 |
| `test_thread_run_uses_last_completed_assistant_message_as_final_response` | `final_response == "Second message"` | 最后消息优先 |
| `test_thread_run_prefers_explicit_final_answer_over_later_commentary` | `final_response == "Final answer"` | phase 优先级 |
| `test_thread_run_raises_on_failed_turn` | `RuntimeError` | 失败 Turn 抛出错误 |
| `test_retry_examples_compare_status_with_enum` | `"TurnStatus.failed" in source` | 正确使用枚举 |

## 依赖与外部交互

### 测试框架
- `pytest`: 测试框架
- `pytest.MonkeyPatch`: 用于模拟依赖
- `asyncio`: 异步测试支持

### 标准库
- `collections.deque`: 用于模拟通知队列
- `types.SimpleNamespace`: 用于创建简单对象

### 内部依赖
- `codex_app_server.api`: 公共 API 层
- `codex_app_server.generated.v2_all`: 生成的模型
- `codex_app_server.models`: 核心模型

## 风险、边界与改进建议

### 潜在风险
1. **测试复杂度高**: 大量模拟和依赖注入使测试脆弱，实现变更容易破坏测试
2. **时间敏感**: 异步测试使用 `asyncio.sleep()`，在慢速系统上可能不稳定
3. **覆盖不完整**: 某些边界条件（如网络断开、超时）未测试

### 边界情况
1. **空流**: 如果 Turn 没有产生任何通知，行为未定义
2. **异常中断**: 流处理中途抛出异常的资源清理
3. **大消息**: 大量通知消息时的内存和性能表现

### 改进建议
1. **使用确定性同步**: 替换 `asyncio.sleep()` 为 `asyncio.Event`
   ```python
   ready = asyncio.Event()
   async def fake_initialize():
       ready.set()
       await asyncio.Event().wait()  # 等待外部信号
   ```

2. **增加资源清理验证**:
   ```python
   def test_turn_stream_cleanup_on_exception():
       # 验证即使发生异常，turn consumer 锁也被释放
   ```

3. **增加超时测试**:
   ```python
   def test_turn_run_timeout():
       # 验证长时间运行的 Turn 可以被中断
   ```

4. **增加内存压力测试**:
   ```python
   def test_large_stream_processing():
       # 验证可以处理大量通知而不耗尽内存
   ```

5. **参数化测试**: 使用 `@pytest.mark.parametrize` 减少重复代码
   ```python
   @pytest.mark.parametrize("client_class", [Codex, AsyncCodex])
   def test_client_init_failure(client_class):
       # 同时测试同步和异步客户端
   ```
