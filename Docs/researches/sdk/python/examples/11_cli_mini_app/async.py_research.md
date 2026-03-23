# async.py 研究文档

## 场景与职责

`async.py` 是 Codex Python SDK 的异步版本 CLI 迷你应用示例，展示了如何使用异步 API 与 Codex App Server 进行交互。该示例实现了一个简单的命令行聊天界面，用户可以输入文本，AI 助手会流式返回响应。

**核心职责：**
- 演示 `AsyncCodex` 异步客户端的使用模式
- 展示异步上下文管理器 (`async with`) 的正确使用
- 实现流式响应的异步处理
- 提供 Token 使用统计的格式化展示

## 功能点目的

### 1. 异步客户端初始化
使用 `async with AsyncCodex(config=runtime_config()) as codex` 模式确保资源正确初始化和释放：
- 自动处理连接建立和初始化握手
- 确保异常时正确关闭连接
- 支持并发操作（通过内部的 `_transport_lock`）

### 2. 线程管理
```python
thread = await codex.thread_start(model="gpt-5.4", config={"model_reasoning_effort": "high"})
```
- 创建新对话线程
- 配置模型参数（如 reasoning effort）

### 3. 异步用户输入
```python
user_input = (await asyncio.to_thread(input, "you> ")).strip()
```
- 使用 `asyncio.to_thread` 将阻塞的 `input()` 转换为异步操作
- 避免阻塞事件循环

### 4. 流式响应处理
```python
async for event in turn.stream():
    payload = event.payload
    if event.method == "item/agentMessage/delta":
        delta = getattr(payload, "delta", "")
        if delta:
            print(delta, end="", flush=True)
```
- 异步迭代事件流
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
   AsyncCodex.__aenter__() 
   -> AsyncAppServerClient.start() 
   -> AsyncAppServerClient.initialize()
   -> 发送 initialize RPC
   ```

2. **对话流程：**
   ```
   用户输入 -> thread.turn(TextInput(...))
   -> turn_start RPC
   -> 异步流式接收通知
   -> 处理 item/agentMessage/delta（文本片段）
   -> 处理 turn/completed（完成状态）
   ```

3. **事件处理流程：**
   ```python
   async for event in turn.stream():
       if event.method == "item/agentMessage/delta":
           # 处理文本增量
       elif isinstance(payload, ThreadTokenUsageUpdatedNotification):
           # 更新 usage 统计
       elif isinstance(payload, TurnCompletedNotification):
           # 获取最终状态
   ```

### 数据结构

**核心类引用：**
- `AsyncCodex` - 异步客户端入口（`api.py`）
- `AsyncThread` - 线程操作封装
- `AsyncTurnHandle` - 单次对话回合控制
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
| 14-19 | `codex_app_server` 导入 | 核心 SDK 类 |
| 42-45 | `async with AsyncCodex(...)` | 异步上下文管理 |
| 46 | `thread_start()` | 创建线程 |
| 51 | `asyncio.to_thread(input, ...)` | 异步用户输入 |
| 60 | `thread.turn(TextInput(...))` | 发送消息 |
| 67-81 | `async for event in turn.stream()` | 流式响应处理 |

### 依赖文件路径

```
sdk/python/examples/11_cli_mini_app/async.py
├── sdk/python/examples/_bootstrap.py          # 启动引导
│   └── sdk/python/examples/_runtime_setup.py  # 运行时设置
├── sdk/python/src/codex_app_server/__init__.py
│   ├── AsyncCodex (from api.py)
│   ├── TextInput (from _inputs.py)
│   └── ThreadTokenUsageUpdatedNotification (from generated/v2_all.py)
├── sdk/python/src/codex_app_server/api.py
│   ├── AsyncCodex 类
│   ├── AsyncThread 类
│   └── AsyncTurnHandle 类
├── sdk/python/src/codex_app_server/async_client.py
│   └── AsyncAppServerClient 类
└── sdk/python/src/codex_app_server/client.py
    └── AppServerClient 类（底层同步实现）
```

## 依赖与外部交互

### 外部依赖

1. **Python 标准库：**
   - `asyncio` - 异步编程核心
   - `sys`, `pathlib` - 路径处理

2. **第三方库：**
   - `pydantic` - 数据模型验证（通过 SDK 间接使用）

3. **Codex 组件：**
   - `codex-cli` 二进制（通过 `codex-cli-bin` 包提供）
   - App Server 进程（stdio 通信）

### 交互流程

```
async.py
    │
    ├─► _bootstrap.py ──► 设置 sys.path
    │
    ├─► codex_app_server.AsyncCodex
    │       │
    │       ├─► AsyncAppServerClient
    │       │       │
    │       │       ├─► subprocess.Popen("codex app-server --listen stdio://")
    │       │       │
    │       │       └─► JSON-RPC over stdio
    │       │
    │       ├─► AsyncThread
    │       │       └─► turn_start RPC
    │       │
    │       └─► AsyncTurnHandle
    │               └─► stream() → 异步通知流
    │
    └─► 用户终端 I/O
```

## 风险、边界与改进建议

### 潜在风险

1. **并发限制：**
   - `acquire_turn_consumer()` 限制同时只能有一个活跃的 turn 消费者
   - 尝试并发处理多个 turn 会抛出 `RuntimeError`

2. **异常处理：**
   - EOFError 仅中断输入循环，不会清理资源（依赖上下文管理器）
   - 网络或进程异常可能导致 `TransportClosedError`

3. **资源泄漏：**
   - 如果 `turn.stream()` 迭代中途被中断，可能丢失后续通知
   - 没有显式的 turn 取消机制

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

### 改进建议

1. **错误恢复：**
   - 添加连接断开后的重连逻辑
   - 实现指数退避重试

2. **功能扩展：**
   - 支持多行输入模式
   - 添加命令历史记录
   - 支持图片输入（使用 `ImageInput`）

3. **用户体验：**
   - 添加打字机效果的延迟控制
   - 支持 Markdown 渲染
   - 添加彩色输出

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
   - 考虑使用 `aioconsole` 替代 `asyncio.to_thread(input)` 以获得更好的异步输入体验
   - 添加输出缓冲以减少 flush 次数

---

**相关文件：**
- 同步版本：`sdk/python/examples/11_cli_mini_app/sync.py`
- SDK API 层：`sdk/python/src/codex_app_server/api.py`
- 异步客户端：`sdk/python/src/codex_app_server/async_client.py`
