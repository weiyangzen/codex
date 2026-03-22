# codex_cli_bin 模块研究文档

## 1. 场景与职责

### 1.1 定位

`codex_cli_bin` 是 `codex-cli-bin` Python 包的运行时入口模块，位于 `sdk/python-runtime/src/codex_cli_bin/` 目录下。该包是 Codex Python SDK (`codex-app-server-sdk`) 的**配套运行时组件**，负责封装和提供平台特定的 Codex CLI 二进制文件。

### 1.2 核心职责

1. **二进制文件定位**：提供 `bundled_codex_path()` 函数，返回打包在 Python wheel 中的 `codex` 可执行文件的绝对路径
2. **跨平台支持**：自动处理 Windows (`codex.exe`) 与 Unix-like 系统 (`codex`) 的可执行文件命名差异
3. **运行时依赖**：作为 `codex-app-server-sdk` 的可选依赖，为 SDK 提供默认的 Codex CLI 路径解析能力

### 1.3 使用场景

```
┌─────────────────────────────────────────────────────────────────┐
│                    Python SDK 用户使用场景                       │
├─────────────────────────────────────────────────────────────────┤
│  1. 安装 SDK: pip install codex-app-server-sdk                  │
│     (自动安装对应平台的 codex-cli-bin 包)                        │
│                                                                 │
│  2. SDK 初始化: from codex_app_server import Codex              │
│                 with Codex() as codex: ...                      │
│                                                                 │
│  3. SDK 内部调用 _installed_codex_path()                        │
│     → 导入 codex_cli_bin.bundled_codex_path()                   │
│     → 返回打包的二进制文件路径                                   │
│     → 启动 codex app-server 子进程                              │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. 功能点目的

### 2.1 功能清单

| 功能 | 目的 | 关键代码 |
|------|------|----------|
| `bundled_codex_path()` | 定位打包的 Codex 二进制文件 | `Path(__file__).resolve().parent / "bin" / exe` |
| 跨平台可执行文件名 | 适配 Windows/Unix 命名差异 | `exe = "codex.exe" if os.name == "nt" else "codex"` |
| 存在性校验 | 确保二进制文件确实存在 | `if not path.is_file(): raise FileNotFoundError(...)` |
| 包元数据 | 标识包名称 | `PACKAGE_NAME = "codex-cli-bin"` |

### 2.2 设计意图

1. **解耦 SDK 与二进制**：SDK 代码不直接依赖特定路径，而是通过 `codex_cli_bin` 包间接获取
2. **平台无关性**：同一套 SDK 代码可在不同平台运行，由平台特定的 wheel 提供对应二进制
3. **版本锁定**：`codex-cli-bin` 的版本号与 Codex CLI 版本严格对应，确保 SDK 使用确定的运行时版本

---

## 3. 具体技术实现

### 3.1 核心代码分析

```python
# sdk/python-runtime/src/codex_cli_bin/__init__.py
from __future__ import annotations

import os
from pathlib import Path

PACKAGE_NAME = "codex-cli-bin"


def bundled_codex_path() -> Path:
    """
    返回打包的 codex 二进制文件路径。
    
    路径结构:
    codex_cli_bin/
    ├── __init__.py
    └── bin/
        ├── codex          (Unix/Linux/macOS)
        └── codex.exe      (Windows)
    """
    exe = "codex.exe" if os.name == "nt" else "codex"
    path = Path(__file__).resolve().parent / "bin" / exe
    if not path.is_file():
        raise FileNotFoundError(
            f"{PACKAGE_NAME} is installed but missing its packaged codex binary at {path}"
        )
    return path
```

### 3.2 包构建配置

```toml
# sdk/python-runtime/pyproject.toml
[tool.hatch.build.targets.wheel]
packages = ["src/codex_cli_bin"]
include = ["src/codex_cli_bin/bin/**"]  # 关键：将 bin/ 目录打包进 wheel

