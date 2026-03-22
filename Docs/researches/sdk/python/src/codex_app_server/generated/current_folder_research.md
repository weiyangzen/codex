# Codex Python SDK - `generated` 目录研究文档

## 目录

1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 1.1 定位与上下文

`sdk/python/src/codex_app_server/generated/` 目录是 **Codex Python SDK** 的核心协议层，负责将 Rust 后端（`codex-rs/app-server-protocol`）定义的 JSON Schema 协议自动转换为 Python 类型定义。该目录位于以下架构层级：

```
┌─────────────────────────────────────────────────────────────┐
│                    应用层 (User Code)                        │
│              使用 Codex / AsyncCodex 高级 API                │
├─────────────────────────────────────────────────────────────┤
│              api.py - 高级封装 (Thread/TurnHandle)           │
├─────────────────────────────────────────────────────────────┤
│        client.py / async_client.py - JSON-RPC 客户端        │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────┐   │
│  │   generated/  <- 本目录：协议类型定义 (Pydantic)     │   │
│  │   - v2_all.py          - 完整协议类型 (6000+ 行)    │   │
│  │   - notification_registry.py - 通知类型注册表       │   │
│  └─────────────────────────────────────────────────────┘   │
├─────────────────────────────────────────────────────────────┤
│           models.py - SDK 内部数据模型                      │
├─────────────────────────────────────────────────────────────┤
│     codex-rs/app-server-protocol - Rust 协议定义 (源)       │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 核心职责

| 职责 | 说明 |
|------|------|
| **协议类型映射** | 将 Rust/JSON Schema 协议转换为 Python Pydantic 模型 |
| **类型安全** | 提供完整的类型提示，支持静态类型检查 (mypy/pyright) |
| **序列化/反序列化** | 通过 Pydantic 自动处理 JSON-RPC 消息的编解码 |
| **通知分发** | 建立通知方法名到具体类型的映射，支持运行时类型解析 |
| **版本同步** | 与 Rust 后端协议版本保持同步，通过代码生成确保一致性 |

### 1.3 使用场景

1. **SDK 内部使用**: `client.py` 使用生成的类型构建 JSON-RPC 请求和解析响应
2. **用户类型提示**: 用户代码可以使用这些类型进行类型注解
3. **通知处理**: 运行时根据通知方法名查找对应的 Pydantic 模型进行反序列化

---

## 功能点目的

### 2.1 v2_all.py - 完整协议类型定义

**文件规模**: 6351 行，包含约 400+ 个类定义

**核心功能**:

| 类别 | 示例类型 | 用途 |
|------|----------|------|
| **请求参数** | `ThreadStartParams`, `TurnStartParams` | 封装 API 请求参数 |
| **响应结果** | `ThreadStartResponse`, `TurnStartResponse` | 封装 API 响应数据 |
| **通知载荷** | `TurnCompletedNotification`, `AgentMessageDeltaNotification` | 服务器推送消息 |
| **枚举类型** | `TurnStatus`, `SandboxMode`, `ReasoningEffort` | 有限取值集合 |
| **联合类型** | `ThreadItem`, `UserInput`, `SandboxPolicy` | 多态数据结构 |
| **请求包装** | `ThreadStartRequest`, `ClientRequest` | JSON-RPC 请求封装 |
| **通知包装** | `TurnCompletedServerNotification`, `ServerNotification` | JSON-RPC 通知封装 |

**关键设计模式**:

```python
# 1. 使用 RootModel 实现联合类型 (Tagged Union)
class ThreadItem(RootModel[...]):
    root: (
        UserMessageThreadItem
        | AgentMessageThreadItem
        | CommandExecutionThreadItem
        | ...  # 共 14 种类型
    )

# 2. 使用 Literal 类型作为 discriminator
class AgentMessageThreadItem(BaseModel):
    type: Annotated[Literal["agentMessage"], Field(title="...")]
    text: str
    id: str

# 3. 使用 Annotated + Field 处理命名转换 (snake_case <-> camelCase)
class TurnStartParams(BaseModel):
    thread_id: Annotated[str, Field(alias="threadId")]  # wire: camelCase
    approval_policy: Annotated[AskForApproval | None, Field(alias="approvalPolicy")]
```

### 2.2 notification_registry.py - 通知类型注册表

**功能**: 建立通知方法名到 Pydantic 模型的运行时映射

```python
NOTIFICATION_MODELS: dict[str, type[BaseModel]] = {
    "account/login/completed": AccountLoginCompletedNotification,
    "turn/completed": TurnCompletedNotification,
    "item/agentMessage/delta": AgentMessageDeltaNotification,
    # ... 共 50+ 条映射
}
```

**使用场景** (`client.py`):

```python
def _coerce_notification(self, method: str, params: object) -> Notification:
    model = NOTIFICATION_MODELS.get(method)
    if model is None:
        return Notification(method=method, payload=UnknownNotification(...))
    payload = model.model_validate(params_dict)
    return Notification(method=method, payload=payload)
