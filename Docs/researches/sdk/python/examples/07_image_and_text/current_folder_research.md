# 07_image_and_text 示例研究文档

## 1. 场景与职责

### 1.1 定位与目标

`07_image_and_text` 是 Codex Python SDK 的**多模态输入示例**，演示如何通过 SDK 向 AI 模型同时提交**文本+远程图片**的混合输入，实现视觉理解能力。

### 1.2 示例演进位置

在 14 个示例序列中，本示例处于第 7 位：

| 序号 | 示例 | 核心能力 |
|------|------|----------|
| 05 | existing_thread | 线程恢复与复用 |
| 06 | thread_lifecycle_and_controls | 线程生命周期管理 |
| **07** | **image_and_text** | **多模态输入（远程图片+文本）** |
| 08 | local_image_and_text | 本地图片输入 |
| 09 | async_parity | 异步API对等性 |

### 1.3 核心职责

1. **展示多模态输入模式**：文本与图片作为独立 `InputItem` 组合提交
2. **演示远程图片引用**：通过 URL 引用外部图片资源
3. **验证视觉理解能力**：请求模型分析图片内容并给出结构化回答

---

## 2. 功能点目的

### 2.1 功能目标

| 功能点 | 目的 |
|--------|------|
| `TextInput` | 提供用户文本指令（"What is in this image? Give 3 bullets."） |
| `ImageInput` | 引用远程图片 URL（GitHub Python logo） |
| 输入列表组合 | 展示多模态输入的标准范式 |
| `model_reasoning_effort: high` | 启用高级推理能力以获得更准确的图像分析 |

### 2.2 业务价值

- **视觉问答（VQA）**：让 AI 理解图像内容并回答相关问题
- **文档分析**：可扩展至图表、截图、扫描件等分析场景
- **多模态交互**：为构建富媒体对话应用提供基础模式

---

## 3. 具体技术实现

### 3.1 关键流程

```
┌─────────────────────────────────────────────────────────────────┐
│                        07_image_and_text 执行流程                │
├─────────────────────────────────────────────────────────────────┤
│  1. 引导加载 (Bootstrap)                                         │
│     └── ensure_local_sdk_src()  # 将 sdk/python/src 加入 sys.path│
│                                                                  │
│  2. 客户端初始化                                                 │
│     └── with Codex(config=runtime_config()) as codex:            │
│         ├── AppServerClient 启动 stdio 子进程                    │
│         ├── 执行 JSON-RPC initialize 握手                        │
│         └── 验证 serverInfo/userAgent                            │
│                                                                  │
│  3. 线程创建                                                     │
│     └── thread_start(model="gpt-5.4", config={...})              │
│         └── 发送 thread/start RPC 请求                           │
│                                                                  │
│  4. 多模态输入构建                                               │
│     └── turn([TextInput(...), ImageInput(REMOTE_IMAGE_URL)])     │
│         ├── _to_wire_input() 将输入项序列化为 wire 格式          │
│         │   ├── TextInput → {"type": "text", "text": "..."}      │
│         │   └── ImageInput → {"type": "image", "url": "..."}     │
│         └── 发送 turn/start RPC 请求                             │
│                                                                  │
│  5. 执行与等待                                                   │
│     └── turn.run()                                               │
│         ├── 订阅 turn/completed 通知                             │
│         └── 返回 AppServerTurn 对象                              │
│                                                                  │
│  6. 结果读取与展示                                               │
│     └── thread.read(include_turns=True)                          │
│         └── assistant_text_from_turn() 提取助手回复文本          │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 核心数据结构

#### 3.2.1 输入类型定义（`_inputs.py`）

```python
@dataclass(slots=True)
class TextInput:
    text: str

@dataclass(slots=True)
class ImageInput:
    url: str  # 远程图片 URL

@dataclass(slots=True)
class LocalImageInput:
    path: str  # 本地文件路径（示例 08 使用）

# 联合类型定义
InputItem = TextInput | ImageInput | LocalImageInput | SkillInput | MentionInput
Input = list[InputItem] | InputItem
```

#### 3.2.2 Wire 格式转换（`_inputs.py:40-51`）

```python
def _to_wire_item(item: InputItem) -> JsonObject:
    if isinstance(item, TextInput):
        return {"type": "text", "text": item.text}
    if isinstance(item, ImageInput):
        return {"type": "image", "url": item.url}
    if isinstance(item, LocalImageInput):
        return {"type": "localImage", "path": item.path}
    # ... SkillInput, MentionInput
```

转换后的 JSON-RPC 请求体示例：

```json
{
  "method": "turn/start",
  "params": {
    "threadId": "thread-xxx",
    "input": [
      {"type": "text", "text": "What is in this image? Give 3 bullets."},
      {"type": "image", "url": "https://raw.githubusercontent.com/.../python.png"}
    ],
    "model": "gpt-5.4"
  }
}
```

### 3.3 协议与通信

#### 3.3.1 JSON-RPC 2.0 over stdio

- **传输层**：`codex app-server --listen stdio://` 子进程
- **协议**：JSON-RPC 2.0（行分隔）
- **请求类型**：
  - `thread/start`：创建新线程
  - `turn/start`：启动新一轮对话
  - `thread/read`：读取线程状态

