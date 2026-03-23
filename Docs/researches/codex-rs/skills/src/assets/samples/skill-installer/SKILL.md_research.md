# SKILL.md 研究文档

## 场景与职责

此文件是 **skill-installer**（技能安装器）的核心定义文档，采用标准 Skill 格式编写。它定义了技能的元数据、功能描述、使用方法和配置选项，使 Codex 系统能够理解和调用该技能。

### 在系统中的定位

- **文件路径**: `codex-rs/skills/src/assets/samples/skill-installer/SKILL.md`
- **所属技能**: `skill-installer`
- **技能类型**: 系统预置技能（System Skill），预装在 `$CODEX_HOME/skills/.system/`
- **功能定位**: 帮助用户从 GitHub 仓库安装和管理 Codex 技能

### 核心职责

1. **技能发现**: 列出 openai/skills 仓库中可用的精选技能（.curated）和实验性技能（.experimental）
2. **技能安装**: 支持从 GitHub 仓库安装技能，包括：
   - 从精选列表安装（通过技能名称）
   - 从任意 GitHub 仓库安装（通过 repo/path）
   - 支持私有仓库（通过 GITHUB_TOKEN 认证）
3. **安装管理**: 检测已安装技能，避免重复安装

## 功能点目的

### 1. 技能元数据定义（YAML Frontmatter）

```yaml
---
name: skill-installer
description: Install Codex skills into $CODEX_HOME/skills from a curated list or a GitHub repo path...
metadata:
  short-description: Install curated skills from openai/skills or other repos
---
```

**目的**:
- 为 Codex 系统提供技能的机器可读描述
- `name`: 技能唯一标识符
- `description`: 详细功能描述，用于 LLM 理解何时使用该技能
- `metadata.short-description`: 简洁描述，用于 UI 展示

### 2. 技能使用指南

**目的**: 指导 LLM 在不同场景下如何正确使用该技能：

| 用户意图 | 推荐操作 | 对应脚本 |
|----------|----------|----------|
| 询问可用技能 | 列出 `.curated` 目录 | `list-skills.py` |
| 询问实验性技能 | 列出 `.experimental` 目录 | `list-skills.py --path skills/.experimental` |
| 提供技能名称 | 从精选列表安装 | `install-skill-from-github.py --repo openai/skills --path skills/.curated/<name>` |
| 提供 GitHub 路径 | 从指定仓库安装 | `install-skill-from-github.py --repo <owner>/<repo> --path <path>` |

### 3. 通信规范

定义了 LLM 与用户交互的标准话术：

**列表展示格式**:
```
Skills from {repo}:
1. skill-1
2. skill-2 (already installed)
3. ...
Which ones would you like installed?
```

**安装后提示**:
```
Restart Codex to pick up new skills.
```

**目的**: 确保用户体验的一致性，无论哪个 LLM 实例处理请求，输出格式都保持统一。

### 4. 脚本接口文档

详细说明了三个核心脚本的使用方法：

#### list-skills.py
```bash
# 基本用法
scripts/list-skills.py

# JSON 输出（供程序解析）
scripts/list-skills.py --format json

# 实验性技能列表
scripts/list-skills.py --path skills/.experimental
```

#### install-skill-from-github.py
```bash
# 从 repo + path 安装
scripts/install-skill-from-github.py --repo <owner>/<repo> --path <path/to/skill>

# 从 URL 安装
scripts/install-skill-from-github.py --url https://github.com/<owner>/<repo>/tree/<ref>/<path>

# 安装实验性技能
scripts/install-skill-from-github.py --repo openai/skills --path skills/.experimental/<skill-name>
```

### 5. 行为配置选项

| 选项 | 默认值 | 说明 |
|------|--------|------|
| 安装方法 | `auto` | 优先直接下载，失败时回退到 git sparse checkout |
| 目标目录 | `$CODEX_HOME/skills` | 默认 `~/.codex/skills` |
| 分支 | `main` | 可通过 `--ref` 指定 |

### 6. 特殊说明

- **系统技能预装**: `.system` 目录下的技能已预装，无需用户手动安装
- **私有仓库支持**: 通过 `GITHUB_TOKEN` 或 `GH_TOKEN` 环境变量认证
- **Git 回退策略**: HTTPS 失败后尝试 SSH

