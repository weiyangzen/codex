# sdk/python 目录深度研究文档

> 研究范围：`/home/sansha/Github/codex/sdk/python`
> 研究时间：2026-03-22
> 包名：`codex-app-server-sdk`
> 版本：0.2.0

---

## 1. 场景与职责

### 1.1 定位与目标

`sdk/python` 是 **Codex App Server 的 Python SDK**，提供对 `codex app-server` JSON-RPC v2 协议的封装。该 SDK 面向需要以编程方式与 Codex CLI 后端交互的 Python 开发者，支持同步和异步两种编程模型。

**核心职责：**
- 作为 Python 客户端与 Rust 实现的 `codex app-server` 之间的桥梁
- 提供类型安全的 API 封装（基于 Pydantic 的生成模型）
- 管理子进程生命周期（stdio 传输）
- 处理 JSON-RPC 协议的双向通信
- 支持同步 (`Codex`) 和异步 (`AsyncCodex`) 两种使用模式

### 1.2 使用场景

| 场景 | 说明 |
|------|------|
| 自动化脚本 | 批量处理文件、执行代码审查、生成文档 |
| 集成应用 | 将 Codex 能力嵌入到现有 Python 应用中 |
| 交互式工具 | 构建自定义 CLI 或聊天界面 |
| 多轮对话 | 维护对话上下文，实现复杂任务分解 |
| 流式处理 | 实时获取模型输出，用于进度展示 |

### 1.3 架构位置

```
┌─────────────────────────────────────────────────────────────┐
│                    Python Application                        │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              codex-app-server-sdk                    │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌───────────┐  │   │
│  │  │  Public API  │  │ Sync Client  │  │ Async CLI │  │   │
│  │  │  (api.py)    │  │(client.py)   │  │(async_*)  │  │   │
│  │  └──────────────┘  └──────────────┘  └───────────┘  │   │
│  └─────────────────────────────────────────────────────┘   │
│                         │ stdio JSON-RPC                    │
│                         ▼                                   │
│              ┌─────────────────────┐                        │
│              │   codex app-server  │  (Rust binary)         │
│              │   (codex-cli-bin)   │                        │
│              └─────────────────────┘                        │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. 功能点目的

### 2.1 核心功能模块

#### 2.1.1 连接管理 (`client.py`)

| 功能 | 目的 | 关键类/方法 |
|------|------|-------------|
| 进程管理 | 启动/停止 `codex app-server` 子进程 | `AppServerClient.start()`, `close()` |
| 二进制解析 | 定位 codex 可执行文件 | `_resolve_codex_bin()`, `CodexBinResolverOps` |
| 配置管理 | 支持自定义启动参数、环境变量 | `AppServerConfig` |
| 初始化握手 | JSON-RPC initialize 协议 | `initialize()` |

#### 2.1.2 RPC 通信 (`client.py`, `models.py`)

| 功能 | 目的 | 关键实现 |
|------|------|----------|
| 请求发送 | 向服务器发送 JSON-RPC 请求 | `_request_raw()`, `_write_message()` |
| 响应接收 | 解析服务器返回 | `_read_message()` |
| 通知处理 | 处理服务器推送的通知 | `next_notification()`, `_coerce_notification()` |
| 服务器请求处理 | 处理服务器的 approval 请求 | `_handle_server_request()` |

#### 2.1.3 Thread 生命周期管理

| 操作 | 方法 | 说明 |
|------|------|------|
| 创建线程 | `thread_start()` | 创建新对话线程 |
| 恢复线程 | `thread_resume()` | 继续已有对话 |
| 分叉线程 | `thread_fork()` | 基于现有线程创建分支 |
| 归档线程 | `thread_archive()` | 归档线程 |
| 取消归档 | `thread_unarchive()` | 恢复归档线程 |
| 列出线程 | `thread_list()` | 分页查询线程列表 |
| 读取线程 | `thread_read()` | 获取线程详情 |
| 设置名称 | `thread_set_name()` | 重命名线程 |
| 压缩上下文 | `thread_compact()` | 压缩线程上下文 |

#### 2.1.4 Turn 执行控制

| 操作 | 方法 | 说明 |
|------|------|------|
| 启动 Turn | `turn_start()` | 在线程中启动新一轮对话 |
| 流式获取 | `TurnHandle.stream()` | 迭代获取事件通知 |
| 等待完成 | `TurnHandle.run()` | 阻塞等待 turn 完成 |
| 干预控制 | `turn_steer()` | 向进行中的 turn 发送额外输入 |
| 中断执行 | `turn_interrupt()` | 中断当前 turn |

#### 2.1.5 输入处理 (`_inputs.py`)

| 输入类型 | 类 | 用途 |
|----------|-----|------|
| 文本 | `TextInput` | 纯文本输入 |
| 图片 URL | `ImageInput` | 远程图片 |
| 本地图片 | `LocalImageInput` | 本地文件路径图片 |
| Skill | `SkillInput` | 引用 skill |
| Mention | `MentionInput` | 引用上下文 |

#### 2.1.6 错误处理与重试 (`errors.py`, `retry.py`)

| 功能 | 实现 | 说明 |
|------|------|------|
| 错误分类 | `map_jsonrpc_error()` | 将 JSON-RPC 错误映射到具体异常类 |
| 重试机制 | `retry_on_overload()` | 对 ServerBusyError 进行指数退避重试 |
| 可重试判断 | `is_retryable_error()` | 判断错误是否可重试 |

---

## 3. 具体技术实现

### 3.1 JSON-RPC over stdio 协议

SDK 通过标准输入输出与 Rust 后端通信，采用 JSON-RPC 2.0 协议：

**请求格式：**
```json
{"id": "uuid", "method": "thread/start", "params": {"model": "gpt-5"}}
```

**响应格式：**
```json
{"id": "uuid", "result": {...}}
```

**通知格式（服务器→客户端）：**
```json
{"method": "turn/completed", "params": {...}}
```

**服务器请求（服务器→客户端，需响应）：**
```json
{"id": "req-id", "method": "item/commandExecution/requestApproval", "params": {...}}
```

### 3.2 关键数据结构

#### 3.2.1 核心类型定义 (`models.py`)

```python
# JSON 类型别名
JsonScalar: TypeAlias = str | int | float | bool | None
JsonValue: TypeAlias = JsonScalar | dict[str, "JsonValue"] | list["JsonValue"]
JsonObject: TypeAlias = dict[str, JsonValue]

