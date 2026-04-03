# 研究文档：sdk/python/examples/13_model_select_and_turn_params

## 1. 场景与职责

### 1.1 目标与定位

本示例（`13_model_select_and_turn_params`）是 Codex Python SDK 的高级使用示例，展示了如何：

1. **动态模型选择**：从可用模型列表中智能选择最适合的模型
2. **推理力度（Reasoning Effort）选择**：根据模型支持的推理力度选项选择最高级别
3. **Turn 级别参数覆盖**：在单个 Turn 调用中覆盖线程级别的配置参数

### 1.2 与相邻示例的关系

| 示例 | 职责 | 关系 |
|------|------|------|
| `04_models_and_metadata` | 基础模型列表查询 | 本示例依赖其模型查询能力并扩展了选择逻辑 |
| `12_turn_params_kitchen_sink` | 展示 Turn 参数的基本使用 | 本示例在此基础上增加了动态模型选择 |
| `13_model_select_and_turn_params` | **动态模型选择 + Turn 参数** | 当前研究对象，展示生产环境中的高级用法 |

### 1.3 使用场景

- **生产环境部署**：需要根据不同任务动态选择模型能力
- **多模型策略**：根据模型可用性和升级路径自动选择最优模型
- **精细化控制**：在单次对话轮次中临时覆盖全局配置

---

## 2. 功能点目的

### 2.1 核心功能拆解

```
┌─────────────────────────────────────────────────────────────────┐
│                    示例 13 功能架构                               │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐      │
│  │ 模型发现     │ -> │ 智能选择     │ -> │ Turn 执行    │      │
│  │ model/list   │    │ _pick_*      │    │ turn/start   │      │
│  └──────────────┘    └──────────────┘    └──────────────┘      │
│         │                   │                   │              │
│         ▼                   ▼                   ▼              │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐      │
│  │ include_hidden│   │ PREFERRED    │    │ 参数覆盖      │      │
│  │ 查询隐藏模型  │    │ MODEL 优先级  │    │ model/effort │      │
│  │              │    │ reasoning    │    │ personality  │      │
│  │              │    │ _effort 排序  │    │ sandbox      │      │
│  └──────────────┘    └──────────────┘    └──────────────┘      │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 关键功能点

#### 2.2.1 模型选择策略（`_pick_highest_model`）

**目的**：从可用模型中选择最优模型

**策略逻辑**：
1. 优先选择非隐藏模型（`hidden=False`）
2. 优先匹配 `PREFERRED_MODEL = "gpt-5.4"`
3. 排除已有升级版本的模型（避免选择即将被替换的模型）
4. 按 `(model, id)` 字典序选择最高版本

#### 2.2.2 推理力度选择（`_pick_highest_turn_effort`）

**目的**：为选定模型选择最高可用的推理力度

**排序逻辑**：
```python
REASONING_RANK = {
    "none": 0,
    "minimal": 1,
    "low": 2,
    "medium": 3,
    "high": 4,
    "xhigh": 5,
}
```

#### 2.2.3 Turn 级别参数覆盖

**目的**：在单次对话中精细控制模型行为

**可覆盖参数**：
- `model`: 覆盖线程级模型选择
- `effort`: 覆盖推理力度
- `personality`: 设置个性风格（pragmatic/friendly/none）
- `output_schema`: 强制输出符合 JSON Schema
- `sandbox_policy`: 临时调整沙箱策略
- `approval_policy`: 临时调整审批策略
- `summary`: 控制推理摘要级别

---

## 3. 具体技术实现

### 3.1 关键流程

#### 3.1.1 异步版本执行流程（`async.py`）

```python
async def main() -> None:
    # 1. 初始化 AsyncCodex 客户端
    async with AsyncCodex(config=runtime_config()) as codex:
        
        # 2. 获取模型列表（包含隐藏模型）
        models = await codex.models(include_hidden=True)
        
        # 3. 选择最优模型和推理力度
        selected_model = _pick_highest_model(models.data)
        selected_effort = _pick_highest_turn_effort(selected_model)
        
        # 4. 创建线程，传入模型和推理力度配置
        thread = await codex.thread_start(
            model=selected_model.model,
            config={"model_reasoning_effort": selected_effort.value},
        )
        
        # 5. 第一个 Turn：基础对话
        first_turn = await thread.turn(
            TextInput("Give one short sentence about reliable production releases."),
            model=selected_model.model,
            effort=selected_effort,
        )
        first = await first_turn.run()
        
        # 6. 第二个 Turn：完整参数覆盖
        second_turn = await thread.turn(
            TextInput("Return JSON for a safe feature-flag rollout plan."),
            approval_policy=APPROVAL_POLICY,      # "never"
            cwd=str(Path.cwd()),                   # 工作目录
            effort=selected_effort,                # 推理力度
            model=selected_model.model,            # 模型
            output_schema=OUTPUT_SCHEMA,           # JSON Schema 约束
            personality=Personality.pragmatic,     # 务实风格
            sandbox_policy=SANDBOX_POLICY,         # 只读沙箱
            summary=ReasoningSummary.model_validate("concise"),  # 简洁摘要
        )
        second = await second_turn.run()
