# sdk/python/src/codex_app_server/errors.py 研究文档

## 场景与职责

`errors.py` 是 Codex Python SDK 的**异常定义与处理模块**，负责定义 SDK 中使用的所有异常类型，并提供 JSON-RPC 错误到 Python 异常的映射机制。它承担着：

1. **异常层次结构设计**：建立清晰的异常继承体系
2. **JSON-RPC 错误映射**：将服务器返回的 JSON-RPC 错误码转换为具体的 Python 异常
3. **重试决策支持**：提供判断错误是否可重试的工具函数
4. **错误信息提取**：从错误响应中提取有用的诊断信息

## 功能点目的

### 1. 异常层次结构

```
AppServerError (基类)
├── JsonRpcError
│   ├── AppServerRpcError
│   │   ├── ParseError (-32700)
│   │   ├── InvalidRequestError (-32600)
│   │   ├── MethodNotFoundError (-32601)
│   │   ├── InvalidParamsError (-32602)
│   │   ├── InternalRpcError (-32603)
│   │   ├── ServerBusyError (-32099 ~ -32000)
│   │   └── RetryLimitExceededError (继承自 ServerBusyError)
│   └── TransportClosedError
└── ... (未来可扩展其他基类)
```

### 2. 异常类定义

| 异常类 | JSON-RPC 码 | 用途 |
|-------|------------|------|
| `AppServerError` | - | 所有 SDK 异常的基类 |
| `JsonRpcError` | - | JSON-RPC 错误的包装器 |
| `ParseError` | -32700 | 解析错误（无效的 JSON） |
| `InvalidRequestError` | -32600 | 无效请求对象 |
| `MethodNotFoundError` | -32601 | 方法不存在 |
| `InvalidParamsError` | -32602 | 无效参数 |
| `InternalRpcError` | -32603 | 内部 JSON-RPC 错误 |
| `ServerBusyError` | -32099 ~ -32000 | 服务器过载/不可用 |
| `RetryLimitExceededError` | - | 重试次数耗尽 |
| `TransportClosedError` | - | 传输层连接关闭 |

### 3. 错误映射函数

**`map_jsonrpc_error(code, message, data)`**：
根据 JSON-RPC 错误码映射到具体异常类：

```python
def map_jsonrpc_error(code: int, message: str, data: Any = None) -> JsonRpcError:
    if code == -32700: return ParseError(code, message, data)
    if code == -32600: return InvalidRequestError(code, message, data)
    if code == -32601: return MethodNotFoundError(code, message, data)
    if code == -32602: return InvalidParamsError(code, message, data)
    if code == -32603: return InternalRpcError(code, message, data)
    
    if -32099 <= code <= -32000:  # 服务器错误范围
        if _is_server_overloaded(data):
            if _contains_retry_limit_text(message):
                return RetryLimitExceededError(code, message, data)
            return ServerBusyError(code, message, data)
        ...
    
    return JsonRpcError(code, message, data)  # 默认
```

### 4. 重试判断函数

**`is_retryable_error(exc)`**：
判断异常是否为可重试的瞬态错误：

```python
def is_retryable_error(exc: BaseException) -> bool:
    if isinstance(exc, ServerBusyError):
        return True
    if isinstance(exc, JsonRpcError):
        return _is_server_overloaded(exc.data)
    return False
```

## 具体技术实现

### JsonRpcError 基类

```python
class JsonRpcError(AppServerError):
    """Raw JSON-RPC error wrapper from the server."""
    
    def __init__(self, code: int, message: str, data: Any = None):
        super().__init__(f"JSON-RPC error {code}: {message}")
        self.code = code
        self.message = message
        self.data = data
```

**设计特点：**
- 保存原始错误码、消息和附加数据
- 提供友好的字符串表示
- 支持通过 `data` 字段访问服务器返回的详细信息

### 服务器过载检测

```python
def _is_server_overloaded(data: Any) -> bool:
    if data is None:
        return False
    
    if isinstance(data, str):
        return data.lower() == "server_overloaded"
    
    if isinstance(data, dict):
        # 检查多种可能的键名
        direct = (
            data.get("codex_error_info")
            or data.get("codexErrorInfo")
            or data.get("errorInfo")
        )
        if isinstance(direct, str) and direct.lower() == "server_overloaded":
            return True
        # 递归检查嵌套结构
        for value in data.values():
            if _is_server_overloaded(value):
                return True
    
    if isinstance(data, list):
        return any(_is_server_overloaded(value) for value in data)
    
    return False
```

**设计考量：**
- 支持多种键名（snake_case, camelCase）以适应不同版本的服务器
- 递归检查嵌套结构，确保不遗漏错误信息
- 大小写不敏感比较，提高兼容性

### 重试限制检测

```python
def _contains_retry_limit_text(message: str) -> bool:
    lowered = message.lower()
    return "retry limit" in lowered or "too many failed attempts" in lowered
```

## 关键代码路径与文件引用

### 模块依赖图

```
errors.py
└── typing.Any  # 仅标准库依赖

被依赖方：
├── client.py          # map_jsonrpc_error, 异常类
├── retry.py           # is_retryable_error
├── __init__.py        # 导出公共 API
└── api.py             # 通过 client 间接使用
```

### 错误映射调用链

