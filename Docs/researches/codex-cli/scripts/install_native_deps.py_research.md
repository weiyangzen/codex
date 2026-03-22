# codex-cli/scripts/install_native_deps.py 研究文档

## 场景与职责

`install_native_deps.py` 是 Codex CLI 原生依赖（Rust 二进制 + ripgrep）的**一站式安装器**。该脚本服务于以下核心场景：

1. **发布准备**: 为 `build_npm_package.py` 预填充 `vendor/` 目录
2. **开发环境搭建**: 开发者在本地获取所有平台的原生二进制
3. **CI/CD 集成**: GitHub Actions 工作流中自动下载构建产物

脚本的核心职责：
- 从 GitHub Actions workflow 下载 Rust 构建产物（artifacts）
- 解压并安装多平台原生二进制到 `vendor/<target>/<component>/`
- 通过 DotSlash manifest 下载并安装 ripgrep 二进制
- 支持并发下载以提高效率

## 功能点目的

### 组件矩阵

脚本管理以下原生组件：

| 组件 | 目标平台 | 说明 |
|------|----------|------|
| `codex` | 全部 6 个目标 | Rust CLI 主程序 |
| `codex-responses-api-proxy` | 全部 6 个目标 | Responses API 代理 |
| `codex-windows-sandbox-setup` | Windows only | Windows 沙箱初始化 |
| `codex-command-runner` | Windows only | Windows 命令执行器 |
| `rg` (ripgrep) | 全部 6 个目标 | 代码搜索工具 |

### 目标平台定义

```python
BINARY_TARGETS = (
    "x86_64-unknown-linux-musl",
    "aarch64-unknown-linux-musl",
    "x86_64-apple-darwin",
    "aarch64-apple-darwin",
    "x86_64-pc-windows-msvc",
    "aarch64-pc-windows-msvc",
)
```

**命名约定**：使用 Rust 目标三元组（target triple），与 GitHub Actions artifact 命名一致。

## 具体技术实现

### 数据结构详解

#### 1. 二进制组件定义 (行 36-69)

```python
@dataclass(frozen=True)
class BinaryComponent:
    artifact_prefix: str      # artifact 文件名前缀
    dest_dir: str             # vendor/<target>/ 下的子目录
    binary_basename: str      # 可执行文件名（不含 .exe）
    targets: tuple[str, ...] | None = None  # 可选的目标限制

BINARY_COMPONENTS = {
    "codex": BinaryComponent(
        artifact_prefix="codex",
        dest_dir="codex",
        binary_basename="codex",
    ),
    "codex-windows-sandbox-setup": BinaryComponent(
        artifact_prefix="codex-windows-sandbox-setup",
        dest_dir="codex",
        binary_basename="codex-windows-sandbox-setup",
        targets=WINDOWS_TARGETS,  # 仅 Windows
    ),
    # ...
}
```

**设计要点**：
- `frozen=True` 确保配置不可变
- `targets` 为 `None` 表示安装到所有目标
- Windows 组件通过 `targets` 限制避免在其他平台创建空目录

#### 2. ripgrep 平台映射 (行 71-80)

```python
RG_TARGET_PLATFORM_PAIRS: list[tuple[str, str]] = [
    ("x86_64-unknown-linux-musl", "linux-x86_64"),
    ("aarch64-unknown-linux-musl", "linux-aarch64"),
    ("x86_64-apple-darwin", "macos-x86_64"),
    ("aarch64-apple-darwin", "macos-aarch64"),
    ("x86_64-pc-windows-msvc", "windows-x86_64"),
    ("aarch64-pc-windows-msvc", "windows-aarch64"),
]
```

**映射目的**：将 Rust 目标三元组转换为 DotSlash manifest 中的平台键名。

### 核心流程

#### 主函数流程 (行 154-191)

```
parse_args() → 准备 vendor 目录 → 下载 artifacts → 安装二进制组件 → [安装 ripgrep]
```

