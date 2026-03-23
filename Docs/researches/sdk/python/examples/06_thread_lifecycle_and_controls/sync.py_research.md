# sync.py 深度研究文档

## 场景与职责

`sync.py` 是 Python SDK 中关于 **Thread 生命周期管理** 的同步示例程序。与 `async.py` 功能完全对应，但使用同步 API 实现。它展示了如何使用 `Codex` 客户端对对话线程（Thread）进行完整的生命周期操作。

### 核心职责
1. 演示同步模式下 Thread 的完整生命周期管理
2. 展示高级 Thread 控制操作（archive/unarchive/fork/compact）
3. 为不习惯异步编程的开发者提供参考示例
4. 验证 SDK 同步 API 的正确性和可用性

### 与 async.py 的关系
- **功能等价**：两个文件展示完全相同的业务逻辑
- **API 差异**：`sync.py` 使用 `Codex`/`Thread`/`TurnHandle`，`async.py` 使用 `AsyncCodex`/`AsyncThread`/`AsyncTurnHandle`
- **使用场景**：同步版本适合脚本、简单应用；异步版本适合高并发、Web 服务

---

## 功能点目的

### 1. Thread 创建与对话
- **目的**：创建新线程并进行多轮对话
- **关键操作**：`thread_start()` → `turn()` → `run()`
- **同步特点**：阻塞式调用，代码顺序执行，逻辑直观

### 2. Thread 恢复与列表查询
- **目的**：演示如何重新打开已有线程，并查询线程列表
- **关键操作**：`thread_resume()`、`thread_list()`
- **意义**：支持长时间运行的对话场景，允许程序重启后恢复对话状态

### 3. Thread 归档管理
- **目的**：管理线程的归档状态，区分活跃和非活跃线程
- **关键操作**：`thread_archive()`、`thread_unarchive()`
- **意义**：帮助用户组织大量线程，将不活跃的对话归档

### 4. Thread 分叉（Fork）
- **目的**：基于现有线程创建分支，用于探索不同对话路径
- **关键操作**：`thread_fork()`
- **意义**：支持 A/B 测试、实验性探索等场景

### 5. Thread 压缩（Compact）
- **目的**：压缩线程上下文，减少 token 消耗
- **关键操作**：`compact()`
- **意义**：优化长对话的性能和成本

---

## 具体技术实现

### 关键流程

#### 1. 初始化流程
```python
with Codex(config=runtime_config()) as codex:
```
- 使用同步上下文管理器确保资源正确释放
- `Codex` 在 `__init__` 中立即启动（eager initialization）
- `__enter__` 返回自身，`__exit__` 调用 `close()`

**与异步版本的区别**：
```python
# 同步：立即初始化
# api.py:72-79
def __init__(self, config: AppServerConfig | None = None) -> None:
    self._client = AppServerClient(config=config)
    try:
        self._client.start()
        self._init = self._validate_initialize(self._client.initialize())
    except Exception:
        self._client.close()
        raise

# 异步：懒加载初始化
# api.py:278-306
async def _ensure_initialized(self) -> None:
    if self._initialized:
        return
    async with self._init_lock:
        # 延迟初始化逻辑
```

#### 2. Thread 创建流程
```python
thread = codex.thread_start(
    model="gpt-5.4", 
    config={"model_reasoning_effort": "high"}
)
```
- 调用 `Codex.thread_start()` → `AppServerClient.thread_start()`
- 直接同步调用，无需线程池包装
- 返回 `Thread` 对象包装线程 ID

#### 3. Turn 执行流程
```python
first = thread.turn(TextInput("...")).run()
```
- `thread.turn()` 创建 turn 并返回 `TurnHandle`
- `TurnHandle.run()` 消费通知流直到 `turn/completed`
- 内部调用 `_collect_run_result()` 收集结果

**同步迭代器实现**：
```python
# api.py:655-669
def stream(self) -> Iterator[Notification]:
    self._client.acquire_turn_consumer(self.id)
    try:
        while True:
            event = self._client.next_notification()  # 阻塞读取
            yield event
            if completed_condition:
                break
    finally:
        self._client.release_turn_consumer(self.id)
```

