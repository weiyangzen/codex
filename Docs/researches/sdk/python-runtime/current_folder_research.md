# sdk/python-runtime 深度研究文档

## 目录

1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 1.1 定位与核心职责

`sdk/python-runtime`（包名 `codex-cli-bin`）是 **Codex CLI 的 Python Runtime 分发包**，其核心职责是：

| 职责 | 说明 |
|------|------|
| **平台特定二进制分发** | 将 Rust 构建的 `codex` CLI 二进制文件打包为 Python wheel，供 Python SDK 调用 |
| **版本锁定** | 允许 Python SDK 精确锁定 Codex CLI 版本，避免版本漂移 |
| **跨平台支持** | 支持 macOS (x86_64/arm64)、Linux (x86_64/arm64)、Windows (x86_64/arm64) 六大平台 |
| **wheel-only 分发** |  intentionally 仅构建 wheel，不发布 sdist，确保每个 wheel 包含对应平台的原生二进制 |

### 1.2 在整体架构中的位置

```
┌─────────────────────────────────────────────────────────────────┐
│                     Python SDK 使用者                            │
│              pip install codex-app-server-sdk                   │
└───────────────────────────┬─────────────────────────────────────┘
                            │ 依赖
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│  codex-app-server-sdk (sdk/python)                              │
│  - 提供 Codex / AsyncCodex 高级 API                             │
│  - 通过 JSON-RPC 与 codex app-server 通信                        │
│  - 需要 codex-cli-bin 提供二进制运行时                           │
└───────────────────────────┬─────────────────────────────────────┘
                            │ 依赖 (精确版本锁定)
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│  codex-cli-bin (sdk/python-runtime)  ◄── 本研究对象              │
│  - 包含 codex 原生二进制 (Rust 构建)                              │
│  - 提供 bundled_codex_path() API                                │
│  - 平台特定的 wheel (无 sdist)                                  │
└───────────────────────────┬─────────────────────────────────────┘
                            │ 调用
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│  codex CLI (codex-rs/cli)                                       │
│  - Rust 实现的 CLI 工具                                          │
│  - 提供 app-server 子命令 (JSON-RPC over stdio)                 │
└─────────────────────────────────────────────────────────────────┘
```

### 1.3 使用场景

**场景 1：终端用户安装**
```bash
pip install codex-app-server-sdk
# 自动安装对应平台的 codex-cli-bin 依赖
```

**场景 2：开发环境（源码开发）**
```bash
cd sdk/python
# 开发时无预打包的二进制，需要：
# 1. 显式指定 codex_bin 路径，或
# 2. 通过 _runtime_setup.py 自动下载安装 runtime
```

**场景 3：CI/CD 发布流程**
```bash
# 1. 构建 codex CLI 各平台二进制
# 2. 使用 update_sdk_artifacts.py stage-runtime 打包
# 3. 发布 codex-cli-bin 平台 wheels 到 PyPI
```

---

## 功能点目的

### 2.1 功能清单

| 功能点 | 目的 | 关键文件 |
|--------|------|----------|
| **二进制打包** | 将 codex 二进制嵌入 Python 包 | `src/codex_cli_bin/__init__.py` |
| **路径暴露** | 提供 API 供 SDK 定位二进制 | `bundled_codex_path()` |
| **构建钩子** | 阻止 sdist 构建，强制 wheel-only | `hatch_build.py` |
| **平台检测** | 自动推断平台标签 | `pyproject.toml` + hatch |
| **版本管理** | 与 SDK 版本解耦，独立版本号 | `pyproject.toml` |

### 2.2 设计决策

#### 2.2.1 为何 wheel-only？

```python
# hatch_build.py
class RuntimeBuildHook(BuildHookInterface):
    def initialize(self, version: str, build_data: dict[str, object]) -> None:
        if self.target_name == "sdist":
            raise RuntimeError(
                "codex-cli-bin is wheel-only; build and publish platform wheels only."
            )
```

