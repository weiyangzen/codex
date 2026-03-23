# sdk/python-runtime/hatch_build.py 研究文档

## 场景与职责

`hatch_build.py` 是 `codex-cli-bin` 包的自定义 Hatch 构建钩子脚本，核心职责是**强制执行 wheel-only 构建策略**，确保该包不会以 sdist（源码分发）形式发布。

### 为什么需要这个钩子？

Python 包通常有两种分发形式：
1. **sdist (Source Distribution)**: 源码包，需要用户环境具备构建能力
2. **wheel**: 预构建的二进制包，可直接安装

`codex-cli-bin` 包含平台特定的原生二进制文件（Rust 构建的 `codex` 可执行文件），这些文件：
- 无法从 Python 源码构建（需要 Rust 工具链）
- 必须在特定平台的 CI 环境中预构建
- 必须随平台特定的 wheel 一起分发

因此，发布 sdist 不仅无意义，还会导致用户安装失败。

## 功能点目的

### 1. 阻止 sdist 构建

```python
if self.target_name == "sdist":
    raise RuntimeError(
        "codex-cli-bin is wheel-only; build and publish platform wheels only."
    )
```

当构建目标为 sdist 时，立即抛出错误，阻止构建过程。

### 2. 标记为非纯 Python 包

```python
build_data["pure_python"] = False
```

告诉 Hatch 这是一个包含原生代码的包，影响：
- wheel 文件名包含平台标签（如 `cp310-manylinux_2_17_x86_64`）
- 不会创建纯 Python 的 `py3-none-any` wheel

### 3. 启用平台标签推断

```python
build_data["infer_tag"] = True
```

允许 Hatch 根据当前构建环境自动推断平台标签，确保生成的 wheel 文件名正确反映目标平台。

## 具体技术实现

### 类继承结构

```python
from hatchling.builders.hooks.plugin.interface import BuildHookInterface

class RuntimeBuildHook(BuildHookInterface):
    def initialize(self, version: str, build_data: dict[str, object]) -> None:
        ...
```

- 继承自 Hatch 的 `BuildHookInterface`
- 实现 `initialize` 钩子方法，在构建初始化阶段执行

### 方法签名分析

```python
def initialize(self, version: str, build_data: dict[str, object]) -> None:
    del version  # 未使用，显式删除避免 lint 警告
```

| 参数 | 类型 | 用途 |
|------|------|------|
| `version` | `str` | 构建版本号（未使用） |
| `build_data` | `dict[str, object]` | 构建数据字典，用于向 Hatch 传递构建参数 |

### build_data 字段说明

| 字段 | 值 | 含义 |
|------|-----|------|
| `pure_python` | `False` | 标记为非纯 Python 包 |
| `infer_tag` | `True` | 启用平台标签自动推断 |

## 关键代码路径与文件引用

### 被调用路径

该文件由 Hatch 构建系统在以下场景自动调用：

```
用户/CI 执行: python -m build
                    │
                    ▼
            hatchling.build
                    │
                    ▼
            读取 pyproject.toml 中的 hooks 配置
                    │
                    ▼
            [tool.hatch.build.targets.wheel.hooks.custom]
                    │
                    ▼
            加载 hatch_build.py 中的 RuntimeBuildHook
                    │
                    ▼
            调用 initialize() 方法
```

### 配置文件关联

`pyproject.toml` 中的相关配置：

```toml
[tool.hatch.build.targets.wheel]
packages = ["src/codex_cli_bin"]
include = ["src/codex_cli_bin/bin/**"]

[tool.hatch.build.targets.wheel.hooks.custom]
# 启用 hatch_build.py 中的自定义钩子

[tool.hatch.build.targets.sdist]

[tool.hatch.build.targets.sdist.hooks.custom]
# sdist 也会触发钩子，但会被拒绝
```

注意：虽然 sdist 配置中声明了 `hooks.custom`，但钩子代码会检查 `target_name` 并拒绝 sdist 构建。

### 测试覆盖

该钩子的行为在以下测试中被验证：

| 测试文件 | 测试函数 | 验证内容 |
|----------|----------|----------|
| `sdk/python/tests/test_artifact_workflow_and_binaries.py:195-248` | `test_runtime_package_is_wheel_only_and_builds_platform_specific_wheels` | 验证 sdist 守卫、build_data 赋值、pyproject 配置 |

测试代码关键断言：

