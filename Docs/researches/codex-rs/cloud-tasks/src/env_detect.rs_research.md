# codex-rs/cloud-tasks/src/env_detect.rs 研究文档

## 场景与职责

`env_detect.rs` 负责 Codex Cloud Tasks 的环境自动检测和列表获取功能。该模块解决了用户在不同代码仓库工作时需要手动选择目标环境的问题，通过以下机制实现智能环境选择：

1. **Git 仓库关联**：解析本地 Git 远程 URL，匹配云端配置的仓库特定环境
2. **智能默认选择**：根据标签匹配、固定状态、任务数量等启发式规则自动选择环境
3. **环境列表管理**：为 TUI 提供完整的环境列表，支持去重、排序和搜索

主要使用场景：
- **TUI 启动**：自动检测并选择最可能的目标环境
- **环境选择弹窗**：提供可搜索的环境列表
- **CLI 命令**：验证用户指定的环境 ID 或标签

## 功能点目的

### 1. 环境自动检测 (`autodetect_environment_id`)

自动检测最适合当前仓库的环境，决策优先级：

1. **仓库特定环境**：根据 Git 远程 URL 获取关联的环境列表
2. **标签匹配**：如果提供了 `desired_label`，优先匹配标签
3. **单一环境**：如果只有一个环境可用，直接选择
4. **固定环境**：优先选择标记为 pinned 的环境
5. **任务数量**：选择任务数量最多的环境作为启发式默认

### 2. 环境列表获取 (`list_environments`)

为 TUI 环境选择弹窗提供环境列表，特点：
- **合并去重**：合并仓库特定环境和全局环境列表
- **标签合并**：保留最友好的标签信息
- **排序**：固定环境优先，然后按标签字母顺序

### 3. Git 远程解析

支持多种 GitHub URL 格式：
- SSH: `git@github.com:owner/repo.git`
- HTTPS: `https://github.com/owner/repo.git`
- Git 协议: `git://github.com/owner/repo.git`
- 带组织的 SSH: `org-123@github.com:owner/repo.git`

## 具体技术实现

### 关键数据结构

```rust
// 云端环境 API 响应结构
#[derive(Debug, Clone, serde::Deserialize)]
struct CodeEnvironment {
    id: String,
    #[serde(default)]
    label: Option<String>,
    #[serde(default)]
    is_pinned: Option<bool>,
    #[serde(default)]
    task_count: Option<i64>,
}

// 自动检测结果
#[derive(Debug, Clone)]
pub struct AutodetectSelection {
    pub id: String,
    pub label: Option<String>,
}

// TUI 环境行（定义在 app.rs，此处使用）
pub struct EnvironmentRow {
    pub id: String,
    pub label: Option<String>,
    pub is_pinned: bool,
    pub repo_hints: Option<String>, // 例如 "openai/codex"
}
```

### 核心函数实现

#### 1. 环境自动检测

```rust
pub async fn autodetect_environment_id(
    base_url: &str,
    headers: &HeaderMap,
    desired_label: Option<String>,
) -> anyhow::Result<AutodetectSelection> {
    // 1. 获取 Git 远程 URL 列表
    let origins = get_git_origins();
    crate::append_error_log(format!("env: git origins: {origins:?}"));
    
    // 2. 尝试仓库特定环境
    let mut by_repo_envs: Vec<CodeEnvironment> = Vec::new();
    for origin in &origins {
        if let Some((owner, repo)) = parse_owner_repo(origin) {
            // 构建 API URL（支持两种后端风格）
            let url = if base_url.contains("/backend-api") {
                format!("{}/wham/environments/by-repo/{}/{}/{}", base_url, "github", owner, repo)
            } else {
                format!("{}/api/codex/environments/by-repo/{}/{}/{}", base_url, "github", owner, repo)
            };
            // 获取并记录结果...
            match get_json::<Vec<CodeEnvironment>>(&url, headers).await {
                Ok(mut list) => by_repo_envs.append(&mut list),
                Err(e) => crate::append_error_log(format!("env: by-repo fetch failed: {e}")),
            }
        }
    }
    
    // 3. 尝试从仓库特定环境中选择
    if let Some(env) = pick_environment_row(&by_repo_envs, desired_label.as_deref()) {
        return Ok(AutodetectSelection { id: env.id.clone(), label: env.label.clone() });
    }
    
    // 4. 回退到全局环境列表
    let list_url = if base_url.contains("/backend-api") {
        format!("{base_url}/wham/environments")
    } else {
        format!("{base_url}/api/codex/environments")
    };
    // 详细记录响应用于调试...
    let all_envs: Vec<CodeEnvironment> = serde_json::from_str(&body)?;
    if let Some(env) = pick_environment_row(&all_envs, desired_label.as_deref()) {
        return Ok(AutodetectSelection { id: env.id.clone(), label: env.label.clone() });
    }
    
    anyhow::bail!("no environments available")
}
```

