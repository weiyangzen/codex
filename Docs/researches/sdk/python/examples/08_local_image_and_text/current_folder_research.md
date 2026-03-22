# 08_local_image_and_text 研究文档

## 1. 场景与职责

### 1.1 目标示例定位

`08_local_image_and_text` 是 Codex App Server Python SDK 的**多模态输入示例**，专门演示如何通过 SDK 向 Codex 服务发送**本地图像文件 + 文本**的混合输入。

与相邻示例的对比：

| 示例 | 功能 | 关键区别 |
|------|------|----------|
| `07_image_and_text` | 远程图片 + 文本 | 使用 `ImageInput(url)` 传入远程 HTTPS URL |
| `08_local_image_and_text` | 本地图片 + 文本 | 使用 `LocalImageInput(path)` 传入本地文件路径 |

### 1.2 核心职责

1. **演示本地图像输入的完整流程**：从生成临时测试图像 → 构建多模态输入 → 执行 Turn → 获取结果
2. **展示同步/异步两种编程模型的 API 使用模式**
3. **作为集成测试用例**：被 `test_real_app_server_integration.py` 引用验证端到端功能

---

## 2. 功能点目的

### 2.1 LocalImageInput 的设计意图

`LocalImageInput` 解决的核心问题是：**让用户能够直接将本地文件系统中的图像作为输入传递给 Codex，而无需自行处理文件读取、Base64 编码、Data URL 构造等底层细节**。

工作流程：

```
用户代码: LocalImageInput("/path/to/image.png")
    ↓
SDK (_inputs.py): 转换为 wire format {"type": "localImage", "path": "/path/to/image.png"}
    ↓
JSON-RPC (turn/start): 发送到 app-server
    ↓
Rust 后端 (codex-rs): 读取本地文件 → Base64 编码 → 构造 data URL → 传递给 LLM
```

### 2.2 与远程图像的区别

| 特性 | `ImageInput` (远程) | `LocalImageInput` (本地) |
|------|---------------------|--------------------------|
| 输入格式 | HTTPS URL | 本地文件系统绝对路径 |
| 数据读取 | 由服务端/LLM 直接拉取 | 由 codex-rs 读取并内联编码 |
| 使用场景 | 网络可访问的图像 | 本地截图、本地生成的图像 |
| 安全性 | 依赖 URL 可访问性 | 依赖本地文件系统权限 |

---

## 3. 具体技术实现

### 3.1 关键流程

#### 3.1.1 示例代码执行流程（以 sync.py 为例）

```python
# 1. 导入依赖
from codex_app_server import Codex, LocalImageInput, TextInput
from _bootstrap import temporary_sample_image_path, runtime_config

# 2. 使用上下文管理器生成临时测试图像
with temporary_sample_image_path() as image_path:
    # 3. 初始化 Codex 客户端（启动 app-server 子进程）
    with Codex(config=runtime_config()) as codex:
        # 4. 创建 Thread，指定模型和配置
        thread = codex.thread_start(
            model="gpt-5.4",
            config={"model_reasoning_effort": "high"}
        )
        
        # 5. 构建多模态输入（文本 + 本地图像）
        result = thread.turn([
            TextInput("Read this generated local image and summarize the colors/layout in 2 bullets."),
            LocalImageInput(str(image_path.resolve())),
        ]).run()  # 6. 执行 Turn 并等待完成
        
        # 7. 读取持久化状态验证结果
        persisted = thread.read(include_turns=True)
        persisted_turn = find_turn_by_id(persisted.thread.turns, result.id)
        
        # 8. 输出结果
        print("Status:", result.status)
        print(assistant_text_from_turn(persisted_turn))
```

#### 3.1.2 异步版本差异

`async.py` 与 `sync.py` 的核心差异：

| 组件 | 同步版 | 异步版 |
|------|--------|--------|
| 客户端类 | `Codex` | `AsyncCodex` |
| 上下文管理器 | `with Codex() as codex:` | `async with AsyncCodex() as codex:` |
| Thread 方法 | `thread.turn(...).run()` | `await (await thread.turn(...)).run()` |
| 方法调用 | 直接调用 | `await` 前缀 |

### 3.2 数据结构

#### 3.2.1 Python SDK 层

**LocalImageInput 定义** (`sdk/python/src/codex_app_server/_inputs.py`):

```python
@dataclass(slots=True)
class LocalImageInput:
    path: str

# Wire format 转换
if isinstance(item, LocalImageInput):
    return {"type": "localImage", "path": item.path}
```

**InputItem 联合类型**:

```python
InputItem = TextInput | ImageInput | LocalImageInput | SkillInput | MentionInput
```

#### 3.2.2 Wire Protocol 层

**生成的 Pydantic 模型** (`sdk/python/src/codex_app_server/generated/v2_all.py`):

