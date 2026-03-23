# sdk_walkthrough.ipynb 深度研究文档

## 概述

`sdk_walkthrough.ipynb` 是 Codex Python SDK 的 Jupyter Notebook 交互式教程，位于 `sdk/python/notebooks/` 目录下。它提供了从基础到高级的完整 SDK 使用示例，是开发者学习和理解 Codex Python SDK 的核心入口文档。

---

## 1. 场景与职责

### 1.1 定位与目标受众

| 维度 | 说明 |
|------|------|
| **目标用户** | Python 开发者、AI 应用构建者、需要集成 Codex 能力的工程师 |
| **使用场景** | 交互式学习 SDK API、原型验证、功能探索、团队内部培训 |
| **前置要求** | Python >= 3.10，已配置 Codex 认证/会话 |
| **执行环境** | Jupyter Notebook / JupyterLab / VS Code Notebook |

### 1.2 核心职责

1. **教学演示**：通过可执行的代码单元格展示 SDK 的完整功能矩阵
2. **环境引导**：自动发现和配置本地 SDK 开发环境（Cell 1 的 bootstrap 逻辑）
3. **API 覆盖**：展示同步/异步客户端、线程生命周期、多模态输入、流式控制等全部特性
4. **最佳实践**：演示错误处理、重试机制、资源清理等生产级模式

### 1.3 与周边组件的关系

```
sdk_walkthrough.ipynb
├── 依赖注入: _runtime_setup.py (运行时自动安装 codex-cli-bin)
├── 工具函数: examples/_bootstrap.py (共享的辅助函数)
├── SDK 源码: src/codex_app_server/ (被演示的核心库)
├── 生成模型: src/codex_app_server/generated/v2_all.py (底层协议模型)
└── 后端服务: codex-rs/app-server/ (JSON-RPC 服务端)
```

---

## 2. 功能点目的

### 2.1 Notebook 结构总览（11 个代码单元格）

| Cell | 主题 | 目的 | 关键 API |
|------|------|------|----------|
| 1 | 环境引导 | 自动发现 SDK 路径、安装运行时依赖 | `_runtime_setup.ensure_runtime_package_installed` |
| 2 | 公共导入 | 展示 SDK 公共 API 表面 | `Codex`, `AsyncCodex`, `TextInput`, `ImageInput` 等 |
| 3 | 同步简单对话 | 最基础的用例：创建线程、执行 Turn | `Codex.thread_start()`, `thread.turn().run()` |
| 4 | 多轮连续性 | 展示同一线程内的多轮对话能力 | 复用 `thread` 对象多次调用 `turn()` |
| 5 | 线程生命周期 | 完整的线程 CRUD 和分支操作 | `thread_resume`, `thread_archive`, `thread_fork`, `compact` |
| 5b | Turn 参数全景 | 演示所有可选 Turn 参数 | `approval_policy`, `sandbox_policy`, `output_schema` 等 |
| 5c | 智能模型选择 | 动态选择最高能力模型和推理强度 | `codex.models()`, `ReasoningEffort` |
| 6 | 远程图片多模态 | 展示远程图片 URL 输入 | `ImageInput(url)` |
| 7 | 本地图片多模态 | 展示本地图片文件输入 | `LocalImageInput(path)` |
| 8 | 重试模式 | 演示过载保护重试机制 | `retry_on_overload()` |
| 9 | 异步生命周期 | Cell 5 的异步版本 | `AsyncCodex`, `async with` |
| 10 | 异步 Turn 控制 | 展示 steer 和 interrupt 能力 | `turn.steer()`, `turn.interrupt()`, `turn.stream()` |

### 2.2 各功能点的设计意图

#### Cell 1: 环境引导（自举机制）

**目的**：解决 Notebook 执行时的环境发现难题

**核心逻辑**：
- 多层级 SDK 路径探测：从当前工作目录向上遍历，查找 `sdk/python` 目录
- 环境变量兜底：支持 `CODEX_PYTHON_SDK_DIR` 手动指定
- 运行时自动安装：调用 `_runtime_setup.py` 确保 `codex-cli-bin` 已安装

