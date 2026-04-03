# skill-installer/scripts 深度研究文档

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

`skill-installer/scripts` 目录包含 skill-installer 技能的**核心可执行脚本**，负责实现从 GitHub 仓库发现、下载和安装 Codex 技能的完整功能链。这些脚本是 skill-installer 技能的"业务逻辑层"，由 Codex Agent 在解析用户意图后调用执行。

### 1.2 脚本职责划分

| 脚本 | 核心职责 | 使用场景 |
|------|----------|----------|
| `github_utils.py` | GitHub API 通信基础设施 | 被其他脚本导入使用 |
| `list-skills.py` | 发现可安装技能 | 用户询问"有哪些技能可用" |
| `install-skill-from-github.py` | 执行技能安装 | 用户请求安装特定技能 |

### 1.3 在 skill-installer 中的位置

```
skill-installer/
├── SKILL.md                    # 技能定义（触发条件、使用说明）
├── agents/openai.yaml          # UI 元数据
├── assets/                     # 图标资源
└── scripts/                    # 【本目录】核心功能脚本
    ├── github_utils.py         # 21 行 - GitHub API 工具
    ├── list-skills.py          # 107 行 - 技能列表
    └── install-skill-from-github.py  # 308 行 - 技能安装
```

### 1.4 执行上下文

这些脚本在以下环境中执行：
- **调用方**：Codex Agent（通过 shell 工具执行）
- **工作目录**：`$CODEX_HOME/skills/.system/skill-installer/scripts/`
- **目标目录**：`$CODEX_HOME/skills/`（用户技能安装位置）
- **临时目录**：`$TMPDIR/codex/skill-install-*/`（下载/解压中间文件）

---

## 功能点目的

### 2.1 github_utils.py - GitHub API 基础设施

**目的**：为其他脚本提供统一的 GitHub API 访问能力，处理认证、请求构造和错误传播。

**关键功能**：
1. **统一请求封装**：`github_request()` 函数统一处理所有 GitHub HTTP 请求
2. **Token 认证管理**：自动检测 `GITHUB_TOKEN` 或 `GH_TOKEN` 环境变量
3. **User-Agent 标识**：区分不同脚本的请求来源
4. **URL 构造助手**：`github_api_contents_url()` 生成标准 GitHub Contents API URL

### 2.2 list-skills.py - 技能发现

**目的**：让用户发现当前可安装的技能，支持官方 curated 列表和自定义仓库。

**关键功能**：
1. **默认 curated 列表**：从 `openai/skills/skills/.curated` 获取精选技能
2. **实验技能支持**：通过 `--path skills/.experimental` 查看实验性技能
3. **已安装检测**：扫描 `$CODEX_HOME/skills/` 目录，标注已安装技能
4. **双格式输出**：
   - `text` 格式：人类可读列表（带序号和安装状态）
   - `json` 格式：机器解析（`[{name, installed}, ...]`）

**输出示例**：
```
Skills from openai/skills:
1. pdf-editor
2. image-generator (already installed)
3. code-reviewer
Which ones would you like installed?
```

### 2.3 install-skill-from-github.py - 技能安装

**目的**：将远程 GitHub 仓库中的技能安全地下载并安装到本地。

**关键功能**：
1. **双模式下载策略**：
   - **Download 模式**（默认）：直接下载 ZIP，速度快、无需 git
   - **Git 模式**（回退）：使用 sparse checkout，支持私有仓库
2. **灵活输入格式**：
   - `--repo owner/repo --path path/to/skill`
   - `--url https://github.com/owner/repo/tree/ref/path`
3. **批量安装**：支持多个 `--path` 参数一次性安装多个技能
4. **安全验证**：
   - 路径遍历防护（验证相对路径）
   - ZIP Slip 防护（验证解压路径）
   - 技能结构验证（必须包含 `SKILL.md`）
5. **防重复安装**：目标目录已存在时直接报错

---

## 具体技术实现

### 3.1 关键数据结构

#### 3.1.1 install-skill-from-github.py

