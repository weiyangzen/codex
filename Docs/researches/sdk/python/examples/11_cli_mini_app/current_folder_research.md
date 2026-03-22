# 11_cli_mini_app 深度研究文档

## 1. 场景与职责

### 1.1 定位与目标

`11_cli_mini_app` 是 Codex App Server Python SDK 的**交互式聊天示例**，展示如何构建一个完整的 CLI 对话应用。它是 SDK 示例序列中的第 11 个示例，位于从基础用法到高级功能的过渡阶段。

该示例的核心目标是：
- 演示**持续多轮对话**的完整生命周期管理
- 展示**实时流式响应**（streaming）的处理模式
- 提供**Token 使用量统计**的监控示例
- 展示同步 (`sync.py`) 与异步 (`async.py`) 两种编程模型的完整对比

### 1.2 典型使用场景

| 场景 | 描述 |
|------|------|
| 交互式 AI 助手 | 构建类似 ChatGPT CLI 的持续对话界面 |
| 开发调试工具 | 开发者用于测试 Codex API 的交互式环境 |
| 教学演示 | 展示 SDK 流式事件处理的最佳实践 |
| 原型开发 | 作为更复杂对话应用的基础模板 |

### 1.3 与前后示例的关系

```
10_error_handling_and_retry/  → 错误处理与重试机制
11_cli_mini_app/              → 【当前】交互式聊天循环
12_turn_params_kitchen_sink/  → 高级 Turn 参数配置
```

`11_cli_mini_app` 是首个展示**完整交互循环**的示例，之前的示例都是单次调用的演示。

---

## 2. 功能点目的

### 2.1 核心功能清单

| 功能 | 目的 | 实现文件 |
|------|------|----------|
| 交互式输入循环 | 持续接收用户输入直到退出命令 | `sync.py`, `async.py` |
| 流式响应渲染 | 实时显示 AI 生成的文本片段 | `sync.py`, `async.py` |
| Token 使用统计 | 展示每次对话的 Token 消耗详情 | `sync.py`, `async.py` |
| 状态监控 | 跟踪 Turn 的执行状态 (completed/failed) | `sync.py`, `async.py` |
| 异步支持 | 展示异步编程模型的完整实现 | `async.py` |

### 2.2 功能详细说明

#### 2.2.1 交互式输入循环

```python
while True:
    try:
        user_input = input("you> ").strip()  # sync
        # user_input = (await asyncio.to_thread(input, "you> ")).strip()  # async
    except EOFError:
        break

    if not user_input:
        continue
    if user_input in {"/exit", "/quit"}:
        break
```

**设计要点：**
- 使用 `EOFError` 捕获处理 Ctrl+D 退出
- 支持 `/exit` 和 `/quit` 两种退出命令
- 空输入直接跳过，不发起 API 调用

#### 2.2.2 流式响应处理

```python
print("assistant> ", end="", flush=True)
for event in turn.stream():  # async: async for event in turn.stream()
    payload = event.payload
    if event.method == "item/agentMessage/delta":
        delta = getattr(payload, "delta", "")
        if delta:
            print(delta, end="", flush=True)
            printed_delta = True
```

**关键事件类型：**

| 事件方法 | 类型 | 说明 |
|----------|------|------|
| `item/agentMessage/delta` | `AgentMessageDeltaNotification` | AI 消息文本片段 |
| `thread/tokenUsage/updated` | `ThreadTokenUsageUpdatedNotification` | Token 使用量更新 |
| `turn/completed` | `TurnCompletedNotification` | Turn 完成通知 |

#### 2.2.3 Token 使用统计格式化

```python
def _format_usage(usage: object | None) -> str:
    if usage is None:
        return "usage> (none)"

    last = getattr(usage, "last", None)
    total = getattr(usage, "total", None)
    
    return (
        "usage>\n"
        f"  last: input={last.input_tokens} output={last.output_tokens} "
        f"reasoning={last.reasoning_output_tokens} total={last.total_tokens} "
        f"cached={last.cached_input_tokens}\n"
        f"  total: input={total.input_tokens} ..."
    )
```

**统计维度：**
- `last`: 最后一次 Turn 的 Token 消耗
- `total`: 整个 Thread 的累计 Token 消耗
- 细分指标：input、output、reasoning、cached