**关键代码路径**：
```python
# sdk/python/notebooks/sdk_walkthrough.ipynb Cell 1
repo_python_dir = _find_sdk_python_dir(Path.cwd())
runtime_version = ensure_runtime_package_installed(sys.executable, repo_python_dir)
```

#### Cell 3-4: 基础对话模式

**目的**：展示 SDK 的黄金路径（Golden Path）

**设计哲学**：
- 同步优先：降低异步认知负担
- 上下文管理器：`with Codex() as codex:` 确保资源清理
- 链式 API：`thread.turn().run()` 的流畅接口

#### Cell 5: 线程生命周期

**目的**：完整展示线程的状态机操作

**状态转换**：
```
thread_start() → [active] → thread_archive() → [archived]
                    ↓
              thread_fork() → [new branch]
                    ↓
              compact() → [compacted]
```

**异常处理模式**：每个可选操作都包裹在 try-except 中，演示防御性编程

#### Cell 5b-5c: 高级参数配置

**目的**：展示生产环境所需的精细控制能力

**关键参数类别**：
| 类别 | 参数 | 用途 |
|------|------|------|
| 安全策略 | `approval_policy`, `sandbox_policy` | 控制命令执行审批和沙箱权限 |
| 模型配置 | `model`, `effort`, `personality` | 调整模型行为和推理强度 |
| 输出控制 | `output_schema` | 强制 JSON Schema 结构化输出 |
| 上下文 | `cwd`, `summary` | 工作目录和推理摘要 |

#### Cell 6-7: 多模态输入

**目的**：展示文本+图像的混合输入能力

**输入类型映射**：
```python
# sdk/python/src/codex_app_server/_inputs.py
InputItem = TextInput | ImageInput | LocalImageInput | SkillInput | MentionInput
```

**Wire 格式转换**：
- `TextInput` → `{"type": "text", "text": ...}`
- `ImageInput` → `{"type": "image", "url": ...}`
- `LocalImageInput` → `{"type": "localImage", "path": ...}`

#### Cell 8: 重试机制

**目的**：演示瞬态故障恢复

**实现原理**：
```python
# sdk/python/src/codex_app_server/retry.py
def retry_on_overload(op, *, max_attempts=3, initial_delay_s=0.25, 
                      max_delay_s=2.0, jitter_ratio=0.2)
```

- 指数退避：delay 每次翻倍，直到 max_delay_s
- 抖动：±20% 随机偏移避免惊群效应
- 错误过滤：仅重试 `ServerBusyError` 和 `is_retryable_error()` 认定的错误

#### Cell 9-10: 异步 API

**目的**：展示异步编程范式和高阶控制能力

**关键差异**：
| 特性 | 同步 (Codex) | 异步 (AsyncCodex) |
|------|-------------|-------------------|
| 初始化 | 构造函数中立即执行 | 延迟初始化（`_ensure_initialized()`） |
| 上下文管理 | `with` | `async with` |
| Turn 控制 | `turn.run()` 阻塞 | `await turn.run()` 可中断 |
| 流式消费 | `for event in stream()` | `async for event in stream()` |

**Steer/Interrupt 机制**：
- `steer()`：在 Turn 执行期间发送额外输入进行引导
- `interrupt()`：强制终止正在执行的 Turn

---

## 3. 具体技术实现

### 3.1 关键流程

#### 3.1.1 SDK 初始化流程

```
Codex() 构造函数
├── AppServerClient.start()
│   ├── resolve_codex_bin()          # 定位 codex 二进制
│   │   ├── 优先使用 config.codex_bin
│   │   └── 否则调用 _installed_codex_path()
│   └── subprocess.Popen()           # 启动 app-server 子进程
│       ├── stdin/stdout/stderr 管道
│       └── 启动 stderr drain 线程
├── initialize()                     # JSON-RPC 握手
│   ├── request("initialize", ...)   # 发送客户端信息
│   └── notify("initialized", None)  # 确认初始化完成
└── _validate_initialize()           # 验证响应元数据
    ├── 解析 userAgent
    └── 确保 serverInfo 完整性
```

