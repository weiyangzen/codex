# async.py 研究文档

## 场景与职责

`async.py` 是 Codex Python SDK 的异步快速入门示例，位于 `sdk/python/examples/01_quickstart_constructor/` 目录。该文件展示了如何使用 `AsyncCodex` 类以异步方式与 Codex App Server 进行交互，是开发者学习异步 API 用法的首要入口点。

核心职责：
- 演示异步上下文管理器 (`async with`) 的正确使用方式
- 展示如何通过构造函数方式初始化异步 Codex 客户端
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

### 3. 异步客户端初始化与使用
```python
async with AsyncCodex(config=runtime_config()) as codex:
    print("Server:", server_label(codex.metadata))
```
目的：使用异步上下文管理器确保资源正确初始化和释放。

### 4. 线程创建与对话执行
```python
thread = await codex.thread_start(model="gpt-5.4", config={"model_reasoning_effort": "high"})
result = await thread.run("Say hello in one sentence.")
```
目的：
- 创建新线程，指定模型和推理强度配置
- 在线程上执行单轮对话，获取 AI 响应
- 输出响应内容和项目数量

## 具体技术实现

### 关键流程

1. **初始化流程**
   ```
   async with AsyncCodex(config) as codex:
       ├── AsyncCodex.__init__(config)  # 创建 AsyncAppServerClient
       ├── AsyncCodex.__aenter__()
       │   └── _ensure_initialized()
       │       ├── AsyncAppServerClient.start()  # 启动子进程
       │       └── AsyncAppServerClient.initialize()  # JSON-RPC initialize
       └── ...使用 codex...
   ```

2. **线程创建流程**
   ```
   await codex.thread_start(model=..., config=...)
       ├── _ensure_initialized()  # 确保已初始化
       ├── 构建 ThreadStartParams
       ├── AsyncAppServerClient.thread_start(params)
       │   └── _call_sync(self._sync.thread_start, params)
       │       └── asyncio.to_thread(...)  # 在线程池中执行同步调用
       └── 返回 AsyncThread(codex, thread_id)
   ```

3. **对话执行流程**
   ```
   await thread.run("Say hello in one sentence.")
       ├── AsyncThread.run(input)
       │   ├── self.turn(input)  # 创建 turn
       │   │   ├── _to_wire_input(input)  # 转换为 wire 格式
       │   │   ├── AsyncAppServerClient.turn_start(...)
       │   │   └── 返回 AsyncTurnHandle
       │   ├── turn.stream()  # 获取事件流
       │   └── _collect_async_run_result(stream, turn_id)
       │       ├── 遍历通知流
       │       ├── 收集 ItemCompletedNotification
       │       ├── 收集 ThreadTokenUsageUpdatedNotification
       │       └── 等待 TurnCompletedNotification
       └── 返回 RunResult
   ```

### 数据结构

- **`AsyncCodex`**: 异步客户端包装器，封装 `AsyncAppServerClient`
- **`AsyncThread`**: 线程句柄，包含 `AsyncCodex` 引用和线程 ID
- **`AsyncTurnHandle`**: Turn 句柄，用于流式获取结果
- **`RunResult`**: 运行结果，包含 `final_response`, `items`, `usage`
- **`ThreadStartParams`**: 线程启动参数 (Pydantic 模型)
- **`TurnStartParams`**: Turn 启动参数 (Pydantic 模型)

### 协议与命令

- **传输协议**: JSON-RPC 2.0 over stdio
- **核心 RPC 方法**:
  - `initialize`: 客户端/服务器握手
  - `thread/start`: 创建新线程
  - `turn/start`: 启动对话 turn
  - `turn/completed` (通知): Turn 完成通知
  - `item/completed` (通知): 项目完成通知

## 关键代码路径与文件引用

### 直接依赖

