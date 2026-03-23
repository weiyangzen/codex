# sdk/python-runtime/pyproject.toml 研究文档

## 场景与职责

`pyproject.toml` 是 `codex-cli-bin` Python 包的构建配置文件，定义了包的元数据、构建系统、依赖关系和构建行为。该文件是整个运行时包的"蓝图"，指导构建工具如何打包和分发这个特殊的平台特定二进制包。

### 核心职责

1. **构建系统声明**: 指定使用 Hatchling 作为构建后端
2. **包元数据定义**: 名称、版本、描述、作者、许可证等
3. **平台分发配置**: 控制 wheel 构建，包含二进制文件
4. **构建钩子集成**: 启用自定义构建钩子阻止 sdist 构建

## 功能点目的

### 1. 构建系统配置

```toml
[build-system]
requires = ["hatchling>=1.24.0"]
build-backend = "hatchling.build"
```

| 字段 | 值 | 说明 |
|------|-----|------|
| `requires` | `["hatchling>=1.24.0"]` | 构建时需要的依赖，指定 Hatchling 版本 |
| `build-backend` | `"hatchling.build"` | 使用 Hatchling 的构建后端 |

**选择 Hatchling 的原因**：
- 现代 Python 打包标准（PEP 517/518）支持
- 强大的构建钩子机制（支持 `hatch_build.py`）
- 更好的平台特定 wheel 支持

### 2. 项目元数据

```toml
[project]
name = "codex-cli-bin"
version = "0.0.0-dev"
description = "Pinned Codex CLI runtime for the Python SDK"
readme = "README.md"
requires-python = ">=3.10"
license = { text = "Apache-2.0" }
authors = [{ name = "OpenAI" }]
```

| 字段 | 值 | 说明 |
|------|-----|------|
| `name` | `codex-cli-bin` | PyPI 包名，SDK 依赖此名称 |
| `version` | `0.0.0-dev` | 开发占位版本，发布时由脚本重写 |
| `description` | `Pinned Codex CLI runtime...` | 包用途说明 |
| `requires-python` | `>=3.10` | 与主 SDK 保持一致的 Python 版本要求 |
| `license` | `Apache-2.0` | 与整个项目一致的许可证 |

**版本 `0.0.0-dev` 的特殊含义**：
- 这是开发模板版本，不会直接发布
- `update_sdk_artifacts.py` 的 `stage_python_runtime_package()` 会在发布前重写版本
- 实际发布的版本与 Rust CLI 版本对应（如 `0.116.0-alpha.1`）

### 3. 分类器 (Classifiers)

```toml
classifiers = [
  "Development Status :: 4 - Beta",
  "Intended Audience :: Developers",
  "License :: OSI Approved :: Apache Software License",
  "Programming Language :: Python :: 3",
  "Programming Language :: Python :: 3.10",
  "Programming Language :: Python :: 3.11",
  "Programming Language :: Python :: 3.12",
  "Programming Language :: Python :: 3.13",
]
```

- 用于 PyPI 页面分类和搜索
- 声明支持的 Python 版本（3.10-3.13）
- 开发状态为 Beta，表明 API 可能变化

### 4. 构建排除配置

```toml
[tool.hatch.build]
exclude = [
  ".venv/**",
  ".pytest_cache/**",
  "dist/**",
  "build/**",
]
```

排除开发环境文件，避免打包进 wheel：
- `.venv/**`: 虚拟环境目录
- `.pytest_cache/**`: pytest 缓存
- `dist/**`, `build/**`: 构建输出目录

### 5. Wheel 构建配置（核心）

```toml
[tool.hatch.build.targets.wheel]
packages = ["src/codex_cli_bin"]
include = ["src/codex_cli_bin/bin/**"]

[tool.hatch.build.targets.wheel.hooks.custom]
```

| 配置 | 值 | 说明 |
|------|-----|------|
| `packages` | `["src/codex_cli_bin"]` | 要打包的 Python 包路径 |
| `include` | `["src/codex_cli_bin/bin/**"]` | **关键**：包含二进制文件目录 |
| `hooks.custom` | `{}` | 启用 `hatch_build.py` 中的自定义钩子 |

**`include` 配置的重要性**：
- 默认 Hatch 只包含 Python 文件
- 必须显式声明包含 `bin/` 目录下的二进制文件
- 使用 `/**` 通配符递归包含所有文件