[tool.hatch.build.targets.wheel.hooks.custom]
# 使用自定义构建钩子
```

```python
# sdk/python-runtime/hatch_build.py
class RuntimeBuildHook(BuildHookInterface):
    def initialize(self, version: str, build_data: dict[str, object]) -> None:
        # 禁止构建 sdist，只允许平台特定的 wheel
        if self.target_name == "sdist":
            raise RuntimeError(
                "codex-cli-bin is wheel-only; build and publish platform wheels only."
            )
        
        # 标记为非纯 Python 包，启用平台标签推断
        build_data["pure_python"] = False
        build_data["infer_tag"] = True
```

### 3.3 发布流程中的二进制注入

```python
# sdk/python/scripts/update_sdk_artifacts.py

def stage_python_runtime_package(
    staging_dir: Path, runtime_version: str, binary_path: Path
) -> Path:
    """
    将 Codex 二进制文件注入到 runtime 包中，准备发布。
    """
    # 1. 复制模板代码
    _copy_package_tree(python_runtime_root(), staging_dir)
    
    # 2. 更新版本号
    pyproject_path = staging_dir / "pyproject.toml"
    pyproject_path.write_text(
        _rewrite_project_version(pyproject_path.read_text(), runtime_version)
    )
    
    # 3. 复制二进制文件到 bin/ 目录
    out_bin = staged_runtime_bin_path(staging_dir)  # src/codex_cli_bin/bin/codex
    out_bin.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(binary_path, out_bin)
    
    # 4. 设置可执行权限 (Unix)
    if not _is_windows():
        out_bin.chmod(
            out_bin.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH
        )
    return staging_dir
```

### 3.4 SDK 端的调用链路

```python
# sdk/python/src/codex_app_server/client.py

def _installed_codex_path() -> Path:
    """
    尝试从 codex-cli-bin 包获取二进制路径。
    如果包未安装，抛出 FileNotFoundError。
    """
    try:
        from codex_cli_bin import bundled_codex_path
    except ImportError as exc:
        raise FileNotFoundError(
            "Unable to locate the pinned Codex runtime. Install the published SDK build "
            f"with its {RUNTIME_PKG_NAME} dependency, or set AppServerConfig.codex_bin "
            "explicitly."
        ) from exc

    return bundled_codex_path()


def resolve_codex_bin(config: "AppServerConfig", ops: CodexBinResolverOps) -> Path:
    """
    解析最终使用的 codex 二进制路径。
    优先级：显式配置 > 打包的二进制 > 报错
    """
    if config.codex_bin is not None:
        # 用户显式指定了二进制路径
        codex_bin = Path(config.codex_bin)
        if not ops.path_exists(codex_bin):
            raise FileNotFoundError(f"Codex binary not found at {codex_bin}...")
        return codex_bin

    # 使用打包的二进制
    return ops.installed_codex_path()
