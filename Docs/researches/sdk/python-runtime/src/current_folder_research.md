# sdk/python-runtime/src 深度研究文档

## 目录

1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 定位

`sdk/python-runtime/src` 是 **Codex CLI 运行时包** (`codex-cli-bin`) 的源代码目录。该包是一个**平台特定的 Python wheel 包**，用于将 Codex CLI 二进制文件打包并分发给 Python SDK 使用。

### 核心职责

| 职责 | 说明 |
|------|------|
| **二进制分发** | 将 Codex CLI 二进制文件 (`codex` 或 `codex.exe`) 打包到 Python wheel 中 |
| **版本锁定** | 为 Python SDK 提供精确的 Codex CLI 版本依赖 (`codex-cli-bin==x.y.z`) |
| **跨平台支持** | 支持 Windows、macOS、Linux 多平台（x86_64 和 aarch64） |
| **运行时解析** | 提供 API 供 SDK 定位捆绑的 Codex CLI 二进制文件路径 |

### 在整体架构中的位置

```
┌─────────────────────────────────────────────────────────────────┐
│                    Python SDK (codex-app-server-sdk)            │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  sdk/python/src/codex_app_server/...                      │  │
│  │  - client.py (AppServerClient)                            │  │
│  │  - api.py (Codex, Thread, TurnHandle)                     │  │
│  └───────────────────────────────────────────────────────────┘  │
│                              │                                   │
│                              ▼                                   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  Runtime Dependency: codex-cli-bin=={version}             │  │
│  │  (由 sdk/python-runtime 构建的平台特定 wheel)              │  │
│  └───────────────────────────────────────────────────────────┘  │
│                              │                                   │
└──────────────────────────────┼───────────────────────────────────┘
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Codex CLI Binary (Rust)                      │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  codex-rs/app-server/src/...                              │  │
│  │  - main.rs (app-server 入口)                              │  │
│  │  - JSON-RPC v2 协议实现                                   │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### 关键设计决策

1. **Wheel-Only 包**: 该包**仅构建 wheel**，禁止构建 sdist（源码分发包）。原因：
   - 二进制文件是平台相关的，源码分发无意义
   - 通过 `hatch_build.py` 中的 `RuntimeBuildHook` 强制阻止 sdist 构建

2. **模板性质**: 目录中的代码是**发布模板**，实际发布时通过 `update_sdk_artifacts.py` 注入版本号和二进制文件

3. **版本锁定**: Python SDK 通过精确的 `codex-cli-bin==x.y.z` 依赖确保运行时版本一致性

---

## 功能点目的

### 功能 1: 运行时路径解析

**目的**: 让 Python SDK 能够定位到捆绑的 Codex CLI 二进制文件

**实现**: `bundled_codex_path()` 函数
- 根据操作系统返回 `codex.exe` (Windows) 或 `codex` (Unix)
- 路径格式: `{package_dir}/bin/{executable}`
- 若二进制文件缺失，抛出 `FileNotFoundError`

### 功能 2: 平台特定 Wheel 构建

**目的**: 为不同平台构建包含正确二进制文件的 wheel

**实现**: `pyproject.toml` + `hatch_build.py`
- 使用 Hatchling 构建系统
- 自定义构建钩子阻止 sdist 构建
- `build_data["infer_tag"] = True` 自动推断平台标签
- `build_data["pure_python"] = False` 标记为非纯 Python 包

### 功能 3: 发布流程集成

**目的**: 支持 CI/CD 自动化发布

**实现**: 与 `update_sdk_artifacts.py` 集成
- `stage_python_runtime_package()`: 将模板复制到临时目录，注入版本号和二进制文件
- 支持多平台并行构建（GitHub Actions matrix）

---

## 具体技术实现

### 3.1 核心数据结构

#### `bundled_codex_path()` 返回值

```python
# Windows
Path("/path/to/codex_cli_bin/bin/codex.exe")

# Unix (macOS/Linux)
Path("/path/to/codex_cli_bin/bin/codex")
```

#### 包结构

```
codex_cli_bin/
├── __init__.py          # 提供 bundled_codex_path() API
└── bin/
    └── codex            # 或 codex.exe (构建时注入)
