# SDK/Python/Tests 深度研究文档

## 1. 场景与职责

### 1.1 目录定位

`sdk/python/tests/` 是 Codex Python SDK 的测试套件目录，负责验证以下核心功能：

- **协议兼容性**: 验证 Python SDK 与 Rust app-server 之间的 JSON-RPC v2 协议通信
- **代码生成正确性**: 验证从 JSON Schema 生成的 Python 类型定义与原始协议保持一致
- **运行时行为**: 验证同步/异步客户端的行为符合预期（连接管理、流控制、错误处理）
- **公共 API 契约**: 验证对外暴露的 API 签名、类型注解、命名规范
- **制品发布流程**: 验证 SDK 和 runtime 包的构建、打包、版本管理流程

### 1.2 测试分层架构

```
┌─────────────────────────────────────────────────────────────────┐
│                    测试目标分层                                   │
├─────────────────────────────────────────────────────────────────┤
│  Layer 4: 集成测试 (test_real_app_server_integration.py)         │
│           - 需要真实 Codex runtime (RUN_REAL_CODEX_TESTS=1)      │
│           - 端到端验证 SDK + Runtime + App Server               │
├─────────────────────────────────────────────────────────────────┤
│  Layer 3: 运行时行为测试 (test_public_api_runtime_behavior.py)   │
│           - 模拟通知流，验证 Turn/Thread 生命周期                │
│           - 验证流控、并发、初始化失败处理                        │
├─────────────────────────────────────────────────────────────────┤
│  Layer 2: 契约测试 (test_contract_generation.py)                 │
│           - 验证生成代码与 Schema 的一致性                       │
│           - 防止生成制品漂移 (generated files drift)             │
├─────────────────────────────────────────────────────────────────┤
│  Layer 1: 单元测试 (test_client_rpc_methods.py,                 │
│                    test_async_client_behavior.py,               │
│                    test_public_api_signatures.py)               │
│           - 方法调用验证、参数序列化、类型注解                    │
├─────────────────────────────────────────────────────────────────┤
│  Layer 0: 制品/脚本测试 (test_artifact_workflow_and_binaries.py) │
│           - 构建脚本、版本管理、运行时包解析                      │
└─────────────────────────────────────────────────────────────────┘
```

### 1.3 与周边组件关系

```
                    ┌─────────────────────┐
                    │   codex-rs (Rust)   │
                    │  app-server-protocol│
                    │   (JSON Schema)     │
                    └──────────┬──────────┘
                               │
                               ▼ schema bundle
┌──────────────────┐    ┌─────────────────────┐    ┌──────────────────┐
│  update_sdk_     │◄───┤ codex_app_server_   │───►│  sdk/python/tests │
│  artifacts.py    │    │ protocol.v2.schemas │    │  (本研究目录)      │
│  (代码生成脚本)   │    │      .json          │    │                  │
└────────┬─────────┘    └─────────────────────┘    └────────┬─────────┘
         │                                                  │
         ▼ generates                                        ▼ validates
┌──────────────────┐                              ┌──────────────────┐
│  generated/      │                              │  test_contract_  │
│  v2_all.py       │                              │  generation.py   │
│  (Pydantic模型)   │                              │                  │
└────────┬─────────┘                              └──────────────────┘
         │
         ▼ imports
┌──────────────────┐
│  client.py       │
│  async_client.py │
│  api.py          │
│  (SDK 核心实现)   │
└──────────────────┘
```

---

## 2. 功能点目的

### 2.1 测试文件功能矩阵

| 测试文件 | 核心目的 | 关键验证点 |
|---------|---------|-----------|
| `conftest.py` | 测试环境配置 | 确保测试使用正确的源码路径，避免导入已安装的包 |
| `test_artifact_workflow_and_binaries.py` | 构建流程验证 | 脚本结构、Schema 规范化、代码生成参数、运行时包解析 |
| `test_async_client_behavior.py` | 异步客户端行为 | 调用序列化、流式传输阻塞机制 |
| `test_client_rpc_methods.py` | RPC 方法验证 | 方法路由、参数序列化、通知类型映射 |
| `test_contract_generation.py` | 生成代码一致性 | 防止生成制品与 Schema 漂移 |
| `test_public_api_runtime_behavior.py` | 公共 API 运行时 | Turn/Thread 生命周期、流控、并发限制、结果收集 |
| `test_public_api_signatures.py` | API 签名契约 | 参数命名规范(snake_case)、类型注解完整性 |
| `test_real_app_server_integration.py` | 端到端集成 | 真实 Runtime 交互、示例验证、Notebook 验证 |

