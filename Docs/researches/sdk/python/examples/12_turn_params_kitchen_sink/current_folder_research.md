# 12_turn_params_kitchen_sink 研究文档

## 1. 场景与职责

### 1.1 目标定位

`12_turn_params_kitchen_sink` 是 Codex Python SDK 示例系列中的**第12个示例**，位于 `sdk/python/examples/12_turn_params_kitchen_sink/` 目录。该示例的核心职责是**展示如何在一次 turn 调用中同时使用所有可用的 turn 级别参数**，即 "kitchen sink"（厨房水槽）式用法——一次性展示所有可配置选项。

### 1.2 业务场景

该示例模拟以下真实业务场景：
- **任务**：让 AI 分析一个安全的特性标志（feature flag）在生产环境启用的 rollout 计划
- **输出要求**：返回符合特定 JSON Schema 的结构化输出（包含 `summary` 和 `actions` 字段）
- **执行策略**：
  - 使用高推理努力度（`model_reasoning_effort: high`）
  - 禁用所有审批（`AskForApproval.never`）
  - 使用务实的个性（`Personality.pragmatic`）
  - 生成简洁的推理摘要（`ReasoningSummary.concise`）

### 1.3 示例在系列中的位置

| 示例编号 | 名称 | 职责 |
|---------|------|------|
| 01 | quickstart_constructor | 基础初始化 |
| 02 | turn_run | 基本 turn 执行 |
| ... | ... | ... |
| 12 | **turn_params_kitchen_sink** | **展示所有 turn 参数的组合使用** |
| 13 | model_select_and_turn_params | 模型选择 + turn 参数 |
| 14 | turn_controls | turn 控制（steer/interrupt） |

---

## 2. 功能点目的

### 2.1 核心功能点

该示例演示以下 turn 级别参数的组合使用：

| 参数 | 类型 | 示例值 | 目的 |
|------|------|--------|------|
| `approval_policy` | `AskForApproval` | `"never"` | 禁用所有操作审批，实现全自动执行 |
| `output_schema` | `JsonObject` | JSON Schema 对象 | 约束 AI 输出为结构化 JSON |
| `personality` | `Personality` | `"pragmatic"` | 设置 AI 个性为务实风格 |
| `summary` | `ReasoningSummary` | `"concise"` | 生成简洁的推理摘要 |
| `model` | `str` | `"gpt-5.4"` | 指定使用的模型 |

### 2.2 结构化输出 (Structured Output)

示例中定义的 `OUTPUT_SCHEMA`：

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

该 Schema 强制 AI 返回包含两个字段的 JSON：
- `summary`: 字符串类型的总结
- `actions`: 字符串数组类型的行动计划

### 2.3 与示例13的区别

- **示例12 (本示例)**：固定使用 `gpt-5.4` 模型，重点展示参数组合
- **示例13**：动态查询可用模型列表，选择最高能力的模型和推理努力度

---

## 3. 具体技术实现

### 3.1 关键流程

#### 3.1.1 同步版本流程 (`sync.py`)

```python
with Codex(config=runtime_config()) as codex:
    # 1. 创建线程，设置模型和推理努力度
    thread = codex.thread_start(
        model="gpt-5.4", 
        config={"model_reasoning_effort": "high"}
    )

    # 2. 创建 turn，传入所有参数
    turn = thread.turn(
        TextInput(PROMPT),
        approval_policy=APPROVAL_POLICY,      # AskForApproval.never
        output_schema=OUTPUT_SCHEMA,          # JSON Schema
        personality=Personality.pragmatic,    # 个性设置
        summary=SUMMARY,                      # ReasoningSummary.concise
    )
    
    # 3. 执行并获取结果
    result = turn.run()
    
    # 4. 读取持久化数据并解析结构化输出
    persisted = thread.read(include_turns=True)
    persisted_turn = find_turn_by_id(persisted.thread.turns, result.id)
    structured_text = assistant_text_from_turn(persisted_turn).strip()
    structured = json.loads(structured_text)
```

#### 3.1.2 异步版本流程 (`async.py`)

与同步版本逻辑相同，使用 `async with` 和 `await`：

```python
async with AsyncCodex(config=runtime_config()) as codex:
    thread = await codex.thread_start(...)
    turn = await thread.turn(...)
    result = await turn.run()
    persisted = await thread.read(include_turns=True)
    # ... 解析逻辑相同
```

### 3.2 数据结构

#### 3.2.1 输入类型定义 (`_inputs.py`)

```python
@dataclass(slots=True)
class TextInput:
    text: str

InputItem = TextInput | ImageInput | LocalImageInput | SkillInput | MentionInput
Input = list[InputItem] | InputItem
```

