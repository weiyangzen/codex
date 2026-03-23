# async.py 深度研究文档

## 场景与职责

`async.py` 是 Python SDK 中关于 **Thread 生命周期管理** 的异步示例程序。它展示了如何使用 `AsyncCodex` 客户端对对话线程（Thread）进行完整的生命周期操作，包括创建、对话、恢复、归档、解档、分叉和压缩等操作。

### 核心职责
1. 演示异步模式下 Thread 的完整生命周期管理
2. 展示高级 Thread 控制操作（archive/unarchive/fork/compact）
3. 验证 SDK 异步 API 的正确性和可用性
4. 作为开发者学习和参考的示例代码

---

## 功能点目的

### 1. Thread 创建与对话
- **目的**：创建新线程并进行多轮对话
- **关键操作**：`thread_start()` → `turn()` → `run()`
- **意义**：建立基础对话上下文，为后续生命周期操作提供测试数据

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
async with AsyncCodex(config=runtime_config()) as codex:
```
- 使用异步上下文管理器确保资源正确释放
- `runtime_config()` 从 `_bootstrap` 模块获取配置
- `AsyncCodex` 在 `__aenter__` 时调用 `_ensure_initialized()` 进行懒加载初始化

#### 2. Thread 创建流程
```python
thread = await codex.thread_start(
    model="gpt-5.4", 
    config={"model_reasoning_effort": "high"}
)
```
- 调用 `AsyncCodex.thread_start()` → `AsyncAppServerClient.thread_start()`
- 通过 `_call_sync()` 在线程池中执行同步调用
- 返回 `AsyncThread` 对象包装线程 ID

#### 3. Turn 执行流程
```python
first = await (await thread.turn(TextInput("..."))).run()
```
- `thread.turn()` 创建 turn 并返回 `AsyncTurnHandle`
- `AsyncTurnHandle.run()` 消费通知流直到 `turn/completed`
- 内部调用 `_collect_async_run_result()` 收集结果

#### 4. Thread 恢复流程
```python
reopened = await codex.thread_resume(thread.id)
```
- 通过 thread ID 重新获取线程句柄
- 支持传入新的 model 和 config 参数覆盖原有配置

#### 5. 列表查询流程
```python
listing_active = await codex.thread_list(limit=20, archived=False)
listing_archived = await codex.thread_list(limit=20, archived=True)
```
- 分页查询线程列表
- 通过 `archived` 参数区分活跃和已归档线程

#### 6. 归档/解档流程
```python
_ = await codex.thread_archive(reopened.id)
unarchived = await codex.thread_unarchive(reopened.id)
```
- `thread_archive()` 将线程标记为归档状态
- `thread_unarchive()` 恢复线程为活跃状态
- 返回更新后的线程信息

#### 7. 分叉流程
```python
forked = await codex.thread_fork(unarchived.id, model="gpt-5.4")
```
- 基于现有线程创建新的分支线程
- 新线程继承原线程的上下文历史
- 支持指定新的模型和配置

#### 8. 压缩流程
```python
_ = await unarchived.compact()
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
    # ... 其他参数

class ThreadStartResponse(BaseModel):
    thread: Thread  # 包含 id, created_at 等字段

class ThreadListParams(BaseModel):
    archived: bool | None = None
    cursor: str | None = None
    limit: int | None = None
    # ... 其他过滤参数

class ThreadListResponse(BaseModel):
    data: list[Thread]
    next_cursor: str | None = None

class ThreadArchiveResponse(BaseModel):
    thread: Thread

class ThreadUnarchiveResponse(BaseModel):
    thread: Thread

class ThreadForkParams(BaseModel):
    thread_id: str
    model: str | None = None
    config: JsonObject | None = None
    # ... 其他参数

class ThreadCompactStartResponse(BaseModel):
    # 压缩操作启动响应
