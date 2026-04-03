# install-skill-from-github.py 研究文档

## 场景与职责

`install-skill-from-github.py` 是 Codex CLI 的 skill 安装工具，负责从 GitHub 仓库下载并安装 skill 到本地 `$CODEX_HOME/skills` 目录。支持两种安装方式：
1. **直接下载模式**：通过 GitHub 的 codeload 服务下载 ZIP 归档（默认，适用于公开仓库）
2. **Git 稀疏检出模式**：使用 `git sparse-checkout` 克隆指定路径（适用于私有仓库或下载失败时）

该脚本由 Codex agent 在接收到用户安装 skill 请求时调用，是 skill 生态系统的关键入口工具。

## 功能点目的

### 1. 参数解析与验证 (`_parse_args`, `_resolve_source`)
**目的**：解析命令行参数，支持多种输入格式（URL、owner/repo、path 等）。

**技术实现**：
- 使用 `argparse.ArgumentParser` 定义参数接口
- 支持 `--url`（完整 GitHub URL）、`--repo`（owner/repo 格式）、`--path`（仓库内路径）、`--ref`（分支/标签，默认 main）、`--dest`（目标目录）、`--name`（skill 名称）、`--method`（安装方式：auto/download/git）
- `_resolve_source` 将参数统一解析为 `Source` 数据结构
- URL 解析支持 `tree`/`blob` 路径格式，提取 ref 和子路径

**关键代码路径**：
```python
@dataclass
class Args:
    url: str | None = None
    repo: str | None = None
    path: list[str] | None = None
    ref: str = DEFAULT_REF
    dest: str | None = None
    name: str | None = None
    method: str = "auto"
```

### 2. ZIP 下载与解压 (`_download_repo_zip`, `_safe_extract_zip`)
**目的**：从 GitHub codeload 下载仓库 ZIP 并安全解压。

**技术实现**：
- 构建 codeload URL: `https://codeload.github.com/{owner}/{repo}/zip/{ref}`
- 使用 `github_request` 下载 ZIP 内容
- 使用 `zipfile.ZipFile` 解压
- **安全校验**：`_safe_extract_zip` 检查所有文件路径是否在目标目录内，防止 Zip Slip 攻击
- 返回解压后的顶层目录名（通常为 `{repo}-{ref}`）

**关键代码路径**：
```python
def _safe_extract_zip(zip_file: zipfile.ZipFile, dest_dir: str) -> None:
    dest_root = os.path.realpath(dest_dir)
    for info in zip_file.infolist():
        extracted_path = os.path.realpath(os.path.join(dest_dir, info.filename))
        if extracted_path == dest_root or extracted_path.startswith(dest_root + os.sep):
            continue
        raise InstallError("Archive contains files outside the destination.")
    zip_file.extractall(dest_dir)
```

### 3. Git 稀疏检出 (`_git_sparse_checkout`)
**目的**：当下载失败或指定 git 方法时，使用 Git 稀疏检出仅克隆指定路径。

**技术实现**：
- 使用 `git clone --filter=blob:none --depth 1 --sparse --single-branch --branch {ref}`
- `--filter=blob:none`：跳过 blob 对象，减少下载量
- `--sparse`：启用稀疏检出模式
- 执行 `git sparse-checkout set {paths}` 指定需要检出的路径
- 如指定 ref 失败，回退到默认分支克隆
- 如 HTTPS 失败，自动尝试 SSH 格式

**关键代码路径**：
```python
clone_cmd = [
    "git", "clone",
    "--filter=blob:none", "--depth", "1", "--sparse", "--single-branch",
    "--branch", ref, repo_url, repo_dir,
]
_run_git(clone_cmd)
_run_git(["git", "-C", repo_dir, "sparse-checkout", "set", *paths])
_run_git(["git", "-C", repo_dir, "checkout", ref])
```

### 4. Skill 验证与安装 (`_validate_skill`, `_copy_skill`)
**目的**：验证 skill 目录结构正确性并复制到目标位置。

**技术实现**：
- `_validate_skill`：检查路径是否为目录，且包含 `SKILL.md` 文件
- `_validate_skill_name`：验证名称不包含路径分隔符，不为 `.` 或 `..`
- `_copy_skill`：使用 `shutil.copytree` 复制整个 skill 目录
- 如目标已存在，抛出 `InstallError`

**关键代码路径**：
```python
def _validate_skill(path: str) -> None:
    if not os.path.isdir(path):
        raise InstallError(f"Skill path not found: {path}")
    skill_md = os.path.join(path, "SKILL.md")
    if not os.path.isfile(skill_md):
        raise InstallError("SKILL.md not found in selected skill directory.")
```

### 5. 安装策略选择 (`_prepare_repo`)
**目的**：根据方法和网络条件选择最佳安装策略。

**技术实现**：
- `method="auto"`：先尝试下载，如遇到 401/403/404 则回退到 git
- `method="download"`：仅使用下载方式，失败则报错
- `method="git"`：直接使用 git 稀疏检出
- 下载失败时自动捕获 HTTPError，检查状态码决定是否回退

**关键代码路径**：
```python
def _prepare_repo(source: Source, method: str, tmp_dir: str) -> str:
    if method in ("download", "auto"):
        try:
            return _download_repo_zip(source.owner, source.repo, source.ref, tmp_dir)
        except InstallError as exc:
            if method == "download":
                raise
            err_msg = str(exc)
            if "HTTP 401" in err_msg or "HTTP 403" in err_msg or "HTTP 404" in err_msg:
                pass  # fallback to git
            else:
                raise
    if method in ("git", "auto"):
        # git sparse checkout logic
```

## 具体技术实现

### 数据结构