#### 3.1.2 Turn 执行流程（同步）

```
thread.turn(TextInput("...")).run()
├── turn_start()                     # JSON-RPC request
│   ├── _to_wire_input()             # 转换输入为 wire 格式
│   └── request("turn/start", ...)   # 获取 turn_id
├── stream()                         # 开始消费通知
│   ├── acquire_turn_consumer()      # 获取独占锁（实验性限制）
│   └── next_notification()          # 循环读取消息
│       ├── _read_message()          # 从 stdout 读取 JSON
│       └── _coerce_notification()   # 转换为 Pydantic 模型
└── _collect_run_result()            # 聚合结果
    ├── ItemCompletedNotification    # 收集 items
    ├── ThreadTokenUsageUpdated      # 收集 usage
    └── TurnCompletedNotification    # 确定完成状态
```

#### 3.1.3 异步 Turn 执行流程

```
await thread.turn(TextInput("...")).run()
├── AsyncAppServerClient._call_sync()
│   ├── asyncio.Lock 获取传输锁
│   └── asyncio.to_thread()          # 在线程池中执行同步调用
└── 流式消费使用 AsyncIterator
    └── 通过 _next_from_iterator() 桥接同步迭代器
```

### 3.2 数据结构

#### 3.2.1 核心类层次

```python
# sdk/python/src/codex_app_server/api.py

Codex                              # 同步入口
├── _client: AppServerClient       # 底层 JSON-RPC 客户端
├── metadata: InitializeResponse   # 服务器元数据
└── thread_*() 方法                # 线程生命周期管理

AsyncCodex                         # 异步入口
├── _client: AsyncAppServerClient  # 异步包装器
├── _init_lock: asyncio.Lock       # 延迟初始化锁
└── 对应的 async 方法

Thread / AsyncThread               # 线程操作封装
├── id: str                        # 线程标识
├── turn() → TurnHandle            # 创建 Turn
├── run() → RunResult              # 便捷执行
└── read()/set_name()/compact()

TurnHandle / AsyncTurnHandle       # Turn 控制句柄
├── id: str                        # Turn 标识
├── steer()                        # 引导执行
├── interrupt()                    # 中断执行
├── stream() → Iterator[Notification]  # 流式事件
└── run() → Turn                   # 等待完成
```

#### 3.2.2 输入类型系统

```python
# sdk/python/src/codex_app_server/_inputs.py

@dataclass
class TextInput:
    text: str

@dataclass
class ImageInput:
    url: str

@dataclass
class LocalImageInput:
    path: str

InputItem = TextInput | ImageInput | LocalImageInput | SkillInput | MentionInput
Input = list[InputItem] | InputItem
RunInput = Input | str  # 支持直接传字符串简写
```

#### 3.2.3 生成模型（Generated Models）

由 `datamodel-codegen` 从 JSON Schema 自动生成：

```python
# sdk/python/src/codex_app_server/generated/v2_all.py

class TurnStartParams(BaseModel):
    thread_id: Annotated[str, Field(alias="threadId")]
    input: list[dict]
    approval_policy: AskForApproval | None = None
    effort: ReasoningEffort | None = None
    model: str | None = None
    output_schema: dict | None = None
    # ... 其他参数

class TurnCompletedNotification(BaseModel):
    turn: Turn
    
class Turn(BaseModel):
    id: str
    status: TurnStatus
    error: ErrorNotification | None = None
    # ...
```

**命名转换规则**：
- Python 字段：snake_case
- Wire 传输：camelCase（通过 `Field(alias="...")` 映射）

### 3.3 协议与通信

#### 3.3.1 JSON-RPC v2 over stdio

```
请求格式：
{"id": "uuid", "method": "turn/start", "params": {...}}

响应格式：
{"id": "uuid", "result": {...}}

错误格式：
{"id": "uuid", "error": {"code": -32602, "message": "...", "data": {...}}}

通知格式（服务端推送）：
{"method": "turn/completed", "params": {...}}
```

