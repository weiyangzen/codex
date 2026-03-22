# Codex App Server Python SDK 深度研究文档

## 目录

1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 1.1 定位与目标

`codex_app_server` 是 Codex CLI 的 Python SDK，提供对 `codex app-server` JSON-RPC v2 协议的封装。它作为 Python 应用程序与 Codex 后端服务之间的桥梁，使开发者能够以同步或异步方式与 Codex AI 助手进行交互。

### 1.2 核心使用场景

| 场景 | 描述 |
|------|------|
| **脚本自动化** | 通过 Python 脚本批量执行 AI 任务，如代码审查、文档生成 |
| **应用集成** | 将 Codex 能力集成到第三方应用或工作流中 |
| **多轮对话** | 维护长期对话上下文（Thread），支持复杂的多轮交互 |
| **流式处理** | 实时获取 AI 生成内容，用于交互式应用 |
| **异步高并发** | 在异步环境中并发处理多个 AI 请求 |

### 1.3 架构角色

```
┌─────────────────────────────────────────────────────────────┐
│                    Python Application                        │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │   Codex()    │  │ AsyncCodex() │  │  AppServerClient │  │
│  └──────┬───────┘  └──────┬───────┘  └────────┬─────────┘  │
└─────────┼─────────────────┼───────────────────┼────────────┘
          │                 │                   │
          └─────────────────┴───────────────────┘
                            │
                    ┌───────▼────────┐
                    │  JSON-RPC v2   │
                    │   over stdio   │
                    └───────┬────────┘
                            │
                    ┌───────▼────────┐
                    │ codex-cli-bin  │
                    │  (Rust binary) │
                    └───────┬────────┘
                            │
                    ┌───────▼────────┐
                    │  OpenAI API    │
                    └────────────────┘
```

### 1.4 职责边界

- **SDK 职责**：协议封装、类型安全、连接管理、错误处理、重试机制
- **运行时职责**：二进制由 `codex-cli-bin` 包提供，SDK 只负责调用
- **非 SDK 职责**：模型训练、底层网络传输（由 Rust 层处理）

---

## 功能点目的

### 2.1 核心功能模块

#### 2.1.1 连接管理（AppServerClient）

| 功能 | 目的 | 关键类/方法 |
|------|------|------------|
| 进程生命周期 | 启动/管理 codex 子进程 | `AppServerClient.start()`, `close()` |
| stdio 传输 | 通过标准输入输出进行 JSON-RPC 通信 | `_write_message()`, `_read_message()` |
| 配置解析 | 支持自定义二进制路径、环境变量、工作目录 | `AppServerConfig` |
| 错误收集 | 捕获子进程 stderr 用于调试 | `_stderr_lines`, `_stderr_tail()` |

#### 2.1.2 线程管理（Thread）

| 功能 | 目的 | 关键类/方法 |
|------|------|------------|
| 创建线程 | 启动新的对话上下文 | `Codex.thread_start()` |
| 恢复线程 | 继续历史对话 | `Codex.thread_resume()` |
| 分支线程 | 基于现有线程创建分叉 | `Codex.thread_fork()` |
| 归档管理 | 线程的归档/解归档 | `thread_archive()`, `thread_unarchive()` |
| 线程列表 | 分页查询历史线程 | `thread_list()` |

#### 2.1.3 回合管理（Turn）

| 功能 | 目的 | 关键类/方法 |
|------|------|------------|
| 执行回合 | 发送输入并等待完整响应 | `Thread.run()` |
| 流式回合 | 实时获取生成内容 | `TurnHandle.stream()` |
| 回合控制 | 中断、引导（steer）回合 | `interrupt()`, `steer()` |
| 结果收集 | 聚合消息、用量统计 | `RunResult` |

#### 2.1.4 输入处理（Input）

| 输入类型 | 用途 | 数据结构 |
|----------|------|----------|
| `TextInput` | 纯文本输入 | `{"type": "text", "text": "..."}` |
| `ImageInput` | 网络图片 URL | `{"type": "image", "url": "..."}` |
| `LocalImageInput` | 本地图片路径 | `{"type": "localImage", "path": "..."}` |
| `SkillInput` | 调用预定义技能 | `{"type": "skill", "name": "...", "path": "..."}` |
| `MentionInput` | 引用其他实体 | `{"type": "mention", "name": "...", "path": "..."}` |

