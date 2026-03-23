# async.py 研究文档

## 场景与职责

`async.py` 是 Codex Python SDK 的异步错误处理与重试机制示例代码。它演示了如何在异步环境下处理服务器过载（Server Overload）等瞬态错误，并实现指数退避（Exponential Backoff）重试策略。

该文件属于 SDK 示例集合中的第 10 个示例（`10_error_handling_and_retry`），与同步版本 `sync.py` 形成对比，展示了异步编程模式下的最佳实践。

## 功能点目的

### 1. 异步重试包装器 (`retry_on_overload_async`)
- **目的**：为异步操作提供自动重试机制，专门处理服务器过载类错误
- **策略**：指数退避 + 随机抖动（Jitter），避免重试风暴
- **可配置参数**：
  - `max_attempts`: 最大重试次数（默认 3）
  - `initial_delay_s`: 初始延迟秒数（默认 0.25s）
  - `max_delay_s`: 最大延迟上限（默认 2.0s）
  - `jitter_ratio`: 抖动比例（默认 0.2，即 ±20%）

### 2. 错误分类处理
- `ServerBusyError`: 服务器过载，可重试
- `JsonRpcError`: JSON-RPC 协议错误，记录错误码和消息
- 其他错误：直接抛出，不进行重试

### 3. 异步线程操作
- 使用 `AsyncCodex` 进行异步上下文管理
- 创建线程并发送文本输入
- 读取持久化的对话历史

## 具体技术实现

### 关键流程

```
main()
  ├── AsyncCodex(config=runtime_config())  # 初始化异步客户端
  ├── thread_start(model="gpt-5.4", ...)   # 创建新线程
  ├── retry_on_overload_async()            # 带重试的执行
  │     ├── _run_turn()                    # 包装 turn 操作
  │     │     └── thread.turn(TextInput)   # 创建 turn
  │     │     └── turn.run()               # 执行并等待结果
  │     └── 指数退避重试逻辑               # 失败时自动重试
  ├── thread.read()                        # 读取完整线程数据
  └── 结果提取与展示
```

### 重试算法实现

```python
delay = initial_delay_s
attempt = 0
while True:
    attempt += 1
    try:
        return await op()  # 执行异步操作
    except Exception as exc:
        # 检查是否可重试
        if attempt >= max_attempts or not is_retryable_error(exc):
            raise
        
        # 计算带抖动的延迟
        jitter = delay * jitter_ratio
        sleep_for = min(max_delay_s, delay) + random.uniform(-jitter, jitter)
        if sleep_for > 0:
            await asyncio.sleep(sleep_for)
        
        # 指数增加延迟
        delay = min(max_delay_s, delay * 2)
```

### 数据结构

| 类型 | 来源 | 用途 |
|------|------|------|
| `AsyncCodex` | `codex_app_server` | 异步 SDK 主入口 |
| `TextInput` | `codex_app_server` | 文本输入包装器 |
| `TurnStatus` | `codex_app_server` | Turn 状态枚举 |
| `ResultT` | TypeVar | 泛型返回类型 |

### 协议与交互

1. **JSON-RPC 2.0**: 底层通信协议
2. **App-Server Protocol v2**: 应用层协议
3. **异步上下文管理器**: `async with` 模式确保资源正确释放

## 关键代码路径与文件引用

### 当前文件
- `sdk/python/examples/10_error_handling_and_retry/async.py`

### 依赖文件

| 文件路径 | 用途 |
|---------|------|
| `sdk/python/examples/_bootstrap.py` | 运行时环境初始化、工具函数 |
| `sdk/python/src/codex_app_server/__init__.py` | SDK 主入口，导出所有公共 API |
| `sdk/python/src/codex_app_server/retry.py` | 同步版本重试工具 |
| `sdk/python/src/codex_app_server/errors.py` | 错误类型定义与 `is_retryable_error` |
| `sdk/python/src/codex_app_server/api.py` | `AsyncCodex`, `AsyncThread`, `AsyncTurnHandle` |
| `sdk/python/src/codex_app_server/async_client.py` | `AsyncAppServerClient` 底层实现 |

### 核心调用链