```python
# 验证 sdist 守卫存在
assert sdist_guard is not None  # 确保有 if self.target_name == "sdist" 检查

# 验证 build_data 赋值
assert build_data_assignments == {"pure_python": False, "infer_tag": True}

# 验证 pyproject 配置
assert pyproject["tool"]["hatch"]["build"]["targets"]["wheel"] == {
    "packages": ["src/codex_cli_bin"],
    "include": ["src/codex_cli_bin/bin/**"],
    "hooks": {"custom": {}},
}
```

## 依赖与外部交互

### 构建时依赖

| 依赖 | 版本要求 | 用途 |
|------|----------|------|
| hatchling | >=1.24.0 | 构建后端，提供 BuildHookInterface |

### Hatch 构建流程集成

```
┌─────────────────────────────────────────────────────────────┐
│                    Hatch Build 流程                          │
├─────────────────────────────────────────────────────────────┤
│  1. 解析 pyproject.toml                                      │
│  2. 确定构建目标 (wheel/sdist)                               │
│  3. 加载目标特定的 hooks                                     │
│  4. 调用 hook.initialize(version, build_data)               │
│       ├── 如果是 sdist: 抛出 RuntimeError                    │
│       └── 如果是 wheel: 设置 pure_python=False, infer_tag=True│
│  5. 继续构建流程                                             │
└─────────────────────────────────────────────────────────────┘
```

## 风险、边界与改进建议

### 风险点

1. **Hatch 版本兼容性**
   - 依赖 `hatchling>=1.24.0` 的 API
   - 如果 Hatch 未来版本更改 `BuildHookInterface`，可能需要更新
   - 当前代码使用基础 API，兼容性风险较低

2. **错误信息清晰度**
   - 当前错误信息：`"codex-cli-bin is wheel-only; build and publish platform wheels only."`
   - 对于不熟悉 Python 打包的用户，可能不清楚如何"只构建 wheel"

3. **CI/CD 集成风险**
   - 如果 CI 配置错误地尝试构建 sdist，会导致构建失败
   - 需要确保发布脚本明确指定只构建 wheel

### 边界条件

1. **目标检测**
   ```python
   if self.target_name == "sdist":
   ```
   - 精确匹配字符串 `"sdist"`
   - Hatch 内部使用这些标准目标名称

2. **构建数据类型**
   - `build_data` 是 `dict[str, object]`，允许任意值类型
   - `pure_python` 期望布尔值
   - `infer_tag` 期望布尔值

3. **版本参数忽略**
   - `del version` 显式标记未使用
   - 如果未来需要基于版本的条件逻辑，可以移除这行

### 改进建议

1. **增强错误信息**

```python
# 当前
raise RuntimeError(
    "codex-cli-bin is wheel-only; build and publish platform wheels only."
)

# 建议
raise RuntimeError(
    "codex-cli-bin is wheel-only and cannot be built as an sdist. "
    "This package contains platform-specific native binaries that must be "
    "pre-built in CI. To build: 'python -m build --wheel'. "
    "See sdk/python-runtime/README.md for details."
)
```

2. **添加调试日志**

```python
def initialize(self, version: str, build_data: dict[str, object]) -> None:
    import sys
    print(f"[hatch_build] Building target: {self.target_name}", file=sys.stderr)
    print(f"[hatch_build] Version: {version}", file=sys.stderr)
    
    del version
    if self.target_name == "sdist":
        raise RuntimeError(...)
    
    build_data["pure_python"] = False
    build_data["infer_tag"] = True
    print(f"[hatch_build] Configured as non-pure Python wheel", file=sys.stderr)
```

3. **考虑添加版本验证**

```python
def initialize(self, version: str, build_data: dict[str, object]) -> None:
    del version
    if self.target_name == "sdist":
        raise RuntimeError(...)
    
    # 验证二进制文件存在（构建时检查）
    bin_dir = Path(__file__).parent / "src" / "codex_cli_bin" / "bin"
    if not any(bin_dir.glob("codex*")):
        raise RuntimeError(
            f"No codex binary found in {bin_dir}. "
            "Ensure the binary is staged before building."
        )
    
    build_data["pure_python"] = False
    build_data["infer_tag"] = True
```

4. **类型安全改进**

```python
from typing import TypedDict

class BuildData(TypedDict):
    pure_python: bool
    infer_tag: bool

def initialize(self, version: str, build_data: BuildData) -> None:
    ...
```

### 替代方案考虑

如果未来需要更复杂的构建逻辑，可以考虑：

1. **使用 hatch-vcs**: 动态版本管理
2. **使用 hatch-mypyc**: 如果添加 Python 扩展模块
3. **迁移到 setuptools**: 如果 Hatch 不再满足需求（需要重写构建钩子）

当前 Hatch 方案是合理且现代的，建议保持。
