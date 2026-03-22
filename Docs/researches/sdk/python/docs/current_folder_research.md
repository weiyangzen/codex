# SDK Python Docs 深度研究文档

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

`sdk/python/docs` 目录是 **Codex App Server Python SDK** 的官方文档集合，面向使用该 SDK 的 Python 开发者。该 SDK 是 `codex app-server` JSON-RPC v2 协议的 Python 客户端实现，提供同步和异步两种 API 风格。

**核心目标：**
- 为开发者提供从安装到高级使用的完整指南
- 解释 Thread/Turn 概念模型和生命周期管理
- 说明同步 (`Codex`) 与异步 (`AsyncCodex`) 客户端的使用模式
- 提供 API 签名参考和常见陷阱规避建议

### 1.2 目标用户

| 用户类型 | 使用场景 |
|---------|---------|
| 新手开发者 | 通过 `getting-started.md` 快速上手 |
| 应用开发者 | 参考 `api-reference.md` 进行集成开发 |
| 问题排查者 | 查阅 `faq.md` 解决常见疑问 |

### 1.3 与周边系统的关系

```
┌─────────────────────────────────────────────────────────────────┐
│                        开发者 (User)                             │
└──────────────────────┬──────────────────────────────────────────┘
                       │ 阅读/参考
                       ▼
┌─────────────────────────────────────────────────────────────────┐
│  sdk/python/docs                                                │
│  ├── getting-started.md  ───────┐                               │
│  ├── api-reference.md    ───────┼──►  指导开发者使用 SDK         │
│  └── faq.md              ───────┘                               │
└──────────────────────┬──────────────────────────────────────────┘
                       │ 文档描述
                       ▼
┌─────────────────────────────────────────────────────────────────┐
│  sdk/python/src/codex_app_server/                               │
│  ├── api.py          (Codex, AsyncCodex 公共 API)                │
│  ├── client.py       (AppServerClient 同步客户端)                │
│  ├── async_client.py (AsyncAppServerClient 异步包装)             │
│  └── generated/      (从 JSON Schema 生成的 Pydantic 模型)        │
└──────────────────────┬──────────────────────────────────────────┘
                       │ JSON-RPC over stdio
                       ▼
┌─────────────────────────────────────────────────────────────────┐
│  codex-rs/app-server-protocol/                                  │
│  └── schema/json/        (v2 协议 JSON Schema 定义)              │
└──────────────────────┬──────────────────────────────────────────┘
                       │ 协议实现
                       ▼
┌─────────────────────────────────────────────────────────────────┐
│  codex app-server (Rust 二进制)                                  │
│  └── 实际执行 AI 对话、工具调用、沙箱管理等核心逻辑                │
└─────────────────────────────────────────────────────────────────┘
```

---

## 功能点目的

### 2.1 文档文件功能矩阵

| 文件 | 核心目的 | 覆盖阶段 |
|-----|---------|---------|
| `getting-started.md` | 安装指南 + 基础使用教程 | 入门阶段 |
| `api-reference.md` | 完整 API 签名参考 | 开发阶段 |
| `faq.md` | 常见决策、陷阱、故障排除 | 全生命周期 |

### 2.2 各文档核心内容详解

#### 2.2.1 getting-started.md

**职责：** 最小可行路径 (Golden Path) 教程

**关键内容：**
1. **安装要求**：Python >=3.10、`codex-cli-bin` 运行时、本地 Codex 认证
2. **同步快速开始**：`with Codex() as codex:` 上下文管理模式
3. **多轮对话**：同一 Thread 上多次 `run()` 调用
4. **异步支持**：`async with AsyncCodex()` 模式
5. **恢复现有线程**：`thread_resume(thread_id)`
6. **生成模型引用**：`codex_app_server.generated.v2_all`

**关键概念解释：**
- `Thread`：对话状态容器
- `Turn`：Thread 内的一次模型执行
- `run()` vs `turn()`：前者是便利方法，后者返回 `TurnHandle` 用于流式控制

#### 2.2.2 api-reference.md

**职责：** 公共 API 签名与行为规格说明

**覆盖的 API 表面：**

| 类/方法 | 类型 | 说明 |
|--------|------|------|
| `Codex` | 同步客户端 | 构造函数启动并初始化 app-server |
| `AsyncCodex` | 异步客户端 | 延迟初始化，上下文管理器确保配对关闭 |
| `Thread` / `AsyncThread` | 对话管理 | `run()` 便利方法，`turn()` 流式控制 |
| `TurnHandle` / `AsyncTurnHandle` | 回合控制 | `steer()`, `interrupt()`, `stream()`, `run()` |
| 输入类型 | 数据类 | `TextInput`, `ImageInput`, `LocalImageInput`, `SkillInput`, `MentionInput` |
| 重试工具 | 函数 | `retry_on_overload()` 处理瞬态过载 |

