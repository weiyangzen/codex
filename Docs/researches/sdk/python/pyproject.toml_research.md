# sdk/python/pyproject.toml 研究文档

## 场景与职责

`pyproject.toml` 是 Python SDK 的构建配置文件，遵循 PEP 517/518 标准，定义了：

1. **构建系统配置**: 使用 Hatchling 作为构建后端
2. **项目元数据**: 包名、版本、描述、作者、许可证等
3. **依赖管理**: 运行时依赖和开发依赖
4. **构建目标**: Wheel 和 SDist 的包含/排除规则
5. **工具配置**: pytest 等工具的配置

该文件是 SDK 发布到 PyPI 的核心配置，也是本地开发环境设置的基础。

## 功能点目的

### 1. 构建系统配置
```toml
[build-system]
requires = ["hatchling>=1.24.0"]
build-backend = "hatchling.build"
```
- 使用 Hatchling 替代 setuptools，提供更现代的构建体验
- 版本要求 >=1.24.0 确保关键功能可用

### 2. 项目元数据
```toml
[project]
name = "codex-app-server-sdk"
version = "0.2.0"
description = "Python SDK for Codex app-server v2"
readme = "README.md"
requires-python = ">=3.10"
license = { text = "Apache-2.0" }
authors = [{ name = "OpenClaw Assistant" }]
```
- **包名**: `codex-app-server-sdk`（PyPI 上的分发名称）
- **版本**: `0.2.0`（与 `__init__.py` 中的 `__version__` 需保持一致）
- **Python 版本要求**: >=3.10（支持类型提示、match 语句等现代特性）
- **许可证**: Apache-2.0

### 3. 分类器（Classifiers）
```toml
classifiers = [
  "Development Status :: 4 - Beta",
  "Programming Language :: Python :: 3.10",
  "Programming Language :: Python :: 3.11",
  "Programming Language :: Python :: 3.12",
  "Programming Language :: Python :: 3.13",
  ...
]
```
- 标记开发状态为 Beta
- 明确支持 Python 3.10-3.13

### 4. 依赖管理
```toml
dependencies = ["pydantic>=2.12"]

[project.optional-dependencies]
dev = ["pytest>=8.0", "datamodel-code-generator==0.31.2", "ruff>=0.11"]
```

**运行时依赖**:
- `pydantic>=2.12`: 数据验证和序列化核心库

**开发依赖**:
- `pytest>=8.0`: 测试框架
- `datamodel-code-generator==0.31.2`: 从 JSON Schema 生成 Pydantic 模型（固定版本确保生成一致性）
- `ruff>=0.11`: 快速 Python 代码检查器和格式化工具

### 5. 构建目标配置

#### Wheel 配置
```toml
[tool.hatch.build.targets.wheel]
packages = ["src/codex_app_server"]
include = [
  "src/codex_app_server/py.typed",
]
```
- 指定包根目录为 `src/codex_app_server`
- 包含 `py.typed` 文件以支持 PEP 561 类型检查

#### SDist 配置
```toml
[tool.hatch.build.targets.sdist]
include = [
  "src/codex_app_server/**",
  "README.md",
  "CHANGELOG.md",
  "CONTRIBUTING.md",
  "RELEASE_CHECKLIST.md",
  "pyproject.toml",
]
```
- 明确包含的文件列表
- 包含文档和元数据文件

#### 排除规则
```toml
[tool.hatch.build]
exclude = [
  ".venv/**",
  ".venv2/**",
  ".pytest_cache/**",
  "dist/**",
  "build/**",
]
```
- 排除虚拟环境和构建产物

### 6. Pytest 配置
```toml
[tool.pytest.ini_options]
addopts = "-q"
testpaths = ["tests"]
```
- 使用安静模式（`-q`）减少输出噪音
- 测试文件搜索路径为 `tests/` 目录

## 具体技术实现

### 目录结构映射
```
sdk/python/
├── pyproject.toml          # 本文件
├── src/
│   └── codex_app_server/   # 包源代码
│       ├── __init__.py
│       ├── api.py
│       ├── client.py
│       ├── async_client.py
│       ├── generated/      # 自动生成的模型
│       └── ...
├── tests/                  # 测试文件
├── examples/               # 示例代码
├── docs/                   # 文档
└── scripts/                # 维护脚本
```

### 版本号管理
版本号在以下位置需要保持一致：
1. `pyproject.toml`: `version = "0.2.0"`
2. `src/codex_app_server/__init__.py`: `__version__ = "0.2.0"`
3. `src/codex_app_server/client.py`: `AppServerConfig.client_version = "0.2.0"`
4. `README.md`: 文档中提及的版本

### 发布流程中的修改
在 CI/CD 发布流程中，`scripts/update_sdk_artifacts.py` 会修改此文件：

```python
def _rewrite_sdk_runtime_dependency(pyproject_text: str, runtime_version: str) -> str:
    # 添加 codex-cli-bin 的精确版本依赖
    raw_items.append(f'"codex-cli-bin=={runtime_version}"')
```

