# sdk/python/src/codex_app_server/_run.py 研究文档

## 场景与职责

`_run.py` 是 Codex Python SDK 的**运行结果处理模块**，负责处理 Turn 执行过程中的事件流收集和结果组装。作为内部模块，它提供：

1. **事件流收集**：从通知流中收集与特定 Turn 相关的所有事件
2. **结果组装**：将分散的事件组装为统一的 `RunResult` 对象
3. **同步/异步双版本**：提供同步和异步两种实现，匹配 SDK 的整体架构
4. **错误处理**：检测 Turn 失败状态并抛出适当的异常

## 功能点目的

### 1. RunResult 数据类

```python
@dataclass(slots=True)
class RunResult:
    final_response: str | None    # 最终助手回复文本
    items: list[ThreadItem]       # 所有完成的 ThreadItem
    usage: ThreadTokenUsage | None  # Token 使用统计
```

### 2. 事件流收集函数

| 函数 | 用途 | 返回 |
|-----|------|------|
| `_collect_run_result` | 同步收集 Turn 事件流 | `RunResult` |
| `_collect_async_run_result` | 异步收集 Turn 事件流 | `RunResult` |

### 3. 辅助函数

- `_agent_message_item_from_thread_item()`：从 ThreadItem 中提取 AgentMessage
- `_final_assistant_response_from_items()`：从 items 列表中提取最终回复
- `_raise_for_failed_turn()`：检查 Turn 状态，失败时抛出 RuntimeError

## 具体技术实现

### 事件流处理流程

```
Turn 开始
    ↓
stream() / stream() async
    ↓
收集事件流中的通知：
  - ItemCompletedNotification (匹配 turn_id)
  - ThreadTokenUsageUpdatedNotification (匹配 turn_id)
  - TurnCompletedNotification (匹配 turn.id)
    ↓
验证 Turn 状态
    ↓
组装 RunResult
```

### 关键数据结构

**事件匹配逻辑：**
```python
for event in stream:
    payload = event.payload
    
    # 收集完成的 Item
    if isinstance(payload, ItemCompletedNotification) and payload.turn_id == turn_id:
        items.append(payload.item)
        continue
    
    # 收集 Token 使用统计
    if isinstance(payload, ThreadTokenUsageUpdatedNotification) and payload.turn_id == turn_id:
        usage = payload.token_usage
        continue
    
    # 检测 Turn 完成
    if isinstance(payload, TurnCompletedNotification) and payload.turn.id == turn_id:
        completed = payload
```

### 最终回复提取算法

```python
def _final_assistant_response_from_items(items: list[ThreadItem]) -> str | None:
    last_unknown_phase_response: str | None = None
    
    for item in reversed(items):  # 从后向前遍历
        agent_message = _agent_message_item_from_thread_item(item)
        if agent_message is None:
            continue
        
        # 优先返回明确标记为 final_answer 的消息
        if agent_message.phase == MessagePhase.final_answer:
            return agent_message.text
        
        # 记录第一个（从后数）无 phase 标记的消息作为备选
        if agent_message.phase is None and last_unknown_phase_response is None:
            last_unknown_phase_response = agent_message.text
    
    return last_unknown_phase_response
```

**算法特点：**
1. **倒序遍历**：优先找到最新的助手消息
2. **Phase 感知**：明确识别 `final_answer` phase 的消息
3. **降级策略**：无 phase 标记的消息作为备选
4. **忽略 commentary**：`commentary` phase 的消息不会作为最终回复

### 错误处理

```python
def _raise_for_failed_turn(turn: AppServerTurn) -> None:
    if turn.status != TurnStatus.failed:
        return
    if turn.error is not None and turn.error.message:
        raise RuntimeError(turn.error.message)
    raise RuntimeError(f"turn failed with status {turn.status.value}")
```

## 关键代码路径与文件引用

### 被调用方

```
api.py
├── Thread.run()
│   └── _collect_run_result(stream, turn_id=turn.id)
│
└── AsyncThread.run()
    └── _collect_async_run_result(stream, turn_id=turn.id)
```

### 调用时序图

```
Thread.run(input)
    │
    ├── turn = self.turn(input, ...)     # api.py
    │   └── turn_start RPC               # client.py
    │
    ├── stream = turn.stream()           # TurnHandle.stream()
    │   └── 订阅通知流                   # client.py
    │
    └── _collect_run_result(stream, turn_id)  # _run.py
        ├── 遍历通知流
        │   ├── 收集 ItemCompletedNotification
        │   ├── 收集 ThreadTokenUsageUpdatedNotification
        │   └── 检测 TurnCompletedNotification
        ├── _raise_for_failed_turn()
        └── _final_assistant_response_from_items()
            └── 提取 final_response
```