```python
@dataclass
class Args:
    url: str | None = None          # GitHub URL 完整路径
    repo: str | None = None         # owner/repo 简写格式
    path: list[str] | None = None   # 技能在仓库内的路径（支持多路径）
    ref: str = "main"               # Git 分支/标签/Commit
    dest: str | None = None         # 覆盖默认目标目录
    name: str | None = None         # 覆盖技能名称（仅单路径时有效）
    method: str = "auto"            # 安装策略: auto|download|git

@dataclass
class Source:
    owner: str                      # 仓库所有者
    repo: str                       # 仓库名
    ref: str                        # Git 引用
    paths: list[str]                # 要安装的路径列表
    repo_url: str | None = None     # 可选的完整仓库 URL
```

#### 3.1.2 list-skills.py

```python
class Args(argparse.Namespace):
    repo: str = "openai/skills"     # 目标仓库
    path: str = "skills/.curated"   # 仓库内路径
    ref: str = "main"               # Git 引用
    format: str = "text"            # 输出格式: text|json
```

### 3.2 关键流程详解

#### 3.2.1 GitHub URL 解析流程（_parse_github_url）

```python
def _parse_github_url(url: str, default_ref: str) -> tuple[str, str, str, str | None]:
    """
    支持格式：
    - https://github.com/owner/repo
    - https://github.com/owner/repo/tree/ref/path/to/skill
    - https://github.com/owner/repo/blob/ref/path/to/skill
    - https://github.com/owner/repo/path/to/skill (无 tree/blob)
    """
    parsed = urllib.parse.urlparse(url)
    if parsed.netloc != "github.com":
        raise InstallError("Only GitHub URLs are supported for download mode.")
    
    parts = [p for p in parsed.path.split("/") if p]
    owner, repo = parts[0], parts[1]
    
    # 处理 /tree/ 或 /blob/ 路径格式
    if len(parts) > 2:
        if parts[2] in ("tree", "blob"):
            ref = parts[3]              # 提取分支/标签
            subpath = "/".join(parts[4:])  # 提取子路径
        else:
            subpath = "/".join(parts[2:])  # 无 tree/blob 前缀
```

#### 3.2.2 双模式仓库准备流程（_prepare_repo）

```python
def _prepare_repo(source: Source, method: str, tmp_dir: str) -> str:
    """
    策略优先级：
    1. 如果 method=download: 强制使用 ZIP 下载
    2. 如果 method=git: 强制使用 git sparse checkout
    3. 如果 method=auto（默认）:
       - 先尝试 ZIP 下载（速度快）
       - 遇到 401/403/404 错误时回退到 git 模式
       - git 模式先尝试 HTTPS，失败再尝试 SSH
    """
    if method in ("download", "auto"):
        try:
            return _download_repo_zip(source.owner, source.repo, source.ref, tmp_dir)
        except InstallError as exc:
            # 仅对认证/权限/不存在错误尝试回退
            if "HTTP 401" in str(exc) or "HTTP 403" in str(exc) or "HTTP 404" in str(exc):
                if method == "auto":
                    pass  # 继续尝试 git 模式
                else:
                    raise
            else:
                raise
    
    if method in ("git", "auto"):
        try:
            repo_url = _build_repo_url(source.owner, source.repo)  # HTTPS
            return _git_sparse_checkout(repo_url, source.ref, source.paths, tmp_dir)
        except InstallError:
            repo_url = _build_repo_ssh(source.owner, source.repo)  # SSH 回退
            return _git_sparse_checkout(repo_url, source.ref, source.paths, tmp_dir)
```

#### 3.2.3 ZIP 下载与解压流程

```python
def _download_repo_zip(owner: str, repo: str, ref: str, dest_dir: str) -> str:
    """
    1. 构造 ZIP URL: https://codeload.github.com/{owner}/{repo}/zip/{ref}
    2. 下载到临时文件 repo.zip
    3. 安全解压（防 Zip Slip）
    4. 返回解压后的根目录名（如 "repo-main"）
    """
    zip_url = f"https://codeload.github.com/{owner}/{repo}/zip/{ref}"
    zip_path = os.path.join(dest_dir, "repo.zip")
    
    payload = _request(zip_url)
    with open(zip_path, "wb") as f:
        f.write(payload)
    
    with zipfile.ZipFile(zip_path, "r") as zf:
        _safe_extract_zip(zf, dest_dir)  # 安全解压
        top_levels = {name.split("/")[0] for name in zf.namelist() if name}
    
    return os.path.join(dest_dir, next(iter(top_levels)))
```