```
服务器返回错误响应
    │
    └── client.py:_request_raw()
        │
        └── 检测到 "error" 字段
            │
            └── map_jsonrpc_error(code, message, data)
                │
                ├── 标准错误码 (-32700 ~ -32603)
                │   └── 返回对应的具体异常
                │
                ├── 服务器错误范围 (-32099 ~ -32000)
                │   ├── _is_server_overloaded(data)
                │   │   └── 检查多种键名和嵌套结构
                │   │
                │   ├── _contains_retry_limit_text(message)
                │   │   └── 检查消息文本
                │   │
                │   └── 返回 ServerBusyError 或 RetryLimitExceededError
                │
                └── 其他错误码
                    └── 返回通用 JsonRpcError
```

### 重试决策调用链

```
retry.py:retry_on_overload()
    │
    ├── 捕获异常
    │
    └── is_retryable_error(exc)
        │
        ├── isinstance(exc, ServerBusyError)
        │   └── True → 可重试
        │
        └── isinstance(exc, JsonRpcError)
            └── _is_server_overloaded(exc.data)
                └── True → 可重试
```

## 依赖与外部交互

### 直接依赖

| 模块 | 导入符号 | 用途 |
|-----|---------|------|
| `typing` | `Any` | 类型注解 |

### 被依赖方

| 模块 | 使用方式 |
|-----|---------|
| `client.py` | 导入所有异常类和 `map_jsonrpc_error` |
| `retry.py` | 导入 `is_retryable_error` |
| `__init__.py` | 导出所有公共异常类 |

## 风险、边界与改进建议

### 当前风险

1. **错误码硬编码**：JSON-RPC 错误码是硬编码的，如果标准变更需要修改代码
2. **服务器过载检测的脆弱性**：依赖字符串匹配和特定键名，可能因服务器响应格式变化而失效
3. **缺乏错误上下文**：异常不包含请求信息（如请求 ID、方法名），调试困难
4. **异常粒度**：`-32099 ~ -32000` 范围内的所有错误都映射为 `ServerBusyError`，粒度较粗

### 边界情况

1. **None 数据处理**：`_is_server_overloaded(None)` 返回 `False`，不会误判
2. **循环引用**：递归检查嵌套字典时，如果存在循环引用会导致无限递归（虽然实际场景中不太可能出现）
3. **大小写敏感**：消息文本检查使用小写转换，确保不区分大小写
4. **空消息**：`_contains_retry_limit_text("")` 安全返回 `False`

### 改进建议

1. **添加请求上下文**：
   ```python
   class JsonRpcError(AppServerError):
       def __init__(self, code, message, data, *, request_id=None, method=None):
           super().__init__(f"JSON-RPC error {code} in {method}: {message}")
           self.request_id = request_id
           self.method = method
   ```

2. **使用枚举定义错误码**：
   ```python
   from enum import IntEnum
   
   class JsonRpcErrorCode(IntEnum):
       PARSE_ERROR = -32700
       INVALID_REQUEST = -32600
       METHOD_NOT_FOUND = -32601
       INVALID_PARAMS = -32602
       INTERNAL_ERROR = -32603
       SERVER_ERROR_START = -32099
       SERVER_ERROR_END = -32000
   ```

3. **防止循环引用**：
   ```python
   def _is_server_overloaded(data: Any, _seen: set[int] | None = None) -> bool:
       if _seen is None:
           _seen = set()
       if id(data) in _seen:
           return False
       _seen.add(id(data))
       # ... 递归调用时传递 _seen
   ```

4. **更细粒度的服务器错误**：
   ```python
   class RateLimitError(ServerBusyError):
       """Rate limit exceeded."""
   
   class QuotaExceededError(ServerBusyError):
       """Quota exceeded."""
   ```

5. **错误分类工具**：
   ```python
   class ErrorCategory(Enum):
       CLIENT = "client"           # 客户端错误
       SERVER = "server"           # 服务器错误
       NETWORK = "network"         # 网络错误
       TRANSIENT = "transient"     # 瞬态错误（可重试）
       PERMANENT = "permanent"     # 永久错误（不可重试）
   
   def categorize_error(exc: BaseException) -> ErrorCategory:
       ...
   ```

6. **结构化错误信息**：
   ```python
   @dataclass
   class ErrorInfo:
       code: int
       message: str
       data: Any
       retry_after: float | None  # 建议重试等待时间
       request_id: str | None
   ```

### 测试覆盖

相关测试场景（应在 `test_client_rpc_methods.py` 或专门测试文件中）：
- 标准 JSON-RPC 错误码映射
- 服务器过载检测（多种数据格式）
- 重试限制文本检测
- 嵌套错误数据结构处理
- 可重试错误判断

示例测试：
```python
def test_server_overloaded_detection():
    assert _is_server_overloaded("server_overloaded") is True
    assert _is_server_overloaded({"codex_error_info": "server_overloaded"}) is True
    assert _is_server_overloaded({"codexErrorInfo": {"status": "server_overloaded"}}) is True
    assert _is_server_overloaded(None) is False

def test_retryable_error():
    assert is_retryable_error(ServerBusyError(-32000, "busy")) is True
    assert is_retryable_error(InvalidParamsError(-32602, "bad params")) is False
```
