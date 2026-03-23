# async.py 深度研究文档

## 场景与职责

`async.py` 是 Python SDK 的异步示例文件，位于 `sdk/python/examples/04_models_and_metadata/` 目录下。该示例的核心职责是演示如何：

1. **异步初始化 Codex 客户端**：展示 `AsyncCodex` 类的正确使用方式
2. **获取服务器元数据**：展示如何读取连接的服务器信息
3. **枚举可用模型**：展示如何调用 `models()` 方法获取当前运行时可见的 AI 模型列表

该示例属于 "04_models_and_metadata" 系列，专注于模型发现和元数据查询功能，是 SDK 示例体系中承上启下的环节（前三个示例分别演示基础连接、Turn 运行、事件流）。

## 功能点目的

### 1. 服务器元数据展示
- **目的**：验证与 app-server 的连接状态，展示服务器版本信息
- **输出示例**：`server: codex-cli 0.116.0-alpha.1`
- **业务价值**：帮助用户确认正在连接的 Codex 运行时版本

### 2. 模型列表枚举
- **目的**：获取当前用户账户可访问的所有 AI 模型
- **输出示例**：`models.count: 15` / `models: gpt-4, gpt-4-turbo, gpt-3.5-turbo...`
- **业务价值**：
  - 让用户了解可用的模型选项
  - 为后续创建 Thread 时选择模型提供依据
  - 展示模型数量上限（示例中只显示前5个）

### 3. 异步上下文管理
- **目的**：演示 `async with` 模式确保资源正确释放
- **技术价值**：展示异步资源的正确生命周期管理

## 具体技术实现

### 关键流程

```
┌─────────────────────────────────────────────────────────────┐
│  1. 引导阶段 (Bootstrap)                                     │
│     ├── 添加 examples 目录到 sys.path                        │
│     ├── 导入 _bootstrap 模块                                 │
│     └── 调用 ensure_local_sdk_src() 设置本地 SDK 路径        │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  2. 异步客户端初始化                                         │
│     ├── 创建 AsyncCodex(config=runtime_config())            │
│     ├── __aenter__ 触发 _ensure_initialized()               │
│     │   ├── 调用 _client.start() 启动子进程                 │
│     │   ├── 发送 initialize RPC 请求                        │
│     │   └── 验证响应元数据                                  │
│     └── 返回初始化完成的客户端实例                          │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  3. 元数据读取                                               │
│     ├── 访问 codex.metadata (InitializeResponse)            │
│     └── 使用 server_label() 工具函数格式化输出              │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  4. 模型列表查询                                             │
│     ├── 调用 await codex.models()                           │
│     │   └── 内部调用 model_list(include_hidden=False)       │
│     ├── 返回 ModelListResponse 对象                         │
│     └── 提取并打印模型数量和前5个模型ID                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  5. 资源清理                                                 │
│     ├── __aexit__ 触发 close()                              │
│     ├── 关闭 stdio 传输                                     │
│     └── 终止 codex-cli 子进程                               │
└─────────────────────────────────────────────────────────────┘
```

### 数据结构

#### ModelListResponse (返回类型)
```python
class ModelListResponse(BaseModel):
    data: list[Model]           # 模型列表
    next_cursor: str | None     # 分页游标（可选）
```

#### Model (模型定义)
```python
class Model(BaseModel):
    id: str                              # 模型ID (如 "gpt-4")
    model: str                           # 模型名称
    display_name: str                    # 显示名称
    description: str                     # 描述
    default_reasoning_effort: ReasoningEffort  # 默认推理强度
    supported_reasoning_efforts: list[ReasoningEffortOption]  # 支持的推理选项
    hidden: bool                         # 是否在默认列表中隐藏
    is_default: bool                     # 是否为默认模型
    input_modalities: list[InputModality]  # 支持的输入类型 (text/image)
    supports_personality: bool | None     # 是否支持个性化
    upgrade: str | None                   # 升级目标模型ID
    upgrade_info: ModelUpgradeInfo | None # 升级信息
    availability_nux: ModelAvailabilityNux | None  # 可用性提示
```

