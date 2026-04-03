# list-skills.py 研究文档

## 场景与职责

`list-skills.py` 是 Codex CLI 的 skill 列表查询工具，用于从 GitHub 仓库（默认 `openai/skills`）获取可用 skill 列表，并标记哪些 skill 已在本地安装。该脚本支持两种输出格式：
1. **文本格式**：带编号的列表，已安装 skill 标注 "(already installed)"
2. **JSON 格式**：结构化数据，包含 `name` 和 `installed` 布尔字段

该工具是 skill-installer skill 的核心组件，用于响应用户 "有哪些 skill 可用" 的查询。

## 功能点目的

### 1. 参数解析 (`_parse_args`)
**目的**：解析命令行参数，支持自定义仓库、路径、分支和输出格式。

**技术实现**：
- 使用 `argparse.ArgumentParser` 定义参数
- `--repo`：目标仓库，默认 `openai/skills`
- `--path`：仓库内 skill 目录路径，默认 `skills/.curated`
- `--ref`：分支/标签，默认 `main`
- `--format`：输出格式，`text` 或 `json`

**关键代码路径**：
```python
default=DEFAULT_REPO      # "openai/skills"
default=DEFAULT_PATH      # "skills/.curated"
default=DEFAULT_REF       # "main"
choices=["text", "json"]  # 输出格式
```

### 2. 本地已安装 skill 检测 (`_installed_skills`)
**目的**：扫描本地 `$CODEX_HOME/skills` 目录，获取已安装 skill 名称集合。

**技术实现**：
- 从 `CODEX_HOME` 环境变量或默认 `~/.codex` 确定根目录
- 遍历 `skills/` 子目录
- 返回目录名集合（仅包含子目录，排除文件）

**关键代码路径**：
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

### 3. 远程 skill 列表获取 (`_list_skills`)
**目的**：通过 GitHub Contents API 获取指定路径下的 skill 目录列表。

**技术实现**：
- 使用 `github_api_contents_url` 构建 API URL
- 使用 `github_request` 发送认证请求
- 解析 JSON 响应，筛选 `type == "dir"` 的条目
- 返回按字母排序的目录名列表

**关键代码路径**：
```python
def _list_skills(repo: str, path: str, ref: str) -> list[str]:
    api_url = github_api_contents_url(repo, path, ref)
    payload = _request(api_url)
    data = json.loads(payload.decode("utf-8"))
    if not isinstance(data, list):
        raise ListError("Unexpected skills listing response.")
    skills = [item["name"] for item in data if item.get("type") == "dir"]
    return sorted(skills)
```

### 4. 结果格式化输出 (`main`)
**目的**：根据指定格式输出 skill 列表和安装状态。

**技术实现**：
- **text 格式**：带编号列表，已安装 skill 附加 "(already installed)"
- **json 格式**：对象数组，每个对象包含 `name` 和 `installed` 字段

**关键代码路径**：
```python
if args.format == "json":
    payload = [
        {"name": name, "installed": name in installed} for name in skills
    ]
    print(json.dumps(payload))
else:
    for idx, name in enumerate(skills, start=1):
        suffix = " (already installed)" if name in installed else ""
        print(f"{idx}. {name}{suffix}")
```

## 具体技术实现

### 数据结构

```python
class Args(argparse.Namespace):
    repo: str      # 目标仓库，如 "openai/skills"
    path: str      # 仓库内路径，如 "skills/.curated"
    ref: str       # 分支/标签，如 "main"
    format: str    # 输出格式: "text" 或 "json"
```

### 关键流程

```
main()
├── _parse_args() → Args
├── _list_skills(repo, path, ref) → list[str]
│   ├── github_api_contents_url() → API URL
│   ├── _request() → bytes
│   │   └── github_request() (from github_utils)
│   └── json.loads() → 筛选 dirs → sorted()
├── _installed_skills() → set[str]
│   └── 遍历 $CODEX_HOME/skills/
└── 格式化输出
    ├── json: [{"name": ..., "installed": ...}]
    └── text: "1. name (already installed)"
```

### 协议与命令

| 协议/命令 | 用途 |
|-----------|------|
| GitHub Contents API | 获取目录内容列表 |
| HTTPS | API 请求传输 |
| 本地文件系统 | 扫描已安装 skill |

### API 响应处理

GitHub Contents API 返回目录内容时，响应为数组，每个元素包含：
- `name`: 文件/目录名
- `type`: `"file"` 或 `"dir"`
- `path`: 完整路径
- 其他字段（size, sha, url 等）

