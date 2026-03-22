# SDK Python Examples 深度研究文档

## 1. 场景与职责

### 1.1 定位与目标

`sdk/python/examples` 是 Codex Python SDK 的官方示例集合，承担以下核心职责：

1. **功能演示**：展示 SDK 所有公共 API 的使用方式
2. **快速入门**：为新用户提供可运行的代码模板
3. **同步/异步对比**：每个示例同时提供 sync.py 和 async.py 版本
4. **集成测试参考**：示例代码可作为集成测试的蓝本
5. **最佳实践传播**：展示错误处理、重试模式、流式处理等生产级模式

### 1.2 使用场景

| 场景 | 对应示例 |
|------|----------|
| 首次体验 SDK | 01_quickstart_constructor |
| 理解 Turn 完整输出 | 02_turn_run |
| 学习流式事件处理 | 03_turn_stream_events |
| 模型发现与选择 | 04_models_and_metadata, 13_model_select_and_turn_params |
| 线程生命周期管理 | 05_existing_thread, 06_thread_lifecycle_and_controls |
| 多模态输入 | 07_image_and_text, 08_local_image_and_text |
| 生产级错误处理 | 10_error_handling_and_retry |
| 交互式应用开发 | 11_cli_mini_app |
| 高级参数配置 | 12_turn_params_kitchen_sink |
| 实时控制操作 | 14_turn_controls |

### 1.3 架构位置