```
async.py::retry_on_overload_async
  └── 调用用户提供的异步操作
        └── _run_turn()
              └── AsyncThread.turn()
                    └── api.py::AsyncThread.turn()
                          └── AsyncAppServerClient.turn_start()
                                └── async_client.py::turn_start()
                                      └── _call_sync() → asyncio.to_thread()
                                            └── client.py::AppServerClient.turn_start()
                                                  └── JSON-RPC request

错误判断：
errors.py::is_retryable_error()
  └── 检查 ServerBusyError 或 _is_server_overloaded()
```

## 依赖与外部交互

### Python 标准库
- `asyncio`: 异步 I/O 和事件循环
- `random`: 随机抖动生成
- `collections.abc`: `Awaitable`, `Callable` 抽象基类
- `typing`: `TypeVar` 泛型支持

### 第三方依赖
- `codex_app_server`: Codex Python SDK（本地源码版本）

### 外部进程
- `codex app-server`: 通过 stdio 启动的 Codex 应用服务器
  - 由 `AppServerConfig` 配置
  - 通过 `runtime_config()` 获取示例友好的配置

### 环境要求
- Python 3.9+（支持 `collections.abc.Awaitable`）
- 本地 SDK 源码路径需通过 `_bootstrap.py` 注入

## 风险、边界与改进建议

### 已知风险

1. **无限递归风险**
   - `max_attempts < 1` 时会抛出 `ValueError`，但检查在循环外
   - 建议：已在实现中防护，但调用方仍需注意

2. **异常捕获过于宽泛**
   - 使用 `except Exception` 捕获所有异常
   - 风险：可能隐藏编程错误（如 `TypeError`, `AttributeError`）
   - 建议：考虑缩小捕获范围，仅捕获预期的网络/服务器异常

3. **抖动计算可能为负**
   - `random.uniform(-jitter, jitter)` 可能产生负值
   - 当前有 `sleep_for > 0` 检查，但首次延迟可能异常短

4. **并发限制**
   - `AsyncAppServerClient` 使用 `_transport_lock` 保护 stdio 传输
   - 同一时间只能有一个 turn 消费者（见 `acquire_turn_consumer`）

### 边界条件

| 场景 | 行为 |
|------|------|
| `max_attempts = 1` | 不重试，直接失败 |
| `initial_delay_s = 0` | 首次重试无延迟，仅抖动 |
| `jitter_ratio = 0` | 无抖动，固定指数退避 |
| 非重试错误 | 立即抛出，不进行延迟 |
| `ServerBusyError` 持续 | 达到最大次数后抛出最后一次错误 |

### 改进建议

1. **类型安全增强**
   ```python
   # 建议定义更精确的异常类型
   from typing import TypeAlias
   RetryableError: TypeAlias = Union[ServerBusyError, ConnectionError]
   ```

2. **可观测性改进**
   ```python
   # 添加日志记录和指标
   import logging
   logger = logging.getLogger(__name__)
   
   # 在重试前记录
   logger.warning(f"Retry {attempt}/{max_attempts} after {sleep_for:.2f}s: {exc}")
   ```

3. **退避策略可配置**
   - 当前仅支持指数退避
   - 建议：支持线性退避、固定间隔等策略

4. **重试条件细化**
   ```python
   # 考虑添加可配置的重试谓词
   def retry_on_overload_async(
       op: Callable[[], Awaitable[ResultT]],
       *,
       should_retry: Callable[[Exception], bool] = is_retryable_error,
       ...
   ) -> ResultT:
   ```

5. **与同步版本代码复用**
   - 当前 `async.py` 和 `retry.py` 中的重试逻辑高度重复
   - 建议：提取通用逻辑到基类或工具函数

6. **取消支持**
   ```python
   # 支持 asyncio.CancelledError 传播
   except Exception as exc:
       if isinstance(exc, asyncio.CancelledError):
           raise  # 不拦截取消信号
   ```

### 测试建议

- 使用 `unittest.mock.AsyncMock` 模拟失败场景
- 测试各种边界条件（`max_attempts=1`, `initial_delay_s=0` 等）
- 验证抖动范围符合预期
- 测试取消操作正确传播
