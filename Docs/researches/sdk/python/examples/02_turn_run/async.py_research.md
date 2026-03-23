# sdk/python/examples/02_turn_run/async.py 研究文档

## 场景与职责

本文件是 Codex Python SDK 的**异步示例程序**，演示如何使用 `AsyncCodex` 客户端完成一次完整的对话回合（Turn）执行流程。该示例位于 `02_turn_run` 目录，是 SDK 示例系列中的第二个示例，重点展示：

1. **异步上下文管理**模式下的 SDK 使用
2. **Thread 生命周期管理**（创建 → 对话 → 读取持久化状态）
3. **Turn 执行与结果收集**的完整流程
4. **异步 API 的链式调用**模式

该示例作为开发者学习异步编程模式的入口点，展示了从初始化到获取结果的完整异步工作流。

## 功能点目的

### 1. 异步 SDK 初始化与上下文管理
- 使用 `async with AsyncCodex(config=runtime_config())` 确保资源正确初始化和释放
- 通过 `runtime_config()` 获取示例友好的配置（来自 `_bootstrap` 模块）

### 2. Thread 创建与配置
- 调用 `codex.thread_start()` 创建新线程
- 配置参数包括：
  - `model`: 指定使用的模型（示例中为 `"gpt-5.4"`）
  - `config`: 模型配置（示例中设置 `model_reasoning_effort: "high"`）

### 3. Turn 执行流程
- 使用 `thread.turn(TextInput(...))` 创建对话回合
- 调用 `.run()` 方法阻塞等待 Turn 完成并获取结果
- 展示同步风格的异步 API（`await turn.run()`）

### 4. 持久化状态验证
- 使用 `thread.read(include_turns=True)` 读取线程完整状态
- 通过 `find_turn_by_id()` 工具函数定位特定 Turn
- 验证 Turn 在服务器端的持久化状态

### 5. 结果输出
- 打印线程 ID、Turn ID、执行状态
- 使用 `assistant_text_from_turn()` 提取助手回复文本
- 统计并输出 Turn 中的项目数量

## 具体技术实现

### 关键流程

```
┌─────────────────────────────────────────────────────────────────┐
│  1. 路径设置与引导导入                                            │
│     - 将父目录加入 sys.path                                       │
│     - 从 _bootstrap 导入辅助函数                                  │
├─────────────────────────────────────────────────────────────────┤
│  2. SDK 源依赖确保                                               │
│     - ensure_local_sdk_src() 确保本地 SDK 源码可用               │
├─────────────────────────────────────────────────────────────────┤
│  3. 异步主函数执行                                               │
│     async with AsyncCodex(config=runtime_config()) as codex:     │
│     ├─ thread = await codex.thread_start(...)                    │
│     ├─ turn = await thread.turn(TextInput("..."))                │
│     ├─ result = await turn.run()                                 │
│     ├─ persisted = await thread.read(include_turns=True)         │
│     └─ 输出结果                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 数据结构

#### 输入类型
```python
from codex_app_server import TextInput
# TextInput 是一个 dataclass，包含单个 text 字段
@dataclass(slots=True)
class TextInput:
    text: str
```

#### 核心响应类型
- `ThreadStartResponse`: 线程创建响应，包含 `thread.id`
- `TurnStartResponse`: Turn 创建响应，包含 `turn.id`
- `AppServerTurn` (via `turn.run()`): 完成的 Turn 对象，包含：
  - `id`: Turn 标识符
  - `status`: Turn 状态（completed/failed/in_progress 等）
  - `error`: 错误信息（如有）
  - `items`: Turn 中的项目列表

### 协议与通信

#### JSON-RPC 2.0 over stdio
- `AsyncCodex` 内部使用 `AsyncAppServerClient`
- 通过 `asyncio.to_thread()` 将同步调用转换为异步
- 使用 `asyncio.Lock` 确保传输层串行化

#### 关键 RPC 调用
| 方法 | 参数 | 响应 |
|------|------|------|
| `thread/start` | `ThreadStartParams` | `ThreadStartResponse` |
| `turn/start` | `TurnStartParams` | `TurnStartResponse` |
| `thread/read` | `{threadId, includeTurns}` | `ThreadReadResponse` |

### 辅助函数依赖

#### `_bootstrap.py` 提供的工具
```python
# 确保本地 SDK 源可用
ensure_local_sdk_src() -> Path

# 返回示例友好的配置
runtime_config() -> AppServerConfig

# 在 turns 列表中查找指定 ID 的 turn
find_turn_by_id(turns: Iterable[object] | None, turn_id: str) -> object | None

# 从 turn 对象中提取助手文本
assistant_text_from_turn(turn: object | None) -> str
```

## 关键代码路径与文件引用

### 直接依赖
| 文件 | 说明 |
|------|------|
| `sdk/python/examples/_bootstrap.py` | 示例引导模块，提供运行时配置和工具函数 |
| `sdk/python/src/codex_app_server/__init__.py` | SDK 公共 API 导出 |
| `sdk/python/src/codex_app_server/api.py` | `AsyncCodex`, `AsyncThread`, `AsyncTurnHandle` 实现 |
| `sdk/python/src/codex_app_server/async_client.py` | `AsyncAppServerClient` 异步客户端实现 |
| `sdk/python/src/codex_app_server/_inputs.py` | `TextInput` 等输入类型定义 |

### 调用链分析

```
async.py
  └─ AsyncCodex.__aenter__()
       └─ AsyncAppServerClient.start()
            └─ AppServerClient.start()
                 └─ subprocess.Popen([codex_bin, "app-server", "--listen", "stdio://"])

