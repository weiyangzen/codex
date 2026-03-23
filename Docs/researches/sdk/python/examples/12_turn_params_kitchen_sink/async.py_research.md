# async.py 研究文档

## 场景与职责

`async.py` 是 Codex Python SDK 的示例程序，展示了如何使用 **异步 API** 调用 Codex App Server 的完整 Turn 参数功能。该示例位于 `sdk/python/examples/12_turn_params_kitchen_sink/` 目录，"kitchen_sink" 命名暗示这是一个展示所有可用参数的综合性示例。

**核心职责**：
- 演示异步上下文管理器 (`async with`) 模式使用 `AsyncCodex` 客户端
- 展示如何在单次 Turn 调用中配置所有高级参数（approval_policy、output_schema、personality、summary 等）
- 演示结构化输出（Structured Output）功能，通过 JSON Schema 约束模型响应格式
- 展示如何解析和处理 Turn 执行结果

## 功能点目的

### 1. 结构化输出 (Structured Output)
```python
OUTPUT_SCHEMA = {
    "type": "object",
    "properties": {
        "summary": {"type": "string"},
        "actions": {
            "type": "array",
            "items": {"type": "string"},
        },
    },
    "required": ["summary", "actions"],
    "additionalProperties": False,
}
```
- **目的**：强制模型输出符合指定 JSON Schema 的结构化数据
- **应用场景**：需要机器可解析的输出，如生成待办事项列表、配置项、API 参数等
- **约束**：`additionalProperties: False` 确保模型不会返回未定义字段

### 2. 审批策略 (Approval Policy)
```python
APPROVAL_POLICY = AskForApproval.model_validate("never")
```
- **目的**：控制命令执行和文件变更的自动审批行为
- **取值**：`"never"` 表示完全自动执行，无需用户确认
- **其他可选值**：`"untrusted"`、`"on-failure"`、`"on-request"`、或细粒度的 `Granular` 配置

### 3. 推理摘要 (Reasoning Summary)
```python
SUMMARY = ReasoningSummary.model_validate("concise")
```
- **目的**：请求模型提供推理过程的摘要
- **取值**：`"concise"` 表示简洁摘要，其他可选 `"auto"`、`"detailed"`、`"none"`
- **参考**：OpenAI 推理摘要文档 https://platform.openai.com/docs/guides/reasoning

### 4. 人格设定 (Personality)
```python
personality=Personality.pragmatic
```
- **目的**：调整模型的响应风格和语气
- **取值**：`pragmatic`（务实）、`friendly`（友好）、`none`（无特定风格）

### 5. 模型配置
```python
model="gpt-5.4", config={"model_reasoning_effort": "high"}
```
- **目的**：指定模型版本和推理努力程度
- **config 参数**：传递给底层模型的额外配置，如 `model_reasoning_effort`

## 具体技术实现

### 关键流程

#### 1. 初始化流程
```python
async def main() -> None:
    async with AsyncCodex(config=runtime_config()) as codex:
        # 1. 创建 Thread
        thread = await codex.thread_start(
            model="gpt-5.4", 
            config={"model_reasoning_effort": "high"}
        )
        # ...
```

**详细流程**：
1. `runtime_config()` 从 `_bootstrap` 获取示例友好的配置
2. `AsyncCodex.__aenter__()` 触发初始化：
   - 调用 `_ensure_initialized()` 
   - 使用 `asyncio.Lock` 确保线程安全
   - 启动底层 `AsyncAppServerClient`
   - 发送 `initialize` JSON-RPC 请求验证服务器元数据

#### 2. Turn 执行流程
```python
turn = await thread.turn(
    TextInput(PROMPT),
    approval_policy=APPROVAL_POLICY,
    output_schema=OUTPUT_SCHEMA,
    personality=Personality.pragmatic,
    summary=SUMMARY,
)
result = await turn.run()
```

