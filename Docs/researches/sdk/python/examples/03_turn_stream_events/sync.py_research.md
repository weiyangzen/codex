# Research: sdk/python/examples/03_turn_stream_events/sync.py

## 场景与职责

本文件是 Codex Python SDK 的**同步流式事件处理示例**，演示如何通过同步 API 与 Codex App Server 交互，实现实时的 Turn（对话轮次）流式事件监听与处理。该示例与 `async.py` 功能完全对等，但采用同步编程模型，适用于不需要异步特性的简单脚本或集成到现有同步代码库的场景。

**核心场景**：
- 同步建立与 Codex App Server 的连接
- 创建 Thread 并启动一个 Turn
- 通过同步迭代器实时接收和处理流式事件（stream events）
- 解析不同类型的通知（Notification）如 turn/started、item/agentMessage/delta、turn/completed
- 处理增量文本输出（delta streaming）实现打字机效果

## 功能点目的

### 1. 同步上下文管理
使用 `with Codex(config=runtime_config()) as codex:` 模式确保资源正确初始化和释放，避免连接泄漏。相比异步版本，代码更简洁直观。

### 2. 实时流式输出
通过 `turn.stream()` 获取同步事件流，实现类似 ChatGPT 的逐字输出效果。同步生成器通过 `yield` 实现惰性求值，内存占用低。

### 3. 事件类型识别与处理
示例中处理三类核心事件：
- `turn/started`: Turn 开始信号，标记流式会话启动
- `item/agentMessage/delta`: 助手消息的增量文本片段，实现实时打字效果
- `turn/completed`: Turn 完成信号，携带最终状态（completed/interrupted/failed）

### 4. 降级处理机制
当流式输出未收到任何 delta 时（`saw_delta=False`），示例展示如何从持久化存储中读取完整 Turn 数据作为降级方案。这在某些模型或配置不输出增量令牌时尤为重要。

### 5. 诊断信息收集
统计并输出事件总数、各阶段状态标志，便于调试和性能分析。

## 具体技术实现

### 关键流程

```
1. 初始化阶段
   ├── 调用 ensure_local_sdk_src() 确保 SDK 在 sys.path
   ├── runtime_config() 创建 AppServerConfig
   └── with Codex(config) 建立连接并初始化

2. Thread 创建
   ├── codex.thread_start(model="gpt-5.4", config={...})
   └── 返回 Thread 对象

3. Turn 启动
   ├── thread.turn(TextInput("Explain SIMD in 3 short bullets."))
   └── 返回 TurnHandle 对象

4. 事件流处理（核心逻辑）
   ├── for event in turn.stream():
   │   ├── event.method == "turn/started" → 设置 saw_started=True
   │   ├── event.method == "item/agentMessage/delta" → 提取并打印 delta
   │   └── event.method == "turn/completed" → 提取最终状态
   └── 流结束自动释放 turn consumer

5. 降级读取（如无 delta）
   ├── thread.read(include_turns=True)
   ├── find_turn_by_id(persisted.thread.turns, turn.id)
   └── assistant_text_from_turn(persisted_turn) 提取完整文本

6. 诊断输出
   └── 打印 stream.started.seen, stream.completed, events.count
```

### 数据结构

**核心类与类型**（来自 `codex_app_server`）：

| 类/类型 | 来源文件 | 作用 |
|---------|----------|------|
| `Codex` | `api.py:69` | 同步 SDK 主入口，包装 AppServerClient |
| `Thread` | `api.py:467` | 线程对象，包含 turn() 方法 |
| `TurnHandle` | `api.py:643` | Turn 句柄，提供 stream() 生成器 |
| `TextInput` | `_inputs.py` | 用户文本输入包装类 |
| `Notification` | `models.py:85` | 事件通知基类，包含 method 和 payload |
| `TurnCompletedNotification` | `generated/v2_all.py:5210` | Turn 完成通知载荷 |
| `AgentMessageDeltaNotification` | `generated/v2_all.py:45` | 增量消息通知载荷 |