# 通知包装器
@dataclass(slots=True)
class Notification:
    method: str
    payload: NotificationPayload  # Union of all notification types

# 初始化响应
class InitializeResponse(BaseModel):
    serverInfo: ServerInfo | None = None
    userAgent: str | None = None
    platformFamily: str | None = None
    platformOs: str | None = None
```

#### 3.2.2 生成模型 (`generated/v2_all.py`)

从 Rust schema 自动生成的 Pydantic 模型，约 2000+ 行，包含：
- 所有 Request/Response 类型
- 所有 Notification 类型
- 枚举类型（snake_case Python 字段，camelCase wire 格式）

**生成工具链：**
```
Rust Types (ts-rs) → JSON Schema → datamodel-code-generator → Python Pydantic Models
```

### 3.3 关键流程

#### 3.3.1 客户端初始化流程

```python
# 同步版本
with Codex() as codex:  # __enter__ → start() → initialize()
    ...
# __exit__ → close()

# 异步版本
async with AsyncCodex() as codex:  # 懒初始化，首次 API 调用时执行
    ...
```

**详细流程：**
1. `AppServerClient.__init__()` - 创建配置
2. `start()` - 启动子进程 `codex app-server --listen stdio://`
3. `initialize()` - 发送 `initialize` 请求，携带客户端信息
4. `notify("initialized")` - 通知服务器初始化完成
5. 验证响应中的 serverInfo/userAgent

#### 3.3.2 Turn 执行流程