```

### 3.2 关键流程

#### 流程 1: SDK 启动时解析二进制路径

```
sdk/python/src/codex_app_server/client.py
│
├─ _installed_codex_path()
│  └─ from codex_cli_bin import bundled_codex_path
│     └─ 返回 Path(__file__).parent / "bin" / "codex"
│
├─ resolve_codex_bin(config)
   ├─ 若 config.codex_bin 显式设置，使用该路径
   └─ 否则调用 _installed_codex_path()
```

#### 流程 2: 发布时构建 Runtime 包

```
scripts/update_sdk_artifacts.py
│
├─ stage_python_runtime_package(staging_dir, version, binary_path)
│  ├─ 复制 sdk/python-runtime 到 staging_dir
│  ├─ 重写 pyproject.toml 中的 version
│  ├─ 复制 binary_path 到 src/codex_cli_bin/bin/
│  └─ 设置可执行权限 (Unix)
│
└─ 构建 wheel: pip wheel {staging_dir}
```

#### 流程 3: 本地开发时自动安装 Runtime

```
sdk/python/_runtime_setup.py
│
├─ ensure_runtime_package_installed()
│  ├─ 检查已安装的 codex-cli-bin 版本
│  ├─ 若版本不匹配或不存在:
│  │  ├─ _download_release_archive()  # 从 GitHub Releases 下载
│  │  ├─ _extract_runtime_binary()    # 解压 tar.gz/zip
│  │  ├─ _stage_runtime_package()     # 调用 update_sdk_artifacts.py
│  │  └─ _install_runtime_package()   # pip install
│  └─ 返回已安装版本
```

### 3.3 协议与命令

#### 构建命令

```bash
# 进入 sdk/python-runtime 目录
cd sdk/python-runtime

# 构建 wheel (仅当 bin/ 目录存在二进制文件时)
python -m build --wheel

# 或使用 hatch
python -m hatch build -t wheel
```

#### 发布命令 (通过 update_sdk_artifacts.py)

```bash
cd sdk/python

# 生成分发类型
python scripts/update_sdk_artifacts.py generate-types

# 构建 SDK 包 (带 runtime 依赖)
python scripts/update_sdk_artifacts.py stage-sdk /tmp/staged-sdk --runtime-version 1.2.3

# 构建 Runtime 包 (平台特定)
python scripts/update_sdk_artifacts.py stage-runtime /tmp/staged-runtime /path/to/codex --runtime-version 1.2.3
```

### 3.4 配置参数

#### `pyproject.toml` 关键配置

```toml
[project]
name = "codex-cli-bin"
version = "0.0.0-dev"  # 发布时被重写

[tool.hatch.build.targets.wheel]
packages = ["src/codex_cli_bin"]
include = ["src/codex_cli_bin/bin/**"]  # 包含二进制文件
hooks = {"custom" = {}}  # 启用 hatch_build.py

[tool.hatch.build.targets.sdist]
hooks = {"custom" = {}}  # sdist 钩子会阻止构建
```

#### `hatch_build.py` 钩子逻辑

```python
class RuntimeBuildHook(BuildHookInterface):
    def initialize(self, version: str, build_data: dict[str, object]) -> None:
        if self.target_name == "sdist":
            raise RuntimeError("codex-cli-bin is wheel-only")
        
        build_data["pure_python"] = False  # 标记为非纯 Python
        build_data["infer_tag"] = True     # 自动推断平台标签