### 2.2 关键测试场景详解

#### 2.2.1 代码生成契约验证 (`test_contract_generation.py`)

**目的**: 确保从 JSON Schema 生成的 Python 代码与原始协议定义保持一致，防止手动修改生成文件或 Schema 变更后未重新生成。

**实现机制**:
```python
def test_generated_files_are_up_to_date():
    # 1. 快照当前生成文件
    before = _snapshot_targets(ROOT)
    
    # 2. 重新执行代码生成
    subprocess.run([..., "scripts/update_sdk_artifacts.py", "generate-types"], ...)
    
    # 3. 对比前后差异
    after = _snapshot_targets(ROOT)
    assert before == after, "Generated files drifted after regeneration"
```

#### 2.2.2 异步客户端序列化验证 (`test_async_client_behavior.py`)

**目的**: 验证 `AsyncAppServerClient` 通过 `_transport_lock` 确保对底层同步客户端的调用是序列化的，避免并发导致的 stdio 传输混乱。

**关键测试**:
- `test_async_client_serializes_transport_calls`: 验证并发调用 `model_list()` 时最大活跃调用数为 1
- `test_async_stream_text_is_incremental_and_blocks_parallel_calls`: 验证流式传输期间其他调用被阻塞

#### 2.2.3 Turn 流控验证 (`test_public_api_runtime_behavior.py`)

**目的**: 验证同一时间只能有一个活跃的 Turn 消费者，防止事件混淆。

**实现机制**:
```python
# client.py 中的流控实现
class AppServerClient:
    def __init__(self, ...):
        self._turn_consumer_lock = threading.Lock()
        self._active_turn_consumer: str | None = None
    
    def acquire_turn_consumer(self, turn_id: str) -> None:
        with self._turn_consumer_lock:
            if self._active_turn_consumer is not None:
                raise RuntimeError("Concurrent turn consumers are not yet supported...")
            self._active_turn_consumer = turn_id
```

**测试验证**:
```python
def test_turn_stream_rejects_second_active_consumer():
    first_stream = TurnHandle(client, "thread-1", "turn-1").stream()
    next(first_stream)  # 激活第一个消费者
    
    second_stream = TurnHandle(client, "thread-1", "turn-2").stream()
    with pytest.raises(RuntimeError, match="Concurrent turn consumers are not yet supported"):
        next(second_stream)  # 第二个消费者应被拒绝
```

#### 2.2.4 运行时包解析验证 (`test_artifact_workflow_and_binaries.py`)

**目的**: 验证 SDK 如何解析和定位 Codex runtime 二进制文件。

**解析优先级**:
1. 显式配置: `AppServerConfig.codex_bin`
2. 已安装的 runtime 包: `codex_cli_bin.bundled_codex_path()`
3. 错误: 未找到可用 runtime

---

## 3. 具体技术实现

### 3.1 关键数据结构与协议

#### 3.1.1 JSON-RPC v2 协议封装

```python
# client.py: 请求/响应结构
class AppServerClient:
    def _request_raw(self, method: str, params: JsonObject | None = None) -> JsonValue:
        request_id = str(uuid.uuid4())
        # 发送: {"id": "uuid", "method": "thread/start", "params": {...}}
        self._write_message({"id": request_id, "method": method, "params": params or {}})
        
        while True:
            msg = self._read_message()
            # 处理服务器请求 (如 approval 请求)
            if "method" in msg and "id" in msg:
                response = self._handle_server_request(msg)
                self._write_message({"id": msg["id"], "result": response})
                continue
            # 缓存通知
            if "method" in msg and "id" not in msg:
                self._pending_notifications.append(...)
                continue
            # 匹配响应 ID
            if msg.get("id") == request_id:
                return msg.get("result")
```

#### 3.1.2 通知类型系统

```python
# models.py: 通知类型定义
NotificationPayload: TypeAlias = (
    AccountLoginCompletedNotification
    | AgentMessageDeltaNotification
    | TurnCompletedNotification
    | ...
    | UnknownNotification  # 兜底类型
)

@dataclass(slots=True)
class Notification:
    method: str
    payload: NotificationPayload
```