```

---

## 4. 关键代码路径与文件引用

### 4.1 本模块文件

| 文件 | 作用 |
|------|------|
| `sdk/python-runtime/src/codex_cli_bin/__init__.py` | 唯一源代码文件，提供 `bundled_codex_path()` |

### 4.2 相关配置文件

| 文件 | 作用 |
|------|------|
| `sdk/python-runtime/pyproject.toml` | 包元数据、构建配置、Hatch 构建设置 |
| `sdk/python-runtime/hatch_build.py` | 自定义构建钩子，禁止 sdist，设置平台标签 |
| `sdk/python-runtime/README.md` | 包说明文档 |

### 4.3 调用方代码

| 文件 | 调用方式 |
|------|----------|
| `sdk/python/src/codex_app_server/client.py:80-90` | `from codex_cli_bin import bundled_codex_path` |
| `sdk/python/_runtime_setup.py:102-120` | 通过子进程检查已安装版本 |

### 4.4 构建/发布脚本

| 文件 | 作用 |
|------|------|
| `sdk/python/scripts/update_sdk_artifacts.py:143-160` | `stage_python_runtime_package()` 注入二进制 |
| `sdk/python/scripts/update_sdk_artifacts.py:56-57` | `staged_runtime_bin_path()` 计算目标路径 |

### 4.5 测试文件

| 文件 | 测试内容 |
|------|----------|
| `sdk/python/tests/test_artifact_workflow_and_binaries.py:153-159` | 验证模板包不包含二进制文件 |
| `sdk/python/tests/test_artifact_workflow_and_binaries.py:250-264` | 验证 `stage_python_runtime_package` 正确复制二进制 |
| `sdk/python/tests/test_artifact_workflow_and_binaries.py:395-409` | 验证默认运行时解析逻辑 |

---

## 5. 依赖与外部交互

### 5.1 依赖关系图

```
┌─────────────────────────────────────────────────────────────────┐
│                        依赖关系图                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   ┌──────────────────┐         ┌──────────────────────────┐    │
│   │  codex-cli-bin   │◄────────│  codex-app-server-sdk    │    │
│   │  (本模块)         │  可选依赖 │  (Python SDK)            │    │
│   │                  │         │                          │    │
│   │  - 打包 codex    │         │  - 调用 bundled_codex_   │    │
│   │    二进制文件     │         │    path()                │    │
│   │  - 提供路径查询   │         │  - 启动 app-server 进程   │    │
│   └──────────────────┘         └──────────────────────────┘    │
│            ▲                             │                      │
│            │                             │                      │
│            │ 构建时注入                   │ 运行时调用            │
│            │                             │                      │
│   ┌──────────────────┐         ┌──────────────────────────┐    │
│   │  update_sdk_     │         │  codex app-server       │    │
│   │  artifacts.py    │────────►│  (Rust 二进制)           │    │
│   │                  │  启动    │                          │    │
│   │  - stage_runtime │         │  - 提供 JSON-RPC API     │    │
│   │    _package()    │         │  - 执行实际 AI 任务       │    │
│   └──────────────────┘         └──────────────────────────┘    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 5.2 运行时安装流程

```python
# sdk/python/_runtime_setup.py

def ensure_runtime_package_installed(...) -> str:
    """
    确保 codex-cli-bin 包已安装且版本匹配。
    如果未安装或版本不匹配，自动从 GitHub Release 下载并安装。
    """
    # 1. 检查当前安装版本
    installed_version = _installed_runtime_version(python_executable)
    
    # 2. 如果版本匹配，直接返回
    if installed_version == requested_version:
        return requested_version
    
    # 3. 从 GitHub Release 下载对应平台的归档
    archive_path = _download_release_archive(requested_version, temp_root)
    
    # 4. 解压提取二进制
    runtime_binary = _extract_runtime_binary(archive_path, temp_root)
    
    # 5. 构建临时 runtime 包
    staged_runtime_dir = _stage_runtime_package(...)
    
    # 6. pip install 安装
    _install_runtime_package(python_executable, staged_runtime_dir, install_target)
```

### 5.3 平台支持矩阵

```python
# sdk/python/_runtime_setup.py:72-95

def platform_asset_name() -> str:
    """
    根据当前平台返回对应的 GitHub Release 资源文件名。
    """
    system = platform.system().lower()
    machine = platform.machine().lower()

    if system == "darwin":
        if machine in {"arm64", "aarch64"}:
            return "codex-aarch64-apple-darwin.tar.gz"
        if machine in {"x86_64", "amd64"}:
            return "codex-x86_64-apple-darwin.tar.gz"
    elif system == "linux":
        if machine in {"aarch64", "arm64"}:
            return "codex-aarch64-unknown-linux-musl.tar.gz"
        if machine in {"x86_64", "amd64"}:
            return "codex-x86_64-unknown-linux-musl.tar.gz"
    elif system == "windows":
        if machine in {"aarch64", "arm64"}:
            return "codex-aarch64-pc-windows-msvc.exe.zip"
        if machine in {"x86_64", "amd64"}:
            return "codex-x86_64-pc-windows-msvc.exe.zip"
```

---

## 6. 风险、边界与改进建议

### 6.1 当前风险

