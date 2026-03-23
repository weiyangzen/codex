# sdk/python/examples/05_existing_thread/async.py 研究文档

## 场景与职责

本文件是 Codex Python SDK 的**异步示例代码**，演示如何在异步环境中恢复已存在的对话线程（thread）并继续对话。这是多轮对话场景的核心能力之一，允许应用程序：

1. 创建新的对话线程并执行第一轮对话
2. 保存线程 ID 以便后续恢复
3. 通过线程 ID 恢复已有线程的上下文
4. 在恢复的线程上继续多轮对话

该示例位于 `05_existing_thread` 目录，与 `sync.py` 共同构成同步/异步 API 的完整对照示例。

## 功能点目的

### 1. 线程生命周期管理
- **`thread_start`**: 创建新线程，配置模型参数（如 `gpt-5.4` 和 `model_reasoning_effort: high`）
- **`thread_resume`**: 通过线程 ID 恢复已有线程，保留历史对话上下文
- **`turn.run()`**: 执行单轮对话并等待完成

### 2. 异步编程模式
- 使用 `async with` 上下文管理器确保资源正确初始化和清理
- 使用 `asyncio.run(main())` 作为异步入口点
- 所有 SDK 操作均使用 `await` 进行异步调用

### 3. 对话状态验证
- 使用 `find_turn_by_id` 工具函数在持久化的线程中查找特定回合
- 使用 `assistant_text_from_turn` 提取助手的回复文本
- 通过 `resumed.read(include_turns=True)` 读取完整线程状态验证持久化

## 具体技术实现

### 关键流程

```
main()
  └── async with AsyncCodex(config=runtime_config()) as codex
        ├── codex.thread_start(model="gpt-5.4", config={...})
        │     └── 返回 AsyncThread 对象 (original)
        ├── original.turn(TextInput("Tell me one fact about Saturn."))
        │     └── 返回 AsyncTurnHandle (first_turn)
        ├── first_turn.run()
        │     └── 返回 AppServerTurn (包含 turn.id 和 status)
        ├── codex.thread_resume(original.id)
        │     └── 返回 AsyncThread 对象 (resumed)，关联同一 thread.id
        ├── resumed.turn(TextInput("Continue with one more fact."))
        │     └── 返回 AsyncTurnHandle (second_turn)
        ├── second_turn.run()
        │     └── 返回 AppServerTurn (second)
        ├── resumed.read(include_turns=True)
        │     └── 返回 ThreadReadResponse (persisted)
        └── 验证: persisted_turn = find_turn_by_id(persisted.thread.turns, second.id)
```

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
1. `AsyncCodex.thread_resume()` → `api.py:384-416`
2. → `AsyncAppServerClient.thread_resume()` → `async_client.py:105-110`
3. → `AppServerClient.thread_resume()` → `client.py:306-312`
4. → JSON-RPC `thread/resume` 请求

## 关键代码路径与文件引用

### 核心实现文件

| 文件路径 | 职责 |
|---------|------|
| `sdk/python/examples/05_existing_thread/async.py` | 本示例代码 |
| `sdk/python/examples/_bootstrap.py` | 启动工具函数（`runtime_config`, `find_turn_by_id`, `assistant_text_from_turn`） |
| `sdk/python/src/codex_app_server/api.py` | 高级 API 封装（`AsyncCodex`, `AsyncThread`, `AsyncTurnHandle`） |
| `sdk/python/src/codex_app_server/async_client.py` | 异步客户端封装（`AsyncAppServerClient`） |
| `sdk/python/src/codex_app_server/client.py` | 底层同步客户端（`AppServerClient`） |
| `sdk/python/src/codex_app_server/generated/v2_all.py` | 协议模型定义（`ThreadResumeParams`, `ThreadResumeResponse`） |

### 相关代码片段

**api.py:384-416 - AsyncCodex.thread_resume()**:
```python
async def thread_resume(
    self,
    thread_id: str,
    *,
    approval_policy: AskForApproval | None = None,
    # ... 其他可选参数
) -> AsyncThread:
    await self._ensure_initialized()
    params = ThreadResumeParams(
        thread_id=thread_id,
        approval_policy=approval_policy,
        # ...
    )
    resumed = await self._client.thread_resume(thread_id, params)
    return AsyncThread(self, resumed.thread.id)
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

## 依赖与外部交互

### 内部依赖

```
async.py
  ├── _bootstrap.py
  │     ├── ensure_local_sdk_src()      # 确保 SDK 源码在路径中
  │     ├── runtime_config()            # 返回 AppServerConfig
  │     ├── find_turn_by_id()           # 工具：按 ID 查找回合
  │     └── assistant_text_from_turn()  # 工具：提取助手文本
  └── codex_app_server
        ├── AsyncCodex                  # 异步 SDK 入口
        ├── AsyncThread                 # 线程操作封装
        ├── AsyncTurnHandle             # 回合操作封装
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
4. `AsyncCodex.__aenter__()` 启动 `codex app-server` 子进程并初始化

## 风险、边界与改进建议

### 潜在风险

1. **线程 ID 有效性**: 如果传入的 `thread_id` 不存在或已被删除，`thread_resume` 会抛出异常
2. **并发限制**: 当前实验性 SDK 限制同一时间只能有一个活动的回合消费者（见 `client.py:288-296`）
3. **资源泄漏**: 若未使用 `async with` 或忘记调用 `close()`，可能导致 `codex app-server` 子进程残留
4. **认证过期**: 长时间运行的应用可能遇到会话过期，需要重新认证

### 边界条件

| 场景 | 行为 |
|------|------|
| 恢复已归档线程 | 需要先调用 `thread_unarchive()` |
| 恢复空线程 | 有效，但 `turns` 列表为空 |
| 重复恢复同一 ID | 每次返回新的 `AsyncThread` 对象，指向同一后端线程 |
| 恢复时指定新模型 | 通过 `model` 参数覆盖原线程配置 |

### 改进建议

1. **错误处理**: 示例中缺少对 `thread_resume` 失败的处理（如线程不存在）
   ```python
   try:
       resumed = await codex.thread_resume(original.id)
   except AppServerRpcError as e:
       print(f"Failed to resume thread: {e}")
   ```

2. **配置持久化**: 示例中每次 `thread_start` 和 `thread_resume` 都重复传递 `model` 和 `config`，可考虑封装配置对象

3. **日志记录**: 添加结构化日志以便调试线程生命周期问题

4. **类型注解**: 示例中的 `_` 变量（如 `first_turn` 的结果）可以添加类型注解提高可读性

5. **资源管理**: 对于长时间运行的应用，考虑使用 `AsyncExitStack` 管理多个线程资源

### 相关测试

- `sdk/python/tests/test_client_rpc_methods.py`: 测试 RPC 方法调用
- `sdk/python/tests/test_async_client_behavior.py`: 测试异步客户端行为
- `sdk/python/tests/test_public_api_signatures.py`: 验证 `AsyncCodex.thread_resume` 签名
