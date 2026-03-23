# test_public_api_signatures.py 研究文档

## 场景与职责

本测试文件验证 Python SDK 公共 API 的签名（函数参数和返回类型）符合设计规范。它确保 API 的命名约定、类型注解和参数结构保持一致，是 API 稳定性和开发者体验的重要保障。

## 功能点目的

### 1. 根模块导出验证
- **目的**: 确保关键类型可以从根模块直接导入
- **测试内容**: 验证 `AppServerConfig` 和 `RunResult` 可从 `codex_app_server` 导入

### 2. 类型标记验证
- **目的**: 确保包包含 PEP 561 要求的 `py.typed` 标记文件
- **背景**: `py.typed` 文件告诉类型检查器（如 mypy）该包支持类型提示

### 3. 公共 API 签名规范验证
- **目的**: 确保生成的公共 API 方法遵循命名和类型规范
- **测试内容**:
  - 参数使用 snake_case 命名
  - 参数为 keyword-only（`*` 后定义）
  - 不使用 `Any` 类型注解

### 4. 生命周期方法作用域验证
- **目的**: 确保线程生命周期方法（resume, fork, archive, unarchive）位于正确的类上
- **测试内容**:
  - `Codex` / `AsyncCodex` 类有生命周期方法
  - `Thread` / `AsyncThread` 类没有生命周期方法

### 5. 初始化元数据解析验证
- **目的**: 验证 `InitializeResponse` 的解析和验证逻辑
- **测试内容**:
  - 正确解析 `userAgent` 字符串
  - 处理缺失元数据的情况

## 具体技术实现

### 根模块导出测试
```python
def test_root_exports_app_server_config() -> None:
    assert AppServerConfig.__name__ == "AppServerConfig"

def test_root_exports_run_result() -> None:
    assert RunResult.__name__ == "RunResult"
```

**导入路径**:
```python
from codex_app_server import AppServerConfig, RunResult
```

### py.typed 标记验证
```python
def test_package_includes_py_typed_marker() -> None:
    marker = resources.files("codex_app_server").joinpath("py.typed")
    assert marker.is_file()
```

**PEP 561 要求**:
- 包必须包含 `py.typed` 文件（可为空）
- 文件必须包含在分发包中

### 签名规范验证
```python
def _keyword_only_names(fn: object) -> list[str]:
    signature = inspect.signature(fn)
    return [
        param.name
        for param in signature.parameters.values()
        if param.kind == inspect.Parameter.KEYWORD_ONLY
    ]

def _assert_no_any_annotations(fn: object) -> None:
    signature = inspect.signature(fn)
    for param in signature.parameters.values():
        if param.annotation is Any:
            raise AssertionError(f"{fn} has public parameter typed as Any: {param.name}")
    if signature.return_annotation is Any:
        raise AssertionError(f"{fn} has public return annotation typed as Any")
```

**验证规则**:
1. 所有参数必须是 keyword-only（`param.kind == KEYWORD_ONLY`）
2. 参数名必须全小写（`name == name.lower()`）
3. 不允许使用 `Any` 类型注解

### 期望的 API 签名
```python
expected = {
    Codex.thread_start: [
        "approval_policy",
        "approvals_reviewer",
        "base_instructions",
        "config",
        "cwd",
        "developer_instructions",
        "ephemeral",
        "model",
        "model_provider",
        "personality",
        "sandbox",
        "service_name",
        "service_tier",
    ],
    Codex.thread_list: [...],
    Codex.thread_resume: [...],
    Codex.thread_fork: [...],
    Thread.turn: [...],
    Thread.run: [...],
    AsyncCodex.thread_start: [...],
    # ... 异步变体
}
```

### 生命周期方法作用域验证
```python
def test_lifecycle_methods_are_codex_scoped() -> None:
    # Codex 类应该有这些方法
    assert hasattr(Codex, "thread_resume")
    assert hasattr(Codex, "thread_fork")
    assert hasattr(Codex, "thread_archive")
    assert hasattr(Codex, "thread_unarchive")
    
    # Codex 类不应该有 thread 方法（返回 Thread 实例的方法除外）
    assert not hasattr(Codex, "thread")
    
    # Thread 类不应该有生命周期方法
    assert not hasattr(Thread, "resume")
    assert not hasattr(Thread, "fork")
    assert not hasattr(Thread, "archive")
    assert not hasattr(Thread, "unarchive")
```

