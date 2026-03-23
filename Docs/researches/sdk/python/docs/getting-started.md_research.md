# sdk/python/docs/getting-started.md 研究文档

## 场景与职责

`getting-started.md` 是 Codex App Server Python SDK 的快速入门指南，面向首次使用该 SDK 的 Python 开发者。文档提供从安装到运行多轮对话的最快路径，通过循序渐进的示例帮助开发者理解 SDK 的核心概念和使用模式。

该文档的核心职责是：
1. 提供清晰的安装步骤和前置要求
2. 通过简单示例展示 SDK 的基本用法
3. 演示多轮对话（multi-turn）的实现
4. 展示异步客户端的使用方式
5. 说明如何恢复现有线程
6. 引导开发者到更深入的文档和示例

## 功能点目的

### 1. 安装指南
- **目的**：帮助开发者快速设置开发环境
- **安装命令**：`cd sdk/python && python -m pip install -e .`
- **前置要求**：
  - Python `>=3.10`
  - 已安装的 `codex-cli-bin` 运行时包，或显式的 `codex_bin` 覆盖
  - 本地 Codex 认证/会话配置
- **实验性声明**：明确 SDK 是实验性的，API、运行时策略和打包细节可能变化

### 2. 第一个 Turn（同步示例）
- **目的**：展示最基本的 SDK 使用方式
- **关键步骤**：
  1. 导入 `Codex`
  2. 使用上下文管理器 `with Codex() as codex:`
  3. 访问 `codex.metadata.serverInfo` 获取服务器信息
  4. 调用 `thread_start()` 创建线程
  5. 调用 `thread.run()` 执行 Turn
  6. 访问 `result.final_response` 获取回复
- **行为解释**：详细说明每个步骤发生了什么

### 3. 多轮对话示例
- **目的**：展示 Thread 的连续性能力
- **关键概念**：在同一个 Thread 上执行多个 `run()` 调用，模型能看到之前的对话历史
- **示例流程**：
  1. 第一轮："Summarize Rust ownership in 2 bullets."
  2. 第二轮："Now explain it to a Python developer."（能理解"it"指代 Rust ownership）

### 4. 异步客户端示例
- **目的**：展示如何在异步代码中使用 SDK
- **关键模式**：`async with AsyncCodex()`
- **延迟初始化说明**：`AsyncCodex` 在上下文进入或首次 API 使用时初始化
- **代码结构**：完整的 `async def main()` + `asyncio.run(main())` 示例

### 5. 恢复现有线程
- **目的**：展示如何继续之前的对话
- **关键 API**：`codex.thread_resume(THREAD_ID)`
- **使用场景**：持久化线程 ID，在应用重启后继续对话

### 6. 生成模型引用
- **目的**：引导开发者使用完整的类型定义
- **导入路径**：`codex_app_server.generated.v2_all`
- **示例类型**：`Turn`, `TurnStatus`, `ThreadReadResponse`

### 7. 下一步指引
- **目的**：引导开发者深入学习
- **推荐文档**：
  - `docs/api-reference.md` - API 详细参考
  - `docs/faq.md` - 常见问题和最佳实践
  - `examples/README.md` - 可运行的端到端示例

## 具体技术实现

### 安装流程详解

**开发模式安装**（文档推荐）：
```bash
cd sdk/python
python -m pip install -e .
```

**`-e .` 含义**：
- `-e` / `--editable`：以可编辑模式安装
- 修改源代码无需重新安装
- 适合开发和测试

**依赖解析**（`pyproject.toml`）：
```toml
dependencies = ["pydantic>=2.12"]
```

**运行时包检查**（安装时）：
- SDK 本身不强制依赖 `codex-cli-bin`
- 运行时动态检查：`from codex_cli_bin import bundled_codex_path`
- 失败时抛出 `FileNotFoundError`

### 同步客户端初始化流程

**代码路径**：`sdk/python/src/codex_app_server/api.py:69-128`

