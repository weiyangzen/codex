# sdk/python/docs/api-reference.md 研究文档

## 场景与职责

`api-reference.md` 是 Codex App Server Python SDK 的 API 参考文档，面向使用该 SDK 的 Python 开发者。文档详细描述了 SDK 的公共接口，包括同步和异步客户端、线程管理、Turn 控制、输入类型以及错误处理机制。

该文档的核心职责是：
1. 为开发者提供完整的 API 签名参考
2. 说明同步 (`Codex`) 和异步 (`AsyncCodex`) 两种客户端的使用方式
3. 解释 Thread/Turn 概念模型及其操作方法
4. 提供输入类型定义和生成的模型引用
5. 说明错误处理和重试机制

## 功能点目的

### 1. 包入口与版本信息
- **目的**：明确 SDK 的公共导出内容和版本要求
- **关键导出**：`Codex`, `AsyncCodex`, `RunResult`, `Thread`, `AsyncThread`, `TurnHandle`, `AsyncTurnHandle`, `InitializeResponse`, 各种输入类型
- **生成模型位置**：`codex_app_server.generated.v2_all`
- **Python 版本要求**：>= 3.10

### 2. 同步客户端 (Codex)
- **目的**：提供阻塞式 API 调用方式，适用于简单脚本和非异步应用
- **初始化方式**：`Codex(config: AppServerConfig | None = None)`
- **上下文管理器支持**：`with Codex() as codex:` 模式确保资源正确释放
- **核心方法**：
  - `thread_start()` - 创建新线程
  - `thread_list()` - 列出线程（支持分页）
  - `thread_resume()` - 恢复现有线程
  - `thread_fork()` - 分叉线程
  - `thread_archive()` / `thread_unarchive()` - 归档管理
  - `models()` - 获取可用模型列表

### 3. 异步客户端 (AsyncCodex)
- **目的**：提供非阻塞式 API 调用方式，适用于高性能异步应用
- **初始化方式**：`AsyncCodex(config: AppServerConfig | None = None)`
- **延迟初始化**：在上下文进入或首次 API 使用时才初始化
- **异步上下文管理器**：`async with AsyncCodex() as codex:`
- **方法签名**：与 `Codex` 完全对应，但返回 `Awaitable` 类型

### 4. Thread / AsyncThread
- **目的**：表示对话状态，管理多轮对话的连续性
- **核心方法**：
  - `run(input)` - 便捷方法：启动 Turn 并等待完成，返回 `RunResult`
  - `turn(input)` - 启动 Turn，返回 `TurnHandle` 用于精细控制
  - `read(include_turns)` - 读取线程状态
  - `set_name(name)` - 设置线程名称
  - `compact()` - 压缩线程上下文

### 5. TurnHandle / AsyncTurnHandle
- **目的**：提供对单个 Turn（模型执行）的细粒度控制
- **核心方法**：
  - `steer(input)` - 向正在进行的 Turn 发送引导输入
  - `interrupt()` - 中断当前 Turn
  - `stream()` - 流式获取通知事件（`Iterator[Notification]` 或 `AsyncIterator[Notification]`）
  - `run()` - 等待 Turn 完成并返回完整的 `Turn` 对象
- **并发限制**：当前实验版本每个客户端实例只能有一个活动的 Turn 消费者

### 6. 输入类型系统
- **目的**：提供类型安全的多模态输入方式
- **输入类型**：
  - `TextInput` - 文本输入
  - `ImageInput` - 远程图片 URL
  - `LocalImageInput` - 本地图片路径
  - `SkillInput` - Skill 引用
  - `MentionInput` - 提及引用
- **类型别名**：`InputItem = TextInput | ImageInput | LocalImageInput | SkillInput | MentionInput`
- **灵活输入**：`Input = list[InputItem] | InputItem` 支持单条或多条输入

### 7. 生成模型
- **目的**：提供与 App Server v2 协议完全一致的类型定义
- **导入路径**：`codex_app_server.generated.v2_all`
- **关键模型**：`AskForApproval`, `ThreadReadResponse`, `Turn`, `TurnStartParams`, `TurnStatus`

### 8. 错误处理与重试
- **目的**：提供健壮的错误处理和自动重试机制
- **关键导出**：
  - `retry_on_overload()` - 对瞬态过载错误进行指数退避重试
  - `is_retryable_error()` - 检查错误是否可重试
  - 错误类型：`JsonRpcError`, `MethodNotFoundError`, `InvalidParamsError`, `ServerBusyError`