#### 3.3.2 通知类型注册表

```python
# sdk/python/src/codex_app_server/generated/notification_registry.py
NOTIFICATION_MODELS = {
    "turn/completed": TurnCompletedNotification,
    "item/agentMessage/delta": AgentMessageDeltaNotification,
    "thread/tokenUsage/updated": ThreadTokenUsageUpdatedNotification,
    # ... 30+ 种通知类型
}
```

#### 3.3.3 服务端请求处理

```python
# sdk/python/src/codex_app_server/client.py

def _handle_server_request(self, msg: dict) -> JsonObject:
    """处理服务端发起的请求（如审批请求）"""
    method = msg["method"]
    params = msg.get("params")
    return self._approval_handler(method, params)

def _default_approval_handler(self, method: str, params: JsonObject | None) -> JsonObject:
    """默认自动接受所有审批请求"""
    if method == "item/commandExecution/requestApproval":
        return {"decision": "accept"}
    if method == "item/fileChange/requestApproval":
        return {"decision": "accept"}
    return {}
```

### 3.4 关键命令

#### 3.4.1 运行时安装命令

```python
# sdk/python/_runtime_setup.py

# 从 GitHub Release 下载并安装 codex-cli-bin
ensure_runtime_package_installed(
    python_executable=sys.executable,
    sdk_python_dir=Path(...),
)

# 流程：
# 1. 检查当前是否已安装正确版本
# 2. 下载平台对应归档（tar.gz / zip）
# 3. 解压提取 codex 二进制
# 4. pip install --force-reinstall 到目标环境
```

#### 3.4.2 类型生成命令

```bash
# sdk/python/scripts/update_sdk_artifacts.py generate-types
# 从 Rust 导出的 JSON Schema 生成 Pydantic 模型
datamodel-codegen \
    --input codex_app_server_protocol.v2.schemas.json \
    --output src/codex_app_server/generated/v2_all.py \
    --output-model-type pydantic_v2.BaseModel
```

---

## 4. 关键代码路径与文件引用

### 4.1 Notebook 相关文件

| 文件 | 职责 |
|------|------|
| `sdk/python/notebooks/sdk_walkthrough.ipynb` | 主 Notebook 文件，包含 11 个演示单元格 |
| `sdk/python/_runtime_setup.py` | 运行时自动安装逻辑，被 Cell 1 导入使用 |
| `sdk/python/examples/_bootstrap.py` | 共享工具函数（`assistant_text_from_turn`, `find_turn_by_id` 等） |

### 4.2 SDK 核心源码

| 文件 | 职责 |
|------|------|
| `sdk/python/src/codex_app_server/__init__.py` | 公共 API 导出，定义 `__all__` |
| `sdk/python/src/codex_app_server/api.py` | 高级封装：`Codex`, `AsyncCodex`, `Thread`, `TurnHandle` |
| `sdk/python/src/codex_app_server/client.py` | 底层同步客户端：`AppServerClient`，JSON-RPC 实现 |
| `sdk/python/src/codex_app_server/async_client.py` | 异步包装器：`AsyncAppServerClient`，线程池桥接 |
| `sdk/python/src/codex_app_server/_inputs.py` | 输入类型定义和 wire 格式转换 |
| `sdk/python/src/codex_app_server/_run.py` | Turn 结果聚合逻辑：`RunResult`, `_collect_run_result` |
| `sdk/python/src/codex_app_server/retry.py` | 重试机制：`retry_on_overload` |
| `sdk/python/src/codex_app_server/errors.py` | 异常层次结构：`AppServerError`, `ServerBusyError` 等 |
| `sdk/python/src/codex_app_server/models.py` | 手动维护的 Pydantic 模型：`InitializeResponse`, `Notification` |

### 4.3 生成代码

| 文件 | 职责 |
|------|------|
| `sdk/python/src/codex_app_server/generated/v2_all.py` | 从 JSON Schema 生成的完整协议模型（~3500 行） |
| `sdk/python/src/codex_app_server/generated/notification_registry.py` | 通知方法到模型的映射表 |