#### 3.3.2 通知机制

```python
# TurnHandle.run() 内部等待逻辑
while True:
    event = self._client.next_notification()
    if (event.method == "turn/completed" and 
        event.payload.turn.id == self.id):
        break
```

### 3.4 关键代码路径

#### 3.4.1 同步版本（`sync.py`）

```python
# sdk/python/examples/07_image_and_text/sync.py
REMOTE_IMAGE_URL = "https://raw.githubusercontent.com/github/explore/main/topics/python/python.png"

with Codex(config=runtime_config()) as codex:
    thread = codex.thread_start(
        model="gpt-5.4", 
        config={"model_reasoning_effort": "high"}
    )
    turn = thread.turn([
        TextInput("What is in this image? Give 3 bullets."),
        ImageInput(REMOTE_IMAGE_URL),
    ])
    result = turn.run()
    persisted = thread.read(include_turns=True)
    persisted_turn = find_turn_by_id(persisted.thread.turns, result.id)
    print("Status:", result.status)
    print(assistant_text_from_turn(persisted_turn))
```

#### 3.4.2 异步版本（`async.py`）

```python
# sdk/python/examples/07_image_and_text/async.py
async with AsyncCodex(config=runtime_config()) as codex:
    thread = await codex.thread_start(
        model="gpt-5.4", 
        config={"model_reasoning_effort": "high"}
    )
    turn = await thread.turn([
        TextInput("What is in this image? Give 3 bullets."),
        ImageInput(REMOTE_IMAGE_URL),
    ])
    result = await turn.run()
    persisted = await thread.read(include_turns=True)
    persisted_turn = find_turn_by_id(persisted.thread.turns, result.id)
    print("Status:", result.status)
    print(assistant_text_from_turn(persisted_turn))
```

#### 3.4.3 输入处理链（`api.py:506-538`）

```python
# Thread.turn() 方法
def turn(
    self,
    input: Input,
    *,
    approval_policy: AskForApproval | None = None,
    # ... 其他参数
) -> TurnHandle:
    wire_input = _to_wire_input(input)  # ← 输入转换
    params = TurnStartParams(
        thread_id=self.id,
        input=wire_input,
        # ...
    )
    turn = self._client.turn_start(self.id, wire_input, params=params)
    return TurnHandle(self._client, self.id, turn.turn.id)
```

---

## 4. 关键代码路径与文件引用

### 4.1 本示例文件

| 文件 | 职责 |
|------|------|
| `sdk/python/examples/07_image_and_text/sync.py` | 同步版本示例 |
| `sdk/python/examples/07_image_and_text/async.py` | 异步版本示例 |

### 4.2 依赖文件

| 文件 | 职责 |
|------|------|
| `sdk/python/examples/_bootstrap.py` | 示例引导工具（路径设置、SDK加载、辅助函数） |
| `sdk/python/src/codex_app_server/_inputs.py` | 输入类型定义与 wire 格式转换 |
| `sdk/python/src/codex_app_server/api.py` | 高层 API（Codex/Thread/TurnHandle） |
| `sdk/python/src/codex_app_server/client.py` | JSON-RPC 客户端实现 |
| `sdk/python/src/codex_app_server/async_client.py` | 异步客户端包装器 |
| `sdk/python/src/codex_app_server/_run.py` | RunResult 收集与处理 |

### 4.3 生成模型文件

| 文件 | 职责 |
|------|------|
| `sdk/python/src/codex_app_server/generated/v2_all.py` | App Server v2 API 模型（Pydantic） |
| `sdk/python/src/codex_app_server/generated/notification_registry.py` | 通知类型注册表 |

### 4.4 测试文件

| 文件 | 相关测试 |
|------|----------|
| `sdk/python/tests/test_real_app_server_integration.py` | `test_real_examples_run_and_assert` 包含 07_image_and_text |

---

## 5. 依赖与外部交互

### 5.1 内部依赖关系

```
07_image_and_text/
    ├── sync.py / async.py
    │       └── from _bootstrap import ...
    │       └── from codex_app_server import Codex/AsyncCodex, ImageInput, TextInput
    │
    └── 依赖链：
            codex_app_server.api.Codex/AsyncCodex
                ├── AppServerClient/AsyncAppServerClient
                │       └── subprocess.Popen(['codex', 'app-server', '--listen', 'stdio://'])
                ├── Thread/AsyncThread
                │       └── turn() → TurnHandle/AsyncTurnHandle
                │               └── run() → 等待 turn/completed 通知
                └── _inputs._to_wire_input()
                        └── TextInput/ImageInput → wire JSON
```

### 5.2 外部依赖

| 依赖 | 用途 |
|------|------|
| `codex-cli-bin` (Rust 二进制) | App Server 运行时，通过 stdio 提供 JSON-RPC 服务 |
| `pydantic>=2.12` | 数据验证与序列化 |
| GitHub 图片 URL | 示例中使用的远程测试图片 |

