# Codex App Server Python SDK 深度研究文档

**研究对象**: `sdk/python/src/codex_app_server`  
**SDK版本**: 0.2.0  
**目标协议**: Codex app-server JSON-RPC v2  
**Python版本要求**: >= 3.10  

---

## 1. 场景与职责

### 1.1 定位与目标

Codex App Server Python SDK 是一个实验性的 Python 客户端库，用于与 `codex app-server` 通过 JSON-RPC v2 over stdio 进行通信。它为开发者提供了类型安全、同步/异步双模式的高层次 API，用于：

- **对话管理**: 创建、恢复、分叉、归档对话线程 (Thread)
- **模型交互**: 执行单轮/多轮对话 (Turn)，支持流式输出
- **输入处理**: 支持文本、远程图片、本地图片、Skill、Mention 等多种输入类型
- **沙盒控制**: 配置命令执行审批策略、沙盒模式
- **错误处理**: 提供结构化的错误类型和重试机制

### 1.2 架构层级

```
┌─────────────────────────────────────────────────────────────┐
│                    用户应用层 (User App)                      │
├─────────────────────────────────────────────────────────────┤
│  高层次 API (api.py)                                        │
│  ├── Codex / AsyncCodex      # 入口类，线程生命周期管理        │
│  ├── Thread / AsyncThread    # 对话线程操作                  │
│  ├── TurnHandle / AsyncTurnHandle  # 单轮对话控制            │
│  └── RunResult               # 运行结果封装                  │
├─────────────────────────────────────────────────────────────┤
│  客户端层 (client.py / async_client.py)                     │
│  ├── AppServerClient         # 同步 JSON-RPC 客户端          │
│  ├── AsyncAppServerClient    # 异步包装器（线程卸载）         │
│  └── AppServerConfig         # 配置（二进制路径、环境等）      │
├─────────────────────────────────────────────────────────────┤
│  协议层 (generated/)                                        │
│  ├── v2_all.py               # Pydantic 模型（自动生成）       │
│  └── notification_registry.py # 通知类型注册表               │
├─────────────────────────────────────────────────────────────┤
│  传输层 (client.py)                                         │
│  └── subprocess.Popen(stdio) # codex app-server 子进程通信    │
└─────────────────────────────────────────────────────────────┘
```

### 1.3 使用场景

| 场景 | 推荐 API | 说明 |
|------|----------|------|
| 快速单轮对话 | `thread.run("prompt")` | 最简单，自动收集结果 |
| 多轮连续对话 | 同一 Thread 多次 `run()` | 保持对话上下文 |
| 流式输出 | `turn.stream()` | 实时获取增量内容 |
| 需要中断/引导 | `turn.steer()` / `turn.interrupt()` | 细粒度控制 |
| 异步应用 | `AsyncCodex` | 非阻塞 I/O |

---

## 2. 功能点目的

### 2.1 核心功能模块

#### 2.1.1 线程生命周期管理 (`Codex` / `AsyncCodex`)

| 方法 | 目的 |
|------|------|
| `thread_start()` | 创建新线程，配置模型、审批策略、沙盒等 |
| `thread_resume()` | 恢复已有线程，继续对话 |
| `thread_fork()` | 从现有线程分叉，创建独立副本 |
| `thread_list()` | 分页查询线程列表，支持归档状态过滤 |
| `thread_archive()` / `thread_unarchive()` | 归档/取消归档线程 |
| `models()` | 获取可用模型列表 |

#### 2.1.2 对话执行 (`Thread` / `AsyncThread`)

| 方法 | 目的 |
|------|------|
| `run(input)` | 便捷方法：启动 turn，等待完成，返回结果 |
| `turn(input)` | 启动 turn，返回 `TurnHandle` 用于流式控制 |
| `read()` | 获取线程详情，可选择包含 turns |
| `set_name()` | 设置线程名称 |
| `compact()` | 压缩线程上下文 |

#### 2.1.3 Turn 控制 (`TurnHandle` / `AsyncTurnHandle`)

