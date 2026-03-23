# sync.py 研究文档

## 场景与职责

`sync.py` 是 Codex Python SDK 的同步错误处理与重试机制示例代码。它演示了如何在同步（阻塞）环境下处理服务器过载（Server Overload）等瞬态错误，并使用 SDK 内置的 `retry_on_overload` 工具函数实现自动重试。

该文件与 `async.py` 形成对照组，展示了同步编程模式下相同功能的实现方式，帮助开发者理解两种编程模型的差异。

## 功能点目的

### 1. 同步重试包装器 (`retry_on_overload`)
- **目的**：SDK 内置的同步操作重试工具
- **策略**：指数退避 + 随机抖动（Jitter）
- **使用方式**：直接调用 SDK 提供的工具函数，无需自行实现

### 2. Lambda 表达式包装
- **目的**：将线程操作包装为可调用的无参函数
- **实现**：`lambda: thread.turn(...).run()`
- **注意**：Lambda 捕获变量时需小心延迟绑定问题

### 3. 错误处理与结果提取
- 捕获 `ServerBusyError` 和 `JsonRpcError`
- 从持久化的线程数据中查找对应 turn
- 提取助手消息文本并打印

## 具体技术实现

### 关键流程

```
with Codex(config=runtime_config()) as codex:  # 同步上下文管理
    ├── thread_start()                          # 创建线程
    ├── retry_on_overload()                     # 带重试执行
    │     └── lambda: thread.turn(...).run()    # 包装为无参函数
    ├── thread.read()                           # 读取线程数据
    ├── find_turn_by_id()                       # 查找对应 turn
    └── assistant_text_from_turn()              # 提取文本
```

### 同步重试使用模式

```python
from codex_app_server import retry_on_overload

result = retry_on_overload(
    lambda: thread.turn(TextInput("...")).run(),
    max_attempts=3,
    initial_delay_s=0.25,
    max_delay_s=2.0,
)
```

### 错误处理模式

```python
try:
    result = retry_on_overload(...)
except ServerBusyError as exc:
    # 重试耗尽后仍失败
    print("Server overloaded after retries:", exc.message)
except JsonRpcError as exc:
    # 其他 JSON-RPC 错误
    print(f"JSON-RPC error {exc.code}: {exc.message}")
else:
    # 成功处理结果
    ...
```

### 数据结构

| 类型 | 来源 | 用途 |
|------|------|------|
| `Codex` | `codex_app_server` | 同步 SDK 主入口 |
| `TextInput` | `codex_app_server` | 文本输入包装器 |
| `TurnStatus` | `codex_app_server` | Turn 状态检查 |
| `RunResult` | `codex_app_server` | Turn 执行结果 |

## 关键代码路径与文件引用

### 当前文件
- `sdk/python/examples/10_error_handling_and_retry/sync.py`

### 依赖文件

| 文件路径 | 用途 |
|---------|------|
| `sdk/python/examples/_bootstrap.py` | 运行时环境初始化 |
| `sdk/python/src/codex_app_server/__init__.py` | 导出 `retry_on_overload` |
| `sdk/python/src/codex_app_server/retry.py` | 同步重试实现 |
| `sdk/python/src/codex_app_server/errors.py` | 错误类型定义 |
| `sdk/python/src/codex_app_server/api.py` | `Codex`, `Thread`, `TurnHandle` |
| `sdk/python/src/codex_app_server/client.py` | `AppServerClient` 底层实现 |

### 核心调用链

```
sync.py
  └── retry_on_overload(lambda: ...)
        └── retry.py::retry_on_overload()
              ├── 执行 lambda
              │     └── Thread.turn().run()
              │           └── api.py::TurnHandle.run()
              │                 └── stream() 迭代通知
              │                       └── 等待 turn/completed
              └── 失败时指数退避重试

错误判断：
errors.py::is_retryable_error()
  └── 检查 ServerBusyError 或 _is_server_overloaded()
```

## 依赖与外部交互

### Python 标准库
- `sys`: 系统路径操作
- `pathlib`: 路径处理

### 第三方依赖
- `codex_app_server`: Codex Python SDK

### 导入的 SDK 组件