#### 3.2.4 Git Sparse Checkout 流程

```python
def _git_sparse_checkout(repo_url: str, ref: str, paths: list[str], dest_dir: str) -> str:
    """
    使用 git sparse checkout 仅下载需要的文件：
    
    1. git clone --filter=blob:none --depth 1 --sparse --single-branch --branch {ref} {url} {dest}
       - --filter=blob:none: 不下载文件内容（仅目录结构）
       - --depth 1: 仅最新提交
       - --sparse: 启用稀疏检出
    
    2. git sparse-checkout set {paths}
       - 仅检出指定路径
    
    3. git checkout {ref}
       - 切换到指定引用
    """
    repo_dir = os.path.join(dest_dir, "repo")
    clone_cmd = [
        "git", "clone",
        "--filter=blob:none",      # 部分克隆，不下载 blob
        "--depth", "1",             # 浅克隆
        "--sparse",                 # 启用稀疏检出
        "--single-branch",
        "--branch", ref,
        repo_url,
        repo_dir
    ]
    _run_git(clone_cmd)
    _run_git(["git", "-C", repo_dir, "sparse-checkout", "set", *paths])
    _run_git(["git", "-C", repo_dir, "checkout", ref])
    return repo_dir
```

### 3.3 安全防护机制

#### 3.3.1 ZIP Slip 防护（_safe_extract_zip）

```python
def _safe_extract_zip(zip_file: zipfile.ZipFile, dest_dir: str) -> None:
    """
    防止 Zip Slip 攻击：验证所有解压路径都在目标目录内
    """
    dest_root = os.path.realpath(dest_dir)
    for info in zip_file.infolist():
        extracted_path = os.path.realpath(os.path.join(dest_dir, info.filename))
        # 验证路径前缀，防止 ../ 跳出目标目录
        if extracted_path == dest_root or extracted_path.startswith(dest_root + os.sep):
            continue
        raise InstallError("Archive contains files outside the destination.")
    zip_file.extractall(dest_dir)
```

#### 3.3.2 路径遍历防护（_validate_relative_path）

```python
def _validate_relative_path(path: str) -> None:
    """
    防止目录遍历攻击：拒绝绝对路径和包含 .. 的相对路径
    """
    if os.path.isabs(path) or os.path.normpath(path).startswith(".."):
        raise InstallError("Skill path must be a relative path inside the repo.")
```

#### 3.3.3 技能名称验证（_validate_skill_name）

```python
def _validate_skill_name(name: str) -> None:
    """
    确保技能名称是合法的单个路径段
    """
    altsep = os.path.altsep  # Windows 上的 '/'
    if not name or os.path.sep in name or (altsep and altsep in name):
        raise InstallError("Skill name must be a single path segment.")
    if name in (".", ".."):
        raise InstallError("Invalid skill name.")
```

### 3.4 技能验证流程

```python
def _validate_skill(path: str) -> None:
    """
    验证技能目录结构完整性：
    1. 路径必须是目录
    2. 必须包含 SKILL.md 文件（技能定义文件）
    """
    if not os.path.isdir(path):
        raise InstallError(f"Skill path not found: {path}")
    skill_md = os.path.join(path, "SKILL.md")
    if not os.path.isfile(skill_md):
        raise InstallError("SKILL.md not found in selected skill directory.")
```

---

## 关键代码路径与文件引用

### 4.1 本目录文件结构

