# sdk/python/src/codex_app_server/models.py 研究文档

## 场景与职责

`models.py` 是 Codex Python SDK 的**核心数据模型定义模块**，负责定义 SDK 内部使用的核心数据结构和类型别名。与 `generated/v2_all.py` 中自动生成的模型不同，这里的模型是手工维护的，用于：

1. **核心类型定义**：定义 JSON 数据的基础类型别名
2. **通知系统模型**：定义通知相关的数据结构
3. **初始化响应模型**：定义服务器初始化响应的数据结构
4. **类型安全**：为动态 JSON 数据提供静态类型支持

## 功能点目的

### 1. JSON 类型别名

```python
JsonScalar: TypeAlias = str | int | float | bool | None
JsonValue: TypeAlias = JsonScalar | dict[str, "JsonValue"] | list["JsonValue"]
JsonObject: TypeAlias = dict[str, JsonValue]
```

**用途：**
- `JsonScalar`：JSON 原子类型
- `JsonValue`：任意 JSON 值（递归定义）
- `JsonObject`：JSON 对象（字典）

这些类型广泛用于：
- RPC 请求/响应参数
- 配置数据
- 动态数据结构

### 2. 通知系统模型

**UnknownNotification**：
```python
@dataclass(slots=True)
class UnknownNotification:
    params: JsonObject
```

用于表示无法识别或解析的通知类型。

**NotificationPayload 联合类型**：
```python
NotificationPayload = (
    AccountLoginCompletedNotification
    | AccountRateLimitsUpdatedNotification
    | ...  # 约 30 种具体通知类型
    | UnknownNotification  # 兜底类型
)
```

**Notification 主类**：
```python
@dataclass(slots=True)
class Notification:
    method: str
    payload: NotificationPayload
```

### 3. 初始化响应模型

**ServerInfo**：
```python
class ServerInfo(BaseModel):
    name: str | None = None
    version: str | None = None
```

**InitializeResponse**：
```python
class InitializeResponse(BaseModel):
    serverInfo: ServerInfo | None = None
    userAgent: str | None = None
    platformFamily: str | None = None
    platformOs: str | None = None
```

用于处理 `initialize` RPC 的响应。

## 具体技术实现

### 类型别名设计

使用 `TypeAlias`（Python 3.10+）提供递归类型支持：

```python
JsonValue: TypeAlias = JsonScalar | dict[str, "JsonValue"] | list["JsonValue"]
```

注意 `"JsonValue"` 使用字符串前向引用，解决递归定义问题。

### 通知类型组织

从 `generated.v2_all` 导入所有具体的通知类型：

```python
from .generated.v2_all import (
    AccountLoginCompletedNotification,
    AccountRateLimitsUpdatedNotification,
    # ... 约 30 种通知类型
    TurnStartedNotification,
    WindowsWorldWritableWarningNotification,
)
```

然后构建联合类型 `NotificationPayload`。

### 数据类 vs Pydantic 模型

| 类型 | 实现方式 | 用途 |
|-----|---------|------|
| `UnknownNotification` | `@dataclass(slots=True)` | 轻量级数据结构 |
| `Notification` | `@dataclass(slots=True)` | 轻量级数据结构 |
| `ServerInfo` | `pydantic.BaseModel` | 需要验证和序列化 |
| `InitializeResponse` | `pydantic.BaseModel` | 需要验证和序列化 |

**设计考量：**
- `dataclass` 用于内部数据结构，性能更好
- `pydantic.BaseModel` 用于需要验证和与 JSON 交互的数据

## 关键代码路径与文件引用

### 模块依赖图

```
models.py
├── __future__.annotations    # 延迟类型注解求值
├── dataclasses.dataclass     # 数据类装饰器
├── typing.TypeAlias          # 类型别名
├── pydantic.BaseModel        # Pydantic 基类
└── generated.v2_all          # 导入所有通知类型
    ├── AccountLoginCompletedNotification
    ├── AgentMessageDeltaNotification
    ├── TurnCompletedNotification
    └── ... (约 30 种)

被依赖方：
├── client.py          # InitializeResponse, Notification, JsonObject
├── async_client.py    # InitializeResponse, Notification
├── api.py             # InitializeResponse, Notification
├── _run.py            # Notification
├── _inputs.py         # JsonObject
├── errors.py          # 间接通过 client
└── __init__.py        # 导出 InitializeResponse
```

### 使用场景

**client.py 中的使用：**
```python
from .models import InitializeResponse, JsonObject, JsonValue, Notification, UnknownNotification

class AppServerClient:
    def initialize(self) -> InitializeResponse:
        result = self.request(..., response_model=InitializeResponse)
        return result
    
    def _coerce_notification(self, method: str, params: object) -> Notification:
        # 使用 UnknownNotification 作为兜底
        ...
```