**原因：**
1. **原生二进制依赖**：包含平台特定的 ELF/Mach-O/PE 可执行文件
2. **跨平台不可移植**：Linux 二进制无法在 macOS/Windows 运行
3. **PyPI 分发策略**：为每个平台构建独立 wheel，pip 自动选择匹配平台

#### 2.2.2 为何与 SDK 分离？

| 优势 | 说明 |
|------|------|
| **独立版本周期** | CLI 可以独立于 SDK 发布 |
| **精确版本锁定** | SDK 通过 `codex-cli-bin==x.y.z` 精确锁定 |
| **减小仓库体积** | 无需将二进制检入 git |
| **多平台 CI** | 各平台独立构建 runtime wheel |

---

## 具体技术实现

### 3.1 包结构

```
sdk/python-runtime/
├── README.md                    # 包说明
├── pyproject.toml              # 包配置 + hatch 构建设置
├── hatch_build.py              # 自定义构建钩子 (wheel-only 强制)
└── src/codex_cli_bin/
    └── __init__.py             # 唯一源码文件，暴露 bundled_codex_path()
    └── bin/                    # 构建时注入 codex 二进制 (git 中不存在)
        └── codex               # Linux/macOS 可执行文件
        └── codex.exe           # Windows 可执行文件
```

### 3.2 核心 API 实现

```python
# src/codex_cli_bin/__init__.py
import os
from pathlib import Path

PACKAGE_NAME = "codex-cli-bin"

def bundled_codex_path() -> Path:
    """返回包内嵌的 codex 二进制文件路径。
    
    调用方: sdk/python/src/codex_app_server/client.py 中的 _installed_codex_path()
    
    异常:
        FileNotFoundError: 如果二进制文件不存在（说明包构建不正确）
    """
    exe = "codex.exe" if os.name == "nt" else "codex"
    path = Path(__file__).resolve().parent / "bin" / exe
    if not path.is_file():
        raise FileNotFoundError(
            f"{PACKAGE_NAME} is installed but missing its packaged codex binary at {path}"
        )
    return path
```

### 3.3 构建流程

#### 3.3.1 Hatch 构建配置

```toml
# pyproject.toml
[tool.hatch.build.targets.wheel]
packages = ["src/codex_cli_bin"]
include = ["src/codex_cli_bin/bin/**"]    # 关键：包含二进制目录
hooks = {custom = {}}                      # 启用 hatch_build.py 钩子

[tool.hatch.build.targets.sdist]
hooks = {custom = {}}                      # sdist 也有钩子，但会报错
```

#### 3.3.2 构建钩子逻辑

```python
# hatch_build.py
class RuntimeBuildHook(BuildHookInterface):
    def initialize(self, version: str, build_data: dict[str, object]) -> None:
        del version
        # 1. 阻止 sdist 构建
        if self.target_name == "sdist":
            raise RuntimeError("codex-cli-bin is wheel-only...")
        
        # 2. 标记为非纯 Python 包（包含原生二进制）
        build_data["pure_python"] = False
        
        # 3. 让 hatch 自动推断平台标签 (py3-none-macosx_11_0_arm64 等)
        build_data["infer_tag"] = True
```

### 3.4 发布流程详解

#### 3.4.1 完整发布流水线

