# sdk/python/examples/05_existing_thread/sync.py 研究文档

## 场景与职责

本文件是 Codex Python SDK 的**同步示例代码**，演示如何在同步环境中恢复已存在的对话线程（thread）并继续对话。这是多轮对话场景的核心能力之一，与异步版本 (`async.py`) 功能对等，但使用同步阻塞式 API。

主要应用场景：
1. 脚本化工具和非异步应用
2. Jupyter Notebook 交互式使用
3. 简单的命令行工具
4. 需要顺序执行、无需并发的场景

## 功能点目的

### 1. 线程生命周期管理
- **`thread_start`**: 创建新线程，配置模型参数（如 `gpt-5.4` 和 `model_reasoning_effort: high`）
- **`thread_resume`**: 通过线程 ID 恢复已有线程，保留历史对话上下文
- **`turn.run()`**: 执行单轮对话并阻塞等待完成

### 2. 同步编程模式
- 使用 `with` 上下文管理器确保资源正确初始化和清理
- 所有 SDK 调用均为同步阻塞式，代码直观线性

### 3. 对话状态验证
- 使用 `find_turn_by_id` 工具函数在持久化的线程中查找特定回合
- 使用 `assistant_text_from_turn` 提取助手的回复文本
- 通过 `resumed.read(include_turns=True)` 读取完整线程状态验证持久化

## 具体技术实现

### 关键流程

```
main (with 上下文)
  └── with Codex(config=runtime_config()) as codex
        ├── codex.thread_start(model="gpt-5.4", config={...})
        │     └── 返回 Thread 对象 (original)
        ├── original.turn(TextInput("Tell me one fact about Saturn.")).run()
        │     └── 返回 AppServerTurn (first)
        ├── codex.thread_resume(original.id)
        │     └── 返回 Thread 对象 (resumed)，关联同一 thread.id
        ├── resumed.turn(TextInput("Continue with one more fact.")).run()
        │     └── 返回 AppServerTurn (second)
        ├── resumed.read(include_turns=True)
        │     └── 返回 ThreadReadResponse (persisted)
        └── 验证: persisted_turn = find_turn_by_id(persisted.thread.turns, second.id)
```

### 与异步版本的核心差异

| 特性 | sync.py | async.py |
|------|---------|----------|
| 入口类 | `Codex` | `AsyncCodex` |
| 上下文管理器 | `with` | `async with` |
| 方法调用 | 直接调用 | `await` 调用 |
| 线程对象 | `Thread` | `AsyncThread` |
| 回合句柄 | `TurnHandle` | `AsyncTurnHandle` |
| 流式 API | 同步迭代器 | 异步迭代器 (`AsyncIterator`) |

### 数据结构

**ThreadResumeParams** (来自 `generated/v2_all.py`):
```python
class ThreadResumeParams(BaseModel):
    thread_id: str                          # 必需，要恢复的线程 ID
    approval_policy: AskForApproval | None  # 审批策略覆盖
    approvals_reviewer: ApprovalsReviewer | None
    base_instructions: str | None
    config: dict[str, Any] | None           # 模型配置覆盖
    cwd: str | None
    developer_instructions: str | None
    model: str | None                       # 模型覆盖
    model_provider: str | None
    personality: Personality | None
    sandbox: SandboxMode | None
    service_tier: ServiceTier | None
```

**ThreadResumeResponse**:
- 包含 `thread: Thread` 字段，其中 `thread.id` 与传入的 `thread_id` 一致
- 包含 `turns` 字段（仅在 `thread/resume` 响应中填充），包含线程的历史回合

### 协议与命令

**JSON-RPC 方法**: `thread/resume`

请求格式:
```json
{
  "id": "<uuid>",
  "method": "thread/resume",
  "params": {
    "threadId": "<thread_id>",
    "model": "gpt-5.4",
    "config": {"model_reasoning_effort": "high"}
  }
}
```

**关键代码路径**:
1. `Codex.thread_resume()` → `api.py:192-223`
2. → `AppServerClient.thread_resume()` → `client.py:306-312`
3. → JSON-RPC `thread/resume` 请求

## 关键代码路径与文件引用

### 核心实现文件

| 文件路径 | 职责 |
|---------|------|
| `sdk/python/examples/05_existing_thread/sync.py` | 本示例代码 |
| `sdk/python/examples/_bootstrap.py` | 启动工具函数（`runtime_config`, `find_turn_by_id`, `assistant_text_from_turn`） |
| `sdk/python/src/codex_app_server/api.py` | 高级 API 封装（`Codex`, `Thread`, `TurnHandle`） |
| `sdk/python/src/codex_app_server/client.py` | 底层同步客户端（`AppServerClient`） |
| `sdk/python/src/codex_app_server/generated/v2_all.py` | 协议模型定义（`ThreadResumeParams`, `ThreadResumeResponse`） |