| 文件 | 行数 | 核心函数/类 | 职责 |
|------|------|-------------|------|
| `github_utils.py` | 21 | `github_request()`, `github_api_contents_url()` | GitHub API 通信基础设施 |
| `list-skills.py` | 107 | `main()`, `_list_skills()`, `_installed_skills()` | 技能发现与列表展示 |
| `install-skill-from-github.py` | 308 | `main()`, `_prepare_repo()`, `_resolve_source()` | 技能下载与安装 |

### 4.2 函数调用关系

```
list-skills.py
    ├── github_utils.github_request()  # 获取目录内容
    ├── _installed_skills()            # 扫描本地已安装
    └── 输出格式化（text/json）

install-skill-from-github.py
    ├── _parse_args()                  # 参数解析
    ├── _resolve_source()              # 解析 repo/url/path
    │   └── _parse_github_url()        # URL 解析
    ├── _prepare_repo()                # 获取仓库内容
    │   ├── _download_repo_zip()       # ZIP 下载模式
    │   │   ├── github_utils.github_request()
    │   │   └── _safe_extract_zip()    # 安全解压
    │   └── _git_sparse_checkout()     # Git 模式
    │       └── _run_git()             # 执行 git 命令
    ├── _validate_skill()              # 验证技能结构
    └── _copy_skill()                  # 复制到目标目录
```

### 4.3 调用方（上游）

| 调用方 | 调用方式 | 说明 |
|--------|----------|------|
| Codex Agent | `python scripts/list-skills.py` | 用户询问可用技能时 |
| Codex Agent | `python scripts/install-skill-from-github.py --repo ... --path ...` | 用户请求安装技能时 |
| SKILL.md | 文档引用 | 指导 Agent 如何调用脚本 |

### 4.4 被调用方/依赖（下游）

| 依赖 | 类型 | 用途 |
|------|------|------|
| `github_utils.py` | 内部模块 | 被 `list-skills.py` 和 `install-skill-from-github.py` 导入 |
| GitHub API | 外部服务 | `api.github.com`, `codeload.github.com` |
| Git 命令 | 外部工具 | `git clone`, `git sparse-checkout` |
| `$CODEX_HOME/skills/` | 文件系统 | 读取已安装技能、写入新技能 |

---

## 依赖与外部交互

### 5.1 Python 标准库依赖

| 模块 | 用途 | 脚本 |
|------|------|------|
| `argparse` | 命令行参数解析 | all |
| `dataclasses` | 数据结构定义 | install-skill-from-github.py |
| `json` | JSON 解析/生成 | list-skills.py |
| `os` | 环境变量、路径操作 | all |
| `shutil` | 文件复制、目录删除 | install-skill-from-github.py |
| `subprocess` | Git 命令调用 | install-skill-from-github.py |
| `tempfile` | 临时目录创建 | install-skill-from-github.py |
| `urllib.request` | HTTP 请求 | github_utils.py |
| `urllib.parse` | URL 解析 | install-skill-from-github.py |
| `urllib.error` | HTTP 错误处理 | all |
| `zipfile` | ZIP 解压 | install-skill-from-github.py |
| `sys` | 退出码、错误输出 | all |

### 5.2 外部服务依赖

| 服务 | 端点 | 用途 | 认证 |
|------|------|------|------|
| GitHub Contents API | `api.github.com/repos/{repo}/contents/{path}` | 获取目录内容列表 | `GITHUB_TOKEN`/`GH_TOKEN` |
| GitHub CodeLoad | `codeload.github.com/{owner}/{repo}/zip/{ref}` | 下载 ZIP 归档 | 同上（可选） |
| GitHub Git | `github.com/{owner}/{repo}.git` | Git clone (HTTPS) | git credentials |
| GitHub Git (SSH) | `git@github.com:{owner}/{repo}.git` | Git clone (SSH) | SSH key |

### 5.3 环境变量

| 变量 | 用途 | 默认值 | 脚本 |
|------|------|--------|------|
| `CODEX_HOME` | Codex 配置根目录 | `~/.codex` | all |
| `GITHUB_TOKEN` | GitHub API 认证（优先） | 无 | github_utils.py |
| `GH_TOKEN` | GitHub API 认证（备选） | 无 | github_utils.py |
| `TMPDIR`/`TEMP` | 临时目录 | 系统默认 | install-skill-from-github.py |