```

#### AsyncThread 类结构（来自 `api.py`）

```python
@dataclass(slots=True)
class AsyncThread:
    _codex: AsyncCodex
    id: str
    
    async def turn(...) -> AsyncTurnHandle
    async def run(...) -> RunResult  # 便捷方法
    async def read(...) -> ThreadReadResponse
    async def set_name(...) -> ThreadSetNameResponse
    async def compact() -> ThreadCompactStartResponse
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
async.py:18
  └─> AsyncCodex.thread_start() [api.py:323-357]
        └─> AsyncAppServerClient.thread_start() [async_client.py:102-103]
              └─> _call_sync() [async_client.py:54-62]
                    └─> AppServerClient.thread_start() [client.py:303-304]
                          └─> request() [client.py:227-237]
                                └─> _request_raw() [client.py:239-270]
                                      └─> JSON-RPC over stdio
```

#### 2. Turn Run 调用链
```
async.py:20
  └─> AsyncThread.turn() [api.py:591-627]
        └─> AsyncAppServerClient.turn_start() [async_client.py:137-143]
              └─> _call_sync() → AppServerClient.turn_start() [client.py:352-363]
        └─> AsyncTurnHandle.run() [api.py:722-735]
              └─> _collect_async_run_result() [_run.py:86-112]
```

#### 3. Thread Resume 调用链
```
async.py:23
  └─> AsyncCodex.thread_resume() [api.py:384-416]
        └─> AsyncAppServerClient.thread_resume() [async_client.py:105-110]
              └─> AppServerClient.thread_resume() [client.py:306-312]
```

### 核心文件依赖图

```
async.py
├── _bootstrap.py          # 运行时引导和配置
│   └── _runtime_setup.py  # 运行时包安装
├── codex_app_server
│   ├── __init__.py        # 公共 API 导出
│   ├── api.py             # AsyncCodex, AsyncThread, AsyncTurnHandle
│   ├── async_client.py    # AsyncAppServerClient 包装器
│   ├── client.py          # AppServerClient 同步客户端
│   ├── _run.py            # RunResult 收集逻辑
│   ├── _inputs.py         # TextInput 等输入类型
│   ├── models.py          # Notification, InitializeResponse
│   └── generated/v2_all.py # Pydantic 生成的协议模型
```

---

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `codex_app_server.AsyncCodex` | 异步 SDK 主入口 |
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
# async_client.py:82-86
def acquire_turn_consumer(self, turn_id: str) -> None:
    # 当前实验性 SDK 仅支持单 turn 消费者
    # 并发调用会抛出 RuntimeError
```
- **风险**：尝试同时运行多个 turn 会导致异常
- **缓解**：代码中使用 try-finally 确保消费者正确释放

#### 2. 异常处理边界
```python
# async.py:33-42, 44-50, 52-56
try:
    resumed = await codex.thread_resume(...)
except Exception as exc:
    resumed_info = f"skipped({type(exc).__name__})"
```
- **风险**：捕获所有异常可能隐藏真正的错误
- **建议**：区分可恢复错误和致命错误，避免静默失败

#### 3. 资源泄漏风险
- **风险**：如果 `async with` 上下文未正确退出，可能留下僵尸进程
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

#### 5. 异步并发优化
```python
# 当前：顺序执行
first = await (await thread.turn(...)).run()
second = await (await thread.turn(...)).run()

# 建议：如果业务允许，支持并发 turn（需 SDK 支持）
# 或使用 asyncio.gather 处理独立的线程操作
results = await asyncio.gather(
    codex.thread_list(archived=False),
    codex.thread_list(archived=True)
)
```

### 测试建议

1. **单元测试**：为每个生命周期操作编写独立测试用例
2. **集成测试**：验证完整的生命周期流程
3. **边界测试**：测试无效 thread_id、空线程等边界情况
4. **并发测试**：验证并发访问时的错误处理
5. **资源测试**：验证资源泄漏情况

---

## 总结

`async.py` 是一个全面的 Thread 生命周期管理示例，展示了 Python SDK 异步 API 的核心功能。它通过实际的代码演示了如何：

1. 正确初始化和关闭异步客户端
2. 管理 Thread 的完整生命周期
3. 处理异常和边界情况
4. 使用高级功能如 fork 和 compact

开发者可以参考此示例构建自己的异步 Codex 应用程序。
