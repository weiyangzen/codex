# sync.py 研究文档

## 场景与职责

`sync.py` 是 Codex Python SDK 的同步版本 CLI 迷你应用示例，展示了如何使用同步阻塞式 API 与 Codex App Server 进行交互。与 `async.py` 相比，该示例采用更简单的同步编程模型，适合不需要高并发的场景。

**核心职责：**
- 演示 `Codex` 同步客户端的使用模式
- 展示同步上下文管理器 (`with`) 的正确使用
- 实现流式响应的同步迭代处理
- 提供 Token 使用统计的格式化展示

## 功能点目的

### 1. 同步客户端初始化
使用 `with Codex(config=runtime_config()) as codex` 模式确保资源正确管理：
- 自动处理连接建立和初始化握手
- 确保异常时正确关闭连接
- 通过 `__enter__`/`__exit__` 实现资源生命周期管理

### 2. 线程管理
```python
thread = codex.thread_start(model="gpt-5.4", config={"model_reasoning_effort": "high"})
```
- 创建新对话线程
- 配置模型参数（如 reasoning effort）

### 3. 同步用户输入
```python
user_input = input("you> ").strip()
```
- 直接使用 Python 内置 `input()` 函数
- 简单直接，但会阻塞直到用户输入

### 4. 流式响应处理
```python
for event in turn.stream():
    payload = event.payload
    if event.method == "item/agentMessage/delta":
        delta = getattr(payload, "delta", "")
        if delta:
            print(delta, end="", flush=True)
```
- 同步迭代事件流
- 实时输出 AI 生成的文本片段

### 5. Token 使用统计
```python
def _format_usage(usage: object | None) -> str:
    # 格式化 last/total 的 input_tokens, output_tokens 等字段
```
- 捕获 `ThreadTokenUsageUpdatedNotification` 事件
- 展示单次请求和累计的 Token 使用情况

## 具体技术实现

### 关键流程

1. **启动流程：**
   ```
   Codex.__enter__() 
   -> AppServerClient.start() 
   -> AppServerClient.initialize()
   -> 发送 initialize RPC
   ```

2. **对话流程：**
   ```
   用户输入 -> thread.turn(TextInput(...))
   -> turn_start RPC
   -> 同步流式接收通知
   -> 处理 item/agentMessage/delta（文本片段）
   -> 处理 turn/completed（完成状态）
   ```

3. **事件处理流程：**
   ```python
   for event in turn.stream():
       if event.method == "item/agentMessage/delta":
           # 处理文本增量
       elif isinstance(payload, ThreadTokenUsageUpdatedNotification):
           # 更新 usage 统计
       elif isinstance(payload, TurnCompletedNotification):
           # 获取最终状态
   ```

### 数据结构

**核心类引用：**
- `Codex` - 同步客户端入口（`api.py`）
- `Thread` - 线程操作封装
- `TurnHandle` - 单次对话回合控制
- `TextInput` - 文本输入封装（`_inputs.py`）
- `ThreadTokenUsageUpdatedNotification` - Token 使用通知（`v2_all.py`）
- `TurnCompletedNotification` - 回合完成通知

**事件类型：**
- `item/agentMessage/delta` - AI 消息文本增量
- `thread/tokenUsageUpdated` - Token 使用量更新
- `turn/completed` - 回合完成

### 协议交互

使用 JSON-RPC over stdio 协议与 Codex App Server 通信：

**请求示例：**
```json
{
  "id": "uuid",
  "method": "turn/start",
  "params": {
    "threadId": "...",
    "input": [{"type": "text", "text": "..."}]
  }
}
```

**通知示例：**
```json
{
  "method": "item/agentMessage/delta",
  "params": {
    "delta": "文本片段",
    "itemId": "...",
    "threadId": "...",
    "turnId": "..."
  }
}
```

## 关键代码路径与文件引用

### 本文件关键代码

| 行号 | 代码 | 说明 |
|------|------|------|
| 1-10 | `sys.path` 修改和 `_bootstrap` 导入 | 本地 SDK 源码加载 |
| 12-17 | `codex_app_server` 导入 | 核心 SDK 类 |
| 19 | 欢迎信息打印 | 用户界面提示 |
| 22-23 | `_status_value()` | 状态值提取辅助函数 |
| 26-39 | `_format_usage()` | Token 使用格式化 |
| 42 | `with Codex(...)` | 同步上下文管理 |
| 43 | `thread_start()` | 创建线程 |
| 48 | `input("you> ")` | 同步用户输入 |
| 57 | `thread.turn(TextInput(...))` | 发送消息 |
| 64-77 | `for event in turn.stream()` | 流式响应处理 |

### 与 async.py 的关键差异

| 特性 | sync.py | async.py |
|------|---------|----------|
| 客户端类 | `Codex` | `AsyncCodex` |
| 上下文管理器 | `with` | `async with` |
| 线程类 | `Thread` | `AsyncThread` |
| Turn 句柄 | `TurnHandle` | `AsyncTurnHandle` |
| 流式迭代 | `for ... in` | `async for ... in` |
| 用户输入 | `input()` | `asyncio.to_thread(input)` |
| 初始化检查 | 构造函数中完成 | `_ensure_initialized()` 延迟初始化 |