```

---

## 关键代码路径与文件引用

### 4.1 本目录文件

| 文件 | 职责 | 关键内容 |
|------|------|----------|
| `__init__.py` | 提供公共 API | `bundled_codex_path()`, `PACKAGE_NAME` |

### 4.2 调用方 (上游)

| 文件 | 调用方式 | 用途 |
|------|----------|------|
| `sdk/python/src/codex_app_server/client.py:80-90` | `from codex_cli_bin import bundled_codex_path` | 解析捆绑的 Codex CLI 路径 |
| `sdk/python/_runtime_setup.py:102-121` | `from codex_cli_bin import bundled_codex_path` | 验证 runtime 包安装状态 |
| `sdk/python/scripts/update_sdk_artifacts.py:143-160` | `stage_python_runtime_package()` | 构建发布包 |

### 4.3 被调用方 (下游)

| 组件 | 关系 | 说明 |
|------|------|------|
| `codex-rs/app-server` | 二进制来源 | Rust 构建的 `codex` 二进制文件 |
| `codex-rs/app-server-protocol` | 协议定义 | JSON-RPC v2 协议规范 |
| GitHub Releases | 分发渠道 | 二进制文件发布位置 |

### 4.4 测试文件

| 文件 | 测试内容 |
|------|----------|
| `sdk/python/tests/test_artifact_workflow_and_binaries.py:153-159` | 验证模板目录无预置二进制文件 |
| `sdk/python/tests/test_artifact_workflow_and_binaries.py:195-247` | 验证 wheel-only 构建配置 |
| `sdk/python/tests/test_artifact_workflow_and_binaries.py:250-284` | 验证 stage_runtime 流程 |
| `sdk/python/tests/test_artifact_workflow_and_binaries.py:395-410` | 验证 runtime 包解析 |

### 4.5 CI/CD 配置

| 文件 | 相关配置 |
|------|----------|
| `.github/workflows/rust-release.yml` | 构建多平台 Codex CLI 二进制文件 |
| `.github/workflows/rust-release-prepare.yml` | 准备发布 (更新 models.json) |
| `.github/workflows/sdk.yml` | SDK CI 测试 |

---

## 依赖与外部交互

### 5.1 Python 依赖

```
codex-cli-bin (本包)
    └── (无运行时依赖，仅包含二进制文件)
```

### 5.2 构建依赖

| 依赖 | 用途 |
|------|------|
| `hatchling>=1.24.0` | 构建系统 |
| `hatch_build.py` | 自定义构建钩子 |

### 5.3 外部系统交互

```
┌─────────────────────────────────────────────────────────────────┐
│                        外部交互图                                │
└─────────────────────────────────────────────────────────────────┘

GitHub Releases (openai/codex)
    │
    ├─ 发布源: rust-v{version} 标签
    ├─ 资源文件:
    │   ├─ codex-aarch64-apple-darwin.tar.gz
    │   ├─ codex-x86_64-apple-darwin.tar.gz
    │   ├─ codex-aarch64-unknown-linux-musl.tar.gz
    │   ├─ codex-x86_64-unknown-linux-musl.tar.gz
    │   ├─ codex-aarch64-pc-windows-msvc.exe.zip
    │   └─ codex-x86_64-pc-windows-msvc.exe.zip
    │
    └─ 下载方式:
        ├─ 直接 HTTPS 下载
        ├─ GitHub API (带 GH_TOKEN/GITHUB_TOKEN)
        └─ gh CLI 工具

Python Package Index (PyPI)
    │
    └─ 发布目标: codex-cli-bin-{version}-{platform}.whl

Python SDK (codex-app-server-sdk)
    │
    └─ 依赖声明: "codex-cli-bin=={version}"
