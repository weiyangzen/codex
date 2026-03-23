# async.py 研究文档

## 场景与职责

`async.py` 是 Python SDK 的示例程序，演示了如何使用异步 API (`AsyncCodex`) 实现以下功能：
1. **动态模型选择**：查询可用模型列表，根据优先级策略选择最佳模型
2. **推理力度选择**：根据模型支持的推理力度选项，选择最高级别的推理力度
3. **多轮对话**：创建线程并执行两轮不同配置的对话回合
4. **结构化输出**：第二轮对话使用 JSON Schema 约束输出格式

该示例位于 `sdk/python/examples/13_model_select_and_turn_params/`，是第 13 号示例，专注于展示模型选择和回合参数的灵活配置。

## 功能点目的

### 1. 模型选择策略 (`_pick_highest_model`)
- **目的**：从可用模型中智能选择最优模型
- **策略**：
  - 优先选择可见模型（非隐藏）
  - 优先匹配首选模型 `gpt-5.4`
  - 排除已有升级版本的模型
  - 最终按模型名称和 ID 字典序选择最高版本

### 2. 推理力度选择 (`_pick_highest_turn_effort`)
- **目的**：为选定的模型选择最高支持的推理力度
- **策略**：
  - 定义推理力度等级映射（none=0 到 xhigh=5）
  - 从模型支持的推理力度选项中选择等级最高的
  - 如果模型不支持任何推理力度，默认使用 `medium`

### 3. 两轮对话演示
- **第一轮**：简单文本对话，演示基本用法
- **第二轮**：高级配置对话，展示多种回合参数：
  - `approval_policy`: 设置审批策略为 "never"（无需审批）
  - `cwd`: 设置当前工作目录
  - `output_schema`: JSON Schema 约束输出格式
  - `personality`: 设置人格为 "pragmatic"（务实）
  - `sandbox_policy`: 沙箱策略为只读+完全访问
  - `summary`: 推理摘要级别为 "concise"（简洁）

## 具体技术实现

### 关键流程

```
main()
├── AsyncCodex(config=runtime_config()) as codex
│   ├── 初始化 AppServerClient
│   └── 建立与 codex-cli 的 stdio 连接
├── codex.models(include_hidden=True)
│   └── 调用 model/list RPC 获取可用模型
├── _pick_highest_model(models.data)
│   └── 返回最优模型对象
├── _pick_highest_turn_effort(selected_model)
│   └── 返回最高推理力度枚举
├── codex.thread_start(model=..., config=...)
│   └── 调用 thread/start RPC 创建线程
│   └── 返回 AsyncThread 对象
├── thread.turn(input, model=..., effort=...).run()
│   ├── 调用 thread/turnStart RPC
│   ├── 流式接收通知直到 turn/completed
│   └── 返回 Turn 对象
├── thread.read(include_turns=True)
│   └── 调用 thread/read RPC 获取线程状态
└── 第二轮对话（带完整参数）
    └── 同上流程，但使用更多 TurnStartParams
```

### 关键数据结构

#### 1. 推理力度等级映射
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

#### 2. 首选模型常量
```python
PREFERRED_MODEL = "gpt-5.4"
```

#### 3. 输出 JSON Schema
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

#### 4. 沙箱策略配置
```python
SANDBOX_POLICY = SandboxPolicy.model_validate({
    "type": "readOnly",
    "access": {"type": "fullAccess"},
})
```

#### 5. 审批策略
```python
APPROVAL_POLICY = AskForApproval.model_validate("never")
```

### 协议与命令

#### App-Server Protocol v2 RPC 调用

1. **model/list**: 获取可用模型列表
   - 请求参数: `ModelListParams(include_hidden=True)`
   - 响应: `ModelListResponse(data=list[Model], next_cursor=Optional[str])`

2. **thread/start**: 创建新线程
   - 请求参数: `ThreadStartParams(model=..., config={"model_reasoning_effort": ...})`
   - 响应: `ThreadStartResponse(thread=Thread)`

3. **turn/start**: 开始新回合
   - 请求参数: `TurnStartParams(...)` 包含所有回合级配置
   - 响应: `TurnStartResponse(turn=Turn)`

4. **thread/read**: 读取线程状态
   - 请求参数: `thread_id`, `include_turns=True`
   - 响应: `ThreadReadResponse(thread=Thread)`

#### 通知流处理
- 通过 `TurnHandle.stream()` 异步迭代接收通知
- 过滤 `turn/completed` 通知确定回合结束
- 通知类型包括：`AgentMessageDeltaNotification`, `TurnCompletedNotification` 等

## 关键代码路径与文件引用

### 核心 SDK 文件