### 5.4 文件系统交互

| 路径 | 类型 | 权限 | 说明 |
|------|------|------|------|
| `$CODEX_HOME/skills/` | 目录 | 读/写 | 用户技能安装根目录 |
| `$CODEX_HOME/skills/.system/` | 目录 | 读 | 系统技能目录（只读） |
| `$TMPDIR/codex/` | 目录 | 读/写 | 临时下载/解压目录 |
| `scripts/` | 目录 | 读 | 脚本自身所在目录 |

---

## 风险、边界与改进建议

### 6.1 安全风险

| 风险 | 等级 | 描述 | 现有缓解 | 改进建议 |
|------|------|------|----------|----------|
| ZIP Slip | 低 | 恶意 ZIP 包含 `../` 路径 | `_safe_extract_zip()` 验证路径前缀 | 已充分防护 |
| 目录遍历 | 低 | `--path` 参数包含 `..` | `_validate_relative_path()` 拒绝绝对路径和 `..` 前缀 | 已充分防护 |
| 命令注入 | 低 | Git 命令参数注入 | 使用列表传参，非 shell 字符串 | 已充分防护 |
| Token 泄露 | 中 | 环境变量中的 GitHub Token | 仅用于 HTTPS Header，不记录日志 | 添加 `--dry-run` 模式便于调试 |
| 网络中间人 | 中 | HTTP 请求被拦截 | 使用 HTTPS | 考虑添加证书固定 |

### 6.2 功能风险

| 风险 | 描述 | 影响 | 缓解/建议 |
|------|------|------|-----------|
| 网络依赖 | 所有脚本都需要网络访问 | 离线环境无法使用 | 添加本地缓存机制 |
| GitHub 限流 | 未认证 API 限制 60 req/hour | 频繁使用触发 403 | 提示用户设置 GITHUB_TOKEN |
| 私有仓库访问 | 需要正确配置 git credentials | 用户体验不一致 | 改进错误提示，指导配置 |
| 名称冲突 | 目标目录已存在时失败 | 需要手动处理 | 添加 `--force` 或 `--update` 选项 |
| 部分失败 | 批量安装时任一失败整体失败 | 已安装的技能被回滚 | 支持 `--continue-on-error` |
| 磁盘空间 | 大仓库下载可能耗尽临时空间 | 安装失败 | 添加磁盘空间预检查 |

### 6.3 边界条件

#### 6.3.1 输入边界

```python
# URL 长度限制（实际受限于系统）
MAX_URL_LEN = 4096  # 常见浏览器/服务器限制

# GitHub 路径限制
MAX_GITHUB_PATH_DEPTH = 20  # 仓库内路径深度

# 批量安装限制
MAX_BATCH_PATHS = 100  # 单次 --path 参数数量（无硬性限制，但建议）
```

#### 6.3.2 行为边界

| 边界条件 | 当前行为 | 建议改进 |
|----------|----------|----------|
| 目标目录已存在 | 报错退出 | 添加 `--update` 支持增量更新 |
| 网络超时 | 使用 urllib 默认超时（无限制） | 添加 `--timeout` 参数 |
| 部分路径失败 | 整体失败 | 添加 `--continue-on-error` |
| 无效 Git 引用 | git 命令失败 | 提前验证引用存在性 |
| 空路径列表 | 报错 "No skill paths provided" | 明确错误信息 |

### 6.4 改进建议

#### 6.4.1 高优先级

1. **添加重试机制**
   ```python
   # 对网络请求添加指数退避重试
   import time
   from functools import wraps
   
   def retry_on_failure(max_attempts=3, delay=1.0):
       def decorator(func):
           @wraps(func)
           def wrapper(*args, **kwargs):
               for attempt in range(max_attempts):
                   try:
                       return func(*args, **kwargs)
                   except urllib.error.HTTPError as e:
                       if e.code in (502, 503, 504) and attempt < max_attempts - 1:
                           time.sleep(delay * (2 ** attempt))
                           continue
                       raise
               return func(*args, **kwargs)
           return wrapper
       return decorator
   ```