#### 4. Thread 恢复流程
```python
reopened = codex.thread_resume(thread.id)
```
- 通过 thread ID 重新获取线程句柄
- 支持传入新的 model 和 config 参数覆盖原有配置

#### 5. 列表查询流程
```python
listing_active = codex.thread_list(limit=20, archived=False)
listing_archived = codex.thread_list(limit=20, archived=True)
```
- 分页查询线程列表
- 通过 `archived` 参数区分活跃和已归档线程

#### 6. 归档/解档流程
```python
_ = codex.thread_archive(reopened.id)
unarchived = codex.thread_unarchive(reopened.id)
```
- `thread_archive()` 将线程标记为归档状态
- `thread_unarchive()` 恢复线程为活跃状态
- 返回更新后的线程信息

#### 7. 分叉流程
```python
forked = codex.thread_fork(unarchived.id, model="gpt-5.4")
```
- 基于现有线程创建新的分支线程
- 新线程继承原线程的上下文历史
- 支持指定新的模型和配置

#### 8. 压缩流程
```python
_ = unarchived.compact()
```
- 调用 `thread/compact/start` RPC 方法
- 触发服务器端的上下文压缩机制

### 数据结构

#### Thread 相关模型（来自 `generated/v2_all.py`）

```python
class ThreadStartParams(BaseModel):
    model: str | None = None
    config: JsonObject | None = None
    approval_policy: AskForApproval | None = None
    approvals_reviewer: ApprovalsReviewer | None = None
    base_instructions: str | None = None
    developer_instructions: str | None = None
    ephemeral: bool | None = None
    model_provider: str | None = None
    personality: Personality | None = None
    sandbox: SandboxMode | None = None
    service_name: str | None = None
    service_tier: ServiceTier | None = None

class ThreadStartResponse(BaseModel):
    thread: Thread  # 包含 id, created_at 等字段

class ThreadListParams(BaseModel):
    archived: bool | None = None
    cursor: str | None = None
    cwd: str | None = None
    limit: int | None = None
    model_providers: list[str] | None = None
    search_term: str | None = None
    sort_key: ThreadSortKey | None = None
    source_kinds: list[ThreadSourceKind] | None = None

class ThreadListResponse(BaseModel):
    data: list[Thread]
    next_cursor: str | None = None

class ThreadArchiveResponse(BaseModel):
    thread: Thread

class ThreadUnarchiveResponse(BaseModel):
    thread: Thread

class ThreadForkParams(BaseModel):
    thread_id: str
    approval_policy: AskForApproval | None = None
    approvals_reviewer: ApprovalsReviewer | None = None
    base_instructions: str | None = None
    config: JsonObject | None = None
    cwd: str | None = None
    developer_instructions: str | None = None
    ephemeral: bool | None = None
    model: str | None = None
    model_provider: str | None = None
    sandbox: SandboxMode | None = None
    service_tier: ServiceTier | None = None

class ThreadCompactStartResponse(BaseModel):
    # 压缩操作启动响应
```

#### Thread 类结构（来自 `api.py`）

```python
@dataclass(slots=True)
class Thread:
    _client: AppServerClient
    id: str
    
    def turn(...) -> TurnHandle
    def run(...) -> RunResult  # 便捷方法
    def read(...) -> ThreadReadResponse
    def set_name(...) -> ThreadSetNameResponse
    def compact() -> ThreadCompactStartResponse
```

### 协议与命令

#### JSON-RPC v2 协议方法

| 方法 | 描述 | 请求参数 | 响应类型 |
|------|------|----------|----------|
| `thread/start` | 创建新线程 | `ThreadStartParams` | `ThreadStartResponse` |
| `thread/resume` | 恢复已有线程 | `threadId` + `ThreadResumeParams` | `ThreadResumeResponse` |
| `thread/list` | 查询线程列表 | `ThreadListParams` | `ThreadListResponse` |
| `thread/read` | 读取线程详情 | `threadId`, `includeTurns` | `ThreadReadResponse` |
| `thread/archive` | 归档线程 | `threadId` | `ThreadArchiveResponse` |
| `thread/unarchive` | 解档线程 | `threadId` | `ThreadUnarchiveResponse` |
| `thread/fork` | 分叉线程 | `threadId` + `ThreadForkParams` | `ThreadForkResponse` |
| `thread/name/set` | 设置线程名称 | `threadId`, `name` | `ThreadSetNameResponse` |
| `thread/compact/start` | 启动压缩 | `threadId` | `ThreadCompactStartResponse` |
| `turn/start` | 开始新 turn | `TurnStartParams` | `TurnStartResponse` |

