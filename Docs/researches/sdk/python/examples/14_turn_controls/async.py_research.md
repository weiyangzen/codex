# async.py 研究文档

## 场景与职责

`async.py` 是 Codex Python SDK 的异步示例程序，专门演示如何在异步编程模式下对 AI 对话回合（turn）进行实时控制和干预。该示例位于 `sdk/python/examples/14_turn_controls/` 目录，是 SDK 示例体系中展示高级 turn 控制功能的核心代码。

### 核心职责
1. **演示 Steer（引导）功能**：在 AI 生成回复过程中，通过发送额外的文本输入来实时引导/修正 AI 的行为方向
2. **演示 Interrupt（中断）功能**：在 AI 生成回复过程中，立即中断当前 turn 的执行
3. **展示异步 API 使用模式**：通过 `async/await` 语法展示如何正确使用 `AsyncCodex` 客户端
4. **事件流处理**：演示如何消费 turn 的事件流（event stream）并解析关键事件

---

## 功能点目的

### 1. Steer（引导）功能演示
- **目的**：允许用户在 AI 生成回复的过程中，通过发送额外的指令来"引导" AI 调整其行为
- **示例场景**：用户要求 AI "从 1 数到 40"，但在生成过程中通过 steer 发送 "Keep it brief and stop after 10 numbers"，让 AI 提前停止并精简输出
- **业务价值**：实现人机协作的实时干预，避免完全重新开始对话

### 2. Interrupt（中断）功能演示
- **目的**：允许用户立即终止当前正在进行的 turn
- **示例场景**：用户要求 AI "从 1 数到 200"，但随后决定不需要这个长列表，调用 interrupt 立即停止
- **业务价值**：提供紧急停止机制，避免不必要的 token 消耗和等待时间

### 3. 事件流监控
- **目的**：展示如何监听 turn 执行过程中的各类事件（如 `turn/completed`）
- **关键指标**：统计事件数量、获取最终 turn 状态、提取 AI 回复文本

---

## 具体技术实现

### 关键流程

```
┌─────────────────────────────────────────────────────────────────┐
│                         主流程 (main)                            │
├─────────────────────────────────────────────────────────────────┤
│  1. 初始化 AsyncCodex 客户端 (with 上下文管理器)                  │
│  2. 创建 Thread (thread_start)                                   │
│  3. 执行 Steer 演示流程                                          │
│     ├── 启动 turn: "Count from 1 to 40..."                       │
│     ├── 调用 steer(): "Keep it brief..."                         │
│     └── 消费事件流，统计事件，获取结果                            │
│  4. 执行 Interrupt 演示流程                                      │
│     ├── 启动 turn: "Count from 1 to 200..."                      │
│     ├── 调用 interrupt()                                         │
│     └── 消费事件流，统计事件，获取结果                            │
│  5. 输出统计结果                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 数据结构

#### 核心类依赖
```python
# 来自 codex_app_server 的异步 API
from codex_app_server import AsyncCodex, TextInput

# 关键类层次
AsyncCodex          # 异步客户端入口
  └── AsyncThread   # 线程/对话容器
        └── AsyncTurnHandle  # 单个回合控制句柄
              ├── steer()     # 引导方法
              ├── interrupt() # 中断方法
              └── stream()    # 事件流
```

#### 关键数据类型
- `TextInput`: 文本输入包装类，包含 `text: str` 字段
- `TurnSteerResponse`: steer 操作的响应，包含 `turn_id: str`
- `TurnInterruptResponse`: interrupt 操作的响应（空结构）
- `Notification`: 事件通知基类，包含 `method: str` 和 `payload`
- `TurnCompletedNotification`: turn 完成事件，包含最终 `turn` 对象

### 协议与命令

#### JSON-RPC 方法调用
示例底层通过 JSON-RPC over stdio 与 Codex app-server 通信：

1. **turn/start**: 启动新 turn
   ```json
   {
     "method": "turn/start",
     "params": {
       "threadId": "...",
       "input": [{"type": "text", "text": "..."}]
     }
   }
   ```

2. **turn/steer**: 向活跃 turn 发送引导输入
   ```json
   {
     "method": "turn/steer",
     "params": {
       "threadId": "...",
       "expectedTurnId": "...",
       "input": [{"type": "text", "text": "..."}]
     }
   }
   ```

3. **turn/interrupt**: 中断活跃 turn
   ```json
   {
     "method": "turn/interrupt",
     "params": {
       "threadId": "...",
       "turnId": "..."
     }
   }
   ```

#### 事件通知监听
通过 `stream()` 方法消费 Server-Sent Events 风格的通知流：
- `turn/completed`: Turn 执行完成（正常结束或被中断）
- `item/agentMessage/delta`: AI 消息片段（流式输出）
- `turn/started`: Turn 开始执行

---

## 关键代码路径与文件引用

### 本文件关键代码段

#### Steer 流程 (lines 23-40)
```python
steer_turn = await thread.turn(TextInput("Count from 1 to 40 with commas, then one summary sentence."))
steer_result = "sent"
try:
    _ = await steer_turn.steer(TextInput("Keep it brief and stop after 10 numbers."))
except Exception as exc:
    steer_result = f"skipped {type(exc).__name__}"

# 事件流消费
async for event in steer_turn.stream():
    if event.method == "turn/completed":
        steer_completed_turn = event.payload.turn
