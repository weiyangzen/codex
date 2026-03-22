# 04_models_and_metadata 研究文档

## 1. 场景与职责

### 1.1 定位与目标

`04_models_and_metadata` 是 Codex Python SDK 示例系列中的第4个示例，其核心职责是**演示如何查询和展示 Codex App Server 的元数据信息以及可用的 AI 模型列表**。

该示例位于示例序列的关键位置：
- 前序示例（01-03）主要关注基础连接、线程创建和对话执行
- 本示例（04）首次引入**服务端发现能力**，让客户端能够了解服务器能力和可用资源
- 后续示例（05-14）在此基础上构建更复杂的线程管理和模型选择场景

### 1.2 使用场景

| 场景 | 描述 |
|------|------|
| 服务端能力探测 | 在正式使用前检查服务器版本、名称等元数据 |
| 模型发现 | 获取当前可用的 AI 模型列表，为后续模型选择提供数据基础 |
| 健康检查 | 验证 SDK 与 App Server 的连接是否正常 |
| 调试诊断 | 输出服务器信息用于问题排查 |

### 1.3 示例输出示例

```
server: codex-cli 0.116.0-alpha.1
models.count: 15
models: gpt-5.4, gpt-5.4-mini, gpt-5.4-nano, o3, o3-mini, o4-mini...
```

## 2. 功能点目的

### 2.1 核心功能

本示例实现两个核心功能点：

#### 2.1.1 服务器元数据获取 (`metadata`)

- **目的**: 获取 App Server 的标识信息（名称、版本、User-Agent 等）
- **业务价值**: 
  - 版本兼容性检查
  - 服务端健康状态确认
  - 日志记录和遥测

#### 2.1.2 模型列表查询 (`models()`)

- **目的**: 获取服务器支持的所有 AI 模型信息
- **业务价值**:
  - 动态发现可用模型，避免硬编码
  - 支持模型选择策略（如示例13中的高级选择逻辑）
  - 获取模型能力信息（支持的推理力度、输入模态等）

### 2.2 功能对比

| 功能 | 同步版本 (`sync.py`) | 异步版本 (`async.py`) |
|------|---------------------|----------------------|
| API 风格 | 阻塞式调用 | `async/await` 非阻塞 |
| 使用模式 | `with Codex() as codex:` | `async with AsyncCodex() as codex:` |
| 方法调用 | `codex.models()` | `await codex.models()` |
| 适用场景 | 脚本、简单应用 | 高并发、Web服务 |

### 2.3 与相关示例的关系

```
04_models_and_metadata          # 基础模型发现
        ↓
13_model_select_and_turn_params  # 基于模型列表的高级选择策略
        ↓
12_turn_params_kitchen_sink      # 使用选定模型执行复杂对话
```

示例13 (`13_model_select_and_turn_params`) 直接依赖本示例展示的基础模型查询能力，实现了：
- 从模型列表中筛选可见模型
- 选择首选模型（gpt-5.4）或最高级备选
- 根据模型支持的推理力度选项选择最高级别

## 3. 具体技术实现

### 3.1 代码结构

```
sdk/python/examples/04_models_and_metadata/
├── sync.py   # 同步实现（18行）
└── async.py  # 异步实现（26行）
```

### 3.2 同步版本详解 (`sync.py`)

```python
import sys
from pathlib import Path

# 1. 路径设置：确保可以导入本地 SDK
_EXAMPLES_ROOT = Path(__file__).resolve().parents[1]
if str(_EXAMPLES_ROOT) not in sys.path:
    sys.path.insert(0, str(_EXAMPLES_ROOT))

# 2. 引导导入：运行时依赖检查和配置
from _bootstrap import ensure_local_sdk_src, runtime_config, server_label

ensure_local_sdk_src()  # 确保 SDK 源码可用

# 3. 核心 SDK 导入
from codex_app_server import Codex

# 4. 主逻辑：上下文管理器确保资源释放
with Codex(config=runtime_config()) as codex:
    # 4.1 获取并打印服务器元数据
    print("server:", server_label(codex.metadata))
    
    # 4.2 查询模型列表
    models = codex.models()
    
    # 4.3 输出统计信息
    print("models.count:", len(models.data))
    
    # 4.4 输出前5个模型ID
    print("models:", ", ".join(model.id for model in models.data[:5]) or "[none]")
```

### 3.3 异步版本详解 (`async.py`)

