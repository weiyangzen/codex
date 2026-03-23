# 研究文档: sdk/python/examples/09_async_parity/sync.py

## 1. 场景与职责

### 1.1 文件定位

`sync.py` 是 Codex Python SDK 示例集合中的第 9 个示例（`09_async_parity`），专门用于展示**同步 API 与异步 API 的 API 对等性（Parity）**。该示例与 `02_turn_run/sync.py` 几乎相同，但位于独立的 `09_async_parity` 目录中，用于强调同步和异步 API 在功能上的一致性。

### 1.2 核心职责

- **API 对等性验证**：证明同步 (`Codex`) 和异步 (`AsyncCodex`) API 提供完全相同的功能集
- **基础使用模式展示**：演示使用同步 SDK 进行单轮对话的标准流程
- **线程生命周期管理**：展示从创建线程、执行 Turn、读取结果到验证持久化状态的完整流程
- **模型配置示例**：展示如何通过 `config` 参数传递模型特定配置（如 `model_reasoning_effort`）

### 1.3 目录结构上下文

```
sdk/python/examples/
├── 01_quickstart_constructor/    # 基础初始化
├── 02_turn_run/                  # Turn 执行基础（sync.py 与本文件几乎相同）
├── 03_turn_stream_events/        # 事件流式处理
├── 04_models_and_metadata/       # 模型发现
├── 05_existing_thread/           # 已有线程恢复
├── 06_thread_lifecycle_and_controls/  # 线程生命周期
├── 07_image_and_text/            # 远程图片+文本多模态
├── 08_local_image_and_text/      # 本地图片+文本多模态
├── 09_async_parity/              # 本文件所在目录（API 对等性）
│   └── sync.py                   # 目标研究文件
├── 10_error_handling_and_retry/  # 错误处理与重试
├── 11_cli_mini_app/              # 交互式聊天循环
├── 12_turn_params_kitchen_sink/  # 高级 Turn 配置
├── 13_model_select_and_turn_params/  # 模型选择与参数
├── 14_turn_controls/             # Turn 控制（steer/interrupt）
├── _bootstrap.py                 # 共享引导工具
└── README.md                     # 示例文档
```

---

## 2. 功能点目的

### 2.1 主要功能点

| 功能点 | 目的 | 对应代码行 |
|--------|------|-----------|
| 路径引导 | 将 `examples/` 目录加入 `sys.path` 以支持本地导入 | 1-6 |
| SDK 引导 | 确保本地 SDK 源码可用并检查依赖 | 8-16 |
| 客户端初始化 | 使用 `runtime_config()` 创建同步 `Codex` 客户端 | 20 |
| 服务器信息展示 | 打印连接的服务器版本信息 | 21 |
| 线程创建 | 启动新线程并配置模型参数 | 23 |
| Turn 执行 | 创建并执行单轮对话 | 24-25 |
| 状态验证 | 读取持久化线程状态并查找对应 Turn | 26-27 |
| 结果输出 | 打印线程 ID、Turn ID 和助手回复文本 | 29-31 |

### 2.2 与 02_turn_run/sync.py 的差异对比

| 特性 | 02_turn_run/sync.py | 09_async_parity/sync.py |
|------|---------------------|-------------------------|
| 主要目的 | 展示 Turn 执行基础 | 强调同步/异步 API 对等性 |
| 输入内容 | "Give 3 bullets about SIMD." | "Say hello in one sentence." |
| 输出字段 | 完整（含 status、error、items count） | 精简（仅 Thread ID、Turn ID、Text） |
| 引导函数 | 使用 `runtime_config` | 额外使用 `server_label` |
| 复杂度 | 更详细（展示错误处理和状态检查） | 更简洁（聚焦核心流程） |

---

## 3. 具体技术实现

### 3.1 关键流程