---

## 3. 具体技术实现

### 3.1 关键流程

#### 3.1.1 同步版本执行流程 (`sync.py`)

```
┌─────────────────────────────────────────────────────────────┐
│  1. 引导与初始化                                              │
│     ├── ensure_local_sdk_src()                              │
│     └── from codex_app_server import ...                    │
├─────────────────────────────────────────────────────────────┤
│  2. 客户端初始化                                              │
│     with Codex(config=runtime_config()) as codex:           │
│     ├── AppServerClient.__init__()                          │
│     ├── AppServerClient.start()                             │
│     └── AppServerClient.initialize()  # JSON-RPC initialize │
├─────────────────────────────────────────────────────────────┤
│  3. Thread 创建                                               │
│     thread = codex.thread_start(model="gpt-5.4", ...)       │
│     └── 内部调用 thread/start RPC                           │
├─────────────────────────────────────────────────────────────┤
│  4. 交互循环                                                  │
│     while True:                                             │
│     ├── input("you> ")  # 用户输入                          │
│     ├── thread.turn(TextInput(...))  # 创建 Turn           │
│     │   └── turn/start RPC                                  │
│     ├── for event in turn.stream():  # 流式消费            │
│     │   ├── item/agentMessage/delta → 实时输出             │
│     │   ├── thread/tokenUsage/updated → 更新 usage         │
│     │   └── turn/completed → 获取状态                      │
│     └── 打印 usage 统计                                     │
├─────────────────────────────────────────────────────────────┤
│  5. 资源清理                                                  │
│     └── __exit__ → AppServerClient.close()                  │
└─────────────────────────────────────────────────────────────┘
```

#### 3.1.2 异步版本执行流程 (`async.py`)

```
┌─────────────────────────────────────────────────────────────┐
│  1. 异步上下文进入                                            │
│     async with AsyncCodex(config=runtime_config()) as codex:│
│     └── _ensure_initialized() → 延迟初始化                  │
├─────────────────────────────────────────────────────────────┤
│  2. 异步 Thread 操作                                          │
│     thread = await codex.thread_start(...)                  │
│     └── 内部通过 _call_sync() 在线程池中执行                 │
├─────────────────────────────────────────────────────────────┤
│  3. 异步交互循环                                              │
│     while True:                                             │
│     ├── await asyncio.to_thread(input, ...)  # 非阻塞输入   │
│     ├── turn = await thread.turn(...)                       │
│     ├── async for event in turn.stream():  # 异步迭代       │
│     │   └── 同 sync 版本的事件处理逻辑                      │
│     └── 打印统计                                              │
├─────────────────────────────────────────────────────────────┤
│  4. 异步资源清理                                              │
│     └── __aexit__ → await close()                           │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 关键数据结构

#### 3.2.1 输入类型定义

```python
# sdk/python/src/codex_app_server/_inputs.py

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
```

#### 3.2.2 Notification 数据模型

```python
# sdk/python/src/codex_app_server/models.py

@dataclass(slots=True)
class Notification:
    method: str
    payload: NotificationPayload  # Union of 30+ notification types

# 关键 Notification 类型
class ThreadTokenUsageUpdatedNotification(BaseModel):
    thread_id: str
    turn_id: str
    token_usage: ThreadTokenUsage

class TurnCompletedNotification(BaseModel):
    turn: Turn  # 包含 status, error 等字段

class AgentMessageDeltaNotification(BaseModel):
    delta: str  # 文本片段
    item_id: str
    thread_id: str
    turn_id: str
```

#### 3.2.3 TurnHandle 结构

```python
# sdk/python/src/codex_app_server/api.py

@dataclass(slots=True)
class TurnHandle:
    _client: AppServerClient
    thread_id: str
    id: str

    def steer(self, input: Input) -> TurnSteerResponse: ...
    def interrupt(self) -> TurnInterruptResponse: ...
    def stream(self) -> Iterator[Notification]: ...
    def run(self) -> AppServerTurn: ...
```

### 3.3 协议细节

#### 3.3.1 JSON-RPC v2 协议

```python
# 请求格式
{
    "id": "uuid-string",
    "method": "turn/start",
    "params": {
        "threadId": "thread-xxx",
        "input": [{"type": "text", "text": "..."}],
        ...
    }
}

