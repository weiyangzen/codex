# SDK Python Examples - 10_error_handling_and_retry 研究文档

## 1. 场景与职责

### 1.1 定位与目标

本示例（`10_error_handling_and_retry`）是 Codex Python SDK 官方示例系列中的第 10 个示例，专注于展示如何在实际应用中处理错误和实现重试机制。该示例位于示例序列的较后位置，表明其建立在前述基础功能（线程管理、Turn 执行、流式事件等）之上，面向生产环境可靠性需求。

### 1.2 核心场景

- **服务端过载处理**：当 Codex app-server 因负载过高返回 `ServerBusyError` 时，客户端需要智能重试
- **网络瞬态故障恢复**：处理 JSON-RPC 通信层的临时错误
- **异步/同步双模式支持**：同时提供同步 (`sync.py`) 和异步 (`async.py`) 两种实现范式
- **错误分类与决策**：区分可重试错误（如服务器过载）与不可重试错误（如参数错误）

### 1.3 职责边界

| 组件 | 职责 |
|------|------|
| `sync.py` / `async.py` | 演示如何在应用层使用 SDK 提供的重试工具 |
| `codex_app_server.retry` | 提供通用重试装饰器/函数 |
| `codex_app_server.errors` | 定义错误层次结构、错误分类逻辑 |
| `codex_app_server.client` | 在 RPC 层识别和抛出特定错误类型 |

---

## 2. 功能点目的

### 2.1 错误处理体系

SDK 构建了层次化的错误处理体系：

```
AppServerError (基类)
├── TransportClosedError          # 传输层连接关闭
├── JsonRpcError                  # 通用 JSON-RPC 错误
│   ├── AppServerRpcError         # App-Server 特定 RPC 错误
│   │   ├── ParseError            # -32700: 解析错误
│   │   ├── InvalidRequestError   # -32600: 无效请求
│   │   ├── MethodNotFoundError   # -32601: 方法未找到
│   │   ├── InvalidParamsError    # -32602: 无效参数
│   │   ├── InternalRpcError      # -32603: 内部 RPC 错误
│   │   ├── ServerBusyError       # -32099~-32000: 服务器过载
│   │   └── RetryLimitExceededError # 重试次数耗尽
```

### 2.2 重试策略设计

示例实现了**指数退避 + 抖动**的重试策略：

- **指数退避**：延迟时间按 `delay = min(max_delay_s, delay * 2)` 增长
- **随机抖动**：在延迟基础上添加 `±jitter_ratio` 比例的随机偏移，避免惊群效应
- **可配置参数**：
  - `max_attempts`: 最大尝试次数（默认 3）
  - `initial_delay_s`: 初始延迟（默认 0.25s）
  - `max_delay_s`: 最大延迟上限（默认 2.0s）
  - `jitter_ratio`: 抖动比例（默认 0.2，即 ±20%）

### 2.3 可重试错误判定

通过 `is_retryable_error()` 函数实现智能判定：

1. **直接类型匹配**：`ServerBusyError` 及其子类直接判定为可重试
2. **错误数据深度检查**：检查 JSON-RPC 错误数据的 `data` 字段中是否包含 `server_overloaded` 标记
3. **多格式兼容**：支持字符串、字典、列表等多种数据格式的递归检查

---

## 3. 具体技术实现

### 3.1 关键流程

#### 3.1.1 同步重试流程 (`retry_on_overload`)

```python
def retry_on_overload(op, *, max_attempts=3, initial_delay_s=0.25, 
                      max_delay_s=2.0, jitter_ratio=0.2):
    delay = initial_delay_s
    attempt = 0
    while True:
        attempt += 1
        try:
            return op()  # 执行操作
        except Exception as exc:
            # 终止条件：达到最大尝试次数 或 错误不可重试
            if attempt >= max_attempts or not is_retryable_error(exc):
                raise
            
            # 计算带抖动的延迟
            jitter = delay * jitter_ratio
            sleep_for = min(max_delay_s, delay) + random.uniform(-jitter, jitter)
            if sleep_for > 0:
                time.sleep(sleep_for)
            
            # 指数退避
            delay = min(max_delay_s, delay * 2)
```

#### 3.1.2 异步重试流程 (`retry_on_overload_async`)

异步版本在示例中直接实现，逻辑与同步版一致，仅使用 `asyncio.sleep()` 替代 `time.sleep()`：

