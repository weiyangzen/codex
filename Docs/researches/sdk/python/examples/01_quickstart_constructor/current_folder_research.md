# SDK Python Examples 01_quickstart_constructor 研究文档

## 1. 场景与职责

### 1.1 定位与目标

`01_quickstart_constructor` 是 Codex Python SDK 的**入门级示例目录**，其核心目标是向开发者展示如何使用构造函数方式（Constructor Pattern）快速初始化并使用 Codex SDK 进行 AI 对话。

该示例目录包含两个并行实现：
- `sync.py` - 同步/阻塞式 API 使用示例
- `async.py` - 异步/非阻塞式 API 使用示例

### 1.2 使用场景

| 场景 | 说明 |
|------|------|
| 首次体验 | 新用户了解 SDK 最基本用法的入口 |
| 快速验证 | 验证 SDK 安装和环境配置是否正确 |
| 开发模板 | 作为实际应用开发的代码模板 |
| 教学演示 | 展示同步 vs 异步 API 的对比 |

### 1.3 目录结构

```
sdk/python/examples/01_quickstart_constructor/
├── sync.py   # 同步版本示例
└── async.py  # 异步版本示例
```

---

## 2. 功能点目的

### 2.1 核心功能演示

该示例演示以下关键功能点：

1. **SDK 初始化** - 通过 `Codex()` / `AsyncCodex()` 构造函数创建客户端实例
2. **配置传递** - 通过 `AppServerConfig` 传递运行时配置
3. **线程创建** - 使用 `thread_start()` 创建新对话线程
4. **模型配置** - 指定模型 (`gpt-5.4`) 和推理参数 (`model_reasoning_effort`)
5. **执行对话** - 使用 `thread.run()` 执行单轮对话
6. **结果获取** - 获取并展示对话结果和元数据

### 2.2 代码功能对比

| 特性 | sync.py | async.py |
|------|---------|----------|
| 客户端类 | `Codex` | `AsyncCodex` |
| 上下文管理器 | `with` | `async with` |
| 线程创建 | `codex.thread_start()` | `await codex.thread_start()` |
| 对话执行 | `thread.run()` | `await thread.run()` |
| 运行方式 | 直接运行 | `asyncio.run(main())` |

### 2.3 示例输出

示例执行后会输出：
- `Server:` - 服务器名称和版本信息
- `Items:` - 返回的 ThreadItem 数量
- `Text:` - AI 的最终回复文本

---

## 3. 具体技术实现

### 3.1 关键流程

#### 3.1.1 同步版本执行流程 (sync.py)

```python
# 1. 引导阶段：确保本地 SDK 源码可用
from _bootstrap import ensure_local_sdk_src, runtime_config, server_label
ensure_local_sdk_src()

# 2. 导入 Codex 类
from codex_app_server import Codex

# 3. 使用上下文管理器初始化
with Codex(config=runtime_config()) as codex:
    # 4. 打印服务器信息
    print("Server:", server_label(codex.metadata))
    
    # 5. 创建线程并配置模型
    thread = codex.thread_start(
        model="gpt-5.4", 
        config={"model_reasoning_effort": "high"}
    )
    
    # 6. 执行对话
    result = thread.run("Say hello in one sentence.")
    
    # 7. 输出结果
    print("Items:", len(result.items))
    print("Text:", result.final_response)
```

#### 3.1.2 异步版本执行流程 (async.py)

```python
async def main() -> None:
    async with AsyncCodex(config=runtime_config()) as codex:
        print("Server:", server_label(codex.metadata))
        
        thread = await codex.thread_start(
            model="gpt-5.4", 
            config={"model_reasoning_effort": "high"}
        )
        result = await thread.run("Say hello in one sentence.")
        
        print("Items:", len(result.items))
        print("Text:", result.final_response)

if __name__ == "__main__":
    asyncio.run(main())
```

### 3.2 核心数据结构

#### 3.2.1 AppServerConfig (配置对象)