### 5.3 运行时交互

```
┌─────────────────┐      stdio      ┌─────────────────────────┐
│  Python SDK     │ ◄──────────────► │  codex app-server       │
│  (本示例)       │   JSON-RPC 2.0   │  (Rust 二进制)          │
└─────────────────┘                  └─────────────────────────┘
        │                                        │
        │ turn/start (with image URL)            │
        │───────────────────────────────────────>│
        │                                        │
        │ <──────────────────────────────────────│
        │    turn/completed (with analysis)      │
        │                                        │
        ▼                                        ▼
   OpenAI API (via Rust backend)
   - 图片下载与处理
   - GPT-5.4 视觉推理
   - 返回结构化分析结果
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险类别 | 描述 | 影响 |
|----------|------|------|
| **网络依赖** | 远程图片 URL 必须可访问 | 网络故障时示例失败 |
| **图片可用性** | GitHub raw 链接可能变更 | 示例运行失败 |
| **并发限制** | 实验性 SDK 仅支持单 turn consumer | 并发 turn 会抛 RuntimeError |
| **模型依赖** | 需要支持视觉的模型（gpt-5.4） | 使用非视觉模型时效果差 |

### 6.2 边界条件

| 边界 | 说明 |
|------|------|
| 图片格式 | 依赖后端模型支持的格式（通常 PNG/JPG/WebP） |
| 图片大小 | 受模型 context window 和 API 限制 |
| URL 类型 | 必须是公开可访问的 HTTP(S) URL |
| 输入顺序 | TextInput + ImageInput 顺序不影响功能 |

### 6.3 改进建议

#### 6.3.1 示例层面

1. **增加错误处理**
   ```python
   # 建议添加网络超时和重试
   try:
       result = turn.run()
   except TransportClosedError as e:
       # 处理连接失败
   ```

2. **使用更稳定的图片源**
   - 可考虑使用 data URI 或内嵌 base64 图片
   - 或提供备用图片 URL

3. **增加输入验证示例**
   ```python
   # 展示如何验证图片 URL 格式
   from urllib.parse import urlparse
   def validate_image_url(url: str) -> bool:
       parsed = urlparse(url)
       return parsed.scheme in ('http', 'https')
   ```

#### 6.3.2 SDK 层面

1. **ImageInput 增强**
   - 支持 base64 编码图片内嵌
   - 添加 URL 验证装饰器
   - 支持图片尺寸/格式提示

2. **批量图片支持**
   ```python
   # 当前：Input = list[InputItem] | InputItem
   # 已支持多图，但示例未展示
   turn([ImageInput(url1), ImageInput(url2), TextInput("对比这两张图")])
   ```

3. **本地缓存机制**
   - 对远程图片添加可选的本地缓存
   - 避免重复下载

#### 6.3.3 文档层面

1. **增加视觉模型说明**
   - 明确列出支持视觉的模型
   - 说明不同模型的视觉能力差异

2. **添加故障排查指南**
   - 图片加载失败的常见原因
   - 网络代理配置说明

### 6.4 与 08_local_image_and_text 的对比

| 特性 | 07_image_and_text | 08_local_image_and_text |
|------|-------------------|-------------------------|
| 输入类型 | `ImageInput(url)` | `LocalImageInput(path)` |
| 图片源 | 远程 URL | 本地文件系统 |
| 使用场景 | Web 图片分析 | 本地截图/文档分析 |
| 依赖 | 网络连接 | 文件系统访问 |
| 辅助函数 | 无 | `temporary_sample_image_path()` |

---

## 7. 附录

### 7.1 相关示例索引

| 示例 | 与本示例关系 |
|------|-------------|
| `02_turn_run` | 基础 turn 执行模式 |
| `08_local_image_and_text` | 本地图片变体 |
| `12_turn_params_kitchen_sink` | 完整参数展示 |

### 7.2 关键源码引用

```
sdk/python/examples/07_image_and_text/
├── sync.py                 # 同步示例入口
└── async.py                # 异步示例入口

sdk/python/src/codex_app_server/
├── __init__.py             # 公开 API 导出
├── _inputs.py              # 输入类型定义
│   ├── TextInput
│   ├── ImageInput
│   ├── LocalImageInput
│   ├── _to_wire_item()
│   └── _to_wire_input()
├── api.py                  # 高层 API
│   ├── Codex.thread_start()
│   ├── Thread.turn()
│   └── TurnHandle.run()
├── client.py               # 同步 JSON-RPC 客户端
│   ├── AppServerClient.turn_start()
│   └── AppServerClient.thread_read()
└── async_client.py         # 异步包装器
    └── AsyncAppServerClient
```

### 7.3 测试覆盖

```python
# sdk/python/tests/test_real_app_server_integration.py
EXAMPLE_CASES = [
    # ...
    ("07_image_and_text", "sync.py"),
    ("07_image_and_text", "async.py"),
    # ...
]

# 测试断言
def test_real_examples_run_and_assert(...):
    if folder in {"07_image_and_text", "08_local_image_and_text"}:
        assert "completed" in out.lower() or "Status:" in out
```