```
┌─────────────────────────────────────────────────────────────────────┐
│ 1. Rust CLI 构建 (rust-release.yml)                                  │
│    - 触发: git tag rust-vx.y.z                                      │
│    - 构建: 6 个平台的目标二进制                                      │
│    - 输出: codex-aarch64-apple-darwin.tar.gz 等                     │
└───────────────────────────┬─────────────────────────────────────────┘
                            │ GitHub Release 附件
                            ▼
┌─────────────────────────────────────────────────────────────────────┐
│ 2. Runtime 包构建 (update_sdk_artifacts.py stage-runtime)            │
│    - 输入: 平台二进制 + runtime_version                             │
│    - 复制: sdk/python-runtime → staging_dir                         │
│    - 注入: 二进制到 src/codex_cli_bin/bin/                          │
│    - 改写: pyproject.toml 版本号                                    │
│    - 输出: 可构建的 runtime 包目录                                   │
└───────────────────────────┬─────────────────────────────────────────┘
                            │ python -m build
                            ▼
┌─────────────────────────────────────────────────────────────────────┐
│ 3. Wheel 构建                                                        │
│    - 平台特定 wheel (如: codex_cli_bin-0.116.0a1-py3-none-          │
│      macosx_11_0_arm64.whl)                                         │
│    - 包含: __init__.py + bin/codex                                  │
└───────────────────────────┬─────────────────────────────────────────┘
                            │ twine upload
                            ▼
┌─────────────────────────────────────────────────────────────────────┐
│ 4. PyPI 发布                                                         │
│    - 6 个平台 wheels 上传到 PyPI                                     │
│    - 无 sdist                                                         │
└─────────────────────────────────────────────────────────────────────┘
```

#### 3.4.2 stage-runtime 实现细节

```python
# sdk/python/scripts/update_sdk_artifacts.py

def stage_python_runtime_package(
    staging_dir: Path, 
    runtime_version: str, 
    binary_path: Path
) -> Path:
    """Stage a releasable runtime package for the current platform."""
    # 1. 复制模板包
    _copy_package_tree(python_runtime_root(), staging_dir)
    
    # 2. 改写版本号
    pyproject_path = staging_dir / "pyproject.toml"
    pyproject_path.write_text(
        _rewrite_project_version(pyproject_path.read_text(), runtime_version)
    )
    
    # 3. 复制二进制到 bin/ 目录
    out_bin = staged_runtime_bin_path(staging_dir)  # src/codex_cli_bin/bin/codex
    out_bin.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(binary_path, out_bin)
    
    # 4. 设置可执行权限 (非 Windows)
    if not _is_windows():
        out_bin.chmod(
            out_bin.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH
        )
    return staging_dir
```

### 3.5 SDK 端二进制解析

```python
# sdk/python/src/codex_app_server/client.py

RUNTIME_PKG_NAME = "codex-cli-bin"

def _installed_codex_path() -> Path:
    """从已安装的 codex-cli-bin 包获取二进制路径。"""
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
    """解析最终使用的 codex 二进制路径。"""
    # 优先级 1: 用户显式配置
    if config.codex_bin is not None:
        codex_bin = Path(config.codex_bin)
        if not ops.path_exists(codex_bin):
            raise FileNotFoundError(f"Codex binary not found at {codex_bin}")
        return codex_bin
    
    # 优先级 2: 从 codex-cli-bin 包获取
    return ops.installed_codex_path()
```

---

## 关键代码路径与文件引用

### 4.1 本目录文件

| 文件 | 行数 | 核心功能 |
|------|------|----------|
| `README.md` | 9 | 包说明：wheel-only 设计意图 |
| `pyproject.toml` | 45 | Hatch 构建配置，wheel 包含规则 |
| `hatch_build.py` | 15 | 构建钩子：阻止 sdist，设置平台标签 |
| `src/codex_cli_bin/__init__.py` | 19 | 暴露 bundled_codex_path() API |

### 4.2 调用方代码（SDK）

| 文件 | 关键函数/类 | 说明 |
|------|-------------|------|
| `sdk/python/src/codex_app_server/client.py:80-91` | `_installed_codex_path()` | 导入并调用 bundled_codex_path |
| `sdk/python/src/codex_app_server/client.py:93-121` | `resolve_codex_bin()` | 二进制路径解析逻辑 |
| `sdk/python/src/codex_app_server/client.py:161-187` | `AppServerClient.start()` | 使用解析的二进制启动子进程 |

### 4.3 发布/构建脚本

| 文件 | 关键函数 | 说明 |
|------|----------|------|
| `sdk/python/scripts/update_sdk_artifacts.py:143-161` | `stage_python_runtime_package()` | Runtime 包打包逻辑 |
| `sdk/python/scripts/update_sdk_artifacts.py:56-58` | `staged_runtime_bin_path()` | 计算二进制目标路径 |
| `sdk/python/_runtime_setup.py:31-69` | `ensure_runtime_package_installed()` | 开发环境自动安装 runtime |