```python
# notification_registry.py: 方法到模型的映射 (自动生成)
NOTIFICATION_MODELS: dict[str, type[BaseModel]] = {
    "item/agentMessage/delta": AgentMessageDeltaNotification,
    "turn/completed": TurnCompletedNotification,
    "thread/tokenUsage/updated": ThreadTokenUsageUpdatedNotification,
    ...
}
```

#### 3.1.3 参数序列化流程

```python
# client.py: _params_dict 实现 snake_case -> camelCase 转换
def _params_dict(params) -> JsonObject:
    if params is None:
        return {}
    if hasattr(params, "model_dump"):
        # Pydantic v2: by_alias=True 将 snake_case 转为 camelCase
        dumped = params.model_dump(by_alias=True, exclude_none=True, mode="json")
        return dumped
    ...

# 示例: ThreadListParams
class ThreadListParams(BaseModel):
    search_term: str | None = None  # Python 字段名
    # 序列化后: {"searchTerm": "value"}  # wire 格式
```

### 3.2 关键流程

#### 3.2.1 同步客户端生命周期

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Codex()   │────►│   start()   │────►│ initialize()│
│  __enter__  │     │ 启动子进程   │     │  握手协议    │
└─────────────┘     └─────────────┘     └─────────────┘
                                               │
                                               ▼
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   close()   │◄────│  __exit__   │◄────│   API 调用   │
│ 终止子进程   │     │   上下文退出 │     │ thread/turn │
└─────────────┘     └─────────────┘     └─────────────┘
```

#### 3.2.2 异步客户端初始化 (懒加载)

```python
# api.py: AsyncCodex 懒加载实现
class AsyncCodex:
    def __init__(self, config: AppServerConfig | None = None):
        self._client = AsyncAppServerClient(config=config)
        self._init: InitializeResponse | None = None
        self._initialized = False
        self._init_lock = asyncio.Lock()
    
    async def _ensure_initialized(self) -> None:
        if self._initialized:
            return
        async with self._init_lock:  # 防止并发初始化
            if self._initialized:
                return
            await self._client.start()
            payload = await self._client.initialize()
            self._init = Codex._validate_initialize(payload)
            self._initialized = True
```

#### 3.2.3 Turn 结果收集流程

```python
# _run.py: 同步/异步结果收集

def _collect_run_result(stream: Iterator[Notification], *, turn_id: str) -> RunResult:
    items: list[ThreadItem] = []
    usage: ThreadTokenUsage | None = None
    
    for event in stream:
        payload = event.payload
        if isinstance(payload, ItemCompletedNotification) and payload.turn_id == turn_id:
            items.append(payload.item)
        elif isinstance(payload, ThreadTokenUsageUpdatedNotification):
            usage = payload.token_usage
        elif isinstance(payload, TurnCompletedNotification):
            completed = payload
            break
    
    # 提取最终响应: 优先找 phase=final_answer 的消息
    final_response = _final_assistant_response_from_items(items)
    return RunResult(final_response=final_response, items=items, usage=usage)
```

### 3.3 代码生成管道

```
┌─────────────────────────────────────────────────────────────────────┐
│                      代码生成管道 (update_sdk_artifacts.py)           │
├─────────────────────────────────────────────────────────────────────┤
│  Input: codex_app_server_protocol.v2.schemas.json (Rust 导出)        │
├─────────────────────────────────────────────────────────────────────┤
│  Step 1: Schema 规范化 (_normalized_schema_bundle_text)              │
│          - 扁平化字符串枚举 oneOf (AuthMode, MessagePhase 等)        │
│          - 为变体添加稳定 title (避免生成 Helper1, Helper2...)        │
│          - 设置 discriminator titles                                 │
├─────────────────────────────────────────────────────────────────────┤
│  Step 2: 生成 v2_all.py (datamodel-code-generator)                   │
│          - --use-title-as-name: 使用 title 作为类名                   │
│          - --snake-case-field: 字段名转为 snake_case                  │
│          - --allow-population-by-field-name: 支持按字段名填充         │
├─────────────────────────────────────────────────────────────────────┤
│  Step 3: 生成 notification_registry.py                               │
│          - 解析 ServerNotification.json 的 oneOf                     │
│          - 建立 method -> NotificationModel 的映射                   │
├─────────────────────────────────────────────────────────────────────┤
│  Step 4: 生成 api.py 的扁平方法 (_render_codex_block 等)              │
│          - 从 Params 模型提取字段生成方法签名                         │
│          - 保持 snake_case 命名，内部转换为 camelCase                 │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 4. 关键代码路径与文件引用