```
┌─────────────────────────────────────────────────────────────────┐
│  1. 引导阶段 (Bootstrap)                                         │
│     ├── 将 examples/ 目录加入 sys.path                          │
│     ├── 从 _bootstrap 导入辅助函数                              │
│     └── 调用 ensure_local_sdk_src() 确保 SDK 可用               │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  2. 客户端初始化 (Client Init)                                   │
│     ├── 创建 AppServerConfig（通过 runtime_config()）           │
│     ├── 启动 codex app-server 子进程（stdio 传输）              │
│     ├── 发送 initialize RPC 请求                                │
│     └── 验证服务器元数据（userAgent、serverInfo）               │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  3. 线程创建 (Thread Creation)                                   │
│     ├── 调用 thread/start RPC                                   │
│     ├── 传递参数：model="gpt-5.4"                               │
│     │              config={"model_reasoning_effort": "high"}    │
│     └── 返回 Thread 对象（包含 thread.id）                      │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  4. Turn 执行 (Turn Execution)                                   │
│     ├── 创建 TextInput("Say hello in one sentence.")            │
│     ├── 调用 thread.turn() → 内部调用 turn/start RPC            │
│     ├── 调用 turn.run() → 阻塞等待 turn/completed 通知          │
│     │   └── 流式消费通知直到收到匹配的 turn/completed           │
│     └── 返回 AppServerTurn 对象（包含 turn.id、status、items）  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  5. 状态验证 (State Verification)                                │
│     ├── 调用 thread.read(include_turns=True)                    │
│     │   └── 调用 thread/read RPC 获取完整线程状态               │
│     ├── 使用 find_turn_by_id() 在 turns 列表中查找目标 Turn     │
│     └── 使用 assistant_text_from_turn() 提取助手回复文本        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  6. 资源清理 (Cleanup)                                           │
│     └── 上下文管理器退出时调用 codex.close()                    │
│         ├── 关闭 stdin/stdout 管道                              │
│         ├── 终止 app-server 子进程                              │
│         └── 等待 stderr  drain 线程结束                         │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 关键数据结构

#### 3.2.1 输入类型 (`_inputs.py`)

```python
@dataclass(slots=True)
class TextInput:
    text: str

InputItem = TextInput | ImageInput | LocalImageInput | SkillInput | MentionInput
Input = list[InputItem] | InputItem
RunInput = Input | str
```

#### 3.2.2 Turn 启动参数 (`generated/v2_all.py`)

```python
class TurnStartParams(BaseModel):
    thread_id: Annotated[str, Field(alias="threadId")]
    input: list[JsonObject]  # 标准化后的输入项
    approval_policy: AskForApproval | None = None
    approvals_reviewer: ApprovalsReviewer | None = None
    cwd: str | None = None
    effort: ReasoningEffort | None = None
    model: str | None = None
    output_schema: JsonObject | None = None
    personality: Personality | None = None
    sandbox_policy: SandboxPolicy | None = None
    service_tier: ServiceTier | None = None
    summary: ReasoningSummary | None = None
```

#### 3.2.3 Turn 响应 (`generated/v2_all.py`)

```python
class Turn(BaseModel):
    id: str
    status: TurnStatus  # "in_progress" | "completed" | "failed" | ...
    items: list[ThreadItem] | None = None
    error: CodexError | None = None
    # ... 其他字段

class TurnStartResponse(BaseModel):
    turn: Turn
```

#### 3.2.4 通知类型 (`models.py`)

```python
@dataclass(slots=True)
class Notification:
    method: str  # 如 "turn/completed", "item/completed"
    payload: NotificationPayload