```

#### Interrupt 流程 (lines 42-58)
```python
interrupt_turn = await thread.turn(TextInput("Count from 1 to 200 with commas, then one summary sentence."))
interrupt_result = "sent"
try:
    _ = await interrupt_turn.interrupt()
except Exception as exc:
    interrupt_result = f"skipped {type(exc).__name__}"
```

### 依赖文件链

```
async.py
├── _bootstrap.py (sdk/python/examples/_bootstrap.py)
│   ├── ensure_local_sdk_src()  # 确保 SDK 源码在路径中
│   └── runtime_config()        # 提供默认 AppServerConfig
└── codex_app_server (sdk/python/src/codex_app_server/)
    ├── __init__.py
    │   ├── AsyncCodex          # 从 api.py 导入
    │   └── TextInput           # 从 _inputs.py 导入
    ├── api.py
    │   ├── AsyncCodex          # 异步客户端主类
    │   ├── AsyncThread         # 线程操作类
    │   └── AsyncTurnHandle     # Turn 控制句柄
    │       ├── steer()         # 调用 client.turn_steer()
    │       ├── interrupt()     # 调用 client.turn_interrupt()
    │       └── stream()        # 异步事件流生成器
    ├── async_client.py
    │   └── AsyncAppServerClient
    │       ├── turn_steer()    # JSON-RPC turn/steer
    │       └── turn_interrupt() # JSON-RPC turn/interrupt
    └── generated/v2_all.py
        ├── TurnSteerResponse   # Pydantic 模型
        ├── TurnInterruptResponse
        └── TurnCompletedNotification
```

---

## 依赖与外部交互

### Python 依赖
- **Python 3.9+**: 支持 `async/await` 语法
- **pydantic**: 数据模型验证（通过 `_bootstrap._ensure_runtime_dependencies` 检查）

### SDK 内部依赖
| 模块 | 用途 |
|------|------|
| `codex_app_server.AsyncCodex` | 异步客户端入口 |
| `codex_app_server.TextInput` | 文本输入包装 |
| `_bootstrap` | 示例环境初始化 |

### 外部进程交互
- **Codex CLI Binary**: 通过 `AppServerConfig` 配置的二进制路径启动 `codex app-server --listen stdio://`
- **JSON-RPC over stdio**: 与 app-server 进程进行双向通信

### 配置参数
```python
# 通过 runtime_config() 获取默认配置
AppServerConfig(
    codex_bin=None,              # 自动查找 codex 二进制
    launch_args_override=None,   # 可覆盖启动参数
    config_overrides=(),         # 额外配置项
    experimental_api=True,       # 启用实验性 API（steer/interrupt 需要）
)
```

---

## 风险、边界与改进建议

### 已知风险

1. **实验性 API 依赖**
   - Steer 和 Interrupt 功能依赖 `experimental_api=True` 配置
   - 未来 API 可能变化，需关注 SDK 更新

2. **并发限制**
   - 当前 SDK 限制同一时间只能有一个活跃的 turn consumer
   - `acquire_turn_consumer()` 会在并发访问时抛出 `RuntimeError`
   - 代码注释显示: "Concurrent turn consumers are not yet supported"

3. **时序竞争条件**
   - Steer 必须在 turn 仍在生成过程中调用，否则可能失败
   - 示例中通过 try-except 捕获异常，但生产代码需要更精细的重试逻辑

4. **异常处理简化**
   - 示例使用通用的 `except Exception` 捕获所有异常
   - 生产环境应区分网络错误、API 错误、状态错误等不同类型

### 边界条件

| 场景 | 行为 |
|------|------|
| Turn 已完成后再调用 steer | 抛出异常，示例中捕获并标记为 "skipped ..." |
| Turn 已完成后再调用 interrupt | 抛出异常，示例中捕获并标记为 "skipped ..." |
| 网络中断 | `TransportClosedError`，需要重新初始化客户端 |
| App-server 进程崩溃 | 从 `stream()` 抛出异常，stderr 日志可通过 `_stderr_tail()` 获取 |

### 改进建议

1. **更精细的错误分类**
   ```python
   # 建议区分错误类型
   from codex_app_server import TransportClosedError, AppServerRpcError
   
   try:
       await turn.steer(...)
   except TransportClosedError:
       # 需要重新连接
   except AppServerRpcError as e:
       # API 级别错误
   ```

2. **添加超时控制**
   ```python
   # 为 steer/interrupt 添加超时
   await asyncio.wait_for(turn.steer(...), timeout=5.0)
   ```

3. **事件流背压处理**
   - 当前实现同步处理每个事件，如果事件产生速度超过处理速度，可能导致内存问题
   - 建议添加 `asyncio.Semaphore` 或队列机制

4. **更丰富的监控指标**
   - 除了事件计数，可以统计 token 使用量、响应时间等
   - 利用 `ThreadTokenUsageUpdatedNotification` 获取实时用量

5. **生产环境配置**
   - 示例使用默认 `AppServerConfig()`，生产环境应显式配置：
     - `codex_bin`: 指定确定的二进制路径
     - `env`: 配置 API keys
     - `approval_handler`: 自定义审批逻辑（当前默认自动接受所有审批）

### 相关测试参考
- SDK 测试目录: `sdk/python/tests/`
- 建议查看是否有 `test_turn_steer` 或 `test_turn_interrupt` 相关测试用例
- 注意: 测试可能需要 `CODEX_SANDBOX_NETWORK_DISABLED` 环境变量处理