### 4.1 测试文件 ↔ 被测代码映射

| 测试文件 | 被测代码文件 | 关键被测函数/类 |
|---------|-------------|----------------|
| `test_artifact_workflow_and_binaries.py` | `scripts/update_sdk_artifacts.py` | `generate_types()`, `stage_python_sdk_package()`, `stage_python_runtime_package()` |
| | `_runtime_setup.py` | `ensure_runtime_package_installed()`, `_release_metadata()` |
| | `client.py` | `resolve_codex_bin()`, `CodexBinResolverOps` |
| `test_async_client_behavior.py` | `async_client.py` | `AsyncAppServerClient._call_sync()`, `stream_text()` |
| `test_client_rpc_methods.py` | `client.py` | `_params_dict()`, `_coerce_notification()` |
| | `generated/v2_all.py` | `ThreadListParams`, `ThreadTokenUsageUpdatedNotification` |
| `test_contract_generation.py` | `scripts/update_sdk_artifacts.py` | `generate_types()` |
| `test_public_api_runtime_behavior.py` | `api.py` | `Codex`, `Thread`, `TurnHandle`, `AsyncCodex`, `AsyncThread`, `AsyncTurnHandle` |
| | `client.py` | `acquire_turn_consumer()`, `release_turn_consumer()` |
| `test_public_api_signatures.py` | `api.py` | `Codex.thread_start`, `Thread.turn`, `AsyncCodex.thread_start` 等 |
| `test_real_app_server_integration.py` | `api.py`, `client.py` | 完整端到端流程 |

### 4.2 核心代码路径

```
sdk/python/
├── tests/
│   ├── conftest.py                          # 测试配置: 源码路径注入
│   ├── test_artifact_workflow_and_binaries.py  # 制品流程测试
│   ├── test_async_client_behavior.py        # 异步客户端行为
│   ├── test_client_rpc_methods.py           # RPC 方法测试
│   ├── test_contract_generation.py          # 代码生成契约
│   ├── test_public_api_runtime_behavior.py  # 公共 API 运行时
│   ├── test_public_api_signatures.py        # API 签名契约
│   └── test_real_app_server_integration.py  # 真实集成测试
│
├── src/codex_app_server/
│   ├── __init__.py                          # 公共导出
│   ├── client.py                            # 同步客户端 (AppServerClient)
│   ├── async_client.py                      # 异步包装 (AsyncAppServerClient)
│   ├── api.py                               # 高级 API (Codex, Thread, TurnHandle)
│   ├── models.py                            # 核心模型 (Notification, InitializeResponse)
│   ├── errors.py                            # 异常体系
│   ├── retry.py                             # 重试逻辑
│   ├── _inputs.py                           # 输入类型 (TextInput, ImageInput...)
│   ├── _run.py                              # 结果收集逻辑
│   └── generated/
│       ├── v2_all.py                        # 生成的 Pydantic 模型 (大文件)
│       └── notification_registry.py         # 通知方法注册表
│
├── scripts/
│   └── update_sdk_artifacts.py              # 代码生成脚本
│
├── _runtime_setup.py                        # Runtime 包安装管理
└── examples/                                # 示例代码 (被集成测试引用)
```

### 4.3 关键代码片段索引

#### 4.3.1 通知类型映射 (`client.py:455-466`)
```python
def _coerce_notification(self, method: str, params: object) -> Notification:
    params_dict = params if isinstance(params, dict) else {}
    model = NOTIFICATION_MODELS.get(method)
    if model is None:
        return Notification(method=method, payload=UnknownNotification(params=params_dict))
    try:
        payload = model.model_validate(params_dict)
    except Exception:
        return Notification(method=method, payload=UnknownNotification(params=params_dict))
    return Notification(method=method, payload=payload)
```

#### 4.3.2 流控锁实现 (`client.py:288-301`)
```python
def acquire_turn_consumer(self, turn_id: str) -> None:
    with self._turn_consumer_lock:
        if self._active_turn_consumer is not None:
            raise RuntimeError(
                "Concurrent turn consumers are not yet supported in the experimental SDK. "
                f"Client is already streaming turn {self._active_turn_consumer!r}; "
                f"cannot start turn {turn_id!r} until the active consumer finishes."
            )
        self._active_turn_consumer = turn_id

def release_turn_consumer(self, turn_id: str) -> None:
    with self._turn_consumer_lock:
        if self._active_turn_consumer == turn_id:
            self._active_turn_consumer = None
```