```python
class Codex:
    def __init__(self, config: AppServerConfig | None = None) -> None:
        self._client = AppServerClient(config=config)
        try:
            self._client.start()           # 启动子进程
            self._init = self._validate_initialize(self._client.initialize())  # 初始化握手
        except Exception:
            self._client.close()
            raise
```

**详细流程**：
1. **创建底层客户端**：`AppServerClient(config=config)`
2. **启动传输**：`self._client.start()`
   - 解析或查找 `codex` 二进制文件路径
   - 启动子进程：`codex app-server --listen stdio://`
   - 启动 stderr 收集线程
3. **初始化握手**：`self._client.initialize()`
   - 发送 `initialize` RPC 请求
   - 接收 `InitializeResponse`
   - 发送 `initialized` 通知
4. **元数据验证**：`_validate_initialize()`
   - 解析 `userAgent` 字符串（格式：`name/version`）
   - 填充 `serverInfo`

### Thread 创建流程

**代码路径**：`sdk/python/src/codex_app_server/api.py:133-166`

```python
def thread_start(
    self,
    *,
    approval_policy: AskForApproval | None = None,
    approvals_reviewer: ApprovalsReviewer | None = None,
    base_instructions: str | None = None,
    ...
) -> Thread:
    params = ThreadStartParams(...)
    started = self._client.thread_start(params)
    return Thread(self._client, started.thread.id)
```

**生成的代码标记**：
```python
# BEGIN GENERATED: Codex.flat_methods
# END GENERATED: Codex.flat_methods
```

**Thread 对象创建**：
```python
@dataclass(slots=True)
class Thread:
    _client: AppServerClient
    id: str
```

### Turn 执行流程（run 方法）

**代码路径**：`sdk/python/src/codex_app_server/api.py:472-504`

```python
def run(
    self,
    input: RunInput,
    *,
    approval_policy: AskForApproval | None = None,
    ...
) -> RunResult:
    turn = self.turn(
        _normalize_run_input(input),
        ...
    )
    stream = turn.stream()
    try:
        return _collect_run_result(stream, turn_id=turn.id)
    finally:
        stream.close()
```

**详细流程**：
1. **输入规范化**：`_normalize_run_input(input)`
   - 字符串 → `TextInput`
   - 其他输入保持不变
2. **创建 Turn**：`self.turn(...)`
   - 调用 `turn/start` RPC
   - 返回 `TurnHandle`
3. **流式消费**：`turn.stream()`
   - 获取通知迭代器
   - 等待 `turn/completed` 通知
4. **结果收集**：`_collect_run_result(stream, turn_id)`
   - 收集所有 `ItemCompletedNotification`
   - 提取 `ThreadTokenUsage`
   - 从 `TurnCompletedNotification` 获取最终状态

**结果提取逻辑**（`sdk/python/src/codex_app_server/_run.py:36-48`）：
```python
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

### 异步客户端初始化

**代码路径**：`sdk/python/src/codex_app_server/api.py:270-321`

```python
class AsyncCodex:
    def __init__(self, config: AppServerConfig | None = None) -> None:
        self._client = AsyncAppServerClient(config=config)
        self._init: InitializeResponse | None = None
        self._initialized = False
        self._init_lock = asyncio.Lock()

    async def _ensure_initialized(self) -> None:
        if self._initialized:
            return
        async with self._init_lock:
            if self._initialized:
                return
            try:
                await self._client.start()
                payload = await self._client.initialize()
                self._init = Codex._validate_initialize(payload)
                self._initialized = True
            except Exception:
                await self._client.close()
                ...
```

**延迟初始化模式**：
1. 构造函数不立即初始化
2. 首次调用 `_ensure_initialized()` 时执行初始化
3. 使用 `asyncio.Lock` 防止并发初始化
4. 上下文管理器自动触发初始化

### 线程恢复实现

**代码路径**：`sdk/python/src/codex_app_server/api.py:192-223`

```python
def thread_resume(
    self,
    thread_id: str,
    *,
    approval_policy: AskForApproval | None = None,
    ...
) -> Thread:
    params = ThreadResumeParams(
        thread_id=thread_id,
        ...
    )
    resumed = self._client.thread_resume(thread_id, params)
    return Thread(self._client, resumed.thread.id)
