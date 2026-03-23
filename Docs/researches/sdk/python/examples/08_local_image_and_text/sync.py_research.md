# sync.py 研究文档

## 场景与职责

`sync.py` 是 Codex Python SDK 的同步示例程序，演示如何使用 `Codex` 客户端向 AI 模型发送**本地图像 + 文本**的多模态输入。该示例位于 `sdk/python/examples/08_local_image_and_text/` 目录，是 SDK 示例系列中第 8 个示例的同步版本。

核心职责：
1. 演示同步 SDK 的初始化与生命周期管理（`with` 上下文管理器）
2. 展示本地图像与文本的多模态输入组合
3. 展示如何读取和解析 AI 模型的响应结果

与 `async.py` 的区别仅在于使用同步 API（`Codex` 替代 `AsyncCodex`），功能完全一致。

## 功能点目的

### 1. 本地图像 + 文本多模态输入
与示例 07（`07_image_and_text`）使用远程 URL 图像不同，本示例使用**本地生成的临时图像**，演示 `LocalImageInput` 类的使用。

### 2. 同步编程模型
展示 `Codex`、`Thread`、`TurnHandle` 等同步 API 的正确使用方式，包括：
- 同步上下文管理器 (`with`)
- 阻塞式方法调用
- 同步迭代器 (`stream()`) 的处理

### 3. 临时图像生成
通过 `_bootstrap.py` 提供的 `temporary_sample_image_path()` 上下文管理器，生成一个 96x96 像素的四色 PNG 测试图像，无需外部依赖。

## 具体技术实现

### 关键流程

```
main()
├── temporary_sample_image_path()  # 生成临时测试图像
├── Codex(config=runtime_config())  # 初始化同步客户端
│   └── __enter__() → start() → initialize()  # 立即初始化
├── thread_start(model="gpt-5.4", config={...})  # 创建线程
├── thread.turn([TextInput, LocalImageInput])  # 创建 Turn
│   └── _to_wire_input()  # 将输入转换为 wire 格式
├── turn.run()  # 执行并等待完成
│   └── stream()  # 订阅通知流
│       └── 等待 turn/completed 通知
├── thread.read(include_turns=True)  # 读取持久化数据
└── assistant_text_from_turn()  # 提取助手回复文本
```

### 数据结构

**输入类型**（来自 `_inputs.py`）：
```python
@dataclass(slots=True)
class TextInput:
    text: str

@dataclass(slots=True)
class LocalImageInput:
    path: str  # 本地文件系统路径

InputItem = TextInput | ImageInput | LocalImageInput | SkillInput | MentionInput
```

**Wire 格式转换**（`_to_wire_item` 函数）：
```python
def _to_wire_item(item: InputItem) -> JsonObject:
    if isinstance(item, LocalImageInput):
        return {"type": "localImage", "path": item.path}
    # ...
```

**模型配置**：
```python
config={"model_reasoning_effort": "high"}  # 启用高级推理
```

### 协议与通信

**JSON-RPC 2.0 over stdio**：
- 请求：`turn/start` 方法，携带 `threadId` 和 `input` 数组
- 输入数组包含两个元素：
  - `{"type": "text", "text": "Read this generated local image..."}`
  - `{"type": "localImage", "path": "/tmp/.../generated_sample.png"}`

**同步通知流**：
- `TurnHandle.stream()` 返回 `Iterator[Notification]`
- 通过 `acquire_turn_consumer()` / `release_turn_consumer()` 管理并发
- 终止条件：`turn/completed` 通知且 `payload.turn.id == self.id`

### 关键代码路径

**1. 客户端初始化**（`sdk/python/src/codex_app_server/api.py:69-86`）
```python
class Codex:
    def __init__(self, config: AppServerConfig | None = None) -> None:
        self._client = AppServerClient(config=config)
        try:
            self._client.start()  # 启动子进程
            self._init = self._validate_initialize(self._client.initialize())
        except Exception:
            self._client.close()
            raise

    def __enter__(self) -> "Codex":
        return self

    def __exit__(self, _exc_type, _exc, _tb) -> None:
        self.close()
```

**2. 输入处理**（`sdk/python/src/codex_app_server/api.py:506-538`）
```python
def turn(self, input: Input, ...) -> TurnHandle:
    wire_input = _to_wire_input(input)  # 转换为 wire 格式
    params = TurnStartParams(...)
    turn = self._client.turn_start(self.id, wire_input, params=params)
    return TurnHandle(self._client, self.id, turn.turn.id)
```

