# sdk/python-runtime/README.md 研究文档

## 场景与职责

`README.md` 是 `codex-cli-bin` Python 运行时包的说明文档，位于 `sdk/python-runtime/` 目录下。该包是一个平台特定的运行时包，被已发布的 `codex-app-server-sdk` 所依赖消费。

### 核心定位

1. **桥梁角色**：作为连接 Python SDK (`codex-app-server-sdk`) 与底层 Codex CLI 二进制文件的桥梁
2. **版本锁定**：允许 SDK 精确锁定 Codex CLI 版本，而无需将平台二进制文件检入代码仓库
3. **平台分发**：以平台特定的 wheel 形式分发，每个 wheel 包含对应平台的 `codex` 可执行文件

### 与相关组件的关系

```
┌─────────────────────────────────────────────────────────────────┐
│                    codex-app-server-sdk                         │
│                     (Python SDK 包)                             │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │         依赖: codex-cli-bin==<pinned_version>           │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      codex-cli-bin                              │
│                   (Python Runtime 包)                           │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  • src/codex_cli_bin/__init__.py                        │   │
│  │  • src/codex_cli_bin/bin/codex (平台特定二进制)          │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    codex CLI 二进制文件                          │
│              (Rust 构建的 app-server 可执行文件)                  │
└─────────────────────────────────────────────────────────────────┘
```

## 功能点目的

### 1. 运行时分发机制

该包解决了 Python SDK 如何获取并执行 Codex CLI 的核心问题：

- **问题**：Python SDK 需要调用 `codex app-server` 命令，但不同平台需要不同的二进制文件
- **解决方案**：通过 PyPI 分发平台特定的 wheel 包，每个 wheel 包含对应平台的二进制文件
- **优势**：用户安装 SDK 时自动获得正确的二进制文件，无需手动下载配置

### 2. Wheel-Only 策略

文档明确指出 `codex-cli-bin` 是 **wheel-only** 包，禁止构建或发布 sdist：

```
`codex-cli-bin` is intentionally wheel-only. Do not build or publish an sdist
for this package.
```

**原因分析**：
- sdist 需要源码编译，但二进制文件无法从源码构建（需要 Rust 工具链）
- 平台特定二进制文件必须在发布时通过 CI 构建并嵌入 wheel
- 强制 wheel-only 确保用户始终获得预构建的平台特定包

### 3. 发布流程集成

该包是 CI/CD 发布流程的关键组成部分：

1. **Rust Release** (`.github/workflows/rust-release.yml`): 构建多平台 `codex` 二进制文件
2. **Staging** (`sdk/python/scripts/update_sdk_artifacts.py`): 将二进制文件打包为 `codex-cli-bin` wheel
3. **PyPI Publish**: 上传平台特定的 wheel 到 PyPI
4. **SDK Dependency**: `codex-app-server-sdk` 声明对特定版本 `codex-cli-bin` 的依赖

## 具体技术实现

### 包结构

```
sdk/python-runtime/
├── README.md              # 本文档
├── pyproject.toml         # 包配置（构建系统、元数据、Hatch 配置）
├── hatch_build.py         # 自定义 Hatch 构建钩子（阻止 sdist 构建）
└── src/codex_cli_bin/
    ├── __init__.py        # 提供 bundled_codex_path() API
    └── bin/               # 构建时嵌入的二进制文件目录
        └── codex          # 平台特定的 codex 可执行文件
```

### 关键 API

`__init__.py` 暴露的核心函数：

```python
def bundled_codex_path() -> Path:
    """返回包内嵌入的 codex 二进制文件路径"""
    exe = "codex.exe" if os.name == "nt" else "codex"
    path = Path(__file__).resolve().parent / "bin" / exe
    if not path.is_file():
        raise FileNotFoundError(...)
    return path
```

该函数被 `codex_app_server.client` 模块调用以定位可执行文件。

## 关键代码路径与文件引用

### 调用方（Consumers）

