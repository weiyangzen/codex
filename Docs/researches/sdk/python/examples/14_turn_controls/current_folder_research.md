# 14_turn_controls 研究文档

## 概述

本文档深入研究 `sdk/python/examples/14_turn_controls` 目录，该示例展示了 Codex App Server Python SDK 中 Turn（对话轮次）的高级控制功能，包括 **Steer（引导）** 和 **Interrupt（中断）** 两种核心控制能力。

---

## 一、场景与职责

### 1.1 定位与目标

`14_turn_controls` 是 Python SDK 示例系列中的高级示例（编号14），专注于展示如何在对话轮次执行过程中进行实时干预控制。与基础的 `thread.run()` 自动完成不同，本示例演示了：

1. **Steer（引导）**：在 Turn 执行过程中发送额外的用户输入，引导模型调整输出方向
2. **Interrupt（中断）**：在 Turn 执行过程中强制终止当前生成

### 1.2 典型使用场景

| 功能 | 场景描述 |
|------|----------|
| **Steer** | 用户发现模型开始生成冗长内容，发送"Keep it brief"引导模型精简输出 |
| **Interrupt** | 用户发现模型开始生成错误方向的内容，立即中断避免浪费 token |

### 1.3 在 SDK 示例体系中的位置

```
01_quickstart_constructor/  → 基础初始化
02_turn_run/               → 基础 Turn 执行
03_turn_stream_events/     → 事件流式消费
...
14_turn_controls/          → Turn 实时控制（本示例）
```

---

## 二、功能点目的

### 2.1 Steer（引导）功能

**目的**：在模型生成过程中动态注入新的用户指令，实现实时引导。

**示例代码**（来自 `async.py` 第24-29行）：
```python
steer_turn = await thread.turn(TextInput("Count from 1 to 40 with commas, then one summary sentence."))
steer_result = "sent"
try:
    _ = await steer_turn.steer(TextInput("Keep it brief and stop after 10 numbers."))
except Exception as exc:
    steer_result = f"skipped {type(exc).__name__}"
```

**关键行为**：
- `steer()` 是 best-effort（尽力而为）操作，可能因 Turn 已完成而失败
- 成功后，模型会收到新的用户输入并调整后续生成
- 需要配合 `stream()` 持续消费事件以观察效果

### 2.2 Interrupt（中断）功能

**目的**：立即停止当前正在进行的 Turn 生成。

**示例代码**（来自 `async.py` 第42-47行）：
```python
interrupt_turn = await thread.turn(TextInput("Count from 1 to 200 with commas, then one summary sentence."))
interrupt_result = "sent"
try:
    _ = await interrupt_turn.interrupt()
except Exception as exc:
    interrupt_result = f"skipped {type(exc).__name__}"
```

**关键行为**：
- `interrupt()` 强制终止 Turn，返回 `TurnInterruptResponse`
- 中断后 Turn 的状态会变为 `interrupted`
- 已生成的内容仍然保留在 Turn 的 items 中

### 2.3 输出指标收集

示例收集了以下指标用于验证控制效果：

```python
print("steer.result:", steer_result)           # steer 调用结果
print("steer.final.status:", steer_completed_status)  # Turn 最终状态
print("steer.events.count:", steer_event_count)       # 收到的事件数量
print("steer.assistant.preview:", steer_preview)      # 助手回复预览
```

---

## 三、具体技术实现

### 3.1 关键流程

