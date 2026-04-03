# sdk/python/src/codex_app_server/client.py 研究文档

## 场景与职责

`client.py` 是 Codex Python SDK 的**同步 JSON-RPC 客户端实现**，负责与 Codex CLI 的 `app-server` 子进程进行通信。它是整个 SDK 的底层核心，承担着：

1. **进程管理**：启动、监控和终止 Codex CLI 子进程
2. **JSON-RPC 协议实现**：处理请求/响应、通知的序列化和反序列化
3. **stdio 传输**：通过标准输入输出与子进程通信
4. **线程安全**：确保多线程环境下的安全访问
5. **错误映射**：将 JSON-RPC 错误映射为 Python 异常

## 功能点目的

### 1. AppServerConfig 配置类

```python
@dataclass(slots=True)
class AppServerConfig:
    codex_bin: str | None = None           # 自定义 Codex 二进制路径
    launch_args_override: tuple[str, ...] | None = None  # 完全自定义启动参数
    config_overrides: tuple[str, ...] = ()  # --config 覆盖
    cwd: str | None = None                  # 工作目录
    env: dict[str, str] | None = None       # 额外环境变量
    client_name: str = "codex_python_sdk"   # 客户端标识
    client_title: str = "Codex Python SDK"
    client_version: str = "0.2.0"
    experimental_api: bool = True           # 启用实验性 API
```

### 2. AppServerClient 核心类

**状态管理：**
```python
class AppServerClient:
    def __init__(self, config: AppServerConfig | None = None, ...) -> None:
        self.config = config or AppServerConfig()
        self._proc: subprocess.Popen[str] | None = None  # 子进程
        self._lock = threading.Lock()                    # 写入锁
        self._turn_consumer_lock = threading.Lock()      # Turn 消费者锁
        self._active_turn_consumer: str | None = None    # 当前活跃消费者
        self._pending_notifications: deque[Notification] = deque()  # 待处理通知
        self._stderr_lines: deque[str] = deque(maxlen=400)  # stderr 缓冲
```

### 3. 进程生命周期

**启动流程：**
```python
def start(self) -> None:
    if self._proc is not None:
        return  # 已启动
    
    # 构建启动参数
    if self.config.launch_args_override:
        args = list(self.config.launch_args_override)
    else:
        codex_bin = _resolve_codex_bin(self.config)
        args = [str(codex_bin)]
        for kv in self.config.config_overrides:
            args.extend(["--config", kv])
        args.extend(["app-server", "--listen", "stdio://"])
    
    # 启动子进程
    self._proc = subprocess.Popen(
        args,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        cwd=self.config.cwd,
        env=env,
        bufsize=1,  # 行缓冲
    )
    
    self._start_stderr_drain_thread()
```

**关闭流程：**
```python
def close(self) -> None:
    if self._proc is None:
        return
    
    proc = self._proc
    self._proc = None
    self._active_turn_consumer = None
    
    if proc.stdin:
        proc.stdin.close()
    try:
        proc.terminate()
        proc.wait(timeout=2)
    except Exception:
        proc.kill()  # 强制终止
```

### 4. JSON-RPC 协议实现

**请求发送：**
```python
def _write_message(self, payload: JsonObject) -> None:
    if self._proc is None or self._proc.stdin is None:
        raise TransportClosedError("app-server is not running")
    with self._lock:
        self._proc.stdin.write(json.dumps(payload) + "\n")
        self._proc.stdin.flush()
```

**响应读取：**
```python
def _read_message(self) -> dict[str, JsonValue]:
    if self._proc is None or self._proc.stdout is None:
        raise TransportClosedError("app-server is not running")
    
    line = self._proc.stdout.readline()
    if not line:
        raise TransportClosedError(
            f"app-server closed stdout. stderr_tail={self._stderr_tail()[:2000]}"
        )
    
    message = json.loads(line)
    if not isinstance(message, dict):
        raise AppServerError(f"Invalid JSON-RPC payload: {message!r}")
    return message
```

### 5. 请求/响应处理

**同步请求：**
```python
def _request_raw(self, method: str, params: JsonObject | None = None) -> JsonValue:
    request_id = str(uuid.uuid4())
    self._write_message({"id": request_id, "method": method, "params": params or {}})
    
    while True:
        msg = self._read_message()
        
        # 处理服务器请求（如 approval 请求）
        if "method" in msg and "id" in msg:
            response = self._handle_server_request(msg)
            self._write_message({"id": msg["id"], "result": response})
            continue
        
        # 缓存通知
        if "method" in msg and "id" not in msg:
            self._pending_notifications.append(...)
            continue
        
        # 匹配响应
        if msg.get("id") != request_id:
            continue
        
        if "error" in msg:
            raise map_jsonrpc_error(...)  # 映射错误
        
        return msg.get("result")
```