```
┌─────────────────────────────────────────────────────────────┐
│                    用户应用层                                │
│  (examples/11_cli_mini_app 等交互式应用)                     │
├─────────────────────────────────────────────────────────────┤
│                    示例层 (examples/)                        │
│  - 14个功能示例，每个含 sync.py + async.py                   │
│  - _bootstrap.py 提供共享工具函数                            │
├─────────────────────────────────────────────────────────────┤
│                    公共 API 层 (api.py)                      │
│  - Codex / AsyncCodex: 主入口类                              │
│  - Thread / AsyncThread: 线程操作封装                        │
│  - TurnHandle / AsyncTurnHandle: Turn 控制与流式处理         │
├─────────────────────────────────────────────────────────────┤
│                    客户端层 (client.py)                      │
│  - AppServerClient: 同步 JSON-RPC over stdio 客户端          │
│  - AsyncAppServerClient: 异步包装器 (线程卸载)               │
├─────────────────────────────────────────────────────────────┤
│                    运行时层 (codex-cli-bin)                  │
│  - Rust 实现的 codex app-server 子命令                       │
│  - 通过 stdio 传输 JSON-RPC 2.0 协议                         │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. 功能点目的

### 2.1 示例分类与功能详解

#### 01_quickstart_constructor - 快速入门
- **目的**：验证环境配置，展示最基本的 SDK 使用流程
- **核心流程**：初始化 Codex → 创建线程 → 运行 Turn → 获取结果
- **关键类**：`Codex`, `AsyncCodex`, `AppServerConfig`

#### 02_turn_run - Turn 完整输出检查
- **目的**：展示如何访问 Turn 的完整元数据（status、error、items）
- **核心流程**：`thread.turn().run()` → 返回 `AppServerTurn` 对象
- **关键方法**：`thread.read(include_turns=True)` 获取持久化数据

#### 03_turn_stream_events - 流式事件处理
- **目的**：展示实时流式输出（打字机效果）
- **核心流程**：`turn.stream()` → 迭代 `Notification` 事件
- **关键事件**：
  - `turn/started`: Turn 开始
  - `item/agentMessage/delta`: 助手消息增量
  - `turn/completed`: Turn 完成

#### 04_models_and_metadata - 模型发现
- **目的**：展示如何获取可用模型列表
- **核心方法**：`codex.models(include_hidden=True)`
- **返回类型**：`ModelListResponse` 包含模型 ID、能力、支持的推理强度等

#### 05_existing_thread - 线程恢复
- **目的**：展示如何通过 ID 恢复已有线程
- **核心方法**：`codex.thread_resume(thread_id)`
- **场景**：持久化对话历史，跨会话恢复上下文

#### 06_thread_lifecycle_and_controls - 线程生命周期
- **目的**：完整展示线程 CRUD 操作
- **涵盖操作**：
  - `thread_start`: 创建
  - `thread_resume`: 恢复
  - `thread_fork`: 分叉（创建分支）
  - `thread_archive/unarchive`: 归档/解归档
  - `thread_list`: 列表查询（支持分页）
  - `thread_set_name`: 重命名
  - `thread_compact`: 压缩上下文

#### 07_image_and_text / 08_local_image_and_text - 多模态输入
- **目的**：展示图文混合输入
- **输入类型**：
  - `ImageInput(url)`: 远程图片 URL
  - `LocalImageInput(path)`: 本地图片路径
- **技术细节**：`_to_wire_input()` 将输入转换为 wire 格式

#### 09_async_parity - 同步/异步等价性验证
- **目的**：验证同步 API 的完整功能覆盖
- **特点**：仅 sync.py，展示与异步示例等价的功能

#### 10_error_handling_and_retry - 错误处理与重试
- **目的**：展示生产级错误处理模式
- **核心组件**：
  - `retry_on_overload()`: 指数退避重试
  - `ServerBusyError`: 服务器过载错误
  - `JsonRpcError`: JSON-RPC 错误基类
  - `is_retryable_error()`: 可重试错误判断

#### 11_cli_mini_app - 交互式 CLI 应用
- **目的**：展示如何构建完整的交互式应用
- **功能**：
  - 用户输入循环
  - 实时流式输出
  - Token 使用量统计展示
  - 状态与错误处理

#### 12_turn_params_kitchen_sink - 高级参数配置
- **目的**：展示所有 Turn 级参数的使用
- **涵盖参数**：
  - `approval_policy`: 审批策略（never/on-failure/on-request/untrusted）
  - `output_schema`: JSON Schema 结构化输出
  - `personality`: 个性设置（pragmatic/...）
  - `summary`: 推理摘要级别

#### 13_model_select_and_turn_params - 动态模型选择
- **目的**：展示运行时模型发现与选择逻辑
- **核心逻辑**：
  - 遍历可用模型
  - 选择最高能力模型
  - 选择最高支持的 reasoning effort
  - 动态应用模型参数

#### 14_turn_controls - Turn 实时控制
- **目的**：展示 Turn 运行时的控制操作
- **核心操作**：
  - `steer()`: 引导/修正当前 Turn
  - `interrupt()`: 中断当前 Turn

---

## 3. 具体技术实现

### 3.1 关键数据结构与协议

#### 3.1.1 JSON-RPC 2.0 over stdio

```python
# 请求格式
{
    "id": "uuid",
    "method": "thread/start",
    "params": {...}
}

# 响应格式
{
    "id": "uuid",
    "result": {...}
}

# 通知格式（服务器→客户端）
{
    "method": "item/agentMessage/delta",
    "params": {...}
}

# 服务器请求格式（需响应）
{
    "id": "uuid",
    "method": "item/commandExecution/requestApproval",
    "params": {...}
}
```

#### 3.1.2 核心数据模型

**输入类型**（`_inputs.py`）:
```python
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
RunInput = Input | str
```

**Wire 格式转换**:
```python
def _to_wire_item(item: InputItem) -> JsonObject:
    if isinstance(item, TextInput):
        return {"type": "text", "text": item.text}
    if isinstance(item, ImageInput):
        return {"type": "image", "url": item.url}
    if isinstance(item, LocalImageInput):
        return {"type": "localImage", "path": item.path}
    # ...
```

**通知类型**（`models.py`）:
```python
@dataclass(slots=True)
class Notification:
    method: str
    payload: NotificationPayload  # 联合类型，包含 30+ 种具体通知
