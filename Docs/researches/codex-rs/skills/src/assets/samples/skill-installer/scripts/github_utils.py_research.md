# github_utils.py 研究文档

## 场景与职责

`github_utils.py` 是 skill-installer 工具集的共享工具模块，为 `install-skill-from-github.py` 和 `list-skills.py` 提供与 GitHub API 交互的基础能力。该模块封装了 GitHub HTTP 请求的通用逻辑，包括认证头管理和 API URL 构建，避免重复代码。

## 功能点目的

### 1. `github_request(url: str, user_agent: str) -> bytes`
**目的**：执行带认证的 GitHub HTTP GET 请求，返回原始字节响应。

**技术实现**：
- 使用 Python 标准库 `urllib.request` 发送 HTTP 请求
- 构建请求头字典，包含 `User-Agent`（由调用方指定）
- 从环境变量 `GITHUB_TOKEN` 或 `GH_TOKEN` 读取 GitHub 认证令牌
- 如存在令牌，添加 `Authorization: token <token>` 头
- 使用 `urllib.request.urlopen` 执行请求并读取响应内容

**关键代码路径**：
```python
headers = {"User-Agent": user_agent}
token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
if token:
    headers["Authorization"] = f"token {token}"
req = urllib.request.Request(url, headers=headers)
with urllib.request.urlopen(req) as resp:
    return resp.read()
```

### 2. `github_api_contents_url(repo: str, path: str, ref: str) -> str`
**目的**：构建 GitHub Contents API URL，用于获取仓库目录内容列表。

**技术实现**：
- 使用 GitHub REST API v3 的 `/repos/{owner}/{repo}/contents/{path}` 端点
- 添加 `?ref={ref}` 查询参数指定分支/标签/commit
- 返回完整 URL 字符串供 `github_request` 使用

**关键代码路径**：
```python
return f"https://api.github.com/repos/{repo}/contents/{path}?ref={ref}"
```

## 具体技术实现

### 数据结构
- 无自定义数据结构，仅使用标准 Python 类型
- 依赖：`os`, `urllib.request`

### 协议与命令
- **协议**：HTTPS (GitHub API v3 REST)
- **认证方式**：Bearer Token via `Authorization: token <TOKEN>` header
- **环境变量**：`GITHUB_TOKEN`（优先）、`GH_TOKEN`（备选）

### 错误处理
- 不捕获异常，由调用方处理 `urllib.error.HTTPError` 等异常
- 认证失败时 GitHub 返回 401/403，由调用方决定重试策略

## 关键代码路径与文件引用

| 函数 | 被调用方 | 调用路径 |
|------|---------|---------|
| `github_request` | `install-skill-from-github.py` | `_request(url)` → `github_request(url, "codex-skill-install")` |
| `github_request` | `list-skills.py` | `_request(url)` → `github_request(url, "codex-skill-list")` |
| `github_api_contents_url` | `list-skills.py` | `_list_skills()` → `github_api_contents_url(repo, path, ref)` |

## 依赖与外部交互

### 内部依赖
- 无（纯工具模块）

### 外部依赖
| 依赖 | 用途 |
|------|------|
| `os.environ` | 读取 `GITHUB_TOKEN`/`GH_TOKEN` 环境变量 |
| `urllib.request` | HTTP 请求发送 |
| GitHub API | 获取仓库内容和归档文件 |

### 环境要求
- 需要网络访问（GitHub 域名）
- 可选：设置 `GITHUB_TOKEN` 或 `GH_TOKEN` 以访问私有仓库或提高 API 限流阈值

## 风险、边界与改进建议

### 风险
1. **认证令牌泄露**：从环境变量读取令牌，如日志打印请求头可能泄露敏感信息
2. **无超时设置**：`urllib.request.urlopen` 默认无超时，网络异常时可能无限阻塞
3. **无重试机制**：网络抖动或 GitHub 间歇性错误会导致直接失败
4. **User-Agent 硬编码**：不同调用方使用不同 User-Agent，但无版本信息

### 边界条件
- 环境变量 `GITHUB_TOKEN` 优先级高于 `GH_TOKEN`
- 令牌格式为 `token <value>`（GitHub 经典格式），非 `Bearer <value>`
- 仅支持 GET 请求，不支持 POST/PUT/DELETE

### 改进建议
1. **添加超时参数**：
   ```python
   urllib.request.urlopen(req, timeout=30)
   ```

2. **添加重试逻辑**：
   ```python
   from urllib.error import HTTPError
   for attempt in range(3):
       try:
           return urllib.request.urlopen(req, timeout=30).read()
       except HTTPError as e:
           if e.code == 429 and attempt < 2:  # Rate limit
               time.sleep(2 ** attempt)
               continue
           raise
   ```

3. **支持 Bearer Token 格式**：GitHub 推荐使用 `Authorization: Bearer <TOKEN>`

4. **添加日志记录**：在 DEBUG 级别记录请求 URL（脱敏后）

5. **类型提示完善**：添加返回类型和异常声明
   ```python
   from typing import overload
   def github_request(url: str, user_agent: str, timeout: float = 30.0) -> bytes: ...
   ```