#### InitializeResponse (元数据类型)
```python
class InitializeResponse(BaseModel):
    serverInfo: ServerInfo | None   # 服务器信息 (name, version)
    userAgent: str | None           # User-Agent 字符串
    platformFamily: str | None      # 平台家族
    platformOs: str | None          # 操作系统
```

### 协议与命令

#### JSON-RPC 请求

**initialize 请求**（客户端初始化时自动发送）：
```json
{
  "id": "uuid",
  "method": "initialize",
  "params": {
    "clientInfo": {
      "name": "codex_python_sdk",
      "title": "Codex Python SDK",
      "version": "0.2.0"
    },
    "capabilities": {
      "experimentalApi": true
    }
  }
}
```

**model/list 请求**：
```json
{
  "id": "uuid",
  "method": "model/list",
  "params": {
    "includeHidden": false
  }
}
```

#### 底层传输
- **传输方式**：stdio (stdin/stdout)
- **进程启动**：`codex app-server --listen stdio://`
- **序列化**：JSON-RPC 2.0

## 关键代码路径与文件引用

### 调用链

```
async.py
├── _bootstrap.py
│   ├── ensure_local_sdk_src()       # 设置本地 SDK 路径
│   └── runtime_config()             # 返回 AppServerConfig()
│
└── codex_app_server/__init__.py
    └── AsyncCodex (从 api.py 导入)
        ├── __init__()               # 创建 AsyncAppServerClient
        ├── __aenter__()
        │   └── _ensure_initialized()
        │       ├── _client.start()  # client.py: AppServerClient.start()
        │       │   └── subprocess.Popen()  # 启动 codex-cli
        │       ├── _client.initialize()    # 发送 initialize RPC
        │       └── _validate_initialize()  # 验证元数据
        ├── models()
        │   └── _client.model_list()        # async_client.py
        │       └── _call_sync()            # 线程卸载调用
        │           └── asyncio.to_thread()
        │               └── AppServerClient.model_list()  # client.py
        │                   └── request("model/list", ...)
        └── __aexit__()
            └── close()              # 清理资源
```

### 核心文件位置

| 文件 | 路径 | 职责 |
|------|------|------|
| async.py | `sdk/python/examples/04_models_and_metadata/async.py` | 本示例文件 |
| _bootstrap.py | `sdk/python/examples/_bootstrap.py` | 示例引导工具 |
| __init__.py | `sdk/python/src/codex_app_server/__init__.py` | SDK 公共 API 导出 |
| api.py | `sdk/python/src/codex_app_server/api.py` | AsyncCodex/Codex 高级 API |
| async_client.py | `sdk/python/src/codex_app_server/async_client.py` | AsyncAppServerClient 实现 |
| client.py | `sdk/python/src/codex_app_server/client.py` | AppServerClient 同步实现 |
| v2_all.py | `sdk/python/src/codex_app_server/generated/v2_all.py` | 生成的 Pydantic 模型 |
| models.py | `sdk/python/src/codex_app_server/models.py` | 核心数据类型定义 |

### 关键函数详解

#### `server_label()` (位于 _bootstrap.py:107-115)
```python
def server_label(metadata: object) -> str:
    """从 InitializeResponse 提取服务器名称和版本"""
    server = getattr(metadata, "serverInfo", None)
    server_name = ((getattr(server, "name", None) or "") if server is not None else "").strip()
    server_version = ((getattr(server, "version", None) or "") if server is not None else "").strip()
    if server_name and server_version:
        return f"{server_name} {server_version}"
    # 回退到 userAgent 解析
    user_agent = ((getattr(metadata, "userAgent", None) or "") if metadata is not None else "").strip()
    return user_agent or "unknown"
```

#### `AsyncCodex.models()` (位于 api.py:462-464)
```python
async def models(self, *, include_hidden: bool = False) -> ModelListResponse:
    await self._ensure_initialized()
    return await self._client.model_list(include_hidden=include_hidden)
```