async.py
  └─ AsyncCodex.thread_start()
       └─ AsyncAppServerClient.thread_start()
            └─ AppServerClient.thread_start()
                 └─ request("thread/start", params, ThreadStartResponse)

async.py
  └─ AsyncThread.turn()
       └─ AsyncCodex._ensure_initialized()
       └─ _to_wire_input(TextInput)
       └─ AsyncAppServerClient.turn_start()
            └─ request("turn/start", params, TurnStartResponse)
       └─ 返回 AsyncTurnHandle

async.py
  └─ AsyncTurnHandle.run()
       └─ AsyncTurnHandle.stream()
            └─ 订阅通知直到 turn/completed
       └─ 返回 AppServerTurn
```

### 配置初始化路径
```
runtime_config()
  └─ AppServerConfig()  # 默认配置
       ├─ codex_bin: None (自动解析)
       ├─ launch_args_override: None
       ├─ config_overrides: ()
       ├─ cwd: None
       ├─ env: None
       ├─ client_name: "codex_python_sdk"
       ├─ client_version: "0.2.0"
       └─ experimental_api: True
```

## 依赖与外部交互

### Python 标准库
- `asyncio`: 异步运行时
- `sys`, `pathlib`: 路径处理

### 第三方依赖
- `codex_app_server`: SDK 主包
  - `AsyncCodex`: 异步 SDK 入口类
  - `TextInput`: 文本输入包装类型

### 外部进程交互
- **Codex CLI Binary**: 通过 `codex app-server --listen stdio://` 启动
- **通信方式**: stdio 上的 JSON-RPC 2.0
- **自动发现**: 通过 `codex-cli-bin` 包或 `AppServerConfig.codex_bin` 配置

### 引导模块依赖
- `_bootstrap.py`: 提供运行时环境设置
- `_runtime_setup.py`: 确保运行时包安装

## 风险、边界与改进建议

### 潜在风险

1. **异常处理不足**
   - 当前代码未捕获 `turn.run()` 可能抛出的异常
   - 如果 Turn 执行失败（如模型不可用），程序会崩溃
   - **建议**: 添加 try-except 块处理 `RuntimeError`

2. **资源泄漏风险**
   - 虽然使用了 `async with`，但如果初始化阶段抛出异常，需要确保清理
   - `AsyncCodex.__aenter__` 已处理此情况，但示例未展示错误处理

3. **模型版本硬编码**
   - `"gpt-5.4"` 是硬编码的模型标识符
   - 如果该模型不可用，示例将失败
   - **建议**: 从环境变量或配置读取模型名称

### 边界情况

1. **并发限制**
   - `AsyncTurnHandle.stream()` 使用 `acquire_turn_consumer()` 限制并发
   - 同时只能有一个活跃的 Turn 消费者
   - 尝试并发流式处理会抛出 `RuntimeError`

2. **空结果处理**
   - `assistant_text_from_turn()` 在 `persisted_turn` 为 None 时返回空字符串
   - 示例中未显式检查此情况

3. **网络/服务不可用**
   - 如果 Codex CLI 未安装或不在 PATH 中，`start()` 会失败
   - 错误信息通过 `FileNotFoundError` 抛出

### 改进建议

1. **添加错误处理示例**
```python
async def main() -> None:
    try:
        async with AsyncCodex(config=runtime_config()) as codex:
            # ... 现有代码 ...
            if result.status == TurnStatus.failed:
                print(f"Turn failed: {result.error}")
                return
            # ...
    except Exception as e:
        print(f"Error: {e}")
        raise
```

2. **展示更多 Turn 参数**
   - 当前仅展示 `model` 和 `config`，可添加 `approval_policy`、`sandbox` 等参数示例

3. **添加超时控制**
   - 使用 `asyncio.wait_for()` 包装长时间运行的操作

4. **模型选择动态化**
```python
import os
model = os.getenv("CODEX_MODEL", "gpt-5.4")
thread = await codex.thread_start(model=model, ...)
```

5. **与同步版本对比注释**
   - 添加注释说明与 `sync.py` 的关键差异（`await` 关键字、异步上下文管理器）

### 测试覆盖

相关测试位于：
- `sdk/python/tests/test_public_api_runtime_behavior.py`: 测试 `AsyncCodex`, `AsyncThread`, `AsyncTurnHandle`
- `sdk/python/tests/test_async_client_behavior.py`: 测试异步客户端行为

关键测试用例：
- `test_async_thread_run_accepts_string_input_and_returns_run_result`: 验证异步运行流程
- `test_async_turn_stream_rejects_second_active_consumer`: 验证并发限制
