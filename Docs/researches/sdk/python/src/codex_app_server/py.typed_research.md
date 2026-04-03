# sdk/python/src/codex_app_server/py.typed 研究文档

## 场景与职责

`py.typed` 是 Python **PEP 561** 规定的类型标记文件，用于指示该包支持类型检查。它的存在告诉类型检查器（如 mypy、pyright）该包包含类型信息，应该进行类型检查。

## 功能点目的

### 1. PEP 561 合规

根据 [PEP 561](https://peps.python.org/pep-0561/)，Python 包可以通过包含 `py.typed` 文件来声明自己是类型化的（typed package）。这使得：

- 类型检查器可以对该包进行类型检查
- IDE 可以提供更好的自动补全和类型提示
- 下游用户可以获得类型安全保证

### 2. 包分发要求

在 `pyproject.toml` 中明确包含此文件：

```toml
[tool.hatch.build.targets.wheel]
packages = ["src/codex_app_server"]
include = [
  "src/codex_app_server/py.typed",
]
```

这确保在构建 wheel 分发包时，`py.typed` 文件会被包含在内。

## 具体技术实现

### 文件内容

`py.typed` 是一个空文件，其存在本身就具有语义意义：

```bash
$ cat sdk/python/src/codex_app_server/py.typed
# 空文件
```

### 文件位置

```
sdk/python/src/codex_app_server/
├── __init__.py
├── _inputs.py
├── _run.py
├── api.py
├── async_client.py
├── client.py
├── errors.py
├── models.py
├── py.typed          # <-- 类型标记文件
└── retry.py
```

### 构建配置

在 `pyproject.toml` 中的配置确保文件被正确打包：

```toml
[tool.hatch.build.targets.wheel]
include = [
  "src/codex_app_server/py.typed",
]
```

### 测试验证

`test_public_api_signatures.py` 中包含对此文件的测试：

```python
def test_package_includes_py_typed_marker() -> None:
    marker = resources.files("codex_app_server").joinpath("py.typed")
    assert marker.is_file()
```

## 关键代码路径与文件引用

### 依赖关系

`py.typed` 本身不依赖任何代码，但整个 SDK 的类型注解依赖它的存在：

```
py.typed
    └── 影响：所有类型检查器和 IDE
        ├── mypy
        ├── pyright / pylance
        └── 其他 PEP 561 兼容工具
```

### 相关配置

| 文件 | 相关配置 |
|-----|---------|
| `pyproject.toml` | `[tool.hatch.build.targets.wheel] include = ["src/codex_app_server/py.typed"]` |
| `test_public_api_signatures.py` | `test_package_includes_py_typed_marker()` |

## 依赖与外部交互

### 外部工具交互

| 工具 | 行为 |
|-----|------|
| mypy | 检测到 `py.typed` 后，对导入的该包进行类型检查 |
| pyright/pylance | 使用 `py.typed` 确定包是否类型化 |
| IDE (VSCode, PyCharm) | 基于 `py.typed` 提供类型提示和补全 |

### 用户影响

**对于 SDK 用户：**
```python
from codex_app_server import Codex

# 由于 py.typed 存在，类型检查器知道 Codex 的类型信息
codex = Codex()  # IDE 会显示类型提示和文档
```

## 风险、边界与改进建议

### 当前风险

1. **空文件依赖**：文件必须存在且为空，任何内容都可能导致某些工具无法识别
2. **打包遗漏**：如果构建配置错误，文件可能不会被包含在分发包中
3. **部分类型化**：当前包并非 100% 类型化（如某些 `Any` 类型），`py.typed` 的存在可能给用户提供完全类型化的错误印象

### 边界情况

1. **文件权限**：文件需要有读取权限，否则某些工具可能无法检测
2. **大小写敏感**：在大小写敏感的文件系统上，文件名必须精确为 `py.typed`
3. **编码**：虽然文件为空，但如果包含 BOM 或其他不可见字符，可能导致问题

### 改进建议

1. **添加部分类型标记（PEP 561 扩展）**：
   虽然当前是空文件，但 PEP 561 允许在文件中添加内容来指示部分类型化：
   ```
   partial
   ```
   这表示包是部分类型化的，类型检查器应该检查存在的类型注解，但不强制要求所有代码都有注解。

2. **自动化检查**：
   在 CI 中添加检查确保 `py.typed` 文件存在且为空：
   ```bash
   #!/bin/bash
   if [ -s sdk/python/src/codex_app_server/py.typed ]; then
       echo "Error: py.typed should be empty"
       exit 1
   fi
   ```

3. **类型覆盖率监控**：
   使用工具（如 `mypy --html-report`）监控类型覆盖率，确保 `py.typed` 的承诺得到兑现：
   ```toml
   [tool.mypy]
   disallow_untyped_defs = true
   disallow_incomplete_defs = true
   ```

4. **文档说明**：
   在 README 中添加类型支持说明：
   ```markdown
   ## Type Safety
   
   This package is fully typed and includes a `py.typed` marker file 
   for PEP 561 compliance. Type checkers like mypy and pyright will 
   automatically use the type annotations.
   ```

5. **验证构建产物**：
   在发布流程中添加验证步骤，确保 wheel 包含 `py.typed`：
   ```python
   import zipfile
   wheel = zipfile.ZipFile("dist/codex_app_server_sdk-*.whl")
   assert "codex_app_server/py.typed" in wheel.namelist()
   ```

### 测试覆盖

测试文件：`test_public_api_signatures.py`

```python
def test_package_includes_py_typed_marker() -> None:
    marker = resources.files("codex_app_server").joinpath("py.typed")
    assert marker.is_file()
```

此测试验证：
- `py.typed` 文件存在
- 文件可以被访问（即已正确安装）

建议添加更多测试：
```python
def test_py_typed_is_empty() -> None:
    marker = resources.files("codex_app_server").joinpath("py.typed")
    content = marker.read_text()
    assert content == "", "py.typed should be empty for full typing"

def test_all_modules_are_typed() -> None:
    # 验证所有模块都有类型注解
    import codex_app_server
    # 检查关键函数的返回类型注解
    assert codex_app_server.Codex.__init__.__annotations__ != {}
```
