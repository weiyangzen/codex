# Codex SDK 深度研究报告

## 目录

1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 1.1 整体定位

Codex SDK 是 OpenAI Codex CLI 的官方客户端开发工具包，提供 Python 和 TypeScript 两种语言绑定，使开发者能够以编程方式与 Codex Agent 进行交互。SDK 采用分层架构设计：

- **底层**: 通过 stdio 与 `codex app-server` 进程进行 JSON-RPC v2 通信
- **中层**: 类型化的客户端封装（同步/异步）
- **上层**: 面向开发者友好的高级 API（Thread/Turn 抽象）

### 1.2 核心使用场景

| 场景 | 说明 |
|------|------|
| **自动化工作流** | 在 CI/CD 管道中集成 Codex Agent 执行代码审查、重构任务 |
| **批量处理** | 对多个文件或项目执行相同的 AI 辅助操作 |
| **自定义应用** | 构建基于 Codex 的专用工具或 IDE 插件 |
| **多轮对话** | 维护长期上下文的多轮编程对话 |
| **结构化输出** | 通过 JSON Schema 获取结构化响应 |

### 1.3 职责边界

```
┌─────────────────────────────────────────────────────────────┐
│                      用户应用程序                            │
├─────────────────────────────────────────────────────────────┤
│  Codex SDK (Python/TypeScript)                              │
│  ├── 高级 API: Codex / Thread / TurnHandle                  │
│  ├── 输入抽象: TextInput / ImageInput / LocalImageInput     │
│  └── 结果聚合: RunResult / Notification 流                  │
├─────────────────────────────────────────────────────────────┤
│  JSON-RPC v2 over stdio                                     │
├─────────────────────────────────────────────────────────────┤
│  codex app-server (Rust 二进制)                             │
│  └── 实际执行: OpenAI API 调用、沙箱命令执行、文件修改       │
└─────────────────────────────────────────────────────────────┘
```

---

## 功能点目的

### 2.1 Python SDK 功能矩阵

| 功能模块 | 核心类/函数 | 目的 |
|----------|-------------|------|
| **客户端管理** | `Codex` / `AsyncCodex` | 管理 app-server 进程生命周期 |
| **线程操作** | `Thread` / `AsyncThread` | 对话上下文管理（创建、恢复、归档） |
| **回合控制** | `TurnHandle` / `AsyncTurnHandle` | 单次交互的细粒度控制（流式、中断、引导） |
| **输入处理** | `TextInput`, `ImageInput`, `LocalImageInput` | 统一多模态输入抽象 |
| **结果收集** | `RunResult` | 聚合最终响应、物品列表、Token 使用量 |
| **重试机制** | `retry_on_overload` | 服务端过载时的指数退避重试 |
| **错误处理** | `AppServerError` 层次结构 | 精细化错误分类与恢复策略 |

### 2.2 TypeScript SDK 功能矩阵

| 功能模块 | 核心类/函数 | 目的 |
|----------|-------------|------|
| **客户端管理** | `Codex` | 封装 CLI 进程调用 |
| **线程操作** | `Thread` | 对话状态管理 |
| **执行控制** | `CodexExec` | 将选项转换为 CLI 参数 |
| **事件流** | `ThreadEvent` 类型 | JSONL 事件解析与类型安全 |
| **配置覆盖** | `CodexConfigObject` | TOML 格式的配置传递 |

### 2.3 关键设计决策

#### 2.3.1 Python SDK: 同步优先，异步通过线程池实现

```python
# AsyncAppServerClient 使用 asyncio.to_thread 包装同步调用
async def _call_sync(self, fn, *args, **kwargs):
    async with self._transport_lock:
        return await asyncio.to_thread(fn, *args, **kwargs)
```

**设计理由**: stdio 传输是单线程的，无法安全地多路复用。异步 API 仅提供非阻塞体验，底层仍是顺序执行。

#### 2.3.2 TypeScript SDK: 基于 `codex exec` 子命令

不同于 Python SDK 直接使用 `app-server`，TypeScript SDK 调用 `codex exec --experimental-json`，通过 JSONL 事件流进行通信。