#### 2.1.5 通知处理（Notification）

| 通知类型 | 触发时机 | 处理类 |
|----------|----------|--------|
| `turn/completed` | 回合完成 | `TurnCompletedNotification` |
| `item/agentMessage/delta` | AI 消息增量更新 | `AgentMessageDeltaNotification` |
| `item/completed` | 单个项目完成 | `ItemCompletedNotification` |
| `thread/tokenUsage/updated` | 令牌用量更新 | `ThreadTokenUsageUpdatedNotification` |
| `item/commandExecution/outputDelta` | 命令执行输出 | `CommandExecutionOutputDeltaNotification` |

#### 2.1.6 错误处理与重试

| 功能 | 目的 | 关键类/方法 |
|------|------|------------|
| 错误分类 | 区分可重试与不可重试错误 | `is_retryable_error()` |
| 指数退避 | 自动重试服务器过载错误 | `retry_on_overload()` |
| 错误映射 | JSON-RPC 错误码到异常类 | `map_jsonrpc_error()` |
| 传输错误 | 连接断开检测 | `TransportClosedError` |

---

## 具体技术实现

### 3.1 JSON-RPC 协议实现

#### 3.1.1 请求格式

```python
# 请求结构（client.py:240-241）
{
    "id": str(uuid.uuid4()),      # 唯一请求 ID
    "method": "thread/start",      # RPC 方法名
    "params": {...}                # 参数对象
}
```

#### 3.1.2 响应处理流程

```python
# _request_raw 方法核心逻辑（client.py:239-270）
def _request_raw(self, method: str, params: JsonObject | None = None) -> JsonValue:
    request_id = str(uuid.uuid4())
    self._write_message({"id": request_id, "method": method, "params": params or {}})
    
    while True:
        msg = self._read_message()
        
        # 处理服务器请求（如审批请求）
        if "method" in msg and "id" in msg:
            response = self._handle_server_request(msg)
            self._write_message({"id": msg["id"], "result": response})
            continue
        
        # 缓存通知
        if "method" in msg and "id" not in msg:
            self._pending_notifications.append(...)
            continue
        
        # 匹配请求 ID
        if msg.get("id") != request_id:
            continue
        
        # 处理错误或返回结果
        if "error" in msg:
            raise map_jsonrpc_error(...)
        return msg.get("result")
```

#### 3.1.3 服务器请求处理

SDK 需要处理服务器发起的请求（如命令执行审批）：

```python
# _default_approval_handler（client.py:478-483）
def _default_approval_handler(self, method: str, params: JsonObject | None) -> JsonObject:
    if method == "item/commandExecution/requestApproval":
        return {"decision": "accept"}  # 默认自动接受
    if method == "item/fileChange/requestApproval":
        return {"decision": "accept"}
    return {}
```

### 3.2 类型系统与代码生成

#### 3.2.1 代码生成流程

```
codex-rs/app-server-protocol/schema/json/
    └── codex_app_server_protocol.v2.schemas.json
                │
                ▼
    scripts/update_sdk_artifacts.py
    ├── generate_v2_all()           # 生成 Pydantic 模型
    ├── generate_notification_registry()  # 生成通知映射
    └── generate_public_api_flat_methods()  # 生成 API 方法
                │
                ▼
    src/codex_app_server/generated/
    ├── v2_all.py                   # ~6000 行 Pydantic 模型
    └── notification_registry.py    # 通知类型映射
```

#### 3.2.2 命名转换策略

| 层级 | 命名风格 | 示例 |
|------|----------|------|
| Wire (JSON) | camelCase | `threadId`, `approvalPolicy` |
| Python 模型 | snake_case | `thread_id`, `approval_policy` |
| 序列化 | 通过 Pydantic `alias` 转换 | `Field(alias="threadId")` |

#### 3.2.3 关键配置

