# async.py 研究文档

## 场景与职责

`async.py` 是 OpenAI Codex Python SDK 的示例程序，演示如何使用**异步 API** 向 AI 模型同时发送**文本和远程图片**进行多模态对话。该示例展示了 SDK 的核心异步工作流程，包括：

1. 初始化异步 Codex 客户端
2. 创建对话线程（Thread）
3. 发送混合输入（文本 + 远程图片 URL）
4. 执行对话回合（Turn）并等待结果
5. 读取持久化的对话历史

## 功能点目的

### 1. 多模态输入支持
展示如何组合 `TextInput` 和 `ImageInput` 作为单次对话的输入，使模型能够同时理解文本问题和图片内容。

### 2. 异步编程模式
使用 `async/await` 语法和异步上下文管理器 (`async with`)，展示如何在不阻塞事件循环的情况下与 Codex API 交互。

### 3. 远程图片处理
通过 `ImageInput` 传入远程图片 URL，SDK 会自动处理图片的下载和编码，无需本地文件操作。

### 4. 对话状态管理
演示如何创建线程、执行回合、读取持久化状态，以及从回合结果中提取助手回复。

## 具体技术实现

### 关键流程

```
┌─────────────────┐
│   async main    │
└────────┬────────┘
         │
         ▼
┌─────────────────────────┐
│ AsyncCodex(config)      │◄── 初始化异步客户端
│ async with ... as codex │
└────────┬────────────────┘
         │
         ▼
┌─────────────────────────┐
│ codex.thread_start()    │◄── 创建新线程，指定模型
│ model="gpt-5.4"         │    config={"model_reasoning_effort": "high"}
└────────┬────────────────┘
         │
         ▼
┌─────────────────────────┐
│ thread.turn([...])      │◄── 发送混合输入
│ - TextInput("...")      │    文本问题
│ - ImageInput(URL)       │    远程图片
└────────┬────────────────┘
         │
         ▼
┌─────────────────────────┐
│ await turn.run()        │◄── 异步执行回合，等待完成
└────────┬────────────────┘
         │
         ▼
┌─────────────────────────┐
│ thread.read()           │◄── 读取持久化线程状态
│ include_turns=True      │
└────────┬────────────────┘
         │
         ▼
┌─────────────────────────┐
│ find_turn_by_id()       │◄── 从线程历史中定位回合
│ assistant_text_from_turn│    提取助手文本回复
└─────────────────────────┘
```

### 数据结构

#### 输入类型定义（`_inputs.py`）

```python
@dataclass(slots=True)
class TextInput:
    text: str

@dataclass(slots=True)
class ImageInput:
    url: str  # 远程图片 URL
```

#### 序列化为 Wire 格式

```python
def _to_wire_item(item: InputItem) -> JsonObject:
    if isinstance(item, TextInput):
        return {"type": "text", "text": item.text}
    if isinstance(item, ImageInput):
        return {"type": "image", "url": item.url}
    # ...
```

输入被序列化为 JSON 格式，通过 JSON-RPC 协议发送到 app-server。

### 协议交互

#### JSON-RPC 请求流程（`client.py` / `async_client.py`）

1. **初始化连接**
   - `AsyncCodex` 使用 `AsyncAppServerClient` 作为底层客户端
   - 通过 `asyncio.to_thread()` 将同步调用 offload 到线程池
   - 使用 `asyncio.Lock()` 保护 stdio 传输（单传输不能多线程安全读取）

2. **Turn 启动请求**
   ```python
   # async_client.py
   async def turn_start(...):
       payload = {
           **_params_dict(params),
           "threadId": thread_id,
           "input": self._normalize_input_items(input_items),
       }
       return await self._call_sync(
           self._sync.turn_start, thread_id, input_items, params=params
       )
   ```

3. **等待回合完成**
   - `turn.run()` 内部调用 `stream()` 获取通知流
   - 监听 `turn/completed` 通知，匹配 `turn_id`
   - 返回 `AppServerTurn` 对象包含完整回合信息

#### 核心异步类关系

```
AsyncCodex
    ├── _client: AsyncAppServerClient
    │       └── _sync: AppServerClient (同步客户端)
    │       └── _transport_lock: asyncio.Lock
    │
    └── thread_start() ──► AsyncThread
            ├── _codex: AsyncCodex
            ├── id: str
            │
            └── turn() ──► AsyncTurnHandle
                    ├── _codex: AsyncCodex
                    ├── thread_id: str
                    ├── id: str
                    │
                    ├── run() ──► AppServerTurn
                    └── stream() ──► AsyncIterator[Notification]
```

### 关键代码路径

| 功能 | 文件路径 | 关键函数/类 |
|------|----------|-------------|
| 异步客户端入口 | `sdk/python/src/codex_app_server/api.py` | `AsyncCodex` 类 |
| 异步底层客户端 | `sdk/python/src/codex_app_server/async_client.py` | `AsyncAppServerClient` 类 |
| 同步底层客户端 | `sdk/python/src/codex_app_server/client.py` | `AppServerClient` 类 |
| 输入类型定义 | `sdk/python/src/codex_app_server/_inputs.py` | `TextInput`, `ImageInput` |
| 回合结果收集 | `sdk/python/src/codex_app_server/_run.py` | `_collect_async_run_result` |
| 工具函数 | `sdk/python/examples/_bootstrap.py` | `assistant_text_from_turn`, `find_turn_by_id` |