## 具体技术实现

### 同步客户端实现 (`client.py`)

```python
class AppServerClient:
    """Synchronous typed JSON-RPC client for `codex app-server` over stdio."""
```

**关键实现细节**：
1. **传输层**：通过 `subprocess.Popen` 启动 `codex app-server --listen stdio://`，使用 stdio 进行 JSON-RPC 通信
2. **并发控制**：使用 `threading.Lock` 保护 `_write_message`，使用 `_turn_consumer_lock` 限制单 Turn 消费者
3. **通知处理**：`_pending_notifications` 双端队列缓存通知，`_coerce_notification` 将原始 JSON 映射到类型化的 `Notification`
4. **参数序列化**：`_params_dict()` 使用 Pydantic 的 `model_dump(by_alias=True, exclude_none=True)` 将 snake_case 参数转为 camelCase

**关键代码路径**：
- `sdk/python/src/codex_app_server/client.py` - `AppServerClient` 类
- `sdk/python/src/codex_app_server/client.py:161-189` - `start()` 方法启动子进程
- `sdk/python/src/codex_app_server/client.py:239-270` - `_request_raw()` 处理 JSON-RPC 请求/响应

### 异步客户端实现 (`async_client.py`)

```python
class AsyncAppServerClient:
    """Async wrapper around AppServerClient using thread offloading."""
```

**关键实现细节**：
1. **线程卸载**：使用 `asyncio.to_thread()` 将同步调用 offload 到线程池
2. **传输锁**：`asyncio.Lock` 保护 stdio 传输，防止多协程并发读写
3. **流式处理**：`stream_text()` 使用迭代器模式，通过 `_next_from_iterator` 在线程间安全获取数据

**关键代码路径**：
- `sdk/python/src/codex_app_server/async_client.py` - `AsyncAppServerClient` 类
- `sdk/python/src/codex_app_server/async_client.py:54-62` - `_call_sync()` 线程卸载核心

### 高级 API 封装 (`api.py`)

**Codex 类**：
```python
class Codex:
    def __init__(self, config: AppServerConfig | None = None) -> None:
        self._client = AppServerClient(config=config)
        self._client.start()
        self._init = self._validate_initialize(self._client.initialize())
```

**关键实现细节**：
1. **立即初始化**：`__init__` 中立即启动传输并执行 `initialize` RPC
2. **元数据验证**：`_validate_initialize()` 解析 `userAgent` 填充 `serverInfo`
3. **Thread 工厂**：`thread_start()` / `thread_resume()` 等方法返回 `Thread` 对象
4. **代码生成**：方法体由代码生成器生成（标记为 `BEGIN GENERATED` / `END GENERATED`）

**Thread 类**：
```python
@dataclass(slots=True)
class Thread:
    _client: AppServerClient
    id: str
```

**关键实现细节**：
1. **轻量级包装**：仅持有客户端引用和线程 ID
2. **Run 便捷方法**：`run()` 内部调用 `turn()` + `stream()` + `_collect_run_result()`
3. **输入规范化**：`_normalize_run_input()` 将字符串转为 `TextInput`

**TurnHandle 类**：
```python
@dataclass(slots=True)
class TurnHandle:
    _client: AppServerClient
    thread_id: str
    id: str
```

**关键实现细节**：
1. **流式消费**：`stream()` 使用 `acquire_turn_consumer()` / `release_turn_consumer()` 管理并发
2. **事件过滤**：只处理与当前 Turn ID 匹配的 `turn/completed` 通知

**关键代码路径**：
- `sdk/python/src/codex_app_server/api.py` - 高级 API 实现
- `sdk/python/src/codex_app_server/api.py:69-124` - `Codex` 类
- `sdk/python/src/codex_app_server/api.py:467-549` - `Thread` 类
- `sdk/python/src/codex_app_server/api.py:643-685` - `TurnHandle` 类

### 输入处理 (`_inputs.py`)

```python
InputItem = TextInput | ImageInput | LocalImageInput | SkillInput | MentionInput
Input = list[InputItem] | InputItem
RunInput = Input | str
```

