# sync.py 研究文档

## 场景与职责

`sync.py` 是 Codex Python SDK 的同步示例程序，与 `async.py` 功能完全对应，但使用 **同步阻塞 API** 实现。该示例展示了在不使用 asyncio 的传统 Python 代码中如何集成 Codex App Server。

**核心职责**：
- 演示同步上下文管理器 (`with`) 模式使用 `Codex` 客户端
- 展示所有 Turn 高级参数在同步场景下的配置方式
- 演示结构化输出（Structured Output）功能的同步调用
- 作为异步示例的对比，帮助开发者选择适合的集成方式

## 功能点目的

### 1. 同步 API 设计
```python
with Codex(config=runtime_config()) as codex:
    thread = codex.thread_start(...)
    turn = thread.turn(...)
    result = turn.run()
```
- **目的**：提供与异步版完全一致的 API 语义，但使用阻塞调用
- **适用场景**：
  - 简单的脚本工具
  - 不需要并发的批处理任务
  - 与现有同步代码库集成
  - 交互式 REPL/Notebook 环境

### 2. 结构化输出 (Structured Output)
```python
OUTPUT_SCHEMA = {
    "type": "object",
    "properties": {
        "summary": {"type": "string"},
        "actions": {
            "type": "array",
            "items": {"type": "string"},
        },
    },
    "required": ["summary", "actions"],
    "additionalProperties": False,
}
```
- **目的**：强制模型生成符合 JSON Schema 的结构化响应
- **业务场景**：生成功能开关（feature flag）的安全上线计划，包含摘要和具体行动项

### 3. 审批策略 (Approval Policy)
```python
APPROVAL_POLICY = AskForApproval.model_validate("never")
```
- **目的**：完全自动化执行，无需人工干预
- **安全考量**：仅在受信任的环境中使用 `"never"` 策略

### 4. 推理摘要与模型配置
```python
SUMMARY = ReasoningSummary.model_validate("concise")
model="gpt-5.4", config={"model_reasoning_effort": "high"}
```
- **目的**：获取模型推理过程的简洁摘要，同时启用高强度推理
- **价值**：帮助理解模型如何得出特定结论

### 5. 人格设定
```python
personality=Personality.pragmatic
```
- **目的**：使模型响应更务实、直接，适合技术规划场景

## 具体技术实现

### 关键流程

#### 1. 同步初始化流程
```python
with Codex(config=runtime_config()) as codex:
    # ...
```

**详细流程**：
1. `Codex.__init__()` (api.py:72-79):
   - 创建 `AppServerClient` 实例
   - 立即调用 `start()` 启动子进程
   - 调用 `initialize()` 进行协议握手
   - 异常时自动调用 `close()` 清理资源

2. `Codex.__enter__()` (api.py:81-82):
   - 返回自身实例

3. `Codex._validate_initialize()` (api.py:88-123):
   - 解析服务器元数据（userAgent、serverInfo）
   - 验证必需字段存在
   - 规范化服务器名称和版本

#### 2. Thread 创建流程
```python
thread = codex.thread_start(
    model="gpt-5.4", 
    config={"model_reasoning_effort": "high"}
)
```

**详细流程**（api.py:133-166）：
1. 构建 `ThreadStartParams` 参数对象
2. 调用底层 `AppServerClient.thread_start()`
3. 返回 `Thread` 对象（dataclass，包含 `_client` 和 `id`）

#### 3. Turn 启动与执行流程
```python
turn = thread.turn(
    TextInput(PROMPT),
    approval_policy=APPROVAL_POLICY,
    output_schema=OUTPUT_SCHEMA,
    personality=Personality.pragmatic,
    summary=SUMMARY,
)
result = turn.run()
```

**详细流程**：

**阶段 1: Turn 启动** (api.py:507-538)
```python
def turn(self, input: Input, ..., summary: ReasoningSummary | None = None) -> TurnHandle:
    wire_input = _to_wire_input(input)  # 转换为 wire 格式
    params = TurnStartParams(...)
    turn = self._client.turn_start(self.id, wire_input, params=params)
    return TurnHandle(self._client, self.id, turn.turn.id)
```

**阶段 2: Turn 运行** (api.py:671-684)
```python
def run(self) -> AppServerTurn:
    completed: TurnCompletedNotification | None = None
    stream = self.stream()
    try:
        for event in stream:
            payload = event.payload
            if isinstance(payload, TurnCompletedNotification) and payload.turn.id == self.id:
                completed = payload
    finally:
        stream.close()
    
    if completed is None:
        raise RuntimeError("turn completed event not received")
    return completed.turn
```

**阶段 3: 事件流消费** (api.py:655-669)
```python
def stream(self) -> Iterator[Notification]:
    self._client.acquire_turn_consumer(self.id)  # 获取独占锁
    try:
        while True:
            event = self._client.next_notification()
            yield event
            if (event.method == "turn/completed" 
                and event.payload.turn.id == self.id):
                break
    finally:
        self._client.release_turn_consumer(self.id)
```