脚本仅使用 `name` 和 `type` 字段。

## 关键代码路径与文件引用

### 内部调用关系

| 函数 | 调用者 | 被调用者 |
|------|--------|----------|
| `main` | - | `_parse_args`, `_list_skills`, `_installed_skills` |
| `_list_skills` | `main` | `github_api_contents_url`, `_request` |
| `_request` | `_list_skills` | `github_request` (from github_utils.py) |
| `_installed_skills` | `main` | `_codex_home` |

### 外部文件引用

| 引用 | 用途 |
|------|------|
| `github_utils.py` | `github_request`, `github_api_contents_url` |
| `$CODEX_HOME/skills/` | 本地 skill 安装目录 |
| GitHub API | 远程 skill 列表来源 |

### 默认配置

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| `DEFAULT_REPO` | `openai/skills` | 官方 skill 仓库 |
| `DEFAULT_PATH` | `skills/.curated` | 精选 skill 目录 |
| `DEFAULT_REF` | `main` | 主分支 |

## 依赖与外部交互

### Python 标准库依赖
- `argparse`：命令行参数解析
- `json`：JSON 序列化
- `os`：文件系统操作和环境变量
- `sys`：退出码和错误输出
- `urllib.error`：HTTP 错误处理

### 外部系统依赖
| 依赖 | 用途 |
|------|------|
| GitHub Contents API | 获取远程 skill 列表 |
| `$CODEX_HOME` 环境变量 | 确定本地 skill 目录 |
| `~/.codex/skills/` | 默认本地 skill 安装路径 |

### 网络要求
- 访问 `api.github.com`
- 可选：设置 `GITHUB_TOKEN`/`GH_TOKEN` 以提高 API 限流阈值

## 风险、边界与改进建议

### 风险

1. **API 限流**：GitHub API 对未认证请求限制 60 次/小时，可能在高频使用时触发
2. **网络依赖**：完全依赖网络获取 skill 列表，离线时无法使用
3. **无缓存机制**：每次调用都重新请求 API，浪费资源且增加失败概率
4. **本地扫描性能**：如 skill 目录包含大量文件，`os.listdir` 可能变慢
5. **API 响应格式变化**：GitHub API 格式变更可能导致解析失败

### 边界条件

| 场景 | 行为 |
|------|------|
| 本地 skill 目录不存在 | 返回空集合，不报错 |
| API 返回 404 | 抛出 `ListError`，提示路径不存在 |
| API 返回其他 HTTP 错误 | 抛出 `ListError`，显示状态码 |
| API 返回非数组响应 | 抛出 `ListError`，提示意外响应 |
| 空 skill 列表 | 输出空数组（JSON）或无输出（text） |
| 所有 skill 已安装 | 所有条目标记 installed=true |

### 改进建议

1. **添加本地缓存**：
   ```python
   import hashlib
   import time
   
   def _cached_list_skills(repo, path, ref, cache_ttl=3600):
       cache_key = hashlib.md5(f"{repo}/{path}/{ref}".encode()).hexdigest()
       cache_file = os.path.join(_codex_home(), ".cache", f"skills_{cache_key}.json")
       
       if os.path.exists(cache_file):
           mtime = os.path.getmtime(cache_file)
           if time.time() - mtime < cache_ttl:
               with open(cache_file) as f:
                   return json.load(f)
       
       skills = _list_skills(repo, path, ref)
       os.makedirs(os.path.dirname(cache_file), exist_ok=True)
       with open(cache_file, "w") as f:
           json.dump(skills, f)
       return skills
   ```

2. **添加离线模式**：
   - 网络失败时使用缓存数据
   - 添加 `--offline` 参数强制使用缓存

3. **增强错误处理**：
   - 区分网络错误、API 错误、解析错误
   - 提供用户友好的错误信息

4. **支持分页**：
   - GitHub API 对大型目录可能分页
   - 处理 `Link` header 获取所有结果

5. **添加搜索/过滤功能**：
   ```python
   parser.add_argument("--search", help="Filter skills by name pattern")
   parser.add_argument("--category", help="Filter by category")
   ```

6. **显示 skill 描述**：
   - 获取每个 skill 的 `SKILL.md`  frontmatter
   - 显示简短描述帮助用户选择

7. **添加版本信息**：
   - 显示 skill 版本（如从 git tag 或 SKILL.md 解析）
   - 提示可更新的 skill

8. **并发获取**：
   - 如需要获取每个 skill 的详细信息，使用并发请求