**设计理由**: 更简单的集成方式，无需维护持久的 app-server 进程。

---

## 具体技术实现

### 3.1 Python SDK 架构详解

#### 3.1.1 进程启动与初始化流程

```
Codex() 构造函数
    ├── AppServerClient.start()
    │   ├── 解析 codex 二进制路径
    │   │   ├── 优先使用 AppServerConfig.codex_bin
    │   │   └── 回退到 codex_cli_bin 包内嵌二进制
    │   ├── subprocess.Popen 启动 app-server --listen stdio://
    │   └── 启动 stderr  drain 线程
    ├── initialize() JSON-RPC 握手
    │   ├── 发送 initialize 请求（客户端信息、能力）
    │   └── 发送 initialized 通知
    └── 验证服务器元数据
```

**关键代码** (`sdk/python/src/codex_app_server/client.py`):

```python
def start(self) -> None:
    codex_bin = _resolve_codex_bin(self.config)
    args = [str(codex_bin), "app-server", "--listen", "stdio://"]
    
    self._proc = subprocess.Popen(
        args,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
    )
    self._start_stderr_drain_thread()
```

#### 3.1.2 JSON-RPC 通信协议

**请求格式**:
```json
{"id": "uuid", "method": "thread/start", "params": {...}}
```

**响应格式**:
```json
{"id": "uuid", "result": {...}}
```

**服务器请求** (需要客户端响应):
```json
{"id": "uuid", "method": "item/commandExecution/requestApproval", "params": {...}}
```

**通知** (无响应):
```json
{"method": "turn/completed", "params": {...}}
```

**关键代码** (`sdk/python/src/codex_app_server/client.py`):

```python
def _request_raw(self, method: str, params: JsonObject | None = None) -> JsonValue:
    request_id = str(uuid.uuid4())
    self._write_message({"id": request_id, "method": method, "params": params or {}})
    
    while True:
        msg = self._read_message()
        
        # 处理服务器发起的请求（如审批）
        if "method" in msg and "id" in msg:
            response = self._handle_server_request(msg)
            self._write_message({"id": msg["id"], "result": response})
            continue
            
        # 缓存通知
        if "method" in msg and "id" not in msg:
            self._pending_notifications.append(...)
            continue
            
        # 匹配响应
        if msg.get("id") == request_id:
            return msg.get("result")
```

#### 3.1.3 Turn 消费者锁机制

由于 stdio 传输的单线程特性，SDK 实现了 turn 级别的互斥锁：

```python
def acquire_turn_consumer(self, turn_id: str) -> None:
    with self._turn_consumer_lock:
        if self._active_turn_consumer is not None:
            raise RuntimeError(
                f"Concurrent turn consumers are not yet supported..."
            )
        self._active_turn_consumer = turn_id
```

**限制**: 一个 `Codex` 实例同时只能有一个活跃的 turn 消费者（`thread.run()`、`TurnHandle.stream()` 或 `TurnHandle.run()`）。

#### 3.1.4 输入处理与序列化

输入类型层次:
```
RunInput = Input | str
Input = list[InputItem] | InputItem
InputItem = TextInput | ImageInput | LocalImageInput | SkillInput | MentionInput
```

**Wire 格式转换** (`sdk/python/src/codex_app_server/_inputs.py`):

```python
def _to_wire_item(item: InputItem) -> JsonObject:
    if isinstance(item, TextInput):
        return {"type": "text", "text": item.text}
    if isinstance(item, LocalImageInput):
        return {"type": "localImage", "path": item.path}
    # ... 其他类型
```

#### 3.1.5 结果收集与聚合

**同步收集** (`sdk/python/src/codex_app_server/_run.py`):

```python
def _collect_run_result(stream: Iterator[Notification], *, turn_id: str) -> RunResult:
    completed: TurnCompletedNotification | None = None
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
    
    _raise_for_failed_turn(completed.turn)
    return RunResult(
        final_response=_final_assistant_response_from_items(items),
        items=items,
        usage=usage,
    )
```

### 3.2 TypeScript SDK 架构详解

#### 3.2.1 进程执行模型

**CodexExec** (`sdk/typescript/src/exec.ts`):