```python
async def retry_on_overload_async(op, *, max_attempts=3, ...):
    delay = initial_delay_s
    attempt = 0
    while True:
        attempt += 1
        try:
            return await op()  # 注意：await 异步操作
        except Exception as exc:
            if attempt >= max_attempts or not is_retryable_error(exc):
                raise
            jitter = delay * jitter_ratio
            sleep_for = min(max_delay_s, delay) + random.uniform(-jitter, jitter)
            if sleep_for > 0:
                await asyncio.sleep(sleep_for)  # 异步睡眠
            delay = min(max_delay_s, delay * 2)
```

#### 3.1.3 错误映射流程 (`map_jsonrpc_error`)

当 RPC 层收到错误响应时，通过错误码映射到特定异常类：

```python
def map_jsonrpc_error(code: int, message: str, data: Any = None) -> JsonRpcError:
    # 标准 JSON-RPC 错误码
    if code == -32700: return ParseError(code, message, data)
    if code == -32600: return InvalidRequestError(code, message, data)
    if code == -32601: return MethodNotFoundError(code, message, data)
    if code == -32602: return InvalidParamsError(code, message, data)
    if code == -32603: return InternalRpcError(code, message, data)
    
    # App-Server 特定错误码 (-32099 ~ -32000)
    if -32099 <= code <= -32000:
        if _is_server_overloaded(data):
            if _contains_retry_limit_text(message):
                return RetryLimitExceededError(code, message, data)
            return ServerBusyError(code, message, data)
        return AppServerRpcError(code, message, data)
    
    return JsonRpcError(code, message, data)
```

### 3.2 关键数据结构

#### 3.2.1 错误类定义

```python
# sdk/python/src/codex_app_server/errors.py

class JsonRpcError(AppServerError):
    def __init__(self, code: int, message: str, data: Any = None):
        super().__init__(f"JSON-RPC error {code}: {message}")
        self.code = code
        self.message = message
        self.data = data

class ServerBusyError(AppServerRpcError):
    """Server is overloaded / unavailable and caller should retry."""

class RetryLimitExceededError(ServerBusyError):
    """Server exhausted internal retry budget for a retryable operation."""
```

#### 3.2.2 Turn 状态枚举

```python
# sdk/python/src/codex_app_server/generated/v2_all.py

class TurnStatus(Enum):
    completed = "completed"
    interrupted = "interrupted"
    failed = "failed"
    in_progress = "inProgress"
```

### 3.3 协议与命令

#### 3.3.1 JSON-RPC 错误码规范

| 错误码范围 | 含义 | SDK 映射类 |
|-----------|------|-----------|
| -32700 | Parse error | `ParseError` |
| -32600 | Invalid Request | `InvalidRequestError` |
| -32601 | Method not found | `MethodNotFoundError` |
| -32602 | Invalid params | `InvalidParamsError` |
| -32603 | Internal error | `InternalRpcError` |
| -32099 ~ -32000 | Server error | `AppServerRpcError` 子类 |

#### 3.3.2 服务器过载检测协议

SDK 通过检查错误数据的特定字段识别服务器过载：

```python
def _is_server_overloaded(data: Any) -> bool:
    if isinstance(data, str):
        return data.lower() == "server_overloaded"
    
    if isinstance(data, dict):
        # 检查多种可能的字段名（snake_case / camelCase）
        direct = (
            data.get("codex_error_info")
            or data.get("codexErrorInfo")
            or data.get("errorInfo")
        )
        if isinstance(direct, str) and direct.lower() == "server_overloaded":
            return True
        # 递归检查嵌套值
        for value in data.values():
            if _is_server_overloaded(value):
                return True
    
    if isinstance(data, list):
        return any(_is_server_overloaded(value) for value in data)
    
    return False
```

---

## 4. 关键代码路径与文件引用

### 4.1 示例文件

| 文件 | 行数 | 核心功能 |
|------|------|---------|
| `sdk/python/examples/10_error_handling_and_retry/sync.py` | 47 | 同步重试示例，展示 `retry_on_overload` 的使用 |
| `sdk/python/examples/10_error_handling_and_retry/async.py` | 98 | 异步重试示例，展示自定义 `retry_on_overload_async` 实现 |

### 4.2 SDK 核心实现

