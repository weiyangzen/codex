# sdk/python/src/codex_app_server/retry.py 研究文档

## 场景与职责

`retry.py` 是 Codex Python SDK 的**重试逻辑实现模块**，提供针对服务器过载错误的自动重试机制。它承担着：

1. **重试策略实现**：指数退避 + 抖动的重试策略
2. **错误分类**：识别可重试的瞬态错误
3. **用户友好接口**：提供简单易用的重试装饰器/函数
4. **可配置性**：允许自定义重试次数、延迟等参数

## 功能点目的

### 1. retry_on_overload 函数

核心重试函数，用于包装可能因服务器过载而失败的操作：

```python
def retry_on_overload(
    op: Callable[[], T],
    *,
    max_attempts: int = 3,
    initial_delay_s: float = 0.25,
    max_delay_s: float = 2.0,
    jitter_ratio: float = 0.2,
) -> T:
```

**参数说明：**

| 参数 | 默认值 | 说明 |
|-----|-------|------|
| `op` | 必需 | 要执行的可调用对象（无参函数） |
| `max_attempts` | 3 | 最大尝试次数 |
| `initial_delay_s` | 0.25 | 初始延迟（秒） |
| `max_delay_s` | 2.0 | 最大延迟（秒） |
| `jitter_ratio` | 0.2 | 抖动比例（±20%） |

### 2. 重试策略

**指数退避 + 抖动：**

```
第 1 次：立即执行
第 2 次：延迟 0.25s ± 20% 抖动
第 3 次：延迟 0.5s ± 20% 抖动
...
最大延迟：2.0s
```

**算法实现：**
```python
delay = initial_delay_s
attempt = 0
while True:
    attempt += 1
    try:
        return op()
    except Exception as exc:
        if attempt >= max_attempts:
            raise
        if not is_retryable_error(exc):
            raise
        
        jitter = delay * jitter_ratio
        sleep_for = min(max_delay_s, delay) + random.uniform(-jitter, jitter)
        if sleep_for > 0:
            time.sleep(sleep_for)
        delay = min(max_delay_s, delay * 2)  # 指数增长
```

## 具体技术实现

### 错误判断

重试仅针对可重试的错误：

```python
from .errors import is_retryable_error

# 在重试循环中
if not is_retryable_error(exc):
    raise  # 不可重试的错误立即抛出
```

`is_retryable_error` 判断逻辑（在 `errors.py` 中）：
- `ServerBusyError` 及其子类
- `JsonRpcError` 且 `data` 包含 `server_overloaded` 标记

### 抖动计算

```python
jitter = delay * jitter_ratio  # 例如：0.25 * 0.2 = 0.05
sleep_for = min(max_delay_s, delay) + random.uniform(-jitter, jitter)
# 结果范围：[delay - jitter, delay + jitter]
# 例如：[0.20, 0.30]
```

**抖动的目的：**
- 避免多个客户端在同一时间重试（"惊群效应"）
- 分散服务器负载

### 延迟上限

```python
delay = min(max_delay_s, delay * 2)
```

确保延迟不会无限增长，避免过长的等待时间。

## 关键代码路径与文件引用

### 模块依赖图

```
retry.py
├── __future__.annotations    # 延迟类型注解求值
├── random                    # 随机抖动
├── time                      # 睡眠延迟
├── typing.Callable           # 类型注解
├── typing.TypeVar            # 泛型类型变量
└── errors.is_retryable_error # 错误判断

被依赖方：
├── client.py          # AppServerClient.request_with_retry_on_overload
├── __init__.py        # 导出 retry_on_overload
└── 用户代码            # 直接使用
```

### 使用场景

**SDK 内部使用（client.py）：**
```python
def request_with_retry_on_overload(
    self,
    method: str,
    params: JsonObject | None,
    *,
    response_model: type[ModelT],
    max_attempts: int = 3,
    initial_delay_s: float = 0.25,
    max_delay_s: float = 2.0,
) -> ModelT:
    return retry_on_overload(
        lambda: self.request(method, params, response_model=response_model),
        max_attempts=max_attempts,
        initial_delay_s=initial_delay_s,
        max_delay_s=max_delay_s,
    )
```