```typescript
async *run(args: CodexExecArgs): AsyncGenerator<string> {
  const commandArgs = ["exec", "--experimental-json"];
  
  // 构建 CLI 参数
  if (args.model) commandArgs.push("--model", args.model);
  if (args.sandboxMode) commandArgs.push("--sandbox", args.sandboxMode);
  // ... 其他选项
  
  const child = spawn(this.executablePath, commandArgs, { env });
  
  // 写入输入
  child.stdin.write(args.input);
  child.stdin.end();
  
  // 读取 JSONL 输出
  const rl = readline.createInterface({ input: child.stdout });
  for await (const line of rl) {
    yield line;
  }
}
```

#### 3.2.2 配置序列化

**TOML 格式转换** (`sdk/typescript/src/exec.ts`):

```typescript
function toTomlValue(value: CodexConfigValue, path: string): string {
  if (typeof value === "string") {
    return JSON.stringify(value);
  } else if (typeof value === "boolean") {
    return value ? "true" : "false";
  } else if (Array.isArray(value)) {
    const rendered = value.map((item, index) => 
      toTomlValue(item, `${path}[${index}]`)
    );
    return `[${rendered.join(", ")}]`;
  } else if (isPlainObject(value)) {
    // 递归处理嵌套对象
    const parts: string[] = [];
    for (const [key, child] of Object.entries(value)) {
      parts.push(`${formatTomlKey(key)} = ${toTomlValue(child, `${path}.${key}`)}`);
    }
    return `{${parts.join(", ")}}`;
  }
}
```

#### 3.2.3 事件类型系统

**ThreadEvent 联合类型** (`sdk/typescript/src/events.ts`):

```typescript
export type ThreadEvent =
  | ThreadStartedEvent
  | TurnStartedEvent
  | TurnCompletedEvent
  | TurnFailedEvent
  | ItemStartedEvent
  | ItemUpdatedEvent
  | ItemCompletedEvent
  | ThreadErrorEvent;
```

**ThreadItem 联合类型** (`sdk/typescript/src/items.ts`):

```typescript
export type ThreadItem =
  | AgentMessageItem
  | ReasoningItem
  | CommandExecutionItem
  | FileChangeItem
  | McpToolCallItem
  | WebSearchItem
  | TodoListItem
  | ErrorItem;
```

### 3.3 代码生成系统

Python SDK 使用 `datamodel-code-generator` 从 JSON Schema 生成 Pydantic 模型：

**生成流程** (`sdk/python/scripts/update_sdk_artifacts.py`):

```
codex-rs/app-server-protocol/schema/json/*.json
    ├── codex_app_server_protocol.v2.schemas.json (bundle)
    ├── 规范化处理 (_annotate_schema)
    │   ├── 展平 oneOf 枚举
    │   ├── 设置 discriminator titles
    │   └── 处理命名冲突
    └── datamodel-code-generator
        ├── --output-model-type pydantic_v2.BaseModel
        ├── --snake-case-field
        ├── --use-title-as-name
        └── src/codex_app_server/generated/v2_all.py
```

**通知注册表自动生成**:

```python
# 从 ServerNotification.json 提取 method -> model 映射
NOTIFICATION_MODELS: dict[str, type[BaseModel]] = {
    "turn/completed": TurnCompletedNotification,
    "item/completed": ItemCompletedNotification,
    "thread/tokenUsage/updated": ThreadTokenUsageUpdatedNotification,
    # ... 其他通知
}
```

---

## 关键代码路径与文件引用

### 4.1 Python SDK 文件结构

```
sdk/python/
├── src/codex_app_server/
│   ├── __init__.py              # 公共 API 导出
│   ├── api.py                   # 高级 API: Codex, Thread, TurnHandle
│   ├── client.py                # 底层 JSON-RPC 客户端
│   ├── async_client.py          # 异步包装器
│   ├── _inputs.py               # 输入类型定义与序列化
│   ├── _run.py                  # 结果收集逻辑
│   ├── errors.py                # 异常层次结构
│   ├── models.py                # 核心数据模型
│   ├── retry.py                 # 重试逻辑
│   └── generated/
│       ├── v2_all.py            # 生成的 Pydantic 模型 (~4000 行)
│       └── notification_registry.py  # 通知类型映射
├── tests/
│   ├── test_client_rpc_methods.py
│   ├── test_public_api_signatures.py
│   └── test_async_client_behavior.py
└── scripts/
    └── update_sdk_artifacts.py  # 代码生成脚本
```