```python
@dataclass(slots=True)
class AppServerConfig:
    codex_bin: str | None = None           # Codex 二进制文件路径
    launch_args_override: tuple[str, ...] | None = None  # 启动参数覆盖
    config_overrides: tuple[str, ...] = ()  # 配置覆盖项
    cwd: str | None = None                  # 工作目录
    env: dict[str, str] | None = None       # 环境变量
    client_name: str = "codex_python_sdk"   # 客户端名称
    client_title: str = "Codex Python SDK"  # 客户端标题
    client_version: str = "0.2.0"           # 客户端版本
    experimental_api: bool = True           # 是否启用实验性 API
```

#### 3.2.2 RunResult (运行结果)

```python
@dataclass(slots=True)
class RunResult:
    final_response: str | None   # AI 最终回复文本
    items: list[ThreadItem]      # 线程项目列表
    usage: ThreadTokenUsage | None  # Token 使用统计
```

#### 3.2.3 InitializeResponse (初始化响应)

```python
class InitializeResponse(BaseModel):
    serverInfo: ServerInfo | None = None    # 服务器信息
    userAgent: str | None = None            # User-Agent 字符串
    platformFamily: str | None = None       # 平台家族
    platformOs: str | None = None           # 操作系统
```

### 3.3 通信协议

#### 3.3.1 JSON-RPC v2 over stdio

SDK 通过标准输入输出与 `codex app-server` 进程通信，使用 JSON-RPC 2.0 协议：

**请求格式：**
```json
{
    "id": "uuid-string",
    "method": "thread/start",
    "params": {
        "model": "gpt-5.4",
        "config": {"modelReasoningEffort": "high"}
    }
}
```

**响应格式：**
```json
{
    "id": "uuid-string",
    "result": {
        "thread": {"id": "thread-xxx"}
    }
}
```

#### 3.3.2 关键 RPC 方法

| 方法 | 用途 |
|------|------|
| `initialize` | 客户端/服务器握手初始化 |
| `thread/start` | 创建新对话线程 |
| `turn/start` | 启动新一轮对话 |
| `turn/completed` | 对话完成通知 |

### 3.4 启动命令

当 `launch_args_override` 为 `None` 时，SDK 自动构建启动命令：

```python
args = [
    str(codex_bin),           # /path/to/codex
    "--config", "key=value",  # 配置覆盖项（可多个）
    "app-server",             # 子命令
    "--listen", "stdio://"    # 监听 stdio
]
```

---

## 4. 关键代码路径与文件引用

### 4.1 调用链分析

```
examples/01_quickstart_constructor/sync.py
    ↓
_bootstrap.py:runtime_config() → AppServerConfig()
    ↓
codex_app_server/api.py:Codex.__init__()
    ↓
codex_app_server/client.py:AppServerClient.__init__()
    ↓
codex_app_server/client.py:AppServerClient.start()
    ↓
subprocess.Popen([codex_bin, "app-server", "--listen", "stdio://"])
```

### 4.2 核心文件引用

| 文件路径 | 职责 |
|----------|------|
| `sdk/python/examples/01_quickstart_constructor/sync.py` | 同步示例入口 |
| `sdk/python/examples/01_quickstart_constructor/async.py` | 异步示例入口 |
| `sdk/python/examples/_bootstrap.py` | 示例引导工具（路径设置、运行时安装） |
| `sdk/python/_runtime_setup.py` | 运行时包安装管理 |
| `sdk/python/src/codex_app_server/__init__.py` | SDK 公共 API 导出 |
| `sdk/python/src/codex_app_server/api.py` | 高级 API 实现（Codex, Thread, TurnHandle） |
| `sdk/python/src/codex_app_server/client.py` | 同步 JSON-RPC 客户端 |
| `sdk/python/src/codex_app_server/async_client.py` | 异步客户端包装器 |
| `sdk/python/src/codex_app_server/models.py` | 核心数据模型 |
| `sdk/python/src/codex_app_server/_run.py` | 运行结果收集逻辑 |
| `sdk/python/src/codex_app_server/_inputs.py` | 输入类型定义和转换 |
| `sdk/python/src/codex_app_server/errors.py` | 异常类型定义 |
| `sdk/python/src/codex_app_server/retry.py` | 重试逻辑 |
| `sdk/python/src/codex_app_server/generated/v2_all.py` | 自动生成的 Pydantic 模型 |

### 4.3 类关系图

