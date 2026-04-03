# sdk/python/src/codex_app_server/_inputs.py 研究文档

## 场景与职责

`_inputs.py` 是 Codex Python SDK 的**输入类型定义模块**，负责定义用户与 SDK 交互时使用的所有输入类型。作为内部模块（以下划线开头），它提供：

1. **类型安全的输入抽象**：将用户的各种输入形式（字符串、图片、技能引用等）封装为强类型数据结构
2. **协议转换层**：将 Python 友好的输入类型转换为 JSON-RPC 传输格式（wire format）
3. **输入规范化**：处理输入的多种形式（单条/列表、字符串快捷方式等）

## 功能点目的

### 1. 输入类型定义

| 类型 | 用途 | 属性 |
|-----|------|------|
| `TextInput` | 文本输入 | `text: str` |
| `ImageInput` | 网络图片 | `url: str` |
| `LocalImageInput` | 本地图片 | `path: str` |
| `SkillInput` | 技能引用 | `name: str`, `path: str` |
| `MentionInput` | 提及引用 | `name: str`, `path: str` |

### 2. 类型联合定义

```python
InputItem = TextInput | ImageInput | LocalImageInput | SkillInput | MentionInput
Input = list[InputItem] | InputItem                    # 单条或多条输入
RunInput = Input | str                                 # 支持字符串快捷方式
```

### 3. 协议转换函数

- `_to_wire_item(item: InputItem) -> JsonObject`：单条输入 → JSON-RPC 格式
- `_to_wire_input(input: Input) -> list[JsonObject]`：多条输入 → JSON-RPC 数组
- `_normalize_run_input(input: RunInput) -> Input`：字符串快捷方式 → TextInput

## 具体技术实现

### 数据结构定义

使用 `@dataclass(slots=True)` 定义所有输入类型，启用 `slots` 带来以下优势：
- 内存效率提升（无 `__dict__`）
- 属性访问速度更快
- 防止动态添加属性（类型安全）

```python
@dataclass(slots=True)
class TextInput:
    text: str
```

### 协议转换映射

| 输入类型 | Wire 格式 | 字段映射 |
|---------|----------|---------|
| `TextInput` | `{"type": "text", "text": ...}` | `text` → `text` |
| `ImageInput` | `{"type": "image", "url": ...}` | `url` → `url` |
| `LocalImageInput` | `{"type": "localImage", "path": ...}` | `path` → `path` |
| `SkillInput` | `{"type": "skill", "name": ..., "path": ...}` | `name`, `path` → 同名 |
| `MentionInput` | `{"type": "mention", "name": ..., "path": ...}` | `name`, `path` → 同名 |

### 输入规范化流程

```
RunInput (str | Input)
    ↓ _normalize_run_input
Input (InputItem | list[InputItem])
    ↓ _to_wire_input
list[JsonObject] (wire format)
    ↓ _to_wire_item (per item)
JsonObject (single item wire format)
```

## 关键代码路径与文件引用

### 被调用方

```
api.py
├── Thread.run() → _normalize_run_input() → _to_wire_input()
├── Thread.turn() → _to_wire_input()
├── AsyncThread.run() → _normalize_run_input() → _to_wire_input()
└── AsyncThread.turn() → _to_wire_input()
```

### 调用链示例

**同步 Thread.run() 调用链：**
```python
# api.py:Thread.run
input = _normalize_run_input(input)  # str → TextInput
turn = self.turn(input, ...)          # 内部调用
stream = turn.stream()                # 获取事件流
_collect_run_result(stream, ...)      # 收集结果
```

**输入转换流程：**
```python
# 用户调用
thread.run("hello")  # str

# _normalize_run_input 转换
→ TextInput(text="hello")  # InputItem

# _to_wire_input 转换
→ [{"type": "text", "text": "hello"}]  # list[JsonObject]

# 传递给 turn_start RPC
client.turn_start(thread_id, wire_input, params)
```

## 依赖与外部交互

### 内部依赖

| 符号 | 来源 | 用途 |
|-----|------|------|
| `JsonObject` | `.models` | Wire 格式的类型注解 |

### 被依赖方

| 模块 | 使用方式 |
|-----|---------|
| `api.py` | 导入所有输入类型和转换函数 |
| `__init__.py` | 通过 `api.py` 间接导出公共 API |

## 风险、边界与改进建议

### 当前风险

1. **类型扩展性**：新增输入类型需要修改 `_to_wire_item` 的 `if/elif` 链，容易遗漏
2. **无验证逻辑**：输入类型仅做数据容器，不对内容做验证（如 URL 格式、路径存在性等）
3. **字符串快捷方式的歧义**：`RunInput` 接受 `str`，但无法区分 "纯文本" 和 "需要解析的指令"

### 边界情况

1. **空输入处理**：未对空字符串、空列表做特殊处理，直接透传给服务器
2. **混合类型输入**：`Input` 支持 `list[InputItem]`，可以混合文本、图片等多种类型
3. **类型守卫**：`_to_wire_item` 最后的 `raise TypeError` 作为穷尽检查，理论上不会触发（Python 类型系统无法保证）

### 改进建议

1. **使用 match/case（Python 3.10+）**：
   ```python
   def _to_wire_item(item: InputItem) -> JsonObject:
       match item:
           case TextInput(text=text):
               return {"type": "text", "text": text}
           # ...
   ```

2. **添加输入验证**：
   ```python
   @dataclass(slots=True)
   class ImageInput:
       url: str
       def __post_init__(self):
           if not self.url.startswith(("http://", "https://")):
               raise ValueError(f"Invalid URL: {self.url}")
   ```

3. **支持更多输入类型**：
   - `FileInput`：通用文件上传
   - `AudioInput`：音频输入
   - `VideoInput`：视频输入

4. **延迟加载优化**：
   对于 `LocalImageInput`，当前仅传递路径，建议支持：
   - 自动检测文件存在性
   - 自动 MIME 类型检测
   - Base64 编码（如果需要）

5. **文档和示例**：
   添加 docstring 说明每种输入类型的使用场景和限制

### 测试覆盖

相关测试：
- `test_public_api_runtime_behavior.py::test_thread_run_accepts_string_input_and_returns_run_result`
- `test_public_api_runtime_behavior.py::test_async_thread_run_accepts_string_input_and_returns_run_result`

这些测试验证了字符串输入的自动转换和正确处理。