```

### 3.2 关键流程实现

#### 3.2.1 Turn 流式处理流程

```python
# sync 版本 (TurnHandle.stream)
def stream(self) -> Iterator[Notification]:
    self._client.acquire_turn_consumer(self.id)  # 获取独占消费权
    try:
        while True:
            event = self._client.next_notification()
            yield event
            if (event.method == "turn/completed" and 
                event.payload.turn.id == self.id):
                break
    finally:
        self._client.release_turn_consumer(self.id)

# async 版本 (AsyncTurnHandle.stream)
async def stream(self) -> AsyncIterator[Notification]:
    await self._codex._ensure_initialized()
    self._codex._client.acquire_turn_consumer(self.id)
    try:
        while True:
            event = await self._codex._client.next_notification()
            yield event
            # ... 完成检测
    finally:
        self._codex._client.release_turn_consumer(self.id)
```

#### 3.2.2 同步客户端实现

```python
class AppServerClient:
    def __init__(self, config: AppServerConfig | None = None, ...):
        self.config = config or AppServerConfig()
        self._proc: subprocess.Popen[str] | None = None
        self._lock = threading.Lock()  # 写入锁
        self._turn_consumer_lock = threading.Lock()  # Turn 消费锁
        self._pending_notifications: deque[Notification] = deque()
        self._stderr_lines: deque[str] = deque(maxlen=400)

    def start(self) -> None:
        # 启动 codex app-server --listen stdio://
        self._proc = subprocess.Popen(
            args,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            ...
        )
        self._start_stderr_drain_thread()

    def _write_message(self, payload: JsonObject) -> None:
        with self._lock:
            self._proc.stdin.write(json.dumps(payload) + "\n")
            self._proc.stdin.flush()

    def _read_message(self) -> dict[str, JsonValue]:
        line = self._proc.stdout.readline()
        return json.loads(line)
```

#### 3.2.3 异步客户端实现（线程卸载模式）

```python
class AsyncAppServerClient:
    """Async wrapper around AppServerClient using thread offloading."""
    
    def __init__(self, config: AppServerConfig | None = None):
        self._sync = AppServerClient(config=config)
        self._transport_lock = asyncio.Lock()  # 单传输不能多线程并发读

    async def _call_sync(self, fn, *args, **kwargs):
        async with self._transport_lock:
            return await asyncio.to_thread(fn, *args, **kwargs)

    async def request(self, method, params, *, response_model):
        return await self._call_sync(
            self._sync.request, method, params, response_model=response_model
        )
```

**设计决策**：使用线程卸载而非原生异步，因为：
1. 底层传输是 stdio，单连接无法真正并发
2. 避免维护两套 JSON-RPC 协议实现
3. `asyncio.to_thread()` 将阻塞 IO  offload 到线程池

#### 3.2.4 重试机制实现

```python
def retry_on_overload(op, *, max_attempts=3, initial_delay_s=0.25, 
                      max_delay_s=2.0, jitter_ratio=0.2):
    delay = initial_delay_s
    attempt = 0
    while True:
        attempt += 1
        try:
            return op()
        except Exception as exc:
            if attempt >= max_attempts:
                raise
            if not is_retryable_error(exc):  # 仅重试特定错误
                raise
            
            # 指数退避 + 抖动
            jitter = delay * jitter_ratio
            sleep_for = min(max_delay_s, delay) + random.uniform(-jitter, jitter)
            time.sleep(sleep_for)
            delay = min(max_delay_s, delay * 2)
```

### 3.3 运行时管理

#### 3.3.1 自动运行时安装（`_runtime_setup.py`）

```python
PINNED_RUNTIME_VERSION = "0.116.0-alpha.1"

def ensure_runtime_package_installed(python_executable, sdk_python_dir):
    # 1. 检查已安装版本
    installed = _installed_runtime_version(python_executable)
    if installed == requested_version:
        return
    
    # 2. 下载对应平台 Release
    archive = _download_release_archive(version, temp_root)
    binary = _extract_runtime_binary(archive, temp_root)
    
    # 3. 打包为 Python 包并安装
    staged = _stage_runtime_package(sdk_python_dir, version, binary, staging_dir)
    _install_runtime_package(python_executable, staged)