```python
# Pydantic 模型配置（v2_all.py 中所有模型）
model_config = ConfigDict(
    populate_by_name=True,  # 允许通过字段名或 alias 填充
)
```

### 3.3 同步/异步架构

#### 3.3.1 同步客户端（AppServerClient）

```python
class AppServerClient:
    def __init__(self, config: AppServerConfig | None = None, ...):
        self._proc: subprocess.Popen[str] | None = None
        self._lock = threading.Lock()  # 写入锁
        self._turn_consumer_lock = threading.Lock()  # 回合消费锁
```

#### 3.3.2 异步包装器（AsyncAppServerClient）

```python
class AsyncAppServerClient:
    def __init__(self, config: AppServerConfig | None = None):
        self._sync = AppServerClient(config=config)
        self._transport_lock = asyncio.Lock()  # 序列化传输调用
    
    async def _call_sync(self, fn, *args, **kwargs):
        async with self._transport_lock:
            return await asyncio.to_thread(fn, *args, **kwargs)
```

**关键设计决策**：
- 异步客户端包装同步客户端，而非原生异步实现
- 使用 `asyncio.Lock` 确保单个 stdio 传输的串行访问
- 流式方法（如 `stream_text`）在迭代期间持有锁

#### 3.3.3 回合消费者互斥

```python
# 防止并发回合消费（client.py:288-301）
def acquire_turn_consumer(self, turn_id: str) -> None:
    with self._turn_consumer_lock:
        if self._active_turn_consumer is not None:
            raise RuntimeError(
                "Concurrent turn consumers are not yet supported..."
            )
        self._active_turn_consumer = turn_id
```

### 3.4 输入处理与序列化

#### 3.4.1 输入规范化

```python
# _inputs.py:54-62
def _to_wire_input(input: Input) -> list[JsonObject]:
    if isinstance(input, list):
        return [_to_wire_item(i) for i in input]
    return [_to_wire_item(input)]

def _normalize_run_input(input: RunInput) -> Input:
    if isinstance(input, str):
        return TextInput(input)  # 字符串自动转为 TextInput
    return input
```

#### 3.4.2 参数序列化

```python
# client.py:53-77
def _params_dict(params) -> JsonObject:
    if params is None:
        return {}
    if hasattr(params, "model_dump"):
        dumped = params.model_dump(
            by_alias=True,      # 使用 camelCase alias
            exclude_none=True,  # 排除 None 值
            mode="json",        # JSON 可序列化模式
        )
        return dumped
    if isinstance(params, dict):
        return params
```

### 3.5 结果收集与解析

#### 3.5.1 RunResult 构建

```python
# _run.py:59-83
def _collect_run_result(stream: Iterator[Notification], *, turn_id: str) -> RunResult:
    completed: TurnCompletedNotification | None = None
    items: list[ThreadItem] = []
    usage: ThreadTokenUsage | None = None

    for event in stream:
        payload = event.payload
        if isinstance(payload, ItemCompletedNotification) and payload.turn_id == turn_id:
            items.append(payload.item)
        if isinstance(payload, ThreadTokenUsageUpdatedNotification) and payload.turn_id == turn_id:
            usage = payload.token_usage
        if isinstance(payload, TurnCompletedNotification) and payload.turn.id == turn_id:
            completed = payload

    _raise_for_failed_turn(completed.turn)
    return RunResult(
        final_response=_final_assistant_response_from_items(items),
        items=items,
        usage=usage,
    )
```

#### 3.5.2 最终响应提取

```python
# _run.py:36-48
def _final_assistant_response_from_items(items: list[ThreadItem]) -> str | None:
    last_unknown_phase_response: str | None = None
    
    for item in reversed(items):
        agent_message = _agent_message_item_from_thread_item(item)
        if agent_message is None:
            continue
        if agent_message.phase == MessagePhase.final_answer:
            return agent_message.text
        if agent_message.phase is None and last_unknown_phase_response is None:
            last_unknown_phase_response = agent_message.text
    
    return last_unknown_phase_response
```

### 3.6 错误处理机制

#### 3.6.1 JSON-RPC 错误码映射

