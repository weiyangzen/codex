# SDK Python Examples 05_existing_thread 深度研究文档

## 1. 场景与职责

### 1.1 目标目录位置
- **路径**: `sdk/python/examples/05_existing_thread/`
- **文件构成**:
  - `sync.py` - 同步模式示例
  - `async.py` - 异步模式示例

### 1.2 核心职责
`05_existing_thread` 示例演示了 **线程恢复（Thread Resume）** 的核心能力，即如何在脚本中：
1. 创建一个初始线程并执行第一轮对话
2. 通过线程 ID 恢复已存在的线程
3. 在恢复的线程上继续执行后续对话
4. 验证线程状态持久化（通过 `thread/read` 读取历史 turns）

这是构建多轮对话应用的基础模式，区别于 `01_quickstart_constructor` 的单轮对话和 `02_turn_run` 的同线程多轮对话。

### 1.3 在示例体系中的定位

| 示例 | 核心能力 |
|------|----------|
| 01_quickstart_constructor | 基础初始化与单轮对话 |
| 02_turn_run | 同线程连续多轮对话 |
| **05_existing_thread** | **跨会话恢复已有线程** |
| 06_thread_lifecycle_and_controls | 线程生命周期管理（归档/解归档/压缩） |

---

## 2. 功能点目的

### 2.1 线程持久化与恢复
在 Codex App Server 架构中：
- **Thread** 是对话状态的容器，包含历史 turns、配置、元数据
- Thread 默认会被持久化到磁盘（除非设置 `ephemeral=True`）
- 通过 `thread_resume(thread_id)` 可以在新的 SDK 会话中恢复已有线程

### 2.2 示例展示的关键能力

#### 同步版本 (`sync.py`)
```python
# 1. 创建初始线程
original = codex.thread_start(model="gpt-5.4", config={"model_reasoning_effort": "high"})
first = original.turn(TextInput("Tell me one fact about Saturn.")).run()
print("Created thread:", original.id)

# 2. 通过 ID 恢复线程
resumed = codex.thread_resume(original.id)
second = resumed.turn(TextInput("Continue with one more fact.")).run()

# 3. 验证持久化状态
persisted = resumed.read(include_turns=True)
persisted_turn = find_turn_by_id(persisted.thread.turns, second.id)
print(assistant_text_from_turn(persisted_turn))
```

#### 异步版本 (`async.py`)
异步版本展示了相同的逻辑，但使用 `AsyncCodex` 和 `async/await` 模式：
```python
async with AsyncCodex(config=runtime_config()) as codex:
    original = await codex.thread_start(model="gpt-5.4", ...)
    first_turn = await original.turn(TextInput("..."))
    _ = await first_turn.run()
    
    resumed = await codex.thread_resume(original.id)
    second_turn = await resumed.turn(TextInput("..."))
    second = await second_turn.run()
```

### 2.3 关键验证点
- `thread_resume()` 返回的 `Thread` 对象与原始线程具有相同的 ID
- `read(include_turns=True)` 可以获取完整的历史对话记录
- 恢复的线程可以无缝继续对话，保持上下文连贯性

---

## 3. 具体技术实现

### 3.1 关键流程

#### 3.1.1 线程创建流程
```
Codex.thread_start(params: ThreadStartParams) -> Thread
  ↓
AppServerClient.thread_start(params) -> ThreadStartResponse
  ↓
JSON-RPC: "thread/start" 
  ↓
返回 Thread 对象（包装 thread.id）
```

#### 3.1.2 线程恢复流程
```
Codex.thread_resume(thread_id: str, params: ThreadResumeParams) -> Thread
  ↓
AppServerClient.thread_resume(thread_id, params) -> ThreadResumeResponse
  ↓
JSON-RPC: "thread/resume" 
  ↓
返回 Thread 对象（包装 resumed.thread.id）
```

#### 3.1.3 Turn 执行流程
```
Thread.turn(input: Input) -> TurnHandle
  ↓
AppServerClient.turn_start(thread_id, input, params) -> TurnStartResponse
  ↓
JSON-RPC: "turn/start"
  ↓
返回 TurnHandle（包装 turn.id）

TurnHandle.run() -> Turn
  ↓
消费通知流直到 turn/completed
  ↓
返回完整的 Turn 对象
```

### 3.2 关键数据结构