```

**平台支持**：
- macOS: aarch64/x86_64
- Linux: aarch64/x86_64 (musl)
- Windows: aarch64/x86_64

#### 3.3.2 引导机制（`_bootstrap.py`）

```python
def ensure_local_sdk_src() -> Path:
    """Add sdk/python/src to sys.path so examples run without installing."""
    sdk_python_dir = _SDK_PYTHON_DIR
    src_dir = sdk_python_dir / "src"
    # 动态修改 sys.path，支持源码直接运行
    if src_str not in sys.path:
        sys.path.insert(0, src_str)
    return src_dir

def runtime_config():
    """Return an example-friendly AppServerConfig."""
    from codex_app_server import AppServerConfig
    ensure_runtime_package_installed(sys.executable, _SDK_PYTHON_DIR)
    return AppServerConfig()
```

---

## 4. 关键代码路径与文件引用

### 4.1 示例目录结构

```
sdk/python/examples/
├── README.md                          # 示例索引与运行说明
├── _bootstrap.py                      # 共享引导工具
├── 01_quickstart_constructor/         # 快速入门
│   ├── sync.py
│   └── async.py
├── 02_turn_run/                       # Turn 完整输出
│   ├── sync.py
│   └── async.py
├── 03_turn_stream_events/             # 流式事件
│   ├── sync.py
│   └── async.py
├── 04_models_and_metadata/            # 模型发现
│   ├── sync.py
│   └── async.py
├── 05_existing_thread/                # 线程恢复
│   ├── sync.py
│   └── async.py
├── 06_thread_lifecycle_and_controls/  # 线程生命周期
│   ├── sync.py
│   └── async.py
├── 07_image_and_text/                 # 远程图片
│   ├── sync.py
│   └── async.py
├── 08_local_image_and_text/           # 本地图片
│   ├── sync.py
│   └── async.py
├── 09_async_parity/                   # 同步等价性
│   └── sync.py
├── 10_error_handling_and_retry/       # 错误处理
│   ├── sync.py
│   └── async.py
├── 11_cli_mini_app/                   # 交互式 CLI
│   ├── sync.py
│   └── async.py
├── 12_turn_params_kitchen_sink/       # 高级参数
│   ├── sync.py
│   └── async.py
├── 13_model_select_and_turn_params/   # 动态模型选择
│   ├── sync.py
│   └── async.py
└── 14_turn_controls/                  # Turn 控制
    ├── sync.py
    └── async.py
```

### 4.2 SDK 源码关键文件

```
sdk/python/src/codex_app_server/
├── __init__.py                        # 公共 API 导出
├── api.py                             # 高级 API (Codex, Thread, TurnHandle)
├── client.py                          # 同步 JSON-RPC 客户端
├── async_client.py                    # 异步客户端包装器
├── models.py                          # 数据模型与通知类型
├── errors.py                          # 异常层次结构
├── retry.py                           # 重试逻辑
├── _inputs.py                         # 输入类型定义
├── _run.py                            # RunResult 收集逻辑
└── generated/
    ├── v2_all.py                      # 生成的 Pydantic 模型（1000+ 行）
    └── notification_registry.py       # 通知类型注册表
```

### 4.3 核心调用链

#### Turn 执行完整链路

```
示例代码
    │
    ▼
Codex.thread_start() ─────────────────────────────────────────────┐
    │                                                              │
    ▼                                                              │
AppServerClient.thread_start() ───────────────────────────────────┤
    │                                                              │
    ▼                                                              │
_request_raw("thread/start", params)                              │
    │                                                              │
    ▼                                                              │
JSON-RPC over stdio ──────────────────────────────────────────────┤
    │                                                              │
    ▼                                                              │
codex app-server (Rust)                                           │
    │                                                              │
    ▼                                                              │
Thread.turn() / AsyncThread.turn() ◄──────────────────────────────┘
    │
    ▼
