# sync.py 研究文档

## 场景与职责

`sync.py` 是 Python SDK 的同步 API 示例程序，与 `async.py` 功能完全对应，但使用同步 API (`Codex`) 实现。演示功能包括：

1. **动态模型选择**：查询可用模型列表，根据优先级策略选择最佳模型
2. **推理力度选择**：根据模型支持的推理力度选项，选择最高级别的推理力度
3. **多轮对话**：创建线程并执行两轮不同配置的对话回合
4. **结构化输出**：第二轮对话使用 JSON Schema 约束输出格式

该示例与 `async.py` 形成对比，展示了 SDK 提供的同步和异步两种 API 风格。开发者可以根据应用场景选择适合的编程模型。

## 功能点目的

### 1. 模型选择策略 (`_pick_highest_model`)
- **目的**：从可用模型中智能选择最优模型
- **策略**：
  - 优先选择可见模型（非隐藏）
  - 优先匹配首选模型 `gpt-5.4`
  - 排除已有升级版本的模型（避免选择即将废弃的模型）
  - 最终按模型名称和 ID 字典序选择最高版本

### 2. 推理力度选择 (`_pick_highest_turn_effort`)
- **目的**：为选定的模型选择最高支持的推理力度
- **策略**：
  - 定义推理力度等级映射（none=0 到 xhigh=5）
  - 从模型支持的推理力度选项中选择等级最高的
  - 如果模型不支持任何推理力度，默认使用 `medium`

### 3. 两轮对话演示
- **第一轮**：简单文本对话，演示基本用法，仅传递 `model` 和 `effort`
- **第二轮**：高级配置对话，展示完整的回合参数配置：
  - `approval_policy`: 设置审批策略为 "never"（无需用户审批）
  - `cwd`: 设置当前工作目录为脚本所在目录
  - `output_schema`: JSON Schema 约束输出格式（结构化输出）
  - `personality`: 设置人格为 "pragmatic"（务实风格）
  - `sandbox_policy`: 沙箱策略为只读+完全访问
  - `summary`: 推理摘要级别为 "concise"（简洁摘要）

## 具体技术实现

### 关键流程

```
with Codex(config=runtime_config()) as codex:
├── 初始化 AppServerClient
├── 建立与 codex-cli 的 stdio 连接
├── 执行 initialize 握手
├── codex.models(include_hidden=True)
│   └── 调用 model/list RPC 获取 ModelListResponse
├── _pick_highest_model(models.data)
│   └── 返回最优 Model 对象
├── _pick_highest_turn_effort(selected_model)
│   └── 返回最高 ReasoningEffort 枚举
├── codex.thread_start(model=..., config=...)
│   ├── 构造 ThreadStartParams
│   ├── 调用 thread/start RPC
│   └── 返回 Thread 对象
├── thread.turn(input, ...).run()
│   ├── 构造 TurnStartParams
│   ├── 调用 turn/start RPC
│   ├── stream() 开始接收通知
│   ├── 迭代通知直到 turn/completed
│   └── 返回 Turn 对象
├── thread.read(include_turns=True)
│   └── 调用 thread/read RPC
└── 第二轮对话（带完整参数）
    └── 同上流程
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
- 用于比较不同推理力度的优先级
- 数值越高表示推理力度越强

#### 2. 首选模型常量
```python
PREFERRED_MODEL = "gpt-5.4"
```
- 硬编码的首选模型标识
- 匹配逻辑同时检查 `model` 和 `id` 字段

#### 3. 输出 JSON Schema（结构化输出）
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
- 约束模型输出必须包含 `summary` 字符串和 `actions` 字符串数组
- 用于生成结构化的功能标志 rollout 计划

#### 4. 沙箱策略配置
```python
SANDBOX_POLICY = SandboxPolicy.model_validate({
    "type": "readOnly",
    "access": {"type": "fullAccess"},
})
```
- `type: readOnly`: 只读沙箱模式
- `access.type: fullAccess`: 完全访问权限（在只读限制内）

#### 5. 审批策略
```python
APPROVAL_POLICY = AskForApproval.model_validate("never")
```
- `"never"` 表示不需要用户审批即可执行工具调用
- 其他选项包括: `"untrusted"`, `"on-failure"`, `"on-request"`

### 协议与命令

#### App-Server Protocol v2 RPC 调用

| RPC 方法 | 用途 | 请求参数 | 响应类型 |
|---------|------|---------|---------|
| `model/list` | 获取可用模型 | `ModelListParams` | `ModelListResponse` |
| `thread/start` | 创建新线程 | `ThreadStartParams` | `ThreadStartResponse` |
| `turn/start` | 开始新回合 | `TurnStartParams` | `TurnStartResponse` |
| `thread/read` | 读取线程状态 | `thread_id`, `include_turns` | `ThreadReadResponse` |

#### TurnStartParams 字段（第二轮使用）
```python
TurnStartParams(
    thread_id=self.id,
    input=wire_input,                    # 用户输入（已序列化）
    approval_policy=APPROVAL_POLICY,      # "never"
    approvals_reviewer=None,
    cwd=cwd,                             # 工作目录
    effort=effort,                       # 推理力度
    model=model,                         # 模型名称
    output_schema=OUTPUT_SCHEMA,         # JSON Schema
    personality=personality,             # "pragmatic"
    sandbox_policy=sandbox_policy,       # 沙箱策略
    service_tier=None,
    summary=summary,                     # "concise"
)
```

#### 通知流处理
```python
def stream(self) -> Iterator[Notification]:
    self._client.acquire_turn_consumer(self.id)  # 获取消费锁
    try:
        while True:
            event = self._client.next_notification()  # 阻塞接收
            yield event
            if (event.method == "turn/completed" and 
                event.payload.turn.id == self.id):
                break  # 回合完成
    finally:
        self._client.release_turn_consumer(self.id)  # 释放锁