| 错误码 | 异常类 | 说明 |
|--------|--------|------|
| -32700 | `ParseError` | 解析错误 |
| -32600 | `InvalidRequestError` | 无效请求 |
| -32601 | `MethodNotFoundError` | 方法未找到 |
| -32602 | `InvalidParamsError` | 无效参数 |
| -32603 | `InternalRpcError` | 内部 RPC 错误 |
| -32000 ~ -32099 | `ServerBusyError` / `RetryLimitExceededError` | 服务器端错误 |

#### 3.6.2 服务器过载检测

```python
# errors.py:61-87
def _is_server_overloaded(data: Any) -> bool:
    if data is None:
        return False
    if isinstance(data, str):
        return data.lower() == "server_overloaded"
    if isinstance(data, dict):
        # 检查多层嵌套结构
        direct = data.get("codex_error_info") or data.get("codexErrorInfo")
        if isinstance(direct, str) and direct.lower() == "server_overloaded":
            return True
        for value in data.values():
            if _is_server_overloaded(value):
                return True
    if isinstance(data, list):
        return any(_is_server_overloaded(value) for value in data)
    return False
```

#### 3.6.3 重试策略

```python
# retry.py:12-41
def retry_on_overload(
    op: Callable[[], T],
    *,
    max_attempts: int = 3,
    initial_delay_s: float = 0.25,
    max_delay_s: float = 2.0,
    jitter_ratio: float = 0.2,
) -> T:
    delay = initial_delay_s
    attempt = 0
    while True:
        attempt += 1
        try:
            return op()
        except Exception as exc:
            if attempt >= max_attempts:
                raise
            if not is_retryable_error(exc):
                raise
            
            jitter = delay * jitter_ratio
            sleep_for = min(max_delay_s, delay) + random.uniform(-jitter, jitter)
            time.sleep(sleep_for)
            delay = min(max_delay_s, delay * 2)  # 指数退避
```

---

## 关键代码路径与文件引用

### 4.1 文件结构

```
sdk/python/src/codex_app_server/
├── __init__.py              # 公共 API 导出
├── api.py                   # 高层 API（Codex, Thread, TurnHandle）
├── client.py                # 同步 JSON-RPC 客户端
├── async_client.py          # 异步客户端包装器
├── models.py                # 核心数据模型（Notification, InitializeResponse）
├── errors.py                # 异常层次结构
├── retry.py                 # 重试逻辑
├── _inputs.py               # 输入类型定义与序列化
├── _run.py                  # 结果收集逻辑
└── generated/
    ├── __init__.py          # 生成包标记
    ├── v2_all.py            # 自动生成的 Pydantic 模型（~6000 行）
    └── notification_registry.py  # 通知类型映射
```

### 4.2 关键代码路径

#### 4.2.1 初始化流程

```
Codex.__init__()
    └── client.py:161-189 AppServerClient.start()
        └── _resolve_codex_bin()  # 解析二进制路径
        └── subprocess.Popen()    # 启动子进程
    └── client.py:209-225 initialize()
        └── request("initialize", ...)  # 发送初始化请求
        └── notify("initialized", None) # 通知初始化完成
```

#### 4.2.2 线程创建流程

```
Codex.thread_start()
    └── api.py:133-166
        └── ThreadStartParams(...)  # 构建参数
        └── client.py:303-304 thread_start()
            └── request("thread/start", ...)
        └── Thread(self._client, started.thread.id)  # 返回 Thread 对象
```

#### 4.2.3 回合执行流程

```
Thread.run()
    └── api.py:472-504
        └── _normalize_run_input()  # 规范化输入
        └── Thread.turn()           # 创建回合
            └── client.py:352-363 turn_start()
        └── TurnHandle.stream()     # 获取事件流
        └── _collect_run_result()   # 收集结果
```

#### 4.2.4 流式处理流程

```
TurnHandle.stream()
    └── api.py:655-669
        └── acquire_turn_consumer()  # 获取消费锁
        └── next_notification() 循环
            └── 匹配 turn/completed 时退出
        └── release_turn_consumer()  # 释放锁
```

#### 4.2.5 通知处理流程