**重要约束说明：**
- 实验性构建中每个客户端实例仅支持一个活跃的 Turn 消费者
- `stream()` 和 `run()` 在同一客户端上是互斥的
- 同时启动第二个消费者会抛出 `RuntimeError`

#### 2.2.3 faq.md

**职责：** 决策指导和故障排除

**核心 FAQ 主题：**

| 主题 | 关键说明 |
|-----|---------|
| Thread vs Turn | Thread 是对话状态，Turn 是单次模型执行 |
| run() vs stream() | run() 消费到完成，stream() 逐事件响应 |
| Sync vs Async | AsyncCodex 延迟初始化，上下文管理器是标准路径 |
| 命名规范迁移 | camelCase → snake_case (approvalPolicy → approval_policy) |
| 构造函数失败原因 | 运行时包缺失、二进制路径无效、认证缺失、不兼容版本 |
| Turn "挂起" 原因 | 必须等到 `turn/completed` 通知才算完成 |
| 安全重试 | 仅对 `ServerBusyError` 使用 `retry_on_overload()` |

---

## 具体技术实现

### 3.1 文档与代码的映射关系

#### 3.1.1 同步客户端初始化流程 (getting-started.md 示例)

```python
# 文档中的代码
with Codex() as codex:
    thread = codex.thread_start(model="gpt-5.4")
    result = thread.run("Say hello.")
```

**实际执行流程：**

```
Codex.__init__()
  ├── AppServerClient.__init__()      # sdk/python/src/codex_app_server/client.py:136
  ├── AppServerClient.start()         # 启动 subprocess (codex app-server --listen stdio://)
  └── AppServerClient.initialize()    # JSON-RPC initialize 握手

thread_start()
  └── client.thread_start()           # RPC: thread/start

thread.run()
  ├── thread.turn()                   # 创建 TurnHandle
  │   └── client.turn_start()         # RPC: turn/start
  └── turn.stream()                   # 消费通知直到 turn/completed
```

#### 3.1.2 异步客户端延迟初始化 (api-reference.md 说明)

```python
async with AsyncCodex() as codex:
    ...
```

**实现细节：**

```python
# sdk/python/src/codex_app_server/api.py:278-306
class AsyncCodex:
    def __init__(self, config=None):
        self._client = AsyncAppServerClient(config=config)
        self._init: InitializeResponse | None = None
        self._initialized = False
        self._init_lock = asyncio.Lock()

    async def _ensure_initialized(self):
        if self._initialized:
            return
        async with self._init_lock:          # 并发安全
            if self._initialized:
                return
            await self._client.start()
            payload = await self._client.initialize()
            self._init = Codex._validate_initialize(payload)
            self._initialized = True
```

### 3.2 关键数据结构

#### 3.2.1 JSON-RPC 消息格式

```python
# sdk/python/src/codex_app_server/client.py:239-270
def _request_raw(self, method, params=None):
    request_id = str(uuid.uuid4())
    self._write_message({
        "id": request_id,
        "method": method,
        "params": params or {}
    })
    
    while True:
        msg = self._read_message()
        # 处理服务器请求 (如 approval 请求)
        if "method" in msg and "id" in msg:
            response = self._handle_server_request(msg)
            self._write_message({"id": msg["id"], "result": response})
            continue
        # 处理通知
        if "method" in msg and "id" not in msg:
            self._pending_notifications.append(...)
            continue
        # 匹配响应 ID
        if msg.get("id") != request_id:
            continue
        # 返回结果或抛出错误
        if "error" in msg:
            raise map_jsonrpc_error(...)
        return msg.get("result")
```

#### 3.2.2 通知类型系统

```python
# sdk/python/src/codex_app_server/models.py:45-88
@dataclass(slots=True)
class Notification:
    method: str
    payload: NotificationPayload

NotificationPayload = (
    AccountLoginCompletedNotification
    | AgentMessageDeltaNotification
    | TurnCompletedNotification
    | ...
    | UnknownNotification  # 回退类型
)
```

通知注册表 (`notification_registry.py`) 自动从 JSON Schema 生成，建立 method 字符串到 Pydantic 模型的映射。