#### 3.2.1 ThreadStartParams (v2_all.py:3142-3169)
```python
class ThreadStartParams(BaseModel):
    approval_policy: AskForApproval | None = None
    approvals_reviewer: ApprovalsReviewer | None = None
    base_instructions: str | None = None
    config: dict[str, Any] | None = None  # 模型配置覆盖
    cwd: str | None = None
    developer_instructions: str | None = None
    ephemeral: bool | None = None  # 是否临时线程（不持久化）
    model: str | None = None  # 模型名称，如 "gpt-5.4"
    model_provider: str | None = None
    personality: Personality | None = None
    sandbox: SandboxMode | None = None
    service_name: str | None = None
    service_tier: ServiceTier | None = None
```

#### 3.2.2 ThreadResumeParams (v2_all.py:3063-3092)
```python
class ThreadResumeParams(BaseModel):
    thread_id: str  # 要恢复的线程 ID
    approval_policy: AskForApproval | None = None
    approvals_reviewer: ApprovalsReviewer | None = None
    base_instructions: str | None = None
    config: dict[str, Any] | None = None  # 可覆盖原配置
    cwd: str | None = None
    developer_instructions: str | None = None
    model: str | None = None  # 可切换模型
    model_provider: str | None = None
    personality: Personality | None = None
    sandbox: SandboxMode | None = None
    service_tier: ServiceTier | None = None
```

#### 3.2.3 ThreadResumeResponse (v2_all.py:5961-5982)
```python
class ThreadResumeResponse(BaseModel):
    approval_policy: AskForApproval
    approvals_reviewer: ApprovalsReviewer
    cwd: str
    model: str
    model_provider: str
    reasoning_effort: ReasoningEffort | None = None
    sandbox: SandboxPolicy
    service_tier: ServiceTier | None = None
    thread: Thread  # 完整的线程对象
```

#### 3.2.4 Thread 对象 (v2_all.py:5820-5908)
```python
class Thread(BaseModel):
    id: str
    created_at: int  # Unix timestamp
    updated_at: int
    cwd: str
    ephemeral: bool
    model_provider: str
    name: str | None = None  # 线程标题
    preview: str  # 通常为首条用户消息
    status: ThreadStatus
    turns: list[Turn]  # 历史 turns（仅在 resume/fork/read 时填充）
    # ... 其他元数据字段
```

### 3.3 协议与命令

#### 3.3.1 JSON-RPC 方法
| 方法 | 方向 | 用途 |
|------|------|------|
| `thread/start` | Client → Server | 创建新线程 |
| `thread/resume` | Client → Server | 恢复已有线程 |
| `turn/start` | Client → Server | 启动新 turn |
| `thread/read` | Client → Server | 读取线程状态 |
| `turn/completed` | Server → Client | Turn 完成通知 |
| `item/completed` | Server → Client | 单个 item 完成通知 |

#### 3.3.2 通知处理
SDK 通过 `TurnHandle.stream()` 消费服务器推送的通知流：
- `turn/started` - Turn 开始
- `item/started`, `item/completed` - Item 生命周期
- `turn/completed` - Turn 结束（包含完整 Turn 数据）

### 3.4 辅助工具函数

示例使用了 `_bootstrap.py` 提供的工具函数：

#### `find_turn_by_id(turns, turn_id)`
```python
def find_turn_by_id(turns: Iterable[object] | None, turn_id: str) -> object | None:
    for turn in turns or []:
        if getattr(turn, "id", None) == turn_id:
            return turn
    return None
```

#### `assistant_text_from_turn(turn)`
```python
def assistant_text_from_turn(turn: object | None) -> str:
    # 从 turn.items 中提取 assistant 的文本响应
    # 支持 agentMessage 和 message/output_text 两种格式
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心调用链

```
sdk/python/examples/05_existing_thread/sync.py
  ↓ imports
sdk/python/examples/_bootstrap.py
  ↓ imports (via sys.path manipulation)
sdk/python/src/codex_app_server/__init__.py
  ↓ exports
sdk/python/src/codex_app_server/api.py :: Codex, Thread, TurnHandle
  ↓ delegates to
sdk/python/src/codex_app_server/client.py :: AppServerClient
  ↓ JSON-RPC over stdio
  ↓
codex app-server (Rust binary)
```

### 4.2 关键文件详解

#### 4.2.1 `sdk/python/examples/05_existing_thread/sync.py`
```python
import sys
from pathlib import Path

# 设置路径以使用本地 SDK 源码
_EXAMPLES_ROOT = Path(__file__).resolve().parents[1]
if str(_EXAMPLES_ROOT) not in sys.path:
    sys.path.insert(0, str(_EXAMPLES_ROOT))

from _bootstrap import assistant_text_from_turn, ensure_local_sdk_src, find_turn_by_id, runtime_config
ensure_local_sdk_src()  # 确保使用本地 SDK 而非已安装的包

from codex_app_server import Codex, TextInput

