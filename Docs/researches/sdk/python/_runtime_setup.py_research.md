# sdk/python/_runtime_setup.py 研究文档

## 场景与职责

`_runtime_setup.py` 是 Python SDK 的运行时安装与管理系统，核心职责包括：

1. **自动运行时安装**: 在首次使用 SDK 时自动下载并安装 `codex-cli-bin` 包
2. **版本管理**: 确保安装的运行时版本与 SDK 期望的版本一致（`PINNED_RUNTIME_VERSION = "0.116.0-alpha.1"`）
3. **跨平台支持**: 支持 macOS、Linux、Windows 的 x86_64 和 aarch64 架构
4. **多种下载策略**: 支持直接下载、GitHub API、GitHub CLI 三种获取方式

该模块主要在 `examples/_bootstrap.py` 中被调用，为本地开发环境提供零配置启动体验。

## 功能点目的

### 1. 版本固定机制
```python
PACKAGE_NAME = "codex-cli-bin"
PINNED_RUNTIME_VERSION = "0.116.0-alpha.1"
REPO_SLUG = "openai/codex"
```
- 明确指定所需的运行时版本
- 从 `openai/codex` GitHub 仓库获取 Release

### 2. 平台检测与资源映射
```python
def platform_asset_name() -> str:
    system = platform.system().lower()
    machine = platform.machine().lower()
    
    if system == "darwin":
        if machine in {"arm64", "aarch64"}:
            return "codex-aarch64-apple-darwin.tar.gz"
        # ...
```
- 自动检测当前操作系统和架构
- 映射到对应的 Release Asset 文件名

### 3. 运行时安装流程
`ensure_runtime_package_installed()` 函数的核心流程：
1. 检查已安装版本是否与期望版本匹配
2. 创建临时目录用于下载和提取
3. 下载 Release Archive（多策略回退）
4. 提取运行时二进制文件
5. 暂存运行时包（调用 `update_sdk_artifacts.py`）
6. 使用 pip 安装暂存的包
7. 验证安装结果

### 4. 多策略下载机制
`_download_release_archive()` 实现了三层回退策略：

**第一层：直接下载**
```python
browser_download_url = f"https://github.com/{REPO_SLUG}/releases/download/rust-v{version}/{asset_name}"
```

**第二层：GitHub API（带认证）**
- 使用 `GH_TOKEN` 或 `GITHUB_TOKEN` 环境变量
- 处理 401 错误时自动回退到无认证请求

**第三层：GitHub CLI**
```python
subprocess.run([
    "gh", "release", "download", f"rust-v{version}",
    "--repo", REPO_SLUG, "--pattern", asset_name, ...
])
```

### 5. 版本规范化
```python
def _normalized_package_version(version: str) -> str:
    return version.strip().replace("-alpha.", "a").replace("-beta.", "b")
```
- 处理 Python 包版本与 Rust 版本命名差异
- 例如：`0.116.0-alpha.1` → `0.116.0a1`

## 具体技术实现

### 核心数据结构

```python
class RuntimeSetupError(RuntimeError):
    pass
```
- 专门的异常类型用于运行时安装错误

### 关键函数流程

#### ensure_runtime_package_installed
```
输入: python_executable, sdk_python_dir, install_target(可选)
输出: 安装的版本号

1. 获取期望版本 (pinned_runtime_version())
2. 检查已安装版本 (_installed_runtime_version())
3. 如果版本匹配，直接返回
4. 创建临时目录
5. 下载 Release Archive (_download_release_archive)
6. 提取二进制文件 (_extract_runtime_binary)
7. 暂存运行时包 (_stage_runtime_package)
8. 安装包 (_install_runtime_package)
9. 验证安装结果
10. 返回版本号
```

#### _download_release_archive 的回退逻辑
```
1. 尝试直接浏览器下载 URL
2. 如果失败，获取 Release Metadata
3. 尝试使用 GitHub API 下载（带 Token）
4. 如果都失败且安装了 gh CLI，使用 gh 命令下载
5. 如果全部失败，抛出 RuntimeSetupError
```

#### _extract_runtime_binary
```
1. 创建提取目录
2. 根据文件扩展名选择提取方式（tar.gz 或 zip）
3. 递归查找候选二进制文件
4. 返回第一个匹配的文件路径
```

### 安全考虑
1. **Token 安全**: 从环境变量读取 `GH_TOKEN`/`GITHUB_TOKEN`，不硬编码
2. **临时文件**: 使用 `tempfile.TemporaryDirectory` 确保清理
3. **权限设置**: 非 Windows 平台设置可执行权限

