# sync.py 研究文档

## 场景与职责

`sync.py` 是 Codex Python SDK 的同步快速入门示例，位于 `sdk/python/examples/01_quickstart_constructor/` 目录。该文件展示了如何使用 `Codex` 类以同步方式与 Codex App Server 进行交互，适合不熟悉异步编程的开发者或简单的脚本场景。

核心职责：
- 演示同步上下文管理器 (`with`) 的正确使用方式
- 展示如何通过构造函数方式初始化同步 Codex 客户端
- 展示如何创建线程、发送消息并获取 AI 响应

## 功能点目的

### 1. 本地 SDK 源文件引导加载
```python
_EXAMPLES_ROOT = Path(__file__).resolve().parents[1]
if str(_EXAMPLES_ROOT) not in sys.path:
    sys.path.insert(0, str(_EXAMPLES_ROOT))
```
目的：允许示例脚本在不安装 SDK 包的情况下直接运行，通过修改 `sys.path` 将 `sdk/python/` 目录加入模块搜索路径。

### 2. 运行时环境准备
```python
from _bootstrap import (
    ensure_local_sdk_src,
    runtime_config,
    server_label,
)
ensure_local_sdk_src()
```
目的：
- `ensure_local_sdk_src()`: 确保本地 SDK 源文件 (`sdk/python/src/codex_app_server`) 可用，并检查依赖项 (pydantic)
- `runtime_config()`: 返回示例友好的 `AppServerConfig` 配置对象
- `server_label()`: 从元数据中提取服务器信息用于显示

### 3. 同步客户端初始化与使用
```python
with Codex(config=runtime_config()) as codex:
    print("Server:", server_label(codex.metadata))
```
目的：使用同步上下文管理器确保资源正确初始化和释放。

### 4. 线程创建与对话执行
```python
thread = codex.thread_start(model="gpt-5.4", config={"model_reasoning_effort": "high"})
result = thread.run("Say hello in one sentence.")
```
目的：
- 创建新线程，指定模型和推理强度配置
- 在线程上执行单轮对话，获取 AI 响应
- 输出响应内容和项目数量

## 具体技术实现

### 关键流程

1. **初始化流程**
   ```
   with Codex(config) as codex:
       ├── Codex.__init__(config)  # 创建 AppServerClient 并启动
       │   ├── AppServerClient.__init__(config)
       │   ├── AppServerClient.start()  # 启动子进程
       │   └── AppServerClient.initialize()  # JSON-RPC initialize
       ├── Codex.__enter__()  # 返回 self
       └── ...使用 codex...
   ```

2. **线程创建流程**
   ```
   codex.thread_start(model=..., config=...)
       ├── 构建 ThreadStartParams (Pydantic 模型)
       ├── AppServerClient.thread_start(params)
       │   ├── _params_dict(params)  # 序列化参数
       │   └── request("thread/start", params, response_model=ThreadStartResponse)
       │       ├── _request_raw("thread/start", params)
       │       │   ├── _write_message({"id": ..., "method": "thread/start", "params": ...})
       │       │   ├── _read_message()  # 等待响应
       │       │   └── 返回响应结果
       │       └── ThreadStartResponse.model_validate(result)
       └── 返回 Thread(client, thread_id)
   ```

3. **对话执行流程**
   ```
   thread.run("Say hello in one sentence.")
       ├── Thread.run(input)
       │   ├── _normalize_run_input(input)  # 字符串转为 TextInput
       │   ├── self.turn(input)  # 创建 turn
       │   │   ├── _to_wire_input(input)  # 转换为 wire 格式
       │   │   ├── AppServerClient.turn_start(thread_id, wire_input, params)
       │   │   │   └── request("turn/start", ...)
       │   │   └── 返回 TurnHandle(client, thread_id, turn_id)
       │   ├── turn.stream()  # 获取通知流迭代器
       │   │   ├── acquire_turn_consumer(turn_id)  # 获取消费者锁
       │   │   └── 生成器: while True 读取通知直到 turn/completed
       │   └── _collect_run_result(stream, turn_id)
       │       ├── 遍历通知流
       │       ├── 收集 ItemCompletedNotification -> items
       │       ├── 收集 ThreadTokenUsageUpdatedNotification -> usage
       │       └── 收到 TurnCompletedNotification -> 结束
       └── 返回 RunResult(final_response, items, usage)
   ```

### 数据结构