#### 2. 环境选择启发式

```rust
fn pick_environment_row(
    envs: &[CodeEnvironment],
    desired_label: Option<&str>,
) -> Option<CodeEnvironment> {
    if envs.is_empty() { return None; }
    
    // 1. 标签匹配（不区分大小写）
    if let Some(label) = desired_label {
        let lc = label.to_lowercase();
        if let Some(e) = envs.iter()
            .find(|e| e.label.as_deref().unwrap_or("").to_lowercase() == lc) {
            crate::append_error_log(format!("env: matched by label: {label} -> {}", e.id));
            return Some(e.clone());
        }
    }
    
    // 2. 单一环境
    if envs.len() == 1 {
        crate::append_error_log("env: single environment available; selecting it");
        return Some(envs[0].clone());
    }
    
    // 3. 固定环境
    if let Some(e) = envs.iter().find(|e| e.is_pinned.unwrap_or(false)) {
        crate::append_error_log(format!("env: selecting pinned environment: {}", e.id));
        return Some(e.clone());
    }
    
    // 4. 最高任务数量
    if let Some(e) = envs.iter()
        .max_by_key(|e| e.task_count.unwrap_or(0))
        .or_else(|| envs.first()) {
        crate::append_error_log(format!("env: selecting by task_count/first: {}", e.id));
        return Some(e.clone());
    }
    None
}
```

#### 3. Git 远程 URL 解析

```rust
fn parse_owner_repo(url: &str) -> Option<(String, String)> {
    let mut s = url.trim().to_string();
    
    // 处理 ssh:// 前缀
    if let Some(rest) = s.strip_prefix("ssh://") {
        s = rest.to_string();
    }
    
    // 处理 SSH 格式（支持任意用户前缀）
    if let Some(idx) = s.find("@github.com:") {
        let rest = &s[idx + "@github.com:".len()..];
        let rest = rest.trim_start_matches('/').trim_end_matches(".git");
        let mut parts = rest.splitn(2, '/');
        let owner = parts.next()?.to_string();
        let repo = parts.next()?.to_string();
        return Some((owner, repo));
    }
    
    // 处理 HTTPS/Git 协议
    for prefix in [
        "https://github.com/",
        "http://github.com/",
        "git://github.com/",
        "github.com/",
    ] {
        if let Some(rest) = s.strip_prefix(prefix) {
            let rest = rest.trim_start_matches('/').trim_end_matches(".git");
            let mut parts = rest.splitn(2, '/');
            let owner = parts.next()?.to_string();
            let repo = parts.next()?.to_string();
            return Some((owner, repo));
        }
    }
    None
}
```

#### 4. Git 远程获取

```rust
fn get_git_origins() -> Vec<String> {
    // 首选：git config --get-regexp remote\..*\.url
    let out = std::process::Command::new("git")
        .args(["config", "--get-regexp", "remote\\..*\\.url"])
        .output();
    if let Ok(ok) = out && ok.status.success() {
        let s = String::from_utf8_lossy(&ok.stdout);
        let mut urls = Vec::new();
        for line in s.lines() {
            if let Some((_, url)) = line.split_once(' ') {
                urls.push(url.trim().to_string());
            }
        }
        if !urls.is_empty() { return uniq(urls); }
    }
    
    // 回退：git remote -v
    let out = std::process::Command::new("git")
        .args(["remote", "-v"])
        .output();
    if let Ok(ok) = out && ok.status.success() {
        // 解析 fetch URL...
    }
    Vec::new()
}
```

## 关键代码路径与文件引用

### 文件内关键代码位置

| 行号范围 | 内容 |
|----------|------|
| 1-7 | 导入声明 |
| 8-17 | `CodeEnvironment` 结构体定义 |
| 19-23 | `AutodetectSelection` 结构体定义 |
| 25-108 | `autodetect_environment_id` 函数 |
| 110-145 | `pick_environment_row` 函数 |
| 147-169 | `get_json` 辅助函数 |
| 171-216 | `get_git_origins` 和 `uniq` 函数 |
| 218-252 | `parse_owner_repo` 函数 |
| 254-362 | `list_environments` 函数 |

### 跨文件引用关系

```
env_detect.rs
├── 被 lib.rs 引用
│   ├── lib.rs:189-190 (resolve_environment_id 中使用 list_environments)
│   ├── lib.rs:851-869 (TUI 启动时自动检测环境)
│   ├── lib.rs:1030-1043 (处理 EnvironmentsLoaded 事件)
│   ├── lib.rs:1044-1093 (处理 EnvironmentAutodetected 事件)
│   └── lib.rs:1465-1471 (环境选择弹窗加载环境列表)
├── 被 app.rs 引用（类型定义）
│   └── app.rs:6-11 (EnvironmentRow 定义)
└── 引用外部 crate
    ├── codex_client::build_reqwest_client_with_custom_ca
    └── reqwest (HTTP 请求)
```