| 文件 | 核心组件 | 功能描述 |
|------|---------|---------|
| `sdk/python/src/codex_app_server/retry.py` | `retry_on_overload()` | 同步重试辅助函数 |
| `sdk/python/src/codex_app_server/errors.py` | 错误类层次结构 | 定义所有异常类型及 `is_retryable_error()` |
| `sdk/python/src/codex_app_server/client.py` | `AppServerClient._request_raw()` | RPC 层错误抛出，调用 `map_jsonrpc_error()` |
| `sdk/python/src/codex_app_server/client.py` | `request_with_retry_on_overload()` | 客户端内置的带重试 RPC 方法 |
| `sdk/python/src/codex_app_server/async_client.py` | `AsyncAppServerClient` | 异步客户端，通过线程卸载调用同步实现 |

### 4.3 关键代码片段

#### 4.3.1 同步示例使用方式

```python
# sdk/python/examples/10_error_handling_and_retry/sync.py
from codex_app_server import (
    Codex,
    JsonRpcError,
    ServerBusyError,
    TextInput,
    TurnStatus,
    retry_on_overload,  # 直接导入 SDK 提供的重试函数
)

with Codex(config=runtime_config()) as codex:
    thread = codex.thread_start(model="gpt-5.4", config={"model_reasoning_effort": "high"})
    
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

#### 4.3.2 异步示例使用方式

```python
# sdk/python/examples/10_error_handling_and_retry/async.py
# 注意：异步版本在示例中自行实现 retry_on_overload_async
# SDK 目前仅提供同步版本的 retry_on_overload

async def main():
    async with AsyncCodex(config=runtime_config()) as codex:
        thread = await codex.thread_start(model="gpt-5.4", config={"model_reasoning_effort": "high"})
        
        try:
            result = await retry_on_overload_async(
                _run_turn(thread, "Summarize retry best practices in 3 bullets."),
                max_attempts=3,
                initial_delay_s=0.25,
                max_delay_s=2.0,
            )
        except ServerBusyError as exc:
            print("Server overloaded after retries:", exc.message)
```

#### 4.3.3 RPC 层错误处理

```python
# sdk/python/src/codex_app_server/client.py:260-268
if "error" in msg:
    err = msg["error"]
    if isinstance(err, dict):
        raise map_jsonrpc_error(
            int(err.get("code", -32000)),
            str(err.get("message", "unknown")),
            err.get("data"),
        )
    raise AppServerError("Malformed JSON-RPC error response")
```

#### 4.3.4 客户端内置重试方法

```python
# sdk/python/src/codex_app_server/client.py:395-410
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

### 4.4 测试覆盖

```python
# sdk/python/tests/test_public_api_runtime_behavior.py:568-575
def test_retry_examples_compare_status_with_enum():
    """验证示例代码使用 TurnStatus.failed 而非硬编码字符串"""
    for path in (
        ROOT / "examples" / "10_error_handling_and_retry" / "sync.py",
        ROOT / "examples" / "10_error_handling_and_retry" / "async.py",
    ):
        source = path.read_text()
        assert '== "failed"' not in source
        assert "TurnStatus.failed" in source
```

---

## 5. 依赖与外部交互

### 5.1 内部依赖

```
10_error_handling_and_retry/
├── sync.py
│   ├── _bootstrap.py          # 示例运行时环境配置
│   │   ├── runtime_config()   # 返回 AppServerConfig
│   │   ├── find_turn_by_id()  # Turn 查找辅助
│   │   └── assistant_text_from_turn()  # 文本提取辅助
│   └── codex_app_server       # SDK 主包
│       ├── Codex, AsyncCodex
│       ├── retry_on_overload
│       ├── JsonRpcError, ServerBusyError, TurnStatus
│       └── is_retryable_error
└── async.py
    └── （相同依赖结构）
```

### 5.2 外部依赖

| 依赖 | 用途 |
|------|------|
| `pydantic` | 数据模型验证（TurnStatus、错误响应等） |
| `codex-cli-bin` | 运行时二进制依赖，提供 app-server |

### 5.3 与 App-Server 的交互

```
┌─────────────────┐     JSON-RPC (stdio)     ┌─────────────────┐
│  Python SDK     │  ──────────────────────> │  Codex CLI      │
│  Client         │                          │  App-Server     │
│                 │  <────────────────────── │                 │
└─────────────────┘     Error Response       └─────────────────┘
        │
        │ 错误码 -32000 范围 + data.server_overloaded
        ▼
┌─────────────────┐
│ ServerBusyError │ ──> retry_on_overload() 捕获 ──> 指数退避重试
└─────────────────┘
```

---

## 6. 风险、边界与改进建议

### 6.1 当前风险与边界

#### 6.1.1 异步重试函数缺失

**问题**：SDK 仅提供同步版本的 `retry_on_overload()`，异步示例需要自行实现 `retry_on_overload_async()`。