**_run.py 中的使用：**
```python
from .models import Notification

def _collect_run_result(stream: Iterator[Notification], *, turn_id: str) -> RunResult:
    for event in stream:  # Notification 类型
        payload = event.payload
        ...
```

## 依赖与外部交互

### 直接依赖

| 模块 | 导入符号 | 用途 |
|-----|---------|------|
| `__future__` | `annotations` | 延迟类型注解求值 |
| `dataclasses` | `dataclass` | 数据类装饰器 |
| `typing` | `TypeAlias` | 类型别名定义 |
| `pydantic` | `BaseModel` | 数据验证模型 |
| `.generated.v2_all` | 所有通知类型 | 构建 NotificationPayload |

### 被依赖方

| 模块 | 使用方式 |
|-----|---------|
| `client.py` | 导入 `InitializeResponse`, `JsonObject`, `JsonValue`, `Notification`, `UnknownNotification` |
| `async_client.py` | 导入 `InitializeResponse`, `Notification` |
| `api.py` | 导入 `InitializeResponse`, `JsonObject`, `Notification` |
| `_run.py` | 导入 `Notification` |
| `_inputs.py` | 导入 `JsonObject` |
| `__init__.py` | 导出 `InitializeResponse` |

## 风险、边界与改进建议

### 当前风险

1. **通知类型同步**：`NotificationPayload` 需要与 `generated/v2_all.py` 中的通知类型保持同步，新增通知类型时需要手动更新
2. **类型递归深度**：`JsonValue` 的递归定义在极端嵌套的 JSON 情况下可能导致类型检查器性能问题
3. **混合使用 dataclass 和 Pydantic**：两种模型混用可能导致序列化行为不一致

### 边界情况

1. **UnknownNotification 兜底**：当通知无法解析时，使用 `UnknownNotification` 包装原始参数，避免丢失数据
2. **可选字段**：`InitializeResponse` 和 `ServerInfo` 的所有字段都是可选的（`| None`），处理不完整的服务器响应
3. **空通知负载**：`Notification.payload` 总是有一个值，不会为 `None`

### 改进建议

1. **自动生成 NotificationPayload**：
   使用代码生成工具从 `generated/v2_all.py` 自动生成 `NotificationPayload` 联合类型：
   ```python
   # 在生成脚本中添加
   notification_types = [name for name in dir(v2_all) if name.endswith('Notification')]
   print(f"NotificationPayload = {' | '.join(notification_types)} | UnknownNotification")
   ```

2. **统一模型基类**：
   考虑统一使用 Pydantic 模型，或提供 dataclass 到 Pydantic 的转换工具：
   ```python
   def notification_to_dict(n: Notification) -> dict:
       if isinstance(n.payload, BaseModel):
           payload = n.payload.model_dump()
       elif isinstance(n.payload, dataclass):
           payload = asdict(n.payload)
       else:
           payload = n.payload
       return {"method": n.method, "payload": payload}
   ```

3. **更精确的 JSON 类型**：
   使用 `TypedDict` 为常见的 JSON 结构提供更精确的类型：
   ```python
   class RpcRequest(TypedDict):
       id: str
       method: str
       params: JsonObject
   
   class RpcResponse(TypedDict):
       id: str
       result: NotRequired[JsonValue]
       error: NotRequired[JsonObject]
   ```

4. **添加验证方法**：
   ```python
   @dataclass(slots=True)
   class Notification:
       method: str
       payload: NotificationPayload
       
       def is_completion(self) -> bool:
           return self.method == "turn/completed"
       
       def is_delta(self) -> bool:
           return self.method == "item/agentMessage/delta"
   ```

5. **性能优化**：
   对于高频创建的对象，考虑使用 `__slots__` 和 `frozen=True`：
   ```python
   @dataclass(slots=True, frozen=True)
   class Notification:
       ...
   ```

6. **文档字符串**：
   为所有类型添加文档字符串，说明用途和示例：
   ```python
   JsonObject: TypeAlias = dict[str, JsonValue]
   """JSON 对象类型，表示任意 JSON 对象。
   
   Example:
       {"key": "value", "nested": {"a": 1}}
   """
   ```

### 测试覆盖

相关测试场景：
- 通知类型的强制转换（`client.py:_coerce_notification` 的测试）
- `InitializeResponse` 的解析和验证
- `UnknownNotification` 作为兜底的处理

测试文件：
- `test_client_rpc_methods.py::test_notifications_are_typed_with_canonical_v2_methods`
- `test_client_rpc_methods.py::test_unknown_notifications_fall_back_to_unknown_payloads`
- `test_public_api_signatures.py::test_initialize_metadata_parses_user_agent_shape`