### 调用流程

```
TUI 启动流程:
lib.rs:851-869
  └── env_detect::autodetect_environment_id()
      ├── get_git_origins() -> ["git@github.com:openai/codex.git"]
      ├── parse_owner_repo() -> ("openai", "codex")
      ├── GET /wham/environments/by-repo/github/openai/codex
      └── pick_environment_row() -> 选择最佳环境

环境列表加载:
lib.rs:1465-1471
  └── env_detect::list_environments()
      ├── 对每个 Git 远程获取仓库特定环境
      ├── GET /wham/environments (全局列表)
      └── 合并、去重、排序
```

## 依赖与外部交互

### 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `codex_client` | 构建带自定义 CA 的 HTTP 客户端 |
| `reqwest` | HTTP 请求和 Header 处理 |
| `tracing` | 日志记录（info, warn） |
| `serde` | JSON 反序列化 |

### API 端点

| 端点 | 用途 |
|------|------|
| `GET /wham/environments/by-repo/{provider}/{owner}/{repo}` | 获取仓库特定环境 |
| `GET /wham/environments` | 获取全局环境列表 |
| `GET /api/codex/environments/by-repo/{provider}/{owner}/{repo}` | 替代风格端点 |
| `GET /api/codex/environments` | 替代风格端点 |

### 环境变量

通过 `crate::append_error_log` 记录调试信息到 `error.log` 文件。

## 风险、边界与改进建议

### 已知风险

1. **Git 命令失败**：`get_git_origins` 依赖本地 `git` 命令，在非 Git 仓库或没有 Git 的环境中会返回空列表
2. **URL 解析局限**：`parse_owner_repo` 仅支持 GitHub，不支持 GitLab、Bitbucket 等其他 Git 托管服务
3. **API 端点硬编码**：两种 URL 风格（`/backend-api` vs `/api/codex`）的检测基于字符串包含检查，可能误判
4. **无缓存机制**：每次打开环境选择弹窗都会重新请求环境列表

### 边界情况

1. **多个 Git 远程**：支持多个远程 URL，会依次尝试获取环境
2. **重复环境**：`list_environments` 使用 `HashMap` 去重，保留最友好的标签
3. **空环境列表**：`pick_environment_row` 返回 `None`，调用方需要处理
4. **网络超时**：依赖 `codex_client` 的超时配置

### 改进建议

1. **支持更多 Git 托管服务**：
   ```rust
   fn parse_owner_repo(url: &str) -> Option<(Provider, String, String)> {
       enum Provider { GitHub, GitLab, Bitbucket }
       // 支持 gitlab.com, bitbucket.org 等
   }
   ```

2. **添加缓存机制**：
   ```rust
   pub struct EnvironmentCache {
       data: Vec<EnvironmentRow>,
       fetched_at: Instant,
       ttl: Duration,
   }
   ```

3. **改进 API 端点检测**：
   ```rust
   enum ApiStyle {
       Wham,      // /backend-api
       CodexApi,  // /api/codex
   }
   
   fn detect_api_style(base_url: &str) -> ApiStyle {
       // 更精确的检测逻辑
   }
   ```

4. **异步 Git 操作**：
   ```rust
   async fn get_git_origins_async() -> Vec<String> {
       // 使用 tokio::process::Command 避免阻塞
   }
   ```

5. **更丰富的环境元数据**：
   ```rust
   struct CodeEnvironment {
       // ... 现有字段
       #[serde(default)]
       description: Option<String>,
       #[serde(default)]
       last_used_at: Option<DateTime<Utc>>,
   }
   ```

6. **错误处理增强**：
   - 区分网络错误、权限错误和配置错误
   - 提供用户友好的错误消息和建议

### 代码质量观察

1. **良好实践**：
   - 详细的日志记录便于调试
   - 防御性编程（`#[serde(default)]` 处理缺失字段）
   - 清晰的启发式选择逻辑

2. **潜在改进**：
   - `get_json` 函数与 `util.rs` 中的类似功能可能有重复
   - 字符串拼接构建 URL 容易出错，建议使用 `url` crate
   - 部分函数较长（`autodetect_environment_id` 80+ 行），可拆分为更小函数

### 测试建议

当前文件没有测试代码，建议添加：

1. **URL 解析测试**：
   ```rust
   #[test]
   fn test_parse_owner_repo_variants() {
       assert_eq!(parse_owner_repo("git@github.com:openai/codex.git"), Some(("openai", "codex")));
       assert_eq!(parse_owner_repo("https://github.com/openai/codex"), Some(("openai", "codex")));
       assert_eq!(parse_owner_repo("org-123@github.com:openai/codex.git"), Some(("openai", "codex")));
   }
   ```

2. **环境选择测试**：
   ```rust
   #[test]
   fn test_pick_environment_by_label() { }
   #[test]
   fn test_pick_environment_pinned_priority() { }
   ```