```

#### 3.1.2 同步版本执行流程（`sync.py`）

同步版本与异步版本逻辑完全一致，仅使用同步 API：

```python
with Codex(config=runtime_config()) as codex:
    models = codex.models(include_hidden=True)
    # ... 相同的选择和执行逻辑
```

### 3.2 数据结构

#### 3.2.1 模型相关数据结构

**Model 结构**（来自 `v2_all.py`）:
```python
class Model(BaseModel):
    availability_nux: ModelAvailabilityNux | None  # 可用性提示
    default_reasoning_effort: ReasoningEffort      # 默认推理力度
    description: str                               # 模型描述
    display_name: str                              # 显示名称
    hidden: bool                                   # 是否隐藏
    id: str                                        # 模型 ID
    input_modalities: list[InputModality]          # 输入模态
    is_default: bool                               # 是否默认
    model: str                                     # 模型名称
    supported_reasoning_efforts: list[ReasoningEffortOption]  # 支持的推理力度
    supports_personality: bool | None              # 是否支持个性
    upgrade: str | None                            # 升级目标模型
    upgrade_info: ModelUpgradeInfo | None          # 升级信息
```

**ReasoningEffort 枚举**:
```python
class ReasoningEffort(Enum):
    none = "none"
    minimal = "minimal"
    low = "low"
    medium = "medium"
    high = "high"
    xhigh = "xhigh"
```

**ReasoningEffortOption 结构**:
```python
class ReasoningEffortOption(BaseModel):
    description: str
    reasoning_effort: ReasoningEffort
```

#### 3.2.2 Turn 参数数据结构

**TurnStartParams**（来自 `v2_all.py`，行 5236-5304）:
```python
class TurnStartParams(BaseModel):
    approval_policy: AskForApproval | None          # 审批策略
    approvals_reviewer: ApprovalsReviewer | None    # 审批审核者
    cwd: str | None                                 # 工作目录
    effort: ReasoningEffort | None                  # 推理力度
    input: list[UserInput]                          # 输入内容（必需）
    model: str | None                               # 模型覆盖
    output_schema: Any | None                       # 输出 Schema
    personality: Personality | None                 # 个性风格
    sandbox_policy: SandboxPolicy | None            # 沙箱策略
    service_tier: ServiceTier | None                # 服务层级
    summary: ReasoningSummary | None                # 推理摘要
    thread_id: str                                  # 线程 ID（必需）
```

#### 3.2.3 输出 Schema 定义

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

#### 3.2.4 沙箱策略定义

```python
SANDBOX_POLICY = SandboxPolicy.model_validate(
    {
        "type": "readOnly",
        "access": {"type": "fullAccess"},
    }
)
```

### 3.3 协议与通信

#### 3.3.1 JSON-RPC 方法调用

**模型列表查询**:
```json
{
    "id": "<uuid>",
    "method": "model/list",
    "params": {
        "includeHidden": true
    }
}
```

**线程创建**:
```json
{
    "id": "<uuid>",
    "method": "thread/start",
    "params": {
        "model": "gpt-5.4",
        "config": {
            "model_reasoning_effort": "high"
        }
    }
}
```

**Turn 启动**:
```json
{
    "id": "<uuid>",
    "method": "turn/start",
    "params": {
        "threadId": "<thread-id>",
        "input": [{"type": "text", "text": "..."}],
        "model": "gpt-5.4",
        "effort": "high",
        "personality": "pragmatic",
        "outputSchema": {...},
        "approvalPolicy": "never",
        "sandboxPolicy": {"type": "readOnly", "access": {"type": "fullAccess"}},
        "summary": "concise"
    }
}
```

#### 3.3.2 通知处理

示例中通过 `turn.run()` 内部处理以下通知：
- `turn/started`: Turn 开始
- `item/started`: 项目开始
- `item/completed`: 项目完成
- `turn/completed`: Turn 完成（携带完整 Turn 数据）
- `error`: 错误通知

---

## 4. 关键代码路径与文件引用

### 4.1 示例文件

| 文件 | 路径 | 职责 |
|------|------|------|
| `async.py` | `sdk/python/examples/13_model_select_and_turn_params/async.py` | 异步版本示例 |
| `sync.py` | `sdk/python/examples/13_model_select_and_turn_params/sync.py` | 同步版本示例 |

### 4.2 SDK 核心文件

| 文件 | 路径 | 职责 |
|------|------|------|
| `api.py` | `sdk/python/src/codex_app_server/api.py` | 高级 API（Codex/AsyncCodex, Thread/AsyncThread） |
| `client.py` | `sdk/python/src/codex_app_server/client.py` | 同步 JSON-RPC 客户端（AppServerClient） |
| `async_client.py` | `sdk/python/src/codex_app_server/async_client.py` | 异步包装器（AsyncAppServerClient） |
| `v2_all.py` | `sdk/python/src/codex_app_server/generated/v2_all.py` | 自动生成的 Pydantic 模型 |
| `_inputs.py` | `sdk/python/src/codex_app_server/_inputs.py` | 输入类型定义（TextInput 等） |
| `_run.py` | `sdk/python/src/codex_app_server/_run.py` | Turn 结果收集逻辑 |
| `_bootstrap.py` | `sdk/python/examples/_bootstrap.py` | 示例通用工具函数 |

### 4.3 关键代码引用

#### 4.3.1 模型选择算法

**文件**: `sdk/python/examples/13_model_select_and_turn_params/async.py` (行 35-43)

```python
def _pick_highest_model(models):
    visible = [m for m in models if not m.hidden] or models
    preferred = next((m for m in visible if m.model == PREFERRED_MODEL or m.id == PREFERRED_MODEL), None)
    if preferred is not None:
        return preferred
    known_names = {m.id for m in visible} | {m.model for m in visible}
    top_candidates = [m for m in visible if not (m.upgrade and m.upgrade in known_names)]
    pool = top_candidates or visible
    return max(pool, key=lambda m: (m.model, m.id))