#### 3.1.1 Steer 调用流程

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   User Code     │     │   TurnHandle     │     │  AppServerClient│
├─────────────────┤     ├──────────────────┤     ├─────────────────┤
│ turn.steer()    │────→│ steer(input)     │────→│ turn_steer()    │
│                 │     │                  │     │                 │
│                 │     │ _to_wire_input() │     │ JSON-RPC        │
│                 │     │                  │     │ "turn/steer"    │
└─────────────────┘     └──────────────────┘     └─────────────────┘
```

**代码路径**：
- 入口：`sdk/python/src/codex_app_server/api.py:649-650` (TurnHandle.steer)
- 客户端调用：`sdk/python/src/codex_app_server/client.py:372-386` (turn_steer)
- 请求构造：`TurnSteerParams` 模型序列化

#### 3.1.2 Interrupt 调用流程

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   User Code     │     │   TurnHandle     │     │  AppServerClient│
├─────────────────┤     ├──────────────────┤     ├─────────────────┤
│ turn.interrupt()│────→│ interrupt()      │────→│ turn_interrupt()│
│                 │     │                  │     │                 │
│                 │     │                  │     │ JSON-RPC        │
│                 │     │                  │     │ "turn/interrupt"│
└─────────────────┘     └──────────────────┘     └─────────────────┘
```

**代码路径**：
- 入口：`sdk/python/src/codex_app_server/api.py:652-653` (TurnHandle.interrupt)
- 客户端调用：`sdk/python/src/codex_app_server/client.py:365-370` (turn_interrupt)

#### 3.1.3 Stream 事件消费流程

```python
async for event in steer_turn.stream():
    steer_event_count += 1
    if event.method == "turn/completed":
        steer_completed_turn = event.payload.turn
        steer_completed_status = getattr(event.payload.turn.status, "value", str(event.payload.turn.status))
```

**关键事件**：
- `turn/completed`：Turn 完成（正常完成或被中断）
- `item/agentMessage/delta`：助手消息增量
- `item/completed`：单个 item 完成

### 3.2 数据结构

#### 3.2.1 TurnSteerParams（Steer 请求参数）

```python
# sdk/python/src/codex_app_server/generated/v2_all.py:5322-5334
class TurnSteerParams(BaseModel):
    expected_turn_id: Annotated[str, Field(alias="expectedTurnId")]  # 预期的 Turn ID
    input: list[UserInput]                                           # 用户输入列表
    thread_id: Annotated[str, Field(alias="threadId")]              # 线程 ID
```

**说明**：`expected_turn_id` 用于确保操作的是当前活跃的 Turn，防止竞态条件。

#### 3.2.2 TurnSteerResponse（Steer 响应）

```python
# sdk/python/src/codex_app_server/generated/v2_all.py:3327-3331
class TurnSteerResponse(BaseModel):
    turn_id: Annotated[str, Field(alias="turnId")]  # 被引导的 Turn ID
```

#### 3.2.3 TurnInterruptParams / TurnInterruptResponse

```python
# sdk/python/src/codex_app_server/generated/v2_all.py:3299-3311
class TurnInterruptParams(BaseModel):
    thread_id: Annotated[str, Field(alias="threadId")]
    turn_id: Annotated[str, Field(alias="turnId")]

class TurnInterruptResponse(BaseModel):
    pass  # 空响应表示成功
```

#### 3.2.4 TurnStatus（Turn 状态枚举）

```python
# sdk/python/src/codex_app_server/generated/v2_all.py:3320-3325
class TurnStatus(Enum):
    completed = "completed"      # 正常完成
    interrupted = "interrupted"  # 被中断
    failed = "failed"           # 失败
    in_progress = "inProgress"  # 进行中
```

### 3.3 协议与命令

#### 3.3.1 JSON-RPC 方法

| 方法 | 方向 | 用途 |
|------|------|------|
| `turn/steer` | Client → Server | 向活跃 Turn 发送额外输入 |
| `turn/interrupt` | Client → Server | 中断活跃 Turn |
| `turn/completed` | Server → Client | Turn 完成通知 |

#### 3.3.2 Wire 格式示例

**Steer 请求**：
```json
{
  "id": "uuid",
  "method": "turn/steer",
  "params": {
    "threadId": "thread-xxx",
    "expectedTurnId": "turn-yyy",
    "input": [{"type": "text", "text": "Keep it brief."}]
  }
}
```

**Interrupt 请求**：
```json
{
  "id": "uuid",
  "method": "turn/interrupt",
  "params": {
    "threadId": "thread-xxx",
    "turnId": "turn-yyy"
  }
}
```

---

## 四、关键代码路径与文件引用