#### 3.2.3 RunResult 收集逻辑

```python
# sdk/python/src/codex_app_server/_run.py:59-83
def _collect_run_result(stream, *, turn_id):
    completed = None
    items = []
    usage = None

    for event in stream:
        payload = event.payload
        if isinstance(payload, ItemCompletedNotification) and payload.turn_id == turn_id:
            items.append(payload.item)
        elif isinstance(payload, ThreadTokenUsageUpdatedNotification) and payload.turn_id == turn_id:
            usage = payload.token_usage
        elif isinstance(payload, TurnCompletedNotification) and payload.turn.id == turn_id:
            completed = payload

    if completed is None:
        raise RuntimeError("turn completed event not received")

    _raise_for_failed_turn(completed.turn)
    return RunResult(
        final_response=_final_assistant_response_from_items(items),
        items=items,
        usage=usage,
    )
```

### 3.3 代码生成流程

文档中引用的 API 签名通过代码生成与 Rust 协议定义保持同步：

```
codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json
                    │
                    ▼
    scripts/update_sdk_artifacts.py generate-types
                    │
                    ├──► src/codex_app_server/generated/v2_all.py
                    │     (Pydantic 模型，datamodel-codegen 生成)
                    │
                    ├──► src/codex_app_server/generated/notification_registry.py
                    │     (通知类型映射)
                    │
                    └──► src/codex_app_server/api.py (生成块替换)
                          (Codex/AsyncCodex/Thread/AsyncThread 方法签名)
```

**关键生成参数：**
```python
# scripts/update_sdk_artifacts.py:422-453
run_python_module(
    "datamodel_code_generator",
    [
        "--input", str(normalized_bundle),
        "--input-file-type", "jsonschema",
        "--output", str(out_path),
        "--output-model-type", "pydantic_v2.BaseModel",
        "--target-python-version", "3.11",
        "--snake-case-field",           # Python 字段使用 snake_case
        "--allow-population-by-field-name",  # 但允许通过原名赋值
        "--use-title-as-name",
    ],
)
```

---

## 关键代码路径与文件引用

### 4.1 文档文件

| 文件路径 | 行数 | 核心内容 |
|---------|------|---------|
| `sdk/python/docs/getting-started.md` | 108 | 安装、快速开始、多轮对话、异步示例 |
| `sdk/python/docs/api-reference.md` | 207 | 完整 API 签名、参数说明、行为约束 |
| `sdk/python/docs/faq.md` | 98 | 概念解释、命名迁移、故障排除、常见陷阱 |

### 4.2 SDK 实现文件

| 文件路径 | 职责 |
|---------|------|
| `sdk/python/src/codex_app_server/__init__.py` | 公共 API 导出，版本定义 (0.2.0) |
| `sdk/python/src/codex_app_server/api.py` | `Codex`, `AsyncCodex`, `Thread`, `AsyncThread`, `TurnHandle`, `AsyncTurnHandle` 实现 |
| `sdk/python/src/codex_app_server/client.py` | `AppServerClient` 同步 JSON-RPC 客户端，stdio 传输 |
| `sdk/python/src/codex_app_server/async_client.py` | `AsyncAppServerClient` 异步包装，线程卸载 |
| `sdk/python/src/codex_app_server/models.py` | `Notification`, `InitializeResponse`, JSON 类型别名 |
| `sdk/python/src/codex_app_server/_inputs.py` | 输入类型定义 (`TextInput`, `ImageInput` 等) |
| `sdk/python/src/codex_app_server/_run.py` | `RunResult` 收集逻辑 |
| `sdk/python/src/codex_app_server/errors.py` | 异常层次结构，错误映射，重试判断 |
| `sdk/python/src/codex_app_server/retry.py` | `retry_on_overload()` 实现 |
| `sdk/python/src/codex_app_server/generated/v2_all.py` | 从 JSON Schema 生成的 Pydantic 模型 (~2000+ 行) |
| `sdk/python/src/codex_app_server/generated/notification_registry.py` | 通知方法到模型的映射 |

### 4.3 代码生成与构建

| 文件路径 | 职责 |
|---------|------|
| `sdk/python/scripts/update_sdk_artifacts.py` | 类型生成、API 方法生成、打包脚本 |
| `sdk/python/pyproject.toml` | 项目配置，依赖: pydantic>=2.12 |
| `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json` | 协议 Schema 源文件 |

### 4.4 示例与测试