### 6. 二进制解析

```python
def _installed_codex_path() -> Path:
    try:
        from codex_cli_bin import bundled_codex_path
    except ImportError as exc:
        raise FileNotFoundError(
            "Unable to locate the pinned Codex runtime. Install the published SDK build "
            f"with its {RUNTIME_PKG_NAME} dependency, or set AppServerConfig.codex_bin "
            "explicitly."
        ) from exc
    return bundled_codex_path()

def resolve_codex_bin(config: "AppServerConfig", ops: CodexBinResolverOps) -> Path:
    if config.codex_bin is not None:
        codex_bin = Path(config.codex_bin)
        if not ops.path_exists(codex_bin):
            raise FileNotFoundError(...)
        return codex_bin
    return ops.installed_codex_path()
```

## 具体技术实现

### stderr 处理

```python
def _start_stderr_drain_thread(self) -> None:
    def _drain() -> None:
        stderr = self._proc.stderr
        for line in stderr:
            self._stderr_lines.append(line.rstrip("\n"))
    
    self._stderr_thread = threading.Thread(target=_drain, daemon=True)
    self._stderr_thread.start()

def _stderr_tail(self, limit: int = 40) -> str:
    return "\n".join(list(self._stderr_lines)[-limit:])
```

**设计考量：**
- 使用守护线程持续读取 stderr，防止管道填满导致死锁
- 环形缓冲区（`maxlen=400`）限制内存使用
- 错误报告时包含最近的 stderr 输出

### Approval 处理

```python
def _default_approval_handler(
    self, method: str, params: JsonObject | None
) -> JsonObject:
    if method == "item/commandExecution/requestApproval":
        return {"decision": "accept"}
    if method == "item/fileChange/requestApproval":
        return {"decision": "accept"}
    return {}
```

默认自动接受所有 approval 请求，用户可通过 `approval_handler` 参数自定义。

### Turn 消费者管理

```python
def acquire_turn_consumer(self, turn_id: str) -> None:
    with self._turn_consumer_lock:
        if self._active_turn_consumer is not None:
            raise RuntimeError(
                "Concurrent turn consumers are not yet supported..."
            )
        self._active_turn_consumer = turn_id

def release_turn_consumer(self, turn_id: str) -> None:
    with self._turn_consumer_lock:
        if self._active_turn_consumer == turn_id:
            self._active_turn_consumer = None
```

### 参数序列化

```python
def _params_dict(params: ...) -> JsonObject:
    if params is None:
        return {}
    if hasattr(params, "model_dump"):  # Pydantic v2
        dumped = params.model_dump(
            by_alias=True,      # 使用 camelCase 别名
            exclude_none=True,  # 排除 None 值
            mode="json",        # JSON 序列化模式
        )
        return dumped
    if isinstance(params, dict):
        return params
    raise TypeError(...)
```

## 关键代码路径与文件引用

### 模块依赖图

```
client.py
├── json                     # JSON 序列化
├── os                       # 环境变量
├── subprocess               # 子进程管理
├── threading                # 线程锁
├── uuid                     # 请求 ID 生成
├── collections.deque        # 队列
├── pathlib.Path             # 路径处理
├── pydantic.BaseModel       # 响应验证
├── errors.py                # 异常映射
├── generated.v2_all         # 生成响应模型
├── models.py                # 核心模型
└── retry.py                 # 重试逻辑
```

### 调用链示例

**初始化流程：**
```
AppServerClient.__init__(config)
    │
    ├── 存储配置
    ├── 初始化锁和队列
    └── approval_handler = 默认或自定义

AppServerClient.start()
    │
    ├── _resolve_codex_bin(config)
    │   └── 优先使用 config.codex_bin
    │   └── 或从 codex_cli_bin 包获取
    │
    ├── subprocess.Popen(...)  # 启动 app-server
    │
    └── _start_stderr_drain_thread()
```

