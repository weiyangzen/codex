# Research: sdk/python/examples/03_turn_stream_events/async.py

## 场景与职责

本文件是 Codex Python SDK 的**异步流式事件处理示例**，演示如何通过异步 API 与 Codex App Server 交互，实现实时的 Turn（对话轮次）流式事件监听与处理。该示例属于 SDK 示例系列的第 3 个示例（03_turn_stream_events），专注于展示事件驱动架构中的流式响应处理模式。

**核心场景**：
- 异步建立与 Codex App Server 的连接
- 创建 Thread 并启动一个 Turn
- 通过异步迭代器实时接收和处理流式事件（stream events）
- 解析不同类型的通知（Notification）如 turn/started、item/agentMessage/delta、turn/completed
- 处理增量文本输出（delta streaming）实现打字机效果

## 功能点目的

### 1. 异步上下文管理
使用 `async with AsyncCodex(config=runtime_config()) as codex:` 模式确保资源正确初始化和释放，避免连接泄漏。

### 2. 实时流式输出
通过 `turn.stream()` 获取异步事件流，实现类似 ChatGPT 的逐字输出效果，提升用户体验。

### 3. 事件类型识别与处理
示例中处理三类核心事件：
- `turn/started`: Turn 开始信号
- `item/agentMessage/delta`: 助手消息的增量文本片段
- `turn/completed`: Turn 完成信号，携带最终状态

### 4. 降级处理机制
当流式输出未收到任何 delta 时（`saw_delta=False`），示例展示如何从持久化存储中读取完整 Turn 数据作为降级方案。

### 5. 诊断信息收集
统计并输出事件总数、各阶段状态标志，便于调试和性能分析。

## 具体技术实现

### 关键流程

```
1. 初始化阶段
   ├── 调用 ensure_local_sdk_src() 确保 SDK 在 sys.path
   ├── runtime_config() 创建 AppServerConfig
   └── async with AsyncCodex(config) 建立连接并初始化

2. Thread 创建
   ├── codex.thread_start(model="gpt-5.4", config={...})
   └── 返回 AsyncThread 对象

3. Turn 启动
   ├── thread.turn(TextInput("Explain SIMD in 3 short bullets."))
   └── 返回 AsyncTurnHandle 对象

4. 事件流处理（核心逻辑）
   ├── async for event in turn.stream():
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
| `AsyncCodex` | `api.py:270` | 异步 SDK 主入口，包装 AsyncAppServerClient |
| `AsyncThread` | `api.py:551` | 线程对象，包含 turn() 方法 |
| `AsyncTurnHandle` | `api.py:687` | Turn 句柄，提供 stream() 异步生成器 |
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
- 底层通过 `AsyncAppServerClient` 与 `codex app-server --listen stdio://` 子进程通信
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
- `acquire_turn_consumer()` / `release_turn_consumer()` 确保单 Turn 消费（`api.py:708` 有 TODO 注释说明这是实验性限制）
- `asyncio.Lock` 保证 stdio 传输的线程安全（`async_client.py:45`）

### 关键代码路径

**事件流生成器实现**（`api.py:705-720`）：
```python
async def stream(self) -> AsyncIterator[Notification]:
    await self._codex._ensure_initialized()
    self._codex._client.acquire_turn_consumer(self.id)  # 获取消费锁
    try:
        while True:
            event = await self._codex._client.next_notification()
            yield event
            if (event.method == "turn/completed" and 
                event.payload.turn.id == self.id):
                break
    finally:
        self._codex._client.release_turn_consumer(self.id)  # 释放锁
```

**增量文本提取逻辑**（本示例第 38-44 行）：
```python
if event.method == "item/agentMessage/delta":
    delta = getattr(event.payload, "delta", "")
    if delta:
        if not saw_delta:
            print("assistant> ", end="", flush=True)  # 首次输出前缀
        print(delta, end="", flush=True)  # 无换行实时输出
        saw_delta = True
```

**状态提取逻辑**（本示例第 46-47 行）：
```python
if event.method == "turn/completed":
    completed_status = getattr(event.payload.turn.status, "value", 
                               str(event.payload.turn.status))
```

## 依赖与外部交互

### 内部依赖

| 依赖项 | 路径 | 说明 |
|--------|------|------|
| `_bootstrap` | `examples/_bootstrap.py` | 示例基础设施，提供运行时配置和工具函数 |
| `codex_app_server` | `src/codex_app_server/` | SDK 主包，包含异步客户端和模型定义 |

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

### 环境要求

- Python 3.9+（使用 `asyncio.to_thread` 等特性）
- pydantic（用于模型验证）
- 本地安装 `codex-cli-bin` 或配置 `AppServerConfig.codex_bin` 指向二进制

## 风险、边界与改进建议

### 已知限制

1. **单 Turn 消费限制**（`api.py:656-657, 707-708`）
   - 当前实现使用 client-wide 锁限制并发 Turn 消费
   - TODO 注释表明需要替换为 per-turn 事件多路复用
   - 尝试并发 stream 多个 Turn 会抛出 RuntimeError

2. **事件丢失风险**
   - 如果在 `turn.stream()` 之外调用其他 API 方法，可能从通知队列中"偷走"属于该 Turn 的事件
   - 示例中通过 `acquire_turn_consumer` 机制部分缓解，但仍需注意

3. **超时处理缺失**
   - 示例未展示如何处理 Turn 长时间无响应或挂起的情况
   - 生产环境应添加 `asyncio.wait_for` 包装

### 边界情况

| 场景 | 当前行为 | 建议 |
|------|----------|------|
| 零 delta 输出 | 降级到 `thread.read()` 读取完整文本 | 已妥善处理 |
| Turn 失败 | 仅记录 status，不抛出异常 | 应检查 `turn.status == "failed"` 并处理错误 |
| 连接中断 | 抛出 TransportClosedError | 应添加重试逻辑 |
| 大文本流 | 逐字输出可能导致性能问题 | 考虑缓冲一定量后再输出 |

### 改进建议

1. **错误处理增强**
```python
# 建议添加的错误检查
if event.method == "turn/completed":
    turn = event.payload.turn
    if turn.status.value == "failed":
        raise TurnFailedError(turn.error.message if turn.error else "Unknown error")
```

2. **超时控制**
```python
# 建议添加超时
async with asyncio.timeout(60):
    async for event in turn.stream():
        ...
```

3. **结构化日志**
- 当前使用 print 输出诊断信息
- 建议替换为 logging 模块，便于生产环境集成

4. **背压处理**
- 当前示例直接打印每个 delta
- 高频 delta 场景下应考虑输出缓冲或采样

5. **资源清理保证**
- 虽然 `async with` 和 `finally` 提供了基本保证
- 建议在 SIGINT/SIGTERM 信号处理中添加优雅关闭

### 与同步版本的对比

| 特性 | async.py（本文件） | sync.py（同目录） |
|------|-------------------|-------------------|
| 客户端类 | `AsyncCodex` | `Codex` |
| 上下文管理 | `async with` | `with` |
| 流式迭代 | `async for` | `for` |
| 线程安全 | asyncio.Lock + 线程 offloading | threading.Lock |
| 适用场景 | 高并发、异步框架集成 | 简单脚本、同步代码库 |

两个版本逻辑完全一致，仅 API 风格不同，体现了 SDK 的"功能对等"设计原则。