| 文件路径 | 职责 |
|---------|------|
| `sdk/python/examples/_bootstrap.py` | 示例运行环境初始化，运行时包安装检查 |
| `sdk/python/examples/01_quickstart_constructor/` | 基础构造函数示例 (sync/async) |
| `sdk/python/examples/03_turn_stream_events/` | 流式事件消费示例 |
| `sdk/python/examples/11_cli_mini_app/` | 迷你 CLI 应用示例 |
| `sdk/python/tests/test_public_api_signatures.py` | API 签名一致性测试 |
| `sdk/python/tests/test_public_api_runtime_behavior.py` | 运行时行为测试 |
| `sdk/python/tests/test_client_rpc_methods.py` | RPC 方法调用测试 |

---

## 依赖与外部交互

### 5.1 运行时依赖

| 依赖 | 版本 | 用途 |
|-----|------|------|
| Python | >=3.10 | 运行时 |
| pydantic | >=2.12 | 数据验证和序列化 |
| codex-cli-bin | 精确版本 | 捆绑的 Codex 二进制运行时 |

### 5.2 开发依赖

| 依赖 | 版本 | 用途 |
|-----|------|------|
| pytest | >=8.0 | 测试框架 |
| datamodel-code-generator | ==0.31.2 | 从 JSON Schema 生成 Pydantic 模型 |
| ruff | >=0.11 | 代码格式化 |

### 5.3 外部系统交互

#### 5.3.1 与 Codex App Server 的交互

```
┌─────────────────────┐         stdio          ┌─────────────────────┐
│   Python SDK        │  ◄──────────────────►  │  codex app-server   │
│   (AppServerClient) │   JSON-RPC 2.0 over    │   (Rust binary)     │
│                     │   stdin/stdout         │                     │
└─────────────────────┘                        └─────────────────────┘
         │                                              │
         │ 1. initialize (clientInfo, capabilities)     │
         │◄────────────────────────────────────────────►│
         │ 2. thread/start, thread/resume, etc.         │
         │◄────────────────────────────────────────────►│
         │ 3. turn/start                                │
         │◄────────────────────────────────────────────►│
         │ 4. Notifications (turn/completed, etc.)      │
         │◄─────────────────────────────────────────────│
         │ 5. Server Requests (approval requests)       │
         │◄────────────────────────────────────────────►│
```

#### 5.3.2 协议版本兼容性

- **目标协议**：Codex `app-server` JSON-RPC v2
- **实验性 API**：默认启用 (`experimental_api=True`)
- **版本建议**：SDK 和 CLI 保持同步更新

### 5.4 代码生成依赖链

```
Rust 协议定义 (codex-rs/app-server-protocol/src/protocol/v2.rs)
    │
    ▼ (schemars 生成)
JSON Schema (codex-rs/app-server-protocol/schema/json/v2/*.json)
    │
    ▼ (合并为 bundle)
codex_app_server_protocol.v2.schemas.json
    │
    ▼ (datamodel-codegen)
Python Pydantic 模型 (sdk/python/src/codex_app_server/generated/v2_all.py)
```

---

## 风险、边界与改进建议

### 6.1 已知限制与风险

#### 6.1.1 并发限制 (文档中明确说明)

```python
# sdk/python/src/codex_app_server/client.py:288-296
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

**风险：** 每个客户端实例同一时间只能有一个活跃的 Turn 消费者。尝试启动第二个会抛出 `RuntimeError`。

**缓解：** 使用多个 `Codex` 实例或顺序处理 Turns。

#### 6.1.2 构造函数立即初始化

```python
# sdk/python/src/codex_app_server/api.py:72-79
def __init__(self, config=None):
    self._client = AppServerClient(config=config)
    try:
        self._client.start()
        self._init = self._validate_initialize(self._client.initialize())
    except Exception:
        self._client.close()
        raise
```

`Codex()` 是**立即 (eager)** 初始化的，构造失败会抛出异常。这与 `AsyncCodex` 的延迟初始化形成对比。

#### 6.1.3 资源清理风险

```python
# 推荐：使用上下文管理器
with Codex() as codex:
    ...

# 风险：忘记关闭会导致子进程泄漏
codex = Codex()  # 子进程已启动
...
# 如果这里抛出异常或提前返回，子进程可能残留
```

#### 6.1.4 运行时包依赖

```python
# sdk/python/src/codex_app_server/client.py:80-90
def _installed_codex_path() -> Path:
    try:
        from codex_cli_bin import bundled_codex_path
    except ImportError as exc:
        raise FileNotFoundError(
            "Unable to locate the pinned Codex runtime. Install the published SDK build "
            f"with its {RUNTIME_PKG_NAME} dependency, or set AppServerConfig.codex_bin "
            "explicitly."
        ) from exc