**同步方式（run）：**
```python
result = thread.run("Hello")  # RunResult
# 内部：turn_start() → stream_until completion → collect items → return RunResult
```

**流式方式（stream）：**
```python
turn = thread.turn(TextInput("Hello"))
for event in turn.stream():  # Iterator[Notification]
    if event.method == "item/agentMessage/delta":
        print(event.payload.delta)
    elif event.method == "turn/completed":
        break
```

**RunResult 收集逻辑 (`_run.py`)：**
```python
@dataclass(slots=True)
class RunResult:
    final_response: str | None  # 提取 final_answer 或最后一个无 phase 的消息
    items: list[ThreadItem]     # 所有完成的 item
    usage: ThreadTokenUsage | None  # Token 使用情况
```

#### 3.3.3 并发控制

**限制：** 当前实验版本每个客户端实例仅支持一个活跃的 turn consumer。

```python
# client.py
class AppServerClient:
    def acquire_turn_consumer(self, turn_id: str) -> None:
        with self._turn_consumer_lock:
            if self._active_turn_consumer is not None:
                raise RuntimeError("Concurrent turn consumers are not yet supported...")
            self._active_turn_consumer = turn_id
```

### 3.4 异步实现 (`async_client.py`)

采用 **线程卸载模式** 实现异步：

```python
class AsyncAppServerClient:
    def __init__(self, config: AppServerConfig | None = None) -> None:
        self._sync = AppServerClient(config=config)  # 底层同步客户端
        self._transport_lock = asyncio.Lock()        # 保护 stdio 传输

    async def _call_sync(self, fn, *args, **kwargs):
        async with self._transport_lock:
            return await asyncio.to_thread(fn, *args, **kwargs)
```

**设计理由：**
- stdio 传输是单线程的，无法安全地多线程并发读取
- 通过 `asyncio.Lock()` 序列化所有传输操作
- 使用 `asyncio.to_thread()` 将同步调用卸载到线程池

---

## 4. 关键代码路径与文件引用

### 4.1 文件结构

```
sdk/python/
├── pyproject.toml                    # 包配置，依赖 pydantic>=2.12
├── README.md                         # 项目说明
├── _runtime_setup.py                 # 运行时包自动下载/安装逻辑
│
├── src/codex_app_server/
│   ├── __init__.py                   # 公共 API 导出
│   ├── api.py                        # 高层 API (Codex, Thread, TurnHandle)
│   ├── client.py                     # 底层 JSON-RPC 客户端 (同步)
│   ├── async_client.py               # 异步客户端包装
│   ├── models.py                     # 核心数据模型
│   ├── errors.py                     # 异常类型定义
│   ├── retry.py                      # 重试逻辑
│   ├── _inputs.py                    # 输入类型定义
│   ├── _run.py                       # RunResult 收集逻辑
│   ├── py.typed                      # PEP 561 类型标记
│   │
│   └── generated/
│       ├── __init__.py
│       ├── v2_all.py                 # 从 schema 生成的 Pydantic 模型
│       └── notification_registry.py  # 通知类型映射表
│
├── scripts/
│   └── update_sdk_artifacts.py       # 代码生成脚本 (schema → Python)
│
├── tests/
│   ├── conftest.py                   # pytest 配置
│   ├── test_client_rpc_methods.py    # RPC 方法测试
│   ├── test_public_api_signatures.py # API 签名一致性测试
│   ├── test_public_api_runtime_behavior.py  # 运行时行为测试
│   ├── test_async_client_behavior.py # 异步客户端测试
│   ├── test_contract_generation.py   # 生成代码一致性测试
│   ├── test_artifact_workflow_and_binaries.py  # 发布流程测试
│   └── test_real_app_server_integration.py     # 真实集成测试
│
├── examples/                         # 14 个使用示例
│   ├── _bootstrap.py                 # 示例运行环境初始化
│   ├── _runtime_setup.py             # 运行时包管理
│   └── 01_quickstart_constructor/    # 等 14 个示例目录
│
├── docs/
│   ├── getting-started.md            # 入门指南
│   ├── api-reference.md              # API 参考
│   └── faq.md                        # 常见问题
│
└── notebooks/
    └── sdk_walkthrough.ipynb         # Jupyter 教程
```