### 4.2 TypeScript SDK 文件结构

```
sdk/typescript/
├── src/
│   ├── index.ts                 # 公共 API 导出
│   ├── codex.ts                 # Codex 类
│   ├── thread.ts                # Thread 类
│   ├── exec.ts                  # CodexExec CLI 调用
│   ├── events.ts                # 事件类型定义
│   ├── items.ts                 # ThreadItem 类型
│   ├── codexOptions.ts          # 配置选项
│   ├── threadOptions.ts         # 线程选项
│   └── turnOptions.ts           # 回合选项
├── tests/
│   ├── run.test.ts
│   ├── runStreamed.test.ts
│   └── exec.test.ts
└── samples/
    ├── basic_streaming.ts
    └── structured_output.ts
```

### 4.3 核心协议定义

```
codex-rs/app-server-protocol/
├── src/protocol/
│   ├── common.rs                # 共享类型（AuthMode, ClientRequest）
│   ├── v1.rs                    # v1 协议定义
│   ├── v2.rs                    # v2 协议定义（Thread/Turn API）
│   └── mappers.rs               # 类型转换
└── schema/json/
    ├── codex_app_server_protocol.v2.schemas.json
    ├── ClientRequest.json
    ├── ServerNotification.json
    └── ...
```

---

## 依赖与外部交互

### 5.1 Python SDK 依赖

**运行时依赖**:
| 包 | 版本 | 用途 |
|----|------|------|
| pydantic | >=2.12 | 数据验证与序列化 |
| codex-cli-bin | 精确版本 | 内嵌 codex 二进制 |

**开发依赖**:
| 包 | 用途 |
|----|------|
| pytest | 测试框架 |
| datamodel-code-generator | 从 JSON Schema 生成 Pydantic 模型 |
| ruff | 代码格式化 |

### 5.2 TypeScript SDK 依赖

**运行时依赖**: 无（纯 SDK，依赖外部 codex CLI）

**开发依赖**:
| 包 | 用途 |
|----|------|
| @modelcontextprotocol/sdk | MCP 类型定义 |
| jest | 测试框架 |
| tsup | 构建工具 |
| typescript | 类型系统 |

### 5.3 外部系统交互

#### 5.3.1 与 codex app-server 的交互

**Python SDK**:
- 通过 `subprocess.Popen` 启动 `codex app-server --listen stdio://`
- 使用 stdin/stdout 进行 JSON-RPC 通信
- stderr 被重定向到内部缓冲区用于调试

**TypeScript SDK**:
- 通过 `spawn` 启动 `codex exec --experimental-json`
- 使用 stdin 发送输入，stdout 接收 JSONL 事件
- 单次执行模式，无持久连接

#### 5.3.2 与 OpenAI API 的交互

SDK 本身不直接与 OpenAI API 通信，所有请求都通过 codex CLI 代理：

```
SDK -> codex app-server -> OpenAI Responses API
```

#### 5.3.3 文件系统交互

| 路径 | 用途 |
|------|------|
| `~/.codex/sessions/` | 线程持久化存储 |
| `~/.codex/config.toml` | 用户配置 |
| `./.codex/config.toml` | 项目配置 |

---

## 风险、边界与改进建议

### 6.1 已知限制与风险

#### 6.1.1 并发限制

**问题**: Python SDK 当前不支持并发 turn 消费。

```python
# 这会抛出 RuntimeError
with Codex() as codex:
    thread1 = codex.thread_start()
    thread2 = codex.thread_start()
    
    # 第二个 run 会失败，因为第一个还在运行
    result1 = thread1.run("...")
    result2 = thread2.run("...")  # RuntimeError!
```

**缓解**: 使用多个 `Codex` 实例，或等待当前 turn 完成。

#### 6.1.2 进程生命周期管理

**问题**: `Codex()` 构造函数是急切的（eager），会立即启动子进程。