| 方法 | 目的 |
|------|------|
| `stream()` | 生成器，产出通知事件直到 turn 完成 |
| `run()` | 阻塞直到 turn 完成，返回完整 Turn 对象 |
| `steer(input)` | 向正在执行的 turn 发送引导输入 |
| `interrupt()` | 中断正在执行的 turn |

#### 2.1.4 输入类型 (`_inputs.py`)

支持多模态输入：

- `TextInput`: 纯文本
- `ImageInput`: 远程图片 URL
- `LocalImageInput`: 本地图片路径
- `SkillInput`: 引用 Skill
- `MentionInput`: 提及（@）

### 2.2 设计决策

1. **同步优先，异步兼容**: 同步 API (`Codex`) 是主要入口，异步 (`AsyncCodex`) 通过线程卸载实现
2. **eager initialization**: `Codex()` 构造函数立即启动子进程并执行 `initialize` RPC
3. **单消费者限制**: 实验性限制，同一时间只能有一个活跃的 turn consumer
4. **snake_case API**: Python 层使用蛇形命名，自动映射到 wire 层的 camelCase

---

## 3. 具体技术实现

### 3.1 关键流程

#### 3.1.1 初始化流程 (`Codex.__init__`)

```python
# 伪代码流程
1. 创建 AppServerClient(config)
2. client.start()  # 启动 codex app-server 子进程
   - 解析 codex_bin 路径（显式配置或 codex-cli-bin 包）
   - subprocess.Popen(stdin/stdout/stderr)
   - 启动 stderr drain 线程
3. client.initialize()  # JSON-RPC 握手
   - 发送 "initialize" 请求（clientInfo, capabilities）
   - 发送 "initialized" 通知
4. 验证 initialize 响应（必须包含 serverInfo 或 userAgent）
5. 异常时自动调用 client.close()
```

**关键代码路径**: `sdk/python/src/codex_app_server/api.py:69-79`, `sdk/python/src/codex_app_server/client.py:161-189`

#### 3.1.2 Turn 执行流程 (`Thread.run`)

```python
# 伪代码流程
1. _normalize_run_input(input)  # 字符串转为 TextInput
2. _to_wire_input(input)        # 转为 JSON 格式
3. client.turn_start(thread_id, wire_input, params)  # RPC
4. turn.stream()  # 获取通知流
5. _collect_run_result(stream, turn_id)
   - 监听 ItemCompletedNotification 收集 items
   - 监听 ThreadTokenUsageUpdatedNotification 收集 usage
   - 监听 TurnCompletedNotification 确认完成
   - 提取 final_response（优先 final_answer phase，否则最后一个无 phase 消息）
```

**关键代码路径**: `sdk/python/src/codex_app_server/api.py:472-504`, `sdk/python/src/codex_app_server/_run.py:59-83`

#### 3.1.3 流式通知消费 (`TurnHandle.stream`)

```python
# 伪代码流程
1. acquire_turn_consumer(turn_id)  # 获取独占锁，拒绝并发
2. while True:
   - client.next_notification()  # 阻塞读取
   - yield notification
   - if notification is turn/completed for this turn_id: break
3. release_turn_consumer(turn_id)  # 释放锁（finally 块）
```

**关键代码路径**: `sdk/python/src/codex_app_server/api.py:655-669`

### 3.2 数据结构

#### 3.2.1 核心类型定义

```python
# sdk/python/src/codex_app_server/models.py
JsonScalar: TypeAlias = str | int | float | bool | None
JsonValue: TypeAlias = JsonScalar | dict[str, "JsonValue"] | list["JsonValue"]
JsonObject: TypeAlias = dict[str, JsonValue]

@dataclass(slots=True)
class Notification:
    method: str
    payload: NotificationPayload  # 联合类型，包含所有通知变体

@dataclass(slots=True)
class UnknownNotification:
    params: JsonObject
```

#### 3.2.2 RunResult

```python
# sdk/python/src/codex_app_server/_run.py
@dataclass(slots=True)
class RunResult:
    final_response: str | None  # 最终助手回复，可能为 None
    items: list[ThreadItem]     # 所有完成的 items
    usage: ThreadTokenUsage | None  # Token 使用量
```

#### 3.2.3 配置类