```python
@dataclass
class Args:
    url: str | None = None          # 完整 GitHub URL
    repo: str | None = None         # owner/repo 格式
    path: list[str] | None = None   # 仓库内 skill 路径列表
    ref: str = DEFAULT_REF          # 分支/标签，默认 "main"
    dest: str | None = None         # 目标目录，默认 $CODEX_HOME/skills
    name: str | None = None         # 指定 skill 名称（单路径时有效）
    method: str = "auto"            # 安装方式: auto/download/git

@dataclass
class Source:
    owner: str                      # 仓库所有者
    repo: str                       # 仓库名
    ref: str                        # 分支/标签
    paths: list[str]                # skill 路径列表
    repo_url: str | None = None     # 可选的自定义仓库 URL
```

### 关键流程

```
main()
├── _parse_args() → Args
├── _resolve_source() → Source
│   ├── _parse_github_url() → (owner, repo, ref, subpath)
│   └── 验证参数组合
├── _prepare_repo() → repo_root
│   ├── _download_repo_zip() [优先]
│   │   ├── github_request() → ZIP bytes
│   │   ├── zipfile.ZipFile.extractall()
│   │   └── _safe_extract_zip() [安全检查]
│   └── _git_sparse_checkout() [回退]
│       ├── git clone --sparse
│       └── git sparse-checkout set
├── 遍历 paths:
│   ├── _validate_relative_path()
│   ├── _validate_skill_name()
│   ├── _validate_skill() [检查 SKILL.md]
│   └── _copy_skill()
└── 清理临时目录
```

### 协议与命令

| 协议/命令 | 用途 |
|-----------|------|
| HTTPS + GitHub codeload | 下载 ZIP 归档 |
| Git + sparse-checkout | 克隆指定路径 |
| GitHub API (via github_utils) | 认证下载 |

## 关键代码路径与文件引用

### 内部调用关系

| 函数 | 调用者 | 被调用者 |
|------|--------|----------|
| `main` | - | `_parse_args`, `_resolve_source`, `_prepare_repo`, `_validate_skill`, `_copy_skill` |
| `_resolve_source` | `main` | `_parse_github_url` |
| `_prepare_repo` | `main` | `_download_repo_zip`, `_git_sparse_checkout` |
| `_download_repo_zip` | `_prepare_repo` | `github_request`, `_safe_extract_zip` |
| `_git_sparse_checkout` | `_prepare_repo` | `_run_git` |
| `_request` | `_download_repo_zip` | `github_request` (from github_utils.py) |

### 外部文件引用

| 引用 | 用途 |
|------|------|
| `github_utils.py` | `github_request` 函数 |
| `$CODEX_HOME` 环境变量 | 确定默认 skill 安装目录 |
| `SKILL.md` | 验证 skill 目录有效性 |
| `git` 命令 | 稀疏检出操作 |

## 依赖与外部交互

### Python 标准库依赖
- `argparse`：命令行参数解析
- `dataclasses`：数据结构定义
- `os`, `shutil`, `tempfile`：文件系统操作
- `subprocess`：执行 git 命令
- `urllib.parse`, `urllib.error`：URL 解析和错误处理
- `zipfile`：ZIP 归档处理

### 外部系统依赖
| 依赖 | 用途 |
|------|------|
| GitHub codeload | ZIP 下载 |
| GitHub API | 认证请求（通过 github_utils） |
| Git 客户端 | 稀疏检出 |
| `$CODEX_HOME` 环境变量 | 默认安装路径 |

### 网络要求
- 访问 `github.com`（codeload 和 API）
- 如使用 git 方法，需要 Git 协议访问（HTTPS/SSH）

## 风险、边界与改进建议

### 风险

1. **Zip Slip 漏洞**：已防护，`_safe_extract_zip` 检查路径前缀
2. **临时目录未清理**：使用 `try...finally` 确保清理，但 `ignore_errors=True` 可能隐藏问题
3. **Git 命令注入**：`paths` 参数直接拼接到命令行，如包含特殊字符可能引发问题
4. **无并发控制**：同时安装同名 skill 可能导致竞态条件
5. **SSH 密钥依赖**：私有仓库回退到 SSH 时依赖用户已配置 SSH 密钥

### 边界条件

| 场景 | 行为 |
|------|------|
| 目标目录已存在 | 抛出 `InstallError`，拒绝覆盖 |
| 多 path 安装 | 每个 path 作为独立 skill，名称取自 basename |
| `--name` + 多 path | `--name` 被忽略，使用 basename |
| 无效 GitHub URL | 抛出 `InstallError` |
| 下载 404 + auto 模式 | 自动回退到 git 模式 |
| 下载非 401/403/404 错误 | 直接抛出，不回退 |
| 缺少 `SKILL.md` | 抛出 `InstallError` |

### 改进建议

1. **添加进度显示**：
   - 下载大仓库时显示进度条
   - Git 操作显示克隆进度

2. **增强错误信息**：
   - 区分网络错误、权限错误、仓库不存在
   - 提供具体的解决建议

3. **支持并发安装**：
   - 使用文件锁防止并发冲突
   - 或支持原子性安装（先安装到临时目录再重命名）

4. **Git 参数转义**：
   ```python
   import shlex
   _run_git(["git", "sparse-checkout", "set"] + [shlex.quote(p) for p in paths])
   ```

5. **支持部分失败**：
   - 多 path 安装时，记录成功和失败的 skill
   - 最后汇总报告

6. **缓存机制**：
   - 缓存下载的 ZIP 文件，避免重复下载相同 ref
   - 使用 ETag 或 SHA 验证缓存有效性

7. **添加 `--force` 选项**：
   - 允许覆盖已存在的 skill（用于更新）

8. **验证 skill 结构**：
   - 除 `SKILL.md` 外，验证 `agents/openai.yaml` 等必要文件