```

#### 4.3.2 推理力度选择

**文件**: `sdk/python/examples/13_model_select_and_turn_params/async.py` (行 46-54)

```python
def _pick_highest_turn_effort(model) -> ReasoningEffort:
    if not model.supported_reasoning_efforts:
        return ReasoningEffort.medium

    best = max(
        model.supported_reasoning_efforts,
        key=lambda option: REASONING_RANK.get(option.reasoning_effort.value, -1),
    )
    return ReasoningEffort(best.reasoning_effort.value)
```

#### 4.3.3 Thread.turn 方法

**文件**: `sdk/python/src/codex_app_server/api.py` (行 507-538)

```python
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
        # ... 其他参数
    )
    turn = self._client.turn_start(self.id, wire_input, params=params)
    return TurnHandle(self._client, self.id, turn.turn.id)
```

#### 4.3.4 Turn 执行与结果收集

**文件**: `sdk/python/src/codex_app_server/api.py` (行 671-684)

```python
def run(self) -> AppServerTurn:
    completed: TurnCompletedNotification | None = None
    stream = self.stream()
    try:
        for event in stream:
            payload = event.payload
            if isinstance(payload, TurnCompletedNotification) and payload.turn.id == self.id:
                completed = payload
    finally:
        stream.close()

    if completed is None:
        raise RuntimeError("turn completed event not received")
    return completed.turn
```

---

## 5. 依赖与外部交互

### 5.1 内部依赖

```
13_model_select_and_turn_params/
    ├── async.py / sync.py
    │       ├── _bootstrap.py ........................... 示例工具
    │       │       └── _runtime_setup.py ............... 运行时设置
    │       └── codex_app_server (package)
    │               ├── __init__.py ..................... 公共 API 导出
    │               ├── api.py .......................... Codex/Thread/TurnHandle
    │               ├── client.py ....................... AppServerClient
    │               ├── async_client.py ................. AsyncAppServerClient
    │               ├── models.py ....................... 基础模型
    │               ├── _inputs.py ...................... 输入类型
    │               ├── _run.py ......................... 结果收集
    │               ├── generated/
    │               │       └── v2_all.py ............... 生成的 Pydantic 模型
    │               └── errors.py ....................... 异常定义
    └── sync.py (与 async.py 结构相同，使用同步 API)
```

### 5.2 外部依赖

| 依赖 | 用途 |
|------|------|
| `pydantic` | 数据验证和序列化 |
| `codex-cli-bin` | 底层 Codex 二进制运行时 |

### 5.3 运行时交互

```
┌─────────────────┐     JSON-RPC (stdio)     ┌─────────────────┐
│   Python SDK    │  <-------------------->  │  codex-cli-bin  │
│   (本示例)       │                         │  (app-server)   │
└─────────────────┘                         └─────────────────┘
       │                                             │
       │  1. model/list                              │
       │  2. thread/start                            │
       │  3. turn/start                              │
       │  4. turn/run (streaming notifications)      │
       │                                             │
       ▼                                             ▼