#### 4.3.3 Schema 规范化 (`scripts/update_sdk_artifacts.py:163-194`)
```python
def _flatten_string_enum_one_of(definition: dict[str, Any]) -> bool:
    """Flatten oneOf[string const, ...] into a single string enum."""
    branches = definition.get("oneOf")
    if not isinstance(branches, list) or not branches:
        return False
    enum_values: list[str] = []
    for branch in branches:
        if not isinstance(branch, dict) or branch.get("type") != "string":
            return False
        enum = branch.get("enum")
        if not isinstance(enum, list) or len(enum) != 1:
            return False
        enum_values.append(enum[0])
    definition.clear()
    definition["type"] = "string"
    definition["enum"] = enum_values
    return True
```

---

## 5. 依赖与外部交互

### 5.1 外部依赖

| 依赖 | 用途 | 版本要求 |
|-----|------|---------|
| `pydantic` | 数据验证、序列化、类型生成 | >=2.12 |
| `datamodel-code-generator` | 从 JSON Schema 生成 Pydantic 模型 | ==0.31.2 |
| `pytest` | 测试框架 | >=8.0 |
| `ruff` | 代码格式化 | >=0.11 |
| `codex-cli-bin` | Runtime 二进制包 (可选) | 特定版本 |

### 5.2 外部系统交互

```
┌─────────────────────────────────────────────────────────────────────┐
│                        外部系统交互图                                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌──────────────┐         ┌──────────────┐         ┌─────────────┐ │
│  │   GitHub     │◄───────►│ _runtime_    │◄───────►│  tests/     │ │
│  │   Releases   │  HTTP   │ setup.py     │  pip    │  conftest   │ │
│  │  (codex-cli) │         │ (下载/安装)   │         │             │ │
│  └──────────────┘         └──────────────┘         └──────┬──────┘ │
│                                                           │        │
│  ┌────────────────────────────────────────────────────────┘        │
│  │                                                                  │
│  ▼                                                                  │
│  ┌──────────────┐         ┌──────────────┐         ┌─────────────┐ │
│  │ codex-rs/    │         │  scripts/    │         │  generated/ │ │
│  │ app-server-  │◄───────►│ update_sdk_  │◄───────►│  v2_all.py  │ │
│  │ protocol/    │  Schema │ artifacts.py │  Codegen│             │ │
│  │ (JSON Schema)│         │              │         │             │ │
│  └──────────────┘         └──────────────┘         └─────────────┘ │
│                                                                     │
│  ┌──────────────┐         ┌──────────────┐                          │
│  │   Codex      │         │   client.py  │                          │
│  │   Runtime    │◄──stdio►│ (AppServer   │                          │
│  │  (子进程)     │ JSON-RPC│  Client)     │                          │
│  └──────────────┘         └──────────────┘                          │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### 5.3 环境变量

| 变量名 | 用途 | 相关测试 |
|-------|------|---------|
| `RUN_REAL_CODEX_TESTS` | 启用真实集成测试 | `test_real_app_server_integration.py` |
| `GH_TOKEN` / `GITHUB_TOKEN` | GitHub API 认证 (下载 runtime) | `_runtime_setup.py` |
| `CODEX_PYTHON_SDK_DIR` | SDK 路径 (集成测试使用) | `test_real_app_server_integration.py` |

---

## 6. 风险、边界与改进建议

### 6.1 当前风险点

#### 6.1.1 并发限制风险

**问题**: `acquire_turn_consumer` 使用客户端级别的全局锁，禁止同一客户端上并发 Turn 流。

**影响**: 用户无法同时监听多个 Thread 的事件流。

**代码位置**: `client.py:288-296`

```python
# 当前限制
raise RuntimeError(
    "Concurrent turn consumers are not yet supported in the experimental SDK. "
    ...
)
```

**建议**: 实现 per-turn 事件多路复用，通过 `turn_id` 路由事件到对应消费者。

#### 6.1.2 生成代码漂移风险

**问题**: `test_contract_generation.py` 通过子进程调用生成脚本，可能因环境差异导致误判。

**代码位置**: `test_contract_generation.py:36-52`

**建议**: 
- 添加版本号到生成文件头部，运行时对比 Schema 版本
- CI 中增加独立的 "generated files up-to-date" 检查任务

#### 6.1.3 Runtime 版本锁定风险

**问题**: `PINNED_RUNTIME_VERSION` 硬编码在 `_runtime_setup.py` 中，与 SDK 版本可能不匹配。

**代码位置**: `_runtime_setup.py:19`

```python
PINNED_RUNTIME_VERSION = "0.116.0-alpha.1"  # 需手动更新
```

**建议**: 
- 从 `pyproject.toml` 或独立版本文件读取
- 添加兼容性矩阵检查 (SDK 版本 vs Runtime 版本)

### 6.2 边界情况

#### 6.2.1 通知类型未知/无效

**处理**: 回退到 `UnknownNotification`，保留原始参数。

```python
# client.py:455-466
model = NOTIFICATION_MODELS.get(method)
if model is None:
    return Notification(method=method, payload=UnknownNotification(params=params_dict))