**3. Turn 执行**（`sdk/python/src/codex_app_server/api.py:671-684`）
```python
def run(self) -> AppServerTurn:
    completed: TurnCompletedNotification | None = None
    stream = self.stream()
    try:
        for event in stream:
            payload = event.payload
            if isinstance(payload, TurnCompletedNotification) and payload.turn.id == self.id:
                completed = payload
    finally:
        stream.close()

    if completed is None:
        raise RuntimeError("turn completed event not received")
    return completed.turn
```

**4. 临时图像生成**（`_bootstrap.py:66-104`）
```python
def _generated_sample_png_bytes() -> bytes:
    # 生成 96x96 四色 PNG：
    # 左上: (120, 180, 255) - 浅蓝
    # 右上: (255, 220, 90)  - 黄色
    # 左下: (90, 180, 95)   - 绿色
    # 右下: (180, 85, 85)   - 红色
    # 使用 zlib 压缩 IDAT chunk
```

## 依赖与外部交互

### 内部依赖

| 模块 | 路径 | 用途 |
|------|------|------|
| `_bootstrap` | `examples/_bootstrap.py` | SDK 路径设置、临时图像生成、工具函数 |
| `codex_app_server` | `sdk/python/src/codex_app_server/__init__.py` | 公共 API 导出 |
| `Codex` | `api.py:69-268` | 同步客户端主类 |
| `Thread` | `api.py:467-549` | 同步线程操作 |
| `TurnHandle` | `api.py:643-684` | 同步 Turn 控制 |
| `LocalImageInput` | `_inputs.py:18-20` | 本地图像输入类型 |
| `TextInput` | `_inputs.py:8-10` | 文本输入类型 |

### 外部依赖

- `codex-cli-bin`：运行时二进制包（通过 `_bootstrap.py` 自动 provision）
- Python 标准库：`sys`, `pathlib`

### 运行时交互

1. **子进程启动**：`codex app-server --listen stdio://`
2. **初始化握手**：`initialize` JSON-RPC 请求
3. **线程创建**：`thread/start` 请求
4. **Turn 启动**：`turn/start` 请求，携带本地图像路径
5. **通知消费**：持续读取 stdout 直到收到 `turn/completed`

## 风险、边界与改进建议

### 风险点

1. **临时文件生命周期**
   - 临时图像在 `temporary_sample_image_path()` 上下文退出时删除
   - 如果 Turn 执行时间过长，可能导致图像在模型读取前被删除
   - **缓解**：当前示例 Turn 执行时间通常较短，且图像在 `turn.run()` 完成后才释放

2. **路径传递**
   - `LocalImageInput` 直接传递文件系统路径给 app-server
   - app-server 需要具有读取该路径的权限
   - **边界**：跨平台路径格式（Windows vs Unix）

3. **并发限制**
   - `acquire_turn_consumer()` 限制同时只能有一个活跃的 Turn 消费者
   - 尝试并发执行多个 Turn 会抛出 `RuntimeError`

4. **阻塞风险**
   - 同步 API 会阻塞当前线程直到 Turn 完成
   - 对于长时间运行的 Turn，建议使用 `async.py` 版本

### 边界条件

| 场景 | 行为 |
|------|------|
| 图像文件不存在 | app-server 返回错误，Turn 状态为 failed |
| 图像格式不支持 | 取决于模型和 app-server 的支持能力 |
| 大图像文件 | 受限于模型上下文窗口和 app-server 配置 |
| 相对路径 | `_bootstrap.py` 生成的是绝对路径，但 API 接受任何路径字符串 |

### 改进建议

1. **图像预处理**
   - 当前示例生成固定 96x96 的小图像，实际使用时可添加图像压缩/调整大小逻辑
   - 建议添加图像格式验证（MIME 类型检查）

2. **错误处理增强**
   ```python
   # 当前代码缺乏显式错误处理
   # 建议添加：
   try:
       result = thread.turn([...]).run()
   except AppServerError as e:
       print(f"Turn failed: {e}")
   ```

3. **资源管理优化**
   - 对于生产环境，建议实现图像上传至对象存储，使用 `ImageInput(url=...)` 替代本地路径
   - 考虑添加超时控制，避免无限期阻塞

4. **类型安全**
   - 当前 `LocalImageInput.path` 是 `str` 类型
   - 建议使用 `pathlib.Path` 类型并在序列化时转换为字符串

5. **测试覆盖**
   - 添加单元测试验证 `_generated_sample_png_bytes()` 生成的 PNG 有效性
   - 添加集成测试验证本地图像输入的端到端流程

6. **同步 vs 异步选择**
   - 在文档中明确说明：对于 I/O 密集型场景（如多图像处理），推荐使用 `async.py` 版本
   - 同步版本更适合简单的脚本和命令行工具
