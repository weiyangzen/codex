# test_async_client_behavior.py 研究文档

## 场景与职责

本测试文件专注于验证 `AsyncAppServerClient` 的异步行为特性，特别是传输层的序列化保证和流式处理的并发控制。这是 Python SDK 中异步客户端的核心行为测试，确保在异步环境下对底层同步客户端的安全包装。

## 功能点目的

### 1. 传输调用序列化验证
- **目的**: 确保异步客户端对底层同步客户端的调用是串行化的
- **背景**: 由于 stdio 传输层无法安全地从多个线程并发读取，必须通过锁机制保证互斥访问
- **测试方法**: 通过并发调用 `model_list()` 并测量同时活跃的调用数

### 2. 流式增量传输验证
- **目的**: 确保 `stream_text()` 方法正确实现增量输出，并在流未完成时阻塞其他调用
- **测试内容**:
  - 验证流式输出按预期顺序产生增量数据
  - 验证流进行期间其他调用被阻塞
  - 验证流完成后阻塞解除

## 具体技术实现

### 传输序列化测试
```python
def test_async_client_serializes_transport_calls() -> None:
    async def scenario() -> int:
        client = AsyncAppServerClient()
        active = 0
        max_active = 0

        def fake_model_list(include_hidden: bool = False) -> bool:
            nonlocal active, max_active
            active += 1
            max_active = max(max_active, active)
            time.sleep(0.05)  # 模拟耗时操作
            active -= 1
            return include_hidden

        client._sync.model_list = fake_model_list  # 替换为模拟实现
        await asyncio.gather(client.model_list(), client.model_list())
        return max_active

    assert asyncio.run(scenario()) == 1  # 验证最大并发数为 1
```

**关键机制**:
- 使用 `asyncio.Lock()` 保护传输层访问
- 通过 `asyncio.to_thread()` 将同步调用 offload 到线程池
- 锁的获取和释放确保串行执行

### 流式处理测试
```python
def test_async_stream_text_is_incremental_and_blocks_parallel_calls() -> None:
    async def scenario() -> tuple[str, list[str], bool]:
        client = AsyncAppServerClient()

        def fake_stream_text(thread_id: str, text: str, params=None):
            yield "first"
            time.sleep(0.03)  # 模拟流延迟
            yield "second"
            yield "third"

        def fake_model_list(include_hidden: bool = False) -> str:
            return "done"

        client._sync.stream_text = fake_stream_text
        client._sync.model_list = fake_model_list

        stream = client.stream_text("thread-1", "hello")
        first = await anext(stream)

        # 在流未完成时尝试并发调用
        blocked_before_stream_done = False
        competing_call = asyncio.create_task(client.model_list())
        await asyncio.sleep(0.01)
        blocked_before_stream_done = not competing_call.done()

        # 消费剩余流数据
        remaining: list[str] = []
        async for item in stream:
            remaining.append(item)

        await competing_call
        return first, remaining, blocked_before_stream_done

    first, remaining, blocked = asyncio.run(scenario())
    assert first == "first"
    assert remaining == ["second", "third"]
    assert blocked  # 验证流期间调用被阻塞
```

**关键机制**:
- `stream_text()` 方法在获取传输锁后创建迭代器
- 使用 `asyncio.to_thread()` 在后台线程中消费同步迭代器
- 锁在整个流生命周期内保持，阻塞其他传输调用

## 关键代码路径与文件引用

### 被测试的核心文件
| 文件路径 | 相关实现 |
|---------|---------|
| `sdk/python/src/codex_app_server/async_client.py` | `AsyncAppServerClient` 类 |
| `sdk/python/src/codex_app_server/client.py` | `AppServerClient` 同步客户端 |

### AsyncAppServerClient 关键实现
```python
class AsyncAppServerClient:
    def __init__(self, config: AppServerConfig | None = None) -> None:
        self._sync = AppServerClient(config=config)
        self._transport_lock = asyncio.Lock()  # 传输层锁

    async def _call_sync(self, fn, /, *args, **kwargs):
        async with self._transport_lock:
            return await asyncio.to_thread(fn, *args, **kwargs)

    async def stream_text(self, thread_id, text, params=None):
        async with self._transport_lock:
            iterator = self._sync.stream_text(thread_id, text, params)
            while True:
                has_value, chunk = await asyncio.to_thread(self._next_from_iterator, iterator)
                if not has_value:
                    break
                yield chunk
```

### 关键测试断言
| 测试函数 | 关键断言 | 验证目标 |
|---------|---------|---------|
| `test_async_client_serializes_transport_calls` | `max_active == 1` | 传输调用串行化 |
| `test_async_stream_text_is_incremental_and_blocks_parallel_calls` | `first == "first"` | 流式数据顺序 |
| | `remaining == ["second", "third"]` | 增量数据完整性 |
| | `blocked == True` | 流期间阻塞生效 |

## 依赖与外部交互

### 标准库依赖
- `asyncio`: 异步编程核心库
- `time`: 用于模拟耗时操作

### 测试框架
- `pytest`: 测试框架（通过 `asyncio.run()` 运行异步测试）

### 被测试类的依赖
- `AppServerClient`: 同步客户端，被包装在异步客户端内部
- `AppServerConfig`: 配置对象

## 风险、边界与改进建议

### 潜在风险
1. **时间敏感测试**: 测试使用 `time.sleep()` 模拟延迟，在慢速或高负载系统上可能不稳定
2. **线程池耗尽**: `asyncio.to_thread()` 使用默认线程池，大量并发调用可能耗尽线程
3. **死锁风险**: 如果在流式处理中尝试获取同一把锁，可能导致死锁

### 边界情况
1. **空流处理**: 测试未覆盖流立即结束的情况
2. **异常处理**: 测试未覆盖流中抛出异常的情况
3. **取消处理**: 测试未覆盖 `asyncio.CancelledError` 的处理

### 改进建议
1. **使用确定性同步原语**: 替换 `time.sleep()` 为 `asyncio.Event` 或 `threading.Event`
   ```python
   def test_async_client_serializes_transport_calls():
       lock = asyncio.Lock()
       
       async def fake_model_list():
           async with lock:
               return "done"
       
       # 验证第二个调用等待第一个完成
   ```

2. **增加异常处理测试**:
   ```python
   def test_async_stream_handles_exception():
       def fake_stream_that_fails():
           yield "first"
           raise RuntimeError("stream error")
       
       # 验证异常正确传播到调用者
   ```

3. **增加取消测试**:
   ```python
   def test_async_stream_can_be_cancelled():
       async def scenario():
           stream = client.stream_text("thread-1", "hello")
           task = asyncio.create_task(anext(stream))
           await asyncio.sleep(0.01)
           task.cancel()
           
           with pytest.raises(asyncio.CancelledError):
               await task
   ```

4. **增加并发压力测试**:
   ```python
   @pytest.mark.parametrize("concurrency", [5, 10, 50])
   def test_async_client_handles_high_concurrency(concurrency):
       # 验证在高并发下仍然保持串行化
   ```

5. **文档化线程安全保证**: 在 `AsyncAppServerClient` 的 docstring 中明确说明线程安全保证
   ```python
   class AsyncAppServerClient:
       """Async wrapper around AppServerClient.
       
       All transport calls are serialized via an internal lock to ensure
       thread-safe access to the underlying stdio transport.
       """
   ```