try:
    payload = model.model_validate(params_dict)
except Exception:
    return Notification(method=method, payload=UnknownNotification(params=params_dict))
```

**测试覆盖**: `test_client_rpc_methods.py:test_unknown_notifications_fall_back_to_unknown_payloads`

#### 6.2.2 服务器过载重试

**处理**: `retry_on_overload` 实现指数退避 + 抖动。

```python
# retry.py:12-41
delay = initial_delay_s
for attempt in range(max_attempts):
    try:
        return op()
    except Exception as exc:
        if not is_retryable_error(exc):
            raise
        jitter = delay * jitter_ratio
        sleep_for = min(max_delay_s, delay) + random.uniform(-jitter, jitter)
        time.sleep(sleep_for)
        delay = min(max_delay_s, delay * 2)
```

### 6.3 改进建议

#### 6.3.1 测试覆盖增强

| 建议 | 优先级 | 说明 |
|-----|-------|------|
| 添加错误恢复测试 | 高 | 验证子进程崩溃后的清理和错误信息 |
| 添加长时间运行测试 | 中 | 验证大流量下的内存稳定性 |
| 添加网络中断模拟 | 中 | 验证 `TransportClosedError` 处理 |
| 添加并发初始化测试 | 高 | 验证 `AsyncCodex` 并发初始化只执行一次 |

#### 6.3.2 代码结构改进

| 建议 | 优先级 | 说明 |
|-----|-------|------|
| 提取协议常量 | 中 | 将方法名 (如 `"thread/start"`) 提取为常量 |
| 统一错误处理 | 中 | 当前 `RuntimeError` 使用较多，建议自定义异常 |
| 添加类型存根 | 低 | 为动态生成的方法添加 `.pyi` 存根 |

#### 6.3.3 文档改进

| 建议 | 优先级 | 说明 |
|-----|-------|------|
| 添加架构图 | 高 | 展示 SDK 与 Runtime 的交互流程 |
| 完善错误码文档 | 中 | 说明各 JSON-RPC 错误码的含义和处理建议 |
| 添加迁移指南 | 低 | v1 -> v2 的 API 变更说明 |

---

## 7. 附录

### 7.1 测试执行命令

```bash
# 运行所有测试 (不含集成测试)
cd sdk/python && python -m pytest tests/ -v

# 运行特定测试文件
cd sdk/python && python -m pytest tests/test_client_rpc_methods.py -v

# 运行集成测试 (需要 RUN_REAL_CODEX_TESTS=1)
cd sdk/python && RUN_REAL_CODEX_TESTS=1 python -m pytest tests/test_real_app_server_integration.py -v

# 重新生成代码 (会触发 contract 测试)
cd sdk/python && python scripts/update_sdk_artifacts.py generate-types
```

### 7.2 关键文件大小参考

| 文件 | 行数 | 说明 |
|-----|------|------|
| `generated/v2_all.py` | ~8000+ | 生成的 Pydantic 模型 |
| `client.py` | ~540 | 同步客户端核心 |
| `api.py` | ~735 | 高级 API 实现 |
| `update_sdk_artifacts.py` | ~998 | 代码生成脚本 |

### 7.3 版本历史参考

- SDK 版本: `0.2.0` (定义于 `pyproject.toml` 和 `client.py:132`)
- 绑定 Runtime 版本: `0.116.0-alpha.1` (定义于 `_runtime_setup.py:19`)