**详细流程**：
1. `TextInput` 被转换为 wire 格式：`{"type": "text", "text": "..."}`
2. 构建 `TurnStartParams` 参数对象（参见 `v2_all.py` 第 5236 行）
3. 调用 `turn_start` JSON-RPC 方法创建 Turn
4. `turn.run()` 启动事件流消费：
   - 调用 `stream()` 获取通知迭代器
   - 持续消费通知直到收到 `turn/completed` 事件
   - 返回 `AppServerTurn` 对象

#### 3. 结果解析流程
```python
persisted = await thread.read(include_turns=True)
persisted_turn = find_turn_by_id(persisted.thread.turns, result.id)
structured_text = assistant_text_from_turn(persisted_turn).strip()
structured = json.loads(structured_text)
```

**详细流程**：
1. `thread.read()` 获取 Thread 完整状态（包含所有 Turns）
2. `find_turn_by_id()` 从 `_bootstrap.py` 导入，按 ID 查找特定 Turn
3. `assistant_text_from_turn()` 提取助手消息文本：
   - 遍历 Turn 的 `items` 列表
   - 识别 `agentMessage` 类型或 `message` 类型且 `role="assistant"` 的项
   - 提取 `output_text` 类型的内容
4. JSON 解析和验证结构化输出

### 数据结构

#### TurnStartParams（生成的 Pydantic 模型）
```python
class TurnStartParams(BaseModel):
    approval_policy: AskForApproval | None      # 审批策略
    approvals_reviewer: ApprovalsReviewer | None # 审批路由目标
    cwd: str | None                             # 工作目录覆盖
    effort: ReasoningEffort | None              # 推理努力程度
    input: list[UserInput]                      # 用户输入（必需）
    model: str | None                           # 模型覆盖
    output_schema: Any | None                   # JSON Schema 约束
    personality: Personality | None             # 人格设定
    sandbox_policy: SandboxPolicy | None        # 沙箱策略
    service_tier: ServiceTier | None            # 服务层级
    summary: ReasoningSummary | None            # 推理摘要设置
```

#### AskForApproval（联合类型）
```python
class AskForApproval(RootModel[AskForApprovalValue | GranularAskForApproval]):
    root: AskForApprovalValue | GranularAskForApproval

class AskForApprovalValue(Enum):
    untrusted = "untrusted"
    on_failure = "on-failure"
    on_request = "on-request"
    never = "never"

class GranularAskForApproval(BaseModel):
    granular: Granular  # 细粒度控制各场景审批行为
```

### 协议交互

#### JSON-RPC 方法调用
| 方法 | 用途 | 参数 |
|------|------|------|
| `initialize` | 客户端初始化握手 | `clientInfo`, `capabilities` |
| `thread/start` | 创建新 Thread | `ThreadStartParams` |
| `turn/start` | 启动 Turn | `TurnStartParams` |
| `thread/read` | 读取 Thread 状态 | `threadId`, `includeTurns` |

#### 通知事件处理
```python
# TurnHandle.stream() 内部实现
while True:
    event = await self._codex._client.next_notification()
    yield event
    if (event.method == "turn/completed" 
        and event.payload.turn.id == self.id):
        break
```

## 关键代码路径与文件引用

### 调用链
```
async.py
  └─ AsyncCodex (api.py:270)
       └─ AsyncAppServerClient (async_client.py:39)
            └─ AppServerClient (client.py:136) [通过 asyncio.to_thread 包装]
  
async.py:thread.turn()
  └─ AsyncThread.turn() (api.py:591)
       └─ AsyncAppServerClient.turn_start() (async_client.py:137)
            └─ AppServerClient.turn_start() (client.py:352)
                 └─ JSON-RPC "turn/start" 请求

async.py:turn.run()
  └─ AsyncTurnHandle.run() (api.py:722)
       └─ AsyncTurnHandle.stream() (api.py:705)
            └─ 消费通知直到 turn/completed
```