- **`Codex`**: 同步客户端包装器，封装 `AppServerClient`
- **`Thread`**: 线程句柄，包含 `AppServerClient` 引用和线程 ID
- **`TurnHandle`**: Turn 句柄，用于流式获取结果
- **`RunResult`**: 运行结果，包含：
  - `final_response: str | None`: 最终 AI 响应文本
  - `items: list[ThreadItem]`: 所有项目列表
  - `usage: ThreadTokenUsage | None`: Token 使用统计
- **`ThreadStartParams`**: 线程启动参数 (Pydantic 模型)
- **`TurnStartParams`**: Turn 启动参数 (Pydantic 模型)
- **`AppServerConfig`**: 客户端配置，包含：
  - `codex_bin: str | None`: 自定义二进制路径
  - `launch_args_override: tuple[str, ...] | None`: 启动参数覆盖
  - `config_overrides: tuple[str, ...]`: 配置覆盖
  - `cwd: str | None`: 工作目录
  - `env: dict[str, str] | None`: 环境变量
  - `client_name/title/version`: 客户端标识
  - `experimental_api: bool`: 实验性 API 开关

### 协议与命令

- **传输协议**: JSON-RPC 2.0 over stdio
- **核心 RPC 方法**:
  - `initialize`: 客户端/服务器握手，交换能力信息
  - `thread/start`: 创建新线程，返回线程 ID
  - `turn/start`: 启动对话 turn，返回 turn ID
  - `turn/completed` (通知): Turn 完成通知，包含完整 turn 信息
  - `item/completed` (通知): 项目完成通知
  - `thread/tokenUsageUpdated` (通知): Token 使用更新

### 线程模型

```
主线程
  ├── AppServerClient._lock (threading.Lock)  # 保护写入
  ├── AppServerClient._turn_consumer_lock     # 保护 turn 消费者
  └── stderr drain thread (daemon)            # 持续读取 stderr
```

## 关键代码路径与文件引用

### 直接依赖

| 文件 | 用途 |
|------|------|
| `sdk/python/examples/_bootstrap.py` | 本地 SDK 引导加载、运行时配置、服务器标签提取 |
| `sdk/python/src/codex_app_server/__init__.py` | 导出 `Codex` 类 |
| `sdk/python/src/codex_app_server/api.py` | `Codex`, `Thread`, `TurnHandle`, `RunResult` 实现 |
| `sdk/python/src/codex_app_server/client.py` | `AppServerClient`, `AppServerConfig` - 同步 RPC 客户端 |

### 间接依赖

| 文件 | 用途 |
|------|------|
| `sdk/python/src/codex_app_server/models.py` | `InitializeResponse`, `Notification`, `JsonObject` 等模型 |
| `sdk/python/src/codex_app_server/_inputs.py` | 输入类型定义 (`TextInput`, `ImageInput` 等) 和转换 |
| `sdk/python/src/codex_app_server/_run.py` | `_collect_run_result` 实现 |
| `sdk/python/src/codex_app_server/generated/v2_all.py` | 生成的 Pydantic 模型 (ThreadStartParams, TurnStartParams 等) |
| `sdk/python/_runtime_setup.py` | 运行时二进制文件下载和安装逻辑 |

### 代码调用链

```
sync.py
  └── Codex (api.py:69)
        └── AppServerClient (client.py:136)
              └── subprocess.Popen([codex_bin, "app-server", "--listen", "stdio://"])
                    └── codex CLI 二进制
```

### 关键方法详解

**`Codex.__init__`** (`api.py:72-79`):
```python
def __init__(self, config: AppServerConfig | None = None) -> None:
    self._client = AppServerClient(config=config)
    try:
        self._client.start()      # 启动子进程
        self._init = self._validate_initialize(self._client.initialize())
    except Exception:
        self._client.close()      # 异常时清理
        raise
```

**`AppServerClient.start`** (`client.py:161-189`):
```python
def start(self) -> None:
    # 解析或下载 codex 二进制
    codex_bin = _resolve_codex_bin(self.config)
    # 构建启动参数
    args = [str(codex_bin), "app-server", "--listen", "stdio://"]
    # 启动子进程
    self._proc = subprocess.Popen(
        args,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        ...
    )
    self._start_stderr_drain_thread()
```

**`Thread.run`** (`api.py:472-504`):
```python
def run(self, input: RunInput, ...) -> RunResult:
    turn = self.turn(_normalize_run_input(input), ...)
    stream = turn.stream()
    try:
        return _collect_run_result(stream, turn_id=turn.id)
    finally:
        stream.close()
```

## 依赖与外部交互

### Python 依赖

- `pydantic`: 数据验证和序列化 (必需)
- 标准库: `sys`, `pathlib`, `subprocess`, `threading`, `json`, `uuid`, `collections`

### 外部二进制依赖

