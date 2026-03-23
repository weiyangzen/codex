# sync.py 研究文档

## 场景与职责

`sync.py` 是 Codex Python SDK 的同步示例程序，与 `async.py` 功能完全对应，但使用同步阻塞式 API 而非异步 API。该示例位于 `sdk/python/examples/14_turn_controls/` 目录，为不熟悉异步编程或需要在同步上下文中集成 Codex 功能的开发者提供参考实现。

### 核心职责
1. **演示 Steer（引导）功能（同步模式）**：在 AI 生成回复过程中，通过发送额外的文本输入来实时引导/修正 AI 的行为方向
2. **演示 Interrupt（中断）功能（同步模式）**：在 AI 生成回复过程中，立即中断当前 turn 的执行
3. **展示同步 API 使用模式**：通过标准同步调用展示如何正确使用 `Codex` 客户端
4. **事件流处理**：演示如何在同步上下文中消费 turn 的事件流（使用迭代器而非异步生成器）

---

## 功能点目的

### 1. Steer（引导）功能演示
- **目的**：展示如何在同步代码中对正在进行的 AI 回复进行实时干预
- **示例场景**：用户要求 AI "从 1 数到 40"，但在生成过程中通过 steer 发送 "Keep it brief and stop after 10 numbers"，让 AI 提前停止
- **同步特性**：`steer()` 方法是同步阻塞调用，直到服务器确认 steer 请求已处理

### 2. Interrupt（中断）功能演示
- **目的**：展示如何在同步代码中立即终止当前 turn
- **示例场景**：用户要求 AI "从 1 数到 200"，但随后决定不需要这个长列表，调用 interrupt 立即停止
- **同步特性**：`interrupt()` 方法是同步阻塞调用，直到服务器确认中断请求

### 3. 同步事件流迭代
- **目的**：展示如何使用标准 Python 迭代器（`for event in stream()`）消费事件流
- **与异步的区别**：异步版本使用 `async for`，同步版本使用普通 `for` 循环

---

## 具体技术实现

### 关键流程

```
┌─────────────────────────────────────────────────────────────────┐
│                         主流程 (main)                            │
├─────────────────────────────────────────────────────────────────┤
│  1. 初始化 Codex 客户端 (with 上下文管理器)                       │
│  2. 创建 Thread (thread_start)                                   │
│  3. 执行 Steer 演示流程                                          │
│     ├── 启动 turn: "Count from 1 to 40..."                       │
│     ├── 调用 steer(): "Keep it brief..."                         │
│     └── 迭代事件流，统计事件，获取结果                            │
│  4. 执行 Interrupt 演示流程                                      │
│     ├── 启动 turn: "Count from 1 to 200..."                      │
│     ├── 调用 interrupt()                                         │
│     └── 迭代事件流，统计事件，获取结果                            │
│  5. 输出统计结果                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 同步 vs 异步 API 对比

| 特性 | sync.py (同步) | async.py (异步) |
|------|---------------|-----------------|
| 客户端类 | `Codex` | `AsyncCodex` |
| 线程类 | `Thread` | `AsyncThread` |
| Turn 句柄 | `TurnHandle` | `AsyncTurnHandle` |
| 上下文管理器 | `with ...:` | `async with ...:` |
| 方法调用 | 直接调用 | `await` 调用 |
| 事件流 | `for event in stream():` | `async for event in stream():` |
| 底层实现 | 直接 stdio 通信 | `asyncio.to_thread()` 包装 |

### 数据结构

#### 核心类依赖
```python
# 来自 codex_app_server 的同步 API
from codex_app_server import Codex, TextInput

# 关键类层次
Codex               # 同步客户端入口
  └── Thread        # 线程/对话容器
        └── TurnHandle    # 单个回合控制句柄
              ├── steer()     # 引导方法（同步）
              ├── interrupt() # 中断方法（同步）
              └── stream()    # 事件流迭代器
```

#### 关键数据类型
与异步版本相同：
- `TextInput`: 文本输入包装类，包含 `text: str` 字段
- `TurnSteerResponse`: steer 操作的响应
- `TurnInterruptResponse`: interrupt 操作的响应
- `Notification`: 事件通知基类
- `TurnCompletedNotification`: turn 完成事件

### 协议与命令

同步版本使用完全相同的底层 JSON-RPC 协议：

1. **turn/start**: 启动新 turn
2. **turn/steer**: 向活跃 turn 发送引导输入
3. **turn/interrupt**: 中断活跃 turn

事件通知类型也完全一致：
- `turn/completed`: Turn 执行完成
- `item/agentMessage/delta`: AI 消息片段
- `turn/started`: Turn 开始执行

**唯一区别**：同步版本在 `async_client.py` 中通过 `asyncio.to_thread()` 将同步调用包装为异步，而同步版本直接调用 `client.py` 中的原始同步方法。

---

## 关键代码路径与文件引用

### 本文件关键代码段

#### Steer 流程 (lines 20-36)
```python
steer_turn = thread.turn(TextInput("Count from 1 to 40 with commas, then one summary sentence."))
steer_result = "sent"
try:
    _ = steer_turn.steer(TextInput("Keep it brief and stop after 10 numbers."))
except Exception as exc:
    steer_result = f"skipped {type(exc).__name__}"

# 同步事件流迭代
for event in steer_turn.stream():
    steer_event_count += 1
    if event.method == "turn/completed":
        steer_completed_turn = event.payload.turn
```

#### Interrupt 流程 (lines 38-54)
```python
interrupt_turn = thread.turn(TextInput("Count from 1 to 200 with commas, then one summary sentence."))
interrupt_result = "sent"
try:
    _ = interrupt_turn.interrupt()