```
┌─────────────────────────────────────────────────────────────┐
│                        示例层                                │
│  ┌─────────────────┐    ┌─────────────────┐                 │
│  │   sync.py       │    │   async.py      │                 │
│  │   Codex()       │    │   AsyncCodex()  │                 │
│  └────────┬────────┘    └────────┬────────┘                 │
└───────────┼──────────────────────┼──────────────────────────┘
            │                      │
            ▼                      ▼
┌─────────────────────────────────────────────────────────────┐
│                      高级 API 层                             │
│  ┌─────────────────┐    ┌─────────────────┐                 │
│  │     Codex       │◄───│   AsyncCodex    │                 │
│  │  (sync wrapper) │    │ (async wrapper) │                 │
│  └────────┬────────┘    └────────┬────────┘                 │
│           │                      │                          │
│           ▼                      ▼                          │
│  ┌─────────────────┐    ┌─────────────────┐                 │
│  │     Thread      │◄───│   AsyncThread   │                 │
│  └────────┬────────┘    └────────┬────────┘                 │
│           │                      │                          │
│           ▼                      ▼                          │
│  ┌─────────────────┐    ┌─────────────────┐                 │
│  │   TurnHandle    │◄───│ AsyncTurnHandle │                 │
│  └─────────────────┘    └─────────────────┘                 │
└─────────────────────────────────────────────────────────────┘
            │                      │
            ▼                      ▼
┌─────────────────────────────────────────────────────────────┐
│                     底层客户端层                             │
│  ┌─────────────────┐    ┌─────────────────┐                 │
│  │ AppServerClient │◄───│AsyncAppServerClient│              │
│  │  (JSON-RPC)     │    │  (thread pool)  │                 │
│  └────────┬────────┘    └─────────────────┘                 │
└───────────┼──────────────────────────────────────────────────┘
            │
            ▼
┌─────────────────────────────────────────────────────────────┐
│                    子进程通信层                              │
│              subprocess.Popen(stdio)                        │
│                      codex app-server                       │
└─────────────────────────────────────────────────────────────┘
```

---

## 5. 依赖与外部交互

### 5.1 直接依赖

| 依赖 | 用途 | 版本要求 |
|------|------|----------|
| `pydantic` | 数据验证和序列化 | >=2.12 |
| `codex-cli-bin` | Codex 运行时二进制 | 0.116.0-alpha.1 (固定) |

### 5.2 运行时依赖解析

#### 5.2.1 本地开发模式

通过 `_bootstrap.py:ensure_local_sdk_src()` 将 `sdk/python/src` 添加到 `sys.path`，允许不安装直接使用源码。

#### 5.2.2 运行时包安装

通过 `_runtime_setup.py:ensure_runtime_package_installed()` 自动：
1. 检测当前平台（Darwin/Linux/Windows, x86_64/aarch64）
2. 从 GitHub Releases 下载对应平台的 `codex` 二进制包
3. 解压并安装为 Python 包 `codex-cli-bin`

支持的下载源优先级：
1. 直接下载（browser_download_url）
2. GitHub API（带认证）
3. GitHub CLI (`gh release download`)

### 5.3 外部交互

#### 5.3.1 子进程启动

```python
self._proc = subprocess.Popen(
    args,                    # [codex_bin, "app-server", "--listen", "stdio://"]
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    cwd=self.config.cwd,
    env=env,
    bufsize=1,
)
```

#### 5.3.2 与 OpenAI API 的间接交互

Codex CLI 内部会连接 OpenAI API（或配置的其他提供商），SDK 本身不直接处理 API 认证，而是通过 Codex CLI 进程代理。

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 并发限制

```python
# client.py:288-296
with self._turn_consumer_lock:
    if self._active_turn_consumer is not None:
        raise RuntimeError(
            "Concurrent turn consumers are not yet supported in the experimental SDK."
        )
```

**风险：** 同一客户端实例不支持并发对话流，尝试同时启动多个 turn 会抛出 RuntimeError。

#### 6.1.2 初始化失败资源泄漏

虽然代码有 try-finally 保护，但在某些边缘情况下（如子进程启动后立即崩溃），stderr 读取线程可能无法正常清理。

#### 6.1.3 平台兼容性