- `codex` CLI 二进制文件 (由 `_runtime_setup.py` 自动下载)
- 版本: `0.116.0-alpha.1` (定义于 `_runtime_setup.py:PINNED_RUNTIME_VERSION`)
- 来源: GitHub Releases (`openai/codex`)
- 支持平台:
  - macOS: aarch64, x86_64
  - Linux: aarch64, x86_64 (musl)
  - Windows: aarch64, x86_64

### 网络交互

- 首次运行时从 GitHub Releases 下载对应平台的 `codex` 二进制文件
- 运行时通过 stdio 与本地 `codex app-server` 子进程通信
- 支持代理配置（通过标准环境变量如 `HTTP_PROXY`）

### 环境变量

- `GH_TOKEN` / `GITHUB_TOKEN`: 用于 GitHub API 认证（可选，提高下载成功率）
- `HTTP_PROXY` / `HTTPS_PROXY`: 代理配置

## 风险、边界与改进建议

### 风险点

1. **运行时下载失败**
   - 风险：首次运行时需要下载二进制文件，网络问题、防火墙、GitHub 访问限制会导致失败
   - 缓解：
     - 支持 `GH_TOKEN` 认证提高 API 限流阈值
     - 支持 `gh` CLI 作为备选下载方式
     - 可手动下载并配置 `AppServerConfig(codex_bin="/path/to/codex")`

2. **子进程管理**
   - 风险：`codex app-server` 子进程可能崩溃或挂起
   - 缓解：实现了 `close()` 方法进行清理，包括 terminate/kill 和超时等待

3. **单线程消费者限制**
   - 风险：当前不支持并发 turn 消费者
   - 代码体现 (`client.py:288-296`):
     ```python
     if self._active_turn_consumer is not None:
         raise RuntimeError(
             "Concurrent turn consumers are not yet supported in the experimental SDK."
         )
     ```

4. **默认审批处理器自动接受**
   - 风险：`AppServerClient` 默认自动接受所有命令执行和文件变更请求
   - 代码体现 (`client.py:478-483`):
     ```python
     def _default_approval_handler(self, method: str, params: JsonObject | None) -> JsonObject:
         if method == "item/commandExecution/requestApproval":
             return {"decision": "accept"}
         if method == "item/fileChange/requestApproval":
             return {"decision": "accept"}
         return {}
     ```

### 边界情况

1. **模型名称硬编码**
   - 示例使用 `"gpt-5.4"`，需要确保服务器支持该模型
   - 建议通过参数或环境变量传入模型名称

2. **响应大小限制**
   - `stderr` 缓冲区限制为 400 行 (`client.py:151`)
   - 大量输出可能被截断

3. **平台兼容性**
   - 运行时二进制仅支持特定平台组合
   - 不支持 32 位系统或非标准架构

4. **JSON-RPC 消息大小**
   - 默认使用行缓冲 (`bufsize=1`)，大消息可能影响性能

### 改进建议

1. **错误处理增强**
   ```python
   # 建议添加更详细的错误处理
   from codex_app_server import TransportClosedError, AppServerError
   
   try:
       with Codex(config=runtime_config()) as codex:
           thread = codex.thread_start(model="gpt-5.4", config={...})
           result = thread.run("...")
   except TransportClosedError as e:
       print(f"Connection closed: {e}")
   except AppServerError as e:
       print(f"Server error: {e}")
   except FileNotFoundError as e:
       print(f"Binary not found: {e}")
   ```

2. **配置外部化**
   ```python
   import os
   
   model = os.getenv("CODEX_MODEL", "gpt-5.4")
   effort = os.getenv("CODEX_REASONING_EFFORT", "high")
   thread = codex.thread_start(model=model, config={"model_reasoning_effort": effort})
   ```

3. **流式响应支持**
   - 当前示例使用 `thread.run()` 是阻塞式收集结果
   - 建议添加流式响应示例展示 `turn.stream()` 用法

4. **审批策略配置**
   - 示例应展示如何配置审批策略，而非使用默认自动接受
   ```python
   from codex_app_server import AskForApproval
   
   thread = codex.thread_start(
       model="gpt-5.4",
       approval_policy=AskForApproval("on-request")  # 或 "never", "on-failure"
   )
   ```

5. **资源使用监控**
   - 示例中打印了 `result.items` 数量和 `result.final_response`
   - 建议也展示 `result.usage` 中的 token 使用统计
   ```python
   print("Items:", len(result.items))
   print("Text:", result.final_response)
   if result.usage:
       print("Tokens - Input:", result.usage.input_tokens, 
             "Output:", result.usage.output_tokens)
   ```