```

## 关键代码路径与文件引用

### 核心 SDK 文件

| 文件路径 | 职责描述 |
|---------|---------|
| `sdk/python/src/codex_app_server/__init__.py` | 公共 API 导出：Codex, TextInput, ReasoningEffort 等 |
| `sdk/python/src/codex_app_server/api.py` | 实现 `Codex`, `Thread`, `TurnHandle` 类 |
| `sdk/python/src/codex_app_server/client.py` | `AppServerClient` - 底层同步 JSON-RPC 客户端 |
| `sdk/python/src/codex_app_server/_inputs.py` | 输入类型：`TextInput`, `ImageInput`, `LocalImageInput` 等 |
| `sdk/python/src/codex_app_server/_run.py` | 运行结果收集逻辑 |
| `sdk/python/src/codex_app_server/generated/v2_all.py` | 自动生成的 Pydantic 模型（来自 Rust 协议） |

### 示例辅助文件

| 文件路径 | 职责描述 |
|---------|---------|
| `sdk/python/examples/_bootstrap.py` | 运行时设置、本地 SDK 路径注入、工具函数 |
| `sdk/python/examples/_runtime_setup.py` | `codex-cli-bin` 运行时包自动安装 |

### 关键代码详解

#### 模型选择算法
```python
def _pick_highest_model(models):
    # 1. 过滤可见模型，如果没有则使用全部
    visible = [m for m in models if not m.hidden] or models
    
    # 2. 优先匹配首选模型
    preferred = next((m for m in visible if m.model == PREFERRED_MODEL 
                      or m.id == PREFERRED_MODEL), None)
    if preferred is not None:
        return preferred
    
    # 3. 排除有升级版本的模型
    known_names = {m.id for m in visible} | {m.model for m in visible}
    top_candidates = [m for m in visible 
                      if not (m.upgrade and m.upgrade in known_names)]
    pool = top_candidates or visible
    
    # 4. 按 (model, id) 字典序选择最高
    return max(pool, key=lambda m: (m.model, m.id))
```

#### 推理力度选择算法
```python
def _pick_highest_turn_effort(model) -> ReasoningEffort:
    # 无支持选项时返回默认值
    if not model.supported_reasoning_efforts:
        return ReasoningEffort.medium
    
    # 按 REASONING_RANK 选择最高等级
    best = max(
        model.supported_reasoning_efforts,
        key=lambda option: REASONING_RANK.get(option.reasoning_effort.value, -1),
    )
    return ReasoningEffort(best.reasoning_effort.value)
```

#### 同步上下文管理器模式
```python
with Codex(config=runtime_config()) as codex:
    # __enter__ 初始化连接
    # __exit__ 确保关闭连接
    ...
```

与异步版本对比：
```python
# 异步版本
async with AsyncCodex(config=runtime_config()) as codex:
    ...