### 关键文件引用
| 文件 | 作用 |
|------|------|
| `sdk/python/examples/_bootstrap.py` | 示例基础设施，提供 `runtime_config`、`find_turn_by_id`、`assistant_text_from_turn` |
| `sdk/python/src/codex_app_server/api.py` | 高级 API 实现：`AsyncCodex`、`AsyncThread`、`AsyncTurnHandle` |
| `sdk/python/src/codex_app_server/async_client.py` | 异步客户端包装器，基于线程池 |
| `sdk/python/src/codex_app_server/client.py` | 同步 JSON-RPC 客户端核心实现 |
| `sdk/python/src/codex_app_server/_inputs.py` | 输入类型定义：`TextInput`、`ImageInput` 等 |
| `sdk/python/src/codex_app_server/generated/v2_all.py` | 生成的 Pydantic 模型，包含 `TurnStartParams`、`AskForApproval` 等 |

## 依赖与外部交互

### 内部依赖
```python
# 来自 _bootstrap.py
from _bootstrap import (
    assistant_text_from_turn,    # 提取助手响应文本
    ensure_local_sdk_src,        # 确保 SDK 源码在路径中
    find_turn_by_id,             # 按 ID 查找 Turn
    runtime_config,              # 获取示例配置
)

# 来自 codex_app_server
from codex_app_server import (
    AskForApproval,      # 审批策略类型
    AsyncCodex,          # 异步客户端主类
    Personality,         # 人格枚举
    ReasoningSummary,    # 推理摘要类型
    TextInput,           # 文本输入包装
)
```

### 外部进程交互
- **Codex CLI Binary**: 通过 `codex app-server --listen stdio://` 启动子进程
- **通信方式**: STDIN/STDOUT JSON-RPC 2.0 协议
- **配置来源**: `AppServerConfig`（可通过环境变量或代码配置）

### 模型服务交互
- **模型**: OpenAI GPT-5.4（示例中硬编码）
- **功能**: 结构化输出、推理摘要、人格设定
- **配置**: `model_reasoning_effort: "high"` 传递给模型提供者

## 风险、边界与改进建议

### 风险点

1. **并发限制**
   ```python
   # client.py:288-296
   if self._active_turn_consumer is not None:
       raise RuntimeError("Concurrent turn consumers are not yet supported...")
   ```
   - 当前实现不支持同时消费多个 Turn 的事件流
   - 尝试并发启动多个 Turn 会抛出 RuntimeError

2. **JSON Schema 验证**
   - 示例中仅对模型输出进行客户端 JSON 解析验证
   - 如果模型返回不符合 Schema 的内容，会抛出 `json.JSONDecodeError`
   - 建议：添加更健壮的 Schema 验证（如使用 `jsonschema` 库）

3. **硬编码模型版本**
   ```python
   model="gpt-5.4"  # 可能在未来版本中失效
   ```

### 边界条件

1. **空 Turn 结果处理**
   ```python
   print("Items:", 0 if persisted_turn is None else len(persisted_turn.items or []))
   ```
   - 代码已处理 `persisted_turn` 为 None 的情况

2. **结构化输出字段验证**
   ```python
   if not isinstance(summary, str) or not isinstance(actions, list) or not all(
       isinstance(action, str) for action in actions
   ):
       raise RuntimeError(...)
   ```
   - 对模型输出的字段类型进行严格验证

### 改进建议

1. **错误处理增强**
   ```python
   # 当前
   except json.JSONDecodeError as exc:
       raise RuntimeError(f"Expected JSON matching OUTPUT_SCHEMA, got: {structured_text!r}") from exc
   
   # 建议：添加重试逻辑或降级策略
   ```

2. **配置外部化**
   - 将 `OUTPUT_SCHEMA`、`PROMPT`、`model` 等提取为命令行参数或环境变量
   - 便于不同场景复用

3. **类型安全**
   - 为结构化输出定义 TypedDict 或 Pydantic 模型
   ```python
   from typing import TypedDict
   
   class RolloutPlan(TypedDict):
       summary: str
       actions: list[str]
   ```

4. **资源清理保障**
   - 当前使用 `async with` 模式，已确保资源清理
   - 建议添加超时控制防止 Turn 执行无限等待

5. **日志记录**
   - 示例中仅使用 `print` 输出结果
   - 建议添加结构化日志记录中间状态和调试信息