| 文件 | 用途 |
|------|------|
| `sdk/python/examples/_bootstrap.py` | 本地 SDK 引导加载、运行时配置、服务器标签提取 |
| `sdk/python/src/codex_app_server/__init__.py` | 导出 `AsyncCodex` 类 |
| `sdk/python/src/codex_app_server/api.py` | `AsyncCodex`, `AsyncThread`, `AsyncTurnHandle`, `RunResult` 实现 |
| `sdk/python/src/codex_app_server/async_client.py` | `AsyncAppServerClient` - 底层异步 RPC 客户端 |
| `sdk/python/src/codex_app_server/client.py` | `AppServerClient`, `AppServerConfig` - 同步 RPC 客户端基础 |

### 间接依赖

| 文件 | 用途 |
|------|------|
| `sdk/python/src/codex_app_server/models.py` | `InitializeResponse`, `Notification`, `JsonObject` 等模型 |
| `sdk/python/src/codex_app_server/_inputs.py` | 输入类型定义 (`TextInput`, `ImageInput` 等) 和转换 |
| `sdk/python/src/codex_app_server/_run.py` | `_collect_async_run_result` 实现 |
| `sdk/python/src/codex_app_server/generated/v2_all.py` | 生成的 Pydantic 模型 (ThreadStartParams, TurnStartParams 等) |
| `sdk/python/_runtime_setup.py` | 运行时二进制文件下载和安装逻辑 |

### 代码调用链

```
async.py
  └── AsyncCodex (api.py:270)
        └── AsyncAppServerClient (async_client.py:39)
              └── AppServerClient (client.py:136)
                    └── subprocess.Popen([codex_bin, "app-server", "--listen", "stdio://"])
```

## 依赖与外部交互

### Python 依赖

- `pydantic`: 数据验证和序列化
- `asyncio`: 异步运行时
- 标准库: `sys`, `pathlib`

### 外部二进制依赖

- `codex` CLI 二进制文件 (由 `_runtime_setup.py` 自动下载)
- 版本: `0.116.0-alpha.1` (定义于 `_runtime_setup.py:PINNED_RUNTIME_VERSION`)
- 来源: GitHub Releases (`openai/codex`)

### 网络交互

- 首次运行时从 GitHub Releases 下载对应平台的 `codex` 二进制文件
- 运行时通过 stdio 与本地 `codex app-server` 子进程通信

### 环境变量

- `GH_TOKEN` / `GITHUB_TOKEN`: 用于 GitHub API 认证（可选）

## 风险、边界与改进建议

### 风险点

1. **运行时下载失败**
   - 风险：首次运行时需要下载二进制文件，网络问题会导致失败
   - 缓解：支持 `GH_TOKEN` 认证，支持 `gh` CLI 作为备选下载方式

2. **异步初始化竞态**
   - 风险：`AsyncCodex` 使用懒初始化，并发访问可能导致重复初始化
   - 缓解：使用 `asyncio.Lock` 保护初始化过程 (`_init_lock`)

3. **资源泄漏**
   - 风险：未正确使用 `async with` 可能导致子进程未清理
   - 缓解：文档强调使用上下文管理器，实现了 `__aexit__` 清理

### 边界情况

1. **线程消费者限制**
   - 当前不支持并发 turn 消费者 (`acquire_turn_consumer` 会报错)
   - 代码注释标明这是实验性限制

2. **模型名称硬编码**
   - 示例使用 `"gpt-5.4"`，需要确保服务器支持该模型

3. **平台支持**
   - 运行时二进制仅支持特定平台 (macOS/Linux/Windows, x86_64/aarch64)

### 改进建议

1. **错误处理增强**
   ```python
   # 建议添加 try-except 块展示错误处理
   try:
       async with AsyncCodex(config=runtime_config()) as codex:
           ...
   except ConnectionError as e:
       print(f"Failed to connect: {e}")
   ```

2. **配置外部化**
   - 将模型名称、配置参数通过环境变量或命令行参数传入

3. **日志记录**
   - 添加结构化日志记录，便于调试

4. **示例扩展**
   - 添加流式响应示例（当前使用 `thread.run()` 是阻塞式收集结果）
   - 展示如何使用 `turn.stream()` 手动处理事件