```

## 依赖与外部交互

### Python 包依赖
| 包名 | 用途 |
|-----|------|
| `codex_app_server` | Python SDK 主包 |
| `pydantic` | 数据验证和 Settings 管理 |

### 运行时依赖
| 组件 | 说明 |
|-----|------|
| `codex-cli-bin` | Codex CLI 二进制运行时 |
| Python >= 3.10 | 语言版本要求 |

### 外部系统交互
1. **stdio 传输**: 通过 stdin/stdout 与 codex-cli 子进程通信
2. **JSON-RPC v2**: 协议层通信格式
3. **OpenAI API**: 通过 codex-cli 间接调用

### 配置来源
- `runtime_config()` 返回 `AppServerConfig` 实例
- 可能读取的环境变量：
  - `OPENAI_API_KEY`
  - `CODEX_*` 系列配置

## 风险、边界与改进建议

### 风险点

1. **硬编码模型名称**
   ```python
   PREFERRED_MODEL = "gpt-5.4"  # 硬编码
   ```
   - 风险：模型名称变更或下架时选择逻辑降级
   - 影响：可能选择非最优模型
   - **建议**: 支持从环境变量或配置文件读取首选模型列表

2. **推理力度默认逻辑**
   ```python
   if not model.supported_reasoning_efforts:
       return ReasoningEffort.medium  # 硬编码默认值
   ```
   - 风险：可能与模型实际默认行为不一致
   - **建议**: 优先使用 `model.default_reasoning_effort`

3. **异常处理缺失**
   - 示例中没有 try/except 块
   - API 错误（限流、网络中断）会导致程序崩溃
   - **建议**: 添加错误处理和用户友好的错误消息

4. **资源管理**
   - 依赖上下文管理器确保连接关闭
   - 如果 `__enter__` 中初始化失败，需要确保不泄漏资源

### 边界情况

| 场景 | 行为 |
|-----|------|
| 空模型列表 | `_pick_highest_model` 抛出 `ValueError` |
| 所有模型都隐藏 | 回退到使用所有模型（包括隐藏） |
| 模型无推理力度选项 | 使用 `medium` 作为默认值 |
| 线程创建失败 | 抛出异常，上下文管理器确保清理 |
| 回合执行超时 | 当前实现无超时控制，可能无限阻塞 |

### 改进建议

1. **配置化首选模型**
   ```python
   import os
   PREFERRED_MODELS = os.getenv(
       "CODEX_PREFERRED_MODELS", 
       "gpt-5.4,gpt-4o,gpt-4"
   ).split(",")
   ```

2. **使用模型默认推理力度**
   ```python
   def _pick_highest_turn_effort(model) -> ReasoningEffort:
       if not model.supported_reasoning_efforts:
           return model.default_reasoning_effort  # 使用模型推荐值
       # ...
   ```

3. **添加超时控制**
   ```python
   import signal
   
   def run_with_timeout(turn, timeout_sec=60):
       def handler(signum, frame):
           raise TimeoutError("Turn execution timed out")
       signal.signal(signal.SIGALRM, handler)
       signal.alarm(timeout_sec)
       try:
           return turn.run()
       finally:
           signal.alarm(0)
   ```

4. **添加日志和调试信息**
   ```python
   import logging
   logger = logging.getLogger(__name__)
   
   def _pick_highest_model(models):
       logger.debug(f"Selecting from {len(models)} models")
       # ... 记录选择决策过程
   ```

5. **支持分页加载模型**
   ```python
   def get_all_models(codex):
       all_models = []
       cursor = None
       while True:
           resp = codex.models(include_hidden=True, cursor=cursor)
           all_models.extend(resp.data)
           cursor = resp.next_cursor
           if not cursor:
               break
       return all_models
   ```

6. **类型注解完善**
   ```python
   from typing import List, Optional
   from codex_app_server import Model
   
   def _pick_highest_model(models: List[Model]) -> Model:
       ...
   ```

### 与 async.py 的差异对比

| 方面 | sync.py | async.py |
|-----|---------|----------|
| API 类 | `Codex` | `AsyncCodex` |
| 上下文管理器 | `with` | `async with` |
| 方法调用 | 直接调用 | `await` 调用 |
| 线程模型 | 同步阻塞 | 异步非阻塞（基于线程卸载） |
| 适用场景 | 简单脚本、交互式 | 高并发、Web 服务 |
| 内部实现 | 直接调用 client | 使用 `asyncio.to_thread` |

两者在功能上完全等价，选择取决于应用场景的并发需求。
