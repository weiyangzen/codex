# updates.rs 研究文档

## 场景与职责

`updates.rs` 是 Codex TUI 应用服务器的版本更新检查和持久化模块，负责：

1. **版本信息获取**：从远程源（GitHub Releases 或 Homebrew Cask）获取最新版本
2. **版本缓存**：将获取的版本信息缓存到本地文件，避免频繁网络请求
3. **版本比较**：比较本地版本与远程版本，判断是否有更新
4. **用户偏好持久化**：记录用户"不再提醒"特定版本的选择
5. **后台刷新**：在 TUI 启动时后台刷新版本信息，不阻塞启动

该模块仅在非调试构建（`not(debug_assertions)`）中启用。

## 功能点目的

### 1. 版本信息获取

**目的**：获取最新可用版本。

**函数**：`get_upgrade_version()`

**逻辑**：
1. 检查配置是否启用启动时更新检查
2. 读取缓存的版本信息
3. 如果缓存过期（超过 20 小时）或不存在，后台触发更新检查
4. 返回比当前版本新的版本号（如果有）

### 2. 后台版本检查

**目的**：在不阻塞 TUI 启动的情况下刷新版本信息。

**实现**：
```rust
tokio::spawn(async move {
    check_for_update(&version_file)
        .await
        .inspect_err(|e| tracing::error!("Failed to update version: {e}"))
});
```

### 3. 远程版本查询

**目的**：从适当的源获取最新版本。

**源选择**：
- Homebrew 安装：查询 `https://formulae.brew.sh/api/cask/codex.json`
- 其他安装：查询 `https://api.github.com/repos/openai/codex/releases/latest`

### 4. 版本比较

**目的**：判断远程版本是否比当前版本新。

**实现**：简单的语义化版本比较（主版本.次版本.补丁版本）

### 5. 用户偏好持久化

**目的**：记录用户选择"不再提醒"的特定版本。

**函数**：
- `get_upgrade_version_for_popup()`：检查是否应该显示更新提示（考虑用户偏好）
- `dismiss_version()`：持久化用户的"不再提醒"选择

## 具体技术实现

### 数据结构

```rust
#[derive(Serialize, Deserialize, Debug, Clone)]
struct VersionInfo {
    latest_version: String,      // 最新版本号
    last_checked_at: DateTime<Utc>, // 上次检查时间（ISO-8601 / RFC3339）
    #[serde(default)]
    dismissed_version: Option<String>, // 用户选择忽略的版本
}

#[derive(Deserialize, Debug, Clone)]
struct ReleaseInfo {
    tag_name: String,  // GitHub release tag，如 "rust-v1.5.0"
}

#[derive(Deserialize, Debug, Clone)]
struct HomebrewCaskInfo {
    version: String,   // Homebrew cask 版本，如 "0.96.0"
}
```

### 常量定义

```rust
const VERSION_FILENAME: &str = "version.json";
const HOMEBREW_CASK_API_URL: &str = "https://formulae.brew.sh/api/cask/codex.json";
const LATEST_RELEASE_URL: &str = "https://api.github.com/repos/openai/codex/releases/latest";
```

### 缓存文件位置

```rust
fn version_filepath(config: &Config) -> PathBuf {
    config.codex_home.join(VERSION_FILENAME)
}
```

### 版本检查流程

```rust
async fn check_for_update(version_file: &Path) -> anyhow::Result<()> {
    // 1. 根据安装方式选择查询源
    let latest_version = match update_action::get_update_action() {
        Some(UpdateAction::BrewUpgrade) => {
            // 查询 Homebrew API
            let HomebrewCaskInfo { version } = client
                .get(HOMEBREW_CASK_API_URL)
                .send().await?
                .json::<HomebrewCaskInfo>().await?;
            version
        }
        _ => {
            // 查询 GitHub Releases
            let ReleaseInfo { tag_name } = client
                .get(LATEST_RELEASE_URL)
                .send().await?
                .json::<ReleaseInfo>().await?;
            extract_version_from_latest_tag(&tag_name)?
        }
    };
    
    // 2. 保留已忽略的版本信息
    let prev_info = read_version_info(version_file).ok();
    let info = VersionInfo {
        latest_version,
        last_checked_at: Utc::now(),
        dismissed_version: prev_info.and_then(|p| p.dismissed_version),
    };
    
    // 3. 写入缓存文件
    let json_line = format!("{}\n", serde_json::to_string(&info)?);
    tokio::fs::create_dir_all(parent).await?;
    tokio::fs::write(version_file, json_line).await?;
    Ok(())
}
```

### 版本解析

```rust
fn extract_version_from_latest_tag(latest_tag_name: &str) -> anyhow::Result<String> {
    latest_tag_name
        .strip_prefix("rust-v")
        .map(str::to_owned)
        .ok_or_else(|| anyhow::anyhow!("Failed to parse latest tag name '{latest_tag_name}'"))
}
```