with Codex(config=runtime_config()) as codex:
    # 创建线程 + 第一轮对话
    original = codex.thread_start(model="gpt-5.4", config={"model_reasoning_effort": "high"})
    first = original.turn(TextInput("Tell me one fact about Saturn.")).run()
    print("Created thread:", original.id)
    
    # 恢复线程 + 第二轮对话
    resumed = codex.thread_resume(original.id)
    second = resumed.turn(TextInput("Continue with one more fact.")).run()
    
    # 验证持久化
    persisted = resumed.read(include_turns=True)
    persisted_turn = find_turn_by_id(persisted.thread.turns, second.id)
    print(assistant_text_from_turn(persisted_turn))
```

#### 4.2.2 `sdk/python/src/codex_app_server/api.py`

**Codex.thread_resume()** (line 192-223):
```python
def thread_resume(
    self,
    thread_id: str,
    *,
    approval_policy: AskForApproval | None = None,
    approvals_reviewer: ApprovalsReviewer | None = None,
    base_instructions: str | None = None,
    config: JsonObject | None = None,
    cwd: str | None = None,
    developer_instructions: str | None = None,
    model: str | None = None,
    model_provider: str | None = None,
    personality: Personality | None = None,
    sandbox: SandboxMode | None = None,
    service_tier: ServiceTier | None = None,
) -> Thread:
    params = ThreadResumeParams(
        thread_id=thread_id,
        approval_policy=approval_policy,
        # ... 其他参数
    )
    resumed = self._client.thread_resume(thread_id, params)
    return Thread(self._client, resumed.thread.id)
```

**Thread.read()** (line 541-542):
```python
def read(self, *, include_turns: bool = False) -> ThreadReadResponse:
    return self._client.thread_read(self.id, include_turns=include_turns)
```

#### 4.2.3 `sdk/python/src/codex_app_server/client.py`

**AppServerClient.thread_resume()** (line 306-312):
```python
def thread_resume(
    self,
    thread_id: str,
    params: V2ThreadResumeParams | JsonObject | None = None,
) -> ThreadResumeResponse:
    payload = {"threadId": thread_id, **_params_dict(params)}
    return self.request("thread/resume", payload, response_model=ThreadResumeResponse)
```

**AppServerClient.thread_read()** (line 317-322):
```python
def thread_read(self, thread_id: str, include_turns: bool = False) -> ThreadReadResponse:
    return self.request(
        "thread/read",
        {"threadId": thread_id, "includeTurns": include_turns},
        response_model=ThreadReadResponse,
    )
```

#### 4.2.4 `sdk/python/src/codex_app_server/generated/v2_all.py`

包含所有 Pydantic 模型定义，由 `datamodel-codegen` 从 JSON Schema 生成：
- `ThreadResumeParams` (line 3063)
- `ThreadResumeResponse` (line 5961)
- `ThreadReadResponse` (line 5954)
- `Thread` (line 5820)
- `Turn` (line 5192)

---

## 5. 依赖与外部交互

### 5.1 运行时依赖

| 依赖 | 用途 |
|------|------|
| `codex-cli-bin` | Codex App Server 二进制程序，通过 stdio 进行 JSON-RPC 通信 |
| `pydantic` | 数据验证和序列化 |
| Python >= 3.10 | 类型注解支持（`str | None` 语法） |

### 5.2 启动流程

```
Codex() 构造函数
  ↓
AppServerClient.start()
  ↓
subprocess.Popen([codex_bin, "app-server", "--listen", "stdio://"])
  ↓
AppServerClient.initialize()
  ↓
JSON-RPC: "initialize" 
  ↓
发送 clientInfo, capabilities
  ↓
接收 serverInfo, userAgent
```

### 5.3 配置覆盖

示例中展示了通过 `config` 参数覆盖模型配置：
```python
codex.thread_start(
    model="gpt-5.4",
    config={"model_reasoning_effort": "high"}
)
```

支持的配置项（来自 Rust 侧的 `ConfigToml`）：
- `model_reasoning_effort`: low/medium/high/xhigh
- `model_verbosity`: low/medium/high
- `web_search`: disabled/cached/live
- 其他模型特定参数

### 5.4 线程状态存储

- **默认位置**: `~/.codex/threads/`
- **文件格式**: 二进制/JSON 混合格式（由 Rust 侧实现）
- **持久化策略**: 非 ephemeral 线程在 turn 完成后自动持久化
- **加载策略**: `thread_resume` 从磁盘加载线程状态到内存

---

## 6. 风险、边界与改进建议

### 6.1 已知限制

#### 6.1.1 并发限制
```python
# SDK 当前限制：每个客户端实例只能有一个活动的 turn consumer
def acquire_turn_consumer(self, turn_id: str) -> None:
    with self._turn_consumer_lock:
        if self._active_turn_consumer is not None:
            raise RuntimeError(
                "Concurrent turn consumers are not yet supported in the experimental SDK."
            )
        self._active_turn_consumer = turn_id