**条件逻辑**：
- 仅当 `rg` 在组件列表中时才执行 ripgrep 安装
- 默认组件：`["codex", "codex-windows-sandbox-setup", "codex-command-runner", "rg"]`

#### Artifacts 下载 (行 262-273)

```python
def _download_artifacts(workflow_id: str, dest_dir: Path) -> None:
    cmd = [
        "gh", "run", "download",
        "--dir", str(dest_dir),
        "--repo", "openai/codex",
        workflow_id,
    ]
    subprocess.check_call(cmd)
```

**依赖**：GitHub CLI (`gh`) 必须已认证并有仓库访问权限。

#### 二进制组件安装 (行 276-305)

```python
def install_binary_components(
    artifacts_dir: Path,      # gh run download 输出目录
    vendor_dir: Path,         # 目标 vendor 目录
    selected_components: Sequence[BinaryComponent],
) -> None:
```

**并发策略**：
- 使用 `ThreadPoolExecutor` 并行安装多个目标
- 工作者数量：`min(len(targets), cpu_count)`

**单目标安装流程** (`_install_single_binary`, 行 308-331)：

```python
def _install_single_binary(
    artifacts_dir: Path,
    vendor_dir: Path,
    target: str,
    component: BinaryComponent,
) -> Path:
    # 1. 构造 artifact 路径
    archive_name = _archive_name_for_target(component.artifact_prefix, target)
    archive_path = artifacts_dir / target / archive_name
    
    # 2. 创建目标目录
    dest_dir = vendor_dir / target / component.dest_dir
    dest_dir.mkdir(parents=True, exist_ok=True)
    
    # 3. 构造最终二进制文件名
    binary_name = f"{component.binary_basename}.exe" if "windows" in target else component.binary_basename
    dest = dest_dir / binary_name
    
    # 4. 解压并设置权限
    extract_archive(archive_path, "zst", None, dest)
    if "windows" not in target:
        dest.chmod(0o755)
    return dest
```

**文件名构造规则** (`_archive_name_for_target`, 行 334-337)：
```python
def _archive_name_for_target(artifact_prefix: str, target: str) -> str:
    if "windows" in target:
        return f"{artifact_prefix}-{target}.exe.zst"
    return f"{artifact_prefix}-{target}.zst"
```

#### ripgrep 安装 (行 194-259)

```python
def fetch_rg(
    vendor_dir: Path,
    targets: Sequence[str] | None = None,
    *,
    manifest_path: Path,  # bin/rg DotSlash manifest
) -> list[Path]:
```

**流程**：
1. 使用 `dotslash -- parse` 解析 manifest
2. 提取每个目标的平台配置（URL、格式、校验和等）
3. 并发下载和提取

**DotSlash 解析** (行 456-469)：
```python
def _load_manifest(manifest_path: Path) -> dict:
    cmd = ["dotslash", "--", "parse", str(manifest_path)]
    stdout = subprocess.check_output(cmd, text=True)
    return json.loads(stdout)
```

**单平台 ripgrep 安装** (`_fetch_single_rg`, 行 340-398)：
- 支持多种压缩格式：zst、tar.gz、zip
- 下载超时：60 秒 (`DOWNLOAD_TIMEOUT_SECS`)
- 权限设置：非 Windows 平台设置 755

#### 压缩文件解压 (行 409-453)

```python
def extract_archive(
    archive_path: Path,
    archive_format: str,       # "zst", "tar.gz", "zip"
    archive_member: str | None,  # 压缩包内的文件路径（tar/zip 需要）
    dest: Path,
) -> None:
```

**格式处理**：

| 格式 | 处理方式 | 依赖 |
|------|----------|------|
| zst | `zstd -f -d` | zstd 命令行工具 |
| tar.gz | `tarfile.open(..., "r:gz")` | Python 标准库 |
| zip | `zipfile.ZipFile` | Python 标准库 |