| 文件 | 职责 |
|------|------|
| `sdk/python/src/codex_app_server/__init__.py` | 导出公共 API：AsyncCodex, TextInput, ReasoningEffort 等 |
| `sdk/python/src/codex_app_server/api.py` | 实现 AsyncCodex, AsyncThread, AsyncTurnHandle 类 |
| `sdk/python/src/codex_app_server/async_client.py` | AsyncAppServerClient，异步包装器，使用线程卸载 |
| `sdk/python/src/codex_app_server/client.py` | AppServerClient，底层同步 JSON-RPC 客户端 |
| `sdk/python/src/codex_app_server/_inputs.py` | 输入类型定义：TextInput, ImageInput 等 |
| `sdk/python/src/codex_app_server/generated/v2_all.py` | 自动生成的 Pydantic 模型（来自 Rust 协议定义） |

### 示例辅助文件

| 文件 | 职责 |
|------|------|
| `sdk/python/examples/_bootstrap.py` | 运行时依赖检查、本地 SDK 路径注入、工具函数 |
| `sdk/python/examples/_runtime_setup.py` | codex-cli-bin 运行时包安装 |

### 关键代码片段

#### 模型选择逻辑
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

#### 推理力度选择逻辑
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

#### 异步主流程
```python
async def main() -> None:
    async with AsyncCodex(config=runtime_config()) as codex:
        models = await codex.models(include_hidden=True)
        selected_model = _pick_highest_model(models.data)
        selected_effort = _pick_highest_turn_effort(selected_model)
        
        thread = await codex.thread_start(
            model=selected_model.model,
            config={"model_reasoning_effort": selected_effort.value},
        )
        
        first_turn = await thread.turn(...)
        first = await first_turn.run()
        # ... 处理结果
```

## 依赖与外部交互

### Python 依赖
- `codex_app_server`: Python SDK 主包
- `pydantic`: 数据验证和序列化
- `asyncio`: 异步运行时

### 运行时依赖
- `codex-cli-bin`: Codex CLI 二进制运行时（通过 `_runtime_setup.py` 自动安装）
- 版本要求: Python >= 3.10

### 外部系统交互
1. **stdio 传输层**: 通过 stdin/stdout 与 codex-cli 子进程通信
2. **JSON-RPC 协议**: 使用 v2 协议进行 RPC 调用
3. **OpenAI API**: 通过 codex-cli 间接调用 OpenAI Responses API

### 配置来源
- `runtime_config()`: 从 `_bootstrap.py` 获取默认配置
- 环境变量: 可能通过 `AppServerConfig` 读取环境配置

## 风险、边界与改进建议

### 风险点

1. **模型硬编码风险**
   - `PREFERRED_MODEL = "gpt-5.4"` 是硬编码的
   - 如果该模型不可用或重命名，选择逻辑会降级到字典序选择
   - **建议**: 从配置文件或环境变量读取首选模型列表

2. **推理力度降级风险**
   - 当模型不支持任何推理力度时，默认使用 `medium`
   - 这可能与模型实际默认行为不一致
   - **建议**: 优先使用模型的 `default_reasoning_effort` 字段

3. **异常处理缺失**
   - 示例中没有 try/except 块处理 API 错误
   - 网络中断或 API 限流会导致程序崩溃
   - **建议**: 添加适当的错误处理和重试逻辑

4. **资源泄漏风险**
   - 虽然使用了 `async with`，但如果初始化失败，清理可能不完整
   - **建议**: 确保所有异常路径都正确关闭资源

### 边界情况

1. **空模型列表**: 如果 `models.data` 为空，`_pick_highest_model` 会抛出 `ValueError`
2. **隐藏模型**: `include_hidden=True` 会返回所有模型，但选择逻辑优先选择可见模型
3. **并发限制**: 异步客户端使用 `asyncio.Lock` 保护 stdio 传输，单连接不支持真正的并发请求

### 改进建议

1. **配置化模型选择**
   ```python
   PREFERRED_MODELS = os.getenv("CODEX_PREFERRED_MODELS", "gpt-5.4,gpt-4o").split(",")
   ```

2. **使用模型默认推理力度**
   ```python
   def _pick_highest_turn_effort(model) -> ReasoningEffort:
       if not model.supported_reasoning_efforts:
           return model.default_reasoning_effort  # 使用模型默认值
       # ...
   ```

3. **添加类型注解**
   - `_pick_highest_model` 和 `_pick_highest_turn_effort` 可以添加完整的类型注解

4. **添加日志记录**
   - 记录模型选择决策过程
   - 记录 API 调用耗时和错误

5. **支持分页**
   - `codex.models()` 支持分页，示例中未展示如何处理多页结果

6. **测试覆盖**
   - 添加单元测试验证模型选择逻辑
   - 使用 mock 测试不同 API 响应场景
