# 09_async_parity 示例研究文档

## 场景与职责

### 定位与目的

`09_async_parity` 是 Python SDK 示例系列中的第 9 个示例，其独特之处在于**仅包含同步版本 (`sync.py`)**，专门用于展示和验证 Python SDK 中同步与异步 API 的**功能对等性 (Feature Parity)**。

根据 `examples/README.md` 中的索引描述：
> - `09_async_parity/`
>   - parity-style sync flow (see async parity in other examples)

这表明该示例的核心职责是：
1. **验证 API 一致性**：确保同步 API (`Codex`) 与异步 API (`AsyncCodex`) 在功能上完全对等
2. **提供对比基准**：开发者可通过将此 sync.py 与其他示例的 async.py 对比，理解同步/异步 API 的调用模式差异
3. **回归测试参考**：作为 CI/CD 中验证 API 表面一致性的参照点

### 与其他示例的关系

| 示例 | 包含 async.py | 包含 sync.py | 用途 |
|------|--------------|-------------|------|
| 01_quickstart_constructor | ✓ | ✓ | 基础入门 |
| 02_turn_run | ✓ | ✓ | Turn 运行 |
| 05_existing_thread | ✓ | ✓ | 线程恢复 |
| **09_async_parity** | **✗** | **✓** | **API 对等性验证** |

**09_async_parity 的特殊性**：
- 它是唯一一个**故意不包含 async.py** 的示例
- 它的存在意味着："此处的同步代码模式，在其他示例的 async.py 中都有对应的异步实现"
- 开发者应将 `09_async_parity/sync.py` 与 `02_turn_run/async.py` 或 `05_existing_thread/async.py` 对比学习

---

## 功能点目的

### 核心功能

该示例演示以下完整流程：

1. **SDK 初始化**：通过 `runtime_config()` 创建配置并初始化 `Codex` 客户端
2. **线程创建**：使用 `codex.thread_start()` 创建新线程，指定模型和配置
3. **Turn 执行**：创建 `TextInput` 并执行 turn，获取 AI 响应
4. **持久化验证**：通过 `thread.read()` 读取持久化后的线程状态
5. **结果提取**：使用辅助函数从 turn 中提取 assistant 的文本回复

### 代码流程详解

```python
# 1. 导入与引导
from _bootstrap import (
    assistant_text_from_turn,
    ensure_local_sdk_src,
    find_turn_by_id,
    runtime_config,
    server_label,
)
ensure_local_sdk_src()  # 确保使用本地 SDK 源码而非已安装包

# 2. 客户端初始化
from codex_app_server import Codex, TextInput
with Codex(config=runtime_config()) as codex:
    print("Server:", server_label(codex.metadata))
    
    # 3. 创建线程
    thread = codex.thread_start(
        model="gpt-5.4", 
        config={"model_reasoning_effort": "high"}
    )
    
    # 4. 执行 Turn
    turn = thread.turn(TextInput("Say hello in one sentence."))
    result = turn.run()
    
    # 5. 验证持久化
    persisted = thread.read(include_turns=True)
    persisted_turn = find_turn_by_id(persisted.thread.turns, result.id)
    
    # 6. 输出结果
    print("Thread:", thread.id)
    print("Turn:", result.id)
    print("Text:", assistant_text_from_turn(persisted_turn).strip())
```

### 与异步版本的对比

| 操作 | 同步版本 (09_async_parity/sync.py) | 异步版本 (如 02_turn_run/async.py) |
|------|-----------------------------------|-----------------------------------|
| 客户端创建 | `with Codex(...) as codex:` | `async with AsyncCodex(...) as codex:` |
| 线程创建 | `thread = codex.thread_start(...)` | `thread = await codex.thread_start(...)` |
| Turn 创建 | `turn = thread.turn(...)` | `turn = await thread.turn(...)` |
| Turn 执行 | `result = turn.run()` | `result = await turn.run()` |
| 线程读取 | `persisted = thread.read(...)` | `persisted = await thread.read(...)` |

---

## 具体技术实现

### 关键流程

#### 1. 同步客户端架构 (`Codex` / `Thread` / `TurnHandle`)