### 版本比较

```rust
fn is_newer(latest: &str, current: &str) -> Option<bool> {
    match (parse_version(latest), parse_version(current)) {
        (Some(l), Some(c)) => Some(l > c),
        _ => None,
    }
}

fn parse_version(v: &str) -> Option<(u64, u64, u64)> {
    let mut iter = v.trim().split('.');
    let maj = iter.next()?.parse::<u64>().ok()?;
    let min = iter.next()?.parse::<u64>().ok()?;
    let pat = iter.next()?.parse::<u64>().ok()?;
    Some((maj, min, pat))
}
```

## 关键代码路径与文件引用

### 依赖模块

| 模块 | 文件 | 用途 |
|------|------|------|
| `update_action` | `update_action.rs` | 确定更新源 |
| `version` | `version.rs` | 当前版本常量 |
| `create_client` | `codex_core::default_client` | HTTP 客户端创建 |

### 调用方

| 文件 | 用途 |
|------|------|
| `update_prompt.rs` | 检查是否需要显示更新提示 |
| `lib.rs` | 启动时检查更新 |

### 配置文件

| 文件 | 说明 |
|------|------|
| `~/.codex/version.json` | 版本缓存和用户偏好 |

### 测试

模块包含单元测试：

```rust
#[test]
fn extract_version_from_brew_api_json() {
    // 测试 Homebrew API 响应解析
}

#[test]
fn extracts_version_from_latest_tag() {
    // 测试 GitHub tag 解析
}

#[test]
fn prerelease_version_is_not_considered_newer() {
    // 预发布版本返回 None（不比较）
}

#[test]
fn plain_semver_comparisons_work() {
    // 标准语义化版本比较
}
```

## 依赖与外部交互

### 外部 Crate

| Crate | 用途 |
|-------|------|
| `chrono` | 日期时间处理 |
| `serde` / `serde_json` | 序列化/反序列化 |
| `tokio` | 异步文件操作 |
| `anyhow` | 错误处理 |

### 内部依赖

| 模块 | 用途 |
|------|------|
| `codex_core::config::Config` | 配置读取（检查更新开关、codex_home） |
| `codex_core::default_client::create_client` | 创建 HTTP 客户端 |

### 网络交互

- **GitHub API**：`api.github.com/repos/openai/codex/releases/latest`
- **Homebrew API**：`formulae.brew.sh/api/cask/codex.json`

### 文件系统交互

- 读取/写入 `~/.codex/version.json`
- 文件格式：单行 JSON

## 风险、边界与改进建议

### 已知风险

1. **网络故障**：
   - 如果网络不可用，版本检查失败，依赖缓存数据
   - 首次启动且无网络时，无法获取版本信息

2. **API 限制**：
   - GitHub API 有速率限制（未认证 60 请求/小时）
   - 频繁重启可能触发限制

3. **版本格式变化**：
   - 硬编码假设 tag 格式为 `rust-v{version}`
   - 如果发布流程改变，解析会失败

4. **时区问题**：
   - 使用 `DateTime<Utc>`，但比较逻辑使用本地时间计算 20 小时间隔
   - 夏令时切换可能导致意外行为

### 边界条件

1. **缓存过期**：
   - 20 小时的缓存时间可能过短或过长
   - 没有考虑用户手动触发检查的场景

2. **版本比较**：
   - 不支持预发布版本比较（如 `1.0.0-beta < 1.0.0`）
   - 非标准版本字符串返回 `None`（视为无更新）

3. **并发写入**：
   - 如果多个 Codex 实例同时运行，可能并发写入 `version.json`
   - 可能导致文件损坏

4. **磁盘空间**：
   - 如果 `~/.codex` 所在分区已满，写入缓存会失败

### 改进建议

1. **错误恢复**：
   - 增加指数退避重试机制
   - 区分网络错误和 API 错误

2. **版本比较增强**：
   - 使用 `semver` crate 进行标准语义化版本比较
   - 支持预发布版本和构建元数据

3. **并发安全**：
   - 使用文件锁或原子写入避免并发冲突
   ```rust
   // 原子写入示例
   let temp_file = version_file.with_extension("tmp");
   tokio::fs::write(&temp_file, json_line).await?;
   tokio::fs::rename(&temp_file, version_file).await?;
   ```

4. **配置化**：
   - 允许用户配置检查频率
   - 允许用户配置更新源（用于企业代理）

5. **离线模式**：
   - 明确检测网络不可用状态
   - 提供离线模式下的用户体验

6. **遥测**：
   - 记录版本检查成功/失败率
   - 帮助识别网络或 API 问题

7. **安全增强**：
   - 验证下载的更新二进制签名
   - 使用 HTTPS 并验证证书

8. **测试增强**：
   - 增加模拟 HTTP 服务器的集成测试
   - 测试各种网络故障场景
   - 测试并发写入场景
