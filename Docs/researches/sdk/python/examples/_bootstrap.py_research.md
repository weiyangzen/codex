# sdk/python/examples/_bootstrap.py 研究文档

## 场景与职责

`_bootstrap.py` 是 OpenAI Codex Python SDK 示例集合的核心引导模块，位于 `sdk/python/examples/` 目录下。该模块承担以下关键职责：

1. **本地 SDK 源码加载**：无需安装 wheel 包，直接将 `sdk/python/src` 添加到 Python 路径，使示例能够使用最新源码运行
2. **运行时依赖检查**：验证 `pydantic` 等必要依赖是否已安装
3. **运行时配置工厂**：提供 `runtime_config()` 函数返回预配置的 `AppServerConfig` 实例
4. **示例工具函数**：提供图像生成、服务器标签提取、turn 数据检索等共享工具

该模块是连接示例代码与 SDK 核心的桥梁，确保示例能够在开发环境中无缝运行。

## 功能点目的

### 1. 本地 SDK 源码注入 (`ensure_local_sdk_src`)

**目的**：允许示例直接从本地源码树运行，而不需要安装 SDK wheel 包。

**实现机制**：
```python
_SDK_PYTHON_DIR = Path(__file__).resolve().parents[1]  # 定位到 sdk/python/
src_dir = sdk_python_dir / "src"                        # sdk/python/src
package_dir = src_dir / "codex_app_server"             # 验证包存在
sys.path.insert(0, str(src_dir))                       # 优先插入路径
```

**价值**：
- 开发迭代：修改源码后立即生效，无需重新安装
- CI/CD：可以直接测试最新代码
- 调试便利：源码可见，便于追踪问题

### 2. 运行时依赖验证 (`_ensure_runtime_dependencies`)

**目的**：在尝试导入 SDK 前验证关键依赖 `pydantic` 是否可用。

**实现**：
```python
if importlib.util.find_spec("pydantic") is not None:
    return  # 依赖已满足
# 否则抛出详细的 RuntimeError，包含安装指令
```

**错误信息设计**：
- 显示当前使用的 Python 解释器路径
- 提供具体的 pip 安装命令
- 提示使用相同解释器安装

### 3. 运行时配置工厂 (`runtime_config`)

**目的**：为示例提供预配置、开箱即用的 `AppServerConfig` 实例。

**流程**：
```python
def runtime_config():
    from codex_app_server import AppServerConfig
    ensure_runtime_package_installed(sys.executable, _SDK_PYTHON_DIR)
    return AppServerConfig()  # 使用默认配置
```

**副作用**：首次调用可能触发 `codex-cli-bin` 运行时的下载和安装。

### 4. 样本 PNG 图像生成 (`_generated_sample_png_bytes`)

**目的**：为 `08_local_image_and_text` 示例提供测试图像，无需外部文件依赖。

**技术实现**：
- 纯 Python 实现 PNG 编码（无 PIL 依赖）
- 生成 96x96 像素的四色渐变图像
- 使用 zlib 压缩和 CRC32 校验
- 符合 PNG 规范（IHDR、IDAT、IEND 块）

**颜色布局**：
```
┌─────────────┬─────────────┐
│ 蓝 (120,180,255) │ 黄 (255,220,90)  │
├─────────────┼─────────────┤
│ 绿 (90,180,95)   │ 红 (180,85,85)   │
└─────────────┴─────────────┘
```

### 5. 临时图像上下文管理器 (`temporary_sample_image_path`)

**目的**：为需要本地图像的示例提供临时文件，确保自动清理。

**使用模式**：
```python
with temporary_sample_image_path() as image_path:
    # image_path 指向生成的 PNG 文件
    ...
# 退出上下文后临时目录自动删除
```

### 6. 服务器标签提取 (`server_label`)

**目的**：从 `initialize` 响应元数据中提取可读的服务器标识字符串。

**逻辑**：
1. 优先使用 `serverInfo.name` + `serverInfo.version`
2. 回退到 `userAgent` 字段
3. 最终回退到 `"unknown"`

**输出示例**：`"Codex 0.116.0-alpha.1"`

### 7. Turn 检索工具 (`find_turn_by_id`)

**目的**：在 thread turns 列表中按 ID 查找特定 turn。

**应用场景**：验证持久化后的 turn 数据与运行时返回的一致性。

### 8. 助手文本提取 (`assistant_text_from_turn`)

**目的**：从 turn 对象中提取助手的文本响应，支持多种消息格式。

**支持的格式**：
- `agentMessage` 类型（直接 `text` 字段）
- `message` 类型 + `role=assistant` + `output_text` 内容

**容错设计**：
- 处理 `None` 输入
- 安全访问可能缺失的属性
- 使用 `model_dump(mode="json")` 处理 Pydantic 模型