| 风险点 | 描述 | 影响等级 |
|--------|------|----------|
| **二进制缺失** | 模板包（未发布前）`bin/` 目录为空，调用 `bundled_codex_path()` 会抛出 `FileNotFoundError` | 高 |
| **平台覆盖不全** | 仅支持 6 种平台组合，其他架构（如 ARMv7、RISC-V）无法使用 | 中 |
| **版本漂移** | 如果用户手动升级/降级 `codex-cli-bin` 而 SDK 未同步，可能导致兼容性问题 | 中 |
| **GitHub 依赖** | 自动安装流程依赖 GitHub Release 和 API，网络受限环境会失败 | 中 |
| **权限问题** | Unix 系统需要确保二进制有执行权限，某些环境可能受限 | 低 |

### 6.2 边界情况

1. **开发环境**：本地开发时未发布 wheel，需要显式设置 `AppServerConfig(codex_bin=...)`
2. **CI/CD 环境**：无网络或 GitHub API 限流时，自动安装会失败
3. **虚拟环境**：`ensure_runtime_package_installed` 需要正确处理不同 Python 可执行文件路径
4. **并发安装**：多进程同时触发安装可能导致竞争条件

### 6.3 改进建议

#### 6.3.1 错误信息优化

当前错误信息：
```python
raise FileNotFoundError(
    f"{PACKAGE_NAME} is installed but missing its packaged codex binary at {path}"
)
```

建议增加操作指引：
```python
raise FileNotFoundError(
    f"{PACKAGE_NAME} is installed but missing its packaged codex binary at {path}. "
    f"This usually means you're using a development build. "
    f"Either: 1) Install the published wheel from PyPI, or "
    f"2) Set AppServerConfig(codex_bin='/path/to/codex') explicitly."
)
```

#### 6.3.2 增加版本信息暴露

建议增加版本查询功能：
```python
def bundled_codex_version() -> str:
    """返回打包的 codex 二进制版本（通过 --version 调用）。"""
    import subprocess
    result = subprocess.run(
        [str(bundled_codex_path()), "--version"],
        capture_output=True,
        text=True,
        check=True
    )
    return result.stdout.strip()
```

#### 6.3.3 支持离线模式

增加环境变量支持离线安装：
```python
def _download_release_archive(...) -> Path:
    # 检查离线缓存
    offline_cache = os.environ.get("CODEX_CLI_BIN_CACHE")
    if offline_cache:
        cached = Path(offline_cache) / asset_name
        if cached.exists():
            return cached
    # ... 原有下载逻辑
```

#### 6.3.4 增加平台检测前置校验

在构建阶段就检测不支持的平台：
```python
# hatch_build.py
def initialize(self, version: str, build_data: dict[str, object]) -> None:
    try:
        platform_asset_name()  # 验证平台支持
    except RuntimeSetupError as e:
        raise RuntimeError(f"Unsupported platform for codex-cli-bin: {e}")
```

#### 6.3.5 考虑 PEP 723 支持

未来可考虑使用 PEP 723（inline script metadata）支持单文件脚本直接依赖 `codex-cli-bin`：
```python
# /// script
# dependencies = ["codex-cli-bin==0.116.0-alpha.1"]
# ///
from codex_cli_bin import bundled_codex_path
```

---

## 7. 附录

### 7.1 版本历史

| 版本 | 变更 |
|------|------|
| 0.0.0-dev | 模板版本，无实际二进制 |
| 0.116.0-alpha.1 | 当前 pinned 版本（见 `_runtime_setup.py:19`） |

### 7.2 相关文档

- `sdk/python/README.md`: SDK 使用文档
- `sdk/python-runtime/README.md`: Runtime 包说明
- `docs/getting-started.md`: 入门指南
- `docs/api-reference.md`: API 参考

### 7.3 调试技巧

```python
# 检查 codex-cli-bin 是否安装
import importlib.metadata
print(importlib.metadata.version("codex-cli-bin"))

# 检查二进制路径
from codex_cli_bin import bundled_codex_path
print(bundled_codex_path())

# 检查二进制版本
import subprocess
subprocess.run([str(bundled_codex_path()), "--version"])
```
