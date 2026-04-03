# sdk/python/src/codex_app_server/async_client.py 研究文档

## 场景与职责

`async_client.py` 是 Codex Python SDK 的**异步客户端包装模块**，通过线程卸载（thread offloading）模式为同步的 `AppServerClient` 提供异步接口。它承担着：

1. **异步适配**：将同步阻塞的 JSON-RPC 调用转换为异步非阻塞操作
2. **传输序列化**：确保对底层 stdio 传输的访问是线程安全的
3. **流式支持**：支持异步迭代器模式的流式响应
4. **API 对等**：提供与同步客户端完全一致的异步 API

## 功能点目的

### 1. AsyncAppServerClient 类

核心异步客户端类，包装同步 `AppServerClient`：

```python
class AsyncAppServerClient:
    def __init__(self, config: AppServerConfig | None = None) -> None:
        self._sync = AppServerClient(config=config)
        self._transport_lock = asyncio.Lock()  # 传输层锁
```

### 2. 线程卸载模式

所有同步操作通过 `asyncio.to_thread` 在后台线程执行：

```python
async def _call_sync(
    self,
    fn: Callable[ParamsT, ReturnT],
    /,
    *args: ParamsT.args,
    **kwargs: ParamsT.kwargs,
) -> ReturnT:
    async with self._transport_lock:
        return await asyncio.to_thread(fn, *args, **kwargs)
```

### 3. 核心方法映射

| 异步方法 | 同步对应 | 说明 |
|---------|---------|------|
| `start()` | `AppServerClient.start()` | 启动子进程 |
| `close()` | `AppServerClient.close()` | 关闭连接 |
| `initialize()` | `AppServerClient.initialize()` | 初始化握手 |
| `request()` | `AppServerClient.request()` | 通用 RPC 请求 |
| `thread_start()` | `AppServerClient.thread_start()` | 创建线程 |
| `thread_resume()` | `AppServerClient.thread_resume()` | 恢复线程 |
| `thread_list()` | `AppServerClient.thread_list()` | 列出线程 |
| `turn_start()` | `AppServerClient.turn_start()` | 启动 Turn |
| `next_notification()` | `AppServerClient.next_notification()` | 获取通知 |

### 4. 特殊流式方法

`stream_text()` 方法支持异步迭代器：

```python
async def stream_text(
    self,
    thread_id: str,
    text: str,
    params: V2TurnStartParams | JsonObject | None = None,
) -> AsyncIterator[AgentMessageDeltaNotification]:
    async with self._transport_lock:
        iterator = self._sync.stream_text(thread_id, text, params)
        while True:
            has_value, chunk = await asyncio.to_thread(
                self._next_from_iterator,
                iterator,
            )
            if not has_value:
                break
            yield chunk
```

## 具体技术实现

### 线程卸载机制

```
调用者协程
    │
    ├── async with _transport_lock  # 获取锁
    │       │
    │       └── await asyncio.to_thread(sync_fn, *args)
    │               │
    │               ├── 线程池调度
    │               │       │
    │               │       └── sync_fn(*args)  # 在后台线程执行
    │               │               │
    │               │               └── 返回结果
    │               │
    │               └── 结果传回协程
    │
    └── 锁释放
```

**关键设计：**
- `asyncio.Lock` 确保同一时间只有一个协程访问传输层
- `asyncio.to_thread`（Python 3.9+）将同步调用卸载到线程池
- 锁的粒度：每个 RPC 调用持有锁，而非整个会话

### 流式迭代器实现

```python
@staticmethod
def _next_from_iterator(
    iterator: Iterator[AgentMessageDeltaNotification],
) -> tuple[bool, AgentMessageDeltaNotification | None]:
    try:
        return True, next(iterator)
    except StopIteration:
        return False, None

async def stream_text(...) -> AsyncIterator[AgentMessageDeltaNotification]:
    async with self._transport_lock:
        iterator = self._sync.stream_text(...)  # 获取同步迭代器
        while True:
            has_value, chunk = await asyncio.to_thread(
                self._next_from_iterator, iterator  # 逐个获取
            )
            if not has_value:
                break
            yield chunk  # 异步产出
```

**设计考量：**
- 整个流期间持有 `_transport_lock`，阻止其他并发调用
- 使用静态方法 `_next_from_iterator` 捕获 `StopIteration`
- 异步产出允许其他协程在迭代间隙执行

### 生命周期管理

```python
async def __aenter__(self) -> "AsyncAppServerClient":
    await self.start()
    return self

async def __aexit__(self, _exc_type, _exc, _tb) -> None:
    await self.close()
```

支持 `async with` 语法：
```python
async with AsyncAppServerClient() as client:
    result = await client.thread_start(...)
```

### Turn 消费者管理

```python
def acquire_turn_consumer(self, turn_id: str) -> None:
    self._sync.acquire_turn_consumer(turn_id)  # 直接委托

def release_turn_consumer(self, turn_id: str) -> None:
    self._sync.release_turn_consumer(turn_id)  # 直接委托
```

注意：这两个方法是同步的，因为它们只操作内存状态，不涉及 I/O。

## 关键代码路径与文件引用

### 模块依赖图

```
async_client.py
├── asyncio                  # 核心异步支持
├── collections.abc.Iterator # 类型注解
├── typing                   # 泛型类型
├── pydantic.BaseModel       # 响应模型基类
├── client.py                # AppServerClient, AppServerConfig
├── generated.v2_all         # 生成模型
└── models.py                # InitializeResponse, Notification
```