```
next_notification()
    └── client.py:275-286
        └── _coerce_notification()
            └── notification_registry.py:57-106 NOTIFICATION_MODELS 映射
            └── Pydantic model_validate()
```

### 4.3 测试覆盖

| 测试文件 | 覆盖范围 |
|----------|----------|
| `test_client_rpc_methods.py` | RPC 方法调用、参数序列化、通知解析 |
| `test_async_client_behavior.py` | 异步序列化、流式阻塞行为 |
| `test_public_api_runtime_behavior.py` | 高层 API 行为、结果收集、并发控制 |
| `test_public_api_signatures.py` | API 签名一致性、类型注解 |
| `test_contract_generation.py` | 代码生成一致性检查 |
| `test_artifact_workflow_and_binaries.py` | 发布流程、运行时包管理 |

---

## 依赖与外部交互

### 5.1 内部依赖

#### 5.1.1 与 Rust 层的接口

| 接口 | 方式 | 说明 |
|------|------|------|
| JSON Schema | 文件读取 | `codex-rs/app-server-protocol/schema/json/*.json` |
| 二进制调用 | subprocess | `codex app-server --listen stdio://` |
| 协议版本 | v2 | 通过 `initialize` 握手确认 |

#### 5.1.2 运行时包依赖

```python
# client.py:80-91
def _installed_codex_path() -> Path:
    from codex_cli_bin import bundled_codex_path  # 运行时包导入
    return bundled_codex_path()
```

### 5.2 外部依赖

#### 5.2.1 Python 依赖（pyproject.toml）

```toml
[project]
dependencies = ["pydantic>=2.12"]

[project.optional-dependencies]
dev = ["pytest>=8.0", "datamodel-code-generator==0.31.2", "ruff>=0.11"]
```

#### 5.2.2 版本兼容性

| 组件 | 版本要求 |
|------|----------|
| Python | >= 3.10 |
| Pydantic | >= 2.12 |
| codex-cli-bin | 与 SDK 版本绑定 |

### 5.3 协议交互

#### 5.3.1 初始化握手

```json
// Client -> Server
{
  "id": "uuid",
  "method": "initialize",
  "params": {
    "clientInfo": {
      "name": "codex_python_sdk",
      "title": "Codex Python SDK",
      "version": "0.2.0"
    },
    "capabilities": {
      "experimentalApi": true
    }
  }
}

// Server -> Client
{
  "id": "uuid",
  "result": {
    "serverInfo": {"name": "codex-cli", "version": "x.y.z"},
    "userAgent": "codex-cli/x.y.z"
  }
}

// Client -> Server
{"method": "initialized", "params": {}}
```

#### 5.3.2 典型请求-响应模式

```json
// thread/start
{"id": "1", "method": "thread/start", "params": {"model": "gpt-5.4"}}
{"id": "1", "result": {"thread": {"id": "thr_xxx", ...}}}

// turn/start
{"id": "2", "method": "turn/start", "params": {"threadId": "thr_xxx", "input": [...]}}
{"id": "2", "result": {"turn": {"id": "turn_yyy", "status": "inProgress", ...}}}
```

---

## 风险、边界与改进建议

### 6.1 已知限制

#### 6.1.1 并发限制

| 限制 | 影响 | 代码位置 |
|------|------|----------|
| 单回合消费者 | 同一客户端不能并发执行多个 `run()`/`stream()` | `client.py:288-301` |
| 单传输锁 | 流式期间阻塞其他 API 调用 | `async_client.py:45,199` |
| 线程不安全 | `AppServerClient` 非线程安全 | 设计如此 |

#### 6.1.2 实验性功能

- `experimental_api=True` 默认开启，API 可能变化
- 异步客户端的流式实现为线程包装，性能非最优
- 审批处理器默认自动接受所有请求

### 6.2 潜在风险

#### 6.2.1 进程管理风险

```python
# client.py:191-207 close() 方法
# 风险：terminate() 后 2 秒超时可能不足，kill() 可能导致数据丢失
def close(self) -> None:
    if proc.stdin:
        proc.stdin.close()
    try:
        proc.terminate()
        proc.wait(timeout=2)
    except Exception:
        proc.kill()
```