### 4.2 核心类继承关系

```
AppServerClient (client.py)
    ├── AsyncAppServerClient (async_client.py) - 包装器
    │
    └── 被以下类使用:
        ├── Codex (api.py)
        ├── Thread (api.py)
        └── TurnHandle (api.py)

AsyncCodex (api.py) - 使用 AsyncAppServerClient
    └── AsyncThread (api.py)
        └── AsyncTurnHandle (api.py)
```

### 4.3 关键代码路径

| 功能 | 入口 | 核心实现文件 |
|------|------|--------------|
| 创建 Thread | `Codex.thread_start()` | `api.py:133-166` → `client.py:303-304` |
| 执行 Turn | `Thread.run()` | `api.py:472-504` → `_run.py:59-83` |
| 流式事件 | `TurnHandle.stream()` | `api.py:655-669` |
| JSON-RPC 请求 | `AppServerClient.request()` | `client.py:227-237` |
| 通知解析 | `_coerce_notification()` | `client.py:455-466` |
| 错误映射 | `map_jsonrpc_error()` | `errors.py:90-113` |
| 模型生成 | `generate_types()` | `scripts/update_sdk_artifacts.py:904-908` |

---

## 5. 依赖与外部交互

### 5.1 Python 依赖

```toml
[project]
dependencies = ["pydantic>=2.12"]
requires-python = ">=3.10"

[project.optional-dependencies]
dev = ["pytest>=8.0", "datamodel-code-generator==0.31.2", "ruff>=0.11"]
```

### 5.2 运行时依赖

| 组件 | 包名 | 说明 |
|------|------|------|
| Codex CLI | `codex-cli-bin` | 平台特定的二进制包，通过 PyPI 分发 |
| 版本 | `0.116.0-alpha.1` | 当前固定版本 (`_runtime_setup.py:19`) |

**运行时包获取流程：**
```
1. 检查本地是否已安装 codex-cli-bin 且版本匹配
2. 如未安装，从 GitHub Releases 下载对应平台二进制
3. 临时构建并安装 codex-cli-bin 包
4. 通过 bundled_codex_path() 获取二进制路径
```

### 5.3 上游协议依赖

| 来源 | 路径 | 用途 |
|------|------|------|
| Rust Schema | `codex-rs/app-server-protocol/schema/json/` | 生成 Python 模型的源 schema |
| TypeScript 定义 | `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 协议实现参考 |

### 5.4 外部服务交互

| 服务 | 用途 | 代码位置 |
|------|------|----------|
| GitHub API | 下载 codex-cli-bin 发布包 | `_runtime_setup.py:123-151` |
| gh CLI | 备选下载方式 | `_runtime_setup.py:207-235` |

---

## 6. 风险、边界与改进建议

### 6.1 已知限制与风险

#### 6.1.1 并发限制

**问题：** 当前版本仅支持单 turn consumer。

```python
# 这将抛出 RuntimeError
with Codex() as codex:
    thread = codex.thread_start()
    turn1 = thread.turn(TextInput("Hello"))
    turn2 = thread.turn(TextInput("World"))  # ❌ 错误：并发 turn