#### 3.2.2 TurnStartParams 定义 (`generated/v2_all.py`)

```python
class TurnStartParams(BaseModel):
    thread_id: Annotated[str, Field(alias="threadId")]
    input: list[UserInput]
    approval_policy: Annotated[AskForApproval | None, Field(alias="approvalPolicy")] = None
    approvals_reviewer: Annotated[ApprovalsReviewer | None, Field(alias="approvalsReviewer")] = None
    cwd: Annotated[str | None, Field()] = None
    effort: Annotated[ReasoningEffort | None, Field()] = None
    model: Annotated[str | None, Field()] = None
    output_schema: Annotated[Any | None, Field(alias="outputSchema")] = None
    personality: Annotated[Personality | None, Field()] = None
    sandbox_policy: Annotated[SandboxPolicy | None, Field(alias="sandboxPolicy")] = None
    service_tier: Annotated[ServiceTier | None, Field(alias="serviceTier")] = None
    summary: Annotated[ReasoningSummary | None, Field()] = None
```

#### 3.2.3 枚举类型定义

| 枚举 | 值 | 来源 |
|------|-----|------|
| `Personality` | `"none"`, `"friendly"`, `"pragmatic"` | `generated/v2_all.py:1599` |
| `ReasoningSummary` | `"auto"`, `"concise"`, `"detailed"`, `"none"` | `generated/v2_all.py:1866-1872` |
| `AskForApprovalValue` | `"untrusted"`, `"on-failure"`, `"on-request"`, `"never"` | `generated/v2_all.py:167-172` |

### 3.3 协议与序列化

#### 3.3.1 JSON-RPC 请求格式

当调用 `thread.turn()` 时，实际发送的 JSON-RPC 请求：

```json
{
    "id": "uuid",
    "method": "turn/start",
    "params": {
        "threadId": "thread-xxx",
        "input": [{"type": "text", "text": "Analyze a safe rollout plan..."}],
        "approvalPolicy": "never",
        "outputSchema": {
            "type": "object",
            "properties": {
                "summary": {"type": "string"},
                "actions": {"type": "array", "items": {"type": "string"}}
            },
            "required": ["summary", "actions"],
            "additionalProperties": false
        },
        "personality": "pragmatic",
        "summary": "concise"
    }
}
```

#### 3.3.2 参数序列化 (`client.py:_params_dict`)

```python
def _params_dict(params) -> JsonObject:
    if params is None:
        return {}
    if hasattr(params, "model_dump"):
        dumped = params.model_dump(by_alias=True, exclude_none=True, mode="json")
        return dumped
    if isinstance(params, dict):
        return params
    raise TypeError(...)
```

关键转换：
- Python snake_case → JSON camelCase (`by_alias=True`)
- `None` 值被排除 (`exclude_none=True`)
- Pydantic 模型序列化为 JSON 兼容格式 (`mode="json"`)

### 3.4 关键代码路径

#### 3.4.1 Turn 创建到执行的完整调用链

```
Thread.turn() / AsyncThread.turn()
    ↓
_to_wire_input(input)  [api.py]
    ↓
TurnStartParams(...)  [generated/v2_all.py]
    ↓
AppServerClient.turn_start() / AsyncAppServerClient.turn_start()  [client.py / async_client.py]
    ↓
request("turn/start", _params_dict(params), response_model=TurnStartResponse)  [client.py]
    ↓
_write_message({"id": uuid, "method": "turn/start", "params": ...})  [client.py]
    ↓
JSON-RPC over stdio → codex-cli app-server
```

#### 3.4.2 结果收集流程

```
TurnHandle.run() / AsyncTurnHandle.run()
    ↓
self.stream() → Iterator[Notification] / AsyncIterator[Notification]
    ↓
消费通知直到 turn/completed
    ↓
返回 TurnCompletedNotification.turn
```

---

## 4. 关键代码路径与文件引用

### 4.1 示例文件

| 文件 | 行数 | 职责 |
|------|------|------|
| `sdk/python/examples/12_turn_params_kitchen_sink/sync.py` | 78 | 同步版本示例 |
| `sdk/python/examples/12_turn_params_kitchen_sink/async.py` | 88 | 异步版本示例 |

### 4.2 SDK 核心文件

| 文件 | 关键行号 | 职责 |
|------|---------|------|
| `sdk/python/src/codex_app_server/api.py` | 506-538 | `Thread.turn()` 实现 |
| `sdk/python/src/codex_app_server/api.py` | 590-628 | `AsyncThread.turn()` 实现 |
| `sdk/python/src/codex_app_server/client.py` | 352-363 | `AppServerClient.turn_start()` |
| `sdk/python/src/codex_app_server/async_client.py` | 137-143 | `AsyncAppServerClient.turn_start()` |
| `sdk/python/src/codex_app_server/generated/v2_all.py` | 5236-5304 | `TurnStartParams` 模型定义 |
| `sdk/python/src/codex_app_server/_inputs.py` | 8-57 | 输入类型定义和转换 |
| `sdk/python/src/codex_app_server/_run.py` | 59-83 | 结果收集逻辑 |