---

## 关键代码路径与文件引用

### 调用链分析

#### 1. Thread Start 调用链
```
sync.py:15
  └─> Codex.thread_start() [api.py:133-166]
        └─> AppServerClient.thread_start() [client.py:303-304]
              └─> request() [client.py:227-237]
                    └─> _request_raw() [client.py:239-270]
                          └─> JSON-RPC over stdio
```

#### 2. Turn Run 调用链
```
sync.py:17
  └─> Thread.turn() [api.py:507-538]
        └─> AppServerClient.turn_start() [client.py:352-363]
              └─> request() → _request_raw()
        └─> TurnHandle.run() [api.py:671-684]
              └─> _collect_run_result() [_run.py:59-83]
                    └─> stream() [api.py:655-669]
```

#### 3. Thread Resume 调用链
```
sync.py:20
  └─> Codex.thread_resume() [api.py:192-223]
        └─> AppServerClient.thread_resume() [client.py:306-312]
              └─> request() → _request_raw()
```

### 核心文件依赖图

```
sync.py
├── _bootstrap.py          # 运行时引导和配置
│   └── _runtime_setup.py  # 运行时包安装
├── codex_app_server
│   ├── __init__.py        # 公共 API 导出
│   ├── api.py             # Codex, Thread, TurnHandle
│   ├── client.py          # AppServerClient 同步客户端
│   ├── _run.py            # RunResult 收集逻辑
│   ├── _inputs.py         # TextInput 等输入类型
│   ├── models.py          # Notification, InitializeResponse
│   └── generated/v2_all.py # Pydantic 生成的协议模型
```

### 同步 vs 异步实现对比

| 特性 | sync.py (同步) | async.py (异步) |
|------|----------------|-----------------|
| 客户端类 | `Codex` | `AsyncCodex` |
| 线程类 | `Thread` | `AsyncThread` |
| Turn 句柄 | `TurnHandle` | `AsyncTurnHandle` |
| 初始化时机 | 立即（eager） | 延迟（lazy） |
| 上下文管理器 | `with` | `async with` |
| 方法调用 | 直接调用 | `await` |
| 流处理 | `Iterator` | `AsyncIterator` |
| 底层客户端 | `AppServerClient` | `AsyncAppServerClient` |
| 线程安全 | 单线程使用 | 单线程使用（有锁保护） |

---

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `codex_app_server.Codex` | 同步 SDK 主入口 |
| `codex_app_server.TextInput` | 文本输入包装类型 |
| `_bootstrap.runtime_config()` | 获取示例运行时配置 |
| `_bootstrap.ensure_local_sdk_src()` | 确保本地 SDK 源码可用 |

### 外部依赖

| 组件 | 交互方式 | 用途 |
|------|----------|------|
| `codex-cli-bin` | subprocess stdio | Codex app-server 运行时 |
| JSON-RPC v2 | stdio 协议 | 与 app-server 通信 |
| OpenAI API | 间接（通过 app-server） | LLM 推理服务 |

### 运行时依赖检查

```python
# _bootstrap.py:20-31
def _ensure_runtime_dependencies(sdk_python_dir: Path) -> None:
    if importlib.util.find_spec("pydantic") is not None:
        return
    # 抛出缺少依赖的错误
```

### 配置依赖

```python
# runtime_config() 返回 AppServerConfig
AppServerConfig(
    codex_bin=None,  # 使用默认的 codex-cli-bin
    launch_args_override=None,
    config_overrides=(),
    cwd=None,
    env=None,
    client_name="codex_python_sdk",
    client_version="0.2.0",
    experimental_api=True,
)
```

---

## 风险、边界与改进建议

### 已知风险