# 响应格式
{
    "id": "uuid-string",
    "result": {
        "turn": {"id": "turn-xxx", ...}
    }
}

# 通知格式 (服务器推送)
{
    "method": "item/agentMessage/delta",
    "params": {
        "delta": "text chunk",
        "itemId": "...",
        "threadId": "...",
        "turnId": "..."
    }
}
```

#### 3.3.2 传输层实现

```python
# sdk/python/src/codex_app_server/client.py

class AppServerClient:
    def _write_message(self, payload: JsonObject) -> None:
        with self._lock:
            self._proc.stdin.write(json.dumps(payload) + "\n")
            self._proc.stdin.flush()

    def _read_message(self) -> dict[str, JsonValue]:
        line = self._proc.stdout.readline()
        if not line:
            raise TransportClosedError(...)
        return json.loads(line)
```

**传输特性：**
- 基于 stdio 的 JSON-RPC over newline-delimited JSON
- 每个消息以换行符分隔
- 使用 `subprocess.Popen` 启动 `codex app-server` 进程

### 3.4 命令与 RPC 映射

| 用户命令 | SDK 方法 | RPC 方法 | 说明 |
|----------|----------|----------|------|
| 任意文本 | `thread.turn(TextInput)` | `turn/start` | 发起新 Turn |
| /exit | - | - | 本地退出循环 |
| - | `turn.stream()` | 消费通知 | 实时获取 AI 响应 |
| - | `turn.interrupt()` | `turn/interrupt` | 中断当前 Turn |

---

## 4. 关键代码路径与文件引用

### 4.1 核心文件结构

```
sdk/python/
├── examples/11_cli_mini_app/
│   ├── sync.py          # 同步版本 CLI 实现
│   └── async.py         # 异步版本 CLI 实现
├── examples/_bootstrap.py    # 示例引导工具
├── src/codex_app_server/
│   ├── __init__.py      # 公共 API 导出
│   ├── api.py           # Codex, Thread, TurnHandle 高层封装
│   ├── client.py        # AppServerClient 同步客户端
│   ├── async_client.py  # AsyncAppServerClient 异步包装
│   ├── _inputs.py       # 输入类型定义
│   ├── _run.py          # RunResult 收集逻辑
│   ├── models.py        # Notification 等数据模型
│   ├── errors.py        # 异常类型定义
│   └── generated/
│       └── v2_all.py    # 自动生成的 Pydantic 模型
└── docs/
    ├── getting-started.md
    └── api-reference.md
```

### 4.2 关键代码路径

#### 4.2.1 同步流式消费路径

```
sync.py:64-81
    turn.stream()
        ↓
api.py:655-669 (TurnHandle.stream)
    _client.acquire_turn_consumer(self.id)
    while True:
        event = self._client.next_notification()
        yield event
        if event.method == "turn/completed": break
    finally: _client.release_turn_consumer(self.id)
        ↓
client.py:275-286 (next_notification)
    _read_message() → _coerce_notification()
```

#### 4.2.2 异步流式消费路径

```
async.py:67-81
    async for event in turn.stream()
        ↓
api.py:705-720 (AsyncTurnHandle.stream)
    await self._codex._ensure_initialized()
    self._codex._client.acquire_turn_consumer(self.id)
    while True:
        event = await self._codex._client.next_notification()
        yield event
        ↓
async_client.py:184-185
    await self._call_sync(self._sync.next_notification)
        ↓
async_client.py:54-62 (_call_sync)
    async with self._transport_lock:
        return await asyncio.to_thread(fn, ...)
```

#### 4.2.3 Token 使用量更新路径

```
client.py:275 (next_notification)
    msg = _read_message()
    return _coerce_notification(method, params)
        ↓
client.py:455-466 (_coerce_notification)
    model = NOTIFICATION_MODELS.get(method)
    payload = model.model_validate(params_dict)
        ↓
generated/notification_registry.py
    NOTIFICATION_MODELS = {
        "thread/tokenUsage/updated": ThreadTokenUsageUpdatedNotification,
        ...
    }
```

### 4.3 配置与启动路径

```
sync.py:42
    with Codex(config=runtime_config()) as codex:
        ↓
