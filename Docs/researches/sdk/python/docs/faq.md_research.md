# sdk/python/docs/faq.md 研究文档

## 场景与职责

`faq.md` 是 Codex App Server Python SDK 的常见问题解答文档，面向正在使用或准备使用该 SDK 的 Python 开发者。文档采用问答形式，解释了 SDK 的核心概念、使用模式、常见问题和最佳实践。

该文档的核心职责是：
1. 澄清 Thread 与 Turn 的概念区别
2. 解释 `run()` 与 `stream()` 两种消费模式的选择依据
3. 指导同步与异步客户端的选择
4. 说明 API 命名规范（snake_case vs camelCase）
5. 解释设计决策背后的原因（如为什么只有 `thread_start` 和 `thread_resume`）
6. 提供故障排查指南（构造函数失败、Turn 挂起等）
7. 列出常见陷阱和避免方法

## 功能点目的

### 1. Thread vs Turn 概念澄清
- **目的**：帮助开发者理解 SDK 的核心抽象模型
- **Thread**：对话状态，维护多轮对话的上下文连续性
- **Turn**：单次模型执行，是 Thread 内的一次交互单元
- **关键洞察**：多轮对话 = 同一个 Thread 上的多个 Turn

### 2. `run()` vs `stream()` 模式选择
- **目的**：指导开发者根据应用场景选择合适的 Turn 消费方式
- **`run()`**：
  - 最简单的使用路径
  - 消费所有事件直到完成
  - 返回生成的 `Turn` 模型对象
  - 适合大多数应用场景
- **`stream()`**：
  - 产生原始通知 (`Notification`)
  - 允许事件级别的细粒度控制
  - 适合进度 UI、自定义超时逻辑、自定义解析

### 3. 同步 vs 异步客户端选择
- **目的**：帮助开发者根据现有代码库选择合适的客户端类型
- **`Codex`**：同步公共 API，适合非异步代码
- **`AsyncCodex`**：异步镜像 API，适合异步代码
- **最佳实践**：
  - 已有异步代码优先使用 `async with AsyncCodex()`
  - `AsyncCodex` 延迟初始化，上下文管理器确保显式启动/关闭
  - 非异步应用保持使用 `Codex`

### 4. 命名规范说明
- **目的**：解释公共 API 的命名约定，帮助迁移旧代码
- **公共 API**：snake_case（Python 惯例）
- **Wire 协议**：camelCase（JSON-RPC 惯例）
- **SDK 自动映射**：内部自动转换
- **迁移对照表**：
  - `approvalPolicy` → `approval_policy`
  - `baseInstructions` → `base_instructions`
  - `developerInstructions` → `developer_instructions`
  - `modelProvider` → `model_provider`
  - `modelProviders` → `model_providers`
  - `sortKey` → `sort_key`
  - `sourceKinds` → `source_kinds`
  - `outputSchema` → `output_schema`
  - `sandboxPolicy` → `sandbox_policy`

### 5. 显式生命周期设计解释
- **目的**：解释为什么公共 API 只保留显式的生命周期调用
- **提供的 API**：
  - `thread_start(...)` - 创建新线程
  - `thread_resume(thread_id, ...)` - 继续现有线程
- **设计原则**：避免同一操作的多种方式，保持行为显式
- **对比**：早期版本可能有隐式线程创建，现在要求显式调用

### 6. 构造函数失败排查
- **目的**：帮助诊断 `Codex()` 初始化失败的原因
- **常见原因**：
  - `codex-cli-bin` 运行时包未安装
  - `codex_bin` 覆盖指向缺失文件
  - 本地认证/会话缺失
  - 不兼容/过时的 app-server
- **发布流程**：维护者通过构建 SDK 和运行时来分阶段发布

### 7. Turn "挂起" 解释
- **目的**：解释为什么 Turn 看起来会"挂起"
- **根本原因**：Turn 仅在收到 `turn/completed` 通知时才算完成
- **`run()` 的行为**：自动等待完成
- **`stream()` 的行为**：需要持续消费通知直到完成
- **解决方案**：确保正确处理流式通知

### 8. 安全重试指南
- **目的**：指导如何正确处理瞬态错误
- **推荐**：使用 `retry_on_overload(...)` 处理 `ServerBusyError`
- **警告**：不要盲目重试所有错误
- **不可重试错误**：`InvalidParamsError`, `MethodNotFoundError` 需要修复输入/版本兼容性

### 9. 常见陷阱清单
- **目的**：帮助开发者避免常见错误
- **陷阱列表**：
  - 为每个提示创建新线程（破坏对话连续性）
  - 忘记 `close()` 或不使用上下文管理器
  - 假设 `run()` 返回 SDK 特有字段（实际返回生成的 `Turn` 模型）
  - 错误地混合 SDK 输入类和原始字典

## 具体技术实现

### 命名转换实现

**代码位置**：`sdk/python/src/codex_app_server/client.py:53-77`