### 4.4 测试文件

| 文件 | 测试用例 | 说明 |
|------|----------|------|
| `sdk/python/tests/test_artifact_workflow_and_binaries.py:153-159` | `test_runtime_package_template_has_no_checked_in_binaries()` | 验证模板无二进制 |
| `sdk/python/tests/test_artifact_workflow_and_binaries.py:195-248` | `test_runtime_package_is_wheel_only_and_builds_platform_specific_wheels()` | 验证 wheel-only 构建 |
| `sdk/python/tests/test_artifact_workflow_and_binaries.py:250-285` | `test_stage_runtime_release_copies_binary_and_sets_version()` | 验证打包逻辑 |
| `sdk/python/tests/test_artifact_workflow_and_binaries.py:395-410` | `test_default_runtime_is_resolved_from_installed_runtime_package()` | 验证运行时解析 |

### 4.5 CI/CD 配置

| 文件 | 说明 |
|------|------|
| `.github/workflows/rust-release.yml` | Rust CLI 构建与发布 |
| `.github/workflows/rust-release-windows.yml` | Windows 特定构建 |
| `sdk/python/scripts/update_sdk_artifacts.py` | SDK/runtime 打包脚本 |

---

## 依赖与外部交互

### 5.1 构建依赖

```
构建系统:
  - hatchling>=1.24.0 (PEP 517 构建后端)
  - hatch_build.py (自定义构建钩子)

运行时依赖:
  - 无 (纯数据包，仅包含二进制)

Python 版本:
  - >=3.10 (与 SDK 保持一致)
```

### 5.2 上游依赖（构建时）

| 组件 | 来源 | 交付形式 |
|------|------|----------|
| `codex` 二进制 | `codex-rs/cli` | GitHub Release 附件 (.tar.gz/.zip) |
| 版本号 | Git tag (rust-v*) | 通过 `--runtime-version` 传入 |

### 5.3 下游依赖（运行时）

| 组件 | 使用方式 | 说明 |
|------|----------|------|
| `codex-app-server-sdk` | `from codex_cli_bin import bundled_codex_path` | 唯一调用方 |

### 5.4 平台支持矩阵

| 平台 | 架构 | 二进制文件名 | Wheel 平台标签 |
|------|------|--------------|----------------|
| macOS | arm64 | `codex` | `macosx_11_0_arm64` |
| macOS | x86_64 | `codex` | `macosx_11_0_x86_64` |
| Linux | x86_64 | `codex` | `manylinux_2_28_x86_64` 或 `musllinux` |
| Linux | arm64 | `codex` | `manylinux_2_28_aarch64` 或 `musllinux` |
| Windows | x86_64 | `codex.exe` | `win_amd64` |
| Windows | arm64 | `codex.exe` | `win_arm64` |

---

## 风险、边界与改进建议

### 6.1 已知风险

#### 风险 1：二进制与 SDK 版本不兼容

**场景**：用户升级 SDK 但未升级 runtime，或反之。

**当前缓解**：
- SDK 通过 `codex-cli-bin=={version}` 精确锁定
- 测试 `test_real_app_server_integration.py` 验证兼容性

**潜在问题**：
```python
# sdk/python/tests/test_real_app_server_integration.py:145-152
def _runtime_compatibility_hint(...):
    if "ThreadStartResponse" in combined and "approvalsReviewer" in combined:
        return (
            "\nCompatibility hint:\n"
            f"Pinned runtime {runtime_env.runtime_version} returned a thread/start payload "
            "that is older than the current SDK schema..."
        )
```

#### 风险 2：平台检测失败

**场景**：新平台/架构无法识别。

**代码位置**：`sdk/python/_runtime_setup.py:72-95`

```python
def platform_asset_name() -> str:
    system = platform.system().lower()
    machine = platform.machine().lower()
    # 明确的平台映射，不支持的会抛出 RuntimeSetupError
```