#### 4. 结果解析流程
```python
persisted = thread.read(include_turns=True)
persisted_turn = find_turn_by_id(persisted.thread.turns, result.id)
structured_text = assistant_text_from_turn(persisted_turn).strip()
structured = json.loads(structured_text)
```

与异步版完全一致，通过 `_bootstrap.py` 提供的工具函数解析助手响应。

### 数据结构

#### Thread (同步线程句柄)
```python
@dataclass(slots=True)
class Thread:
    _client: AppServerClient  # 底层同步客户端
    id: str                   # Thread ID
```

#### TurnHandle (同步 Turn 句柄)
```python
@dataclass(slots=True)
class TurnHandle:
    _client: AppServerClient
    thread_id: str
    id: str
    
    def steer(self, input: Input) -> TurnSteerResponse: ...
    def interrupt(self) -> TurnInterruptResponse: ...
    def stream(self) -> Iterator[Notification]: ...
    def run(self) -> AppServerTurn: ...
```

#### 输入类型转换
```python
# _inputs.py:40-57
def _to_wire_item(item: InputItem) -> JsonObject:
    if isinstance(item, TextInput):
        return {"type": "text", "text": item.text}
    if isinstance(item, ImageInput):
        return {"type": "image", "url": item.url}
    # ... 其他类型

def _to_wire_input(input: Input) -> list[JsonObject]:
    if isinstance(input, list):
        return [_to_wire_item(i) for i in input]
    return [_to_wire_item(input)]
```

### 协议交互

#### JSON-RPC 通信流程
```
客户端                              App Server
  |                                     |
  |-- initialize ---------------------->|
  |<----------------- InitializeResult--|
  |-- initialized --------------------->|
  |                                     |
  |-- thread/start -------------------->|
  |<---------------- ThreadStartResponse|
  |                                     |
  |-- turn/start ---------------------->|
  |<------------------ TurnStartResponse|
  |                                     |
  |<-- notification: turn/started ------|
  |<-- notification: item/started ------|
  |<-- notification: item/completed ----|
  |<-- notification: turn/completed ----|
  |                                     |
  |-- thread/read --------------------->|
  |<------------------ ThreadReadResponse|
```

## 关键代码路径与文件引用

### 调用链
```
sync.py
  └─ Codex (api.py:69)
       └─ AppServerClient (client.py:136)
  
sync.py:thread.turn()
  └─ Thread.turn() (api.py:507)
       └─ AppServerClient.turn_start() (client.py:352)
            └─ _write_message() / _read_message()

sync.py:turn.run()
  └─ TurnHandle.run() (api.py:671)
       └─ TurnHandle.stream() (api.py:655)
            └─ AppServerClient.next_notification() (client.py:275)
```

### 核心类图
```
┌─────────────────┐
│     Codex       │◄────────── 同步入口类
├─────────────────┤
│ - _client       │────┐
│ - _init         │    │
├─────────────────┤    │
│ + thread_start()│    │
│ + thread_list() │    │
└─────────────────┘    │
                       │
┌─────────────────┐    │
│     Thread      │◄───┘
├─────────────────┤
│ - _client       │
│ - id            │
├─────────────────┤
│ + turn()        │────┐
│ + read()        │    │
└─────────────────┘    │
                       │
┌─────────────────┐    │
│   TurnHandle    │◄───┘
├─────────────────┤
│ - _client       │
│ - thread_id     │
│ - id            │
├─────────────────┤
│ + run()         │
│ + stream()      │
│ + steer()       │
│ + interrupt()   │
└─────────────────┘
```

### 关键文件引用
| 文件 | 行号范围 | 作用 |
|------|---------|------|
| `sdk/python/examples/_bootstrap.py` | 118-151 | `find_turn_by_id`、`assistant_text_from_turn` |
| `sdk/python/src/codex_app_server/api.py` | 69-264 | `Codex`、`Thread`、`TurnHandle` 同步 API |
| `sdk/python/src/codex_app_server/client.py` | 136-540 | `AppServerClient` JSON-RPC 实现 |
| `sdk/python/src/codex_app_server/_inputs.py` | 8-62 | 输入类型和转换函数 |
| `sdk/python/src/codex_app_server/generated/v2_all.py` | 5236-5290 | `TurnStartParams` 定义 |

## 依赖与外部交互

