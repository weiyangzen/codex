# skill-installer 深度研究文档

## 目录
- [场景与职责](#场景与职责)
- [功能点目的](#功能点目的)
- [具体技术实现](#具体技术实现)
- [关键代码路径与文件引用](#关键代码路径与文件引用)
- [依赖与外部交互](#依赖与外部交互)
- [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 1.1 定位与上下文

`skill-installer` 是 Codex 的**系统级技能（System Skill）**，位于 `codex-rs/skills/src/assets/samples/skill-installer/`。它是 Codex 内置的三个系统技能之一（另外两个是 `skill-creator` 和 `openai-docs`），随 Codex 二进制文件一起分发，在启动时自动安装到 `$CODEX_HOME/skills/.system/` 目录。

### 1.2 核心职责

该技能的主要职责是**帮助用户从 GitHub 仓库安装和管理 Codex 技能**：

1. **列出可安装技能**：从 `openai/skills` 仓库的 `skills/.curated` 或 `skills/.experimental` 目录获取技能列表
2. **安装精选技能**：从官方 curated 列表安装技能
3. **安装第三方技能**：支持从任意 GitHub 仓库（包括私有仓库）安装技能
4. **管理安装状态**：检测本地已安装的技能，避免重复安装

### 1.3 使用场景

| 场景 | 触发条件 | 用户输入示例 |
|------|----------|--------------|
| 列出技能 | 用户询问可用技能 | "What skills can I install?" |
| 安装精选技能 | 用户提供技能名称 | "Install the pdf-editor skill" |
| 安装实验技能 | 用户指定 experimental 路径 | "Install experimental skills" |
| 安装第三方技能 | 用户提供 GitHub 路径 | "Install skill from github.com/user/repo" |

---

## 功能点目的

### 2.1 功能模块划分

```
skill-installer/
├── SKILL.md                    # 技能定义和使用说明
├── agents/openai.yaml          # UI 元数据（图标、描述）
├── assets/                     # 图标资源
│   ├── skill-installer-small.svg
│   └── skill-installer.png
├── scripts/                    # 核心功能脚本
│   ├── github_utils.py         # GitHub API 工具函数
│   ├── list-skills.py          # 列出可安装技能
│   └── install-skill-from-github.py  # 安装技能
└── LICENSE.txt                 # Apache 2.0 许可证
```

### 2.2 各功能点详细说明

#### 2.2.1 技能列表功能 (`list-skills.py`)

**目的**：让用户发现可用的技能

**关键特性**：
- 默认从 `openai/skills` 仓库的 `skills/.curated` 目录获取
- 支持 `--path` 参数指定其他目录（如 `skills/.experimental`）
- 支持 `--format json` 输出 JSON 格式（供程序解析）
- 自动检测本地已安装技能并标注 `(already installed)`

**实现机制**：
- 使用 GitHub Contents API: `GET /repos/{repo}/contents/{path}?ref={ref}`
- 本地扫描 `$CODEX_HOME/skills/` 目录对比已安装状态
- 支持 `GITHUB_TOKEN`/`GH_TOKEN` 环境变量进行认证

#### 2.2.2 技能安装功能 (`install-skill-from-github.py`)

**目的**：将远程技能下载并安装到本地

**关键特性**：
- 支持两种安装方式：
  - **Direct Download**（默认）：直接下载 ZIP 归档，速度快
  - **Git Sparse Checkout**（回退）：用于私有仓库或下载失败时
- 支持多种输入格式：
  - `--repo owner/repo --path path/to/skill`
  - `--url https://github.com/owner/repo/tree/ref/path`
- 支持批量安装（多个 `--path`）
- 自动验证技能完整性（检查 `SKILL.md` 存在）

**安装流程**：
1. 解析输入参数（repo/url/path/ref）
2. 验证路径安全性（防止目录遍历攻击）
3. 准备仓库（下载 ZIP 或 git sparse checkout）
4. 验证技能结构（必须包含 `SKILL.md`）
5. 复制到目标目录（`$CODEX_HOME/skills/{skill-name}`）
6. 清理临时文件

---

## 具体技术实现

### 3.1 关键数据结构

#### 3.1.1 Python 脚本中的核心类

```python
# install-skill-from-github.py
@dataclass
class Args:
    url: str | None = None          # GitHub URL 输入
    repo: str | None = None         # owner/repo 格式
    path: list[str] | None = None   # 技能在仓库中的路径
    ref: str = DEFAULT_REF          # Git 分支/标签（默认 main）
    dest: str | None = None         # 目标目录覆盖
    name: str | None = None         # 技能名称覆盖
    method: str = "auto"            # 安装方法: auto|download|git

@dataclass
class Source:
    owner: str
    repo: str
    ref: str
    paths: list[str]
    repo_url: str | None = None
```

#### 3.1.2 错误处理

```python
class InstallError(Exception):
    """安装过程中的业务错误"""
    pass

class ListError(Exception):
    """列表获取过程中的业务错误"""
    pass
```

### 3.2 关键流程详解

#### 3.2.1 GitHub URL 解析流程

```python
def _parse_github_url(url: str, default_ref: str) -> tuple[str, str, str, str | None]:
    """
    解析 GitHub URL 格式：
    - https://github.com/owner/repo
    - https://github.com/owner/repo/tree/ref/path
    - https://github.com/owner/repo/blob/ref/path
    """
    parsed = urllib.parse.urlparse(url)
    if parsed.netloc != "github.com":
        raise InstallError("Only GitHub URLs are supported for download mode.")
    
    parts = [p for p in parsed.path.split("/") if p]
    owner, repo = parts[0], parts[1]
    
    # 处理 /tree/ 或 /blob/ 路径格式
    if len(parts) > 2:
        if parts[2] in ("tree", "blob"):
            ref = parts[3]
            subpath = "/".join(parts[4:])
        else:
            subpath = "/".join(parts[2:])
```

#### 3.2.2 双模式下载策略

```python
def _prepare_repo(source: Source, method: str, tmp_dir: str) -> str:
    """
    准备仓库内容，支持两种模式：
    
    1. Download 模式（优先）：
       - 下载 https://codeload.github.com/{owner}/{repo}/zip/{ref}
       - 解压 ZIP 到临时目录
       - 返回解压后的根目录
    
    2. Git Sparse Checkout 模式（回退）：
       - 用于私有仓库或下载失败时
       - git clone --filter=blob:none --sparse --depth 1
       - git sparse-checkout set {paths}
       - 支持 HTTPS -> SSH 回退
    """
    if method in ("download", "auto"):
        try:
            return _download_repo_zip(source.owner, source.repo, source.ref, tmp_dir)
        except InstallError as exc:
            # 401/403/404 错误时尝试 git 模式
            if method == "download":
                raise
            err_msg = str(exc)
            if "HTTP 401" in err_msg or "HTTP 403" in err_msg or "HTTP 404" in err_msg:
                pass  # 继续尝试 git 模式
            else:
                raise
    
    if method in ("git", "auto"):
        # 先尝试 HTTPS
        try:
            return _git_sparse_checkout(repo_url, source.ref, source.paths, tmp_dir)
        except InstallError:
            # 回退到 SSH
            repo_url = _build_repo_ssh(source.owner, source.repo)
            return _git_sparse_checkout(repo_url, source.ref, source.paths, tmp_dir)
```

#### 3.2.3 安全验证机制

```python
def _validate_relative_path(path: str) -> None:
    """防止目录遍历攻击"""
    if os.path.isabs(path) or os.path.normpath(path).startswith(".."):
        raise InstallError("Skill path must be a relative path inside the repo.")

def _validate_skill_name(name: str) -> None:
    """验证技能名称合法性"""
    if not name or os.path.sep in name or (altsep and altsep in name):
        raise InstallError("Skill name must be a single path segment.")
    if name in (".", ".."):
        raise InstallError("Invalid skill name.")

def _safe_extract_zip(zip_file: zipfile.ZipFile, dest_dir: str) -> None:
    """防止 ZIP 路径遍历攻击（Zip Slip）"""
    dest_root = os.path.realpath(dest_dir)
    for info in zip_file.infolist():
        extracted_path = os.path.realpath(os.path.join(dest_dir, info.filename))
        if not extracted_path.startswith(dest_root + os.sep):
            raise InstallError("Archive contains files outside the destination.")
```

### 3.3 系统技能集成机制

#### 3.3.1 编译时嵌入

```rust
// codex-rs/skills/src/lib.rs
const SYSTEM_SKILLS_DIR: Dir = include_dir::include_dir!("$CARGO_MANIFEST_DIR/src/assets/samples");
```

使用 `include_dir` crate 将 `samples/` 目录下的所有技能（包括 skill-installer）在**编译时**嵌入到二进制文件中。

#### 3.3.2 运行时安装

```rust
// codex-rs/core/src/skills/manager.rs
impl SkillsManager {
    pub fn new(codex_home: PathBuf, plugins_manager: Arc<PluginsManager>, bundled_skills_enabled: bool) -> Self {
        if !bundled_skills_enabled {
            // 禁用捆绑技能时，卸载系统技能
            uninstall_system_skills(&manager.codex_home);
        } else if let Err(err) = install_system_skills(&manager.codex_home) {
            tracing::error!("failed to install system skills: {err}");
        }
        manager
    }
}
```

#### 3.3.3 指纹缓存机制

```rust
// codex-rs/skills/src/lib.rs
pub fn install_system_skills(codex_home: &Path) -> Result<(), SystemSkillsError> {
    let expected_fingerprint = embedded_system_skills_fingerprint();
    
    // 检查 marker 文件，如果指纹匹配则跳过安装
    if read_marker(&marker_path).is_ok_and(|marker| marker == expected_fingerprint) {
        return Ok(());  // 已是最新版本，跳过
    }
    
    // 清除旧版本并重新安装
    if dest_system.as_path().exists() {
        fs::remove_dir_all(dest_system.as_path())?;
    }
    write_embedded_dir(&SYSTEM_SKILLS_DIR, &dest_system)?;
    fs::write(marker_path, format!("{expected_fingerprint}\n"))?;
    Ok(())
}
```

指纹计算包含：
- 盐值：`"v1"`
- 所有文件路径和内容的哈希

---

## 关键代码路径与文件引用

### 4.1 本目录文件

| 文件 | 行数 | 职责 |
|------|------|------|
| `SKILL.md` | 58 | 技能定义、使用说明、触发条件 |
| `agents/openai.yaml` | 5 | UI 元数据（显示名称、图标路径） |
| `scripts/github_utils.py` | 21 | GitHub API 请求封装、认证处理 |
| `scripts/list-skills.py` | 107 | 列出可安装技能、检测已安装状态 |
| `scripts/install-skill-from-github.py` | 308 | 技能安装核心逻辑 |
| `LICENSE.txt` | 202 | Apache 2.0 许可证 |

### 4.2 调用方代码路径

| 文件 | 关键函数/行 | 调用关系 |
|------|-------------|----------|
| `codex-rs/skills/src/lib.rs` | `install_system_skills()` (L47) | 系统技能安装入口 |
| `codex-rs/skills/build.rs` | `visit_dir()` (L14) | 编译时监控文件变化 |
| `codex-rs/core/src/skills/manager.rs` | `SkillsManager::new()` (L38) | 初始化时调用安装 |
| `codex-rs/core/src/skills/system.rs` | `uninstall_system_skills()` (L6) | 卸载系统技能 |

### 4.3 被调用方/依赖代码路径

| 文件 | 关键功能 | 说明 |
|------|----------|------|
| `codex-rs/core/src/skills/loader.rs` | 技能加载、解析 | 扫描 `.system` 目录 |
| `codex-rs/skills/Cargo.toml` | 依赖声明 | `include_dir`, `codex-utils-absolute-path` |
| `codex-rs/skills/BUILD.bazel` | Bazel 构建配置 | `compile_data` 包含所有资源文件 |

### 4.4 配置与数据流

```
编译时:
  codex-rs/skills/src/assets/samples/skill-installer/
    └── [嵌入] → include_dir!() → 二进制文件

运行时安装:
  二进制文件
    └── [解压] → $CODEX_HOME/skills/.system/skill-installer/

运行时调用:
  用户请求 → Codex Agent → 解析意图 → 执行 scripts/
    ├── list-skills.py → GitHub API → 技能列表
    └── install-skill-from-github.py → 下载/安装 → $CODEX_HOME/skills/
```

---

## 依赖与外部交互

### 5.1 Python 脚本依赖

| 依赖 | 用途 | 标准库/第三方 |
|------|------|---------------|
| `argparse` | 命令行参数解析 | 标准库 |
| `dataclasses` | 数据结构定义 | 标准库 (Python 3.7+) |
| `json` | JSON 解析 | 标准库 |
| `os` | 环境变量、路径操作 | 标准库 |
| `shutil` | 文件复制、目录删除 | 标准库 |
| `subprocess` | Git 命令调用 | 标准库 |
| `tempfile` | 临时目录创建 | 标准库 |
| `urllib.request` | HTTP 请求 | 标准库 |
| `urllib.parse` | URL 解析 | 标准库 |
| `zipfile` | ZIP 解压 | 标准库 |

### 5.2 外部服务依赖

| 服务 | API 端点 | 用途 | 认证方式 |
|------|----------|------|----------|
| GitHub | `api.github.com/repos/{repo}/contents/{path}` | 获取目录内容 | `GITHUB_TOKEN`/`GH_TOKEN` |
| GitHub | `codeload.github.com/{owner}/{repo}/zip/{ref}` | 下载 ZIP 归档 | 同上（可选） |
| GitHub | `github.com/{owner}/{repo}.git` | Git clone | git credentials/SSH |

### 5.3 环境变量

| 变量 | 用途 | 默认值 |
|------|------|--------|
| `CODEX_HOME` | Codex 配置根目录 | `~/.codex` |
| `GITHUB_TOKEN` | GitHub API 认证（优先级高） | 无 |
| `GH_TOKEN` | GitHub API 认证（备选） | 无 |

### 5.4 Rust 依赖

```toml
# codex-rs/skills/Cargo.toml
[dependencies]
codex-utils-absolute-path = { workspace = true }  # 绝对路径处理
include_dir = { workspace = true }                # 编译时嵌入目录
thiserror = { workspace = true }                  # 错误处理
```

---

## 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 安全风险

| 风险 | 等级 | 描述 | 现有缓解措施 |
|------|------|------|--------------|
| ZIP Slip | 低 | 恶意 ZIP 包含 `../` 路径 | `_safe_extract_zip()` 验证 |
| 目录遍历 | 低 | `--path` 参数包含 `..` | `_validate_relative_path()` 验证 |
| 命令注入 | 低 | Git 命令参数注入 | 使用列表传参，非 shell 字符串 |
| Token 泄露 | 中 | 环境变量中的 GitHub Token | 仅用于 HTTPS 头，不记录日志 |

#### 6.1.2 功能风险

| 风险 | 描述 | 影响 |
|------|------|------|
| 网络依赖 | 所有脚本都需要网络访问 | 离线环境无法使用 |
| GitHub 限流 | 未认证 API 限制 60 req/hour | 频繁使用可能触发限流 |
| 私有仓库 | 需要正确配置 git credentials | 用户体验不一致 |
| 名称冲突 | 安装时目标目录已存在会失败 | 需要手动处理冲突 |

### 6.2 边界条件

#### 6.2.1 输入边界

```python
# 路径长度限制（来自 loader.rs）
MAX_NAME_LEN = 64                    # 技能名称最大长度
MAX_DESCRIPTION_LEN = 1024           # 描述最大长度
MAX_SCAN_DEPTH = 6                   # 技能扫描深度
MAX_SKILLS_DIRS_PER_ROOT = 2000      # 每根目录最大扫描目录数
```

#### 6.2.2 行为边界

1. **安装冲突**：目标目录已存在时**直接报错**，不会覆盖或合并
2. **部分失败**：批量安装时，任一失败则整体失败（事务性）
3. **网络超时**：使用 `urllib` 默认超时，无自定义超时配置
4. **Git 回退**：仅对 401/403/404 错误尝试 git 模式

### 6.3 改进建议

#### 6.3.1 高优先级

1. **添加重试机制**
   ```python
   # 建议：对网络请求添加指数退避重试
   @retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=4, max=10))
   def _request(url: str) -> bytes:
       ...
   ```

2. **支持离线模式**
   - 缓存技能列表到本地
   - 提供 `--offline` 参数使用缓存

3. **改进错误信息**
   - 区分网络错误、权限错误、格式错误
   - 提供具体的解决建议（如 "请设置 GITHUB_TOKEN"）

#### 6.3.2 中优先级

4. **支持更新已安装技能**
   - 添加 `--force` 或 `--update` 参数
   - 比较远程和本地版本（如通过 git commit hash）

5. **支持依赖解析**
   - 技能元数据中添加 `dependencies` 字段
   - 自动安装依赖的技能

6. **添加进度显示**
   - 大仓库下载时显示进度条
   - 批量安装时显示当前进度

#### 6.3.3 低优先级

7. **支持其他 Git 托管平台**
   - GitLab、Bitbucket 等
   - 通过 `--provider` 参数指定

8. **添加校验和验证**
   - 下载后验证文件完整性
   - 支持 `sha256sum.txt` 或类似机制

9. **优化稀疏检出性能**
   - 对非常大的仓库，考虑使用 `git clone --filter=tree:0`

### 6.4 测试建议

当前目录下**无测试文件**，建议添加：

```
skill-installer/
└── tests/
    ├── test_github_utils.py      # 测试 URL 解析、API 请求
    ├── test_list_skills.py       # 测试列表功能（mock GitHub API）
    └── test_install_skill.py     # 测试安装流程（使用临时目录）
```

关键测试场景：
1. 各种 GitHub URL 格式的解析
2. ZIP 路径遍历攻击防护
3. 相对路径验证
4. 已存在目录的处理
5. 网络失败时的 git 回退

---

## 附录：关键代码片段

### A.1 完整的安装流程

```python
# install-skill-from-github.py:main() 的简化流程

def main(argv: list[str]) -> int:
    args = _parse_args(argv)
    
    # 1. 解析源信息
    source = _resolve_source(args)
    
    # 2. 验证路径
    for path in source.paths:
        _validate_relative_path(path)
    
    # 3. 准备临时目录
    tmp_dir = tempfile.mkdtemp(prefix="skill-install-", dir=_tmp_root())
    
    try:
        # 4. 获取仓库内容
        repo_root = _prepare_repo(source, args.method, tmp_dir)
        
        # 5. 安装每个技能
        for path in source.paths:
            skill_name = os.path.basename(path.rstrip("/"))
            dest_dir = os.path.join(dest_root, skill_name)
            
            # 验证并复制
            skill_src = os.path.join(repo_root, path)
            _validate_skill(skill_src)
            _copy_skill(skill_src, dest_dir)
            
    finally:
        # 6. 清理
        shutil.rmtree(tmp_dir, ignore_errors=True)
```

### A.2 GitHub API 请求封装

```python
# github_utils.py

def github_request(url: str, user_agent: str) -> bytes:
    headers = {"User-Agent": user_agent}
    
    # 优先使用 GITHUB_TOKEN，备选 GH_TOKEN
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if token:
        headers["Authorization"] = f"token {token}"
    
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req) as resp:
        return resp.read()
```

---

*文档生成时间：2026-03-22*
*基于代码版本：codex-rs/skills/src/assets/samples/skill-installer/*
