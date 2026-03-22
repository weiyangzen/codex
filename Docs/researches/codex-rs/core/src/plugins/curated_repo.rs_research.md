# curated_repo.rs 研究文档

## 场景与职责

`curated_repo.rs` 负责 Codex 插件系统中**精选插件仓库（OpenAI Curated Plugins Repository）**的同步与管理。该模块通过 GitHub API 从 `openai/plugins` 仓库下载最新的插件包，并维护本地缓存，确保用户能够获取到 OpenAI 官方精选的插件集合。

### 核心职责
1. **远程仓库同步**：从 GitHub API 获取 `openai/plugins` 仓库的最新代码
2. **版本管理**：通过 SHA 校验判断是否需要更新本地缓存
3. **原子性安装**：使用临时目录和备份机制确保插件包更新的原子性
4. **安全解压**：处理 ZIP 包解压，防止路径遍历攻击

---

## 功能点目的

### 1. 精选插件仓库路径管理
- `curated_plugins_repo_path()`: 返回精选插件仓库在本地 codex_home 中的存储路径（`.tmp/plugins`）
- `read_curated_plugins_sha()`: 读取本地记录的仓库 SHA，用于版本比对

### 2. 仓库同步机制
- `sync_openai_plugins_repo()`: 主入口函数，协调整个同步流程
  - 获取远程仓库的默认分支和最新 SHA
  - 对比本地 SHA，如一致则跳过下载
  - 下载 ZIP 包并解压到临时目录
  - 验证必需文件（`.agents/plugins/marketplace.json`）存在
  - 原子性替换旧版本（备份-激活-回滚机制）
  - 更新本地 SHA 记录

### 3. GitHub API 交互
- `fetch_curated_repo_remote_sha()`: 获取远程仓库 HEAD 的 SHA
  - 调用 `/repos/openai/plugins` 获取默认分支
  - 调用 `/repos/openai/plugins/git/ref/heads/{branch}` 获取 SHA
- `fetch_curated_repo_zipball()`: 下载 ZIP 包
- `fetch_github_text()` / `fetch_github_bytes()`: 通用 HTTP 请求封装

### 4. ZIP 包处理
- `extract_zipball_to_dir()`: 安全解压 ZIP 包
  - 使用 `enclosed_name()` 防止路径遍历
  - 跳过 ZIP 包中的根目录（如 `openai-plugins-{sha}/`）
  - 保留 Unix 文件权限

---

## 具体技术实现

### 关键数据结构

```rust
// GitHub API 响应结构
struct GitHubRepositorySummary { default_branch: String }
struct GitHubGitRefSummary { object: GitHubGitRefObject }
struct GitHubGitRefObject { sha: String }
```

### 核心常量

| 常量 | 值 | 说明 |
|------|-----|------|
| `GITHUB_API_BASE_URL` | `https://api.github.com` | GitHub API 基础 URL |
| `GITHUB_API_ACCEPT_HEADER` | `application/vnd.github+json` | GitHub API 版本 |
| `GITHUB_API_VERSION_HEADER` | `2022-11-28` | API 版本号 |
| `OPENAI_PLUGINS_OWNER/REPO` | `openai/plugins` | 目标仓库 |
| `CURATED_PLUGINS_RELATIVE_DIR` | `.tmp/plugins` | 本地存储路径 |
| `CURATED_PLUGINS_SHA_FILE` | `.tmp/plugins.sha` | SHA 记录文件 |
| `CURATED_PLUGINS_HTTP_TIMEOUT` | 30秒 | HTTP 超时 |

### 同步流程

```
sync_openai_plugins_repo()
├── fetch_curated_repo_remote_sha()  [获取远程SHA]
├── read_sha_file()                   [读取本地SHA]
├── 对比 SHA，如相同则返回
├── 创建临时目录 (tempfile::Builder)
├── fetch_curated_repo_zipball()     [下载ZIP]
├── extract_zipball_to_dir()         [解压]
├── 验证 marketplace.json 存在
├── 原子性替换：
│   ├── 如存在旧版本 → 备份到临时目录
│   ├── 移动新版本到目标位置
│   └── 失败则回滚
└── 写入新 SHA 到文件
```

### 原子性更新机制

```rust
// 伪代码展示原子性替换逻辑
if repo_path.exists() {
    // 1. 创建备份
    fs::rename(&repo_path, &backup_repo_path)?;
    
    // 2. 激活新版本
    if let Err(err) = fs::rename(&cloned_repo_path, &repo_path) {
        // 3. 失败则回滚
        fs::rename(&backup_repo_path, &repo_path)?;
        return Err(...);
    }
} else {
    // 首次安装直接移动
    fs::rename(&cloned_repo_path, &repo_path)?;
}
```

### 安全解压实现

```rust
fn extract_zipball_to_dir(bytes: &[u8], destination: &Path) -> Result<(), String> {
    // 1. 使用 Cursor 包装字节流
    let cursor = Cursor::new(bytes);
    let mut archive = ZipArchive::new(cursor)?;
    
    for index in 0..archive.len() {
        let mut entry = archive.by_index(index)?;
        
        // 2. 安全检查：防止路径遍历
        let Some(relative_path) = entry.enclosed_name() else {
            return Err("zip entry escapes extraction root");
        };
        
        // 3. 跳过 ZIP 包根目录（如 openai-plugins-abc123/）
        let mut components = relative_path.components();
        let Some(Component::Normal(_)) = components.next() else { continue };
        
        // 4. 构建输出路径并解压
        let output_path = destination.join(components.fold(...));
        // ... 文件/目录处理
    }
}
```