```python
class LocalImageUserInput(BaseModel):
    path: str
    type: Annotated[Literal["localImage"], Field(title="LocalImageUserInputType")]
```

**UserInput 联合模型**:

```python
class UserInput(RootModel[...]):
    root: (
        TextUserInput
        | ImageUserInput
        | LocalImageUserInput  # <-- 本地图像变体
        | SkillUserInput
        | MentionUserInput
    )
```

#### 3.2.3 Rust 协议层

**Core UserInput 枚举** (`codex-rs/protocol/src/user_input.rs`):

```rust
#[derive(...)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum UserInput {
    Text { text: String, text_elements: Vec<TextElement> },
    Image { image_url: String },
    LocalImage { path: std::path::PathBuf },  // <-- 本地图像变体
    Skill { name: String, path: std::path::PathBuf },
    Mention { name: String, path: String },
}
```

**App-Server Protocol V2** (`codex-rs/app-server-protocol/src/protocol/v2.rs`):

```rust
pub enum UserInput {
    // ...
    LocalImage { path: PathBuf },
}

// 与 Core 类型的双向转换
impl UserInput {
    pub fn into_core(self) -> CoreUserInput {
        match self {
            UserInput::LocalImage { path } => CoreUserInput::LocalImage { path },
            // ...
        }
    }
}
```

### 3.3 协议与命令

#### 3.3.1 JSON-RPC 请求格式

**turn/start 方法请求体**（简化）：

```json
{
  "method": "turn/start",
  "id": "uuid",
  "params": {
    "threadId": "thr_xxx",
    "input": [
      {"type": "text", "text": "Read this generated local image..."},
      {"type": "localImage", "path": "/tmp/codex-python-example-image-xxx/generated_sample.png"}
    ],
    "model": "gpt-5.4",
    "modelReasoningEffort": "high"
  }
}
```

#### 3.3.2 本地图像处理流程（Rust 后端）

```rust
// codex-rs/protocol/src/models.rs:1120
UserInput::LocalImage { path } => {
    image_index += 1;
    match std::fs::read(&path) {
        Ok(file_bytes) => local_image_content_items_with_label_number(
            &path,
            file_bytes,
            Some(image_index),
            PromptImageMode::ResizeToFit,
        ),
        Err(err) => vec![local_image_error_placeholder(&path, err)],
    }
}
```

处理步骤：
1. 读取本地文件字节
2. 根据图像模式（ResizeToFit/Exact/Auto）处理
3. 编码为 Base64 Data URL
4. 包装为 LLM 可消费的 `ContentItem::InputImage`

---

## 4. 关键代码路径与文件引用

### 4.1 示例文件

| 文件 | 职责 |
|------|------|
| `sdk/python/examples/08_local_image_and_text/sync.py` | 同步 API 演示 |
| `sdk/python/examples/08_local_image_and_text/async.py` | 异步 API 演示 |

### 4.2 SDK 核心实现

| 文件 | 职责 |
|------|------|
| `sdk/python/src/codex_app_server/_inputs.py` | `LocalImageInput` 数据类定义及 Wire 格式转换 |
| `sdk/python/src/codex_app_server/api.py` | `Codex`/`AsyncCodex` 高层 API，`Thread.turn()` 方法 |
| `sdk/python/src/codex_app_server/client.py` | `AppServerClient` JSON-RPC 客户端，`turn_start()` 方法 |
| `sdk/python/src/codex_app_server/async_client.py` | `AsyncAppServerClient` 异步包装器 |
| `sdk/python/src/codex_app_server/generated/v2_all.py` | 生成的 Pydantic 模型，含 `LocalImageUserInput` |

### 4.3 测试与工具

| 文件 | 职责 |
|------|------|
| `sdk/python/examples/_bootstrap.py` | 示例引导工具，含 `temporary_sample_image_path()` 生成测试 PNG |
| `sdk/python/tests/test_real_app_server_integration.py` | 集成测试，验证示例可运行 |

### 4.4 Rust 后端实现

| 文件 | 职责 |
|------|------|
| `codex-rs/protocol/src/user_input.rs` | Core `UserInput::LocalImage` 定义 |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | V2 协议 `UserInput::LocalImage` 及转换逻辑 |
| `codex-rs/protocol/src/models.rs` | 本地图像文件读取、编码、错误处理 |
| `codex-rs/app-server/README.md` | 协议文档，示例含 `{"type":"localImage","path":"..."}` |

---

## 5. 依赖与外部交互

### 5.1 运行时依赖

```
示例代码
    ↓ 导入
_codex_bootstrap.py
    ↓ 调用
codex_app_server (Python SDK)
    ↓ JSON-RPC over stdio
codex app-server (Rust 二进制)
    ↓ HTTP API
OpenAI Responses API (LLM 服务)
```

### 5.2 关键依赖项