## 关键代码路径与文件引用

### 调用方
| 文件 | 调用点 | 用途 |
|------|--------|------|
| `examples/_bootstrap.py` | `ensure_runtime_package_installed(sys.executable, _SDK_PYTHON_DIR)` | 示例自动安装运行时 |

### 被调用方
| 文件 | 调用点 | 用途 |
|------|--------|------|
| `scripts/update_sdk_artifacts.py` | `_stage_runtime_package()` 中动态导入 | 暂存运行时包 |

### 相关文件
| 文件 | 关系 |
|------|------|
| `sdk/python-runtime/` | 运行时包模板目录 |
| `sdk/python-runtime/pyproject.toml` | 运行时包配置模板 |
| `sdk/python-runtime/src/codex_cli_bin/__init__.py` | 运行时包入口 |

### 测试覆盖
| 测试文件 | 测试内容 |
|----------|----------|
| `tests/test_artifact_workflow_and_binaries.py` | 运行时包构建、版本检查、下载逻辑 |

## 依赖与外部交互

### 外部系统依赖
1. **GitHub Releases**: 从 `openai/codex` 下载预编译二进制
2. **pip**: 用于安装暂存的运行时包
3. **GitHub CLI (可选)**: 作为下载回退方案

### Python 标准库依赖
- `importlib`: 动态导入 `update_sdk_artifacts` 模块
- `urllib.request`: HTTP 下载
- `tempfile`: 临时目录管理
- `tarfile`/`zipfile`: 压缩包解压
- `platform`: 系统/架构检测
- `subprocess`: 执行 pip 和 gh CLI

### 环境变量
| 变量 | 用途 |
|------|------|
| `GH_TOKEN` | GitHub API 认证（首选） |
| `GITHUB_TOKEN` | GitHub API 认证（备选） |

## 风险、边界与改进建议

### 风险点

1. **网络依赖**: 首次使用必须能访问 GitHub
   - 缓解：支持 GH_TOKEN 认证，支持 gh CLI 回退
   
2. **版本漂移**: `PINNED_RUNTIME_VERSION` 需要手动更新
   - 缓解：测试 `test_examples_readme_matches_pinned_runtime_version` 检查一致性

3. **平台支持限制**: 仅支持特定平台/架构组合
   - 不支持的组合会抛出 `RuntimeSetupError`

4. **pip 依赖**: 假设系统有可用的 pip
   - 使用 `python -m pip` 调用，而非直接 `pip`

### 边界条件

1. **版本规范化差异**: Python 和 Rust 版本号格式不同
   - alpha → a, beta → b
   
2. **并发安装**: 临时目录使用 `prefix="codex-python-runtime-"` 避免冲突

3. **缓存失效**: 安装后调用 `importlib.invalidate_caches()` 刷新导入缓存

4. **二进制查找**: 提取后通过文件名模式匹配查找二进制文件
   - 支持 `codex`, `codex.exe`, `codex-*` 等模式

### 改进建议

1. **镜像支持**: 添加对国内镜像（如 Gitee）的支持，避免 GitHub 访问问题
   ```python
   MIRROR_URLS = [
       f"https://github.com/{REPO_SLUG}/releases/download/...",
       f"https://ghproxy.com/https://github.com/{REPO_SLUG}/releases/download/...",
   ]
   ```

2. **缓存机制**: 添加下载缓存，避免重复下载相同版本
   ```python
   CACHE_DIR = Path.home() / ".cache" / "codex-python-runtime"
   ```

3. **进度显示**: 大文件下载时添加进度条
   ```python
   from urllib.request import urlopen
   # 使用 tqdm 或类似库显示进度
   ```

4. **校验和验证**: 下载后验证文件校验和
   - GitHub Release 通常提供 SHA256 校验文件

5. **离线模式**: 支持 `CODEX_OFFLINE=1` 环境变量，跳过下载仅使用已安装版本

6. **版本兼容性检查**: 在 SDK 初始化时检查运行时版本兼容性
   ```python
   if installed_version < min_required_version:
       raise RuntimeSetupError(f"Runtime {installed_version} is too old, need >= {min_required}")
   ```

7. **代理支持**: 显式支持 HTTP_PROXY/HTTPS_PROXY
   ```python
   proxy_handler = urllib.request.ProxyHandler({
       'http': os.environ.get('HTTP_PROXY'),
       'https': os.environ.get('HTTPS_PROXY'),
   })
   ```

8. **错误信息改进**: 下载失败时提供更详细的排查指南
   - 检查网络连接
   - 检查 GitHub 访问权限
   - 提供手动下载和安装的步骤