**设计原则**:
- 生命周期操作（创建、恢复、归档）在 `Codex` 级别
- 线程实例只包含操作该线程的方法（如 `turn`, `run`, `read`）

### 初始化元数据解析
```python
def test_initialize_metadata_parses_user_agent_shape() -> None:
    payload = InitializeResponse.model_validate({"userAgent": "codex-cli/1.2.3"})
    parsed = Codex._validate_initialize(payload)
    assert parsed.userAgent == "codex-cli/1.2.3"
    assert parsed.serverInfo.name == "codex-cli"
    assert parsed.serverInfo.version == "1.2.3"
```

**解析逻辑**:
```python
@staticmethod
def _split_user_agent(user_agent: str) -> tuple[str | None, str | None]:
    raw = user_agent.strip()
    if "/" in raw:
        name, version = raw.split("/", 1)
        return (name or None), (version or None)
    parts = raw.split(maxsplit=1)
    if len(parts) == 2:
        return parts[0], parts[1]
    return raw, None
```

## 关键代码路径与文件引用

### 被测试的核心文件
| 文件路径 | 相关实现 |
|---------|---------|
| `sdk/python/src/codex_app_server/__init__.py` | 根模块导出 |
| `sdk/python/src/codex_app_server/api.py` | `Codex`, `AsyncCodex`, `Thread`, `AsyncThread` |
| `sdk/python/src/codex_app_server/models.py` | `InitializeResponse` |

### 关键测试断言
| 测试函数 | 关键断言 | 验证目标 |
|---------|---------|---------|
| `test_root_exports_app_server_config` | `AppServerConfig.__name__ == "AppServerConfig"` | 根模块导出 |
| `test_package_includes_py_typed_marker` | `marker.is_file()` | PEP 561 合规 |
| `test_generated_public_signatures_are_snake_case_and_typed` | `actual == expected_kwargs` | 参数签名一致 |
| | `all(name == name.lower() for name in actual)` | snake_case 命名 |
| `test_lifecycle_methods_are_codex_scoped` | `hasattr(Codex, "thread_resume")` | 生命周期方法位置 |
| | `not hasattr(Thread, "resume")` | Thread 无生命周期方法 |
| `test_initialize_metadata_parses_user_agent_shape` | `serverInfo.name == "codex-cli"` | User-Agent 解析 |
| `test_initialize_metadata_requires_non_empty_information` | `RuntimeError` | 元数据验证 |

## 依赖与外部交互

### 标准库
- `importlib.resources`: 访问包内资源
- `inspect`: 反射获取函数签名
- `typing.Any`: 类型检查

### 内部依赖
- `codex_app_server`: 根模块
- `codex_app_server.api`: 公共 API 实现
- `codex_app_server.models`: 数据模型

## 风险、边界与改进建议

### 潜在风险
1. **硬编码参数列表**: 当 API 变更时，需要同步更新测试中的期望参数列表
2. **类型检查器差异**: 不同类型检查器对 `Any` 的处理可能不同
3. **反射开销**: 大量使用 `inspect` 可能影响测试性能

### 边界情况
1. **私有方法**: 测试只验证公共 API，私有方法的行为未覆盖
2. **重载方法**: 如果 API 使用 `@overload`，签名验证可能不完整
3. **泛型类型**: 复杂泛型类型的验证未覆盖

### 改进建议
1. **动态参数列表生成**: 从 schema 或源码自动生成期望参数列表
   ```python
   def load_expected_params_from_schema():
       schema = load_thread_start_schema()
       return [to_snake_case(p) for p in schema.properties.keys()]
   ```

2. **增加返回类型验证**:
   ```python
   def test_public_api_return_types():
       assert get_return_annotation(Codex.thread_start) == Thread
       assert get_return_annotation(Thread.run) == RunResult
   ```

3. **增加文档字符串验证**:
   ```python
   def test_public_api_has_docstrings():
       for fn in public_api_functions:
           assert fn.__doc__, f"{fn} missing docstring"
   ```

4. **使用 mypy 程序化 API**:
   ```python
   def test_api_passes_mypy():
       # 使用 mypy.api.run 验证类型正确性
       result = mypy_api.run(['-p', 'codex_app_server'])
       assert result[2] == 0  # 无类型错误
   ```

5. **参数化测试减少重复**:
   ```python
   @pytest.mark.parametrize("method,expected", [
       (Codex.thread_start, [...]),
       (AsyncCodex.thread_start, [...]),
   ])
   def test_method_signature(method, expected):
       assert _keyword_only_names(method) == expected
   ```