**关键实现细节**：
1. **类型安全**：使用 `@dataclass(slots=True)` 定义输入类型
2. **Wire 格式转换**：`_to_wire_item()` 将 Python 对象转为 JSON-RPC 所需的字典格式
3. **灵活输入**：支持字符串快捷输入（自动转为 `TextInput`）

**关键代码路径**：
- `sdk/python/src/codex_app_server/_inputs.py` - 输入类型定义和转换

### 运行结果收集 (`_run.py`)

```python
@dataclass(slots=True)
class RunResult:
    final_response: str | None
    items: list[ThreadItem]
    usage: ThreadTokenUsage | None
```

**关键实现细节**：
1. **最终响应提取**：`_final_assistant_response_from_items()` 从 `ThreadItem` 列表中提取最终助手回复
2. **优先级**：优先返回 `phase == MessagePhase.final_answer` 的消息，其次是无 phase 的助手消息
3. **错误处理**：`_raise_for_failed_turn()` 在 Turn 失败时抛出异常

**关键代码路径**：
- `sdk/python/src/codex_app_server/_run.py` - Run 结果收集逻辑

### 错误处理 (`errors.py`)

**异常层次**：
```
AppServerError (基类)
├── JsonRpcError
│   └── AppServerRpcError
│       ├── ParseError (-32700)
│       ├── InvalidRequestError (-32600)
│       ├── MethodNotFoundError (-32601)
│       ├── InvalidParamsError (-32602)
│       ├── InternalRpcError (-32603)
│       └── ServerBusyError (-32099 to -32000)
│           └── RetryLimitExceededError
└── TransportClosedError
```

**关键实现细节**：
1. **错误码映射**：`map_jsonrpc_error()` 根据 JSON-RPC 错误码映射到具体异常类型
2. **过载检测**：`_is_server_overloaded()` 递归检查错误数据中的 `server_overloaded` 标记
3. **可重试判断**：`is_retryable_error()` 判断异常是否属于瞬态过载错误

**关键代码路径**：
- `sdk/python/src/codex_app_server/errors.py` - 错误类型定义和映射

### 重试机制 (`retry.py`)

```python
def retry_on_overload(
    op: Callable[[], T],
    *,
    max_attempts: int = 3,
    initial_delay_s: float = 0.25,
    max_delay_s: float = 2.0,
    jitter_ratio: float = 0.2,
) -> T
```

**关键实现细节**：
1. **指数退避**：延迟时间从 `initial_delay_s` 开始，每次翻倍，上限 `max_delay_s`
2. **抖动**：添加 ±20% 的随机抖动避免惊群效应
3. **选择性重试**：仅对 `is_retryable_error()` 返回 True 的异常进行重试

**关键代码路径**：
- `sdk/python/src/codex_app_server/retry.py` - 重试逻辑实现

## 关键代码路径与文件引用

### SDK 核心文件
| 文件 | 职责 |
|------|------|
| `sdk/python/src/codex_app_server/__init__.py` | 公共 API 导出，定义 `__all__` |
| `sdk/python/src/codex_app_server/api.py` | 高级 API (`Codex`, `Thread`, `TurnHandle`) |
| `sdk/python/src/codex_app_server/client.py` | 底层同步 JSON-RPC 客户端 |
| `sdk/python/src/codex_app_server/async_client.py` | 异步客户端包装器 |
| `sdk/python/src/codex_app_server/_inputs.py` | 输入类型定义和转换 |
| `sdk/python/src/codex_app_server/_run.py` | Run 结果收集逻辑 |
| `sdk/python/src/codex_app_server/models.py` | 核心模型定义 (`Notification`, `InitializeResponse`) |
| `sdk/python/src/codex_app_server/errors.py` | 异常类型和错误映射 |
| `sdk/python/src/codex_app_server/retry.py` | 重试逻辑 |
| `sdk/python/src/codex_app_server/generated/v2_all.py` | 从 Rust 协议生成的 Pydantic 模型 |

### 配置文件
| 文件 | 职责 |
|------|------|
| `sdk/python/pyproject.toml` | 包元数据、依赖、构建配置 |

### 测试文件
| 文件 | 职责 |
|------|------|
| `sdk/python/tests/test_public_api_signatures.py` | 验证公共 API 签名 |
| `sdk/python/tests/test_client_rpc_methods.py` | 测试 RPC 方法调用 |
| `sdk/python/tests/test_async_client_behavior.py` | 测试异步客户端行为 |