```python
# sdk/python/src/codex_app_server/client.py
@dataclass(slots=True)
class AppServerConfig:
    codex_bin: str | None = None           # 显式指定二进制路径
    launch_args_override: tuple[str, ...] | None = None  # 完全自定义启动参数
    config_overrides: tuple[str, ...] = ()  # --config 覆盖
    cwd: str | None = None                  # 工作目录
    env: dict[str, str] | None = None       # 额外环境变量
    client_name: str = "codex_python_sdk"
    client_version: str = "0.2.0"
    experimental_api: bool = True           # 启用实验性 API
```

### 3.3 协议实现

#### 3.3.1 JSON-RPC 消息格式

```python
# 请求
{"id": "uuid", "method": "thread/start", "params": {...}}

# 响应
{"id": "uuid", "result": {...}}
{"id": "uuid", "error": {"code": -32602, "message": "...", "data": ...}}

# 通知（server -> client）
{"method": "turn/completed", "params": {...}}

# 服务器请求（server -> client，需要响应）
{"id": "...", "method": "item/commandExecution/requestApproval", "params": {...}}
```

#### 3.3.2 通知处理机制

```python
# sdk/python/src/codex_app_server/client.py:455-466
def _coerce_notification(self, method: str, params: object) -> Notification:
    model = NOTIFICATION_MODELS.get(method)  # 从注册表查找
    if model is None:
        return Notification(method=method, payload=UnknownNotification(...))
    try:
        payload = model.model_validate(params_dict)
    except Exception:
        return Notification(method=method, payload=UnknownNotification(...))
    return Notification(method=method, payload=payload)
```

### 3.4 命令与 RPC 方法映射

| SDK 方法 | RPC 方法 | 参数 | 响应模型 |
|----------|----------|------|----------|
| `thread_start` | `thread/start` | `ThreadStartParams` | `ThreadStartResponse` |
| `thread_resume` | `thread/resume` | `threadId` + `ThreadResumeParams` | `ThreadResumeResponse` |
| `thread_list` | `thread/list` | `ThreadListParams` | `ThreadListResponse` |
| `thread_read` | `thread/read` | `threadId`, `includeTurns` | `ThreadReadResponse` |
| `thread_fork` | `thread/fork` | `threadId` + `ThreadForkParams` | `ThreadForkResponse` |
| `thread_archive` | `thread/archive` | `threadId` | `ThreadArchiveResponse` |
| `thread_unarchive` | `thread/unarchive` | `threadId` | `ThreadUnarchiveResponse` |
| `thread_set_name` | `thread/name/set` | `threadId`, `name` | `ThreadSetNameResponse` |
| `thread_compact` | `thread/compact/start` | `threadId` | `ThreadCompactStartResponse` |
| `turn_start` | `turn/start` | `threadId`, `input`, `TurnStartParams` | `TurnStartResponse` |
| `turn_steer` | `turn/steer` | `threadId`, `expectedTurnId`, `input` | `TurnSteerResponse` |
| `turn_interrupt` | `turn/interrupt` | `threadId`, `turnId` | `TurnInterruptResponse` |
| `model_list` | `model/list` | `includeHidden` | `ModelListResponse` |

---

## 4. 关键代码路径与文件引用

### 4.1 文件组织结构

```
sdk/python/src/codex_app_server/
├── __init__.py              # 公共 API 导出
├── api.py                   # 高层次 API (Codex, Thread, TurnHandle)
├── client.py                # 同步 JSON-RPC 客户端
├── async_client.py          # 异步客户端包装器
├── models.py                # 核心数据模型 (Notification, JsonObject, etc.)
├── errors.py                # 异常层次结构
├── retry.py                 # 重试逻辑
├── _inputs.py               # 输入类型定义与转换
├── _run.py                  # RunResult 收集逻辑
├── py.typed                 # PEP 561 类型标记
└── generated/               # 自动生成代码
    ├── __init__.py
    ├── v2_all.py            # Pydantic 模型（从 schema 生成）
    └── notification_registry.py  # 通知类型映射表
```

### 4.2 关键代码引用

#### 4.2.1 同步客户端核心逻辑