**安全考虑**：
- tar 提取使用 `filter="data"`（Python 3.12+ 安全过滤器）
- 解压前删除已存在的目标文件，避免文件拼接攻击

### GitHub Actions 集成

脚本包含专门的 GHA 优化功能：

#### 1. 环境检测 (行 86-90)
```python
def _gha_enabled() -> bool:
    return os.environ.get("GITHUB_ACTIONS") == "true"
```

#### 2. 日志分组 (行 109-119)
```python
@contextmanager
def _gha_group(title: str):
    if _gha_enabled():
        print(f"::group::{_gha_escape(title)}", flush=True)
    try:
        yield
    finally:
        if _gha_enabled():
            print("::endgroup::", flush=True)
```

**效果**：在 GitHub Actions 日志中创建可折叠的分组。

#### 3. 错误标注 (行 98-106)
```python
def _gha_error(*, title: str, message: str) -> None:
    if _gha_enabled():
        print(f"::error title={_gha_escape(title)}::{_gha_escape(message)}", flush=True)
```

**效果**：在 GitHub PR/Actions UI 中显示醒目的错误提示。

## 关键代码路径与文件引用

### 上游调用方

1. **`scripts/stage_npm_packages.py`** (行 121-125, 163)
   ```python
   def install_native_components(workflow_url: str, components: set[str], vendor_root: Path) -> None:
       cmd = [str(INSTALL_NATIVE_DEPS), "--workflow-url", workflow_url]
       for component in sorted(components):
           cmd.extend(["--component", component])
       cmd.append(str(vendor_root))
       run_command(cmd)
   ```

2. **手动调用**（开发场景）
   ```bash
   ./codex-cli/scripts/install_native_deps.py \
       --workflow-url https://github.com/openai/codex/actions/runs/17952349351 \
       --component codex --component rg \
       ./codex-cli
   ```

### 下游依赖

1. **`build_npm_package.py`**: 消费生成的 `vendor/` 目录
2. **`bin/rg`**: DotSlash manifest，用于 ripgrep 安装
3. **GitHub Actions artifacts**: 由 `rust-release.yml` 工作流生成

### 默认 Workflow

```python
DEFAULT_WORKFLOW_URL = "https://github.com/openai/codex/actions/runs/17952349351"  # rust-v0.40.0
```

这是硬编码的已知良好构建，用于未指定 workflow URL 时的回退。

## 依赖与外部交互

### 外部工具依赖

| 工具 | 用途 | 安装来源 |
|------|------|----------|
| `gh` | 下载 GitHub Actions artifacts | GitHub CLI |
| `zstd` | 解压 .zst 文件 | 系统包管理器 |
| `dotslash` | 解析 DotSlash manifest | Meta 提供的工具 |

### 网络依赖

| 端点 | 用途 |
|------|------|
| GitHub Actions API | 下载 workflow artifacts |
| GitHub releases | 下载 ripgrep 二进制（通过 DotSlash URL）|

### 文件系统约定

**输入**：
- `bin/rg`: DotSlash manifest 文件
- `/tmp/codex-native-artifacts-*/`: 临时 artifacts 目录

**输出**：
```
vendor/
├── x86_64-unknown-linux-musl/
│   ├── codex/codex              # 主程序
│   └── path/rg                  # ripgrep
├── aarch64-unknown-linux-musl/
│   └── ...
└── ...
```

## 风险、边界与改进建议

### 已知风险

1. **Workflow ID 硬编码过时**
   - `DEFAULT_WORKFLOW_URL` 指向特定构建，可能随时间变得不可用（artifacts 过期）
   - **缓解**: 定期更新默认值，或在 CI 中始终显式指定

2. **GitHub CLI 认证依赖**
   - `gh run download` 需要有效的 GitHub 认证
   - 在 fork 仓库或受限环境中可能失败

3. **并发下载竞争**
   - `ThreadPoolExecutor` 同时写入不同目标目录，但共享 `artifacts_dir`
   - 如果 artifact 解压产生临时文件，可能存在冲突