```

**代码位置：** `client.py:288-301`

#### 6.1.2 实验性 API

- 标记为 `experimental_api = True` 的客户端会启用实验性功能
- API 可能在未来版本发生变化

#### 6.1.3 进程生命周期管理

- `Codex()` 构造器是 **eager** 的，立即启动子进程
- 必须使用上下文管理器或显式调用 `close()` 清理
- 子进程异常退出时，错误信息从 stderr 捕获

#### 6.1.4 平台支持

| 平台 | 状态 |
|------|------|
| macOS (arm64/x86_64) | ✅ 支持 |
| Linux (arm64/x86_64) | ✅ 支持 |
| Windows (arm64/x86_64) | ✅ 支持 |

### 6.2 边界条件

| 场景 | 行为 |
|------|------|
| 无可用模型 | `model_list()` 返回空列表 |
| 认证失败 | 初始化时抛出 `AppServerError` |
| 网络超时 | 底层 Rust 处理，SDK 透传错误 |
| 超大输入 | 受限于 Codex CLI 的上下文窗口 |
| 二进制缺失 | `FileNotFoundError` 提示安装 codex-cli-bin |

### 6.3 测试覆盖

| 测试类型 | 文件 | 说明 |
|----------|------|------|
| 单元测试 | `test_client_rpc_methods.py` | RPC 方法调用验证 |
| API 契约测试 | `test_public_api_signatures.py` | 签名一致性检查 |
| 行为测试 | `test_public_api_runtime_behavior.py` | 运行时行为模拟 |
| 异步测试 | `test_async_client_behavior.py` | 异步特性验证 |
| 生成代码测试 | `test_contract_generation.py` | 生成代码未漂移 |
| 发布流程测试 | `test_artifact_workflow_and_binaries.py` | 打包流程验证 |
| 集成测试 | `test_real_app_server_integration.py` | 真实 Codex 后端测试 |

**运行集成测试：**
```bash
RUN_REAL_CODEX_TESTS=1 pytest tests/test_real_app_server_integration.py
```

### 6.4 改进建议

#### 6.4.1 架构层面

1. **支持真正的并发**
   - 当前限制为实验性设计，未来应支持多 turn 并发
   - 需要服务器端支持事件多路复用

2. **连接池支持**
   - 当前每个 `Codex` 实例对应一个子进程
   - 可考虑支持连接池复用多个子进程

3. **WebSocket 传输**
   - 当前仅支持 stdio，可考虑添加 WebSocket 支持
   - 便于远程部署和容器化场景

#### 6.4.2 功能增强

1. **更丰富的重试策略**
   - 当前仅支持 `retry_on_overload`
   - 可添加指数退避、熔断等高级策略

2. **可观测性**
   - 添加结构化日志支持
   - 暴露更多指标（延迟、token 使用量等）

3. **类型安全增强**
   - 利用 Pydantic v2 的严格模式
   - 添加更多运行时类型检查

#### 6.4.3 工程实践

1. **文档生成**
   - 从代码自动生成 API 文档
   - 添加更多使用示例

2. **性能优化**
   - 评估 asyncio 线程卸载的开销
   - 考虑原生异步实现（如需）

3. **错误信息改进**
   - 提供更详细的错误上下文
   - 添加错误恢复建议

---

## 7. 附录

### 7.1 代码生成流程

```bash
# 重新生成 Python 类型（当 Rust schema 变更时）
cd sdk/python
python scripts/update_sdk_artifacts.py generate-types

# 这会：
# 1. 读取 codex-rs/app-server-protocol/schema/json/*.json
# 2. 使用 datamodel-code-generator 生成 v2_all.py
# 3. 生成 notification_registry.py
# 4. 更新 api.py 中的公共方法签名
```

### 7.2 发布流程

```bash
# 1. 生成类型
python scripts/update_sdk_artifacts.py generate-types

# 2. 打包 SDK（指定运行时版本）
python scripts/update_sdk_artifacts.py stage-sdk \
  /tmp/release/codex-app-server-sdk \
  --runtime-version 1.2.3

# 3. 打包运行时（每个平台）
python scripts/update_sdk_artifacts.py stage-runtime \
  /tmp/release/codex-cli-bin \
  /path/to/codex-binary \
  --runtime-version 1.2.3
```

### 7.3 相关文档

| 文档 | 路径 |
|------|------|
| AGENTS.md | `/home/sansha/Github/codex/AGENTS.md` |
| Rust 协议实现 | `codex-rs/app-server-protocol/src/protocol/v2.rs` |
| TypeScript SDK | `sdk/typescript/` |
| 示例代码 | `sdk/python/examples/` |