┌─────────────────┐                         ┌─────────────────┐
│  模型选择逻辑    │                         │  OpenAI API     │
│  参数组装       │                         │  (Responses API)│
└─────────────────┘                         └─────────────────┘
```

---

## 6. 风险、边界与改进建议

### 6.1 当前风险

#### 6.1.1 硬编码偏好模型

**风险**：`PREFERRED_MODEL = "gpt-5.4"` 是硬编码的，如果该模型不可用或名称变更，选择逻辑会降级到字典序选择。

**影响**：可能选择到非最优模型。

**建议**：
```python
# 改进：从环境变量或配置文件读取
PREFERRED_MODEL = os.getenv("CODEX_PREFERRED_MODEL", "gpt-5.4")
```

#### 6.1.2 模型升级路径处理

**风险**：`_pick_highest_model` 排除了有 `upgrade` 字段的模型，但如果所有可见模型都有升级路径，逻辑可能选择到即将废弃的模型。

**代码位置**：行 39
```python
top_candidates = [m for m in visible if not (m.upgrade and m.upgrade in known_names)]
```

**建议**：添加降级策略日志，当所有模型都被排除时发出警告。

#### 6.1.3 推理力度回退

**风险**：当模型不支持任何推理力度时，默认返回 `ReasoningEffort.medium`，这可能不适用于所有场景。

**代码位置**：行 47-48
```python
if not model.supported_reasoning_efforts:
    return ReasoningEffort.medium
```

**建议**：根据任务类型动态选择默认力度。

### 6.2 边界情况

#### 6.2.1 空模型列表

**边界**：如果 `codex.models()` 返回空列表，`_pick_highest_model` 会抛出 `ValueError`（`max()` 参数为空）。

**建议**：添加空列表检查：
```python
def _pick_highest_model(models):
    if not models:
        raise ValueError("No models available")
    # ... 原逻辑
```

#### 6.2.2 Turn 参数冲突

**边界**：线程级配置和 Turn 级配置可能产生冲突。当前实现中 Turn 级参数会覆盖线程级参数，但某些参数（如 `sandbox_policy`）的覆盖可能导致意外行为。

**建议**：在文档中明确参数覆盖优先级。

### 6.3 改进建议

#### 6.3.1 模型选择策略可配置化

```python
@dataclass
class ModelSelectionStrategy:
    preferred_models: list[str]  # 优先级排序的模型列表
    exclude_hidden: bool = True
    exclude_upgradable: bool = True
    fallback_to_any: bool = True

def _pick_model(models: list[Model], strategy: ModelSelectionStrategy) -> Model:
    # 可配置的模型选择逻辑
    ...
```

#### 6.3.2 添加模型能力匹配

```python
def _pick_model_for_task(models: list[Model], task_requirements: TaskRequirements) -> Model:
    """根据任务需求选择模型（如需要图像输入、需要特定推理能力等）"""
    candidates = [
        m for m in models
        if all(req in m.capabilities for req in task_requirements.required_capabilities)
    ]
    return _pick_highest_model(candidates)
```

#### 6.3.3 参数验证增强

```python
def turn_with_validation(
    self,
    input: Input,
    *,
    output_schema: JsonObject | None = None,
    **kwargs
) -> TurnHandle:
    """带参数验证的 Turn 创建"""
    if output_schema:
        validate_schema(output_schema)  # 提前验证 Schema 有效性
    
    if kwargs.get("effort") and not self._supports_effort(kwargs["model"]):
        logger.warning(f"Model {kwargs['model']} may not support effort {kwargs['effort']}")
    
    return self.turn(input, output_schema=output_schema, **kwargs)
```

#### 6.3.4 可观测性增强

```python
# 添加结构化日志记录
logger.info(
    "model_selected",
    extra={
        "model_id": selected_model.id,
        "model_name": selected_model.model,
        "reasoning_effort": selected_effort.value,
        "selection_reason": "preferred_model_matched"  # 或 "fallback_to_highest_version"
    }
)
```

### 6.4 测试建议

1. **模型选择单元测试**：
   - 测试偏好模型匹配成功场景
   - 测试偏好模型不可用时的降级逻辑
   - 测试所有模型都有 upgrade 路径的边界情况

2. **参数覆盖集成测试**：
   - 验证 Turn 级参数确实覆盖线程级参数
   - 测试无效参数组合的错误处理

3. **端到端测试**：
   - 使用 mock app-server 验证完整流程
   - 验证输出 Schema 约束是否生效

---

## 7. 总结

本示例展示了 Codex Python SDK 在生产环境中的高级用法，核心贡献在于：

1. **动态模型选择策略**：提供了可复用的模型选择算法，考虑了隐藏状态、升级路径和版本排序
2. **推理力度自动匹配**：根据模型能力自动选择最高可用推理级别
3. **Turn 级精细控制**：展示了如何在单次对话中覆盖全局配置，实现灵活的行为控制

该示例适合作为构建智能模型路由系统的基础模板，但需要注意硬编码偏好和边界情况处理。