TurnHandle.stream() / AsyncTurnHandle.stream()
    │
    ▼
AppServerClient.next_notification()
    │
    ▼
_parse_notification() → Notification 对象
```

---

## 5. 依赖与外部交互

### 5.1 依赖关系

#### Python 依赖
```
pydantic >= 2.0          # 数据验证与序列化
codex-cli-bin            # Rust 运行时二进制（自动安装）
```

#### 运行时依赖
```
codex app-server         # Rust 实现的 JSON-RPC 服务器
  ├── OpenAI API         # LLM 推理服务
  ├── Seatbelt/sandbox   # 代码执行沙箱（可选）
  └── stdio 传输         # JSON-RPC 通信通道
```

### 5.2 外部交互

#### 5.2.1 GitHub Release API

**用途**：自动下载 codex-cli-bin 运行时

**交互点**：`_runtime_setup.py`
- 获取 Release 元数据：`GET /repos/openai/codex/releases/tags/rust-v{version}`
- 下载平台特定二进制：`GET /releases/download/rust-v{version}/{asset}`
- 认证：支持 `GH_TOKEN` / `GITHUB_TOKEN` 环境变量

#### 5.2.2 codex app-server 进程

**启动命令**：
```bash
codex app-server --listen stdio://
```

**协议**：JSON-RPC 2.0 over stdio（行分隔）

**生命周期**：
1. `AppServerClient.start()` 启动子进程
2. `initialize` 握手交换能力信息
3. 双向 JSON-RPC 通信
4. `close()` 发送终止信号，清理资源

#### 5.2.3 模型服务（间接）

通过 codex app-server 间接调用：
- OpenAI Responses API
- 可能的第三方模型提供商

### 5.3 配置覆盖机制

```python
AppServerConfig(
    codex_bin=None,              # 自定义二进制路径
    launch_args_override=None,   # 完全自定义启动参数
    config_overrides=(),         # --config key=value 覆盖
    cwd=None,                    # 工作目录
    env=None,                    # 环境变量
    client_name="codex_python_sdk",
    client_version="0.2.0",
    experimental_api=True,       # 启用实验性 API
)
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 并发限制

**风险**：当前实现不支持并发 Turn 消费

**代码体现**：
```python
def acquire_turn_consumer(self, turn_id: str) -> None:
    with self._turn_consumer_lock:
        if self._active_turn_consumer is not None:
            raise RuntimeError(
                "Concurrent turn consumers are not yet supported..."
            )
        self._active_turn_consumer = turn_id
```

**影响**：无法同时流式处理多个 Turn

#### 6.1.2 线程安全

**风险**：`AsyncAppServerClient` 使用单锁保护整个传输

**代码体现**：
```python
async def _call_sync(self, fn, *args, **kwargs):
    async with self._transport_lock:  # 全局锁
        return await asyncio.to_thread(fn, *args, **kwargs)
```

**影响**：高并发场景下可能成为瓶颈

#### 6.1.3 运行时版本锁定

**风险**：硬编码的 `PINNED_RUNTIME_VERSION` 可能过时

**代码体现**：
```python
PINNED_RUNTIME_VERSION = "0.116.0-alpha.1"  # 需要手动更新
```

**影响**：新功能或 bug 修复无法自动获取

#### 6.1.4 错误处理边界

**风险**：未知通知类型降级为 `UnknownNotification`，可能丢失信息

**代码体现**：
```python
def _coerce_notification(self, method: str, params: object) -> Notification:
    model = NOTIFICATION_MODELS.get(method)
    if model is None:
        return Notification(method=method, payload=UnknownNotification(...))
    try:
        payload = model.model_validate(params_dict)
    except Exception:  # 捕获所有异常
        return Notification(method=method, payload=UnknownNotification(...))
```

### 6.2 边界条件