### 4.3 协议定义 (Rust)

| 文件 | 关键行号 | 职责 |
|------|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | 3828-3879 | Rust 端 `TurnStartParams` 定义 |

### 4.4 工具文件

| 文件 | 职责 |
|------|------|
| `sdk/python/examples/_bootstrap.py` | 示例运行时环境初始化 |
| `sdk/python/scripts/update_sdk_artifacts.py` | 从 Rust 协议生成 Python 模型代码 |

---

## 5. 依赖与外部交互

### 5.1 内部依赖关系

```
12_turn_params_kitchen_sink/
    ├── sync.py / async.py
    │   └── from _bootstrap import ...
    │       └── ensure_local_sdk_src()
    │           └── 将 sdk/python/src 添加到 sys.path
    │   └── from codex_app_server import ...
    │       └── codex_app_server/__init__.py
    │           ├── 从 api.py 导入 Codex, AsyncCodex, Thread, AsyncThread, ...
    │           ├── 从 generated.v2_all 导入 AskForApproval, Personality, ReasoningSummary, ...
    │           └── 从 _inputs 导入 TextInput
    └── 运行时依赖 codex-cli-bin (通过 AppServerConfig 解析)
```

### 5.2 外部依赖

| 依赖 | 用途 |
|------|------|
| `codex-cli-bin` | 实际的 Codex CLI 二进制文件，通过 stdio 提供 app-server 功能 |
| `pydantic` | 数据模型验证和序列化 |
| Python ≥ 3.10 | 类型注解支持 (union types with `|`) |

### 5.3 进程间通信

```
Python SDK (AppServerClient)
    ↓ stdio (stdin/stdout)
codex app-server --listen stdio://
    ↓ HTTP/SSE
OpenAI Responses API
```

### 5.4 代码生成依赖

Python SDK 的 `generated/v2_all.py` 是从 Rust 协议定义自动生成的：

```
Rust Protocol (v2.rs)
    ↓ schemars / ts-rs
JSON Schema / TypeScript 定义
    ↓ datamodel-codegen
Python Pydantic 模型 (v2_all.py)
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 实验性 API 限制

```python
# api.py 注释说明
# TODO: replace this client-wide experimental guard with per-turn event demux.
```

**限制**：当前实现只允许每个客户端实例有一个活跃的 turn consumer（`stream()` 或 `run()`）。尝试启动第二个 consumer 会引发 `RuntimeError`。

#### 6.1.2 并发限制

```python
# async_client.py
async def _call_sync(self, fn, /, *args, **kwargs):
    async with self._transport_lock:  # 全局传输锁
        return await asyncio.to_thread(fn, *args, **kwargs)
```

异步客户端通过线程锁序列化所有调用，因为底层的 stdio 传输不能安全地多线程读取。

#### 6.1.3 结构化输出解析风险

```python
# 示例中的解析逻辑
structured_text = assistant_text_from_turn(persisted_turn).strip()
try:
    structured = json.loads(structured_text)
except json.JSONDecodeError as exc:
    raise RuntimeError(f"Expected JSON matching OUTPUT_SCHEMA, got: {structured_text!r}") from exc
```

如果 AI 未按预期返回有效 JSON，会导致运行时错误。

### 6.2 边界条件

| 边界条件 | 行为 |
|---------|------|
| `output_schema` 为 `None` | 不约束输出格式，AI 自由回复 |
| `approval_policy` 为 `"never"` | 所有操作自动执行，无人工确认 |
| `personality` 为 `"none"` | 使用默认系统个性 |
| `summary` 为 `"none"` | 不生成推理摘要 |
| 空输入 | 由 Pydantic 模型验证处理 |

### 6.3 改进建议

#### 6.3.1 错误处理增强

当前示例在 JSON 解析失败时直接抛出 RuntimeError，建议添加重试逻辑或更优雅的错误恢复：

```python
# 建议改进
for attempt in range(3):
    try:
        structured = json.loads(structured_text)
        break
    except json.JSONDecodeError:
        if attempt == 2:
            raise
        # 可选：重新请求格式化输出
```

#### 6.3.2 Schema 验证

示例仅解析 JSON 但未验证是否符合 Schema，建议添加：

```python
import jsonschema