### 4.1 示例文件

| 文件 | 职责 |
|------|------|
| `sdk/python/examples/14_turn_controls/sync.py` | 同步 API 演示 |
| `sdk/python/examples/14_turn_controls/async.py` | 异步 API 演示 |

### 4.2 SDK 核心实现

| 文件 | 关键类/方法 | 职责 |
|------|------------|------|
| `sdk/python/src/codex_app_server/api.py:643-685` | `TurnHandle` | 同步 Turn 控制句柄 |
| `sdk/python/src/codex_app_server/api.py:687-735` | `AsyncTurnHandle` | 异步 Turn 控制句柄 |
| `sdk/python/src/codex_app_server/client.py:365-370` | `turn_interrupt()` | 底层中断 RPC 调用 |
| `sdk/python/src/codex_app_server/client.py:372-386` | `turn_steer()` | 底层引导 RPC 调用 |
| `sdk/python/src/codex_app_server/async_client.py:145-159` | `turn_steer()` / `turn_interrupt()` | 异步包装 |

### 4.3 生成模型

| 文件 | 关键模型 | 职责 |
|------|---------|------|
| `sdk/python/src/codex_app_server/generated/v2_all.py:5322-5334` | `TurnSteerParams` | Steer 请求参数 |
| `sdk/python/src/codex_app_server/generated/v2_all.py:3327-3331` | `TurnSteerResponse` | Steer 响应 |
| `sdk/python/src/codex_app_server/generated/v2_all.py:3299-3305` | `TurnInterruptParams` | Interrupt 请求参数 |
| `sdk/python/src/codex_app_server/generated/v2_all.py:3307-3311` | `TurnInterruptResponse` | Interrupt 响应 |
| `sdk/python/src/codex_app_server/generated/v2_all.py:3320-3325` | `TurnStatus` | Turn 状态枚举 |

### 4.4 输入处理

| 文件 | 关键函数 | 职责 |
|------|---------|------|
| `sdk/python/src/codex_app_server/_inputs.py:40-51` | `_to_wire_item()` | 输入项序列化 |
| `sdk/python/src/codex_app_server/_inputs.py:54-57` | `_to_wire_input()` | 输入列表序列化 |

---

## 五、依赖与外部交互

### 5.1 内部依赖

```
14_turn_controls/async.py
    ├── _bootstrap.py (示例基础设施)
    │   ├── ensure_local_sdk_src()
    │   ├── runtime_config()
    │   └── assistant_text_from_turn()
    └── codex_app_server (SDK 主包)
        ├── AsyncCodex (异步客户端)
        ├── TextInput (输入类型)
        └── 内部模块...
```

### 5.2 SDK 架构依赖

```
codex_app_server
├── api.py (高层 API: Codex, Thread, TurnHandle)
├── client.py (同步 JSON-RPC 客户端)
├── async_client.py (异步包装)
├── _inputs.py (输入处理)
├── _run.py (结果收集)
├── models.py (核心模型)
├── generated/v2_all.py (生成协议模型)
└── errors.py (异常定义)
```

### 5.3 外部运行时依赖

| 依赖 | 用途 |
|------|------|
| `codex-cli-bin` | 本地 Codex 运行时二进制 |
| `pydantic` | 模型验证与序列化 |
| Python >= 3.10 | 类型注解支持 |

### 5.4 进程间通信

SDK 通过 **stdio JSON-RPC** 与 `codex app-server` 进程通信：

```python
# sdk/python/src/codex_app_server/client.py:178-187
self._proc = subprocess.Popen(
    args,
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    cwd=self.config.cwd,
    env=env,
    bufsize=1,
)
```

---

## 六、风险、边界与改进建议

### 6.1 已知限制与风险

#### 6.1.1 单消费者限制（重要）

```python
# sdk/python/src/codex_app_server/client.py:288-296
def acquire_turn_consumer(self, turn_id: str) -> None:
    with self._turn_consumer_lock:
        if self._active_turn_consumer is not None:
            raise RuntimeError(
                "Concurrent turn consumers are not yet supported in the experimental SDK. "
                f"Client is already streaming turn {self._active_turn_consumer!r}; "
                f"cannot start turn {turn_id!r} until the active consumer finishes."
            )
        self._active_turn_consumer = turn_id
```

