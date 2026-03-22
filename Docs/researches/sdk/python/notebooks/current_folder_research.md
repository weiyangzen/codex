# SDK/Python/Notebooks 深度研究文档

## 目录
- [场景与职责](#场景与职责)
- [功能点目的](#功能点目的)
- [具体技术实现](#具体技术实现)
- [关键代码路径与文件引用](#关键代码路径与文件引用)
- [依赖与外部交互](#依赖与外部交互)
- [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 1.1 目录定位

`sdk/python/notebooks/` 是 **Codex Python SDK** 的交互式文档和教程目录，目前包含核心文件：

- **`sdk_walkthrough.ipynb`**: Jupyter Notebook 格式的完整 SDK 使用教程

### 1.2 核心职责

该目录服务于以下场景：

| 场景 | 说明 |
|------|------|
| **交互式学习** | 提供可执行的代码单元，用户可逐步运行学习 SDK API |
| **功能演示** | 展示从基础到高级的完整功能链条 |
| **快速验证** | 开发者和用户可快速验证 SDK 安装和运行环境 |
| **API 文档补充** | 作为静态文档的补充，提供可运行的示例代码 |

### 1.3 与 SDK 其他部分的关系

```
sdk/python/
├── notebooks/                    # 交互式教程 (本目录)
│   └── sdk_walkthrough.ipynb    # 主 Notebook 文件
├── src/codex_app_server/        # SDK 源码实现
│   ├── api.py                   # 公共 API (Codex, AsyncCodex, Thread, TurnHandle)
│   ├── client.py                # 同步 JSON-RPC 客户端
│   ├── async_client.py          # 异步客户端包装
│   ├── generated/v2_all.py      # 生成的 Pydantic 模型 (6351 行)
│   └── ...
├── examples/                    # 可运行的示例脚本
│   ├── 01_quickstart_constructor/
│   ├── 02_turn_run/
│   └── ... (14 个示例目录)
├── docs/                        # 静态文档
│   ├── getting-started.md
│   ├── api-reference.md
│   └── faq.md
└── tests/                       # 测试套件
```

---

## 功能点目的

### 2.1 Notebook 整体结构

`sdk_walkthrough.ipynb` 包含 **11 个代码单元 (Cells)**，覆盖以下功能领域：

| Cell | 功能 | 目的 |
|------|------|------|
| Cell 1 | 引导与初始化 | 自动定位 SDK 路径、安装运行时依赖、配置 Python 环境 |
| Cell 2 | 导入公共 API | 展示 SDK 的公开导出接口 |
| Cell 3 | 简单同步对话 | 演示最基本的 `Codex()` + `thread_start()` + `turn()` + `run()` 流程 |
| Cell 4 | 多轮对话 | 展示同一 Thread 上的连续多轮交互 |
| Cell 5 | 完整线程生命周期 | 演示 thread_resume, thread_archive, thread_unarchive, thread_fork, compact 等操作 |
| Cell 5b | 完整 Turn 参数 | 展示所有可选 turn 参数的使用 (approval_policy, effort, output_schema 等) |
| Cell 5c | 智能模型选择 | 动态选择最高级模型和最高推理努力度 |
| Cell 6 | 远程图片多模态 | ImageInput + 远程 URL 的多模态对话 |
| Cell 7 | 本地图片多模态 | LocalImageInput + 本地文件路径的多模态对话 |
| Cell 8 | 重试模式 | retry_on_overload 的使用示例 |
| Cell 9 | 异步生命周期 | AsyncCodex 的完整异步 API 演示 |
| Cell 10 | Turn 控制 | steer() 和 interrupt() 的异步控制演示 |

### 2.2 核心功能点详解

#### 2.2.1 环境引导系统 (Cell 1)

**目的**: 解决 Notebook 运行时的环境发现难题

**关键问题**: 
- Notebook 可能从任意工作目录启动
- 需要自动发现 `sdk/python` 目录位置
- 需要自动安装/验证 `codex-cli-bin` 运行时包

**实现策略**:
1. 多层级目录扫描 (当前目录 → 父目录 → 预定义模式)
2. 环境变量回退 (`CODEX_PYTHON_SDK_DIR`)
3. sys.path 回退检查
4. 用户目录边界扫描 (`~/sdk/python`, `~/*/sdk/python` 等)

#### 2.2.2 同步/异步 API 覆盖

**同步 API** (Cells 3-8):
```python
with Codex() as codex:
    thread = codex.thread_start(model='gpt-5.4')
    result = thread.turn(TextInput('...')).run()
```

**异步 API** (Cells 9-10):
```python
async with AsyncCodex() as codex:
    thread = await codex.thread_start(model='gpt-5.4')
    result = await (await thread.turn(TextInput('...'))).run()
```

#### 2.2.3 多模态输入支持

| 输入类型 | 类 | 用途 |
|----------|-----|------|
| 文本 | `TextInput` | 纯文本用户输入 |
| 远程图片 | `ImageInput` | 通过 URL 引用图片 |
| 本地图片 | `LocalImageInput` | 本地文件系统图片 |
| Skill | `SkillInput` | 引用技能/工具 |
| Mention | `MentionInput` | 提及/引用其他实体 |

---

## 具体技术实现

### 3.1 关键流程

#### 3.1.1 SDK 发现流程 (Cell 1)

```python
# 伪代码表示的核心逻辑
def _find_sdk_python_dir(start: Path) -> Path | None:
    # 1. 向上遍历目录树
    for candidate in [start, *start.parents]:
        if _is_sdk_python_dir(candidate):
            return candidate
    
    # 2. 检查 sdk/python 子路径
    for candidate in [start / 'sdk' / 'python', ...]:
        if _is_sdk_python_dir(candidate):
            return candidate
    
    # 3. 环境变量回退
    env_dir = os.environ.get('CODEX_PYTHON_SDK_DIR')
    
    # 4. sys.path 检查
    for entry in sys.path:
        check_sdk_location(Path(entry))
    
    # 5. 用户目录扫描 (bounded depth)
    patterns = ('sdk/python', '*/sdk/python', '*/*/sdk/python', '*/*/*/sdk/python')
```

#### 3.1.2 运行时安装流程

```python
# _runtime_setup.py 核心逻辑
ensure_runtime_package_installed(
    python_executable,
    sdk_python_dir,
    install_target=None
)
  ↓
检查已安装版本 == PINNED_RUNTIME_VERSION ("0.116.0-alpha.1")
  ↓
如果不匹配:
  1. 下载 GitHub Release 资源 (支持多平台)
  2. 解压运行时二进制
  3. 构建临时运行时包
  4. pip install --force-reinstall
```

**支持的平台**:
- macOS: `arm64`, `x86_64`
- Linux: `aarch64`, `x86_64` (musl)
- Windows: `aarch64`, `x86_64`

#### 3.1.3 Turn 执行流程

```
Thread.run(input)
  ↓
Thread.turn(_normalize_run_input(input))  # 字符串 → TextInput
  ↓
_to_wire_input()  # 转换为 JSON-RPC 格式
  ↓
client.turn_start(thread_id, wire_input, params)
  ↓
JSON-RPC: "turn/start" → app-server
  ↓
TurnHandle.stream() / TurnHandle.run()
  ↓
消费通知直到 turn/completed
```

### 3.2 关键数据结构

#### 3.2.1 输入类型系统

```python
# _inputs.py
@dataclass(slots=True)
class TextInput:
    text: str

@dataclass(slots=True)
class ImageInput:
    url: str

@dataclass(slots=True)
class LocalImageInput:
    path: str

InputItem = TextInput | ImageInput | LocalImageInput | SkillInput | MentionInput
Input = list[InputItem] | InputItem
RunInput = Input | str  # run() 接受字符串简写
```

#### 3.2.2 通知类型系统

```python
# models.py
NotificationPayload = (
    AccountLoginCompletedNotification
    | AgentMessageDeltaNotification
    | TurnCompletedNotification
    | ...  # 40+ 种通知类型
    | UnknownNotification  # 回退类型
)

@dataclass(slots=True)
class Notification:
    method: str
    payload: NotificationPayload
```

#### 3.2.3 RunResult 结构

```python
# _run.py
@dataclass(slots=True)
class RunResult:
    final_response: str | None  # 最终助手回复
    items: list[ThreadItem]     # 所有线程项
    usage: ThreadTokenUsage | None  # Token 使用情况
```

### 3.3 协议与通信

#### 3.3.1 JSON-RPC v2 协议

```python
# client.py 核心通信逻辑
class AppServerClient:
    def _request_raw(self, method: str, params: JsonObject | None = None) -> JsonValue:
        request_id = str(uuid.uuid4())
        self._write_message({"id": request_id, "method": method, "params": params or {}})
        
        while True:
            msg = self._read_message()
            # 处理服务器请求 (如 approval)
            # 处理通知
            # 匹配响应 ID
```

#### 3.3.2 通知注册表

```python
# generated/notification_registry.py
NOTIFICATION_MODELS: dict[str, type[BaseModel]] = {
    "turn/completed": TurnCompletedNotification,
    "item/agentMessage/delta": AgentMessageDeltaNotification,
    "thread/tokenUsage/updated": ThreadTokenUsageUpdatedNotification,
    # ... 40+ 条目
}
```

### 3.4 命令与工具

#### 3.4.1 代码生成命令

```bash
# scripts/update_sdk_artifacts.py
python scripts/update_sdk_artifacts.py generate-types

# 内部流程:
# 1. 读取 codex-rs/app-server-protocol/schema/json/*.json
# 2. 使用 datamodel-code-generator 生成 Pydantic 模型
# 3. 生成 notification_registry.py
# 4. 生成 api.py 中的公共 API 方法
```

#### 3.4.2 运行时包管理

```bash
# 下载并安装指定版本运行时
python _runtime_setup.py  # 被 notebook 自动调用

# 手动管理
python scripts/update_sdk_artifacts.py stage-sdk <dir> --runtime-version 1.2.3
python scripts/update_sdk_artifacts.py stage-runtime <dir> <binary> --runtime-version 1.2.3
```

---

## 关键代码路径与文件引用

### 4.1 Notebook 直接依赖

| 文件 | 路径 | 用途 |
|------|------|------|
| sdk_walkthrough.ipynb | `sdk/python/notebooks/` | 主 Notebook 文件 |
| _runtime_setup.py | `sdk/python/_runtime_setup.py` | 运行时安装逻辑 |
| _bootstrap.py | `sdk/python/examples/_bootstrap.py` | 辅助函数 (server_label, assistant_text_from_turn) |

### 4.2 SDK 核心实现

| 文件 | 路径 | 职责 |
|------|------|------|
| __init__.py | `sdk/python/src/codex_app_server/__init__.py` | 公共 API 导出 |
| api.py | `sdk/python/src/codex_app_server/api.py` | 高级 API (Codex, Thread, TurnHandle) |
| client.py | `sdk/python/src/codex_app_server/client.py` | 同步 JSON-RPC 客户端 (540 行) |
| async_client.py | `sdk/python/src/codex_app_server/async_client.py` | 异步客户端包装 (208 行) |
| _inputs.py | `sdk/python/src/codex_app_server/_inputs.py` | 输入类型定义 |
| _run.py | `sdk/python/src/codex_app_server/_run.py` | RunResult 收集逻辑 |
| models.py | `sdk/python/src/codex_app_server/models.py` | 核心数据模型 |
| errors.py | `sdk/python/src/codex_app_server/errors.py` | 异常层次结构 |
| retry.py | `sdk/python/src/codex_app_server/retry.py` | 重试逻辑 |

### 4.3 生成代码

| 文件 | 路径 | 说明 |
|------|------|------|
| v2_all.py | `sdk/python/src/codex_app_server/generated/v2_all.py` | 生成的 Pydantic 模型 (6351 行) |
| notification_registry.py | `sdk/python/src/codex_app_server/generated/notification_registry.py` | 通知类型映射 |

### 4.4 配置与构建

| 文件 | 路径 | 职责 |
|------|------|------|
| pyproject.toml | `sdk/python/pyproject.toml` | 包配置、依赖、构建设置 |
| update_sdk_artifacts.py | `sdk/python/scripts/update_sdk_artifacts.py` | 代码生成和发布脚本 (998 行) |

### 4.5 测试覆盖

| 文件 | 路径 | 测试范围 |
|------|------|----------|
| test_public_api_signatures.py | `sdk/python/tests/` | 公共 API 签名一致性 |
| test_public_api_runtime_behavior.py | `sdk/python/tests/` | 运行时行为 (575 行) |
| test_client_rpc_methods.py | `sdk/python/tests/` | RPC 方法测试 |
| test_async_client_behavior.py | `sdk/python/tests/` | 异步客户端行为 |
| test_contract_generation.py | `sdk/python/tests/` | 生成代码一致性 |

---

## 依赖与外部交互

### 5.1 Python 依赖

```toml
# pyproject.toml
[project]
dependencies = ["pydantic>=2.12"]
requires-python = ">=3.10"

[project.optional-dependencies]
dev = ["pytest>=8.0", "datamodel-code-generator==0.31.2", "ruff>=0.11"]
```

### 5.2 外部运行时依赖

| 组件 | 来源 | 版本 | 用途 |
|------|------|------|------|
| codex-cli-bin | GitHub Releases | 0.116.0-alpha.1 | 核心 Codex 二进制 |
| app-server | codex-cli | bundled | JSON-RPC 服务端 |

### 5.3 协议依赖

```
codex-rs/app-server-protocol/schema/json/
├── codex_app_server_protocol.v2.schemas.json  # 主 Schema
├── ServerNotification.json                     # 通知定义
└── ...
```

### 5.4 网络交互

| 场景 | 目标 | 协议 | 说明 |
|------|------|------|------|
| 运行时下载 | GitHub API/Releases | HTTPS | 获取 codex-cli-bin |
| 模型调用 | OpenAI API | HTTPS | 通过 app-server 代理 |
| 身份验证 | OpenAI 认证服务 | HTTPS | API Key 验证 |

---

## 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 并发限制 (实验性)

**风险**: 当前 SDK 实验性实现限制每个客户端实例只能有一个活跃的 Turn 消费者

```python
# api.py
class TurnHandle:
    def stream(self) -> Iterator[Notification]:
        self._client.acquire_turn_consumer(self.id)  # 可能抛出 RuntimeError
        ...
```

**影响**: 同时启动多个 `stream()` 或 `run()` 会导致 `RuntimeError`

#### 6.1.2 运行时版本锁定

**风险**: PINNED_RUNTIME_VERSION 硬编码在 `_runtime_setup.py` 中

```python
PINNED_RUNTIME_VERSION = "0.116.0-alpha.1"
```

**影响**: SDK 与运行时版本强耦合，升级需要同步更新

#### 6.1.3 平台支持限制

**风险**: 仅支持特定平台架构

```python
def platform_asset_name() -> str:
    # 仅支持: macOS (arm64/x86_64), Linux (aarch64/x86_64), Windows (aarch64/x86_64)
    # 不支持: 32位系统, 某些嵌入式 Linux
```

#### 6.1.4 Notebook 环境依赖

**风险**: Cell 1 的目录发现逻辑可能失败

```python
# 如果所有发现策略都失败:
raise RuntimeError('Could not locate sdk/python. Set CODEX_PYTHON_SDK_DIR...')
```

### 6.2 边界条件

| 边界 | 行为 | 代码位置 |
|------|------|----------|
| 空输入 | `run("")` 合法，发送空文本 | `_inputs.py: _normalize_run_input` |
| 大图片 | 受 app-server 限制 | 无客户端限制 |
| 长对话 | 受 token 限制，可调用 `compact()` | `api.py: Thread.compact` |
| 网络中断 | 抛出 `TransportClosedError` | `client.py: _read_message` |
| 服务器过载 | 抛出 `ServerBusyError`，可用 `retry_on_overload` | `retry.py` |

### 6.3 改进建议

#### 6.3.1 Notebook 改进

1. **添加错误处理示例**
   - 当前 Cell 仅展示成功路径
   - 建议添加 try/except 模式演示

2. **添加性能监控示例**
   - Token 使用统计
   - 响应时间测量

3. **环境检查增强**
   - 预检查 API Key 配置
   - 网络连通性测试

#### 6.3.2 SDK 改进

1. **并发支持**
   ```python
   # 建议: 真正的多 Turn 并发支持
   # 当前: client-wide 锁限制
   ```

2. **流式输出优化**
   - 当前 `stream()` 返回 `Notification` 需要用户解析
   - 建议提供高层次的 `text_stream()` 方法

3. **类型安全增强**
   - 部分返回值使用 `object` 类型
   - 建议完善 `assistant_text_from_turn` 等辅助函数的类型注解

#### 6.3.3 文档改进

1. **API 变更日志**
   - 当前 `CHANGELOG.md` 几乎为空
   - 需要维护版本间的 API 变更记录

2. **故障排查指南**
   - 常见错误代码说明
   - 调试技巧

### 6.4 维护建议

1. **定期更新 PINNED_RUNTIME_VERSION**
   - 跟随 codex-cli 发布节奏
   - 测试兼容性

2. **监控生成代码漂移**
   - `test_contract_generation.py` 已覆盖
   - CI 中应强制执行

3. **Notebook 回归测试**
   - 考虑使用 nbconvert 自动化测试
   - 验证所有 Cell 可执行

---

## 附录

### A. 文件统计

```
sdk/python/notebooks/
└── sdk_walkthrough.ipynb        587 行

sdk/python/src/codex_app_server/
├── __init__.py                  113 行
├── api.py                       735 行
├── client.py                    540 行
├── async_client.py              208 行
├── _inputs.py                    63 行
├── _run.py                      112 行
├── models.py                     99 行
├── errors.py                    125 行
├── retry.py                      41 行
└── generated/
    ├── v2_all.py              6,351 行
    └── notification_registry.py 106 行
```

### B. 版本信息

- **SDK Version**: 0.2.0
- **Python Requirement**: >=3.10
- **Pinned Runtime**: 0.116.0-alpha.1
- **Protocol**: JSON-RPC v2

### C. 相关文档链接

- 入门指南: `sdk/python/docs/getting-started.md`
- API 参考: `sdk/python/docs/api-reference.md`
- FAQ: `sdk/python/docs/faq.md`
- 示例索引: `sdk/python/examples/README.md`