jsonschema.validate(instance=structured, schema=OUTPUT_SCHEMA)
```

#### 6.3.3 类型安全

`output_schema` 在 `TurnStartParams` 中类型为 `Any | None`，建议更精确的类型定义：

```python
from typing import TypedDict

class OutputSchema(TypedDict):
    type: Literal["object"]
    properties: dict[str, Any]
    required: list[str]
```

#### 6.3.4 文档改进

建议在示例中添加更多注释说明每个参数的用途和可选值范围，特别是：
- `Personality` 各选项的行为差异
- `ReasoningSummary` 对 token 使用的影响
- `AskForApproval` 的安全含义

### 6.4 测试覆盖建议

当前测试主要关注 API 签名（`test_public_api_signatures.py`），建议添加：

1. **集成测试**：验证所有参数组合能正确序列化并传递给后端
2. **错误场景测试**：验证无效 schema 或模型拒绝时的行为
3. **并发测试**：验证多 turn 的排队和锁行为

---

## 附录：关键代码片段

### A.1 TurnStartParams 完整定义 (Python)

```python
# sdk/python/src/codex_app_server/generated/v2_all.py:5236
class TurnStartParams(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    
    approval_policy: Annotated[AskForApproval | None, Field(alias="approvalPolicy")] = None
    approvals_reviewer: Annotated[ApprovalsReviewer | None, Field(alias="approvalsReviewer")] = None
    cwd: Annotated[str | None, Field()] = None
    effort: Annotated[ReasoningEffort | None, Field()] = None
    input: list[UserInput]
    model: Annotated[str | None, Field()] = None
    output_schema: Annotated[Any | None, Field(alias="outputSchema")] = None
    personality: Annotated[Personality | None, Field()] = None
    sandbox_policy: Annotated[SandboxPolicy | None, Field(alias="sandboxPolicy")] = None
    service_tier: Annotated[ServiceTier | None, Field(alias="serviceTier")] = None
    summary: Annotated[ReasoningSummary | None, Field()] = None
    thread_id: Annotated[str, Field(alias="threadId")]
```

### A.2 TurnStartParams 完整定义 (Rust)

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs:3828
#[derive(Serialize, Deserialize, Debug, Default, Clone, PartialEq, JsonSchema, TS, ExperimentalApi)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct TurnStartParams {
    pub thread_id: String,
    pub input: Vec<UserInput>,
    #[ts(optional = nullable)]
    pub cwd: Option<PathBuf>,
    #[experimental(nested)]
    #[ts(optional = nullable)]
    pub approval_policy: Option<AskForApproval>,
    #[ts(optional = nullable)]
    pub approvals_reviewer: Option<ApprovalsReviewer>,
    #[ts(optional = nullable)]
    pub sandbox_policy: Option<SandboxPolicy>,
    #[ts(optional = nullable)]
    pub model: Option<String>,
    #[ts(optional = nullable)]
    pub service_tier: Option<Option<ServiceTier>>,
    #[ts(optional = nullable)]
    pub effort: Option<ReasoningEffort>,
    #[ts(optional = nullable)]
    pub summary: Option<ReasoningSummary>,
    #[ts(optional = nullable)]
    pub personality: Option<Personality>,
    #[ts(optional = nullable)]
    pub output_schema: Option<JsonValue>,
    #[experimental("turn/start.collaborationMode")]
    #[ts(optional = nullable)]
    pub collaboration_mode: Option<CollaborationMode>,
}
```

### A.3 Thread.turn() 实现

```python
# sdk/python/src/codex_app_server/api.py:506-538
def turn(
    self,
    input: Input,
    *,
    approval_policy: AskForApproval | None = None,
    approvals_reviewer: ApprovalsReviewer | None = None,
    cwd: str | None = None,
    effort: ReasoningEffort | None = None,
    model: str | None = None,
    output_schema: JsonObject | None = None,
    personality: Personality | None = None,
    sandbox_policy: SandboxPolicy | None = None,
    service_tier: ServiceTier | None = None,
    summary: ReasoningSummary | None = None,
) -> TurnHandle:
    wire_input = _to_wire_input(input)
    params = TurnStartParams(
        thread_id=self.id,
        input=wire_input,
        approval_policy=approval_policy,
        approvals_reviewer=approvals_reviewer,
        cwd=cwd,
        effort=effort,
        model=model,
        output_schema=output_schema,
        personality=personality,
        sandbox_policy=sandbox_policy,
        service_tier=service_tier,
        summary=summary,
    )
    turn = self._client.turn_start(self.id, wire_input, params=params)
    return TurnHandle(self._client, self.id, turn.turn.id)
```

---

*文档生成时间：2026-03-22*
*基于代码版本：sdk/python @ 当前工作目录*