### 相关代码片段

**api.py:192-223 - Codex.thread_resume()**:
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
        approvals_reviewer=approvals_reviewer,
        base_instructions=base_instructions,
        config=config,
        cwd=cwd,
        developer_instructions=developer_instructions,
        model=model,
        model_provider=model_provider,
        personality=personality,
        sandbox=sandbox,
        service_tier=service_tier,
    )
    resumed = self._client.thread_resume(thread_id, params)
    return Thread(self._client, resumed.thread.id)
```

**client.py:306-312 - AppServerClient.thread_resume()**:
```python
def thread_resume(
    self,
    thread_id: str,
    params: V2ThreadResumeParams | JsonObject | None = None,
) -> ThreadResumeResponse:
    payload = {"threadId": thread_id, **_params_dict(params)}
    return self.request("thread/resume", payload, response_model=ThreadResumeResponse)
```

**TurnHandle.run() - api.py:671-684**:
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

## 依赖与外部交互

### 内部依赖

```
sync.py
  ├── _bootstrap.py
  │     ├── ensure_local_sdk_src()      # 确保 SDK 源码在路径中
  │     ├── runtime_config()            # 返回 AppServerConfig
  │     ├── find_turn_by_id()           # 工具：按 ID 查找回合
  │     └── assistant_text_from_turn()  # 工具：提取助手文本
  └── codex_app_server
        ├── Codex                       # 同步 SDK 入口
        ├── Thread                      # 线程操作封装
        ├── TurnHandle                  # 回合操作封装
        └── TextInput                   # 文本输入类型
```

### 外部依赖

1. **Codex CLI 运行时**: 通过 `runtime_config()` 配置的 `codex app-server` 进程
2. **认证**: 依赖本地配置的 Codex 认证/会话
3. **模型服务**: 通过 `gpt-5.4` 模型进行推理

### 启动流程

1. `_bootstrap.py` 将 `sdk/python/src` 添加到 `sys.path`
2. `ensure_local_sdk_src()` 验证本地 SDK 可用性
3. `runtime_config()` 创建默认 `AppServerConfig`
4. `Codex.__enter__()` 启动 `codex app-server` 子进程并初始化

## 风险、边界与改进建议

### 潜在风险

1. **线程 ID 有效性**: 如果传入的 `thread_id` 不存在或已被删除，`thread_resume` 会抛出异常
2. **并发限制**: 当前实验性 SDK 限制同一时间只能有一个活动的回合消费者（见 `client.py:288-296`）
3. **资源泄漏**: 若未使用 `with` 上下文或忘记调用 `close()`，可能导致 `codex app-server` 子进程残留
4. **阻塞风险**: 同步 API 会阻塞直到操作完成，不适合需要并发的场景

### 边界条件

| 场景 | 行为 |
|------|------|
| 恢复已归档线程 | 需要先调用 `thread_unarchive()` |
| 恢复空线程 | 有效，但 `turns` 列表为空 |
| 重复恢复同一 ID | 每次返回新的 `Thread` 对象，指向同一后端线程 |
| 恢复时指定新模型 | 通过 `model` 参数覆盖原线程配置 |

### 改进建议

1. **错误处理**: 示例中缺少对 `thread_resume` 失败的处理（如线程不存在）
   ```python
   try:
       resumed = codex.thread_resume(original.id)
   except AppServerRpcError as e:
       print(f"Failed to resume thread: {e}")
   ```

2. **配置持久化**: 示例中每次 `thread_start` 和 `thread_resume` 都重复传递 `model` 和 `config`，可考虑封装配置对象

3. **日志记录**: 添加结构化日志以便调试线程生命周期问题

4. **类型注解**: 示例中的变量可以添加类型注解提高可读性
   ```python
   from codex_app_server.generated.v2_all import AppServerTurn
   
   first: AppServerTurn = original.turn(...).run()
   ```

5. **链式调用优化**: 当前 `turn().run()` 的链式调用在复杂场景下可读性较差，可考虑添加 `thread.run(input)` 快捷方法

### 相关测试

- `sdk/python/tests/test_client_rpc_methods.py`: 测试 RPC 方法调用
- `sdk/python/tests/test_public_api_signatures.py`: 验证 `Codex.thread_resume` 签名
- `sdk/python/tests/test_public_api_runtime_behavior.py`: 测试运行时行为

### 与相关示例的关系

| 示例 | 说明 |
|------|------|
| `01_quickstart_constructor` | 基础 SDK 使用 |
| `02_turn_run` | 回合执行基础 |
| `06_thread_lifecycle_and_controls` | 更完整的线程生命周期演示（包含 archive/unarchive/fork） |
| `05_existing_thread/sync.py` | 本文件：专注线程恢复功能 |