## 具体技术实现

### 文档解析流程

当 Codex 系统加载 skill-installer 时：

1. **读取 SKILL.md**: 从 `$CODEX_HOME/skills/.system/skill-installer/SKILL.md` 读取内容
2. **解析 Frontmatter**: 提取 YAML 元数据（name, description, metadata）
3. **加载 Agent 配置**: 读取 `agents/openai.yaml` 获取接口定义
4. **注册技能**: 将技能注册到 Codex 的技能管理系统

### 脚本调用链

```
用户请求
    ↓
LLM 解析意图 → 匹配 SKILL.md 中的使用场景
    ↓
构建命令参数
    ↓
调用对应脚本
    ├── list-skills.py → GitHub API → 解析响应 → 标记已安装
    └── install-skill-from-github.py → 下载/克隆 → 验证 → 复制
```

### 关键数据结构

#### 技能列表响应（JSON 格式）
```python
[
    {"name": "skill-1", "installed": false},
    {"name": "skill-2", "installed": true},
    ...
]
```

#### GitHub API 响应解析
```python
# list-skills.py 中的解析逻辑
data = json.loads(payload.decode("utf-8"))
skills = [item["name"] for item in data if item.get("type") == "dir"]
```

### 已安装技能检测

```python
def _installed_skills() -> set[str]:
    root = os.path.join(_codex_home(), "skills")
    if not os.path.isdir(root):
        return set()
    entries = set()
    for name in os.listdir(root):
        path = os.path.join(root, name)
        if os.path.isdir(path):
            entries.add(name)
    return entries
```

检测逻辑：遍历 `$CODEX_HOME/skills` 目录下的所有子目录，排除 `.system` 等特殊目录后，其余即为用户安装的技能。

## 关键代码路径与文件引用

### 技能定义相关

| 文件 | 作用 |
|------|------|
| `SKILL.md` | 本文件，技能主定义文档 |
| `agents/openai.yaml` | OpenAI 接口配置（显示名称、图标等） |
| `LICENSE.txt` | Apache 2.0 许可证 |

### 脚本实现

| 脚本 | 路径 | 功能 |
|------|------|------|
| `list-skills.py` | `scripts/list-skills.py` | 列出远程仓库中的可用技能 |
| `install-skill-from-github.py` | `scripts/install-skill-from-github.py` | 从 GitHub 安装技能 |
| `github_utils.py` | `scripts/github_utils.py` | GitHub API 请求工具函数 |

### 嵌入与加载

| 代码位置 | 功能 |
|----------|------|
| `codex-rs/skills/src/lib.rs:12` | `include_dir!` 嵌入整个 skill-installer 目录 |
| `codex-rs/skills/src/lib.rs:47-78` | `install_system_skills()` 函数，释放系统技能到磁盘 |

### 调用方

skill-installer 作为系统技能，被以下组件调用：

1. **Codex CLI/TUI**: 当用户输入与技能安装相关的命令时
2. **LLM Agent**: 根据 SKILL.md 中的描述，决定何时调用相关脚本

## 依赖与外部交互

### 内部依赖

| 组件 | 依赖方式 | 说明 |
|------|----------|------|
| `codex-skills` crate | 嵌入 | 通过 `include_dir` 嵌入到 Rust 二进制 |
| `codex-utils-absolute-path` | workspace | 安全的路径操作 |

### 外部依赖

| 服务/工具 | 用途 | 必需 |
|-----------|------|------|
| GitHub API | 获取技能列表和仓库内容 | 是 |
| `git` 命令 | sparse checkout 回退 | 可选（auto/download 模式不需要） |
| `GITHUB_TOKEN`/`GH_TOKEN` | 私有仓库认证 | 可选 |

### 网络交互

```
list-skills.py
    ↓ GET
api.github.com/repos/{repo}/contents/{path}?ref={ref}
    ↓
解析 JSON 响应

install-skill-from-github.py (download 模式)
    ↓ GET
codeload.github.com/{owner}/{repo}/zip/{ref}
    ↓
解压 ZIP 文件

install-skill-from-github.py (git 模式)
    ↓ git clone --sparse
github.com/{owner}/{repo}.git
    ↓
sparse-checkout set {paths}
```