```python
from codex_app_server import (
    Codex,              # 同步客户端
    JsonRpcError,       # JSON-RPC 错误基类
    ServerBusyError,    # 服务器过载错误
    TextInput,          # 文本输入类型
    TurnStatus,         # Turn 状态枚举
    retry_on_overload,  # 重试工具函数
)
```

### 辅助函数（来自 _bootstrap.py）

| 函数 | 用途 |
|------|------|
| `assistant_text_from_turn()` | 从 turn 对象提取助手回复文本 |
| `ensure_local_sdk_src()` | 确保使用本地 SDK 源码 |
| `find_turn_by_id()` | 在线程 turns 列表中查找指定 ID |
| `runtime_config()` | 获取示例友好的配置 |

### 外部进程
- `codex app-server`: 通过 stdio 启动的 Codex 应用服务器

## 风险、边界与改进建议

### 已知风险

1. **Lambda 延迟绑定陷阱**
   ```python
   # 危险：如果在循环中使用，所有 lambda 会引用同一变量
   for prompt in prompts:
       futures.append(lambda: thread.turn(TextInput(prompt)).run())  # 错误！
   
   # 正确：使用默认参数捕获当前值
   futures.append(lambda p=prompt: thread.turn(TextInput(p)).run())
   ```
   当前示例未在循环中使用，但开发者复制代码时需注意。

2. **异常类型层次**
   - `ServerBusyError` 继承自 `AppServerRpcError` → `JsonRpcError`
   - 捕获顺序：应先捕获子类，再捕获父类
   - 当前实现顺序正确

3. **资源未关闭风险**
   - 使用 `with Codex(...) as codex` 确保关闭
   - 如果中途抛出未捕获异常，上下文管理器保证清理

4. **阻塞风险**
   - 同步实现会阻塞事件循环
   - 在异步应用中混用会导致性能问题

### 边界条件

| 场景 | 行为 |
|------|------|
| `max_attempts = 1` | 不重试，直接失败 |
| `initial_delay_s = 0` | 首次重试无延迟 |
| 操作立即成功 | 无延迟开销，直接返回 |
| 最后一次重试失败 | 抛出原始异常，不包装 |

### 与异步版本的差异

| 特性 | sync.py | async.py |
|------|---------|----------|
| 客户端 | `Codex` | `AsyncCodex` |
| 上下文管理器 | `with` | `async with` |
| 重试实现 | SDK 内置 `retry_on_overload` | 自定义 `retry_on_overload_async` |
| 延迟实现 | `time.sleep()` | `asyncio.sleep()` |
| 操作包装 | `lambda` | 嵌套 `async def` |
| 代码行数 | 47 行 | 98 行 |

### 改进建议

1. **使用 functools.partial 替代 lambda**
   ```python
   from functools import partial
   
   # 比 lambda 更清晰，支持关键字参数
   result = retry_on_overload(
       partial(thread.turn, TextInput("...")),
       ...
   )
   ```

2. **添加上下文信息**
   ```python
   try:
       result = retry_on_overload(...)
   except ServerBusyError as exc:
       # 添加上下文帮助诊断
       raise RuntimeError(f"Failed to get summary after {max_attempts} attempts") from exc
   ```

3. **类型注解增强**
   ```python
   from codex_app_server import RunResult
   
   result: RunResult = retry_on_overload(...)
   ```

4. **配置外部化**
   ```python
   import os
   
   max_attempts = int(os.getenv("CODEX_RETRY_ATTEMPTS", "3"))
   initial_delay_s = float(os.getenv("CODEX_RETRY_DELAY", "0.25"))
   ```

5. **结果验证**
   ```python
   if result.status == TurnStatus.failed:
       # 当前仅打印，建议抛出异常或返回错误码
       raise TurnFailedError(result.error)
   ```

### 测试建议

- 使用 `responses` 库或 `unittest.mock` 模拟服务器过载响应
- 验证重试次数和延迟间隔符合预期
- 测试各种错误码的映射行为
- 确保资源正确关闭（使用 `weakref` 或显式检查）

### 文档建议

- 添加 docstring 说明示例的前提条件（需要运行的 app-server）
- 说明模型名称 `"gpt-5.4"` 需要替换为实际可用的模型
- 解释 `model_reasoning_effort: "high"` 的含义和影响