## 依赖与外部交互

### 内部依赖

1. **`_bootstrap.py`** - 示例共享工具模块
   - `ensure_local_sdk_src()`: 将 `sdk/python/src` 添加到 `sys.path`，支持无需安装的本地开发
   - `runtime_config()`: 返回示例友好的 `AppServerConfig`
   - `assistant_text_from_turn()`: 从回合对象提取助手文本回复
   - `find_turn_by_id()`: 在线程历史中按 ID 查找回合

2. **SDK 核心模块**
   - `codex_app_server.AsyncCodex`: 异步客户端主类
   - `codex_app_server.ImageInput`: 图片输入包装器
   - `codex_app_server.TextInput`: 文本输入包装器

### 外部依赖

1. **Codex CLI 二进制**
   - 通过 `AppServerConfig` 配置或自动发现 `codex-cli-bin` 包中的二进制
   - 启动 `codex app-server --listen stdio://` 子进程
   - 通过 stdio 进行 JSON-RPC 通信

2. **OpenAI API**
   - 远程图片 URL: `https://raw.githubusercontent.com/github/explore/main/topics/python/python.png`
   - 模型: `gpt-5.4`
   - 推理努力度: `high`

### 启动流程

```python
# 1. 确保本地 SDK 可用
ensure_local_sdk_src()

# 2. 导入 SDK
from codex_app_server import AsyncCodex, ImageInput, TextInput

# 3. 使用运行时配置创建客户端
async with AsyncCodex(config=runtime_config()) as codex:
    # runtime_config() 返回 AppServerConfig()
    # 自动处理 codex 二进制路径解析
```

## 风险、边界与改进建议

### 风险点

1. **远程图片可用性**
   - 示例使用 GitHub 上的外部图片 URL，如果链接失效或网络不可达，请求会失败
   - 建议：使用可靠的图床或本地图片（参考 `08_local_image_and_text` 示例）

2. **模型版本硬编码**
   - `model="gpt-5.4"` 是硬编码的，可能随 API 更新而过时
   - 建议：从环境变量或配置文件读取模型名称

3. **错误处理缺失**
   - 示例没有展示错误处理（网络错误、API 错误、超时等）
   - 建议：添加 `try/except` 块和重试逻辑（参考 `10_error_handling_and_retry` 示例）

4. **并发限制**
   - `AsyncAppServerClient` 使用 `_transport_lock` 保护 stdio 传输
   - 当前不支持并发回合消费（见 `acquire_turn_consumer` 中的检查）

### 边界条件

1. **图片大小限制**
   - 远程图片受 OpenAI API 大小限制（通常几 MB）
   - 超大图片可能导致请求失败

2. **输入顺序**
   - 示例中 `TextInput` 在前，`ImageInput` 在后
   - 模型处理顺序可能与输入顺序一致，但无严格保证

3. **上下文长度**
   - 长对话历史可能触发上下文压缩或截断
   - 示例未展示上下文管理（参考 `06_thread_lifecycle_and_controls`）

### 改进建议

1. **添加类型注解**
   ```python
   async def main() -> None:
       ...
   ```
   已存在，但可为中间变量添加更多注解

2. **环境变量配置**
   ```python
   import os
   MODEL = os.getenv("CODEX_MODEL", "gpt-5.4")
   IMAGE_URL = os.getenv("CODEX_IMAGE_URL", DEFAULT_URL)
   ```

3. **流式输出支持**
   - 当前使用 `turn.run()` 等待完整结果
   - 可改为 `turn.stream()` 实现流式输出（参考 `03_turn_stream_events` 示例）

4. **批量图片支持**
   - 当前仅单张图片，可扩展为多张
   ```python
   inputs = [
       TextInput("Compare these images:"),
       ImageInput(url1),
       ImageInput(url2),
   ]
   ```

5. **与同步版本对比**
   - 同目录的 `sync.py` 展示了同步 API 用法
   - 两者功能相同，可根据应用场景选择

### 相关示例对比

| 示例 | 场景 | 关键区别 |
|------|------|----------|
| `07_image_and_text/async.py` | 异步 + 远程图片 | 使用 `async/await`，远程 URL |
| `07_image_and_text/sync.py` | 同步 + 远程图片 | 使用同步上下文管理器 |
| `08_local_image_and_text/async.py` | 异步 + 本地图片 | 使用 `LocalImageInput` 和临时文件 |

### 测试建议

1. **单元测试**：Mock `AsyncAppServerClient` 验证输入序列化
2. **集成测试**：使用真实 API 密钥运行（注意成本）
3. **边界测试**：测试无效 URL、超大图片、网络超时场景