### 文件系统交互

| 路径 | 操作 | 说明 |
|------|------|------|
| `$CODEX_HOME/skills` | 读取/写入 | 用户技能安装目录 |
| `$CODEX_HOME/skills/.system` | 读取 | 系统技能目录（包括本技能） |
| `/tmp/codex/skill-install-*` | 创建/删除 | 临时下载/克隆目录 |

## 风险、边界与改进建议

### 潜在风险

1. **GitHub API 限流**
   - 未认证请求限制为每小时 60 次
   - 风险：频繁使用可能导致临时无法获取技能列表
   - 缓解：建议使用 `GITHUB_TOKEN` 提高限额至 5000 次/小时

2. **网络依赖**
   - 所有功能都依赖 GitHub 可访问性
   - 在受限网络环境中可能完全无法使用
   - 建议：考虑增加离线模式或镜像支持

3. **权限提升需求**
   - SKILL.md 明确指出："All of these scripts use network, so when running in the sandbox, request escalation when running them"
   - 沙箱环境中需要显式请求网络权限提升

4. **安全风险**
   - 从任意 GitHub 仓库安装技能存在执行不可信代码的风险
   - 当前实现仅验证 `SKILL.md` 存在性，不验证内容安全性

### 边界情况

| 场景 | 当前行为 | 评估 |
|------|----------|------|
| 目标技能目录已存在 | 报错并退出（`Destination already exists`） | 安全，防止意外覆盖 |
| 技能路径不存在 | 报错（`Skill path not found`） | 合理 |
| 缺少 SKILL.md | 报错（`SKILL.md not found`） | 符合技能规范 |
| 下载失败（401/403/404） | 自动回退到 git sparse checkout | 健壮的设计 |
| 私有仓库无认证 | 下载失败后尝试 git（依赖本地凭证） | 可能成功也可能失败 |
| 路径包含 `..` | 拒绝（`Skill path must be a relative path inside the repo`） | 安全，防止目录遍历 |
| 绝对路径 | 拒绝 | 安全 |

### 改进建议

1. **技能签名验证**
   ```yaml
   # 建议增加的安全机制
   metadata:
     signature: <signature>
     trusted-authors: ["openai", "verified-org"]
   ```

2. **安装前预览**
   增加 `--dry-run` 选项，显示将要安装的文件列表而不实际安装：
   ```bash
   install-skill-from-github.py --repo owner/repo --path skill-name --dry-run
   ```

3. **依赖解析**
   如果技能 A 依赖技能 B，当前需要用户手动安装两者。建议：
   ```yaml
   # 在 SKILL.md 中声明依赖
   dependencies:
     - skill-name-b
     - skill-name-c
   ```

4. **版本管理**
   当前安装总是使用最新版本（或指定 ref）。建议增加版本锁定：
   ```bash
   # 安装特定版本
   install-skill-from-github.py --repo openai/skills --path skills/.curated/my-skill --ref v1.2.3
   ```

5. **卸载功能**
   当前只有安装功能，没有对应的卸载脚本。建议增加：
   ```bash
   scripts/uninstall-skill.py --name skill-name
   ```

6. **更新检查**
   增加检查已安装技能是否有更新的功能：
   ```bash
   scripts/check-updates.py
   ```

7. **本地缓存**
   对于频繁安装的技能，可以考虑本地缓存已下载的仓库 ZIP，减少网络请求。

8. **更好的错误信息**
   当前错误信息较为简单，建议增加：
   - 网络连接失败的诊断建议
   - 认证失败的解决指南
   - 权限不足的修复步骤

### 与 skill-creator 的关系

skill-installer 与 skill-creator（技能创建器）形成互补：

```
skill-creator: 帮助用户创建新技能 → 本地开发 → 推送到 GitHub
                                              ↓
skill-installer: 从 GitHub 安装技能 ← 用户分享技能 ← 其他用户使用
```

两个技能的协同使用构成了 Codex 技能的完整生命周期管理。