#### `AsyncAppServerClient.model_list()` (位于 async_client.py:161-162)
```python
async def model_list(self, include_hidden: bool = False) -> ModelListResponse:
    return await self._call_sync(self._sync.model_list, include_hidden)
```

## 依赖与外部交互

### 内部依赖

| 依赖 | 类型 | 说明 |
|------|------|------|
| `codex_app_server.AsyncCodex` | 类 | 异步 SDK 主入口 |
| `_bootstrap.ensure_local_sdk_src` | 函数 | 设置本地 SDK 源路径 |
| `_bootstrap.runtime_config` | 函数 | 返回默认配置 |
| `_bootstrap.server_label` | 函数 | 格式化服务器标签 |

### 外部依赖

| 依赖 | 类型 | 说明 |
|------|------|------|
| `codex-cli` | 二进制 | Codex CLI 运行时（通过 `codex-cli-bin` 包提供）|
| `pydantic` | Python 包 | 数据验证和序列化 |
| `asyncio` | Python 标准库 | 异步运行时 |

### 运行时进程交互

```
┌─────────────┐      stdio (JSON-RPC)      ┌─────────────────┐
│  async.py   │  <--------------------->   │  codex-cli      │
│  (Python)   │      stdin/stdout          │  app-server     │
└─────────────┘                            └─────────────────┘
                                                  │
                                                  ▼
                                           ┌─────────────────┐
                                           │  OpenAI API     │
                                           │  (模型列表查询)  │
                                           └─────────────────┘
```

## 风险、边界与改进建议

### 已知风险

1. **模型列表截断**
   - 示例只打印前5个模型：`models.data[:5]`
   - 风险：用户可能误以为只有5个模型可用
   - 建议：添加提示说明"仅显示前5个，共N个"

2. **空列表处理**
   - 代码使用 `or "[none]"` 处理空列表，但逻辑仅在 `join()` 返回空字符串时触发
   - 风险：如果模型列表为空，显示可能不够直观

3. **异常处理缺失**
   - 示例没有 try/except 块
   - 风险：连接失败或 RPC 错误会直接抛出未处理异常

### 边界条件

| 场景 | 行为 | 说明 |
|------|------|------|
| 无可用模型 | 输出 `models: [none]` | 空列表回退逻辑 |
| 服务器连接失败 | 抛出 RuntimeError | 在 `__aenter__` 时失败 |
| 认证失败 | 抛出 AppServerRpcError | 在 initialize 时失败 |
| 网络超时 | 依赖默认超时 | 可能长时间挂起 |

### 改进建议

1. **添加异常处理**
   ```python
   async def main() -> None:
       try:
           async with AsyncCodex(config=runtime_config()) as codex:
               # ... 现有逻辑
       except AppServerError as e:
           print(f"连接失败: {e}", file=sys.stderr)
           sys.exit(1)
   ```

2. **显示完整模型信息**
   ```python
   # 添加更多模型详情展示
   for model in models.data[:5]:
       print(f"  - {model.id}: {model.display_name}")
       if model.description:
           print(f"    {model.description}")
   ```

3. **添加分页支持演示**
   - 当前示例未展示 `next_cursor` 的使用
   - 建议添加分页遍历示例代码（注释形式）

4. **配置选项展示**
   - 添加 `include_hidden=True` 的对比展示
   - 帮助用户理解该参数的作用

5. **类型提示完善**
   - `main()` 函数已添加 `-> None` 返回类型
   - 建议添加函数文档字符串

### 与 sync.py 的差异

| 方面 | async.py | sync.py |
|------|----------|---------|
| 客户端类 | `AsyncCodex` | `Codex` |
| 上下文管理器 | `async with` | `with` |
| 方法调用 | `await codex.models()` | `codex.models()` |
| 初始化方式 | 延迟初始化（`_ensure_initialized`）| 构造函数初始化 |
| 适用场景 | 高并发/异步应用 | 简单脚本/同步应用 |

两个示例功能完全一致，仅展示同步/异步 API 的使用差异。