```python
# 如果初始化失败，需要手动处理异常
try:
    codex = Codex()
except Exception:
    # 进程可能已启动但未正确关闭
    pass
```

**建议**: 始终使用上下文管理器 `with Codex() as codex:`。

#### 6.1.3 错误传播

**问题**: app-server 崩溃时，错误信息可能仅出现在 stderr，需要通过 `_stderr_tail()` 获取。

```python
def _read_message(self) -> dict[str, JsonValue]:
    line = self._proc.stdout.readline()
    if not line:
        raise TransportClosedError(
            f"app-server closed stdout. stderr_tail={self._stderr_tail()[:2000]}"
        )
```

#### 6.1.4 TypeScript SDK 平台依赖

**问题**: TypeScript SDK 依赖特定平台的 npm 包（`@openai/codex-linux-x64` 等）。

```typescript
// 如果平台包缺失，会抛出错误
function findCodexPath() {
  // ...
  throw new Error(
    `Unable to locate Codex CLI binaries. Ensure ${CODEX_NPM_NAME} is installed with optional dependencies.`
  );
}
```

### 6.2 边界条件

| 边界条件 | 行为 |
|----------|------|
| 空输入字符串 | 正常发送，由服务器处理 |
| 超长输入 | 受 OpenAI API token 限制 |
| 网络中断 | `ServerBusyError` 或 `TransportClosedError` |
| 无效 thread_id | `InvalidParamsError` |
| 沙箱拒绝 | 命令执行 item 标记为 `declined` |
| 上下文窗口溢出 | `CodexErrorInfo.ContextWindowExceeded` |

### 6.3 改进建议

#### 6.3.1 架构层面

1. **支持真正的并发**
   - 实现 per-turn 的事件多路复用
   - 或提供明确的连接池抽象

2. **流式响应优化**
   - 当前 `stream_text()` 仅返回 AgentMessageDelta
   - 建议统一为完整的 Notification 流

3. **TypeScript SDK 持久连接**
   - 考虑支持 `app-server` 模式，减少进程启动开销

#### 6.3.2 API 设计

1. **更灵活的审批处理**
   ```python
   # 当前：简单的回调函数
   approval_handler: Callable[[str, JsonObject | None], JsonObject]
   
   # 建议：支持 async/await 和更丰富的上下文
   class ApprovalHandler(Protocol):
       async def on_command_execution(
           self, command: str, context: ExecutionContext
       ) -> ApprovalDecision: ...
   ```

2. **中间件/拦截器机制**
   ```python
   codex.add_middleware(logging_middleware)
   codex.add_middleware(retry_middleware)
   ```

3. **更丰富的类型提示**
   - 使用 `TypedDict` 提供更精确的 JSON 结构提示
   - 为常见配置选项提供 Literal 类型

#### 6.3.3 可观测性

1. **结构化日志**
   ```python
   # 当前：仅 stderr drain
   # 建议：内置结构化日志支持
   codex = Codex(logger=structlog.get_logger())
   ```

2. **指标收集**
   - Token 使用量统计
   - 请求延迟分布
   - 错误率监控

#### 6.3.4 测试与文档

1. **集成测试增强**
   - 提供 mock app-server 实现
   - 录制/回放测试模式

2. **示例扩展**
   - 多模态输入示例
   - 复杂工作流编排示例
   - 错误处理最佳实践

### 6.4 安全考虑

| 风险 | 缓解措施 |
|------|----------|
| 命令注入 | 所有输入通过 JSON 序列化，无 shell 解释 |
| 路径遍历 | `LocalImageInput` 路径由 app-server 验证 |
| 敏感信息泄露 | stderr 缓冲区大小限制（400 行） |
| 资源耗尽 | 建议配合超时机制使用 |

---

## 附录：版本信息

- **Python SDK 版本**: 0.2.0
- **TypeScript SDK 版本**: 0.0.0-dev
- **目标协议**: Codex app-server JSON-RPC v2
- **最低 Python 版本**: 3.10
- **最低 Node.js 版本**: 18

---

*文档生成时间: 2026-03-22*
*基于代码库 commit: HEAD*