```

**影响**: 不能同时运行多个 `TurnHandle.stream()` 或 `Thread.run()`。

#### 6.1.2 线程 ID 有效性
- `thread_resume()` 假设传入的 `thread_id` 存在且可访问
- 无效的 ID 会导致服务器返回错误（通常映射为 `InvalidParamsError`）

#### 6.1.3 配置覆盖范围
- 通过 `thread_resume` 传入的配置仅影响后续 turns
- 不会修改已持久化的历史 turns

### 6.2 边界情况

| 场景 | 行为 |
|------|------|
| 恢复 ephemeral 线程 | 如果进程已重启，ephemeral 线程可能丢失 |
| 并发修改同一线程 | 最后一个写入者获胜，可能导致状态丢失 |
| 网络/服务中断 | 正在进行的 turn 会失败，需要客户端重试逻辑 |
| 磁盘空间不足 | 线程持久化可能失败，返回 `InternalRpcError` |

### 6.3 改进建议

#### 6.3.1 SDK 层面
1. **添加线程存在性检查**:
   ```python
   def thread_exists(self, thread_id: str) -> bool:
       try:
           self.thread_read(thread_id)
           return True
       except InvalidParamsError:
           return False
   ```

2. **支持批量线程操作**:
   ```python
   def thread_resume_many(self, thread_ids: list[str]) -> list[Thread]:
       # 减少多次 RPC 调用开销
   ```

3. **添加线程缓存**:
   ```python
   class Codex:
       def __init__(self):
           self._thread_cache: dict[str, Thread] = {}
   ```

#### 6.3.2 示例层面
1. **添加错误处理示例**:
   ```python
   try:
       resumed = codex.thread_resume(thread_id)
   except InvalidParamsError:
       print("Thread not found, creating new...")
       resumed = codex.thread_start(...)
   ```

2. **展示线程列表查询**:
   ```python
   threads = codex.thread_list(search_term="Saturn")
   if threads.data:
       resumed = codex.thread_resume(threads.data[0].id)
   ```

3. **添加超时控制示例**:
   ```python
   from codex_app_server.retry import retry_on_overload
   
   result = retry_on_overload(
       lambda: resumed.turn(TextInput("...")).run(),
       max_attempts=3
   )
   ```

#### 6.3.3 文档层面
1. 明确说明 `include_turns=True` 的性能影响（大数据量时的内存占用）
2. 补充线程存储路径和清理策略
3. 添加线程 ID 格式说明（通常是 `thread_` 前缀的 UUID）

### 6.4 测试建议

参考 `sdk/python/tests/test_public_api_runtime_behavior.py` 中的测试模式：

```python
def test_thread_resume_persists_state():
    # 模拟场景：创建线程 → 执行 turn → 模拟新会话恢复 → 验证历史
    pass

def test_thread_resume_with_config_override():
    # 验证 resume 时的配置覆盖是否生效
    pass

def test_thread_resume_invalid_id():
    # 验证无效 thread_id 的错误处理
    pass
```

---

## 7. 附录

### 7.1 相关文件索引

| 文件 | 用途 |
|------|------|
| `sdk/python/examples/05_existing_thread/sync.py` | 同步示例代码 |
| `sdk/python/examples/05_existing_thread/async.py` | 异步示例代码 |
| `sdk/python/examples/_bootstrap.py` | 示例启动辅助工具 |
| `sdk/python/src/codex_app_server/api.py` | 公共 API 实现（Codex, Thread, TurnHandle） |
| `sdk/python/src/codex_app_server/client.py` | JSON-RPC 客户端实现 |
| `sdk/python/src/codex_app_server/generated/v2_all.py` | 自动生成的 Pydantic 模型 |
| `sdk/python/docs/getting-started.md` | 快速入门文档（含 resume 示例） |
| `sdk/python/docs/api-reference.md` | API 参考文档 |

### 7.2 版本信息
- **SDK 版本**: 0.2.0
- **目标协议**: Codex App Server JSON-RPC v2
- **Python 要求**: >= 3.10

### 7.3 变更历史注意事项
- `thread_resume` 替代了早期版本中的隐式线程恢复机制
- 配置参数从 camelCase 迁移到 snake_case（FAQ 中有详细对照表）
- `AsyncCodex` 采用延迟初始化模式（lazy initialization）
