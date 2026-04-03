# sdk/python/src/codex_app_server/api.py 研究文档

## 场景与职责

`api.py` 是 Codex Python SDK 的**高级 API 实现模块**，提供面向开发者的同步和异步编程接口。它是 SDK 的核心业务逻辑层，承担着：

1. **高级抽象封装**：将底层 JSON-RPC 客户端封装为易用的 `Codex`, `Thread`, `TurnHandle` 等类
2. **生命周期管理**：处理客户端初始化、连接建立和资源清理
3. **同步/异步双模式**：提供完全对等的同步 (`Codex`, `Thread`) 和异步 (`AsyncCodex`, `AsyncThread`) API
4. **输入处理**：集成输入类型转换，支持多种输入形式
5. **事件流管理**：处理 Turn 级别的事件流订阅和消费

## 功能点目的

### 1. 核心类层次

| 类 | 模式 | 职责 |
|-----|------|------|
| `Codex` | 同步 | SDK 主入口，管理线程生命周期 |
| `AsyncCodex` | 异步 | 异步版 SDK 主入口 |
| `Thread` | 同步 | 线程操作封装（run, turn, read 等） |
| `AsyncThread` | 异步 | 异步版线程操作封装 |
| `TurnHandle` | 同步 | Turn 流式操作句柄 |
| `AsyncTurnHandle` | 异步 | 异步版 Turn 操作句柄 |

### 2. 线程生命周期方法

**Codex/AsyncCodex 级别：**
- `thread_start()` - 创建新线程
- `thread_list()` - 列出线程（支持分页、筛选）
- `thread_resume()` - 恢复已有线程
- `thread_fork()` - 分叉线程
- `thread_archive()` / `thread_unarchive()` - 归档管理

**Thread/AsyncThread 级别：**
- `run()` - 执行完整 Turn（阻塞直到完成）
- `turn()` - 启动 Turn 返回句柄
- `read()` - 读取线程状态
- `set_name()` - 设置线程名称
- `compact()` - 压缩线程上下文

### 3. Turn 控制方法

**TurnHandle/AsyncTurnHandle：**
- `stream()` - 订阅事件流（迭代器/异步迭代器）
- `run()` - 等待 Turn 完成并返回结果
- `steer()` - 向运行中的 Turn 发送引导输入
- `interrupt()` - 中断 Turn 执行

### 4. 元数据与模型

- `metadata` 属性 - 获取服务器初始化信息
- `models()` - 获取可用模型列表

## 具体技术实现

### 初始化与验证

**同步 Codex 初始化：**
```python
def __init__(self, config: AppServerConfig | None = None) -> None:
    self._client = AppServerClient(config=config)
    try:
        self._client.start()
        self._init = self._validate_initialize(self._client.initialize())
    except Exception:
        self._client.close()
        raise
```

**异步 AsyncCodex 初始化（延迟初始化）：**
```python
def __init__(self, config: AppServerConfig | None = None) -> None:
    self._client = AsyncAppServerClient(config=config)
    self._init: InitializeResponse | None = None
    self._initialized = False
    self._init_lock = asyncio.Lock()

async def _ensure_initialized(self) -> None:
    if self._initialized:
        return
    async with self._init_lock:  # 并发安全
        if self._initialized:
            return
        # 执行初始化...
```

**User-Agent 解析：**
```python
@staticmethod
def _split_user_agent(user_agent: str) -> tuple[str | None, str | None]:
    raw = user_agent.strip()
    if not raw:
        return None, None
    if "/" in raw:
        name, version = raw.split("/", 1)
        return (name or None), (version or None)
    parts = raw.split(maxsplit=1)
    if len(parts) == 2:
        return parts[0], parts[1]
    return raw, None
```

### 线程方法生成模式

代码中包含 `BEGIN GENERATED` / `END GENERATED` 标记的代码块，说明这些方法是由代码生成工具自动生成的：

```python
# BEGIN GENERATED: Codex.flat_methods
def thread_start(self, *, approval_policy=..., model=..., ...) -> Thread:
    params = ThreadStartParams(...)
    started = self._client.thread_start(params)
    return Thread(self._client, started.thread.id)
# END GENERATED: Codex.flat_methods
```

生成逻辑确保：
- 参数名使用蛇形命名（snake_case）
- 可选参数使用关键字-only 形式
- 返回类型正确标注

### Turn 事件流实现

**同步流：**
```python
def stream(self) -> Iterator[Notification]:
    self._client.acquire_turn_consumer(self.id)  # 获取独占消费权
    try:
        while True:
            event = self._client.next_notification()
            yield event
            if (event.method == "turn/completed" 
                and event.payload.turn.id == self.id):
                break
    finally:
        self._client.release_turn_consumer(self.id)
```

**异步流：**
```python
async def stream(self) -> AsyncIterator[Notification]:
    await self._codex._ensure_initialized()
    self._codex._client.acquire_turn_consumer(self.id)
    try:
        while True:
            event = await self._codex._client.next_notification()
            yield event
            if (...):
                break
    finally:
        self._codex._client.release_turn_consumer(self.id)
```

**关键设计：**
- `acquire_turn_consumer` / `release_turn_consumer` 确保同一时间只有一个消费者
- 不支持并发 Turn 流（实验性 SDK 限制）
- 使用 `try/finally` 确保资源释放

### Run 方法实现