---

## 关键代码路径与文件引用

### 主要函数调用图

```
curated_repo.rs
├── pub curated_plugins_repo_path()
├── pub read_curated_plugins_sha()
├── pub sync_openai_plugins_repo()
│   └── sync_openai_plugins_repo_with_api_base_url()
│       ├── fetch_curated_repo_remote_sha()
│       │   ├── fetch_github_text()
│       │   └── github_request()
│       ├── read_sha_file()
│       ├── fetch_curated_repo_zipball()
│       │   └── fetch_github_bytes()
│       └── extract_zipball_to_dir()
│           └── apply_zip_permissions()
└── [测试模块] tests (curated_repo_tests.rs)
```

### 文件引用关系

| 被引用方 | 用途 |
|---------|------|
| `default_client::build_reqwest_client` | 创建 HTTP 客户端 |
| `zip::ZipArchive` | ZIP 包解压 |
| `tempfile::Builder` | 创建临时目录 |
| `std::os::unix::fs::PermissionsExt` | Unix 权限设置 |

### 测试覆盖

测试文件：`curated_repo_tests.rs`

| 测试用例 | 验证内容 |
|---------|---------|
| `curated_plugins_repo_path_uses_codex_home_tmp_dir` | 路径拼接正确性 |
| `read_curated_plugins_sha_reads_trimmed_sha_file` | SHA 文件读取与 trim |
| `sync_openai_plugins_repo_downloads_zipball_and_records_sha` | 完整同步流程 |
| `sync_openai_plugins_repo_skips_archive_download_when_sha_matches` | SHA 匹配时跳过下载 |

---

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `reqwest` | HTTP 客户端 |
| `serde` | JSON 反序列化 |
| `zip` | ZIP 包处理 |
| `tempfile` | 临时目录管理 |
| `tokio` | 异步运行时（同步阻塞调用） |

### 外部服务

| 服务 | 接口 | 说明 |
|------|------|------|
| GitHub API | `GET /repos/openai/plugins` | 获取仓库信息 |
| GitHub API | `GET /repos/openai/plugins/git/ref/heads/{branch}` | 获取分支 SHA |
| GitHub API | `GET /repos/openai/plugins/zipball/{sha}` | 下载代码包 |

### 文件系统交互

| 路径 | 操作 |
|------|------|
| `{codex_home}/.tmp/plugins` | 插件仓库存储 |
| `{codex_home}/.tmp/plugins.sha` | SHA 版本记录 |
| 临时目录（前缀 `plugins-clone-`） | 下载解压临时存储 |
| 临时目录（前缀 `plugins-backup-`） | 更新时备份 |

---

## 风险、边界与改进建议

### 已知风险

1. **网络依赖风险**
   - 首次启动或 SHA 变更时必须联网下载
   - GitHub API 有速率限制（未处理 403/429 特殊逻辑）
   - **建议**：增加指数退避重试机制，处理速率限制响应

2. **磁盘空间风险**
   - 临时目录和备份目录需要额外磁盘空间
   - 如磁盘满，回滚可能失败
   - **建议**：预检查磁盘空间，清理临时文件

3. **并发安全风险**
   - 使用 `std::thread` 创建同步运行时，非异步友好
   - `CURATED_REPO_SYNC_STARTED` 原子标志防止重复启动，但无进程级锁
   - **建议**：考虑文件锁防止多进程并发同步

4. **ZIP 安全风险**
   - 已使用 `enclosed_name()` 防止路径遍历
   - 但未限制单个文件大小或总解压大小
   - **建议**：增加 ZIP bomb 防护（大小限制）

### 边界条件

| 场景 | 当前行为 |
|------|---------|
| SHA 文件不存在 | 视为需要更新，执行完整同步 |
| SHA 文件内容为空 | `read_sha_file()` 返回 `None`，执行同步 |
| ZIP 包缺少 marketplace.json | 返回错误，不激活 |
| 激活失败 | 尝试回滚，如回滚失败则保留备份路径 |
| 非 Unix 系统 | `apply_zip_permissions` 为空操作 |

### 改进建议

1. **增量更新**：当前每次下载完整 ZIP，可考虑使用 Git 协议或增量更新
2. **缓存策略**：增加缓存过期时间配置，而非仅依赖 SHA
3. **校验和验证**：下载后验证 ZIP 完整性（GitHub 提供 SHA）
4. **后台同步**：当前在独立线程运行，但阻塞等待完成，可考虑纯异步
5. **监控埋点**：增加更多 metrics（下载时间、失败率等）

### 测试建议

- 当前测试使用 `wiremock` 模拟 GitHub API，覆盖正常路径
- **待补充**：
  - 网络超时场景
  - 磁盘满场景
  - ZIP 炸弹攻击防护
  - 并发同步场景
