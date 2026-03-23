# stage_npm_packages.py 深度研究文档

## 场景与职责

`stage_npm_packages.py` 是一个 NPM 包发布准备工具，用于自动化构建、打包和准备 Codex CLI 的 NPM 发布包。该脚本主要服务于以下场景：

1. **发布流程自动化**：简化多平台 NPM 包的发布准备
2. **原生二进制集成**：将 Rust 编译的原生二进制打包到 NPM 包中
3. **多平台支持**：为 Linux、macOS、Windows 的 x64 和 arm64 架构准备包
4. **CI/CD 集成**：在 GitHub Actions 中自动执行发布准备

### 在 CI 中的位置

```yaml
# .github/workflows/ci.yml
- name: Stage npm package
  id: stage_npm_package
  env:
    GH_TOKEN: ${{ github.token }}
  run: |
    set -euo pipefail
    CODEX_VERSION=0.115.0
    OUTPUT_DIR="${RUNNER_TEMP}"
    python3 ./scripts/stage_npm_packages.py \
      --release-version "$CODEX_VERSION" \
      --package codex \
      --output-dir "$OUTPUT_DIR"
```

### 包结构概览

Codex NPM 发布采用多包策略：
- `@openai/codex` - 主包（平台无关，依赖平台包）
- `@openai/codex-linux-x64` - Linux x64 原生二进制
- `@openai/codex-linux-arm64` - Linux ARM64 原生二进制
- `@openai/codex-darwin-x64` - macOS x64 原生二进制
- `@openai/codex-darwin-arm64` - macOS ARM64 原生二进制
- `@openai/codex-win32-x64` - Windows x64 原生二进制
- `@openai/codex-win32-arm64` - Windows ARM64 原生二进制

## 功能点目的

### 1. 多包管理
- **目的**：支持同时准备多个相关包
- **包扩展机制**：`PACKAGE_EXPANSIONS` 定义包别名展开
  - `codex` → `codex` + 所有平台包

### 2. 原生组件收集
- **目的**：确定每个包需要的原生二进制组件
- **组件映射**：`PACKAGE_NATIVE_COMPONENTS`
  - `codex` 主包：无原生组件
  - 平台包：`codex` + `rg`（ripgrep）
  - Windows 平台额外包含：`codex-windows-sandbox-setup` + `codex-command-runner`

### 3. GitHub Actions 工作流集成
- **目的**：从 CI 工作流下载预编译的原生二进制
- **流程**：
  1. 解析版本号对应的分支 `rust-v{version}`
  2. 查找 `rust-release.yml` 工作流的运行记录
  3. 下载工作流产物（artifacts）

### 4. 临时目录管理
- **目的**：安全地管理构建过程中的临时文件
- **策略**：
  - 使用 `RUNNER_TEMP` 环境变量（CI 环境）或系统临时目录
  - 支持 `--keep-staging-dirs` 保留目录用于调试
  - 自动清理（除非指定保留）

### 5. NPM 打包
- **目的**：生成最终的 `.tgz` 发布包
- **工具**：使用 `npm pack` 命令
- **命名**：`{package}-npm-{version}.tgz` 或 `codex-npm-{platform}-{version}.tgz`

## 具体技术实现

### 核心数据结构

```python
# 从 build_npm_package.py 动态导入的配置
PACKAGE_NATIVE_COMPONENTS: dict[str, list[str]] = {
    "codex": [],
    "codex-linux-x64": ["codex", "rg"],
    "codex-linux-arm64": ["codex", "rg"],
    "codex-darwin-x64": ["codex", "rg"],
    "codex-darwin-arm64": ["codex", "rg"],
    "codex-win32-x64": ["codex", "rg", "codex-windows-sandbox-setup", "codex-command-runner"],
    "codex-win32-arm64": ["codex", "rg", "codex-windows-sandbox-setup", "codex-command-runner"],
    "codex-responses-api-proxy": ["codex-responses-api-proxy"],
    "codex-sdk": [],
}

PACKAGE_EXPANSIONS: dict[str, list[str]] = {
    "codex": ["codex", *CODEX_PLATFORM_PACKAGES],
}

CODEX_PLATFORM_PACKAGES: dict[str, dict[str, str]] = {
    "codex-linux-x64": {"target_triple": "x86_64-unknown-linux-musl", ...},
    "codex-linux-arm64": {"target_triple": "aarch64-unknown-linux-musl", ...},
    # ... 其他平台
}
```

### 关键流程