```

### 5.4 版本管理

| 组件 | 版本来源 | 说明 |
|------|----------|------|
| `codex-cli-bin` | `sdk/python/_runtime_setup.py:PINNED_RUNTIME_VERSION` | 锁定版本 |
| `codex-app-server-sdk` | `sdk/python/pyproject.toml:version` | SDK 版本 |
| Codex CLI 二进制 | `codex-rs/Cargo.toml:version` | Rust 代码版本 |

---

## 风险、边界与改进建议

### 6.1 已知风险

#### 风险 1: 二进制文件缺失

**场景**: 模板目录 `src/codex_cli_bin/bin/` 为空时，若直接构建 wheel，安装后调用 `bundled_codex_path()` 会抛出 `FileNotFoundError`。

**缓解**:
- 测试 `test_runtime_package_template_has_no_checked_in_binaries` 确保模板无预置二进制
- `bundled_codex_path()` 显式检查文件存在性并抛出清晰错误

#### 风险 2: 平台不匹配

**场景**: 在 ARM64 机器上安装 x86_64 的 wheel，或反之。

**缓解**:
- `build_data["infer_tag"] = True` 确保 wheel 标签与构建平台匹配
- pip 会拒绝安装平台不匹配的 wheel

#### 风险 3: 版本漂移

**场景**: SDK 依赖的 `codex-cli-bin` 版本与实际安装的 Codex CLI 二进制版本不一致。

**缓解**:
- 精确版本依赖 (`==` 而非 `>=`)
- `_runtime_setup.py` 在运行时验证版本

#### 风险 4: sdist 误构建

**场景**: 用户尝试构建 sdist 会触发 `RuntimeError`。

**缓解**:
- `hatch_build.py` 钩子显式阻止 sdist 构建
- 清晰的错误消息: "codex-cli-bin is wheel-only"

### 6.2 边界条件

| 边界条件 | 行为 |
|----------|------|
| Windows 路径 | 使用 `codex.exe` 而非 `codex` |
| 可执行权限 | Unix 平台通过 `chmod` 设置 `+x` |
| 并发安装 | `_runtime_setup.py` 使用临时目录避免冲突 |
| 网络失败 | 支持 GH_TOKEN 回退、gh CLI 回退 |

### 6.3 改进建议

#### 建议 1: 添加平台检测工具函数

```python
# 建议添加到 __init__.py
def get_platform_tag() -> str:
    """返回当前平台的 PEP 425 标签，用于验证 wheel 兼容性。"""
    ...
```

#### 建议 2: 改进错误消息

当前错误消息:
```python
raise FileNotFoundError(
    f"{PACKAGE_NAME} is installed but missing its packaged codex binary at {path}"
)
```

建议增加故障排除指引:
```python
raise FileNotFoundError(
    f"{PACKAGE_NAME} is installed but missing its packaged codex binary at {path}. "
    "This may happen if: (1) you're using an editable install without building the runtime, "
    "(2) the wheel was built for a different platform. "
    "Run 'python -m pip install codex-cli-bin' to install the correct wheel."
)
```

#### 建议 3: 添加健康检查命令

```python
# 建议添加 CLI 接口
if __name__ == "__main__":
    import sys
    try:
        path = bundled_codex_path()
        print(f"OK: Codex CLI found at {path}")
        sys.exit(0)
    except FileNotFoundError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)
```

#### 建议 4: 考虑支持可选的校验和验证

```python
def bundled_codex_path(expected_sha256: str | None = None) -> Path:
    path = ...
    if expected_sha256 is not None:
        actual = hashlib.sha256(path.read_bytes()).hexdigest()
        if actual != expected_sha256:
            raise RuntimeError(f"Checksum mismatch: expected {expected_sha256}, got {actual}")
    return path
```

### 6.4 相关文档

| 文档 | 路径 |
|------|------|
| Python SDK README | `sdk/python/README.md` |
| Runtime README | `sdk/python-runtime/README.md` |
| API 参考 | `sdk/python/docs/api-reference.md` |
| 使用指南 | `sdk/python/docs/getting-started.md` |
| 发布工作流 | `.github/workflows/rust-release.yml` |

---

## 附录: 文件引用速查

### 核心文件

```
sdk/python-runtime/
├── src/codex_cli_bin/
│   └── __init__.py              # 本目录唯一源文件
├── pyproject.toml               # 包配置
├── hatch_build.py               # 构建钩子
└── README.md                    # 包说明
```

### 相关文件

```
sdk/python/
├── src/codex_app_server/
│   ├── client.py                # 调用 bundled_codex_path()
│   └── ...
├── scripts/
│   └── update_sdk_artifacts.py  # 构建发布包
├── _runtime_setup.py            # 自动安装 runtime
└── tests/
    └── test_artifact_workflow_and_binaries.py

codex-rs/
├── app-server/src/main.rs       # Codex CLI 入口
├── app-server-protocol/         # JSON-RPC v2 协议
└── Cargo.toml                   # 版本定义
```