2. **支持技能更新**
   ```python
   # 添加 --update 参数
   parser.add_argument("--update", action="store_true", 
                       help="Update existing skill if already installed")
   
   # 实现：比较远程和本地版本（如通过 git commit hash）
   def _should_update(src: str, dest: str) -> bool:
       # 比较 .git/refs/heads/main 或 SKILL.md 修改时间
       pass
   ```

3. **改进错误信息**
   ```python
   # 区分错误类型，提供具体解决建议
   class InstallError(Exception):
       def __init__(self, message: str, suggestion: str = None):
           super().__init__(message)
           self.suggestion = suggestion
   
   # 使用示例
   raise InstallError(
       "GitHub API rate limit exceeded",
       suggestion="Set GITHUB_TOKEN environment variable to increase rate limit"
   )
   ```

#### 6.4.2 中优先级

4. **添加进度显示**
   ```python
   # 大仓库下载时显示进度
   def _download_with_progress(url: str, dest: str) -> None:
       import urllib.request
       from tqdm import tqdm  # 或标准库实现
       
       with urllib.request.urlopen(url) as response:
           total = int(response.headers.get('Content-Length', 0))
           with open(dest, 'wb') as f, tqdm(total=total, unit='B', unit_scale=True) as pbar:
               while True:
                   chunk = response.read(8192)
                   if not chunk:
                       break
                   f.write(chunk)
                   pbar.update(len(chunk))
   ```

5. **支持离线缓存**
   ```python
   # 缓存技能列表到本地
   CACHE_DIR = os.path.join(os.environ.get("CODEX_HOME", "~/.codex"), ".cache", "skills")
   
   def _get_cached_skills(repo: str, path: str, ref: str, max_age: int = 3600):
       cache_key = f"{repo.replace('/', '_')}_{path.replace('/', '_')}_{ref}.json"
       cache_path = os.path.join(CACHE_DIR, cache_key)
       
       if os.path.exists(cache_path):
           mtime = os.path.getmtime(cache_path)
           if time.time() - mtime < max_age:
               with open(cache_path) as f:
                   return json.load(f)
       
       # 获取新数据并缓存
       data = _fetch_skills(repo, path, ref)
       os.makedirs(CACHE_DIR, exist_ok=True)
       with open(cache_path, 'w') as f:
           json.dump(data, f)
       return data
   ```

6. **添加依赖解析**
   ```python
   # 在 SKILL.md 中添加 dependencies 字段
   # 安装时自动解析并安装依赖
   def _install_dependencies(skill_path: str):
       skill_md = os.path.join(skill_path, "SKILL.md")
       # 解析 YAML 中的 dependencies 部分
       # 递归安装依赖技能
   ```

#### 6.4.3 低优先级

7. **支持其他 Git 托管平台**
   - GitLab: `https://gitlab.com/{owner}/{repo}/-/archive/{ref}/{repo}-{ref}.zip`
   - Bitbucket: `https://bitbucket.org/{owner}/{repo}/get/{ref}.zip`

8. **添加校验和验证**
   ```python
   # 支持 skill.sha256 文件验证完整性
   def _verify_checksum(skill_path: str) -> bool:
       checksum_file = os.path.join(skill_path, "..", f"{os.path.basename(skill_path)}.sha256")
       if os.path.exists(checksum_file):
           # 验证 SHA256
           pass
   ```

9. **优化稀疏检出性能**
   ```python
   # 对非常大的仓库，使用 treeless clone
   # git clone --filter=tree:0 --depth 1 --sparse ...
   ```

### 6.5 测试建议

当前目录**无测试文件**，建议添加：

```
scripts/
├── github_utils.py
├── list-skills.py
├── install-skill-from-github.py
└── tests/                          # 新增测试目录
    ├── __init__.py
    ├── test_github_utils.py        # 测试 URL 构造、Token 读取
    ├── test_list_skills.py         # 测试列表功能（mock GitHub API）
    ├── test_install_skill.py       # 测试安装流程（使用临时目录）
    └── fixtures/                   # 测试数据
        ├── mock_skill/
        │   └── SKILL.md
        └── mock_repo.zip
```