```
┌─────────────────────────────────────────────────────────────────┐
│                        Codex (api.py)                           │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  __init__() -> _client = AppServerClient()              │   │
│  │              -> _client.start()                         │   │
│  │              -> _client.initialize()                    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                          │                                      │
│                          ▼                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  thread_start() -> Thread(_client, thread_id)           │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                       Thread (api.py)                           │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  turn() -> TurnHandle(_client, thread_id, turn_id)      │   │
│  └─────────────────────────────────────────────────────────┘   │
│                          │                                      │
│                          ▼                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  run() -> _collect_run_result(stream, turn_id)          │   │
│  │         -> RunResult(final_response, items, usage)      │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     TurnHandle (api.py)                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  stream() -> Iterator[Notification]                     │   │
│  │         -> yield events until turn/completed            │   │
│  └─────────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  run() -> stream() -> collect -> AppServerTurn          │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

#### 2. 异步客户端架构 (`AsyncCodex` / `AsyncThread` / `AsyncTurnHandle`)

异步客户端通过 `AsyncAppServerClient` 包装同步客户端，使用 `asyncio.to_thread()` 将同步调用 offload 到线程池：

```python
# async_client.py
class AsyncAppServerClient:
    async def _call_sync(self, fn, /, *args, **kwargs):
        async with self._transport_lock:  # 确保串行访问 stdio 传输层
            return await asyncio.to_thread(fn, *args, **kwargs)
    
    async def thread_start(self, params=None):
        return await self._call_sync(self._sync.thread_start, params)
```

#### 3. 事件流处理流程

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   turn.start()  │────▶│  next_notification│────▶│  Event Stream   │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        ▼                     ▼                     ▼
┌───────────────┐    ┌─────────────────┐    ┌───────────────┐
│ item/completed│    │thread/tokenUsage│    │ turn/completed│
│  (收集 items)  │    │  (收集 usage)    │    │  (结束标志)    │
└───────────────┘    └─────────────────┘    └───────────────┘
```

### 数据结构

#### 核心数据类

```python
# _run.py
@dataclass(slots=True)
class RunResult:
    final_response: str | None  # AI 的最终文本回复
    items: list[ThreadItem]     # 所有 ThreadItem
    usage: ThreadTokenUsage | None  # Token 使用量

# api.py
@dataclass(slots=True)
class Thread:
    _client: AppServerClient
    id: str

@dataclass(slots=True)
class TurnHandle:
    _client: AppServerClient
    thread_id: str
    id: str
```

#### 输入类型

```python
# _inputs.py
@dataclass(slots=True)
class TextInput:
    text: str

@dataclass(slots=True)
class ImageInput:
    url: str

@dataclass(slots=True)
class LocalImageInput:
    path: str

InputItem = TextInput | ImageInput | LocalImageInput | SkillInput | MentionInput
Input = list[InputItem] | InputItem
RunInput = Input | str  # 支持直接传字符串
```

### 协议与通信

#### JSON-RPC over stdio

```python
# client.py - AppServerClient
class AppServerClient:
    def _write_message(self, payload: JsonObject) -> None:
        with self._lock:
            self._proc.stdin.write(json.dumps(payload) + "\n")
            self._proc.stdin.flush()
    
    def _read_message(self) -> dict[str, JsonValue]:
        line = self._proc.stdout.readline()
        return json.loads(line)
```

#### 关键 RPC 方法

| 方法 | 用途 |
|------|------|
| `initialize` | 客户端/服务器握手 |
| `thread/start` | 创建新线程 |
| `thread/read` | 读取线程状态 |
| `turn/start` | 启动新的 turn |
| `turn/completed` (notification) | Turn 完成通知 |
| `item/completed` (notification) | Item 完成通知 |

### 命令与工具

#### Bootstrap 辅助函数

```python
# _bootstrap.py
def runtime_config() -> AppServerConfig:
    """返回示例友好的配置"""
    return AppServerConfig()

def assistant_text_from_turn(turn: object | None) -> str:
    """从 turn 对象中提取 assistant 的文本回复"""
    # 处理 agentMessage 和 message 两种类型
    
def find_turn_by_id(turns: Iterable[object] | None, turn_id: str) -> object | None:
    """在线程的 turns 列表中查找指定 ID 的 turn"""
```

---

## 关键代码路径与文件引用

### 09_async_parity 目录结构

```
sdk/python/examples/09_async_parity/
└── sync.py          # 唯一文件，同步 API 示例
```

### 依赖文件链