```

**风险：** 如果 `codex-cli-bin` 包未安装且未显式配置 `codex_bin`，构造函数会失败。

### 6.2 边界情况

| 场景 | 行为 |
|-----|------|
| Turn 完成但无最终响应 | `RunResult.final_response` 为 `None` |
| 仅 commentary 消息完成 | `final_response` 为 `None` (非 commentary) |
| Turn 失败 | 抛出 `RuntimeError`，消息来自 `turn.error.message` |
| 未知通知类型 | 包装为 `UnknownNotification`，保留原始参数 |
| 无效通知载荷 | 回退到 `UnknownNotification`，不中断流程 |
| 服务器过载 | 抛出 `ServerBusyError`，可使用 `retry_on_overload()` 重试 |

### 6.3 改进建议

#### 6.3.1 文档改进

| 建议 | 优先级 | 说明 |
|-----|-------|------|
| 添加架构图 | 中 | 展示 Thread/Turn/Item 的层级关系 |
| 添加错误处理最佳实践 | 高 | 当前 FAQ 仅提及重试，可扩展完整错误处理指南 |
| 添加性能/并发模式 | 中 | 如何处理多个并发对话 (多实例 vs 连接池) |
| 添加类型提示示例 | 低 | 展示如何与静态类型检查器 (mypy/pyright) 配合使用 |

#### 6.3.2 代码改进

| 建议 | 优先级 | 说明 |
|-----|-------|------|
| 支持并发 Turn 消费者 | 高 | 移除实验性限制，支持每 Turn 独立事件多路复用 |
| 添加连接池 | 中 | 管理多个 app-server 实例以支持高并发 |
| 改进错误消息 | 中 | 当 `codex-cli-bin` 缺失时，提供更详细的安装指导 |
| 添加调试模式 | 低 | 记录所有 JSON-RPC 消息便于故障排除 |

#### 6.3.3 测试改进

| 建议 | 优先级 | 说明 |
|-----|-------|------|
| 添加集成测试 | 高 | 当前测试多为单元测试，需 mock |
| 添加性能基准 | 低 | 测量 Turn 启动、流式传输延迟 |
| 添加并发测试 | 中 | 验证并发限制行为和错误处理 |

### 6.4 维护注意事项

1. **Schema 变更同步**：当 `codex-rs/app-server-protocol` 的 v2 协议变更时，必须运行：
   ```bash
   cd sdk/python
   python scripts/update_sdk_artifacts.py generate-types
   ```

2. **版本锁定**：发布时 SDK 和运行时 (`codex-cli-bin`) 版本必须精确匹配。

3. **API 签名测试**：`test_public_api_signatures.py` 确保公共 API 使用 snake_case，修改 API 时需同步更新测试。

---

## 附录：关键代码片段索引

### A.1 文档中引用的代码模式

**同步基本用法：**
```python
# docs/getting-started.md:24-37
from codex_app_server import Codex

with Codex() as codex:
    thread = codex.thread_start(model="gpt-5.4", config={"model_reasoning_effort": "high"})
    result = thread.run("Say hello in one sentence.")
    print(result.final_response)
```

**流式事件处理：**
```python
# docs/api-reference.md:126-127 + examples/03_turn_stream_events/sync.py:28-44
for event in turn.stream():
    if event.method == "item/agentMessage/delta":
        print(event.payload.delta, end="")
```

**异步模式：**
```python
# docs/getting-started.md:68-81
async with AsyncCodex() as codex:
    thread = await codex.thread_start(model="gpt-5.4")
    result = await thread.run("Continue where we left off.")
```

### A.2 命名规范映射

| 文档/公共 API (snake_case) | Wire/JSON (camelCase) |
|---------------------------|----------------------|
| `approval_policy` | `approvalPolicy` |
| `base_instructions` | `baseInstructions` |
| `developer_instructions` | `developerInstructions` |
| `model_provider` | `modelProvider` |
| `output_schema` | `outputSchema` |
| `sandbox_policy` | `sandboxPolicy` |
| `service_tier` | `serviceTier` |

映射由 Pydantic 的 `Field(alias="...")` 和 `model_dump(by_alias=True)` 自动处理。

---

*文档生成时间：2026-03-22*
*研究范围：sdk/python/docs 及其依赖的 SDK 实现、协议定义、示例代码*