```
解析命令行参数
├── 展开包列表（应用 PACKAGE_EXPANSIONS）
├── 收集所需原生组件
├── 如有原生组件：
│   ├── 解析工作流 URL（--workflow-url 或自动查找）
│   ├── 创建临时 vendor 目录
│   └── 调用 install_native_deps.py 下载组件
├── 对每个包：
│   ├── 创建临时 staging 目录
│   ├── 调用 build_npm_package.py 构建包
│   │   ├── 复制源码文件
│   │   ├── 复制原生二进制（如有）
│   │   ├── 生成/修改 package.json
│   │   └── 执行 npm pack
│   └── 清理 staging 目录（除非 --keep-staging-dirs）
├── 清理 vendor 目录（除非 --keep-staging-dirs）
└── 输出结果摘要
```

### GitHub CLI 集成

```python
def resolve_release_workflow(version: str) -> dict:
    """查找指定版本的 rust-release 工作流运行记录"""
    cmd = [
        "gh", "run", "list",
        "--branch", f"rust-v{version}",
        "--json", "workflowName,url,headSha",
        "--workflow", WORKFLOW_NAME,
        "--jq", "first(.[])",
    ]
    stdout = subprocess.check_output(cmd, cwd=REPO_ROOT, text=True)
    return json.loads(stdout or "null")
```

### 模块动态导入

```python
# 从 build_npm_package.py 导入配置常量
_SPEC = importlib.util.spec_from_file_location(
    "codex_build_npm_package", BUILD_SCRIPT
)
_BUILD_MODULE = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_BUILD_MODULE)
PACKAGE_NATIVE_COMPONENTS = getattr(_BUILD_MODULE, "PACKAGE_NATIVE_COMPONENTS", {})
PACKAGE_EXPANSIONS = getattr(_BUILD_MODULE, "PACKAGE_EXPANSIONS", {})
CODEX_PLATFORM_PACKAGES = getattr(_BUILD_MODULE, "CODEX_PLATFORM_PACKAGES", {})
```

### 依赖脚本

```python
BUILD_SCRIPT = REPO_ROOT / "codex-cli" / "scripts" / "build_npm_package.py"
INSTALL_NATIVE_DEPS = REPO_ROOT / "codex-cli" / "scripts" / "install_native_deps.py"
```

## 关键代码路径与文件引用

### 脚本本身
- **路径**：`scripts/stage_npm_packages.py` (206 行)
- **Shebang**：`#!/usr/bin/env python3`

### 依赖脚本
- `codex-cli/scripts/build_npm_package.py` - 构建单个 NPM 包
- `codex-cli/scripts/install_native_deps.py` - 下载原生二进制依赖

### 调用方
- **CI 工作流**：`.github/workflows/ci.yml`
- **发布工作流**：`.github/workflows/rust-release.yml`（间接）

### 配置文件
- `codex-cli/package.json` - 主包配置模板
- `codex-cli/bin/codex.js` - CLI 入口脚本
- `codex-cli/bin/rg` - ripgrep 的 DotSlash 清单

### 相关文件
- `MODULE.bazel.lock` - Bazel 依赖锁文件
- `.github/workflows/rust-release.yml` - 原生二进制构建工作流

## 依赖与外部交互

### Python 标准库
| 模块 | 用途 |
|------|------|
| `argparse` | 命令行参数解析 |
| `importlib.util` | 动态导入 build_npm_package.py |
| `json` | 解析 GitHub CLI 输出 |
| `os` | 环境变量访问 |
| `shutil` | 目录清理 |
| `subprocess` | 执行 GitHub CLI 和构建脚本 |
| `tempfile` | 临时目录创建 |
| `pathlib.Path` | 路径处理 |

### 外部工具
| 工具 | 用途 | 来源 |
|------|------|------|
| `gh` | GitHub CLI，查询工作流 | GitHub |
| `npm` | 打包发布包 | Node.js |
| `build_npm_package.py` | 包构建逻辑 | 项目内 |
| `install_native_deps.py` | 原生依赖下载 | 项目内 |

### 环境变量
| 变量 | 用途 |
|------|------|
| `GH_TOKEN` | GitHub CLI 认证 |
| `RUNNER_TEMP` | GitHub Actions 临时目录 |

### 网络依赖
- GitHub API（通过 `gh` CLI）
- GitHub Actions 产物下载

## 风险、边界与改进建议

### 已知风险

1. **工作流查找失败**
   - 风险：找不到对应版本的 `rust-release` 工作流运行
   - 场景：工作流尚未完成或分支名称不匹配
   - 错误：`Unable to find rust-release workflow for version {version}`