### 6. Sdist 构建配置

```toml
[tool.hatch.build.targets.sdist]

[tool.hatch.build.targets.sdist.hooks.custom]
```

- 声明了 sdist 目标，但钩子会阻止实际构建
- `hatch_build.py` 中的 `RuntimeBuildHook` 会在 `target_name == "sdist"` 时抛出错误

## 具体技术实现

### 配置层次结构

```
pyproject.toml
├── [build-system]           # PEP 517 构建系统声明
├── [project]                # PEP 621 项目元数据
│   ├── 基本信息 (name, version, description)
│   ├── Python 版本要求
│   ├── 许可证和作者
│   └── 分类器
├── [project.urls]           # 项目链接
└── [tool.hatch.build]       # Hatch 特定配置
    ├── 全局排除模式
    ├── [targets.wheel]      # Wheel 构建配置
    │   ├── 包路径
    │   ├── 包含模式（关键：二进制文件）
    │   └── 自定义钩子
    └── [targets.sdist]      # Sdist 构建配置（被钩子阻止）
        └── 自定义钩子
```

### 与构建钩子的交互

```toml
[tool.hatch.build.targets.wheel.hooks.custom]
# 空配置表示使用默认的 hatch_build.py
```

Hatch 的钩子发现机制：
1. 检测到 `hooks.custom` 配置
2. 查找同目录下的 `hatch_build.py`
3. 加载其中的 `RuntimeBuildHook` 类
4. 在构建过程中调用 `initialize()` 方法

### 版本重写机制

```python
# sdk/python/scripts/update_sdk_artifacts.py:143-160
def stage_python_runtime_package(
    staging_dir: Path, runtime_version: str, binary_path: Path
) -> Path:
    _copy_package_tree(python_runtime_root(), staging_dir)
    
    pyproject_path = staging_dir / "pyproject.toml"
    pyproject_path.write_text(
        _rewrite_project_version(pyproject_path.read_text(), runtime_version)
    )
    # ...
```

```python
# _rewrite_project_version 函数 (line 100-110)
def _rewrite_project_version(pyproject_text: str, version: str) -> str:
    updated, count = re.subn(
        r'^version = "[^"]+"$',
        f'version = "{version}"',
        pyproject_text,
        count=1,
        flags=re.MULTILINE,
    )
    if count != 1:
        raise RuntimeError("Could not rewrite project version in pyproject.toml")
    return updated
```

## 关键代码路径与文件引用

### 直接引用该文件的代码

| 文件 | 引用方式 | 用途 |
|------|----------|------|
| `sdk/python/scripts/update_sdk_artifacts.py:143-151` | 读取并重写版本 | 构建发布包 |
| `sdk/python/tests/test_artifact_workflow_and_binaries.py:196-247` | `tomllib.loads()` 解析 | 验证配置正确性 |

### 配置依赖关系

```
pyproject.toml
    │
    ├── 引用 ──> hatch_build.py (通过 hooks.custom)
    │
    ├── 引用 ──> README.md (通过 readme 字段)
    │
    └── 被引用 <── sdk/python/pyproject.toml (通过依赖声明)
```

### 测试验证

`test_artifact_workflow_and_binaries.py` 中的关键测试：

```python
def test_runtime_package_is_wheel_only_and_builds_platform_specific_wheels() -> None:
    pyproject = tomllib.loads(
        (ROOT.parent / "python-runtime" / "pyproject.toml").read_text()
    )
    # ...
    assert pyproject["tool"]["hatch"]["build"]["targets"]["wheel"] == {
        "packages": ["src/codex_cli_bin"],
        "include": ["src/codex_cli_bin/bin/**"],
        "hooks": {"custom": {}},
    }
    assert pyproject["tool"]["hatch"]["build"]["targets"]["sdist"] == {
        "hooks": {"custom": {}},
    }
```

## 依赖与外部交互

### 构建时依赖

| 依赖 | 来源 | 用途 |
|------|------|------|
| hatchling>=1.24.0 | PyPI | 构建后端 |
| hatch_build.py | 本地 | 自定义构建钩子 |

### 运行时依赖

- **无**: 该包没有 Python 依赖
- 仅包含二进制文件和简单的路径查询 API

### 与 SDK 的依赖关系