```
09_async_parity/sync.py
    │
    ├──▶ _bootstrap.py (同目录父级)
    │       ├──▶ _runtime_setup.py
    │       └──▶ 辅助函数: runtime_config(), assistant_text_from_turn(), find_turn_by_id()
    │
    └──▶ codex_app_server (sdk/python/src/codex_app_server/)
            │
            ├──▶ __init__.py
            │       └── 导出: Codex, TextInput, AppServerConfig, ...
            │
            ├──▶ api.py
            │       ├──▶ class Codex
            │       ├──▶ class Thread
            │       ├──▶ class TurnHandle
            │       ├──▶ class AsyncCodex      (对比参考)
            │       ├──▶ class AsyncThread     (对比参考)
            │       └──▶ class AsyncTurnHandle (对比参考)
            │
            ├──▶ client.py
            │       └──▶ class AppServerClient (同步 JSON-RPC 客户端)
            │
            ├──▶ async_client.py
            │       └──▶ class AsyncAppServerClient (异步包装器)
            │
            ├──▶ _inputs.py
            │       └──▶ TextInput, ImageInput, ...
            │
            ├──▶ _run.py
            │       └──▶ RunResult, _collect_run_result()
            │
            └──▶ generated/v2_all.py
                    └──▶ Pydantic 模型 (ThreadStartResponse, TurnCompletedNotification, ...)
```

### 核心代码路径

#### 同步路径

```
sync.py:20  with Codex(config=runtime_config()) as codex:
    │
    ▼
api.py:72-79  Codex.__init__()
    │
    ▼
client.py:161-189  AppServerClient.start()
    │
    ▼
client.py:209-225  AppServerClient.initialize()
    │
    ▼
api.py:133-166  Codex.thread_start()
    │
    ▼
api.py:507-538  Thread.turn()
    │
    ▼
api.py:671-684  TurnHandle.run()
    │
    ▼
api.py:655-669  TurnHandle.stream()
    │
    ▼
_run.py:59-83  _collect_run_result()
```

#### 异步路径（对比参考）

```
async.py:22  async with AsyncCodex(...) as codex:
    │
    ▼
api.py:278-306  AsyncCodex.__init__() / _ensure_initialized()
    │
    ▼
async_client.py:73-77  AsyncAppServerClient.start()/close()
    │
    ▼
async_client.py:54-62  _call_sync()  [核心: asyncio.to_thread()]
    │
    ▼
api.py:323-357  AsyncCodex.thread_start()
    │
    ▼
api.py:591-627  AsyncThread.turn()
    │
    ▼
api.py:722-734  AsyncTurnHandle.run()
    │
    ▼
_run.py:86-112  _collect_async_run_result()
```

---

## 依赖与外部交互

### Python 依赖

```
codex_app_server/
    ├── pydantic          # 数据模型验证
    ├── asyncio           # 异步支持 (Python 标准库)
    └── typing            # 类型提示
```

### 外部进程交互

```
sync.py
    │
    ▼
AppServerClient
    │
    ▼ 启动子进程
codex-cli-bin (Rust 二进制)
    │
    ▼ JSON-RPC over stdio
app-server (Rust 端)
    │
    ▼ HTTP/ WebSocket
OpenAI API / Codex Backend
```

### 运行时依赖

| 组件 | 版本 | 来源 |
|------|------|------|
| codex-cli-bin | 0.116.0-alpha.1 | GitHub Release / PyPI |
| Python | >=3.10 | 系统 |
| pydantic | * | pip |

### 配置依赖

```python
# runtime_config() 返回的默认配置
AppServerConfig(
    codex_bin=None,              # 使用已安装的 codex-cli-bin
    launch_args_override=None,   # 无自定义启动参数
    config_overrides=(),         # 无配置覆盖
    cwd=None,                    # 使用当前工作目录
    env=None,                    # 无额外环境变量
    client_name="codex_python_sdk",
    client_title="Codex Python SDK",
    client_version="0.2.0",
    experimental_api=True,       # 启用实验性 API
)
```

---

## 风险、边界与改进建议

### 当前风险

#### 1. 单线程 Turn 消费限制

```python
# client.py:288-296
def acquire_turn_consumer(self, turn_id: str) -> None:
    with self._turn_consumer_lock:
        if self._active_turn_consumer is not None:
            raise RuntimeError(
                "Concurrent turn consumers are not yet supported in the experimental SDK."
            )
        self._active_turn_consumer = turn_id
```

**风险**：同时只能有一个 turn 在流式消费事件，尝试并发消费会抛出 RuntimeError。

**影响**：
- 无法同时监控多个线程的 turn 进度
- 高并发场景下可能成为瓶颈

#### 2. 异步客户端的线程锁竞争

```python
# async_client.py:54-62
async def _call_sync(self, fn, /, *args, **kwargs):
    async with self._transport_lock:  # 全局锁
        return await asyncio.to_thread(fn, *args, **kwargs)
```

**风险**：所有异步 API 调用共享同一个 `_transport_lock`，虽然保证了 stdio 传输安全，但限制了并发性能。

#### 3. 缺少 async.py 的潜在混淆

**风险**：开发者可能困惑于为何 09_async_parity 没有 async.py，误以为异步 API 不支持某些功能。

### 边界条件

#### 1. 初始化失败处理