**影响**：同一时间只能有一个 `stream()`、`run()` 或 `thread.run()` 处于活跃状态。

#### 6.1.2 Steer 的 Best-Effort 特性

Steer 调用可能失败的情况：
- Turn 在 steer 调用前已完成
- Turn 已被中断
- 网络或服务器错误

**代码中的处理**：
```python
try:
    _ = await steer_turn.steer(TextInput("Keep it brief..."))
except Exception as exc:
    steer_result = f"skipped {type(exc).__name__}"
```

#### 6.1.3 竞态条件

`expected_turn_id` 参数用于防止以下竞态：
1. 用户调用 `steer()`
2. Turn 在传输过程中完成
3. 新的 Turn 开始
4. Steer 错误地应用到新 Turn

### 6.2 边界情况

| 场景 | 行为 |
|------|------|
| Steer 已完成的 Turn | 抛出异常，示例中捕获并记录 |
| Interrupt 已完成的 Turn | 可能无操作或抛出异常 |
| 多次 Steer 同一 Turn | 支持，每次都会追加输入 |
| Steer 后立即 Interrupt | 取决于服务器状态，可能 steer 未生效 |
| Stream 未消费完成 | 阻塞后续 Turn 操作（单消费者限制） |

### 6.3 改进建议

#### 6.3.1 SDK 层面

1. **支持并发消费者**：移除单消费者限制，实现真正的多路复用
   ```python
   # 建议：基于 turn_id 的事件路由
   def _route_notification(self, notification: Notification) -> None:
       turn_id = self._extract_turn_id(notification)
       if turn_id and turn_id in self._active_streams:
           self._active_streams[turn_id].put(notification)
   ```

2. **Steer 超时控制**：添加可选超时参数
   ```python
   steer(input, timeout_ms=5000)  # 5秒超时
   ```

3. **更细粒度的状态查询**：
   ```python
   turn.get_status()  # 实时查询 Turn 状态
   ```

#### 6.3.2 示例层面

1. **添加更多控制场景**：
   - 多次 steer 的累积效果
   - steer 与工具调用的交互
   - 中断后的恢复策略

2. **可视化输出**：
   ```python
   # 实时显示 token 使用量
   if event.method == "thread/tokenUsage/updated":
       print(f"Tokens: {event.payload.token_usage.total.total_tokens}")
   ```

3. **错误重试示例**：
   ```python
   from codex_app_server import retry_on_overload
   
   @retry_on_overload
   async def steer_with_retry(turn, input):
       return await turn.steer(input)
   ```

#### 6.3.3 文档层面

1. **添加序列图**：清晰展示 steer/interrupt 的时序关系
2. **状态机文档**：Turn 状态转换图
3. **性能指南**：steer 的延迟预期、最佳实践

### 6.4 测试建议

```python
# 建议添加的测试用例

async def test_steer_affects_generation():
    """验证 steer 确实影响生成内容"""
    pass

async def test_interrupt_stops_generation():
    """验证 interrupt 立即停止生成"""
    pass

async def test_steer_after_completion_fails():
    """验证对已完成的 Turn steer 会失败"""
    pass

async def test_concurrent_steer_safety():
    """验证并发 steer 的安全性"""
    pass
```

---

## 七、总结

`14_turn_controls` 示例展示了 Codex Python SDK 的高级控制能力：

1. **Steer** 提供了在生成过程中动态干预的能力，适用于实时引导场景
2. **Interrupt** 提供了紧急停止能力，适用于错误方向的内容生成
3. 两者都基于 JSON-RPC over stdio 协议，通过 `TurnHandle` / `AsyncTurnHandle` 暴露

当前实现为实验性质，存在单消费者限制，但在单 Turn 场景下已具备实用价值。后续演进应关注并发支持、更细粒度的状态控制和更好的错误恢复机制。