| 边界条件 | 行为 |
|----------|------|
| 空输入字符串 | 转换为 `[{"type": "text", "text": ""}]` |
| 单输入项 | 自动包装为列表 |
| 服务器进程崩溃 | `TransportClosedError` |
| JSON 解析错误 | `AppServerError` |
| 超时 | 依赖底层 TCP/HTTP 超时 |
| 超大图片 | 受限于模型 API 限制 |
| 并发 Turn | 抛出 `RuntimeError` |

### 6.3 改进建议

#### 6.3.1 架构层面

1. **原生异步实现**
   - 当前：线程卸载模式
   - 建议：考虑使用 `asyncio.subprocess` 实现真正的异步传输
   - 收益：减少线程开销，提高并发效率

2. **并发 Turn 支持**
   - 当前：单 Turn 消费锁
   - 建议：实现 per-turn 事件多路复用
   - 收益：支持真正的多轮对话并行处理

3. **运行时版本管理**
   - 当前：硬编码版本号
   - 建议：支持版本范围约束（如 `>=0.116.0,<0.120.0`）
   - 收益：自动获取兼容的最新版本

#### 6.3.2 API 设计

1. **上下文管理器增强**
   ```python
   # 当前
   with Codex() as codex:
       thread = codex.thread_start()
   
   # 建议：支持异步上下文传播
   async with AsyncCodex() as codex:
       async with codex.thread() as thread:  # 自动清理
           ...
   ```

2. **流式 API 简化**
   ```python
   # 当前
   for event in turn.stream():
       if event.method == "item/agentMessage/delta":
           print(event.payload.delta)
   
   # 建议：提供高层封装
   async for delta in turn.stream_text_deltas():
       print(delta)
   ```

3. **类型安全增强**
   - 当前：部分 `JsonObject` 类型过于宽泛
   - 建议：为常用配置结构生成 TypedDict

#### 6.3.3 可观测性

1. **结构化日志**
   - 当前：stderr 简单收集
   - 建议：集成 Python logging，支持结构化输出

2. **性能指标**
   - 建议：暴露请求延迟、重试次数等指标

3. **调试工具**
   - 建议：提供 `CODEX_SDK_DEBUG` 环境变量启用详细协议日志

#### 6.3.4 测试与文档

1. **示例测试自动化**
   - 当前：示例代码无自动化测试
   - 建议：添加示例代码的冒烟测试（使用 mock server）

2. **交互式文档**
   - 建议：将示例集成到 Jupyter Notebook，支持在线运行

### 6.4 生产环境检查清单

- [ ] 配置适当的重试策略（`retry_on_overload`）
- [ ] 处理 `TransportClosedError` 异常
- [ ] 设置合理的超时（当前依赖底层）
- [ ] 监控 Token 使用量（`ThreadTokenUsageUpdatedNotification`）
- [ ] 实现审批处理器（`approval_handler`）控制敏感操作
- [ ] 考虑线程/异步模型的并发限制
- [ ] 验证运行时版本兼容性
- [ ] 配置适当的日志级别

---

## 附录：关键代码片段索引

| 功能 | 文件路径 | 行号范围 |
|------|----------|----------|
| 同步客户端核心 | `sdk/python/src/codex_app_server/client.py` | 136-540 |
| 异步客户端包装 | `sdk/python/src/codex_app_server/async_client.py` | 39-208 |
| 高级 API | `sdk/python/src/codex_app_server/api.py` | 69-735 |
| 输入类型定义 | `sdk/python/src/codex_app_server/_inputs.py` | 1-63 |
| 结果收集 | `sdk/python/src/codex_app_server/_run.py` | 1-112 |
| 错误处理 | `sdk/python/src/codex_app_server/errors.py` | 1-125 |
| 重试逻辑 | `sdk/python/src/codex_app_server/retry.py` | 1-41 |
| 运行时安装 | `sdk/python/_runtime_setup.py` | 1-359 |
| 示例引导 | `sdk/python/examples/_bootstrap.py` | 1-152 |
| 生成模型 | `sdk/python/src/codex_app_server/generated/v2_all.py` | 1-1000+ |