```python
import sys
from pathlib import Path

# 路径设置和引导导入与同步版相同
_EXAMPLES_ROOT = Path(__file__).resolve().parents[1]
if str(_EXAMPLES_ROOT) not in sys.path:
    sys.path.insert(0, str(_EXAMPLES_ROOT))

from _bootstrap import ensure_local_sdk_src, runtime_config, server_label

ensure_local_sdk_src()

import asyncio
from codex_app_server import AsyncCodex  # 导入异步客户端

async def main() -> None:
    # 使用异步上下文管理器
    async with AsyncCodex(config=runtime_config()) as codex:
        print("server:", server_label(codex.metadata))
        
        # await 关键字等待异步操作完成
        models = await codex.models()
        
        print("models.count:", len(models.data))
        print("models:", ", ".join(model.id for model in models.data[:5]) or "[none]")

if __name__ == "__main__":
    asyncio.run(main())  # 运行异步主函数
```

### 3.4 关键数据结构

#### 3.4.1 `InitializeResponse` (元数据响应)

```python
# sdk/python/src/codex_app_server/models.py
class InitializeResponse(BaseModel):
    serverInfo: ServerInfo | None = None      # 服务器信息
    userAgent: str | None = None              # User-Agent 字符串
    platformFamily: str | None = None         # 平台家族
    platformOs: str | None = None             # 操作系统

class ServerInfo(BaseModel):
    name: str | None = None                   # 服务器名称（如 "codex-cli"）
    version: str | None = None                # 版本号（如 "0.116.0-alpha.1"）
```

#### 3.4.2 `ModelListResponse` (模型列表响应)

```python
# sdk/python/src/codex_app_server/generated/v2_all.py
class ModelListResponse(BaseModel):
    data: list[Model]                         # 模型列表
    next_cursor: str | None = None            # 分页游标

class Model(BaseModel):
    id: str                                   # 模型ID（如 "gpt-5.4"）
    model: str                                # 模型名称
    display_name: str                         # 显示名称
    description: str                          # 描述
    hidden: bool                              # 是否隐藏
    is_default: bool                          # 是否为默认模型
    default_reasoning_effort: ReasoningEffort # 默认推理力度
    supported_reasoning_efforts: list[ReasoningEffortOption]  # 支持的推理选项
    input_modalities: list[InputModality] | None = ["text", "image"]  # 输入模态
    supports_personality: bool | None = False # 是否支持个性设置
    availability_nux: ModelAvailabilityNux | None = None  # 可用性提示
    upgrade: str | None = None                # 升级推荐模型
    upgrade_info: ModelUpgradeInfo | None = None  # 升级信息
```

### 3.5 调用链分析

#### 3.5.1 `codex.models()` 调用链

```
Codex.models(include_hidden=False)
    ↓
AppServerClient.model_list(include_hidden=False)  [client.py:388]
    ↓
AppServerClient.request(
    method="model/list",
    params={"includeHidden": include_hidden},
    response_model=ModelListResponse
)  [client.py:227]
    ↓
AppServerClient._request_raw(method, params)  [client.py:239]
    ↓
JSON-RPC over stdio → codex app-server
    ↓
返回 ModelListResponse
```

#### 3.5.2 `codex.metadata` 访问链

```
Codex.metadata  [api.py:126-127]
    ↓
返回 self._init (InitializeResponse)
    ↓
在 __init__ 中通过 self._client.initialize() 获取
```

### 3.6 JSON-RPC 协议细节

#### 请求格式

```json
{
  "id": "uuid-v4-string",
  "method": "model/list",
  "params": {
    "includeHidden": false
  }
}
```

#### 响应格式

```json
{
  "id": "uuid-v4-string",
  "result": {
    "data": [
      {
        "id": "gpt-5.4",
        "model": "gpt-5.4",
        "displayName": "GPT-5.4",
        "description": "Most capable model...",
        "hidden": false,
        "isDefault": true,
        "defaultReasoningEffort": "medium",
        "supportedReasoningEfforts": [...]
      }
    ],
    "nextCursor": null
  }
}
```

## 4. 关键代码路径与文件引用

### 4.1 核心文件

| 文件路径 | 职责 |
|---------|------|
| `sdk/python/examples/04_models_and_metadata/sync.py` | 同步示例实现 |
| `sdk/python/examples/04_models_and_metadata/async.py` | 异步示例实现 |
| `sdk/python/examples/_bootstrap.py` | 运行时引导和配置 |