```toml
# sdk/python/pyproject.toml
[project]
dependencies = ["pydantic>=2.12"]
# 发布时由脚本添加: "codex-cli-bin=={version}"
```

SDK 的依赖注入：
```python
# update_sdk_artifacts.py:113-124
def _rewrite_sdk_runtime_dependency(pyproject_text: str, runtime_version: str) -> str:
    raw_items = [item for item in raw_items if "codex-cli-bin" not in item]
    raw_items.append(f'"codex-cli-bin=={runtime_version}"')
    replacement = "dependencies = [\n  " + ",\n  ".join(raw_items) + ",\n]"
    return pyproject_text[: match.start()] + replacement + pyproject_text[match.end() :]
```

## 风险、边界与改进建议

### 风险点

1. **版本占位符风险**
   - `version = "0.0.0-dev"` 是占位符
   - 如果忘记在发布前重写版本，可能发布开发版本
   - **缓解**: `stage_python_runtime_package` 强制重写版本

2. **二进制文件包含失败**
   - 如果 `include` 模式配置错误，wheel 可能不包含二进制文件
   - **测试覆盖**: `test_runtime_package_template_has_no_checked_in_binaries` 验证模板状态

3. **Hatch 版本兼容性**
   - `hatchling>=1.24.0` 指定最低版本
   - 如果 Hatch 有破坏性变更，可能需要更新

### 边界条件

1. **平台特定 wheel 命名**
   - `infer_tag = True` 依赖 Hatch 正确推断平台标签
   - 跨平台构建（如 macOS 上构建 Linux wheel）需要额外配置

2. **Python 版本范围**
   - `requires-python = ">=3.10"` 限制安装环境
   - 与主 SDK 保持一致

3. **文件包含通配符**
   - `"src/codex_cli_bin/bin/**"` 使用 Hatch 的通配符语法
   - 确保二进制文件无论在 `bin/` 下什么位置都被包含

### 改进建议

1. **添加动态版本说明**

```toml
[project]
# 添加注释说明版本会被重写
version = "0.0.0-dev"  # 发布时由 update_sdk_artifacts.py 重写
```

2. **增强文件包含验证**

```toml
[tool.hatch.build.targets.wheel]
packages = ["src/codex_cli_bin"]
include = [
  "src/codex_cli_bin/__init__.py",
  "src/codex_cli_bin/bin/**",
]
# 显式排除不应包含的文件
exclude = [
  "src/codex_cli_bin/bin/*.dSYM",  # macOS 调试符号
  "src/codex_cli_bin/bin/*.pdb",   # Windows 调试符号（如不需要）
]
```

3. **添加构建后验证**

```toml
[tool.hatch.build.targets.wheel.hooks.custom]
# 可以添加 post-build 钩子验证二进制文件存在
# 当前 Hatch 不支持原生 post-build，但可在 hatch_build.py 中扩展
```

4. **考虑使用 hatch-vcs**

```toml
[build-system]
requires = ["hatchling>=1.24.0", "hatch-vcs"]
build-backend = "hatchling.build"

[project]
dynamic = ["version"]  # 使用 hatch-vcs 从 git tag 获取版本

[tool.hatch.version]
source = "vcs"
```

**优点**: 版本自动从 git tag 获取，无需手动重写
**缺点**: 增加复杂性，当前脚本驱动的方式更可控

5. **完善元数据**

```toml
[project]
# 添加更多有用的元数据
keywords = ["codex", "cli", "runtime", "openai"]
classifiers = [
  # 现有分类器...
  "Operating System :: MacOS",
  "Operating System :: POSIX :: Linux",
  "Operating System :: Microsoft :: Windows",
  "Topic :: Software Development :: Libraries :: Python Modules",
]

[project.urls]
# 添加更多相关链接
Documentation = "https://github.com/openai/codex/tree/main/sdk/python/docs"
Changelog = "https://github.com/openai/codex/blob/main/CHANGELOG.md"
```

### 配置验证检查清单

在发布前应验证：

- [ ] `version` 是否已从 `0.0.0-dev` 重写为实际版本
- [ ] `src/codex_cli_bin/bin/` 目录是否包含正确的二进制文件
- [ ] 构建的 wheel 文件名是否包含正确的平台标签
- [ ] wheel 内是否确实包含二进制文件（可用 `unzip -l` 检查）
- [ ] sdist 构建是否被正确阻止