**用户直接使用（示例代码）：**
```python
from codex_app_server import Codex, retry_on_overload

with Codex() as codex:
    thread = codex.thread_start(model="gpt-5.4")
    
    result = retry_on_overload(
        lambda: thread.turn(TextInput("...")).run(),
        max_attempts=3,
        initial_delay_s=0.25,
        max_delay_s=2.0,
    )
```

### 调用链

```
用户代码 / SDK 内部
    │
    └── retry_on_overload(lambda: operation())
        │
        ├── attempt = 1
        │   └── try: operation()
        │       ├── 成功 → 返回结果
        │       └── 失败（可重试错误）
        │           └── sleep(0.25 ± 抖动)
        │
        ├── attempt = 2
        │   └── try: operation()
        │       ├── 成功 → 返回结果
        │       └── 失败（可重试错误）
        │           └── sleep(0.5 ± 抖动)
        │
        ├── attempt = 3
        │   └── try: operation()
        │       ├── 成功 → 返回结果
        │       └── 失败 → 抛出异常
        │
        └── 达到 max_attempts，抛出最后一次异常
```

## 依赖与外部交互

### 直接依赖

| 模块 | 导入符号 | 用途 |
|-----|---------|------|
| `__future__` | `annotations` | 延迟类型注解求值 |
| `random` | `uniform` | 生成随机抖动 |
| `time` | `sleep` | 延迟等待 |
| `typing` | `Callable`, `TypeVar` | 类型注解 |
| `.errors` | `is_retryable_error` | 判断错误是否可重试 |

### 被依赖方

| 模块 | 使用方式 |
|-----|---------|
| `client.py` | `AppServerClient.request_with_retry_on_overload` 使用 |
| `__init__.py` | 导出为公共 API |
| 用户代码 | 直接使用 `retry_on_overload` |

## 风险、边界与改进建议

### 当前风险

1. **同步阻塞**：`time.sleep` 是同步阻塞调用，在异步代码中使用会阻塞事件循环
2. **无超时控制**：没有整体超时限制，如果 `max_attempts` 很大且每次延迟很长，可能长时间阻塞
3. **异常信息丢失**：多次重试的异常信息只保留最后一次，可能丢失有价值的调试信息
4. **无回调机制**：无法监控重试过程（如记录日志、发送指标）

### 边界情况

1. **max_attempts < 1**：函数会立即抛出 `ValueError`
2. **负延迟**：如果计算出的 `sleep_for` 为负数（极端抖动情况），函数会立即重试
3. **不可重试错误**：立即抛出，不会等待
4. **非异常返回值**：如果 `op()` 返回表示错误的结果（而非抛出异常），重试机制不会触发

### 改进建议

1. **异步版本**：
   ```python
   import asyncio
   
   async def retry_on_overload_async(
       op: Callable[[], Awaitable[T]],
       *,
       max_attempts: int = 3,
       initial_delay_s: float = 0.25,
       max_delay_s: float = 2.0,
       jitter_ratio: float = 0.2,
   ) -> T:
       delay = initial_delay_s
       attempt = 0
       last_exception: Exception | None = None
       
       while True:
           attempt += 1
           try:
               return await op()
           except Exception as exc:
               if attempt >= max_attempts:
                   raise
               if not is_retryable_error(exc):
                   raise
               
               jitter = delay * jitter_ratio
               sleep_for = min(max_delay_s, delay) + random.uniform(-jitter, jitter)
               if sleep_for > 0:
                   await asyncio.sleep(sleep_for)  # 非阻塞睡眠
               delay = min(max_delay_s, delay * 2)
   ```