```

**与 `thread_start` 的区别**：
- `thread_start`：创建新线程，生成新 thread ID
- `thread_resume`：恢复现有线程，使用提供的 thread ID

### 输入类型系统

**代码路径**：`sdk/python/src/codex_app_server/_inputs.py`

```python
@dataclass(slots=True)
class TextInput:
    text: str

InputItem = TextInput | ImageInput | LocalImageInput | SkillInput | MentionInput
Input = list[InputItem] | InputItem
RunInput = Input | str
```

**Wire 格式转换**：
```python
def _to_wire_item(item: InputItem) -> JsonObject:
    if isinstance(item, TextInput):
        return {"type": "text", "text": item.text}
    if isinstance(item, ImageInput):
        return {"type": "image", "url": item.url}
    ...
```

## 关键代码路径与文件引用

### 快速入门涉及的核心文件

| 步骤 | 文件 | 关键代码 |
|-----|------|---------|
| 安装 | `pyproject.toml` | 依赖定义、包配置 |
| 同步客户端 | `api.py` | `Codex` 类 (69-267) |
| 异步客户端 | `api.py` | `AsyncCodex` 类 (270-464) |
| Thread 创建 | `api.py` | `thread_start()` (133-166) |
| Thread 恢复 | `api.py` | `thread_resume()` (192-223) |
| Turn 执行 | `api.py` | `Thread.run()` (472-504) |
| 结果收集 | `_run.py` | `_collect_run_result()` (59-83) |
| 输入处理 | `_inputs.py` | `_normalize_run_input()` (60-63) |
| 底层 RPC | `client.py` | `AppServerClient` 类 (136-540) |
| 异步包装 | `async_client.py` | `AsyncAppServerClient` 类 (39-208) |

### 示例代码文件

| 示例 | 文件 | 说明 |
|-----|------|------|
| 快速开始 | `examples/01_quickstart_constructor/` | 基本初始化和使用 |
| Turn 执行 | `examples/02_turn_run/` | `run()` 方法详细示例 |
| 流式事件 | `examples/03_turn_stream_events/` | `stream()` 方法示例 |
| 恢复线程 | `examples/05_existing_thread/` | `thread_resume()` 示例 |
| 异步使用 | `examples/09_async_parity/` | `AsyncCodex` 示例 |

### 生成模型文件

| 文件 | 内容 |
|------|------|
| `generated/v2_all.py` | 从 Rust 协议生成的 Pydantic 模型 |
| `generated/notification_registry.py` | 通知类型注册表 |

## 依赖与外部交互

### Python 版本要求

**最低版本**：Python 3.10

**原因**：
- 使用 `|` 联合类型语法（PEP 604）
- 使用 `typing.ParamSpec`（Python 3.10+）
- 使用 `slots=True` dataclass 特性

**支持的版本**（`pyproject.toml`）：
```toml
classifiers = [
  "Programming Language :: Python :: 3.10",
  "Programming Language :: Python :: 3.11",
  "Programming Language :: Python :: 3.12",
  "Programming Language :: Python :: 3.13",
]
```

### 运行时包依赖

**包名**：`codex-cli-bin`

**提供内容**：
- `codex` 二进制文件
- `bundled_codex_path()` 函数返回二进制文件路径

**版本匹配**：
- SDK 版本：`0.2.0`
- 运行时版本：`0.116.0-alpha.1`（示例中提到的）
- 需要版本兼容

**覆盖机制**：
```python
config = AppServerConfig(codex_bin="/custom/path/to/codex")
codex = Codex(config=config)
```

### 认证与会话

**要求**：本地 Codex 认证/会话配置

**实现方式**：
- 运行时 (`codex-cli`) 管理认证状态
- SDK 通过环境变量或配置文件继承认证
- 具体机制取决于运行时实现

### 与 App Server 的协议交互

**传输**：JSON-RPC over stdio

**初始化序列**：
```python
# 1. 启动子进程
proc = subprocess.Popen(
    [codex_bin, "app-server", "--listen", "stdio://"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
)

# 2. 发送 initialize 请求
request = {
    "id": str(uuid.uuid4()),
    "method": "initialize",
    "params": {
        "clientInfo": {
            "name": "codex_python_sdk",
            "title": "Codex Python SDK",
            "version": "0.2.0",
        },
        "capabilities": {
            "experimentalApi": True,
        },
    },
}

# 3. 接收 InitializeResponse
response = {
    "serverInfo": {"name": "codex-cli", "version": "x.y.z"},
    "userAgent": "codex-cli/x.y.z",
    ...
}

# 4. 发送 initialized 通知
notification = {"method": "initialized", "params": {}}
```

## 风险、边界与改进建议

### 当前风险

1. **实验性 API 的不稳定性**
   - **风险**：文档明确说明 SDK 是实验性的，API 可能变化
   - **影响**：生产环境使用可能面临破坏性变更
   - **缓解**：锁定 SDK 版本，关注更新日志
   - **建议**：在文档中添加版本兼容性矩阵

2. **同步客户端的阻塞初始化**
   - **风险**：`Codex()` 构造函数立即启动子进程并执行 RPC
   - **影响**：可能阻塞事件循环或超时
   - **缓解**：文档推荐使用 `AsyncCodex` 进行异步代码
   - **建议**：添加同步客户端的超时配置选项

3. **运行时包版本不匹配**
   - **风险**：SDK 与运行时包版本不兼容
   - **影响**：协议错误、功能异常
   - **缓解**：维护者通过发布流程确保版本匹配
   - **建议**：SDK 添加运行时版本检查，提供清晰的错误消息

4. **资源泄漏风险**
   - **风险**：不使用上下文管理器可能导致子进程泄漏
   - **影响**：僵尸进程、资源耗尽
   - **缓解**：文档强调使用 `with` 语句
   - **建议**：添加 `atexit` 处理器清理未关闭的客户端

### 边界情况

1. **空输入处理**
   - `thread.run("")` 会创建空文本输入
   - 服务器行为未明确文档化
   - 建议：客户端添加空输入验证

2. **超长对话历史**
   - 多轮对话可能导致上下文窗口溢出
   - 文档未说明如何处理
   - 建议：添加关于 `compact()` 方法的说明

3. **网络中断恢复**
   - 文档未说明网络中断后的恢复策略
   - `thread_resume` 需要线程 ID，但获取方式未详细说明
   - 建议：添加持久化和恢复的最佳实践

4. **并发限制**
   - 当前版本限制单客户端单 Turn 消费者
   - 文档未明确说明此限制
   - 建议：在快速入门中添加并发限制说明

### 改进建议

1. **增强错误处理示例**
   - 当前示例假设一切正常
   - 建议：添加错误处理示例，展示如何捕获和处理常见异常

2. **添加配置示例**
   - 文档未展示 `AppServerConfig` 的使用
   - 建议：添加配置自定义二进制路径、环境变量的示例

3. **扩展多轮对话示例**
   - 当前示例只有两轮对话
   - 建议：展示更多轮次，演示上下文保持能力

4. **添加性能提示**
   - 未说明 `run()` vs `stream()` 的性能差异
   - 建议：添加关于内存使用和延迟的说明

5. **改进下一步指引**
   - 当前指引较简单
   - 建议：根据使用场景（简单脚本、Web 应用、CLI 工具）提供不同的学习路径

6. **添加故障排除部分**
   - 常见问题：连接失败、认证错误、超时
   - 建议：添加专门的故障排除章节

### 文档结构建议

```markdown
## 快速入门（当前内容）

## 配置指南（新增）
- 自定义运行时路径
- 环境变量配置
- 代理设置

## 故障排除（新增）
- 连接问题
- 认证问题
- 性能问题

## 最佳实践（新增）
- 资源管理
- 错误处理
- 性能优化
```