except Exception as exc:
    interrupt_result = f"skipped {type(exc).__name__}"
```

### 依赖文件链

```
sync.py
├── _bootstrap.py (sdk/python/examples/_bootstrap.py)
│   ├── ensure_local_sdk_src()  # 确保 SDK 源码在路径中
│   └── runtime_config()        # 提供默认 AppServerConfig
│       └── assistant_text_from_turn()  # 辅助函数：从 turn 提取文本
└── codex_app_server (sdk/python/src/codex_app_server/)
    ├── __init__.py
    │   ├── Codex               # 从 api.py 导入（同步版本）
    │   └── TextInput           # 从 _inputs.py 导入
    ├── api.py
    │   ├── Codex               # 同步客户端主类
    │   ├── Thread              # 同步线程操作类
    │   └── TurnHandle          # 同步 Turn 控制句柄
    │       ├── steer()         # 调用 _client.turn_steer()
    │       ├── interrupt()     # 调用 _client.turn_interrupt()
    │       └── stream()        # 同步事件流迭代器
    ├── client.py
    │   └── AppServerClient
    │       ├── turn_steer()    # JSON-RPC turn/steer
    │       ├── turn_interrupt() # JSON-RPC turn/interrupt
    │       └── next_notification() # 阻塞读取通知
    └── generated/v2_all.py
        ├── TurnSteerResponse
        ├── TurnInterruptResponse
        └── TurnCompletedNotification
```

### 同步与异步实现差异

#### 同步实现 (client.py)
```python
# 直接阻塞调用
proc = subprocess.Popen(..., stdin=PIPE, stdout=PIPE, ...)
proc.stdin.write(json.dumps(payload) + "\n")
line = proc.stdout.readline()  # 阻塞等待响应
```

#### 异步包装 (async_client.py)
```python
# 在线程池中执行同步调用
async def turn_steer(...):
    async with self._transport_lock:
        return await asyncio.to_thread(
            self._sync.turn_steer, ...
        )
```

---

## 依赖与外部交互

### Python 依赖
- **Python 3.9+**: 基础版本要求
- **pydantic**: 数据模型验证

### SDK 内部依赖
| 模块 | 用途 |
|------|------|
| `codex_app_server.Codex` | 同步客户端入口 |
| `codex_app_server.TextInput` | 文本输入包装 |
| `_bootstrap` | 示例环境初始化 |

### 外部进程交互
与异步版本完全相同：
- 启动 `codex app-server --listen stdio://`
- JSON-RPC over stdio 通信

### 配置参数
```python
# 通过 runtime_config() 获取默认配置
AppServerConfig(
    experimental_api=True,  # 启用实验性 API
    # 其他参数使用默认值
)
```

---

## 风险、边界与改进建议

### 同步版本特有考虑

1. **阻塞风险**
   - 同步 API 会阻塞调用线程直到服务器响应
   - 在 GUI 应用或 Web 服务中使用需要格外小心
   - 建议：在后台线程中运行同步 Codex 操作

2. **线程安全**
   - `AppServerClient` 内部使用 `threading.Lock` 保护 stdio 操作
   - 但同一时间仍只能有一个 turn consumer（通过 `_turn_consumer_lock` 限制）

3. **与异步代码集成**
   - 如果需要在异步应用中集成，建议使用 `async.py` 模式
   - 或在线程池中运行同步版本：`await asyncio.to_thread(sync_codex_operation)`

### 通用风险（与 async.py 相同）

1. **实验性 API 依赖**
   - Steer 和 Interrupt 需要 `experimental_api=True`

2. **并发限制**
   - 同一时间只能有一个活跃的 turn consumer

3. **时序竞争条件**
   - Steer/Interrupt 必须在 turn 活跃期间调用

4. **异常处理简化**
   - 示例使用通用的 `except Exception`

### 边界条件

| 场景 | 行为 |
|------|------|
| Turn 已完成后再调用 steer | 抛出异常，标记为 "skipped ..." |
| Turn 已完成后再调用 interrupt | 抛出异常，标记为 "skipped ..." |
| 网络/App-server 崩溃 | `TransportClosedError` |

### 改进建议

1. **线程池使用**
   ```python
   # 在 Web 服务中集成时
   from concurrent.futures import ThreadPoolExecutor
   
   executor = ThreadPoolExecutor(max_workers=2)
   
   def run_codex_task():
       with Codex() as codex:
           # ... 操作
           pass
   
   # 异步上下文中调用
   await asyncio.get_event_loop().run_in_executor(executor, run_codex_task)
   ```

2. **超时控制**
   ```python
   import signal
   
   # 使用信号实现超时（Unix）
   signal.alarm(30)  # 30秒超时
   try:
       turn.steer(...)
   finally:
       signal.alarm(0)
   ```

3. **生成器资源管理**
   ```python
   # 确保流迭代器正确关闭
   stream = turn.stream()
   try:
       for event in stream:
           # 处理事件
           pass
   finally:
       stream.close()  # 显式关闭
   ```

4. **与 async.py 的代码复用**
   - 两个示例逻辑几乎完全相同，仅 API 调用方式不同
   - 可以考虑抽象出业务逻辑，通过适配器模式支持两种模式

### 选择建议：同步 vs 异步

| 场景 | 推荐版本 |
|------|---------|
| 命令行脚本、批处理任务 | `sync.py` |
| 已有同步代码库集成 | `sync.py` |
| Web 服务（FastAPI/Starlette） | `async.py` |
| 需要并发处理多个对话 | `async.py` |
| 与 asyncio 生态集成 | `async.py` |
| Jupyter Notebook | `async.py`（支持 `await` 直接调用）|