```python
def _params_dict(
    params: (
        V2ThreadStartParams
        | V2ThreadResumeParams
        | V2ThreadListParams
        | V2ThreadForkParams
        | V2TurnStartParams
        | JsonObject
        | None
    ),
) -> JsonObject:
    if params is None:
        return {}
    if hasattr(params, "model_dump"):
        dumped = params.model_dump(
            by_alias=True,      # 使用字段别名（camelCase）
            exclude_none=True,  # 排除 None 值
            mode="json",
        )
        ...
```

**Pydantic 模型配置**（生成代码）：
```python
class ThreadStartParams(BaseModel):
    model_config = ConfigDict(
        populate_by_name=True,  # 允许通过字段名和别名访问
    )
    approval_policy: Annotated[
        AskForApproval | None,
        Field(alias="approvalPolicy")  # Wire 格式使用 camelCase
    ] = None
```

### 构造函数失败检测

**代码位置**：`sdk/python/src/codex_app_server/client.py:80-91`

```python
def _installed_codex_path() -> Path:
    try:
        from codex_cli_bin import bundled_codex_path
    except ImportError as exc:
        raise FileNotFoundError(
            "Unable to locate the pinned Codex runtime. Install the published SDK build "
            f"with its {RUNTIME_PKG_NAME} dependency, or set AppServerConfig.codex_bin "
            "explicitly."
        ) from exc
    return bundled_codex_path()
```

**运行时包名称**：`RUNTIME_PKG_NAME = "codex-cli-bin"`

### Turn 完成检测

**代码位置**：`sdk/python/src/codex_app_server/api.py:655-669`

```python
def stream(self) -> Iterator[Notification]:
    self._client.acquire_turn_consumer(self.id)
    try:
        while True:
            event = self._client.next_notification()
            yield event
            if (
                event.method == "turn/completed"
                and isinstance(event.payload, TurnCompletedNotification)
                and event.payload.turn.id == self.id
            ):
                break
    finally:
        self._client.release_turn_consumer(self.id)
```

**异步版本**：`sdk/python/src/codex_app_server/api.py:705-720`

### 重试机制实现

**代码位置**：`sdk/python/src/codex_app_server/retry.py:12-41`

```python
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
            if sleep_for > 0:
                time.sleep(sleep_for)
            delay = min(max_delay_s, delay * 2)
```

**可重试错误检测**：`sdk/python/src/codex_app_server/errors.py:116-125`

```python
def is_retryable_error(exc: BaseException) -> bool:
    if isinstance(exc, ServerBusyError):
        return True
    if isinstance(exc, JsonRpcError):
        return _is_server_overloaded(exc.data)
    return False
```

### 资源清理模式

**同步上下文管理器**：`sdk/python/src/codex_app_server/api.py:81-85`

```python
def __enter__(self) -> "Codex":
    return self

def __exit__(self, _exc_type, _exc, _tb) -> None:
    self.close()
```

**异步上下文管理器**：`sdk/python/src/codex_app_server/api.py:284-289`

```python
async def __aenter__(self) -> "AsyncCodex":
    await self._ensure_initialized()
    return self

async def __aexit__(self, _exc_type, _exc, _tb) -> None:
    await self.close()
```

**客户端关闭**：`sdk/python/src/codex_app_server/client.py:191-207`

```python
def close(self) -> None:
    if self._proc is None:
        return
    proc = self._proc
    self._proc = None
    self._active_turn_consumer = None

    if proc.stdin:
        proc.stdin.close()
    try:
        proc.terminate()
        proc.wait(timeout=2)
    except Exception:
        proc.kill()

    if self._stderr_thread and self._stderr_thread.is_alive():
        self._stderr_thread.join(timeout=0.5)
```

## 关键代码路径与文件引用

### FAQ 涉及的核心实现文件

| FAQ 主题 | 实现文件 | 关键代码位置 |
|---------|---------|-------------|
| Thread vs Turn | `api.py` | `Thread` 类 (467-549), `TurnHandle` 类 (643-735) |
| run() vs stream() | `api.py` | `Thread.run()` (472-504), `TurnHandle.stream()` (655-669) |
| Sync vs Async | `api.py` | `Codex` 类 (69-267), `AsyncCodex` 类 (270-464) |
| 命名规范 | `client.py` | `_params_dict()` (53-77) |
| 构造函数失败 | `client.py` | `_installed_codex_path()` (80-91) |
| Turn 挂起 | `api.py` | `stream()` 中的完成检测 (655-669) |
| 重试机制 | `retry.py` | `retry_on_overload()` (12-41) |
| 资源清理 | `client.py` | `close()` (191-207) |

### 测试验证文件

| 文件 | 验证内容 |
|------|---------|
| `tests/test_public_api_signatures.py` | 验证 snake_case 参数命名 |
| `tests/test_client_rpc_methods.py` | 验证 RPC 方法调用和通知处理 |
| `tests/test_async_client_behavior.py` | 验证异步客户端行为 |