**事件流状态跟踪变量**：
```python
event_count = 0       # 总事件计数器
saw_started = False   # 是否收到 turn/started
saw_delta = False     # 是否收到任何 agentMessage/delta
completed_status = "unknown"  # Turn 最终状态
```

### 协议与命令

**JSON-RPC over stdio 协议**：
- 底层通过 `AppServerClient` 与 `codex app-server --listen stdio://` 子进程通信
- 使用 `turn/start` RPC 方法启动 Turn
- 通过 `next_notification()` 循环读取服务器推送的通知

**关键 RPC 方法**：
| 方法 | 方向 | 用途 |
|------|------|------|
| `thread/start` | Client → Server | 创建新线程 |
| `turn/start` | Client → Server | 启动对话轮次 |
| `thread/read` | Client → Server | 读取线程状态（含历史 Turn）|
| `turn/started` | Server → Client | 通知 Turn 已开始 |
| `item/agentMessage/delta` | Server → Client | 推送增量文本 |
| `turn/completed` | Server → Client | 通知 Turn 已完成 |

**并发控制**：
- `acquire_turn_consumer()` / `release_turn_consumer()` 确保单 Turn 消费（`api.py:656-657` 有 TODO 注释说明这是实验性限制）
- `threading.Lock` 保证 stdio 传输的线程安全（`client.py:147`）

### 关键代码路径

**事件流生成器实现**（`api.py:655-669`）：
```python
def stream(self) -> Iterator[Notification]:
    # TODO: replace this client-wide experimental guard with per-turn event demux.
    self._client.acquire_turn_consumer(self.id)  # 获取消费锁
    try:
        while True:
            event = self._client.next_notification()
            yield event
            if (event.method == "turn/completed" and 
                isinstance(event.payload, TurnCompletedNotification) and
                event.payload.turn.id == self.id):
                break
    finally:
        self._client.release_turn_consumer(self.id)  # 释放锁
```

**增量文本提取逻辑**（本示例第 34-40 行）：
```python
if event.method == "item/agentMessage/delta":
    delta = getattr(event.payload, "delta", "")
    if delta:
        if not saw_delta:
            print("assistant> ", end="", flush=True)  # 首次输出前缀
        print(delta, end="", flush=True)  # 无换行实时输出
        saw_delta = True
```

**状态提取逻辑**（本示例第 42-43 行）：
```python
if event.method == "turn/completed":
    completed_status = getattr(event.payload.turn.status, "value", 
                               str(event.payload.turn.status))
```

**降级读取逻辑**（本示例第 47-51 行）：
```python
if saw_delta:
    print()
else:
    persisted = thread.read(include_turns=True)
    persisted_turn = find_turn_by_id(persisted.thread.turns, turn.id)
    final_text = assistant_text_from_turn(persisted_turn).strip() or "[no assistant text]"
    print("assistant>", final_text)
```

## 依赖与外部交互

### 内部依赖

| 依赖项 | 路径 | 说明 |
|--------|------|------|
| `_bootstrap` | `examples/_bootstrap.py` | 示例基础设施，提供运行时配置和工具函数 |
| `codex_app_server` | `src/codex_app_server/` | SDK 主包，包含同步客户端和模型定义 |

### _bootstrap 提供的工具函数

```python
ensure_local_sdk_src()      # 确保 SDK 源码在 sys.path 中
runtime_config()            # 返回 AppServerConfig 实例
find_turn_by_id(turns, id)  # 在 Turn 列表中按 ID 查找
assistant_text_from_turn(turn)  # 从 Turn 对象提取助手回复文本
```

### 外部进程交互

**Codex CLI 二进制**：
- 通过 `AppServerConfig` 配置（默认自动发现 `codex-cli-bin` 包中的捆绑二进制）
- 启动命令：`codex app-server --listen stdio://`
- 通信方式：JSON-RPC over stdio（stdin/stdout）
- 子进程 stderr 被重定向到环形缓冲区用于调试（`client.py:485-500`）