- **子进程管理**: `client.py:161-207` (`start`, `close`)
- **RPC 请求**: `client.py:227-270` (`request`, `_request_raw`)
- **通知读取**: `client.py:275-286` (`next_notification`)
- **通知类型强制**: `client.py:455-466` (`_coerce_notification`)
- **输入标准化**: `client.py:468-476` (`_normalize_input_items`)

#### 4.2.2 异步客户端

- **线程序列化**: `async_client.py:54-62` (`_call_sync` + `asyncio.Lock`)
- **流式文本**: `async_client.py:193-207` (`stream_text` 使用 `_transport_lock`)

#### 4.2.3 高层次 API

- **Codex 初始化**: `api.py:69-124` (`__init__`, `_validate_initialize`)
- **Thread.run**: `api.py:472-504` (同步), `api.py:556-588` (异步)
- **TurnHandle.stream**: `api.py:655-669` (同步), `api.py:705-720` (异步)

#### 4.2.4 结果收集

- **同步收集**: `_run.py:59-83` (`_collect_run_result`)
- **异步收集**: `_run.py:86-112` (`_collect_async_run_result`)
- **Final response 提取**: `_run.py:36-48` (`_final_assistant_response_from_items`)

#### 4.2.5 错误处理

- **错误映射**: `errors.py:90-113` (`map_jsonrpc_error`)
- **重试判断**: `errors.py:116-125` (`is_retryable_error`)
- **重试实现**: `retry.py:12-41` (`retry_on_overload`)

### 4.3 代码生成

- **生成脚本**: `sdk/python/scripts/update_sdk_artifacts.py`
- **类型生成**: `generate_v2_all()` (行 412-454)
- **通知注册表**: `generate_notification_registry()` (行 497-530)
- **公共 API 方法**: `generate_public_api_flat_methods()` (行 836-901)

---

## 5. 依赖与外部交互

### 5.1 运行时依赖

| 依赖 | 用途 | 版本要求 |
|------|------|----------|
| `pydantic` | 数据验证与序列化 | >= 2.12 |
| `codex-cli-bin` | 捆绑的 codex 二进制 | 精确版本锁定 |

### 5.2 外部进程交互

```python
# sdk/python/src/codex_app_server/client.py:178-187
self._proc = subprocess.Popen(
    args,  # [codex_bin, "app-server", "--listen", "stdio://"]
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    cwd=self.config.cwd,
    env=env,
    bufsize=1,
)
```

### 5.3 与 Rust 后端的协议对接

- **Schema 来源**: `codex-rs/app-server-protocol/schema/json/`
- **主要 Schema**: `codex_app_server_protocol.v2.schemas.json`
- **生成工具**: `datamodel-code-generator`
- **字段命名**: Python 使用 `snake_case`，wire 使用 `camelCase` (通过 Pydantic `alias` 映射)

### 5.4 开发依赖

- `pytest>=8.0`: 测试框架
- `datamodel-code-generator==0.31.2`: 类型生成
- `ruff>=0.11`: 代码格式化

---

## 6. 风险、边界与改进建议

### 6.1 已知限制与风险

#### 6.1.1 并发限制（实验性）

```python
# api.py:656-660
def stream(self) -> Iterator[Notification]:
    self._client.acquire_turn_consumer(self.id)
    try:
        ...
```

- **限制**: 同一时间只能有一个活跃的 turn consumer
- **风险**: 并发调用会抛出 `RuntimeError: Concurrent turn consumers are not yet supported`
- **缓解**: 应用层需串行化 turn 执行，或使用多个 `Codex` 实例

#### 6.1.2 初始化失败处理

```python
# api.py:74-79
try:
    self._client.start()
    self._init = self._validate_initialize(self._client.initialize())
except Exception:
    self._client.close()
    raise
```

- **行为**: 构造函数失败时会自动清理子进程
- **风险**: 如果 `codex-cli-bin` 未安装或 `codex_bin` 路径无效，构造函数立即失败

#### 6.1.3 异步初始化竞态

```python
# api.py:291-306
async def _ensure_initialized(self) -> None:
    if self._initialized:
        return
    async with self._init_lock:
        if self._initialized:
            return
        ...
```

- **实现**: 使用双检锁模式确保单次初始化
- **风险**: 已正确处理，但依赖 `asyncio.Lock`