### 示例代码

| 示例 | 说明 |
|------|------|
| `examples/02_turn_run/` | `run()` 模式使用示例 |
| `examples/03_turn_stream_events/` | `stream()` 模式使用示例 |
| `examples/09_async_parity/` | 异步客户端使用示例 |
| `examples/10_error_handling_and_retry/` | 错误处理和重试示例 |

## 依赖与外部交互

### 与运行时包的交互

**依赖关系**：
- SDK (`codex-app-server-sdk`) 依赖运行时包 (`codex-cli-bin`)
- 运行时包提供 `codex` 二进制文件
- 运行时包通过 `bundled_codex_path()` 暴露二进制文件位置

**错误场景**：
```python
# 当运行时包未安装时
from codex_cli_bin import bundled_codex_path  # ImportError
```

**覆盖机制**：
```python
config = AppServerConfig(codex_bin="/path/to/custom/codex")
codex = Codex(config=config)
```

### 与 App Server 的协议交互

**初始化序列**（FAQ 中构造函数失败的相关部分）：
```
1. SDK 启动子进程: codex app-server --listen stdio://
2. SDK -> Server: initialize { clientInfo: {...}, capabilities: {...} }
3. Server -> SDK: { serverInfo: {...}, userAgent: "...", ... }
4. SDK -> Server: initialized (notification)
```

**失败点**：
- 步骤 1：二进制文件不存在 → `FileNotFoundError`
- 步骤 2/3：认证失败 → 连接关闭
- 步骤 3：版本不兼容 → 协议错误

### 发布流程（维护者视角）

**FAQ 中提到的发布命令**：
```bash
cd sdk/python
python scripts/update_sdk_artifacts.py generate-types
python scripts/update_sdk_artifacts.py stage-sdk /tmp/codex-python-release/codex-app-server-sdk --runtime-version 1.2.3
python scripts/update_sdk_artifacts.py stage-runtime /tmp/codex-python-release/codex-cli-bin /path/to/codex --runtime-version 1.2.3
```

**流程说明**：
1. `generate-types`：从 Rust 协议生成 Python 类型
2. `stage-sdk`：准备 SDK 包（纯 Python）
3. `stage-runtime`：准备运行时包（平台特定二进制文件）

## 风险、边界与改进建议

### 当前风险

1. **隐式资源管理风险**
   - **风险**：开发者可能忘记使用上下文管理器，导致子进程泄漏
   - **代码**：`Codex()` 立即启动子进程，需要显式 `close()`
   - **缓解**：文档强调使用 `with Codex()` 模式
   - **改进建议**：添加弱引用跟踪未关闭的客户端，在垃圾回收时发出警告

2. **Turn 完成检测的可靠性**
   - **风险**：如果 `turn/completed` 通知丢失，流式消费会无限挂起
   - **代码**：`stream()` 使用 `while True` 循环等待特定通知
   - **缓解**：文档说明需要持续消费通知
   - **改进建议**：添加超时机制和心跳检测

3. **重试的副作用**
   - **风险**：非幂等操作的重试可能导致意外副作用
   - **代码**：`retry_on_overload` 对所有 `is_retryable_error` 返回 True 的异常重试
   - **缓解**：文档警告不要盲目重试所有错误
   - **改进建议**：明确标记哪些操作是幂等的，对非幂等操作添加特殊处理

4. **命名转换的混淆**
   - **风险**：开发者可能混淆 snake_case 和 camelCase 的使用场景
   - **代码**：SDK 内部转换，但生成的模型字段使用 camelCase 别名
   - **缓解**：FAQ 提供完整的对照表
   - **改进建议**：添加类型检查器插件，在开发时捕获命名错误

### 边界情况

1. **空输入处理**
   - `Thread.run("")` 会创建空的 `TextInput`，行为取决于服务器
   - 建议：客户端添加空输入验证

2. **超长线程 ID 或 Turn ID**
   - 文档未说明 ID 长度限制
   - 实际限制取决于服务器实现

3. **并发 Turn 启动**
   - 当前版本明确禁止并发 Turn 消费者
   - 代码抛出 `RuntimeError`："Concurrent turn consumers are not yet supported"

### 改进建议

1. **增强 FAQ 内容**
   - 添加关于网络代理配置的说明
   - 添加关于大文件/图片上传的性能建议
   - 添加关于内存使用的最佳实践（长时间运行的 Thread）

2. **改进错误消息**
   - 构造函数失败时提供更具体的故障排除步骤
   - 添加链接到在线文档的错误代码

3. **添加诊断工具**
   - 提供 `codex_app_server.doctor()` 函数检查环境配置
   - 验证运行时包、认证状态、网络连接

4. **文档自动化**
   - 从代码自动生成 FAQ 中的 API 对照表
   - 确保文档与代码实现同步

5. **示例扩展**
   - 添加更多边缘情况的处理示例
   - 添加性能优化示例
   - 添加单元测试集成示例