### 4.4 后端协议（Rust）

| 文件 | 职责 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 端 v2 协议定义，作为 Schema 源 |
| `codex-rs/app-server-protocol/src/bin/write_schema_fixtures.rs` | 导出 JSON Schema 的工具 |
| `codex-rs/app-server/src/lib.rs` | app-server 服务端实现 |

### 4.5 测试文件

| 文件 | 职责 |
|------|------|
| `sdk/python/tests/test_public_api_signatures.py` | 验证公共 API 签名一致性 |
| `sdk/python/tests/test_client_rpc_methods.py` | 验证 RPC 方法调用正确性 |
| `sdk/python/tests/test_async_client_behavior.py` | 异步客户端行为测试 |

### 4.6 文档文件

| 文件 | 职责 |
|------|------|
| `sdk/python/README.md` | SDK 概览和快速开始 |
| `sdk/python/docs/getting-started.md` | 详细教程 |
| `sdk/python/docs/api-reference.md` | API 参考文档 |
| `sdk/python/docs/faq.md` | 常见问题解答 |
| `sdk/python/examples/README.md` | 示例代码索引 |

---

## 5. 依赖与外部交互

### 5.1 Python 依赖

```toml
# sdk/python/pyproject.toml (推断)
[dependencies]
python = ">=3.10"
pydantic = "*"           # 数据验证和序列化
```

### 5.2 运行时依赖

| 组件 | 版本 | 来源 |
|------|------|------|
| codex-cli-bin | 0.116.0-alpha.1 (PINNED_RUNTIME_VERSION) | GitHub Release |

**安装机制**：
- 自动从 `https://github.com/openai/codex/releases/download/rust-v{version}/` 下载
- 支持平台：macOS (arm64/x86_64), Linux (arm64/x86_64), Windows (arm64/x86_64)
- 支持认证：GH_TOKEN / GITHUB_TOKEN 环境变量，或已登录的 `gh` CLI

### 5.3 外部服务交互

```
sdk_walkthrough.ipynb
└── Codex() / AsyncCodex()
    └── subprocess.Popen([codex_bin, "app-server", "--listen", "stdio://"])
        └── codex app-server (Rust 二进制)
            ├── JSON-RPC over stdio
            │   ├── 请求: initialize, thread/start, turn/start, etc.
            │   └── 通知: turn/completed, item/agentMessage/delta, etc.
            ├── OpenAI API (模型推理)
            ├── 文件系统操作（沙箱内）
            └── 可选：MCP 服务器、技能执行
```

### 5.4 环境变量

| 变量 | 用途 |
|------|------|
| `CODEX_PYTHON_SDK_DIR` | 手动指定 SDK 路径，覆盖自动发现 |
| `GH_TOKEN` / `GITHUB_TOKEN` | GitHub API 认证，用于下载运行时 |

---

## 6. 风险、边界与改进建议

### 6.1 已知限制与风险

#### 6.1.1 实验性限制

| 限制 | 影响 | 缓解措施 |
|------|------|----------|
| 单 Turn 消费者限制 | 同一客户端实例只能有一个活跃的 `stream()` 或 `run()` | 使用多个 `Codex()` 实例或串行执行 |
| 线程锁竞争 | `acquire_turn_consumer()` 会抛出 `RuntimeError` | 确保 Turn 完成后再启动新 Turn |
| 异步初始化延迟 | `AsyncCodex` 首次调用时才初始化 | 使用 `async with` 确保预热 |

#### 6.1.2 环境依赖风险

| 风险 | 描述 | 缓解 |
|------|------|------|
| 运行时下载失败 | 网络问题或 GitHub API 限制 | 预安装 `codex-cli-bin`，或配置代理 |
| 版本不匹配 | SDK 与运行时版本不兼容 | 使用相同版本发布，遵循 `PINNED_RUNTIME_VERSION` |
| 认证缺失 | 本地 Codex 会话未配置 | 先运行 `codex login` 配置认证 |

#### 6.1.3 Notebook 特定风险