#### 6.1.4 传输层单线程限制

```python
# async_client.py:44-45
# Single stdio transport cannot be read safely from multiple threads.
self._transport_lock = asyncio.Lock()
```

- **限制**: 异步客户端通过 `_call_sync` 将所有操作序列化到单个线程
- **影响**: 虽然是异步 API，但底层是串行执行

### 6.2 边界情况

| 场景 | 行为 | 代码位置 |
|------|------|----------|
| 未知通知类型 | 包装为 `UnknownNotification` | `client.py:459-460` |
| 通知解析失败 | 降级为 `UnknownNotification` | `client.py:463-465` |
| 空 turn 结果 | `final_response` 为 `None` | `_run.py:36-48` |
| 只有 commentary | `final_response` 为 `None` | `_run.py:44-46` |
| Turn 失败 | 抛出 `RuntimeError` | `_run.py:51-56` |
| 服务器过载 | 抛出 `ServerBusyError` | `errors.py:48-50` |
| 重试耗尽 | 抛出 `RetryLimitExceededError` | `errors.py:52-54` |

### 6.3 改进建议

#### 6.3.1 架构层面

1. **真正的异步传输**
   - 当前: 异步 API 通过线程池调用同步代码
   - 建议: 实现基于 `asyncio.subprocess` 的真正异步传输层

2. **并发 Turn 支持**
   - 当前: 全局单消费者锁
   - 建议: 按 turn_id 分离通知流，支持真正的并发 turns

3. **连接池**
   - 当前: 单连接
   - 建议: 支持多 `codex app-server` 实例池化，提高吞吐量

#### 6.3.2 功能增强

4. **更丰富的重试策略**
   - 当前: 固定指数退避
   - 建议: 支持自定义重试策略（线性退避、自定义判断条件）

5. **中间件/钩子机制**
   - 当前: 固定的 approval_handler
   - 建议: 支持链式中间件，便于日志、监控、自定义逻辑注入

6. **类型安全增强**
   - 当前: `JsonObject` 使用 `dict[str, JsonValue]`
   - 建议: 对常用配置结构提供更精确的类型定义

#### 6.3.3 可观测性

7. **结构化日志**
   - 当前: stderr drain 到内存队列（仅调试）
   - 建议: 集成标准 logging，支持请求/响应日志、性能指标

8. **事件回调**
   - 当前: 通过 `stream()` 消费通知
   - 建议: 支持注册回调函数（如 `on_turn_completed`, `on_token_usage`）

#### 6.3.4 代码质量

9. **测试覆盖**
   - 当前: 单元测试覆盖主要路径
   - 建议: 增加集成测试（真实 `codex app-server` 进程），增加边界 case 测试

10. **文档完善**
    - 当前: 基础文档齐全
    - 建议: 增加架构图、时序图、更多复杂用例示例

---

## 附录：关键类型参考

### A.1 审批策略类型

```python
# generated/v2_all.py
class AskForApprovalValue(Enum):
    untrusted = "untrusted"
    on_failure = "on-failure"
    on_request = "on-request"
    never = "never"

class GranularAskForApproval(BaseModel):
    granular: Granular  # 细粒度控制各场景

AskForApproval = AskForApprovalValue | GranularAskForApproval
```

### A.2 沙盒模式

```python
class SandboxMode(Enum):
    disabled = "disabled"
    read_only = "read-only"
    network_restricted = "network-restricted"
    network_or_full = "network-or-full"
    network_and_full = "network-and-full"
```

### A.3 错误码映射

| JSON-RPC Code | SDK 异常类型 | 说明 |
|---------------|--------------|------|
| -32700 | `ParseError` | 解析错误 |
| -32600 | `InvalidRequestError` | 无效请求 |
| -32601 | `MethodNotFoundError` | 方法不存在 |
| -32602 | `InvalidParamsError` | 参数错误 |
| -32603 | `InternalRpcError` | 内部错误 |
| -32099 ~ -32000 | `AppServerRpcError` / `ServerBusyError` / `RetryLimitExceededError` | 服务端错误 |

---

*文档生成时间: 2026-03-22*  
*基于代码版本: sdk/python 0.2.0*
