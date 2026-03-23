# sync.py 研究文档

## 场景与职责

`sync.py` 是 OpenAI Codex Python SDK 的示例程序，演示如何使用**同步 API** 向 AI 模型同时发送**文本和远程图片**进行多模态对话。与 `async.py` 相比，该示例使用阻塞式 API 调用，适合：

1. 简单的脚本和命令行工具
2. 不需要并发处理的场景
3. 快速原型开发和测试
4. 与现有同步代码库集成

## 功能点目的

### 1. 同步多模态输入
展示如何使用同步 API 组合 `TextInput` 和 `ImageInput`，实现与异步版本相同的多模态对话功能。

### 2. 简洁的阻塞式编程
使用同步上下文管理器 (`with` 语句)，代码更直观，无需处理 `async/await` 复杂性。

### 3. 远程图片处理
通过 `ImageInput` 传入远程图片 URL，SDK 自动处理图片下载和编码。

### 4. 对话生命周期管理
演示同步模式下线程创建、回合执行、结果读取的完整流程。

## 具体技术实现

### 关键流程

```
┌─────────────────┐
│    __main__     │
└────────┬────────┘
         │
         ▼
┌─────────────────────────┐
│ ensure_local_sdk_src()  │◄── 确保 SDK 在 sys.path
└────────┬────────────────┘
         │
         ▼
┌─────────────────────────┐
│ Codex(config)           │◄── 初始化同步客户端
│ with ... as codex:      │    自动启动/关闭
└────────┬────────────────┘
         │
         ▼
┌─────────────────────────┐
│ codex.thread_start()    │◄── 创建新线程
│ model="gpt-5.4"         │    config={"model_reasoning_effort": "high"}
└────────┬────────────────┘
         │
         ▼
┌─────────────────────────┐
│ thread.turn([...])      │◄── 创建 TurnHandle
│ - TextInput("...")      │    不立即执行
│ - ImageInput(URL)       │
└────────┬────────────────┘
         │
         ▼
┌─────────────────────────┐
│ .run()                  │◄── 阻塞执行回合
└────────┬────────────────┘
         │
         ▼
┌─────────────────────────┐
│ thread.read()           │◄── 读取线程状态
│ include_turns=True      │
└────────┬────────────────┘
         │
         ▼
┌─────────────────────────┐
│ find_turn_by_id()       │◄── 定位回合
│ assistant_text_from_turn│    提取回复文本
└─────────────────────────┘
```

### 与异步版本的关键差异

| 方面 | sync.py | async.py |
|------|---------|----------|
| 客户端类 | `Codex` | `AsyncCodex` |
| 上下文管理器 | `with` | `async with` |
| 方法调用 | 直接调用 | `await` 调用 |
| 线程模型 | 阻塞主线程 | 事件循环非阻塞 |
| 并发能力 | 无 | 支持 asyncio 并发 |

### 数据结构

#### 输入序列化流程

```python
# 用户代码
thread.turn([
    TextInput("What is in this image? Give 3 bullets."),
    ImageInput(REMOTE_IMAGE_URL),
])

# 内部转换为 Wire 格式（_inputs.py）
[
    {"type": "text", "text": "What is in this image? Give 3 bullets."},
    {"type": "image", "url": "https://raw.githubusercontent.com/..."}
]

# 封装为 TurnStartParams（api.py）
params = TurnStartParams(
    thread_id=self.id,
    input=wire_input,
    # ... 其他参数
)
```

#### TurnHandle 执行流程

```python
# api.py - TurnHandle.run()
def run(self) -> AppServerTurn:
    completed: TurnCompletedNotification | None = None
    stream = self.stream()  # 获取通知迭代器
    try:
        for event in stream:  # 阻塞迭代直到回合完成
            payload = event.payload
            if isinstance(payload, TurnCompletedNotification) and payload.turn.id == self.id:
                completed = payload
    finally:
        stream.close()

    if completed is None:
        raise RuntimeError("turn completed event not received")
    return completed.turn
```

### 协议交互

#### 同步 JSON-RPC 客户端架构

```
AppServerClient (client.py)
    ├── _proc: subprocess.Popen     # codex app-server 子进程
    ├── _lock: threading.Lock       # 写入锁
    ├── _turn_consumer_lock: threading.Lock
    ├── _pending_notifications: deque[Notification]
    └── _stderr_lines: deque[str]   # stderr 日志缓冲

    ├── start()                     # 启动子进程
    │       └── subprocess.Popen([codex_bin, "app-server", "--listen", "stdio://"])
    │
    ├── request()                   # 发送请求，等待响应
    │       ├── _write_message()    # JSON-RPC 请求
    │       └── _read_message()     # 解析响应
    │
    └── turn_start()                # 启动回合
            └── request("turn/start", ...)
```

#### 回合完成通知处理

```python
# client.py - wait_for_turn_completed
def wait_for_turn_completed(self, turn_id: str) -> TurnCompletedNotification:
    while True:
        notification = self.next_notification()
        if (
            notification.method == "turn/completed"
            and isinstance(notification.payload, TurnCompletedNotification)
            and notification.payload.turn.id == turn_id
        ):
            return notification.payload
```

### 关键代码路径