#### 6.2.2 错误处理风险

- `ServerBusyError` 检测依赖字符串匹配，可能误报/漏报
- JSON-RPC 错误数据字段结构复杂，解析可能不完整

#### 6.2.3 类型安全风险

- 部分生成的 Pydantic 模型使用 `Any` 类型（如 `Resource.annotations`）
- `UnknownNotification` 回退可能隐藏协议变更

### 6.3 改进建议

#### 6.3.1 架构改进

| 优先级 | 建议 | 预期收益 |
|--------|------|----------|
| 高 | 原生异步传输实现 | 消除线程包装开销，支持真并发 |
| 高 | 回合级事件多路复用 | 支持多回合并发消费 |
| 中 | 连接池/连接复用 | 减少进程启动开销 |
| 中 | 流式 JSON 解析 | 降低大响应内存占用 |

#### 6.3.2 可靠性改进

```python
# 建议：增加进程健康检查
class AppServerClient:
    def _health_check(self) -> bool:
        """检查子进程是否存活且响应"""
        if self._proc is None or self._proc.poll() is not None:
            return False
        # 发送 ping 请求验证响应
        ...
```

#### 6.3.3 可观测性改进

| 建议 | 实现方式 |
|------|----------|
| 结构化日志 | 替换 `print`/`stderr` 为 logging |
| 指标收集 | 请求延迟、重试次数、错误率 |
| 分布式追踪 | OpenTelemetry 集成 |

#### 6.3.4 API 改进

```python
# 建议：上下文管理器支持 TurnHandle
with thread.turn("...") as turn:
    for event in turn.stream():
        ...
# 自动处理 interrupt 或 cleanup

# 建议：更灵活的审批策略
@dataclass
class ApprovalConfig:
    command_execution: Literal["accept", "reject", "prompt"]
    file_change: Literal["accept", "reject", "prompt"]
    callback: Callable[[ApprovalRequest], ApprovalDecision] | None
```

### 6.4 代码生成改进

| 建议 | 说明 |
|------|------|
| 增量生成 | 仅变更的 schema 定义重新生成 |
| 版本校验 | 生成文件嵌入 schema 版本哈希 |
| 文档生成 | 从 schema 描述生成 API 文档 |

### 6.5 测试建议

| 建议 | 优先级 |
|------|--------|
| 集成测试（真实 codex 进程） | 高 |
| 混沌测试（模拟网络/进程故障） | 中 |
| 性能基准测试（大消息、高并发） | 中 |
| 协议兼容性测试（多版本） | 低 |

---

## 附录：关键数据结构

### A.1 AppServerConfig

```python
@dataclass(slots=True)
class AppServerConfig:
    codex_bin: str | None = None              # 自定义二进制路径
    launch_args_override: tuple[str, ...] | None = None  # 完全自定义启动参数
    config_overrides: tuple[str, ...] = ()    # --config 覆盖
    cwd: str | None = None                    # 工作目录
    env: dict[str, str] | None = None         # 额外环境变量
    client_name: str = "codex_python_sdk"
    client_title: str = "Codex Python SDK"
    client_version: str = "0.2.0"
    experimental_api: bool = True
```

### A.2 RunResult

```python
@dataclass(slots=True)
class RunResult:
    final_response: str | None    # 最终助手回复（可能为 None）
    items: list[ThreadItem]       # 所有完成的条目
    usage: ThreadTokenUsage | None  # 令牌用量统计
```

### A.3 通知类型层次

```
Notification
├── method: str
└── payload: NotificationPayload
    ├── AccountLoginCompletedNotification
    ├── AgentMessageDeltaNotification
    ├── CommandExecutionOutputDeltaNotification
    ├── ItemCompletedNotification
    ├── ThreadTokenUsageUpdatedNotification
    ├── TurnCompletedNotification
    ├── TurnStartedNotification
    ├── ... (40+ 类型)
    └── UnknownNotification  # 回退类型
```

---

*文档生成时间：2026-03-22*
*基于代码版本：sdk/python/src/codex_app_server/ (v0.2.0)*