_bootstrap.py:50-55 (runtime_config)
    ensure_runtime_package_installed(...)
    return AppServerConfig()
        ↓
client.py:123-133 (AppServerConfig)
    dataclass with: codex_bin, launch_args_override, 
                    config_overrides, cwd, env, ...
```

---

## 5. 依赖与外部交互

### 5.1 运行时依赖

| 依赖 | 版本 | 用途 |
|------|------|------|
| Python | >=3.10 | 运行时环境 |
| pydantic | - | 数据模型验证与序列化 |
| codex-cli-bin | 0.116.0-alpha.1 | Codex 二进制运行时 |

### 5.2 SDK 内部依赖关系

```
11_cli_mini_app/sync.py
    ├── _bootstrap.py
    │   └── _runtime_setup.py (ensure_runtime_package_installed)
    └── codex_app_server
        ├── __init__.py
        │   ├── Codex (from api.py)
        │   ├── TextInput (from _inputs.py)
        │   └── ThreadTokenUsageUpdatedNotification (from generated.v2_all)
        ├── api.py
        │   ├── Codex → AppServerClient
        │   ├── Thread → turn_start
        │   └── TurnHandle → stream
        ├── client.py
        │   ├── AppServerClient
        │   ├── subprocess.Popen (启动 codex app-server)
        │   └── JSON-RPC 通信
        └── generated/v2_all.py
            └── Pydantic 模型定义
```

### 5.3 外部进程交互

```
Python SDK 进程
    │
    ├── subprocess.Popen ──→ codex app-server --listen stdio://
    │                           │
    │   stdin  (JSON-RPC)  ←──┤
    │   stdout (JSON-RPC)  ──→│
    │   stderr (日志)      ──→│
    │
    └── 网络请求 (由 app-server 处理)
            │
            └── OpenAI API / ChatGPT 后端
```

### 5.4 引导机制详解

```python
# _bootstrap.py:34-47
def ensure_local_sdk_src() -> Path:
    """Add sdk/python/src to sys.path so examples run without installing."""
    sdk_python_dir = _SDK_PYTHON_DIR
    src_dir = sdk_python_dir / "src"
    package_dir = src_dir / "codex_app_server"
    if not package_dir.exists():
        raise RuntimeError(...)
    
    _ensure_runtime_dependencies(sdk_python_dir)
    
    src_str = str(src_dir)
    if src_str not in sys.path:
        sys.path.insert(0, src_str)
    return src_dir
```

**引导流程：**
1. 将 `sdk/python/src` 添加到 `sys.path`
2. 检查 pydantic 是否已安装
3. `runtime_config()` 确保 `codex-cli-bin` 运行时包已安装

---

## 6. 风险、边界与改进建议

### 6.1 已知限制与风险

#### 6.1.1 并发限制

```python
# client.py:288-296
class AppServerClient:
    def acquire_turn_consumer(self, turn_id: str) -> None:
        with self._turn_consumer_lock:
            if self._active_turn_consumer is not None:
                raise RuntimeError(
                    "Concurrent turn consumers are not yet supported..."
                )
            self._active_turn_consumer = turn_id
```

**风险：** 单个 `Codex` 实例同一时间只能有一个活跃的 Turn 消费者。尝试同时启动多个 `stream()` 或 `run()` 会抛出 `RuntimeError`。

#### 6.1.2 异常处理边界

```python
# sync.py 当前实现
try:
    user_input = input("you> ").strip()
except EOFError:
    break
```

**缺失处理：**
- `KeyboardInterrupt` (Ctrl+C) 未捕获，会导致堆栈跟踪输出
- 网络/API 错误未在循环内处理

#### 6.1.3 资源泄漏风险

```python
# 当前实现
turn = thread.turn(TextInput(user_input))
# ... stream 消费 ...
```

如果 `stream()` 消费被异常中断（如用户按 Ctrl+C），Turn 可能仍在服务器端运行，但客户端已失去对其的引用。

### 6.2 边界条件

| 边界条件 | 当前行为 | 潜在问题 |
|----------|----------|----------|
| 空输入 | `continue` 跳过 | 合理 |
| 仅空白字符输入 | `continue` 跳过 | 合理 |
| 超长输入 | 无限制直接发送 | 可能触发 API 限制 |
| 网络中断 | `TransportClosedError` | 需要重连逻辑 |
| 服务器过载 | 抛出 `ServerBusyError` | 示例中无重试处理 |

### 6.3 改进建议

#### 6.3.1 错误处理增强

```python
# 建议添加
try:
    user_input = input("you> ").strip()