**子进程生命周期管理**（`client.py:161-207`）：
```python
def start(self) -> None:
    # 解析 codex 二进制路径
    codex_bin = _resolve_codex_bin(self.config)
    args = [str(codex_bin), "app-server", "--listen", "stdio://"]
    
    # 启动子进程
    self._proc = subprocess.Popen(
        args,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    
    # 启动 stderr  drain 线程
    self._start_stderr_drain_thread()

def close(self) -> None:
    # 优雅关闭：先 terminate，超时后 kill
    proc.terminate()
    proc.wait(timeout=2)
    # 或 proc.kill() 强制终止
```

### 环境要求

- Python 3.9+（使用类型注解、联合类型语法 `|` 等特性）
- pydantic（用于模型验证）
- 本地安装 `codex-cli-bin` 或配置 `AppServerConfig.codex_bin` 指向二进制

## 风险、边界与改进建议

### 已知限制

1. **单 Turn 消费限制**（`api.py:656-657`）
   - 当前实现使用 client-wide 锁限制并发 Turn 消费
   - TODO 注释表明需要替换为 per-turn 事件多路复用
   - 尝试并发 stream 多个 Turn 会抛出 RuntimeError

2. **事件丢失风险**
   - 如果在 `turn.stream()` 之外调用其他 API 方法，可能从通知队列中"偷走"属于该 Turn 的事件
   - 示例中通过 `acquire_turn_consumer` 机制部分缓解，但仍需注意

3. **阻塞风险**
   - 同步 API 在 `next_notification()` 处阻塞等待服务器响应
   - 长时间运行的 Turn 会阻塞整个线程
   - 不适合需要并发处理多个 Turn 的场景

### 边界情况

| 场景 | 当前行为 | 建议 |
|------|----------|------|
| 零 delta 输出 | 降级到 `thread.read()` 读取完整文本 | 已妥善处理 |
| Turn 失败 | 仅记录 status，不抛出异常 | 应检查 `turn.status == "failed"` 并处理错误 |
| 连接中断 | 抛出 TransportClosedError | 应添加重试逻辑 |
| 大文本流 | 逐字输出可能导致性能问题 | 考虑缓冲一定量后再输出 |
| 用户中断（Ctrl+C） | 抛出 KeyboardInterrupt，可能未清理资源 | 应添加信号处理确保关闭子进程 |

### 改进建议

1. **错误处理增强**
```python
# 建议添加的错误检查
if event.method == "turn/completed":
    turn = event.payload.turn
    if turn.status.value == "failed":
        raise TurnFailedError(turn.error.message if turn.error else "Unknown error")
```

2. **信号处理**
```python
# 建议添加的信号处理确保资源清理
import signal

def signal_handler(sig, frame):
    codex.close()
    sys.exit(0)

signal.signal(signal.SIGINT, signal_handler)
```

3. **结构化日志**
- 当前使用 print 输出诊断信息
- 建议替换为 logging 模块，便于生产环境集成

4. **超时控制**
```python
# 建议添加超时（需要配合 select 或线程实现）
import select
if not select.select([codex._client._proc.stdout], [], [], timeout)[0]:
    raise TimeoutError("No event received within timeout")
```

5. **背压处理**
- 当前示例直接打印每个 delta
- 高频 delta 场景下应考虑输出缓冲或采样

### 与异步版本的对比

| 特性 | sync.py（本文件） | async.py（同目录） |
|------|-------------------|-------------------|
| 客户端类 | `Codex` | `AsyncCodex` |
| 上下文管理 | `with` | `async with` |
| 流式迭代 | `for` | `async for` |
| 线程安全 | threading.Lock | asyncio.Lock + 线程 offloading |
| 并发能力 | 单线程阻塞 | 支持并发 Turn（受锁限制） |
| 代码复杂度 | 简单直观 | 稍复杂但功能更强 |
| 适用场景 | 简单脚本、同步代码库 | 高并发、异步框架集成 |

两个版本逻辑完全一致，仅 API 风格不同，体现了 SDK 的"功能对等"设计原则。选择哪个版本取决于具体应用场景：
- 简单 CLI 工具或脚本 → 同步版本
- Web 服务、高并发应用 → 异步版本