### 调用链示例

**异步线程创建：**
```
用户代码: await AsyncCodex().thread_start()
    │
    ├── AsyncCodex._ensure_initialized()
    │   └── AsyncAppServerClient.start()
    │       └── _call_sync(AppServerClient.start)
    │           └── asyncio.to_thread(...)
    │
    └── AsyncCodex.thread_start()
        └── AsyncAppServerClient.thread_start(params)
            └── _call_sync(AppServerClient.thread_start, params)
                └── asyncio.to_thread(...)
```

**异步流式调用：**
```
用户代码: async for chunk in client.stream_text(...)
    │
    └── AsyncAppServerClient.stream_text()
        ├── async with _transport_lock:  # 获取锁
        │   ├── iterator = self._sync.stream_text(...)  # 创建同步迭代器
        │   │
        │   └── while True:
        │       ├── await asyncio.to_thread(_next_from_iterator, iterator)
        │       │   └── next(iterator)  # 在后台线程执行
        │       │
        │       └── yield chunk  # 异步产出
        │
        └── 锁释放（流结束）
```

## 依赖与外部交互

### 直接依赖

| 模块 | 导入符号 | 用途 |
|-----|---------|------|
| `asyncio` | `Lock`, `to_thread` | 异步核心 |
| `collections.abc` | `Iterator` | 类型注解 |
| `typing` | `AsyncIterator`, `Callable`, `ParamSpec`, `TypeVar` | 泛型 |
| `pydantic` | `BaseModel` | 响应模型基类 |
| `.client` | `AppServerClient`, `AppServerConfig` | 同步客户端 |
| `.generated.v2_all` | 响应模型、参数模型 | API 类型 |
| `.models` | `InitializeResponse`, `JsonObject`, `Notification` | 核心模型 |

### 与同步客户端的关系

```
AsyncAppServerClient
    └── _sync: AppServerClient
        ├── _proc: subprocess.Popen  # stdio 传输
        ├── _lock: threading.Lock   # 线程锁
        └── ...
```

**设计模式：适配器 + 代理**
- 适配器：将同步接口适配为异步接口
- 代理：委托实际工作给 `_sync` 实例

## 风险、边界与改进建议

### 当前风险

1. **全局解释器锁（GIL）**：虽然使用了线程池，但 Python GIL 可能限制 CPU 密集型操作的并行性（不过 I/O 操作会释放 GIL）
2. **锁粒度**：`_transport_lock` 在流式调用期间一直持有，阻止了真正的并发
3. **线程池耗尽**：大量并发调用可能耗尽默认线程池
4. **异常传播**：后台线程的异常需要正确包装和传递

### 边界情况

1. **并发流式调用**：由于 `_transport_lock`，第二个 `stream_text()` 会阻塞直到第一个完成
2. **取消处理**：`asyncio.CancelledError` 可能发生在 `to_thread` 等待期间，需要正确处理
3. **迭代器状态**：如果异步迭代被中途取消，同步迭代器可能处于不确定状态
4. **线程安全**：`acquire_turn_consumer` / `release_turn_consumer` 直接委托给同步客户端，依赖其内部锁

### 改进建议

1. **使用原生异步传输**：
   当前使用线程卸载是因为底层 `AppServerClient` 使用同步 stdio。可以考虑实现原生异步传输：
   ```python
   class AsyncAppServerClientNative:
       async def _read_message(self) -> dict[str, JsonValue]:
           line = await self._proc.stdout.readline()  # 原生异步
           return json.loads(line)
   ```

2. **更细粒度的锁**：
   将锁的粒度从"整个调用"降低到"单次读写"：
   ```python
   async def _write_message(self, payload: JsonObject) -> None:
       async with self._write_lock:
           await self._writer.write(json.dumps(payload) + "\n")
   
   async def _read_message(self) -> dict[str, JsonValue]:
       async with self._read_lock:
           line = await self._reader.readline()
           return json.loads(line)
   ```

3. **背压控制**：
   流式方法应支持背压，避免内存无限增长：
   ```python
   async def stream_text(self, ...) -> AsyncIterator[...]:
       queue: asyncio.Queue[...] = asyncio.Queue(maxsize=100)
       # 生产者-消费者模式
   ```

4. **超时支持**：
   所有方法应支持超时参数：
   ```python
   async def request(
       self, ..., timeout: float | None = None
   ) -> ModelT:
       return await asyncio.wait_for(
           self._call_sync(...),
           timeout=timeout
       )
   ```

5. **性能优化**：
   - 使用 `asyncio.Event` 替代轮询
   - 批量处理通知而非逐个
   - 连接池支持（如果服务器支持多路复用）

### 测试覆盖

相关测试文件：
- `test_async_client_behavior.py`：专门测试异步客户端行为

关键测试场景：
```python
def test_async_client_serializes_transport_calls() -> None:
    """验证传输层调用被序列化（同一时间只有一个活跃调用）"""
    
def test_async_stream_text_is_incremental_and_blocks_parallel_calls() -> None:
    """验证流式调用期间其他调用被阻塞"""
```

这些测试验证了：
- 并发调用被正确序列化（`max_active == 1`）
- 流式调用期间其他调用被阻塞
- 流式数据被正确增量产出