| 文件 | 用途 |
|------|------|
| `sdk/python/src/codex_app_server/client.py:80-90` | `_installed_codex_path()` 导入并调用 `bundled_codex_path()` |
| `sdk/python/_runtime_setup.py:102-120` | 检查已安装的 runtime 版本 |
| `sdk/python/scripts/update_sdk_artifacts.py:143-160` | `stage_python_runtime_package()` 构建 runtime 包 |

### 被调用方 / 依赖

| 文件 | 用途 |
|------|------|
| `codex-rs/target/*/release/codex` | Rust 构建的原始二进制文件，被嵌入 wheel |
| `hatchling` | 构建后端，通过 `hatch_build.py` 自定义构建行为 |

### 配置引用

| 文件 | 相关配置 |
|------|----------|
| `sdk/python/pyproject.toml:25` | SDK 依赖声明 `"codex-cli-bin=={version}"` |
| `sdk/python-runtime/pyproject.toml:37-44` | Wheel 构建配置，包含二进制文件 |

## 依赖与外部交互

### 构建时依赖

- **hatchling>=1.24.0**: 现代 Python 构建后端，支持自定义构建钩子
- **Hatch 构建钩子** (`hatch_build.py`): 阻止 sdist 构建，标记为非纯 Python 包

### 运行时依赖

- **无**: 该包是纯数据包，仅包含二进制文件和路径查询 API
- **Python>=3.10**: 支持的 Python 版本（与 SDK 一致）

### 外部系统交互

| 交互方 | 方式 | 目的 |
|--------|------|------|
| GitHub Releases | CI 下载 | 获取构建好的平台二进制文件 |
| PyPI | 上传/下载 | 分发平台 wheel 包 |
| `codex-app-server-sdk` | pip 依赖 | 被 SDK 安装时自动引入 |

## 风险、边界与改进建议

### 风险点

1. **平台覆盖不全**
   - 当前支持：macOS (x86_64, arm64), Linux (x86_64, arm64, musl/gnu), Windows (x86_64, arm64)
   - 风险：某些边缘平台（如 Alpine Linux on ARM）可能无法使用

2. **版本同步问题**
   - `codex-cli-bin` 版本必须与 Rust CLI 版本严格对应
   - SDK (`_runtime_setup.py`) 中的 `PINNED_RUNTIME_VERSION` 必须与实际发布的 runtime 版本一致
   - 测试 `test_examples_readme_matches_pinned_runtime_version` 验证此同步

3. **二进制文件缺失**
   - 如果 wheel 构建流程失败，可能导致发布的 wheel 缺少二进制文件
   - `bundled_codex_path()` 会在运行时检查并抛出 `FileNotFoundError`

### 边界条件

1. **Wheel-Only 强制执行**
   - `hatch_build.py` 在 `target_name == "sdist"` 时抛出 `RuntimeError`
   - 防止意外发布 sdist 到 PyPI

2. **平台检测**
   - `_runtime_setup.py:72-95` 的 `platform_asset_name()` 函数处理平台检测
   - 未知平台会抛出 `RuntimeSetupError`

3. **并发安装**
   - `_runtime_setup.py` 使用临时目录和文件锁确保安全的并发安装

### 改进建议

1. **增强错误信息**
   ```python
   # 当前
   raise FileNotFoundError(f"{PACKAGE_NAME} is installed but missing its packaged codex binary at {path}")
   
   # 建议：添加平台信息和安装指导
   raise FileNotFoundError(
       f"{PACKAGE_NAME} is installed but missing its packaged codex binary at {path}. "
       f"Platform: {platform.system()} {platform.machine()}. "
       "Please ensure you installed the correct platform wheel."
   )
   ```

2. **版本信息暴露**
   - 当前 `__init__.py` 仅暴露 `PACKAGE_NAME` 和 `bundled_codex_path()`
   - 建议增加 `bundled_codex_version()` 函数，便于调试版本问题

3. **健康检查命令**
   - 添加 CLI 入口点 `python -m codex_cli_bin --check` 验证安装完整性

4. **文档完善**
   - README 可以增加发布流程的链接或简要说明
   - 添加故障排除部分，指导用户解决常见的平台不匹配问题