### Rust 协议定义（生成 Python 模型的来源）
| 文件 | 职责 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | App Server v2 协议定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 共享协议组件 |

## 依赖与外部交互

### Python 依赖
```toml
dependencies = ["pydantic>=2.12"]
```

**Pydantic 用途**：
1. 数据验证和序列化/反序列化
2. 生成模型的基类 (`BaseModel`)
3. 配置 `model_dump(by_alias=True)` 实现 snake_case 到 camelCase 的自动转换

### 运行时依赖
**codex-cli-bin**：
- SDK 需要 `codex-cli-bin` 包提供运行时二进制文件
- 通过 `codex_cli_bin.bundled_codex_path()` 定位二进制文件
- 可通过 `AppServerConfig.codex_bin` 覆盖二进制文件路径

### 协议交互
**JSON-RPC over stdio**：
1. SDK 启动 `codex app-server --listen stdio://` 子进程
2. 通过 stdin 发送 JSON-RPC 请求
3. 通过 stdout 接收 JSON-RPC 响应和通知
4. stderr 由独立线程收集用于调试

**初始化流程**：
```
1. Client -> Server: initialize { clientInfo, capabilities }
2. Server -> Client: InitializeResponse { serverInfo, userAgent, ... }
3. Client -> Server: initialized (notification)
```

**Turn 执行流程**：
```
1. Client -> Server: turn/start { threadId, input, ... }
2. Server -> Client: TurnStartResponse { turn }
3. Server -> Client: [notifications...] (item/started, item/agentMessage/delta, ...)
4. Server -> Client: turn/completed { turn }
```

### 代码生成依赖
**datamodel-code-generator**：
- 从 JSON Schema 生成 Python Pydantic 模型
- 生成文件：`sdk/python/src/codex_app_server/generated/v2_all.py`
- 模式来源：`codex_app_server_protocol.v2.schemas.json`

## 风险、边界与改进建议

### 已知限制

1. **单 Turn 消费者限制**
   - **风险**：当前实验版本每个客户端实例只能有一个活动的 Turn 消费者
   - **表现**：尝试在 `stream()` 或 `run()` 进行时启动第二个消费者会抛出 `RuntimeError`
   - **代码位置**：`client.py:288-296` (`acquire_turn_consumer`)
   - **缓解**：使用多个 `Codex` / `AsyncCodex` 实例实现并发

2. **同步客户端的阻塞特性**
   - **风险**：`Codex` 在 `__init__` 中立即启动子进程并执行初始化 RPC
   - **表现**：构造函数可能阻塞较长时间，且在网络问题时会抛出异常
   - **代码位置**：`api.py:72-79`
   - **建议**：使用 `AsyncCodex` 进行延迟初始化

3. **字符串输入的隐式转换**
   - **风险**：`Thread.run()` 接受 `str | Input`，字符串会被隐式转为 `TextInput`
   - **边界**：无法直接传递原始 JSON 输入
   - **代码位置**：`_inputs.py:60-63` (`_normalize_run_input`)

4. **错误信息可能泄露敏感信息**
   - **风险**：`_stderr_tail()` 可能将 stderr 内容包含在异常消息中
   - **代码位置**：`client.py:499-500`

### 改进建议

1. **支持多 Turn 并发**
   - 当前 `acquire_turn_consumer` 使用客户端级别的锁
   - 建议改为 Turn 级别的通知路由，允许并发执行多个 Turn

2. **添加连接池支持**
   - 当前每个 `Codex` 实例对应一个子进程
   - 建议添加连接池管理多个子进程，提高吞吐量

3. **改进错误上下文**
   - 当前错误消息可能过于底层（JSON-RPC 错误码）
   - 建议添加更友好的错误消息和故障排除建议

4. **添加类型安全的配置验证**
   - `AppServerConfig` 使用简单的 dataclass
   - 建议添加 Pydantic 验证确保配置有效性

5. **文档改进**
   - 添加更多关于 `Notification` 类型的详细文档
   - 提供完整的错误处理最佳实践示例
   - 说明 `RunResult.final_response` 为 `None` 的各种情况

### 测试覆盖建议

1. **并发场景测试**：验证多线程/多协程使用单个客户端时的行为
2. **网络故障恢复**：测试连接中断后的恢复机制
3. **大数据输入**：测试大图片/长文本输入的处理
4. **内存泄漏**：长时间运行场景下的内存使用监控