## 具体技术实现

### PNG 生成技术细节

#### `_png_chunk` 函数
```python
def _png_chunk(chunk_type: bytes, data: bytes) -> bytes:
    import struct
    payload = chunk_type + data
    checksum = zlib.crc32(payload) & 0xFFFFFFFF  # CRC32 校验
    return (
        struct.pack(">I", len(data)) +    # 长度（大端 4 字节）
        payload +                          # 类型 + 数据
        struct.pack(">I", checksum)       # CRC32（大端 4 字节）
    )
```

#### PNG 文件结构
```
[PNG 签名: 8 字节] +
[IHDR 块: 13 字节图像头] +
[IDAT 块: zlib 压缩的像素数据] +
[IEND 块: 空数据结束标记]
```

#### 像素数据格式
- 每行以滤波器字节 `0` 开头
- RGB 格式（3 字节/像素）
- 无 Alpha 通道

### 路径处理策略

```python
_SDK_PYTHON_DIR = Path(__file__).resolve().parents[1]
```

该表达式计算：
1. `__file__` → `_bootstrap.py` 路径
2. `.resolve()` → 绝对路径（解析符号链接）
3. `.parents[1]` → 上级目录（`examples/` 的父目录 = `sdk/python/`）

### 导入时副作用控制

模块在导入时执行以下操作：
1. 计算 `_SDK_PYTHON_DIR` 和 `_SDK_PYTHON_STR`
2. 将 `_SDK_PYTHON_STR` 插入 `sys.path`（如果尚未存在）
3. 从 `_runtime_setup` 导入 `ensure_runtime_package_installed`

**注意**：实际的 SDK 源码注入和依赖检查延迟到 `ensure_local_sdk_src()` 调用时执行。

## 关键代码路径与文件引用

### 模块依赖图
```
_bootstrap.py
    ├── _runtime_setup.py          # 运行时安装逻辑
    │       └── scripts/update_sdk_artifacts.py  # 包构建脚本
    └── codex_app_server (通过路径注入)
            ├── __init__.py        # 公共 API
            ├── api.py             # Codex/AsyncCodex 类
            ├── client.py          # AppServerConfig
            └── models.py          # 数据模型
```

### 示例使用模式

每个示例文件遵循以下导入模式：

```python
import sys
from pathlib import Path

# 步骤 1: 将 examples 目录添加到路径
_EXAMPLES_ROOT = Path(__file__).resolve().parents[1]
if str(_EXAMPLES_ROOT) not in sys.path:
    sys.path.insert(0, str(_EXAMPLES_ROOT))

# 步骤 2: 从 _bootstrap 导入所需函数
from _bootstrap import (
    ensure_local_sdk_src,
    runtime_config,
    server_label,           # 可选
    assistant_text_from_turn,  # 可选
    ...
)

# 步骤 3: 执行本地 SDK 注入
ensure_local_sdk_src()

# 步骤 4: 导入 SDK 并运行
from codex_app_server import Codex
with Codex(config=runtime_config()) as codex:
    ...
```

### 跨文件函数使用矩阵

| 函数 | 使用示例 |
|------|---------|
| `ensure_local_sdk_src` | 所有示例 |
| `runtime_config` | 所有示例 |
| `server_label` | `01_quickstart_constructor`, `04_models_and_metadata` |
| `assistant_text_from_turn` | `02_turn_run`, `03_turn_stream_events`, `08_local_image_and_text`, `10_error_handling_and_retry` |
| `find_turn_by_id` | `03_turn_stream_events`, `05_existing_thread`, `08_local_image_and_text`, `10_error_handling_and_retry` |
| `temporary_sample_image_path` | `08_local_image_and_text` |

## 依赖与外部交互

### Python 标准库依赖
| 模块 | 用途 |
|------|------|
| `contextlib` | `@contextlib.contextmanager` 装饰器 |
| `importlib.util` | `find_spec` 检查模块存在性 |
| `os` | 环境变量访问（间接） |
| `sys` | 路径操作和解释器信息 |
| `tempfile` | `TemporaryDirectory` 临时文件管理 |
| `zlib` | PNG 数据压缩和 CRC32 计算 |
| `pathlib.Path` | 路径操作 |
| `struct` | PNG 二进制数据打包（运行时导入） |

### 外部包依赖
| 包 | 用途 | 检查方式 |
|---|------|---------|
| `pydantic` | SDK 数据模型验证 | `importlib.util.find_spec` |

### 运行时依赖（通过 `_runtime_setup`）
| 组件 | 用途 |
|------|------|
| `codex-cli-bin` | Rust 实现的 Codex 运行时二进制 |