#### 风险 3：开发环境体验

**场景**：开发者从源码安装 SDK，但没有预打包的 runtime。

**当前方案**：
- 必须显式设置 `AppServerConfig(codex_bin="/path/to/codex")`
- 或使用 `_runtime_setup.py` 自动下载（需要 GitHub API 或 gh CLI）

### 6.2 边界情况

| 边界情况 | 行为 | 测试覆盖 |
|----------|------|----------|
| sdist 构建尝试 | `hatch_build.py` 抛出 `RuntimeError` | `test_runtime_package_is_wheel_only...` |
| 二进制文件缺失 | `bundled_codex_path()` 抛出 `FileNotFoundError` | 无直接测试 |
| 用户显式指定二进制 | 优先使用用户指定路径 | `test_explicit_codex_bin_override_takes_priority` |
| runtime 包未安装 | 抛出 `FileNotFoundError` 提示安装 | `test_missing_runtime_package_requires_explicit_codex_bin` |
| Windows 路径处理 | 自动使用 `codex.exe` | 代码逻辑覆盖 |

### 6.3 改进建议

#### 建议 1：增强错误信息

当前错误信息较简单，可以添加更多诊断信息：

```python
# 当前
def bundled_codex_path() -> Path:
    ...
    raise FileNotFoundError(
        f"{PACKAGE_NAME} is installed but missing its packaged codex binary at {path}"
    )

# 建议改进
    raise FileNotFoundError(
        f"{PACKAGE_NAME} is installed but missing its packaged codex binary at {path}. "
        f"Platform: {platform.system()} {platform.machine()}. "
        f"Expected binary: {exe}. "
        "This may indicate a corrupted installation or platform mismatch."
    )
```

#### 建议 2：添加版本元数据暴露

当前 SDK 需要单独维护 `PINNED_RUNTIME_VERSION`，可以考虑让 runtime 包自身暴露版本：

```python
# 建议添加
__version__ = "0.116.0a1"

def bundled_codex_version() -> str:
    """返回包内嵌 codex 二进制的版本。"""
    # 可通过 subprocess.run([bundled_codex_path(), "--version"]) 获取
    ...
```

#### 建议 3：支持更多安装源

当前 `_runtime_setup.py` 主要从 GitHub Release 下载，可以扩展：

- 企业内部镜像支持（环境变量配置）
- 本地缓存复用
- 预下载二进制验证（checksum）

#### 建议 4：文档改进

- 添加 `PLATFORM_SUPPORT.md` 明确列出支持的平台和最低 OS 版本
- 添加故障排除指南（如何手动指定二进制、如何验证安装）

### 6.4 测试覆盖分析

| 测试类型 | 覆盖情况 | 缺口 |
|----------|----------|------|
| 单元测试 | `test_artifact_workflow_and_binaries.py` 覆盖打包逻辑 | 缺少实际 wheel 构建测试 |
| 集成测试 | `test_real_app_server_integration.py` 覆盖端到端 | 需要 `RUN_REAL_CODEX_TESTS=1` 触发 |
| 平台测试 | CI 覆盖 6 平台构建 | 无自动化 runtime wheel 安装测试 |

---

## 附录

### A. 关键常量汇总

| 常量 | 值 | 位置 |
|------|-----|------|
| 包名 | `codex-cli-bin` | `__init__.py:6`, `client.py:50` |
| 当前 pinned 版本 | `0.116.0-alpha.1` | `_runtime_setup.py:19` |
| 二进制文件名 (Unix) | `codex` | `__init__.py:10` |
| 二进制文件名 (Windows) | `codex.exe` | `__init__.py:10` |
| 最小 Python 版本 | `3.10` | `pyproject.toml:10` |

### B. 相关文档链接

- SDK 使用文档：`sdk/python/docs/getting-started.md`
- SDK FAQ：`sdk/python/docs/faq.md`
- 发布流程：`sdk/python/README.md` (Maintainer workflow 章节)