except EOFError:
    break
except KeyboardInterrupt:
    print("\nUse /exit to quit.")
    continue
```

#### 6.3.2 信号处理与优雅关闭

```python
import signal

def signal_handler(sig, frame):
    print("\nReceived interrupt, closing...")
    codex.close()
    sys.exit(0)

signal.signal(signal.SIGINT, signal_handler)
```

#### 6.3.3 输入长度限制

```python
MAX_INPUT_LENGTH = 10000  # 或其他合理限制
if len(user_input) > MAX_INPUT_LENGTH:
    print(f"Input too long (max {MAX_INPUT_LENGTH} chars)")
    continue
```

#### 6.3.4 重试机制集成

```python
from codex_app_server import retry_on_overload

# 在循环中使用
result = retry_on_overload(
    lambda: thread.run(user_input),
    max_attempts=3
)
```

#### 6.3.5 会话持久化

当前示例每次启动都创建新 Thread，建议添加 Thread ID 保存/恢复功能：

```python
import json
import os

STATE_FILE = ".cli_mini_app_state.json"

def load_thread_id() -> str | None:
    if os.path.exists(STATE_FILE):
        with open(STATE_FILE) as f:
            return json.load(f).get("thread_id")
    return None

def save_thread_id(thread_id: str) -> None:
    with open(STATE_FILE, "w") as f:
        json.dump({"thread_id": thread_id}, f)
```

### 6.4 测试建议

| 测试场景 | 验证点 |
|----------|--------|
| 正常多轮对话 | 消息正确显示，Token 统计准确 |
| 流式中断 | Ctrl+C 后资源正确释放 |
| 空输入处理 | 不触发 API 调用 |
| 退出命令 | `/exit`, `/quit` 正确退出 |
| EOF 处理 | Ctrl+D 正确退出 |
| 长文本输入 | 边界行为符合预期 |
| 网络异常 | 错误信息清晰可读 |

### 6.5 性能考虑

| 方面 | 现状 | 建议 |
|------|------|------|
| 内存使用 | 流式处理，内存占用低 | 当前实现良好 |
| 响应延迟 | 首 token 延迟取决于模型 | 可添加 "typing..." 提示 |
| 连接复用 | 单连接复用多轮对话 | 当前实现良好 |
| 异步效率 | 使用线程池包装同步调用 | 未来可考虑原生异步实现 |

---

## 7. 附录

### 7.1 相关文件索引

| 文件路径 | 说明 |
|----------|------|
| `sdk/python/examples/11_cli_mini_app/sync.py` | 同步版本主文件 |
| `sdk/python/examples/11_cli_mini_app/async.py` | 异步版本主文件 |
| `sdk/python/examples/_bootstrap.py` | 示例引导工具 |
| `sdk/python/src/codex_app_server/__init__.py` | 公共 API 导出 |
| `sdk/python/src/codex_app_server/api.py` | 高层封装 (Codex, Thread, TurnHandle) |
| `sdk/python/src/codex_app_server/client.py` | 同步 JSON-RPC 客户端 |
| `sdk/python/src/codex_app_server/async_client.py` | 异步客户端包装 |
| `sdk/python/src/codex_app_server/_inputs.py` | 输入类型定义 |
| `sdk/python/src/codex_app_server/models.py` | 核心数据模型 |
| `sdk/python/src/codex_app_server/generated/v2_all.py` | 自动生成模型 |
| `sdk/python/docs/getting-started.md` | 快速入门文档 |
| `sdk/python/docs/api-reference.md` | API 参考文档 |

### 7.2 术语表

| 术语 | 说明 |
|------|------|
| Turn | 一次用户输入到 AI 响应的完整交互 |
| Thread | 多轮对话的上下文容器 |
| Stream | 服务器推送的实时事件流 |
| Notification | 服务器主动推送的消息 |
| JSON-RPC | 远程过程调用协议 |
| Token | AI 模型的文本处理单位 |