| 依赖 | 用途 |
|------|------|
| `pydantic>=2.12` | 数据验证与序列化 |
| `codex-cli-bin` | 捆绑的 Rust app-server 运行时 |
| `gpt-5.4` (模型) | 示例中指定的多模态模型 |

### 5.3 引导机制

示例通过 `_bootstrap.py` 中的 `temporary_sample_image_path()` 生成测试图像：

```python
@contextlib.contextmanager
def temporary_sample_image_path() -> Iterator[Path]:
    with tempfile.TemporaryDirectory(...) as temp_root:
        image_path = Path(temp_root) / "generated_sample.png"
        image_path.write_bytes(_generated_sample_png_bytes())
        yield image_path
```

生成的 PNG 特征：
- 尺寸：96x96 像素
- 四象限不同颜色（左上蓝、右上黄、左下绿、右下红）
- 格式：标准 PNG（IHDR + IDAT + IEND）

---

## 6. 风险、边界与改进建议

### 6.1 已知限制与风险

#### 6.1.1 并发限制

```python
# api.py:656-667
self._client.acquire_turn_consumer(self.id)
# ...
if (
    event.method == "turn/completed"
    and isinstance(event.payload, TurnCompletedNotification)
    and event.payload.turn.id == self.id
):
    break
```

**限制**：每个 `Codex`/`AsyncCodex` 实例同时只能有一个活跃的 Turn 消费者（`run()` 或 `stream()`）。尝试启动第二个会抛出 `RuntimeError`。

#### 6.1.2 本地文件访问风险

| 风险点 | 说明 |
|--------|------|
| 文件不存在 | Rust 后端会生成错误占位符，不会中断整个 Turn |
| 权限不足 | 同上，转化为错误内容项 |
| 大文件 | 示例使用 96x96 小图像；大图像会经过 ResizeToFit 处理 |
| 路径注入 | SDK 仅传递路径字符串，实际读取在 Rust 端受沙箱限制 |

#### 6.1.3 模型支持

- 示例硬编码使用 `gpt-5.4` 模型
- 若运行时该模型不可用或用户无权限，Turn 将失败
- 建议：生产代码应先用 `codex.models()` 查询可用模型

### 6.2 边界条件

| 边界 | 行为 |
|------|------|
| 空路径 | 依赖 Rust 端错误处理 |
| 相对路径 | 建议转换为绝对路径（示例使用 `path.resolve()`） |
| 非图像文件 | Rust 端会尝试读取，编码失败时生成错误占位符 |
| 并发多图像 | 当前实验性 SDK 仅支持单 Turn 消费者 |

### 6.3 改进建议

#### 6.3.1 示例层面

1. **增加模型可用性检查**：
   ```python
   available = codex.models()
   if "gpt-5.4" not in [m.id for m in available.models]:
       print("Warning: gpt-5.4 not available, using gpt-5")
   ```

2. **增加错误处理示例**：
   ```python
   try:
       result = thread.turn([...]).run()
   except AppServerRpcError as e:
       print(f"Turn failed: {e}")
   ```

3. **展示图像预处理选项**：当前示例使用默认 `ResizeToFit`，可展示如何配置图像模式

#### 6.3.2 SDK 层面

1. **路径验证**：在 Python 层增加 `Path.exists()` 预检查，提前发现文件不存在问题
2. **类型提示增强**：`LocalImageInput.path` 可考虑使用 `pathlib.Path` 类型而非纯字符串
3. **文档补充**：增加关于图像大小限制、支持格式的明确说明

#### 6.3.3 测试层面

当前集成测试仅验证示例可运行：

```python
# test_real_app_server_integration.py:525-526
elif folder in {"07_image_and_text", "08_local_image_and_text"}:
    assert "completed" in out.lower() or "Status:" in out
```

建议增强：
- 验证输出中包含对图像内容的实际描述（而非仅检查状态）
- 测试错误路径（如文件不存在时的行为）

---

## 7. 相关文档索引

| 文档 | 路径 |
|------|------|
| 示例 README | `sdk/python/examples/README.md` |
| API 参考 | `sdk/python/docs/api-reference.md` |
| 快速开始 | `sdk/python/docs/getting-started.md` |
| App-Server 协议文档 | `codex-rs/app-server/README.md` |
| Jupyter 教程 | `sdk/python/notebooks/sdk_walkthrough.ipynb` |

---

## 8. 总结

`08_local_image_and_text` 示例是 Python SDK 多模态能力的核心演示，展示了如何通过 `LocalImageInput` 将本地图像文件无缝集成到 Codex 对话流程中。其技术实现横跨 Python SDK（输入封装、Wire 格式转换）、JSON-RPC 协议传输、Rust 后端（文件读取、编码、LLM 交互）三个层次，是理解 Codex 多模态输入架构的关键切入点。