关键测试场景：
1. 各种 GitHub URL 格式的解析（tree/blob/无前缀）
2. ZIP 路径遍历攻击防护（包含 `../` 的恶意 ZIP）
3. 相对路径验证（绝对路径、`..` 前缀）
4. 已存在目录的处理
5. 网络失败时的 git 回退逻辑
6. Token 优先级（GITHUB_TOKEN > GH_TOKEN）

---

## 附录：关键代码片段

### A.1 完整的安装流程（简化）

```python
# install-skill-from-github.py:main()

def main(argv: list[str]) -> int:
    args = _parse_args(argv)
    
    try:
        # 1. 解析源信息
        source = _resolve_source(args)
        
        # 2. 验证路径安全性
        for path in source.paths:
            _validate_relative_path(path)
        
        # 3. 准备临时目录
        dest_root = args.dest or _default_dest()
        tmp_dir = tempfile.mkdtemp(prefix="skill-install-", dir=_tmp_root())
        
        try:
            # 4. 获取仓库内容（下载或 git）
            repo_root = _prepare_repo(source, args.method, tmp_dir)
            
            # 5. 安装每个技能
            installed = []
            for path in source.paths:
                skill_name = args.name if len(source.paths) == 1 else None
                skill_name = skill_name or os.path.basename(path.rstrip("/"))
                _validate_skill_name(skill_name)
                
                dest_dir = os.path.join(dest_root, skill_name)
                if os.path.exists(dest_dir):
                    raise InstallError(f"Destination already exists: {dest_dir}")
                
                skill_src = os.path.join(repo_root, path)
                _validate_skill(skill_src)
                _copy_skill(skill_src, dest_dir)
                installed.append((skill_name, dest_dir))
        
        finally:
            # 6. 清理临时文件
            shutil.rmtree(tmp_dir, ignore_errors=True)
        
        # 7. 输出结果
        for skill_name, dest_dir in installed:
            print(f"Installed {skill_name} to {dest_dir}")
        return 0
        
    except InstallError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1
```

### A.2 GitHub API 请求封装

```python
# github_utils.py

def github_request(url: str, user_agent: str) -> bytes:
    """
    统一的 GitHub HTTP 请求封装：
    - 自动添加 User-Agent
    - 自动添加认证头（如果环境变量中有 Token）
    - 返回原始字节响应
    """
    headers = {"User-Agent": user_agent}
    
    # 优先使用 GITHUB_TOKEN，备选 GH_TOKEN
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if token:
        headers["Authorization"] = f"token {token}"
    
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req) as resp:
        return resp.read()


def github_api_contents_url(repo: str, path: str, ref: str) -> str:
    """
    构造 GitHub Contents API URL
    示例: https://api.github.com/repos/openai/skills/contents/skills/.curated?ref=main
    """
    return f"https://api.github.com/repos/{repo}/contents/{path}?ref={ref}"
```

### A.3 已安装技能检测

```python
# list-skills.py

def _installed_skills() -> set[str]:
    """
    扫描 $CODEX_HOME/skills/ 目录，返回已安装技能名称集合
    排除 .system 目录（系统技能）
    """
    root = os.path.join(_codex_home(), "skills")
    if not os.path.isdir(root):
        return set()
    
    entries = set()
    for name in os.listdir(root):
        path = os.path.join(root, name)
        # 只统计目录，排除文件和隐藏目录
        if os.path.isdir(path) and not name.startswith("."):
            entries.add(name)
    return entries
```

---

*文档生成时间：2026-03-22*
*基于代码版本：*
- `codex-rs/skills/src/assets/samples/skill-installer/scripts/github_utils.py` (21 lines)
- `codex-rs/skills/src/assets/samples/skill-installer/scripts/list-skills.py` (107 lines)
- `codex-rs/skills/src/assets/samples/skill-installer/scripts/install-skill-from-github.py` (308 lines)