```

关键通知：
- `TurnCompletedNotification`: Turn 完成时发送
- `ItemCompletedNotification`: 单个 Item（如助手消息）完成时发送
- `ThreadTokenUsageUpdatedNotification`: Token 使用量更新

### 3.3 协议与通信机制

#### 3.3.1 JSON-RPC over stdio

SDK 通过标准输入输出与 `codex app-server` 子进程通信，使用 JSON-RPC 2.0 协议：

**请求格式** (`client.py:241`):
```python
{"id": request_id, "method": method, "params": params}
```

**响应格式**:
```python
{"id": request_id, "result": {...}}  # 成功
{"id": request_id, "error": {"code": ..., "message": ...}}  # 失败
```

**通知格式** (服务器→客户端):
```python
{"method": "turn/completed", "params": {...}}  # 无 id 字段
```

**服务器请求格式** (客户端→服务器的请求):
```python
{"id": id, "method": "item/commandExecution/requestApproval", "params": {...}}
```

#### 3.3.2 核心 RPC 方法

| 方法 | 方向 | 用途 |
|------|------|------|
| `initialize` | C→S | 初始化连接，交换客户端/服务器信息 |
| `initialized` | C→S | 通知服务器初始化完成 |
| `thread/start` | C→S | 创建新线程 |
| `turn/start` | C→S | 在指定线程启动新 Turn |
| `thread/read` | C→S | 读取线程状态和 Turn 列表 |
| `turn/completed` | S→C | 通知 Turn 完成 |
| `item/completed` | S→C | 通知单个 Item 完成 |

---

## 4. 关键代码路径与文件引用

### 4.1 调用链分析

```
sync.py:20
    └── with Codex(config=runtime_config()) as codex:
        └── api.py:69-86 (Codex 类)
            ├── client.py:154-159 (__enter__/__exit__)
            │   └── start() / close()
            ├── client.py:209-225 (initialize)
            │   ├── request("initialize", ...)
            │   └── notify("initialized", None)
            └── _validate_initialize() (元数据验证)

sync.py:23
    └── codex.thread_start(model="gpt-5.4", config={...})
        └── api.py:133-166
            └── client.py:303-304 (thread_start)
                └── request("thread/start", _params_dict(params), ...)

sync.py:24
    └── thread.turn(TextInput(...))
        └── api.py:507-538 (Thread.turn)
            ├── _to_wire_input(input) → [{"type": "text", "text": "..."}]
            └── client.py:352-363 (turn_start)
                └── request("turn/start", ...)

sync.py:25
    └── turn.run()
        └── api.py:671-684 (TurnHandle.run)
            └── stream() → 消费通知直到 turn/completed

sync.py:26
    └── thread.read(include_turns=True)
        └── client.py:317-322 (thread_read)
            └── request("thread/read", ...)
```

### 4.2 核心文件清单

| 文件路径 | 职责 | 与本文件关系 |
|---------|------|-------------|
| `examples/09_async_parity/sync.py` | 本研究文件 | 目标文件 |
| `examples/_bootstrap.py` | 共享引导工具 | 被导入，提供 `ensure_local_sdk_src`, `runtime_config`, `assistant_text_from_turn`, `find_turn_by_id`, `server_label` |
| `src/codex_app_server/__init__.py` | 公共 API 导出 | 提供 `Codex`, `TextInput` 等 |
| `src/codex_app_server/api.py` | 高级 API 实现 | `Codex`, `Thread`, `TurnHandle` 类实现 |
| `src/codex_app_server/client.py` | 底层同步客户端 | `AppServerClient` 类，JSON-RPC 通信 |
| `src/codex_app_server/async_client.py` | 异步客户端包装 | `AsyncAppServerClient` 类，线程卸载 |
| `src/codex_app_server/_inputs.py` | 输入类型定义 | `TextInput` 等输入类型 |
| `src/codex_app_server/_run.py` | 结果收集逻辑 | `RunResult`, `_collect_run_result` |
| `src/codex_app_server/models.py` | 共享模型定义 | `InitializeResponse`, `Notification`, `JsonObject` |
| `src/codex_app_server/generated/v2_all.py` | 生成的 Pydantic 模型 | `TurnStartParams`, `Turn`, `TurnCompletedNotification` 等 |
| `src/codex_app_server/errors.py` | 异常定义与映射 | `AppServerError`, `JsonRpcError` 等 |
| `src/codex_app_server/retry.py` | 重试逻辑 | `retry_on_overload` |

---

## 5. 依赖与外部交互

### 5.1 Python 依赖

```python
# 标准库
import sys
from pathlib import Path

# 第三方库（通过 _bootstrap 检查）
import pydantic  # 数据验证

# 本地 SDK（通过 _bootstrap 引导）
from codex_app_server import Codex, TextInput
```

### 5.2 外部进程交互

```
sync.py ──spawn──> codex app-server --listen stdio://
                      │
                      ├── stdin  <-- JSON-RPC 请求
                      └── stdout --> JSON-RPC 响应/通知