### 依赖文件路径

```
sdk/python/examples/11_cli_mini_app/sync.py
├── sdk/python/examples/_bootstrap.py          # 启动引导
│   └── sdk/python/examples/_runtime_setup.py  # 运行时设置
├── sdk/python/src/codex_app_server/__init__.py
│   ├── Codex (from api.py)
│   ├── TextInput (from _inputs.py)
│   └── ThreadTokenUsageUpdatedNotification (from generated/v2_all.py)
├── sdk/python/src/codex_app_server/api.py
│   ├── Codex 类
│   ├── Thread 类
│   └── TurnHandle 类
└── sdk/python/src/codex_app_server/client.py
    └── AppServerClient 类（底层同步实现）
```

## 依赖与外部交互

### 外部依赖

1. **Python 标准库：**
   - `sys`, `pathlib` - 路径处理

2. **第三方库：**
   - `pydantic` - 数据模型验证（通过 SDK 间接使用）

3. **Codex 组件：**
   - `codex-cli` 二进制（通过 `codex-cli-bin` 包提供）
   - App Server 进程（stdio 通信）

### 交互流程

```
sync.py
    │
    ├─► _bootstrap.py ──► 设置 sys.path
    │
    ├─► codex_app_server.Codex
    │       │
    │       ├─► AppServerClient
    │       │       │
    │       │       ├─► subprocess.Popen("codex app-server --listen stdio://")
    │       │       │
    │       │       └─► JSON-RPC over stdio
    │       │
    │       ├─► Thread
    │       │       └─► turn_start RPC
    │       │
    │       └─► TurnHandle
    │               └─► stream() → 同步通知流
    │
    └─► 用户终端 I/O
```

### 线程模型

同步版本使用单线程模型：
1. 主线程调用 `input()` 阻塞等待用户输入
2. 后台线程（SDK 内部）通过 `subprocess.Popen` 运行 App Server
3. 通过 `threading.Lock` 保护共享状态
4. `stderr` 由专门的 drain 线程处理

## 风险、边界与改进建议

### 潜在风险

1. **阻塞问题：**
   - `input()` 调用会完全阻塞主线程
   - 无法在等待输入时处理其他事件
   - 无法优雅地处理超时

2. **并发限制：**
   - 与异步版本相同，`acquire_turn_consumer()` 限制单 turn 消费
   - 同步模型下并发能力更受限

3. **异常处理：**
   - EOFError 仅中断输入循环
   - 依赖上下文管理器进行资源清理

### 边界条件

1. **空输入处理：**
   ```python
   if not user_input:
       continue  # 忽略空行
   ```

2. **无文本响应：**
   ```python
   if printed_delta:
       print()
   else:
       print("[no text]")  # 处理空响应
   ```

3. **状态检查：**
   ```python
   if status_text == "failed":
       print("assistant.error>", error)
   ```

4. **EOF 处理：**
   ```python
   try:
       user_input = input("you> ").strip()
   except EOFError:
       break  # 优雅退出
   ```

### 改进建议

1. **非阻塞输入：**
   - 考虑使用 `select` 或 `readline` 实现超时输入
   - 或使用 `threading` 将输入移到后台线程

2. **功能扩展：**
   - 支持多行输入模式（如使用特殊命令进入多行模式）
   - 添加命令历史记录（使用 `readline` 模块）
   - 支持图片输入（使用 `ImageInput`）

3. **用户体验：**
   - 添加打字机效果的延迟控制
   - 支持 Markdown 渲染
   - 添加彩色输出（使用 `rich` 或 `colorama`）

4. **代码优化：**
   ```python
   # 建议：使用结构化日志替代 print
   import logging
   logger = logging.getLogger("codex.cli")
   
   # 建议：添加信号处理优雅退出
   import signal
   def signal_handler(sig, frame):
       # 清理资源
       pass
   signal.signal(signal.SIGINT, signal_handler)
   ```

5. **性能优化：**
   - 添加输出缓冲以减少 flush 次数
   - 考虑使用生成器表达式替代列表操作

### 与异步版本的选型建议

| 场景 | 推荐版本 | 理由 |
|------|----------|------|
| 简单脚本/工具 | sync.py | 代码简单，易于理解 |
| 需要并发处理 | async.py | 支持多个并发对话 |
| Web 服务集成 | async.py | 与异步框架（FastAPI等）兼容 |
| 交互式应用 | async.py | 可在等待输入时处理后台任务 |
| 快速原型 | sync.py | 调试更简单 |

---

**相关文件：**
- 异步版本：`sdk/python/examples/11_cli_mini_app/async.py`
- SDK API 层：`sdk/python/src/codex_app_server/api.py`
- 同步客户端：`sdk/python/src/codex_app_server/client.py`