4. **校验和验证缺失**
   - 下载的 artifacts 没有验证 SHA256 校验和
   - 网络错误或中间人攻击可能导致损坏的二进制

5. **Windows 可执行权限**
   - Windows 二进制没有设置可执行权限（非 Windows 平台设置 755）
   - 在 Windows 宿主机上运行时可能需要额外处理

### 边界条件

| 场景 | 行为 |
|------|------|
| workflow_id 无效 | `gh run download` 失败，脚本退出 |
| artifact 缺失 | `FileNotFoundError`，脚本退出 |
| zstd 未安装 | `subprocess.CalledProcessError`，脚本退出 |
| dotslash 未安装 | `subprocess.CalledProcessError`，脚本退出 |
| manifest 解析失败 | `json.JSONDecodeError`，脚本退出 |
| 下载超时 (60s) | `socket.timeout`，脚本退出 |
| 目标目录已存在 | `mkdir(parents=True, exist_ok=True)` 静默处理 |
| 目标文件已存在 | `unlink(missing_ok=True)` 后重新创建 |

### 改进建议

1. **校验和验证**
   ```python
   # 添加校验和文件下载和验证
   def verify_checksum(file_path: Path, expected_digest: str) -> None:
       actual = hashlib.sha256(file_path.read_bytes()).hexdigest()
       if actual != expected_digest:
           raise RuntimeError(f"Checksum mismatch: {file_path}")
   ```

2. **重试机制**
   ```python
   # 添加指数退避重试
   from functools import wraps
   
   def retry(max_attempts: int = 3):
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

3. **进度显示**
   ```python
   # 下载进度回调
   def _download_file(url: str, dest: Path) -> None:
       with urlopen(url, timeout=DOWNLOAD_TIMEOUT_SECS) as response, open(dest, "wb") as out:
           total = int(response.headers.get("content-length", 0))
           downloaded = 0
           while chunk := response.read(8192):
               out.write(chunk)
               downloaded += len(chunk)
               if total:
                   print(f"\r{downloaded/total*100:.1f}%", end="", flush=True)
   ```

4. **增量更新**
   ```python
   # 跳过已存在且校验和匹配的文件
   if dest.exists():
       if verify_checksum(dest, expected_digest):
           print(f"Skipping {dest} (up to date)")
           return dest
   ```

5. **备用下载源**
   ```python
   # DotSlash manifest 支持多个 providers，当前只使用第一个
   for provider in providers:
       try:
           _download_file(provider["url"], download_path)
           break
       except Exception:
           continue
   else:
       raise RuntimeError("All providers failed")
   ```

6. **元数据记录**
   ```python
   # 记录安装来源信息
   (vendor_dir / ".install-meta.json").write_text(json.dumps({
       "workflow_id": workflow_id,
       "installed_at": datetime.utcnow().isoformat(),
       "components": [c.binary_basename for c in selected_components],
   }))
   ```

7. **类型安全增强**
   ```python
   # 使用 TypedDict 定义 manifest 结构
   from typing import TypedDict
   
   class DotSlashProvider(TypedDict):
       url: str
   
   class DotSlashPlatform(TypedDict):
       size: int
       hash: str
       digest: str
       format: str
       path: str
       providers: list[DotSlashProvider]
   ```

### 与相关组件的协同

```
GitHub Actions (rust-release.yml)
         │
         ▼ 生成 artifacts
install_native_deps.py
         │
         ▼ 填充 vendor/
build_npm_package.py
         │
         ▼ 打包到 npm tarball
npm publish
```

**关键约定**：
- Artifact 命名：`{prefix}-{target}.zst`（Linux/macOS）或 `{prefix}-{target}.exe.zst`（Windows）
- 目录结构：`vendor/<target>/<component>/<binary>`
- 权限：非 Windows 二进制必须可执行（755）