**同步 Thread.run：**
```python
def run(self, input: RunInput, *, ...) -> RunResult:
    turn = self.turn(_normalize_run_input(input), ...)
    stream = turn.stream()
    try:
        return _collect_run_result(stream, turn_id=turn.id)
    finally:
        stream.close()
```

**流程：**
1. 规范化输入（字符串 → TextInput）
2. 创建 Turn
3. 订阅事件流
4. 收集结果
5. 确保流关闭

## 关键代码路径与文件引用

### 模块依赖图

```
api.py
├── async_client.py          # AsyncAppServerClient
├── client.py                # AppServerClient, AppServerConfig
├── generated.v2_all         # 生成模型（参数、响应、枚举）
├── models.py                # InitializeResponse, Notification
├── _inputs.py               # 输入类型和转换函数
│   ├── TextInput, ImageInput, ...
│   ├── _normalize_run_input
│   └── _to_wire_input
└── _run.py                  # 结果收集函数
    ├── _collect_run_result
    └── _collect_async_run_result
```

### 调用链示例

**完整调用链（同步）：**
```
用户代码: Codex().thread_start().run("hello")
    │
    ├── Codex.__init__()
    │   ├── AppServerClient.__init__()
    │   ├── AppServerClient.start()  # 启动子进程
    │   └── initialize()             # JSON-RPC 握手
    │
    ├── Codex.thread_start()
    │   ├── ThreadStartParams(...)   # 构建参数
    │   ├── AppServerClient.thread_start()  # RPC 调用
    │   └── Thread(...)              # 返回 Thread 对象
    │
    └── Thread.run("hello")
        ├── _normalize_run_input()   # "hello" → TextInput
        ├── Thread.turn()
        │   ├── _to_wire_input()     # 转换为 JSON
        │   ├── AppServerClient.turn_start()  # RPC
        │   └── TurnHandle(...)      # 返回句柄
        ├── TurnHandle.stream()
        │   └── 订阅通知流
        └── _collect_run_result()    # 收集并返回 RunResult
```

## 依赖与外部交互

### 直接依赖

| 模块 | 导入符号 | 用途 |
|-----|---------|------|
| `.async_client` | `AsyncAppServerClient` | 异步底层客户端 |
| `.client` | `AppServerClient`, `AppServerConfig` | 同步底层客户端+配置 |
| `.generated.v2_all` | ~30 个生成模型 | 参数、响应、枚举类型 |
| `.models` | `InitializeResponse`, `JsonObject`, `Notification`, `ServerInfo` | 核心数据模型 |
| `._inputs` | 输入类型和转换函数 | 输入处理 |
| `._run` | 结果收集函数 | Run 方法实现 |

### 外部包依赖

- `asyncio`：异步 API 实现
- `pydantic`：通过生成模型间接使用

## 风险、边界与改进建议

### 当前风险

1. **并发限制**：`acquire_turn_consumer` 限制同一时间只能有一个活跃的 Turn 流，这可能成为性能瓶颈
2. **资源泄漏风险**：虽然使用了 `try/finally`，但在某些异常路径下可能仍有泄漏
3. **初始化失败处理**：同步版本在 `__init__` 中执行 I/O，不符合 Python 最佳实践
4. **代码生成依赖**：大量重复代码依赖生成工具，手动修改容易出错

### 边界情况

1. **重复关闭**：`close()` 方法被多次调用是安全的（有 `if self._proc is not None` 检查）
2. **未初始化访问**：`AsyncCodex.metadata` 在未初始化时会抛出明确的错误信息
3. **并发初始化**：`AsyncCodex` 使用 `asyncio.Lock` 确保并发安全
4. **空输入处理**：`Thread.run()` 接受空字符串，透传给服务器处理

### 改进建议

1. **分离初始化和连接**：
   ```python
   # 当前（问题）
   codex = Codex()  # 立即执行 I/O
   
   # 建议
   codex = Codex()
   codex.connect()  # 显式连接
   ```

2. **支持并发 Turn 流**：
   移除 `acquire_turn_consumer` 限制，使用事件多路复用：
   ```python
   # 内部使用 turn_id 过滤，而非全局锁
   def next_notification_for_turn(self, turn_id: str) -> Notification:
       while True:
           event = self.next_notification()
           if event.turn_id == turn_id:
               return event
   ```

3. **添加上下文管理器支持**：
   ```python
   # 已支持，但可以改进错误处理
   with Codex() as codex:
       # 如果初始化失败，自动清理
       pass
   ```

4. **流式结果回调**：
   ```python
   def run_with_callback(
       self,
       input: RunInput,
       *,
       on_delta: Callable[[str], None] | None = None,
       on_item: Callable[[ThreadItem], None] | None = None,
   ) -> RunResult:
       # 支持实时处理事件，而非收集完再返回
   ```

5. **类型安全改进**：
   - 使用 `typing.Self`（Python 3.11+）改进返回类型
   - 添加 `@overload` 支持更精确的类型推断

6. **性能优化**：
   - 考虑使用 `__slots__` 减少内存占用
   - 缓存 `Thread` 对象避免重复创建

### 测试覆盖

相关测试文件：
- `test_public_api_signatures.py`：验证公共 API 签名
- `test_public_api_runtime_behavior.py`：验证运行时行为（初始化、流、并发）
- `test_client_rpc_methods.py`：验证底层 RPC 调用

关键测试场景：
- 初始化失败时的资源清理
- 并发初始化只执行一次
- Turn 流拒绝第二个消费者
- 字符串输入自动转换
- 多消息场景下的回复选择