```python
# api.py:72-79
def __init__(self, config: AppServerConfig | None = None) -> None:
    self._client = AppServerClient(config=config)
    try:
        self._client.start()
        self._init = self._validate_initialize(self._client.initialize())
    except Exception:
        self._client.close()  # 确保资源释放
        raise
```

边界：初始化失败时会自动关闭客户端，避免僵尸进程。

#### 2. 流式消费边界

```python
# api.py:655-669
def stream(self) -> Iterator[Notification]:
    self._client.acquire_turn_consumer(self.id)
    try:
        while True:
            event = self._client.next_notification()
            yield event
            if event.method == "turn/completed" and ...:
                break
    finally:
        self._client.release_turn_consumer(self.id)  # 确保释放
```

边界：使用 `try/finally` 确保 turn consumer 锁总是被释放，避免死锁。

#### 3. 字符串输入自动转换

```python
# _inputs.py:60-63
def _normalize_run_input(input: RunInput) -> Input:
    if isinstance(input, str):
        return TextInput(input)
    return input
```

边界：`Thread.run()` 支持直接传字符串，会自动包装为 `TextInput`。

### 改进建议

#### 1. 文档改进

**建议**：在 `09_async_parity/sync.py` 文件顶部添加明确注释，说明为何没有对应的 async.py：

```python
"""
09_async_parity - API 功能对等性验证示例

此示例仅包含同步版本，用于验证同步 API (Codex) 与异步 API (AsyncCodex) 的功能对等性。

对应的异步实现请参考：
- examples/02_turn_run/async.py
- examples/05_existing_thread/async.py

关键差异：
- 使用 `async with AsyncCodex()` 替代 `with Codex()`
- 所有方法调用前添加 `await`
"""
```

#### 2. 添加显式的 parity 测试

**建议**：在测试套件中添加自动化测试，验证 sync 和 async API 的行为一致性：

```python
# 建议添加的测试模式
def test_parity_thread_start():
    """验证 sync 和 async 的 thread_start 返回相同结构"""
    # 对比 Codex.thread_start() 和 AsyncCodex.thread_start() 的返回结果
```

#### 3. 异步客户端性能优化

**建议**：考虑为异步客户端实现真正的异步 I/O，而非基于线程的包装：

```python
# 当前实现 (基于线程)
async def _call_sync(self, fn, /, *args, **kwargs):
    async with self._transport_lock:
        return await asyncio.to_thread(fn, *args, **kwargs)

# 潜在优化：真正的异步 I/O
async def request(self, method, params, *, response_model):
    # 使用 asyncio 原生 subprocess 和流
    # 避免 GIL 和线程切换开销
```

#### 4. 并发 Turn 消费支持

**建议**：实现 per-turn 的事件多路复用，解除单 turn consumer 限制：

```python
# 当前限制
self._active_turn_consumer: str | None = None  # 全局单一消费者

# 建议改进
self._turn_consumers: dict[str, Queue[Notification]]  # 每 turn 一个队列
```

#### 5. 示例增强

**建议**：在 09_async_parity 目录下添加 `PARITY.md` 文档，列出所有 sync/async API 的对比表格：

```markdown
| 同步 API | 异步 API | 差异说明 |
|---------|---------|---------|
| `Codex()` | `AsyncCodex()` | 使用 `async with` |
| `thread.turn()` | `await thread.turn()` | 添加 await |
| `turn.run()` | `await turn.run()` | 添加 await |
```

---

## 附录：相关测试文件

| 测试文件 | 测试内容 |
|---------|---------|
| `tests/test_async_client_behavior.py` | 异步客户端序列化、流式阻塞行为 |
| `tests/test_public_api_runtime_behavior.py` | 同步/异步初始化、turn 流、run 结果收集 |
| `tests/test_client_rpc_methods.py` | JSON-RPC 方法调用 |

---

## 总结

`09_async_parity` 示例虽然代码量小，但承载了重要的架构验证职责：

1. **它是同步/异步 API 对等的活文档**：开发者可通过对比学习两种编程模型的差异
2. **它验证了 SDK 的分层设计**：底层 `AppServerClient` + 中层 `AsyncAppServerClient` 包装 + 顶层 `Codex`/`AsyncCodex` API
3. **它揭示了当前限制**：单 turn consumer 限制、异步客户端的线程锁设计

对于希望深入理解 Python SDK 架构的开发者，建议阅读顺序：
1. `09_async_parity/sync.py` - 理解同步 API 模式
2. `02_turn_run/async.py` - 对比异步 API 模式
3. `client.py` + `async_client.py` - 理解底层实现
4. `api.py` - 理解高层 API 设计
