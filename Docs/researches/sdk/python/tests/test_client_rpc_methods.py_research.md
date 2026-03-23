# test_client_rpc_methods.py 研究文档

## 场景与职责

本测试文件验证 Python SDK 客户端的 RPC 方法调用、参数序列化和通知处理机制。它确保客户端与 app-server 之间的 JSON-RPC 通信协议正确实现，包括请求构造、响应解析和通知类型转换。

## 功能点目的

### 1. RPC 方法调用验证
- **目的**: 确保 `thread_set_name` 和 `thread_compact` 使用当前正确的 RPC 方法名
- **背景**: app-server 协议可能演进，方法名可能变更（如从 `thread/setName` 到 `thread/name/set`）
- **测试方法**: 模拟 `request` 方法，捕获调用参数并验证方法名

### 2. 参数模型序列化验证
- **目的**: 确保生成的参数模型使用 snake_case 字段名，但序列化为 camelCase
- **背景**: Python 使用 snake_case 命名规范，但 JSON-RPC 协议使用 camelCase
- **测试方法**: 验证 `ThreadListParams` 的字段命名和 `_params_dict()` 的序列化输出

### 3. 生成代码结构验证
- **目的**: 确保生成的类型定义中没有重复定义
- **测试方法**: 验证 `v2_all.py` 中 `PlanType` 类只定义一次

### 4. 通知类型转换验证
- **目的**: 确保服务器通知被正确解析为对应的 Pydantic 模型
- **测试方法**: 使用 `_coerce_notification()` 方法验证通知解析
- **覆盖场景**: 已知通知类型、未知通知类型、无效通知负载

## 具体技术实现

### RPC 方法名验证
```python
def test_thread_set_name_and_compact_use_current_rpc_methods() -> None:
    client = AppServerClient()
    calls: list[tuple[str, dict[str, Any] | None]] = []

    def fake_request(method: str, params, *, response_model):
        calls.append((method, params))
        return response_model.model_validate({})

    client.request = fake_request  # 替换 request 方法

    client.thread_set_name("thread-1", "sdk-name")
    client.thread_compact("thread-1")

    assert calls[0][0] == "thread/name/set"  # 验证方法名
    assert calls[1][0] == "thread/compact/start"
```

### 参数序列化验证
```python
def test_generated_params_models_are_snake_case_and_dump_by_alias() -> None:
    params = ThreadListParams(search_term="needle", limit=5)

    assert "search_term" in ThreadListParams.model_fields  # Python 字段名
    dumped = _params_dict(params)
    assert dumped == {"searchTerm": "needle", "limit": 5}  # 序列化后的 wire 格式
```

**关键机制**:
- Pydantic 模型定义使用 `snake_case` 字段名
- `model_dump(by_alias=True)` 将字段名转换为 camelCase
- `exclude_none=True` 排除未设置的可选字段

### 通知类型转换
```python
def test_notifications_are_typed_with_canonical_v2_methods() -> None:
    client = AppServerClient()
    event = client._coerce_notification(
        "thread/tokenUsage/updated",
        {
            "threadId": "thread-1",
            "turnId": "turn-1",
            "tokenUsage": {...},
        },
    )

    assert event.method == "thread/tokenUsage/updated"
    assert isinstance(event.payload, ThreadTokenUsageUpdatedNotification)
    assert event.payload.turn_id == "turn-1"  # 验证字段解析
```

**通知注册表机制**:
```python
# notification_registry.py
NOTIFICATION_MODELS: dict[str, type[BaseModel]] = {
    "thread/tokenUsage/updated": ThreadTokenUsageUpdatedNotification,
    # ... 其他通知类型
}
```

**类型转换流程**:
1. 根据方法名从 `NOTIFICATION_MODELS` 查找对应模型
2. 使用 `model_validate()` 解析通知数据
3. 解析失败时回退到 `UnknownNotification`

## 关键代码路径与文件引用

### 被测试的核心文件
| 文件路径 | 相关实现 |
|---------|---------|
| `sdk/python/src/codex_app_server/client.py` | `AppServerClient`, `_params_dict()` |
| `sdk/python/src/codex_app_server/generated/v2_all.py` | 生成的 Pydantic 模型 |
| `sdk/python/src/codex_app_server/generated/notification_registry.py` | 通知类型注册表 |
| `sdk/python/src/codex_app_server/models.py` | `UnknownNotification` |

