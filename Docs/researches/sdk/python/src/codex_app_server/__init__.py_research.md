# sdk/python/src/codex_app_server/__init__.py 研究文档

## 场景与职责

`__init__.py` 是 Codex Python SDK 的公共 API 入口点，负责统一暴露 SDK 的所有公共接口。作为包的根模块，它承担着以下核心职责：

1. **统一命名空间管理**：将分散在各个子模块中的类、函数、常量聚合到 `codex_app_server` 包级别
2. **版本声明**：定义 SDK 版本号 `__version__ = "0.2.0"`
3. **公共 API 契约**：通过 `__all__` 列表明确声明哪些符号属于公共 API
4. **向后兼容性保障**：为下游用户提供稳定的导入接口

## 功能点目的

### 1. 客户端类导出

| 导出符号 | 来源模块 | 用途 |
|---------|---------|------|
| `AsyncAppServerClient` | `.async_client` | 异步底层 JSON-RPC 客户端 |
| `AppServerClient` | `.client` | 同步底层 JSON-RPC 客户端 |
| `AppServerConfig` | `.client` | 客户端配置类 |
| `Codex` / `AsyncCodex` | `.api` | 高级同步/异步 API 入口 |
| `Thread` / `AsyncThread` | `.api` | 线程操作封装类 |
| `TurnHandle` / `AsyncTurnHandle` | `.api` | Turn 流式操作句柄 |

### 2. 异常类导出

从 `.errors` 模块导出完整的异常层次结构：
- 基础异常：`AppServerError`, `JsonRpcError`, `TransportClosedError`
- JSON-RPC 标准错误：`ParseError`, `InvalidRequestError`, `MethodNotFoundError`, `InvalidParamsError`, `InternalRpcError`
- 业务错误：`ServerBusyError`, `RetryLimitExceededError`
- 工具函数：`is_retryable_error`

### 3. 生成模型导出

从 `.generated.v2_all` 导出由 `datamodel-codegen` 从 JSON Schema 生成的 Pydantic 模型：
- 配置枚举：`AskForApproval`, `Personality`, `ReasoningEffort`, `SandboxMode`, `SandboxPolicy`, `ServiceTier`
- 线程参数：`ThreadStartParams`, `ThreadResumeParams`, `ThreadListParams`, `ThreadForkParams`
- 通知类型：`TurnCompletedNotification`, `ThreadTokenUsageUpdatedNotification`
- 其他枚举：`PlanType`, `ReasoningSummary`, `ThreadSortKey`, `ThreadSourceKind`, `TurnStatus`, `TurnStartParams`, `TurnSteerParams`

### 4. 输入类型导出

从 `.api` 和 `._inputs` 导出用户输入相关的类型：
- `Input`, `InputItem`, `RunResult`
- `TextInput`, `ImageInput`, `LocalImageInput`, `SkillInput`, `MentionInput`

### 5. 重试工具导出

`retry_on_overload` 装饰器/函数，用于自动重试服务器过载错误。

## 具体技术实现

### 导入结构

```python
# 分层导入模式
from .async_client import AsyncAppServerClient      # 异步客户端
from .client import AppServerClient, AppServerConfig  # 同步客户端+配置
from .errors import ...                              # 异常层次结构
from .generated.v2_all import ...                    # 生成模型（~40个符号）
from .models import InitializeResponse               # 核心模型
from .api import ...                                 # 高级 API（~12个符号）
from .retry import retry_on_overload                 # 重试工具
```

### 版本管理

```python
__version__ = "0.2.0"  # 与 pyproject.toml 中的 version 保持一致
```

### 公共 API 声明

`__all__` 列表包含 52 个符号，明确界定公共接口边界：
- 元信息：`__version__`
- 客户端类：6 个（AppServerClient, AsyncAppServerClient, Codex, AsyncCodex, Thread, AsyncThread）
- 句柄类：2 个（TurnHandle, AsyncTurnHandle）
- 响应/结果类：2 个（InitializeResponse, RunResult）
- 输入类型：6 个（Input, InputItem 及其具体类型）
- 生成模型：~25 个（线程相关参数和枚举）
- 通知类型：2 个
- 异常类：11 个 + 1 个工具函数
- 重试工具：1 个

## 关键代码路径与文件引用

### 依赖关系图

```
codex_app_server/__init__.py
├── async_client.py          # AsyncAppServerClient
├── client.py                # AppServerClient, AppServerConfig
├── errors.py                # 所有异常类
├── generated/
│   ├── v2_all.py           # ~40 个生成模型
│   └── notification_registry.py  # 通知模型注册表
├── models.py               # InitializeResponse, Notification
├── api.py                  # Codex, Thread, TurnHandle 等高级 API
├── retry.py                # retry_on_overload
└── _inputs.py              # Input 类型定义（通过 api.py 间接导出）
```

### 生成代码的依赖

`generated/v2_all.py` 是通过以下流程生成的：
1. Rust 协议定义 → JSON Schema (`codex_app_server_protocol.v2.schemas.json`)
2. `datamodel-code-generator` → Python Pydantic 模型
3. 由 `scripts/update_sdk_artifacts.py` 自动维护

## 依赖与外部交互

### 直接依赖模块

| 模块 | 关系 | 说明 |
|-----|------|------|
| `.async_client` | 导入 | 异步客户端实现 |
| `.client` | 导入 | 同步客户端+配置 |
| `.errors` | 导入 | 完整异常层次 |
| `.generated.v2_all` | 导入 | 生成模型 |
| `.models` | 导入 | 核心数据模型 |
| `.api` | 导入 | 高级 API 封装 |
| `.retry` | 导入 | 重试工具 |

### 外部包依赖

- `pydantic>=2.12`：用于生成模型的数据验证（间接依赖，通过生成代码使用）

## 风险、边界与改进建议

### 当前风险

1. **生成模型版本漂移**：`generated/v2_all.py` 是自动生成的，如果 Rust 协议变更但未重新生成 Python 代码，会导致运行时错误
2. **__all__ 维护负担**：手动维护的 `__all__` 列表容易遗漏新添加的公共符号
3. **循环导入风险**：虽然当前结构避免了循环导入，但随着功能扩展需要警惕

### 边界情况

1. **类型检查器兼容性**：`py.typed` 标记文件存在，确保类型检查器能正确识别类型信息
2. **部分导入支持**：用户可以通过 `from codex_app_server import X` 精确导入所需符号
3. **星号导入**：`from codex_app_server import *` 只会导入 `__all__` 中列出的符号

### 改进建议

1. **自动化 __all__ 生成**：考虑使用 `__all__ = [...]` 的自动生成工具（如 `mkall`）减少维护负担
2. **版本一致性检查**：在 CI 中添加检查确保 `__init__.py` 中的 `__version__` 与 `pyproject.toml` 一致
3. **分层导出**：考虑将导出分为 `codex_app_server`（基础）和 `codex_app_server.types`（类型）等子模块，减少根命名空间污染
4. **废弃警告**：对于计划移除的符号，添加 `warnings.warn` 废弃提示
5. **文档字符串**：为 `__init__.py` 添加模块级文档字符串，描述包的整体用途和快速开始示例

### 测试覆盖

相关测试文件：
- `sdk/python/tests/test_public_api_signatures.py`：验证公共 API 签名
- `sdk/python/tests/test_public_api_runtime_behavior.py`：验证运行时行为
- `sdk/python/tests/test_client_rpc_methods.py`：验证 RPC 方法调用

这些测试确保 `__init__.py` 中导出的符号具有正确的类型注解和运行时行为。