### 文件系统交互
1. **读取**：检查 `sdk/python/src/codex_app_server` 存在性
2. **写入**：生成临时 PNG 文件到临时目录
3. **清理**：`temporary_sample_image_path` 退出时自动删除临时目录

## 风险、边界与改进建议

### 当前风险

1. **路径硬编码风险**
   ```python
   _SDK_PYTHON_DIR = Path(__file__).resolve().parents[1]
   ```
   - 假设模块位于 `examples/` 子目录
   - 如果移动文件，路径计算会出错

2. **全局状态修改**
   ```python
   sys.path.insert(0, _SDK_PYTHON_STR)
   ```
   - 修改全局 `sys.path` 可能影响其他导入
   - 重复导入可能导致路径重复（虽然有检查）

3. **PNG 生成性能**
   - 每次调用生成完整 PNG 数据
   - 对于大图像或高频调用可能较慢
   - 当前 96x96 尺寸较小，影响不大

4. **依赖检查时机**
   - `pydantic` 检查在 `ensure_local_sdk_src` 中执行
   - 如果直接导入 `codex_app_server` 而不调用该函数，可能得到不友好的导入错误

### 边界条件

1. **并发安全**
   - `sys.path` 修改不是线程安全的
   - 多线程环境下同时导入可能导致竞态条件

2. **临时目录限制**
   - `temporary_sample_image_path` 使用系统临时目录
   - 某些环境可能限制临时目录访问或大小

3. **图像尺寸限制**
   - 硬编码 96x96 像素
   - 不支持自定义尺寸或颜色

4. **文本提取限制**
   - `assistant_text_from_turn` 仅支持特定消息格式
   - 新消息类型需要更新代码

### 改进建议

1. **路径计算鲁棒性**
   ```python
   # 建议：添加验证和更灵活的查找
   def _find_sdk_root() -> Path:
       start = Path(__file__).resolve()
       for parent in start.parents:
           if (parent / "src" / "codex_app_server").exists():
               return parent
       raise RuntimeError("Could not find SDK root")
   ```

2. **PNG 缓存机制**
   ```python
   # 建议：缓存生成的 PNG 数据
   @functools.lru_cache(maxsize=1)
   def _generated_sample_png_bytes() -> bytes:
       ...
   ```

3. **增强图像生成**
   ```python
   # 建议：支持自定义参数
   def generate_sample_image(
       width: int = 96,
       height: int = 96,
       colors: list[tuple[int, int, int]] | None = None
   ) -> bytes:
       ...
   ```

4. **依赖检查前置**
   ```python
   # 建议：模块导入时即检查
   try:
       import pydantic
   except ImportError:
       raise RuntimeError("pydantic is required...") from None
   ```

5. **类型注解完善**
   ```python
   # 建议：为 turn 参数使用更具体的类型
   from codex_app_server import Turn
   def find_turn_by_id(turns: Iterable[Turn] | None, turn_id: str) -> Turn | None:
       ...
   ```

6. **文本提取扩展**
   ```python
   # 建议：支持更多内容类型
   def extract_content_from_turn(
       turn: object | None,
       content_types: list[str] | None = None
   ) -> dict[str, list[str]]:
       # 返回按类型分组的文本内容
       ...
   ```

7. **添加日志记录**
   ```python
   import logging
   logger = logging.getLogger(__name__)
   
   def ensure_local_sdk_src() -> Path:
       logger.debug(f"Injecting SDK from {src_dir}")
       ...
   ```

### 测试建议

1. **单元测试**
   - 测试 `_png_chunk` 生成有效 PNG 块
   - 测试 `_generated_sample_png_bytes` 生成有效 PNG 文件
   - 测试 `server_label` 的各种输入组合
   - 测试 `find_turn_by_id` 的边界条件

2. **集成测试**
   - 测试 `ensure_local_sdk_src` 成功注入路径
   - 测试 `temporary_sample_image_path` 正确清理

3. **Mock 测试**
   - Mock `importlib.util.find_spec` 测试依赖检查
   - Mock `sys.path` 测试路径注入

### 相关文件完整列表

```
sdk/python/
├── examples/
│   ├── _bootstrap.py              # 本文档分析的文件
│   ├── 01_quickstart_constructor/
│   │   ├── sync.py               # 使用 _bootstrap
│   │   └── async.py
│   ├── ...
│   └── 14_turn_controls/
│       ├── sync.py
│       └── async.py
├── _runtime_setup.py              # 运行时安装
├── src/codex_app_server/
│   ├── __init__.py
│   ├── api.py                     # Codex 类
│   ├── client.py                  # AppServerConfig
│   ├── models.py
│   └── generated/v2_all.py        # 生成类型
└── scripts/
    └── update_sdk_artifacts.py    # 运行时包构建
```