**RPC 调用流程：**
```
thread_start(params)
    │
    ├── _params_dict(params)  # Pydantic → dict
    │
    └── request("thread/start", payload, response_model=ThreadStartResponse)
        │
        ├── _request_raw("thread/start", payload)
        │   │
        │   ├── _write_message({id, method, params})  # 发送请求
        │   │
        │   └── while True:
        │       ├── _read_message()  # 读取响应
        │       │
        │       ├── 处理服务器请求 → _handle_server_request
        │       ├── 缓存通知 → _pending_notifications
        │       └── 匹配响应 ID → 返回结果
        │
        └── response_model.model_validate(result)  # Pydantic 验证
```

## 依赖与外部交互

### 直接依赖

| 模块 | 导入符号 | 用途 |
|-----|---------|------|
| `json` | `loads`, `dumps` | JSON-RPC 序列化 |
| `os` | `environ` | 环境变量处理 |
| `subprocess` | `Popen` | 子进程管理 |
| `threading` | `Lock`, `Thread` | 并发控制 |
| `uuid` | `uuid4` | 请求 ID 生成 |
| `collections` | `deque` | 队列数据结构 |
| `pathlib` | `Path` | 路径处理 |
| `pydantic` | `BaseModel` | 数据验证 |
| `.errors` | 异常类和映射函数 | 错误处理 |
| `.generated.v2_all` | 响应模型 | API 类型 |
| `.models` | 核心模型 | 数据结构 |
| `.retry` | `retry_on_overload` | 重试逻辑 |

### 外部依赖

- `codex_cli_bin`：可选依赖，提供捆绑的 Codex 二进制文件

## 风险、边界与改进建议

### 当前风险

1. **单进程限制**：每个 `AppServerClient` 实例启动一个独立的 Codex 进程，资源开销较大
2. **无连接池**：不支持连接复用，每个客户端独立维护连接
3. **进程僵死**：如果 Codex 进程异常退出，可能留下僵尸进程
4. **大消息处理**：JSON 消息在内存中处理，超大消息可能导致内存问题
5. **平台兼容性**：依赖 `codex_cli_bin` 包，可能不支持所有平台

### 边界情况

1. **重复启动**：`start()` 被多次调用时，第二次及以后直接返回（幂等）
2. **重复关闭**：`close()` 被多次调用是安全的
3. **空响应处理**：服务器返回空响应时，`_read_message` 抛出 `TransportClosedError`
4. **无效 JSON**：收到非 JSON 行时抛出 `AppServerError`
5. **并发请求**：由于 `_lock` 的存在，写操作是线程安全的，但读操作需要配合 `_request_raw` 的循环逻辑

### 改进建议

1. **健康检查**：
   ```python
   def is_healthy(self) -> bool:
       return self._proc is not None and self._proc.poll() is None
   ```

2. **自动重连**：
   ```python
   def request_with_retry(self, method, params, *, max_retries=3):
       for attempt in range(max_retries):
           try:
               return self.request(method, params)
           except TransportClosedError:
               if attempt < max_retries - 1:
                   self.start()  # 自动重启
   ```

3. **消息大小限制**：
   ```python
   def _write_message(self, payload: JsonObject) -> None:
       data = json.dumps(payload)
       if len(data) > MAX_MESSAGE_SIZE:
           raise MessageTooLargeError(f"Message exceeds {MAX_MESSAGE_SIZE} bytes")
       ...
   ```

4. **异步原生支持**：
   当前 `AsyncAppServerClient` 使用线程卸载，可以实现原生异步：
   ```python
   class AsyncAppServerClientNative:
       async def start(self):
           self._proc = await asyncio.create_subprocess_exec(
               ..., stdin=PIPE, stdout=PIPE, stderr=PIPE
           )
   ```

5. **更好的错误上下文**：
   ```python
   class AppServerRpcError(Exception):
       def __init__(self, message, *, request_id, method, stderr_tail):
           super().__init__(message)
           self.request_id = request_id
           self.method = method
           self.stderr_tail = stderr_tail
   ```

6. **资源监控**：
   ```python
   def get_stats(self) -> ClientStats:
       return ClientStats(
           messages_sent=self._messages_sent,
           messages_received=self._messages_received,
           pending_notifications=len(self._pending_notifications),
           stderr_lines=len(self._stderr_lines),
       )
   ```

### 测试覆盖

相关测试文件：
- `test_client_rpc_methods.py`：RPC 方法调用测试
- `test_public_api_runtime_behavior.py`：运行时行为测试

关键测试场景：
- 参数序列化（snake_case → camelCase）
- 通知类型强制转换
- 未知通知回退
- 无效通知负载处理