## 依赖与外部交互

### 内部依赖

| 符号 | 来源 | 用途 |
|-----|------|------|
| `AgentMessageThreadItem` | `.generated.v2_all` | 识别助手消息类型 |
| `ItemCompletedNotification` | `.generated.v2_all` | 检测 Item 完成事件 |
| `MessagePhase` | `.generated.v2_all` | 消息 phase 枚举 |
| `ThreadItem` | `.generated.v2_all` | ThreadItem 类型 |
| `ThreadTokenUsage` | `.generated.v2_all` | Token 使用统计 |
| `ThreadTokenUsageUpdatedNotification` | `.generated.v2_all` | Token 更新通知 |
| `Turn` / `TurnCompletedNotification` | `.generated.v2_all` | Turn 完成通知 |
| `TurnStatus` | `.generated.v2_all` | Turn 状态枚举 |
| `Notification` | `.models` | 通知类型 |

### 依赖关系图

```
_run.py
├── generated.v2_all  (大量生成模型)
└── models.py         (Notification)
    
api.py  →  _run.py  (导入收集函数)
```

## 风险、边界与改进建议

### 当前风险

1. **无限循环风险**：如果服务器不发送 `turn/completed` 通知，同步版本会无限阻塞
2. **内存累积**：长时间运行的 Turn 可能积累大量 items，导致内存增长
3. **异常处理不完整**：`_collect_async_run_result` 中如果发生异常，可能导致资源泄漏

### 边界情况

1. **空事件流**：如果 `TurnCompletedNotification` 从未到达，会抛出 `RuntimeError("turn completed event not received")`
2. **部分完成**：即使 Turn 失败，已收集的 items 和 usage 也会包含在异常前的状态
3. **Phase 歧义**：`MessagePhase` 为 `None` 的消息处理逻辑依赖遍历顺序
4. **并发安全**：同步和异步版本分别由不同的调用方使用，不存在混用风险

### 改进建议

1. **添加超时机制**：
   ```python
   def _collect_run_result(stream: Iterator[Notification], *, turn_id: str, timeout: float | None = None) -> RunResult:
       start_time = time.monotonic()
       for event in stream:
           if timeout and (time.monotonic() - start_time) > timeout:
               raise TimeoutError(f"Turn {turn_id} did not complete within {timeout}s")
           # ...
   ```

2. **支持部分结果返回**：
   ```python
   @dataclass(slots=True)
   class RunResult:
       final_response: str | None
       items: list[ThreadItem]
       usage: ThreadTokenUsage | None
       completed: bool  # 新增：是否完整完成
       error: str | None  # 新增：错误信息
   ```

3. **流式结果支持**：
   当前实现是"收集完再返回"，可以考虑添加回调模式支持真正的实时处理：
   ```python
   def _collect_run_result_with_callback(
       stream: Iterator[Notification],
       *,
       turn_id: str,
       on_item: Callable[[ThreadItem], None] | None = None,
       on_usage: Callable[[ThreadTokenUsage], None] | None = None,
   ) -> RunResult:
       # ...
   ```

4. **更精确的错误类型**：
   当前使用通用的 `RuntimeError`，建议定义专门的异常：
   ```python
   class TurnFailedError(AppServerError):
       def __init__(self, turn_id: str, message: str):
           super().__init__(f"Turn {turn_id} failed: {message}")
           self.turn_id = turn_id
   ```

5. **日志记录**：
   添加结构化日志记录，便于调试事件流问题：
   ```python
   import logging
   logger = logging.getLogger(__name__)
   
   # 在收集过程中记录关键事件
   logger.debug("Collected item for turn %s: %s", turn_id, item.id)
   ```

### 测试覆盖

相关测试：
- `test_public_api_runtime_behavior.py::test_thread_run_accepts_string_input_and_returns_run_result`
- `test_public_api_runtime_behavior.py::test_thread_run_uses_last_completed_assistant_message_as_final_response`
- `test_public_api_runtime_behavior.py::test_thread_run_preserves_empty_last_assistant_message`
- `test_public_api_runtime_behavior.py::test_thread_run_prefers_explicit_final_answer_over_later_commentary`
- `test_public_api_runtime_behavior.py::test_thread_run_returns_none_when_only_commentary_messages_complete`
- `test_public_api_runtime_behavior.py::test_thread_run_raises_on_failed_turn`
- `test_public_api_runtime_behavior.py::test_async_thread_run_*`（异步版本对应测试）

这些测试覆盖了：
- 基本结果收集
- 多消息场景下的回复选择
- Phase 处理逻辑
- 失败 Turn 的异常抛出