### 4.2 SDK 核心文件

| 文件路径 | 职责 |
|---------|------|
| `sdk/python/src/codex_app_server/api.py` | 高层 API (`Codex`, `AsyncCodex`) |
| `sdk/python/src/codex_app_server/client.py` | 同步底层客户端 (`AppServerClient`) |
| `sdk/python/src/codex_app_server/async_client.py` | 异步底层客户端 (`AsyncAppServerClient`) |
| `sdk/python/src/codex_app_server/models.py` | 核心数据模型 (`InitializeResponse`, `ServerInfo`) |
| `sdk/python/src/codex_app_server/generated/v2_all.py` | 生成的 v2 API 模型 (`ModelListResponse`, `Model`) |

### 4.3 关键代码行引用

```python
# 高层 API 入口
sdk/python/src/codex_app_server/api.py:266
    def models(self, *, include_hidden: bool = False) -> ModelListResponse:
        return self._client.model_list(include_hidden=include_hidden)

# 底层客户端实现
sdk/python/src/codex_app_server/client.py:388-393
    def model_list(self, include_hidden: bool = False) -> ModelListResponse:
        return self.request(
            "model/list",
            {"includeHidden": include_hidden},
            response_model=ModelListResponse,
        )

# 异步包装
sdk/python/src/codex_app_server/async_client.py:161-162
    async def model_list(self, include_hidden: bool = False) -> ModelListResponse:
        return await self._call_sync(self._sync.model_list, include_hidden)

# 生成的模型定义
sdk/python/src/codex_app_server/generated/v2_all.py:4553-4580
    class Model(BaseModel): ...

sdk/python/src/codex_app_server/generated/v2_all.py:4582-4593
    class ModelListResponse(BaseModel): ...

# 引导工具函数
sdk/python/examples/_bootstrap.py:107-115
    def server_label(metadata: object) -> str:
        # 从元数据中提取服务器标识字符串
```

### 4.4 测试覆盖

```python
# 集成测试验证示例输出
sdk/python/tests/test_real_app_server_integration.py:516-520
    elif folder == "04_models_and_metadata":
        assert "server:" in out
        assert "models.count:" in out
        assert "models:" in out
        assert "metadata:" not in out

# 模型列表功能测试
sdk/python/tests/test_real_app_server_integration.py:202-228
    def test_real_initialize_and_model_list(runtime_env: PreparedRuntimeEnv) -> None:
        # 验证 models(include_hidden=True) 返回正确结构
```

## 5. 依赖与外部交互

### 5.1 内部依赖

```
04_models_and_metadata/
    ↓ imports
_bootstrap.py
    ↓ imports
sdk/python/src/codex_app_server/
    ├── api.py (Codex, AsyncCodex)
    ├── client.py (AppServerClient)
    ├── async_client.py (AsyncAppServerClient)
    ├── models.py (InitializeResponse)
    └── generated/v2_all.py (ModelListResponse, Model)
```

### 5.2 外部依赖

| 依赖 | 用途 |
|------|------|
| `codex-cli-bin` | 本地 Codex App Server 运行时二进制 |
| `pydantic` | 数据模型验证和序列化 |
| Python >= 3.10 | 类型注解支持 |

### 5.3 运行时交互

```
┌─────────────────────────────────────────────────────────────┐
│                     Python 示例进程                          │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │   sync.py    │    │  Codex API   │    │  AppServer   │  │
│  │   async.py   │───→│   (api.py)   │───→│   Client     │  │
│  └──────────────┘    └──────────────┘    └──────────────┘  │
└─────────────────────────────────────────────────────────────┘
                          │
                          ↓ JSON-RPC over stdio
┌─────────────────────────────────────────────────────────────┐
│              codex app-server (codex-cli-bin)               │
│                     ┌──────────────┐                        │
│                     │  model/list  │                        │
│                     │  initialize  │                        │
│                     └──────────────┘                        │
└─────────────────────────────────────────────────────────────┘
                          │
                          ↓ HTTP
┌─────────────────────────────────────────────────────────────┐
│              OpenAI API / Codex Backend                     │
└─────────────────────────────────────────────────────────────┘
```

### 5.4 配置依赖

示例通过 `runtime_config()` 获取默认配置：

```python
# sdk/python/examples/_bootstrap.py:50-55
def runtime_config():
    """Return an example-friendly AppServerConfig for repo-source SDK usage."""
    from codex_app_server import AppServerConfig
    ensure_runtime_package_installed(sys.executable, _SDK_PYTHON_DIR)
    return AppServerConfig()  # 使用默认配置
```