| 平台 | 支持状态 | 备注 |
|------|----------|------|
| macOS ARM64 | ✅ 完全支持 | 主要开发平台 |
| macOS x86_64 | ✅ 支持 | 通过 Rosetta 2 |
| Linux x86_64 | ✅ 支持 | musl 静态链接 |
| Linux ARM64 | ✅ 支持 | musl 静态链接 |
| Windows x86_64 | ✅ 支持 | MSVC 构建 |
| Windows ARM64 | ✅ 支持 | 实验性 |

#### 6.1.4 运行时版本锁定

```python
# _runtime_setup.py:19
PINNED_RUNTIME_VERSION = "0.116.0-alpha.1"
```

SDK 与特定版本的 Codex CLI 绑定，升级 CLI 可能需要同步更新 SDK。

### 6.2 边界条件

#### 6.2.1 输入处理边界

```python
# _inputs.py:60-62
def _normalize_run_input(input: RunInput) -> Input:
    if isinstance(input, str):
        return TextInput(input)
    return input
```

- 字符串输入自动包装为 `TextInput`
- 复杂输入（图片、技能等）需要显式构造输入对象

#### 6.2.2 结果提取边界

```python
# _run.py:36-48
def _final_assistant_response_from_items(items: list[ThreadItem]) -> str | None:
    # 优先返回 phase=final_answer 的消息
    # 其次返回 phase=None 的最后一条消息
    # 忽略 phase=commentary 的消息
```

**边界：** `final_response` 可能为 `None`，当：
- 对话失败
- 所有消息都是 commentary 类型
- 没有 assistant 消息

### 6.3 改进建议

#### 6.3.1 示例增强

| 建议 | 优先级 | 说明 |
|------|--------|------|
| 添加错误处理示例 | 高 | 展示 try-except 和 retry 用法 |
| 添加配置自定义示例 | 中 | 展示 `AppServerConfig` 各字段用法 |
| 添加多轮对话示例 | 中 | 展示如何在同一线程进行多轮对话 |
| 添加流式输出示例 | 低 | 已在 03_turn_stream_events 中覆盖 |

#### 6.3.2 代码改进

1. **类型注解完善**
   - 部分内部函数使用 `Any` 类型，建议细化

2. **文档字符串**
   - 示例代码缺少文档字符串，建议添加中文/英文注释

3. **配置验证**
   - 建议在 `AppServerConfig` 添加字段验证器，提前发现配置错误

4. **并发支持**
   - 长期建议实现真正的并发 turn 支持，而非全局锁

#### 6.3.3 测试覆盖

当前测试位于 `sdk/python/tests/test_real_app_server_integration.py`：

```python
EXAMPLE_CASES = [
    ("01_quickstart_constructor", "sync.py"),
    ("01_quickstart_constructor", "async.py"),
    # ...
]
```

**建议：**
- 添加单元测试覆盖 `_bootstrap.py` 的边界条件
- 添加 mock 测试验证 JSON-RPC 通信逻辑
- 添加性能测试验证启动时间

### 6.4 相关示例演进路径

对于从 `01_quickstart_constructor` 开始的开发者，建议按以下顺序学习：

```
01_quickstart_constructor  →  02_turn_run  →  03_turn_stream_events
      (基础用法)              (完整 API)        (流式事件)
                ↓
        05_existing_thread  →  06_thread_lifecycle_and_controls
           (线程恢复)              (线程管理)
                ↓
        10_error_handling_and_retry  →  11_cli_mini_app
              (错误处理)                  (完整应用)
```

---

## 7. 附录

### 7.1 版本信息

- SDK 版本: `0.2.0`
- 运行时版本: `0.116.0-alpha.1`
- Python 要求: `>=3.10`
- 协议版本: JSON-RPC v2

### 7.2 相关文档

- `sdk/python/README.md` - SDK 总览
- `sdk/python/docs/api-reference.md` - API 参考
- `sdk/python/docs/faq.md` - 常见问题
- `sdk/python/examples/README.md` - 示例索引
- `docs/getting-started.md` - 入门指南

### 7.3 测试执行

```bash
# 运行特定示例测试
RUN_REAL_CODEX_TESTS=1 pytest tests/test_real_app_server_integration.py::test_real_examples_run_and_assert -k "01_quickstart_constructor"

# 直接运行示例
cd sdk/python
python examples/01_quickstart_constructor/sync.py
python examples/01_quickstart_constructor/async.py
```
