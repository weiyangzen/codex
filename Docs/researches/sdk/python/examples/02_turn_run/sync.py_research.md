# sdk/python/examples/02_turn_run/sync.py 研究文档

## 场景与职责

本文件是 Codex Python SDK 的**同步示例程序**，演示如何使用 `Codex` 客户端完成一次完整的对话回合（Turn）执行流程。该示例位于 `02_turn_run` 目录，与 `async.py` 形成对照，重点展示：

1. **同步阻塞式 API** 的使用模式
2. **上下文管理器** (`with` 语句) 下的资源管理
3. **Thread 生命周期管理**（创建 → 对话 → 读取持久化状态）
4. **Turn 执行与结果收集**的简洁流程

该示例适合不熟悉异步编程的开发者，提供了最直观的 SDK 使用方式。

## 功能点目的

### 1. 同步 SDK 初始化与上下文管理
- 使用 `with Codex(config=runtime_config())` 确保资源正确初始化和释放
- 通过 `runtime_config()` 获取示例友好的配置（来自 `_bootstrap` 模块）
- 在 `__enter__` 时自动启动底层进程，在 `__exit__` 时自动清理

### 2. Thread 创建与配置
- 调用 `codex.thread_start()` 创建新线程
- 配置参数包括：
  - `model`: 指定使用的模型（示例中为 `"gpt-5.4"`）
  - `config`: 模型配置（示例中设置 `model_reasoning_effort: "high"`）

### 3. Turn 执行流程
- 使用 `thread.turn(TextInput(...))` 创建对话回合
- 调用 `.run()` 方法阻塞等待 Turn 完成并获取结果
- 展示链式调用风格：`thread.turn(...).run()`

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
│  3. 同步上下文执行                                               │
│     with Codex(config=runtime_config()) as codex:                │
│     ├─ thread = codex.thread_start(...)                          │
│     ├─ result = thread.turn(TextInput("...")).run()              │
│     ├─ persisted = thread.read(include_turns=True)               │
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
- `Codex` 内部使用 `AppServerClient`
- 通过 `subprocess.Popen` 启动 `codex app-server --listen stdio://`
- 使用 stdio 进行 JSON-RPC 通信

#### 关键 RPC 调用
| 方法 | 参数 | 响应 |
|------|------|------|
| `thread/start` | `ThreadStartParams` | `ThreadStartResponse` |
| `turn/start` | `TurnStartParams` | `TurnStartResponse` |
| `thread/read` | `{threadId, includeTurns}` | `ThreadReadResponse` |

#### 通知处理
- `turn.run()` 内部调用 `stream()` 方法
- `stream()` 通过 `acquire_turn_consumer()` 获取消费锁
- 循环读取通知直到收到 `turn/completed` 事件
- 最后调用 `release_turn_consumer()` 释放锁

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
| `sdk/python/src/codex_app_server/api.py` | `Codex`, `Thread`, `TurnHandle` 实现 |
| `sdk/python/src/codex_app_server/client.py` | `AppServerClient` 同步客户端实现 |
| `sdk/python/src/codex_app_server/_inputs.py` | `TextInput` 等输入类型定义 |
| `sdk/python/src/codex_app_server/_run.py` | `RunResult` 和结果收集逻辑 |

### 调用链分析

```
sync.py
  └─ Codex.__enter__()
       └─ AppServerClient.start()
            └─ subprocess.Popen([codex_bin, "app-server", "--listen", "stdio://"])
            └─ _start_stderr_drain_thread()  # 启动 stderr 读取线程

sync.py
  └─ Codex.thread_start()
       └─ AppServerClient.thread_start()
            └─ request("thread/start", _params_dict(params), ThreadStartResponse)
            └─ 返回 Thread(self._client, started.thread.id)

sync.py
  └─ Thread.turn()
       └─ _to_wire_input(TextInput) -> [{"type": "text", "text": "..."}]
       └─ AppServerClient.turn_start()
            └─ request("turn/start", payload, TurnStartResponse)
       └─ 返回 TurnHandle(self._client, self.id, turn.turn.id)

sync.py
  └─ TurnHandle.run()
       └─ TurnHandle.stream()
            ├─ acquire_turn_consumer(turn_id)  # 获取消费锁
            ├─ 循环: next_notification()
            │     └─ 从 _pending_notifications 或 _read_message() 获取
            ├─ 直到收到 turn/completed 且 turn.id == self.id
            └─ release_turn_consumer(turn_id)  # 释放锁
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

### 线程安全机制
```python
# AppServerClient 中的锁
self._lock = threading.Lock()              # 保护 _write_message
self._turn_consumer_lock = threading.Lock() # 保护 _active_turn_consumer