### 内部依赖
```python
# 示例基础设施
from _bootstrap import (
    assistant_text_from_turn,    # 行125-151: 提取助手消息文本
    ensure_local_sdk_src,        # 行34-47: 设置 SDK 源码路径
    find_turn_by_id,             # 行118-122: 查找 Turn
    runtime_config,              # 行50-55: 获取默认配置
)

# SDK 公共 API
from codex_app_server import (
    AskForApproval,      # 审批策略枚举/模型
    Codex,               # 同步客户端主类
    Personality,         # 人格枚举: none/friendly/pragmatic
    ReasoningSummary,    # 推理摘要类型
    TextInput,           # 文本输入包装类
)
```

### 外部进程
- **Codex CLI**: 通过 `subprocess.Popen` 启动 `codex app-server --listen stdio://`
- **生命周期**: `Codex.__enter__` 启动，`Codex.__exit__` 终止
- **通信**: STDIN/STDOUT 行分隔 JSON-RPC 消息

### 线程安全
```python
# client.py:147-151
self._lock = threading.Lock()                    # 写入锁
self._turn_consumer_lock = threading.Lock()      # Turn 消费锁
self._active_turn_consumer: str | None = None    # 当前消费者
```
- 写入操作使用 `_lock` 互斥
- Turn 事件流消费使用 `_turn_consumer_lock` 限制并发

## 风险、边界与改进建议

### 风险点

1. **阻塞 I/O**
   ```python
   # client.py:519-536
   line = self._proc.stdout.readline()  # 阻塞直到有数据
   ```
   - 同步实现会阻塞直到收到响应
   - 长时间运行的 Turn 会阻塞整个线程
   - 建议：在独立线程中运行，或使用异步版本

2. **单 Turn 消费限制**
   ```python
   # client.py:288-296
   if self._active_turn_consumer is not None:
       raise RuntimeError("Concurrent turn consumers are not yet supported...")
   ```
   - 同一时间只能有一个 Turn 在消费事件流
   - 多线程环境下需要外部协调

3. **进程生命周期管理**
   ```python
   # client.py:191-207
   def close(self) -> None:
       if proc.stdin:
           proc.stdin.close()
       try:
           proc.terminate()
           proc.wait(timeout=2)
       except Exception:
           proc.kill()
   ```
   - 强制终止可能导致资源泄漏
   - 2 秒等待时间可能不足以优雅关闭

### 边界条件

1. **空响应处理**
   ```python
   # sync.py:64
   except json.JSONDecodeError as exc:
       raise RuntimeError(f"Expected JSON matching OUTPUT_SCHEMA, got: {structured_text!r}") from exc
   ```
   - 模型可能返回不符合 Schema 的内容
   - 建议添加重试或降级逻辑

2. **Turn 查找失败**
   ```python
   # sync.py:59
   persisted_turn = find_turn_by_id(persisted.thread.turns, result.id)
   # sync.py:60
   structured_text = assistant_text_from_turn(persisted_turn).strip()
   ```
   - `persisted_turn` 可能为 None
   - `assistant_text_from_turn` 内部已处理 None 情况

3. **进程异常退出**
   ```python
   # client.py:524-527
   if not line:
       raise TransportClosedError(
           f"app-server closed stdout. stderr_tail={self._stderr_tail()[:2000]}"
       )
   ```
   - 会捕获最后 40 行 stderr 用于调试

### 改进建议

1. **超时控制**
   ```python
   # 建议添加超时参数
   result = turn.run(timeout=60.0)  # 60秒超时
   ```

2. **进度回调**
   ```python
   # 建议支持进度回调
   for notification in turn.stream():
       if on_progress:
           on_progress(notification)
   ```

3. **批量处理支持**
   ```python
   # 当前仅支持单 Turn
   # 建议添加批量接口
   results = thread.run_batch([input1, input2, input3])
   ```

4. **更健壮的 Schema 验证**
   ```python
   # 当前仅做 JSON 解析
   # 建议使用 jsonschema 验证
   from jsonschema import validate
   validate(structured, OUTPUT_SCHEMA)
   ```

5. **配置外部化**
   ```python
   # 建议支持环境变量或配置文件
   import os
   MODEL = os.getenv("CODEX_MODEL", "gpt-5.4")
   APPROVAL_POLICY = os.getenv("CODEX_APPROVAL_POLICY", "never")
   ```

6. **日志集成**
   ```python
   # 当前使用 print
   # 建议使用标准 logging
   import logging
   logger = logging.getLogger(__name__)
   logger.info("Turn completed: %s", result.status)
   ```

### 与异步版对比

| 特性 | sync.py | async.py |
|------|---------|----------|
| API 风格 | 阻塞同步 | 异步非阻塞 |
| 上下文管理器 | `with` | `async with` |
| 适用场景 | 脚本、批处理 | Web 服务、高并发 |
| 代码复杂度 | 简单直观 | 需要 async/await 知识 |
| 性能 | 单线程阻塞 | 支持并发 |
| 错误处理 | 直接抛出异常 | 需要 await 捕获 |

两个示例功能完全一致，开发者可根据应用场景选择适合的版本。