### 关键函数实现

#### `_params_dict()` 参数序列化
```python
def _params_dict(params) -> JsonObject:
    if params is None:
        return {}
    if hasattr(params, "model_dump"):
        dumped = params.model_dump(
            by_alias=True,      # 使用 alias（camelCase）
            exclude_none=True,  # 排除 None 值
            mode="json",        # JSON 序列化模式
        )
        return dumped
    if isinstance(params, dict):
        return params
    raise TypeError(...)
```

#### `_coerce_notification()` 通知转换
```python
def _coerce_notification(self, method: str, params: object) -> Notification:
    params_dict = params if isinstance(params, dict) else {}
    
    model = NOTIFICATION_MODELS.get(method)
    if model is None:
        return Notification(method=method, payload=UnknownNotification(params=params_dict))
    
    try:
        payload = model.model_validate(params_dict)
    except Exception:
        return Notification(method=method, payload=UnknownNotification(params=params_dict))
    return Notification(method=method, payload=payload)
```

### 关键测试断言
| 测试函数 | 关键断言 | 验证目标 |
|---------|---------|---------|
| `test_thread_set_name_and_compact_use_current_rpc_methods` | `calls[0][0] == "thread/name/set"` | RPC 方法名正确 |
| `test_generated_params_models_are_snake_case_and_dump_by_alias` | `"search_term" in model_fields` | Python 命名规范 |
| | `dumped == {"searchTerm": ...}` | Wire 格式正确 |
| `test_generated_v2_bundle_has_single_shared_plan_type_definition` | `source.count("class PlanType(") == 1` | 无重复定义 |
| `test_notifications_are_typed_with_canonical_v2_methods` | `isinstance(payload, ThreadTokenUsageUpdatedNotification)` | 通知类型解析 |
| `test_unknown_notifications_fall_back_to_unknown_payloads` | `isinstance(payload, UnknownNotification)` | 未知通知回退 |
| `test_invalid_notification_payload_falls_back_to_unknown` | `isinstance(payload, UnknownNotification)` | 无效负载回退 |

## 依赖与外部交互

### 内部依赖
- `AppServerClient`: 同步客户端核心类
- `ThreadListParams`, `ThreadTokenUsageUpdatedNotification`: 生成的 Pydantic 模型
- `_params_dict()`: 参数序列化工具函数
- `UnknownNotification`: 未知通知回退类型

### 协议依赖
- app-server v2 JSON-RPC 协议
- 通知类型定义（`ServerNotification.json` schema）

## 风险、边界与改进建议

### 潜在风险
1. **协议变更**: app-server 协议演进时，硬编码的方法名可能过时
2. **字段名不一致**: 如果 schema 中的字段名与生成代码不一致，可能导致序列化错误
3. **通知类型遗漏**: 新添加的通知类型如果没有更新注册表，会被当作未知通知处理

### 边界情况
1. **空参数**: `_params_dict(None)` 返回空字典
2. **嵌套模型**: 复杂嵌套模型的序列化未在测试中覆盖
3. **额外字段**: 服务器返回未在模型中定义的字段时的行为

### 改进建议
1. **协议版本兼容性测试**: 添加测试验证客户端与不同版本 app-server 的兼容性
   ```python
   def test_client_backward_compatibility():
       # 验证客户端可以处理旧版本服务器的响应
   ```

2. **动态方法名验证**: 从 schema 文件读取期望的方法名，而非硬编码
   ```python
   def test_rpc_methods_match_schema():
       schema = load_schema()
       expected_methods = extract_methods_from_schema(schema)
       assert actual_methods == expected_methods
   ```

3. **通知类型完整性检查**: 验证注册表包含 schema 中定义的所有通知类型
   ```python
   def test_all_notification_types_registered():
       schema_notifications = load_server_notification_schema()
       registered = set(NOTIFICATION_MODELS.keys())
       assert registered == set(schema_notifications)
   ```

4. **增加边界测试**:
   ```python
   def test_params_dict_with_nested_model():
       # 测试嵌套模型的序列化
       
   def test_coerce_notification_with_extra_fields():
       # 测试服务器返回额外字段时的行为
       
   def test_coerce_notification_with_missing_required_fields():
       # 测试缺少必填字段时的回退行为
   ```

5. **性能测试**: 验证大量通知处理的性能
   ```python
   def test_notification_processing_performance():
       # 验证可以高效处理大量通知
   ```