发布后的 `pyproject.toml` 会包含：
```toml
dependencies = [
  "pydantic>=2.12",
  "codex-cli-bin==0.116.0-alpha.1",
]
```

## 关键代码路径与文件引用

### 被引用方
| 文件 | 引用方式 | 用途 |
|------|----------|------|
| `scripts/update_sdk_artifacts.py` | 读取并修改 | 发布时注入运行时依赖 |
| `tests/test_artifact_workflow_and_binaries.py` | 解析验证 | 测试构建配置 |
| `examples/_bootstrap.py` | 间接依赖 | 检查 pydantic 安装 |

### 引用方
| 配置项 | 引用目标 |
|--------|----------|
| `readme` | `README.md` |
| `packages` | `src/codex_app_server` |

### 相关文件
| 文件 | 关系 |
|------|------|
| `sdk/python-runtime/pyproject.toml` | 运行时包的配置模板 |
| `README.md` | 项目描述来源 |
| `CHANGELOG.md` | 变更日志（SDist 包含） |

## 依赖与外部交互

### 构建时依赖
| 包 | 版本 | 用途 |
|----|------|------|
| hatchling | >=1.24.0 | 构建后端 |

### 运行时依赖
| 包 | 版本 | 用途 |
|----|------|------|
| pydantic | >=2.12 | 数据模型验证 |
| codex-cli-bin | ==PINNED_VERSION | 运行时二进制（发布时注入） |

### 开发依赖
| 包 | 版本 | 用途 |
|----|------|------|
| pytest | >=8.0 | 测试框架 |
| datamodel-code-generator | ==0.31.2 | 从 Schema 生成模型 |
| ruff | >=0.11 | 代码检查/格式化 |

### PyPI 交互
- 包名: `codex-app-server-sdk`
- 项目链接: GitHub 仓库
- 问题追踪: GitHub Issues

## 风险、边界与改进建议

### 风险点

1. **版本不一致**: 多处硬编码版本号可能导致不一致
   - 缓解：测试 `test_examples_readme_matches_pinned_runtime_version` 检查版本
   - 建议：使用 `hatch-vcs` 从 git tag 动态获取版本

2. **运行时依赖缺失**: 本地开发时 `codex-cli-bin` 未在依赖中声明
   - 这是有意设计，本地开发通过 `AppServerConfig(codex_bin=...)` 或 `_runtime_setup.py` 处理
   - 发布版本才会注入精确版本依赖

3. **Python 版本限制**: 要求 >=3.10，排除旧版本用户
   - 这是有意设计，利用现代 Python 特性

### 边界条件

1. **构建环境**: 需要 Hatchling 支持，旧版 pip 可能不兼容
   - 要求 pip >= 21.0（支持 PEP 517）

2. **平台无关性**: SDK 本身是纯 Python，但依赖的平台特定 wheel `codex-cli-bin` 限制平台支持

3. **可编辑安装**: `pip install -e .` 需要构建后端支持
   - Hatchling 完全支持

### 改进建议

1. **动态版本管理**: 使用 `hatch-vcs` 从 git tag 获取版本
   ```toml
   [build-system]
   requires = ["hatchling>=1.24.0", "hatch-vcs"]
   build-backend = "hatchling.build"
   
   [tool.hatch.version]
   source = "vcs"
   ```

2. **依赖分组**: 添加更多可选依赖分组
   ```toml
   [project.optional-dependencies]
   dev = ["pytest>=8.0", "datamodel-code-generator==0.31.2", "ruff>=0.11"]
   docs = ["mkdocs", "mkdocstrings"]
   test = ["pytest>=8.0", "pytest-asyncio", "pytest-cov"]
   ```

3. **入口点**: 如果 SDK 提供 CLI，添加 console_scripts
   ```toml
   [project.scripts]
   codex-sdk = "codex_app_server.cli:main"
   ```

4. **严格类型检查**: 添加 mypy 配置
   ```toml
   [tool.mypy]
   python_version = "3.10"
   strict = true
   warn_return_any = true
   warn_unused_configs = true
   ```

5. **代码格式化**: 添加 black/isort 配置（或继续使用 ruff）
   ```toml
   [tool.ruff]
   line-length = 100
   target-version = "py310"
   
   [tool.ruff.lint]
   select = ["E", "F", "I", "N", "W", "UP"]
   ```

6. **测试覆盖率**: 添加 coverage 配置
   ```toml
   [tool.coverage.run]
   source = ["src/codex_app_server"]
   
   [tool.coverage.report]
   fail_under = 80
   ```

7. **发布检查清单**: 添加 `check` 命令确保发布前检查
   ```toml
   [tool.hatch.envs.release]
   dependencies = ["twine", "build"]
   
   [tool.hatch.envs.release.scripts]
   check = "twine check dist/*"
   build = "python -m build"
   ```

8. **文档生成**: 配置自动化 API 文档生成
   ```toml
   [tool.hatch.envs.docs]
   dependencies = ["mkdocs", "mkdocstrings[python]"]
   ```