| 功能 | 文件路径 | 关键函数/类 |
|------|----------|-------------|
| 同步客户端入口 | `sdk/python/src/codex_app_server/api.py` | `Codex` 类 |
| 同步底层客户端 | `sdk/python/src/codex_app_server/client.py` | `AppServerClient` 类 |
| 输入类型定义 | `sdk/python/src/codex_app_server/_inputs.py` | `TextInput`, `ImageInput` |
| 回合结果收集 | `sdk/python/src/codex_app_server/_run.py` | `_collect_run_result` |
| 线程/回合管理 | `sdk/python/src/codex_app_server/api.py` | `Thread`, `TurnHandle` |

## 依赖与外部交互

### 内部依赖

1. **`_bootstrap.py`** - 示例共享工具
   - `ensure_local_sdk_src()`: 本地 SDK 路径注入
   - `runtime_config()`: 默认配置生成
   - `assistant_text_from_turn()`: 文本提取辅助函数
   - `find_turn_by_id()`: 回合查找辅助函数

2. **SDK 核心模块**
   - `codex_app_server.Codex`: 同步客户端主类
   - `codex_app_server.ImageInput`: 图片输入（URL 模式）
   - `codex_app_server.TextInput`: 文本输入

### 外部依赖

1. **Codex CLI 二进制**
   - 通过 `_resolve_codex_bin()` 自动发现或配置指定
   - 启动命令: `codex app-server --listen stdio://`
   - 通信协议: JSON-RPC over stdio

2. **OpenAI API**
   - 图片 URL: GitHub Explore 的 Python logo
   - 模型: `gpt-5.4`
   - 配置: `{"model_reasoning_effort": "high"}`

### 启动流程详解

```python
# 1. 路径设置（示例通用模式）
_EXAMPLES_ROOT = Path(__file__).resolve().parents[1]
if str(_EXAMPLES_ROOT) not in sys.path:
    sys.path.insert(0, str(_EXAMPLES_ROOT))

# 2. 本地 SDK 注入
from _bootstrap import ensure_local_sdk_src
ensure_local_sdk_src()  # 将 sdk/python/src 添加到 sys.path

# 3. 客户端初始化
from codex_app_server import Codex
with Codex(config=runtime_config()) as codex:
    # __enter__ 调用 start() -> 启动 app-server 子进程
    # __exit__ 调用 close() -> 终止子进程
    ...
```

## 风险、边界与改进建议

### 风险点

1. **阻塞调用风险**
   - `turn.run()` 是阻塞调用，直到 AI 完成响应
   - 长时间运行的回合会冻结整个程序
   - 建议：为长时间任务使用异步版本，或添加超时处理

2. **资源泄漏风险**
   - 虽然 `with` 语句确保客户端关闭，但如果程序异常退出，子进程可能残留
   - 建议：添加信号处理程序确保清理

3. **远程依赖风险**
   - 远程图片 URL 可能失效
   - 建议：添加本地回退或使用 `08_local_image_and_text` 模式

4. **并发限制**
   - 同步客户端不支持并发回合
   - `acquire_turn_consumer` 会抛出错误如果尝试并发

### 边界条件

1. **stdio 缓冲区限制**
   - JSON-RPC 消息通过 stdio 传输，受操作系统管道缓冲区限制
   - 超大输入可能导致死锁

2. **子进程生命周期**
   - `AppServerClient` 管理子进程，但异常情况下可能无法优雅关闭
   - `_stderr_lines` 环形缓冲区仅保留最后 400 行日志

3. **模型响应时间**
   - 图片理解通常比纯文本慢，阻塞时间更长
   - 无内置超时机制

### 改进建议

1. **添加超时控制**
   ```python
   import signal
   
   def timeout_handler(signum, frame):
       raise TimeoutError("Turn execution timed out")
   
   signal.signal(signal.SIGALRM, timeout_handler)
   signal.alarm(60)  # 60 秒超时
   try:
       result = thread.turn(inputs).run()
   finally:
       signal.alarm(0)
   ```

2. **错误处理增强**
   ```python
   from codex_app_server import AppServerError
   
   try:
       with Codex(config=runtime_config()) as codex:
           ...
   except AppServerError as e:
       print(f"API Error: {e}")
   except FileNotFoundError as e:
       print(f"Codex binary not found: {e}")
   ```

3. **流式输出支持**
   - 使用 `turn.stream()` 替代 `turn.run()` 实现实时输出
   ```python
   for notification in thread.turn(inputs).stream():
       print(notification.method, notification.payload)
   ```

4. **配置外部化**
   ```python
   import os
   
   config = {
       "model": os.getenv("CODEX_MODEL", "gpt-5.4"),
       "model_reasoning_effort": os.getenv("CODEX_REASONING", "high"),
   }
   ```

5. **批量输入优化**
   - 当前示例仅单张图片，可支持多张
   - 注意 API 对输入数量和总大小的限制

### 与异步版本的选型建议

| 场景 | 推荐版本 | 原因 |
|------|----------|------|
| 简单脚本/CLI | sync.py | 代码简洁，无 async 开销 |
| Web 服务后端 | async.py | 支持并发请求处理 |
| Jupyter Notebook | sync.py | 避免事件循环冲突 |
| 数据处理管道 | async.py | 可并发处理多个输入 |
| 快速原型 | sync.py | 调试更简单 |
| 生产服务 | async.py | 更好的性能和资源利用 |

### 测试建议

1. **Mock 测试**：Mock `AppServerClient` 验证调用序列
2. **集成测试**：使用测试图片和短提示控制成本
3. **异常测试**：模拟网络中断、子进程崩溃、无效响应
4. **性能测试**：测量不同图片大小的响应时间