#### 1. 并发限制风险
```python
# client.py:288-296
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
- **风险**：尝试同时运行多个 turn 会导致异常
- **缓解**：代码中使用 try-finally 确保消费者正确释放

#### 2. 异常处理边界
```python
# sync.py:29-39, 41-47, 49-53
try:
    resumed = codex.thread_resume(...)
except Exception as exc:
    resumed_info = f"skipped({type(exc).__name__})"
```
- **风险**：捕获所有异常可能隐藏真正的错误
- **建议**：区分可恢复错误和致命错误，避免静默失败

#### 3. 阻塞风险
- **风险**：同步 API 会阻塞主线程，不适合 GUI 或高并发场景
- **缓解**：在需要并发的场景使用 `async.py` 模式

#### 4. 资源泄漏风险
- **风险**：如果 `with` 上下文未正确退出，可能留下僵尸进程
- **缓解**：使用上下文管理器模式确保 `close()` 被调用

### 边界条件

| 边界条件 | 行为 |
|----------|------|
| thread_id 不存在 | `thread_resume()` 可能抛出异常 |
| 已归档线程操作 | 某些操作可能需要先解档 |
| 空线程 fork | 可以基于空线程创建分支 |
| compact 重复调用 | 幂等操作，多次调用无额外副作用 |
| limit=0 的列表查询 | 返回空列表 |

### 改进建议

#### 1. 类型安全增强
```python
# 当前：使用泛型 Exception
try:
    ...
except Exception as exc:
    ...

# 建议：使用具体异常类型
from codex_app_server.errors import AppServerRpcError, TransportClosedError

try:
    ...
except AppServerRpcError as e:
    logger.error(f"RPC error: {e}")
except TransportClosedError:
    logger.error("Connection lost")
```

#### 2. 日志记录增强
```python
# 当前：仅打印最终结果
print("Lifecycle OK:", thread.id)

# 建议：添加结构化日志
import logging
logger = logging.getLogger(__name__)

logger.info("thread_lifecycle_step", extra={
    "step": "thread_start",
    "thread_id": thread.id,
    "model": "gpt-5.4"
})
```

#### 3. 配置参数化
```python
# 当前：硬编码参数
model="gpt-5.4"
config={"model_reasoning_effort": "high"}

# 建议：环境变量或配置文件
import os

model = os.getenv("CODEX_MODEL", "gpt-5.4")
reasoning_effort = os.getenv("CODEX_REASONING_EFFORT", "high")
```

#### 4. 结果验证增强
```python
# 当前：简单打印结果
print("first:", first.id, first.status)

# 建议：添加状态断言
assert first.status == TurnStatus.completed, f"Turn failed: {first.status}"
assert first.id is not None
```

#### 5. 同步并发优化（如果需要）
```python
# 当前：顺序执行
first = thread.turn(...).run()
second = thread.turn(...).run()

# 建议：使用线程池处理独立的线程操作
from concurrent.futures import ThreadPoolExecutor

with ThreadPoolExecutor() as executor:
    future1 = executor.submit(codex.thread_list, archived=False)
    future2 = executor.submit(codex.thread_list, archived=True)
    active_list = future1.result()
    archived_list = future2.result()
```

### 测试建议

1. **单元测试**：为每个生命周期操作编写独立测试用例
2. **集成测试**：验证完整的生命周期流程
3. **边界测试**：测试无效 thread_id、空线程等边界情况
4. **并发测试**：验证并发访问时的错误处理
5. **资源测试**：验证资源泄漏情况

---

## 总结

`sync.py` 是一个全面的 Thread 生命周期管理示例，展示了 Python SDK 同步 API 的核心功能。与 `async.py` 相比，它具有以下特点：

### 优势
1. **代码直观**：顺序执行，易于理解和调试
2. **无需 async/await**：降低学习成本
3. **立即初始化**：构造函数中完成所有初始化

### 劣势
1. **阻塞执行**：会阻塞主线程
2. **不适合高并发**：无法利用异步 I/O 优势
3. **难以组合**：多个独立操作的组合不如异步灵活

### 适用场景
- 命令行脚本
- 简单的自动化任务
- 数据处理和批处理作业
- 不需要高并发的应用场景

开发者可以根据实际需求选择使用 `sync.py` 或 `async.py` 模式。