# TurnHandle.stream() 中的使用
self._client.acquire_turn_consumer(self.id)
try:
    while True:
        event = self._client.next_notification()
        yield event
        # ... 检查完成条件
finally:
    self._client.release_turn_consumer(self.id)
```

## 依赖与外部交互

### Python 标准库
- `sys`, `pathlib`: 路径处理

### 第三方依赖
- `codex_app_server`: SDK 主包
  - `Codex`: 同步 SDK 入口类
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
   - 虽然使用了 `with` 语句，但如果初始化阶段抛出异常，需要确保清理
   - `Codex.__init__` 已处理此情况（try-except 块中关闭客户端）

3. **模型版本硬编码**
   - `"gpt-5.4"` 是硬编码的模型标识符
   - 如果该模型不可用，示例将失败
   - **建议**: 从环境变量或配置读取模型名称

4. **并发限制**
   - `TurnHandle.stream()` 使用 `acquire_turn_consumer()` 限制并发
   - 同时只能有一个活跃的 Turn 消费者
   - 尝试并发流式处理会抛出 `RuntimeError`

### 边界情况

1. **空结果处理**
   - `assistant_text_from_turn()` 在 `persisted_turn` 为 None 时返回空字符串
   - 示例中未显式检查此情况

2. **网络/服务不可用**
   - 如果 Codex CLI 未安装或不在 PATH 中，`start()` 会失败
   - 错误信息通过 `FileNotFoundError` 抛出，提示安装 `codex-cli-bin`

3. **stderr 处理**
   - 客户端启动 `_stderr_drain_thread` 后台线程读取 stderr
   - 最多保留 400 行 stderr 输出用于错误诊断

### 改进建议

1. **添加错误处理示例**
```python
with Codex(config=runtime_config()) as codex:
    try:
        thread = codex.thread_start(model="gpt-5.4", ...)
        result = thread.turn(TextInput("...")).run()
        if result.status == TurnStatus.failed:
            print(f"Turn failed: {result.error}")
            return
    except Exception as e:
        print(f"Error: {e}")
        raise
```

2. **展示更多 Turn 参数**
   - 当前仅展示 `model` 和 `config`，可添加 `approval_policy`、`sandbox` 等参数示例

3. **添加超时控制**
   - 使用 `threading.Timer` 或信号机制实现超时

4. **模型选择动态化**
```python
import os
model = os.getenv("CODEX_MODEL", "gpt-5.4")
thread = codex.thread_start(model=model, ...)
```

5. **与异步版本对比注释**
   - 添加注释说明与 `async.py` 的关键差异（无 `await`、使用 `with` 而非 `async with`）

### 测试覆盖

相关测试位于：
- `sdk/python/tests/test_public_api_runtime_behavior.py`: 测试 `Codex`, `Thread`, `TurnHandle`
- `sdk/python/tests/test_client_rpc_methods.py`: 测试 RPC 方法调用

关键测试用例：
- `test_turn_run_returns_completed_turn_payload`: 验证同步运行流程
- `test_turn_stream_rejects_second_active_consumer`: 验证并发限制
- `test_thread_run_accepts_string_input_and_returns_run_result`: 验证字符串输入处理
- `test_thread_run_raises_on_failed_turn`: 验证失败 Turn 的异常抛出

### 与异步版本的差异

| 特性 | sync.py | async.py |
|------|---------|----------|
| 上下文管理器 | `with` | `async with` |
| 调用方式 | 直接调用 | `await` 调用 |
| 内部实现 | 直接调用 `AppServerClient` | 通过 `asyncio.to_thread()` 包装 |
| 并发能力 | 阻塞式 | 支持协程并发 |
| 适用场景 | 简单脚本、Jupyter | 高并发、Web 服务 |