| 风险 | 描述 | 缓解 |
|------|------|------|
| 内核状态残留 | 多次执行 Cell 1 可能导致模块重复导入 | Cell 1 已包含 `sys.modules.pop` 清理逻辑 |
| 工作目录漂移 | Jupyter 内核 cwd 可能不是预期路径 | Cell 1 的 `_find_sdk_python_dir` 多路径探测 |
| 资源泄漏 | Notebook 异常终止时 `codex` 子进程可能残留 | 使用上下文管理器，定期 `killall codex` 清理 |

### 6.2 边界条件

#### 6.2.1 输入边界

```python
# 最大输入限制（由后端决定，SDK 仅透传）
- 单条文本输入长度：受模型上下文窗口限制
- 图片大小：受 OpenAI Vision API 限制
- 并发 Turn：当前限制为 1（实验性）
```

#### 6.2.2 超时边界

| 操作 | 默认超时 | 可配置性 |
|------|----------|----------|
| Turn 执行 | 无默认，依赖模型响应 | 通过 `stream()` 自行实现超时逻辑 |
| 运行时下载 | 无 | 依赖 urllib 默认 |
| JSON-RPC 请求 | 无 | 阻塞等待响应 |

### 6.3 改进建议

#### 6.3.1 Notebook 体验改进

1. **添加进度指示**：长 Turn 执行时显示 spinner 或进度条
   ```python
   # 建议添加
   from tqdm.notebook import tqdm
   # 在 stream() 中包装进度显示
   ```

2. **可视化输出**：将模型响应渲染为 Markdown 而非纯文本
   ```python
   from IPython.display import Markdown, display
   display(Markdown(assistant_text))
   ```

3. **交互式小部件**：使用 `ipywidgets` 创建模型选择器、参数滑块

4. **错误恢复指引**：在异常处理中提供更具体的故障排除步骤

#### 6.3.2 SDK 功能改进

1. **原生超时支持**：
   ```python
   # 建议添加
   turn.run(timeout=30.0)  # 30 秒超时
   ```

2. **并发 Turn 支持**：移除实验性的单消费者限制

3. **更智能的重试**：
   - 区分可重试错误（网络瞬态）和不可重试错误（参数无效）
   - 支持自定义重试策略

4. **调试工具**：
   ```python
   # 建议添加
   codex.debug_log = True  # 输出详细 RPC 日志
   ```

#### 6.3.3 文档改进

1. **交互式文档**：将 Notebook 发布为可在线运行的 Binder 环境
2. **API 对比表**：同步 vs 异步 API 的详细对比
3. **故障排除指南**：常见错误代码和解决方案

#### 6.3.4 测试覆盖建议

1. **Notebook 自动化测试**：使用 `nbval` 或 `testbook` 验证 Notebook 可执行性
2. **多平台 CI**：在 macOS、Linux、Windows 上测试运行时安装
3. **离线模式测试**：测试预安装运行时的场景

---

## 7. 附录

### 7.1 术语表

| 术语 | 定义 |
|------|------|
| Turn | 模型的一次执行，包含输入处理和输出生成 |
| Thread | 对话状态容器，包含多个 Turn 的历史 |
| app-server | Codex 的 JSON-RPC 服务端，提供 AI 能力 |
| Wire 格式 | 网络传输使用的序列化格式（JSON-RPC） |
| Steer | 在 Turn 执行期间发送额外输入进行引导 |
| Compact | 压缩线程历史，减少上下文窗口占用 |

### 7.2 相关链接

- SDK 目录：`sdk/python/`
- Notebook 路径：`sdk/python/notebooks/sdk_walkthrough.ipynb`
- 示例目录：`sdk/python/examples/`
- 生成模型：`sdk/python/src/codex_app_server/generated/v2_all.py`

### 7.3 版本信息

| 组件 | 版本 |
|------|------|
| SDK 版本 | 0.2.0 (`codex_app_server.__version__`) |
| 运行时版本 | 0.116.0-alpha.1 (`PINNED_RUNTIME_VERSION`) |
| 目标协议 | app-server JSON-RPC v2 |
| Python 要求 | >= 3.10 |