**影响**：
- 增加用户代码复杂度
- 可能导致重复实现，引入不一致性

**代码证据**：
```python
# sdk/python/src/codex_app_server/__init__.py:56
from .retry import retry_on_overload  # 仅同步版本

# __all__ 中仅包含 retry_on_overload，无异步版本
```

#### 6.1.2 重试策略硬编码

当前重试参数在多处硬编码，缺乏全局配置机制：

```python
# client.py 中默认值
max_attempts: int = 3
initial_delay_s: float = 0.25
max_delay_s: float = 2.0

# 示例中重复指定相同值
```

#### 6.1.3 并发 Turn 消费限制

```python
# sdk/python/src/codex_app_server/client.py:291-295
if self._active_turn_consumer is not None:
    raise RuntimeError(
        "Concurrent turn consumers are not yet supported in the experimental SDK. "
        ...
    )
```

此限制影响重试场景下的并发性能。

#### 6.1.4 错误数据格式依赖

服务器过载检测依赖特定字段名（`codex_error_info` / `codexErrorInfo` / `errorInfo`），若服务端格式变更，检测可能失效。

### 6.2 改进建议

#### 6.2.1 提供官方异步重试函数

```python
# 建议添加到 sdk/python/src/codex_app_server/retry.py

import asyncio

async def aretry_on_overload(
    op: Callable[[], Awaitable[T]],
    *,
    max_attempts: int = 3,
    initial_delay_s: float = 0.25,
    max_delay_s: float = 2.0,
    jitter_ratio: float = 0.2,
) -> T:
    """Async version of retry_on_overload."""
    ...
```

#### 6.2.2 配置化重试策略

建议在 `AppServerConfig` 中添加默认重试配置：

```python
@dataclass(slots=True)
class AppServerConfig:
    # ... 现有字段 ...
    retry_max_attempts: int = 3
    retry_initial_delay_s: float = 0.25
    retry_max_delay_s: float = 2.0
    retry_jitter_ratio: float = 0.2
```

#### 6.2.3 增强错误上下文

当前 `ServerBusyError` 仅包含基础字段，建议添加：

```python
class ServerBusyError(AppServerRpcError):
    @property
    def retry_after_hint(self) -> float | None:
        """服务器建议的重试等待时间（如果提供）"""
        # 从 self.data 中提取
```

#### 6.2.4 可观测性增强

建议添加重试事件回调机制：

```python
def retry_on_overload(
    op: Callable[[], T],
    *,
    on_retry: Callable[[int, BaseException, float], None] | None = None,
    # on_retry(attempt_number, exception, next_delay)
    ...
) -> T:
```

#### 6.2.5 测试覆盖扩展

当前测试仅验证示例使用 `TurnStatus.failed` 枚举，建议添加：

- 模拟 `ServerBusyError` 的重试行为测试
- 指数退避延迟计算验证
- 抖动随机性分布测试
- 异步重试函数单元测试

### 6.3 使用建议

1. **优先使用 SDK 内置重试**：对于简单场景，直接使用 `retry_on_overload()`
2. **异步场景自定义实现**：参考示例中的 `retry_on_overload_async()` 模式
3. **错误处理层次化**：捕获顺序应为 `ServerBusyError` -> `JsonRpcError` -> `AppServerError`
4. **监控重试指标**：在生产环境中记录重试次数和成功率
5. **设置合理超时**：重试总时间 = 延迟总和，需确保在应用超时范围内

---

## 7. 附录

### 7.1 文件清单

```
sdk/python/examples/10_error_handling_and_retry/
├── async.py    # 异步重试示例
└── sync.py     # 同步重试示例

sdk/python/src/codex_app_server/
├── retry.py    # 同步重试实现
├── errors.py   # 错误类型定义
├── client.py   # RPC 客户端（含内置重试方法）
└── async_client.py  # 异步客户端包装
```

### 7.2 相关示例对比

| 示例 | 与 10_error_handling_and_retry 的关系 |
|------|--------------------------------------|
| `09_async_parity` | 基础异步模式，本示例在其基础上添加错误处理 |
| `11_cli_mini_app` | 展示 Turn 状态检查 (`turn.status`)，本示例展示错误捕获 |
| `02_turn_run` | 基础 Turn 执行，本示例在其基础上添加重试包装 |

### 7.3 版本信息

- SDK 版本：`0.2.0`（见 `sdk/python/src/codex_app_server/__init__.py:58`）
- 生成日期：基于代码库当前状态（2026-03-22）