```

### 2.3 __init__.py - 包标识

仅包含文档字符串，标识此为自动生成的代码包。

---

## 具体技术实现

### 3.1 代码生成流程

完整的代码生成流水线由 `scripts/update_sdk_artifacts.py` 驱动：

```
┌─────────────────────────────────────────────────────────────────────┐
│  Source: codex-rs/app-server-protocol/schema/json/*.json            │
│  特别是: codex_app_server_protocol.v2.schemas.json (合并后的 schema) │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Step 1: _normalized_schema_bundle_text()                           │
│  - 读取 JSON Schema                                                 │
│  - _flatten_string_enum_one_of(): 简化 enum oneOf 结构              │
│  - _annotate_schema(): 为联合类型分支添加稳定 title                  │
│  - 输出规范化后的 JSON                                              │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Step 2: datamodel_code_generator (外部工具)                        │
│  配置参数:                                                          │
│  --input-file-type jsonschema                                       │
│  --output-model-type pydantic_v2.BaseModel                          │
│  --target-python-version 3.11                                       │
│  --use-standard-collections                                         │
│  --enum-field-as-literal one                                        │
│  --field-constraints                                                │
│  --snake-case-field                                                 │
│  --allow-population-by-field-name                                   │
│  --use-title-as-name                                                │
│  --use-annotated                                                    │
│  --use-union-operator                                               │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Step 3: 后处理                                                      │
│  - _normalize_generated_timestamps(): 统一时间戳占位符               │
│  - generate_notification_registry(): 生成通知注册表                  │
│  - generate_public_api_flat_methods(): 更新 api.py 中的方法签名      │
└─────────────────────────────────────────────────────────────────────┘
```

### 3.2 关键技术细节

#### 3.2.1 Schema 规范化

**问题**: `datamodel-code-generator` 对匿名 oneOf 分支会生成 `...1`, `...2` 这样的不稳定类名

**解决方案**: `_annotate_schema()` 函数通过 discriminator 推断稳定的 title:

```python
DISCRIMINATOR_KEYS = ("type", "method", "mode", "state", "status", "role", "reason")

def _variant_definition_name(base: str, variant: dict[str, Any]) -> str | None:
    props = variant.get("properties", {})
    for key in DISCRIMINATOR_KEYS:
        literal = _literal_from_property(props, key)
        if literal is not None:
            pascal = _to_pascal_case(literal)
            return f"{pascal}{base}"  # 如: ThreadStartedServerNotification
```

#### 3.2.2 命名风格转换

| 层级 | 命名风格 | 示例 |
|------|----------|------|
| JSON Schema (Wire) | camelCase | `threadId`, `approvalPolicy` |
| Python 代码 | snake_case | `thread_id`, `approval_policy` |
| 类名 | PascalCase | `ThreadStartParams`, `TurnStatus` |

实现方式:
```python
# Pydantic Field alias 实现双向映射
thread_id: Annotated[str, Field(alias="threadId")]

# model_dump(by_alias=True) 输出 camelCase
# model_validate() 接受 camelCase 输入
```

#### 3.2.3 联合类型实现

**Tagged Union 模式** (Rust-style):

```python
# Rust: enum ThreadItem { UserMessage(UserMessageThreadItem), ... }
# Python: RootModel + Literal discriminator

class UserMessageThreadItem(BaseModel):
    type: Literal["userMessage"]  # tag
    ...

class AgentMessageThreadItem(BaseModel):
    type: Literal["agentMessage"]  # tag
    ...

class ThreadItem(RootModel[...]):
    root: UserMessageThreadItem | AgentMessageThreadItem | ...
```

### 3.3 核心数据结构

#### 3.3.1 Thread 生命周期相关

```python
# 创建线程
ThreadStartParams:
    - approval_policy: AskForApproval | None
    - base_instructions: str | None
    - config: dict[str, Any] | None
    - cwd: str | None
    - developer_instructions: str | None
    - ephemeral: bool | None
    - model: str | None
    - sandbox: SandboxMode | None
    - service_tier: ServiceTier | None

ThreadStartResponse:
    - thread: Thread
    - approval_policy: AskForApproval
    - sandbox: SandboxPolicy

# Turn 执行
TurnStartParams:
    - thread_id: str
    - input: list[UserInput]
    - effort: ReasoningEffort | None
    - model: str | None
    - output_schema: Any | None
    - sandbox_policy: SandboxPolicy | None

TurnCompletedNotification:
    - thread_id: str
    - turn: Turn  # 包含 items, status, error 等
```

#### 3.3.2 通知系统

```python
# 50+ 种服务器通知，按类别分组：

# Thread 生命周期
"thread/started", "thread/status/changed", "thread/archived", 
"thread/unarchived", "thread/closed", "thread/name/updated"

# Turn 执行
"turn/started", "turn/completed", "turn/plan/updated", "turn/diff/updated"

# Item 级事件
"item/started", "item/completed"
"item/agentMessage/delta", "item/plan/delta"
"item/commandExecution/outputDelta"

# 系统事件
"account/updated", "account/rateLimits/updated"
"configWarning", "deprecationNotice"
"error"
```

---

## 关键代码路径与文件引用

### 4.1 文件结构

```
sdk/python/src/codex_app_server/generated/
├── __init__.py                    # 包标识 (1 行)
├── v2_all.py                      # 完整协议类型 (6351 行)
└── notification_registry.py       # 通知注册表 (106 行)
```

### 4.2 上游依赖 (Sources)

| 文件 | 用途 | 生成关系 |
|------|------|----------|
| `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json` | 合并后的 V2 协议 Schema | 主输入 |
| `codex-rs/app-server-protocol/schema/json/ServerNotification.json` | 服务器通知定义 | 用于生成 notification_registry.py |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 协议定义 (源) | 间接输入 |

### 4.3 下游消费者 (Consumers)

| 文件 | 使用方式 | 关键引用 |
|------|----------|----------|
| `client.py` | 导入类型用于 JSON-RPC 请求/响应 | `from .generated.v2_all import ThreadStartParams, ...` |
| `async_client.py` | 同上 | 同上 |
| `models.py` | 导入通知类型构建联合类型 | `from .generated.v2_all import TurnCompletedNotification, ...` |
| `api.py` | 导入类型用于高级 API | `from .generated.v2_all import ThreadStartParams, ...` |
| `__init__.py` (包根) | 导出公共类型 | `from .generated.v2_all import AskForApproval, ...` |

### 4.4 关键代码片段

#### 4.4.1 客户端请求构建 (client.py)

```python
def thread_start(self, params: V2ThreadStartParams | JsonObject | None = None) -> ThreadStartResponse:
    return self.request("thread/start", _params_dict(params), response_model=ThreadStartResponse)

# _params_dict 将 Pydantic 模型转换为 JSON 对象
def _params_dict(params) -> JsonObject:
    if hasattr(params, "model_dump"):
        return params.model_dump(by_alias=True, exclude_none=True, mode="json")
```

#### 4.4.2 通知反序列化 (client.py)

```python
def _coerce_notification(self, method: str, params: object) -> Notification:
    params_dict = params if isinstance(params, dict) else {}
    model = NOTIFICATION_MODELS.get(method)  # 从注册表查找
    if model is None:
        return Notification(method=method, payload=UnknownNotification(params=params_dict))
    try:
        payload = model.model_validate(params_dict)  # Pydantic 验证
    except Exception:
        return Notification(method=method, payload=UnknownNotification(params=params_dict))
    return Notification(method=method, payload=payload)
```

#### 4.4.3 测试契约 (tests/test_contract_generation.py)

```python
GENERATED_TARGETS = [
    Path("src/codex_app_server/generated/notification_registry.py"),
    Path("src/codex_app_server/generated/v2_all.py"),
    Path("src/codex_app_server/api.py"),
]

def test_generated_files_are_up_to_date():
    before = _snapshot_targets(ROOT)
    # 重新生成...
    subprocess.run([sys.executable, "scripts/update_sdk_artifacts.py", "generate-types"], ...)
    after = _snapshot_targets(ROOT)
    assert before == after, "Generated files drifted after regeneration"
```

---

## 依赖与外部交互

### 5.1 运行时依赖

| 包 | 用途 | 版本要求 |
|----|------|----------|
| `pydantic` | BaseModel, RootModel, Field, ConfigDict, Validation | >=2.0 |
| `typing.Annotated` | 类型元数据 (PEP 593) | Python 3.9+ |

### 5.2 生成时依赖

| 包 | 用途 |
|----|------|
| `datamodel-code-generator` | JSON Schema -> Pydantic 模型 |
| `ruff-format` | 生成的代码格式化 |

### 5.3 协议版本管理

```
codex-rs/app-server-protocol/
├── src/protocol/
│   ├── v2.rs          # Rust 协议定义 (Source of Truth)
│   └── common.rs      # 共享类型定义
├── schema/
│   └── json/          # 生成的 JSON Schema
│       ├── codex_app_server_protocol.v2.schemas.json
│       ├── ServerNotification.json
│       └── v2/*.json  # 单个类型定义
```

**版本同步流程**:
1. Rust 协议变更 -> 重新生成 JSON Schema (`just write-app-server-schema`)
2. JSON Schema 变更 -> 重新生成 Python 类型 (`python scripts/update_sdk_artifacts.py generate-types`)
3. CI 检查 (`test_contract_generation.py`) 确保生成文件与源 Schema 一致

---

## 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 代码生成漂移风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| 手动修改 | 开发者可能直接修改 generated/ 文件 | 文件头明确标注 `# DO NOT EDIT MANUALLY` |
| Schema 不同步 | Rust 协议变更后未重新生成 Python | CI 测试 `test_generated_files_are_up_to_date` |
| 工具版本差异 | 不同版本的 datamodel-code-generator 输出不同 | 锁定工具版本，使用 `--disable-timestamp` |

#### 6.1.2 类型兼容性风险

```python
# 问题: RootModel 的嵌套使用可能导致类型推断复杂
class ThreadItem(RootModel[...]):
    root: ...

# 使用时需要 .root 访问
item = ThreadItem.model_validate(data)
actual_item = item.root  # 解包
```

#### 6.1.3 枚举扩展风险

```python
# Literal 类型在新增枚举值时需要更新代码
# 如新增 TurnStatus 值，需要修改:
class TurnStatus(Enum):
    completed = "completed"
    interrupted = "interrupted"
    failed = "failed"
    in_progress = "inProgress"
    # new_value = "newValue"  # 需要重新生成
```

### 6.2 边界情况

#### 6.2.1 未知通知处理

```python
# 当收到未知通知方法时，fallback 到 UnknownNotification
model = NOTIFICATION_MODELS.get(method)
if model is None:
    return Notification(method=method, payload=UnknownNotification(params=params_dict))
```

#### 6.2.2 验证失败处理

```python
# Pydantic 验证失败时不抛出异常，而是降级为 UnknownNotification
try:
    payload = model.model_validate(params_dict)
except Exception:  # noqa: BLE001
    return Notification(method=method, payload=UnknownNotification(params=params_dict))
```

### 6.3 改进建议

#### 6.3.1 短期改进

| 建议 | 优先级 | 说明 |
|------|--------|------|
| 添加生成版本元数据 | 中 | 在 v2_all.py 中添加源 Schema 版本哈希 |
| 优化 RootModel 使用体验 | 中 | 考虑添加 `__getattr__` 代理到 `.root` |
| 完善文档字符串 | 低 | 将 JSON Schema description 导入为 docstring |

#### 6.3.2 中期改进

| 建议 | 优先级 | 说明 |
|------|--------|------|
| 增量生成 | 低 | 仅变更的类型重新生成，减少 diff |
| 类型别名优化 | 低 | 为常用联合类型提供有意义的别名 |
| 验证模式切换 | 低 | 支持严格/宽松验证模式 |

#### 6.3.3 架构建议

```python
# 当前: 单一 v2_all.py 文件 (6000+ 行)
# 建议: 按功能模块拆分

generated/
├── __init__.py
├── v2/
│   ├── __init__.py
│   ├── thread.py      # Thread 相关类型
│   ├── turn.py        # Turn 相关类型
│   ├── notification.py # 通知类型
│   ├── config.py      # 配置相关
│   └── common.py      # 共享类型
└── registry.py        # 通知注册表
```

### 6.4 监控与维护

| 检查项 | 频率 | 负责人 |
|--------|------|--------|
| 生成文件与 Schema 一致性 | 每次 CI | 自动化测试 |
| datamodel-code-generator 版本 | 每月 | SDK 维护者 |
| Pydantic 兼容性 | 每次升级 | SDK 维护者 |
| 类型覆盖率 | 每次发布 | SDK 维护者 |

---

## 附录

### A. 关键类型速查表

| 类型 | 说明 | 所在文件 |
|------|------|----------|
| `ThreadStartParams` | 创建线程参数 | v2_all.py |
| `TurnStartParams` | 开始 Turn 参数 | v2_all.py |
| `TurnCompletedNotification` | Turn 完成通知 | v2_all.py |
| `ThreadItem` | 线程项目联合类型 | v2_all.py |
| `SandboxPolicy` | 沙箱策略联合类型 | v2_all.py |
| `AskForApproval` | 审批策略类型 | v2_all.py |
| `ServerNotification` | 服务器通知联合类型 | v2_all.py |
| `NOTIFICATION_MODELS` | 通知方法映射表 | notification_registry.py |

### B. 相关命令

```bash
# 重新生成协议类型
python sdk/python/scripts/update_sdk_artifacts.py generate-types

# 运行契约测试
pytest sdk/python/tests/test_contract_generation.py -v

# 格式化生成代码 (已集成到生成流程)
ruff format sdk/python/src/codex_app_server/generated/v2_all.py
```

---

*文档生成时间: 2026-03-22*
*基于协议版本: codex_app_server_protocol.v2.schemas.json*