默认配置包含：
- `client_name`: "codex_python_sdk"
- `client_version`: "0.2.0"
- `experimental_api`: True

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 运行时不可用

| 风险 | 描述 | 缓解措施 |
|------|------|---------|
| `codex-cli-bin` 未安装 | 示例依赖本地运行时包 | `_bootstrap.py` 自动下载安装 |
| App Server 启动失败 | 配置错误或端口占用 | 检查 `~/.codex/` 配置和日志 |
| 网络连接失败 | 无法连接到后端 API | 确保有效的 API Key 和网络 |

#### 6.1.2 数据兼容性

- **模型字段变更**: `Model` 结构由后端定义，字段可能增减
- **版本不匹配**: SDK 与运行时版本不兼容可能导致字段缺失
- **缓解**: SDK 使用 Pydantic 模型，未知字段默认忽略

### 6.2 边界情况

#### 6.2.1 空模型列表

```python
# 当前实现
print("models:", ", ".join(model.id for model in models.data[:5]) or "[none]")

# 边界: models.data 为空列表时输出 "[none]"
```

#### 6.2.2 分页处理

当前示例**不处理分页**：
- `next_cursor` 被忽略
- 仅显示前5个模型
- 完整列表可能需要多次请求

#### 6.2.3 隐藏模型

```python
# 默认不包含隐藏模型
codex.models()  # include_hidden=False

# 获取全部模型（包括隐藏）
codex.models(include_hidden=True)
```

### 6.3 改进建议

#### 6.3.1 功能增强

| 建议 | 优先级 | 说明 |
|------|--------|------|
| 分页支持示例 | 中 | 展示如何处理 `next_cursor` 获取完整列表 |
| 模型过滤示例 | 低 | 按能力（图像、推理）筛选模型 |
| 模型详情展示 | 低 | 输出更多字段（description, supported_reasoning_efforts） |
| 错误处理 | 高 | 添加 try/except 处理连接失败 |

#### 6.3.2 代码改进

```python
# 建议：添加错误处理
from codex_app_server import Codex, AppServerError, TransportClosedError

try:
    with Codex(config=runtime_config()) as codex:
        models = codex.models()
        # ... 处理结果
except TransportClosedError as e:
    print(f"连接失败: {e}")
except AppServerError as e:
    print(f"服务器错误: {e}")
```

#### 6.3.3 文档改进

- 添加模型字段说明注释
- 解释 `include_hidden` 参数的用途
- 说明 `next_cursor` 分页机制

### 6.4 与示例13的协同建议

示例04和示例13可以合并为一个更完整的"模型发现与选择"教程：

```python
# 04: 基础发现
models = codex.models(include_hidden=True)

# 13: 高级选择
selected = _pick_highest_model(models.data)  # 复杂选择逻辑
```

建议创建一个中间示例，展示：
1. 获取模型列表
2. 按可见性筛选
3. 按能力筛选（支持图像、支持特定推理力度）
4. 选择最优模型

### 6.5 测试建议

当前测试仅验证输出包含特定字符串，建议增加：

```python
# 验证模型数据结构
def test_model_list_structure():
    models = codex.models()
    for model in models.data:
        assert model.id  # ID 必须存在
        assert model.model  # 模型名称必须存在
        assert isinstance(model.hidden, bool)  # hidden 必须是布尔值
```

---

## 附录：相关文件索引

### 示例文件
- `sdk/python/examples/04_models_and_metadata/sync.py`
- `sdk/python/examples/04_models_and_metadata/async.py`
- `sdk/python/examples/_bootstrap.py`
- `sdk/python/examples/README.md`

### SDK 源文件
- `sdk/python/src/codex_app_server/api.py`
- `sdk/python/src/codex_app_server/client.py`
- `sdk/python/src/codex_app_server/async_client.py`
- `sdk/python/src/codex_app_server/models.py`
- `sdk/python/src/codex_app_server/generated/v2_all.py`

### 文档
- `sdk/python/docs/api-reference.md`
- `sdk/python/docs/getting-started.md`
- `sdk/python/docs/faq.md`

### 测试
- `sdk/python/tests/test_real_app_server_integration.py`
- `sdk/python/tests/test_client_rpc_methods.py`
- `sdk/python/tests/test_public_api_signatures.py`