```

**运行时二进制**: 通过 `codex-cli-bin` Python 包提供，版本 `0.116.0-alpha.1`

### 5.3 网络交互（间接）

`codex app-server` 子进程内部会：
- 连接到 OpenAI API（或其他配置的模型提供商）
- 执行沙箱命令（如文件操作）
- 发送通知到客户端（本示例）

### 5.4 配置依赖

`runtime_config()` 返回的 `AppServerConfig` 包含：
- `codex_bin`: 可选的自定义二进制路径
- `launch_args_override`: 可选的启动参数覆盖
- `config_overrides`: 配置覆盖项（`--config key=value`）
- `cwd`: 工作目录
- `env`: 环境变量
- `client_name`, `client_title`, `client_version`: 客户端标识
- `experimental_api`: 实验性 API 开关（默认 True）

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 描述 | 缓解措施 |
|------|------|---------|
| 并发限制 | SDK 当前不支持并发 Turn 消费 (`acquire_turn_consumer` 会报错) | 确保单线程顺序执行 Turn |
| 进程泄露 | 如果 `Codex` 未正确关闭，app-server 子进程可能残留 | 始终使用上下文管理器 `with Codex()` |
| 网络依赖 | 需要有效的 OpenAI API 凭据和网络连接 | 配置正确的环境变量或配置文件 |
| 模型可用性 | `gpt-5.4` 可能不是所有环境都可用 | 使用 `codex.models()` 查询可用模型 |

### 6.2 边界情况

1. **空响应处理**: `assistant_text_from_turn()` 在 Turn 为 None 时返回空字符串
2. **错误状态**: 如果 Turn 失败，`turn.run()` 会抛出 `RuntimeError`（在 `_raise_for_failed_turn` 中实现）
3. **超时**: 当前实现没有内置超时，可能无限期阻塞等待 `turn/completed`
4. **信号处理**: 如果进程被信号中断，可能无法正确清理子进程

### 6.3 改进建议

#### 6.3.1 代码层面

1. **添加超时支持**:
   ```python
   # 建议添加 timeout 参数
   result = turn.run(timeout=30.0)  # 30秒超时
   ```

2. **更健壮的错误处理**:
   ```python
   try:
       result = turn.run()
   except TurnFailedError as e:
       print(f"Turn failed: {e.message}")
   except TimeoutError:
       print("Turn timed out")
   ```

3. **异步示例补充**: 当前目录只有 `sync.py`，建议添加对应的 `async.py` 以真正展示 API 对等性

#### 6.3.2 文档层面

1. **明确说明与 02_turn_run 的区别**: 当前 README 描述较简略，可补充：
   > "09_async_parity 示例与 02_turn_run 功能相同，但专注于展示同步 API 的简洁用法，作为与异步 API 对比的基准。"

2. **添加注释说明 `server_label` 的用途**:
   ```python
   # 展示服务器版本信息，用于调试和验证连接
   print("Server:", server_label(codex.metadata))
   ```

#### 6.3.3 测试层面

1. **添加 API 对等性测试**: 验证同步和异步 API 的输出一致性
2. **集成测试**: 在 CI 中运行示例确保其始终可用

### 6.4 相关测试文件

| 测试文件 | 覆盖内容 |
|---------|---------|
| `tests/test_public_api_runtime_behavior.py` | Turn 执行、流式处理、结果收集 |
| `tests/test_async_client_behavior.py` | 异步客户端序列化和流式行为 |
| `tests/test_client_rpc_methods.py` | RPC 方法调用、参数序列化 |
| `tests/test_public_api_signatures.py` | 公共 API 签名一致性 |

---

## 7. 总结

`09_async_parity/sync.py` 是一个**简洁的同步 API 使用示例**，其核心目的是：

1. **展示标准使用模式**：线程创建 → Turn 执行 → 结果验证
2. **强调 API 对等性**：作为与异步 API 对比的基准
3. **演示配置传递**：通过 `config` 参数传递模型特定配置

该示例代码简洁、职责清晰，适合作为 SDK 入门学习的参考。但目录中缺少对应的 `async.py` 文件，建议补充以完整展示 API 对等性概念。