2. **GitHub CLI 依赖**
   - 风险：需要 `gh` 命令且需要认证
   - 场景：本地开发环境可能未配置

3. **版本号格式敏感**
   - 风险：版本号必须与分支名 `rust-v{version}` 匹配
   - 示例：`0.115.0` → 分支 `rust-v0.115.0`

4. **并发问题**
   - 风险：多个包同时下载可能触发速率限制
   - 缓解：当前顺序处理，非并发

### 边界情况

1. **无原生组件的包**
   - 处理：跳过工作流查找和 vendor 下载
   - 示例：`codex-sdk`

2. **--workflow-url 覆盖**
   - 行为：直接使用提供的 URL，不自动查找
   - 用途：调试或重试特定工作流

3. **临时目录清理失败**
   - 处理：`shutil.rmtree` 使用 `ignore_errors=True`
   - 风险：可能留下孤儿目录

4. **HEAD SHA 提示**
   - 行为：如从工作流解析到 SHA，提示用户 checkout
   - 输出：`should git checkout {sha}`

### 改进建议

1. **添加重试机制**
   ```python
   from functools import wraps
   
   def retry_on_error(max_attempts=3):
       def decorator(func):
           @wraps(func)
           def wrapper(*args, **kwargs):
               for attempt in range(max_attempts):
                   try:
                       return func(*args, **kwargs)
                   except Exception as e:
                       if attempt == max_attempts - 1:
                           raise
                       time.sleep(2 ** attempt)
           return wrapper
       return decorator
   ```

2. **支持本地二进制路径**
   ```python
   parser.add_argument("--local-binaries", type=Path,
                       help="Use locally built binaries instead of downloading")
   ```

3. **添加并行构建**
   ```python
   from concurrent.futures import ThreadPoolExecutor
   
   with ThreadPoolExecutor(max_workers=4) as executor:
       futures = [executor.submit(build_package, pkg) for pkg in packages]
   ```

4. **验证产物完整性**
   ```python
   def verify_tarball(path: Path) -> bool:
       """验证生成的 tarball 可解压且包含必要文件"""
       import tarfile
       with tarfile.open(path, "r:gz") as tar:
           # 检查关键文件存在
           pass
   ```

5. **添加详细日志**
   ```python
   parser.add_argument("-v", "--verbose", action="store_true")
   # 输出每个步骤的详细信息
   ```

6. **支持增量构建**
   ```python
   parser.add_argument("--cache-dir", type=Path,
                       help="Cache downloaded artifacts")
   ```

7. **版本兼容性检查**
   ```python
   def check_version_compatibility(version: str) -> bool:
       """检查版本号格式是否符合预期"""
       import re
       return bool(re.match(r'^\d+\.\d+\.\d+(-\w+\.\d+)?$', version))
   ```

8. **添加产物校验和**
   ```python
   import hashlib
   
   def compute_checksum(path: Path) -> str:
       sha256 = hashlib.sha256()
       with open(path, "rb") as f:
           for chunk in iter(lambda: f.read(8192), b""):
               sha256.update(chunk)
       return sha256.hexdigest()
   ```

### 测试建议

```python
# 单元测试场景
def test_package_expansion():
    """测试包别名展开"""
    assert expand_packages(["codex"]) == ["codex", "codex-linux-x64", ...]

def test_component_collection():
    """测试原生组件收集"""
    components = collect_native_components(["codex-linux-x64"])
    assert components == {"codex", "rg"}

def test_workflow_resolution():
    """测试工作流 URL 解析"""
    # Mock gh CLI 输出
    pass

def test_tarball_naming():
    """测试 tarball 命名规则"""
    assert tarball_name_for_package("codex", "0.1.0") == "codex-npm-0.1.0.tgz"
    assert tarball_name_for_package("codex-linux-x64", "0.1.0") == "codex-npm-linux-x64-0.1.0.tgz"
```

### 发布流程时序图

```
Developer                    stage_npm_packages                    GitHub Actions
    |                               |                                      |
    |-- trigger release --------->|                                      |
    |                               |-- query workflow list ------------->|
    |                               |<-- workflow URL & SHA ---------------|
    |                               |                                      |
    |                               |-- download artifacts -------------->|
    |                               |<-- native binaries (zst) ------------|
    |                               |                                      |
    |                               |-- extract & stage ---------------->|
    |                               |   (for each platform)                |
    |                               |                                      |
    |                               |-- npm pack ------------------------>|
    |<-- staged tarballs -----------|                                      |
    |                               |                                      |
    |-- npm publish -------------->|                                      |
```