2. **添加回调钩子**：
   ```python
   def retry_on_overload(
       op: Callable[[], T],
       *,
       max_attempts: int = 3,
       on_retry: Callable[[int, Exception, float], None] | None = None,
       # on_retry(attempt_number, exception, next_delay)
       ...
   ) -> T:
       ...
       if on_retry:
           on_retry(attempt, exc, sleep_for)
   ```

3. **异常链保留**：
   ```python
   if attempt >= max_attempts:
       raise RetryExhaustedError(
           f"Failed after {max_attempts} attempts"
       ) from exc
   ```

4. **整体超时控制**：
   ```python
   import signal
   
   def retry_on_overload(
       op: Callable[[], T],
       *,
       max_attempts: int = 3,
       total_timeout_s: float | None = None,
       ...
   ) -> T:
       start_time = time.monotonic()
       ...
       if total_timeout_s and (time.monotonic() - start_time) > total_timeout_s:
           raise TimeoutError(f"Retry exceeded total timeout of {total_timeout_s}s")
   ```

5. **退避策略可配置**：
   ```python
   from enum import Enum
   
   class BackoffStrategy(Enum):
       EXPONENTIAL = "exponential"
       LINEAR = "linear"
       FIXED = "fixed"
   
   def retry_on_overload(
       op: Callable[[], T],
       *,
       backoff_strategy: BackoffStrategy = BackoffStrategy.EXPONENTIAL,
       ...
   ) -> T:
       if backoff_strategy == BackoffStrategy.EXPONENTIAL:
           delay = min(max_delay_s, delay * 2)
       elif backoff_strategy == BackoffStrategy.LINEAR:
           delay = min(max_delay_s, delay + initial_delay_s)
       # ...
   ```

6. **重试统计**：
   ```python
   @dataclass
   class RetryStats:
       attempts: int
       total_delay: float
       exceptions: list[Exception]
   
   def retry_on_overload(
       op: Callable[[], T],
       *,
       collect_stats: bool = False,
       ...
   ) -> T | tuple[T, RetryStats]:
       # 返回结果和统计信息
   ```

### 测试覆盖

相关测试场景（应在 `test_client_rpc_methods.py` 或专门测试文件中）：

```python
def test_retry_on_overload_succeeds_on_first_attempt():
    call_count = 0
    def op():
        nonlocal call_count
        call_count += 1
        return "success"
    
    result = retry_on_overload(op, max_attempts=3)
    assert result == "success"
    assert call_count == 1

def test_retry_on_overload_retries_on_server_busy():
    call_count = 0
    def op():
        nonlocal call_count
        call_count += 1
        if call_count < 3:
            raise ServerBusyError(-32000, "busy")
        return "success"
    
    result = retry_on_overload(op, max_attempts=3)
    assert result == "success"
    assert call_count == 3

def test_retry_on_overload_raises_immediately_on_non_retryable_error():
    call_count = 0
    def op():
        nonlocal call_count
        call_count += 1
        raise ValueError("not retryable")
    
    with pytest.raises(ValueError):
        retry_on_overload(op, max_attempts=3)
    assert call_count == 1

def test_retry_on_overload_validates_max_attempts():
    with pytest.raises(ValueError, match="max_attempts must be >= 1"):
        retry_on_overload(lambda: None, max_attempts=0)
```

### 示例代码

SDK 提供的示例代码（`examples/10_error_handling_and_retry/sync.py`）：

```python
from codex_app_server import (
    Codex,
    JsonRpcError,
    ServerBusyError,
    TextInput,
    TurnStatus,
    retry_on_overload,
)

with Codex(config=runtime_config()) as codex:
    thread = codex.thread_start(model="gpt-5.4")
    
    try:
        result = retry_on_overload(
            lambda: thread.turn(TextInput("Summarize retry best practices in 3 bullets.")).run(),
            max_attempts=3,
            initial_delay_s=0.25,
            max_delay_s=2.0,
        )
    except ServerBusyError as exc:
        print("Server overloaded after retries:", exc.message)
    except JsonRpcError as exc:
        print(f"JSON-RPC error {exc.code}: {exc.message}")
```
