# updates.rs 研究文档

## 场景与职责

`updates.rs` 负责 Codex CLI 的版本更新检查和持久化逻辑。它管理本地版本缓存、从远程源获取最新版本信息，并处理用户"不再提醒"的偏好设置。

主要使用场景：
- TUI 启动时检查是否有新版本可用
- 后台刷新版本缓存（避免阻塞启动）
- 用户选择"不再提醒"时持久化该偏好
- 根据安装方式选择正确的版本源（GitHub Releases 或 Homebrew Cask）

## 功能点目的

### 1. 版本信息结构

**定义**：
```rust
#[derive(Serialize, Deserialize, Debug, Clone)]
struct VersionInfo {
    latest_version: String,
    last_checked_at: DateTime<Utc>,  // ISO-8601 (RFC3339)
    dismissed_version: Option<String>,
}
```

**字段说明**：
- `latest_version`：缓存的最新版本号
- `last_checked_at`：上次检查时间，用于控制检查频率
- `dismissed_version`：用户选择忽略的版本号

### 2. 版本检查策略

**主函数**：
```rust
pub fn get_upgrade_version(config: &Config) -> Option<String>
```

**策略**：
1. 如果 `check_for_update_on_startup` 为 false，跳过检查
2. 读取本地缓存的版本信息
3. 如果缓存不存在或超过 20 小时未更新，后台触发新版本检查
4. 返回比当前版本新的缓存版本（如果有）

**后台刷新**：
```rust
tokio::spawn(async move {
    check_for_update(&version_file)
        .await
        .inspect_err(|e| tracing::error!("Failed to update version: {e}"))
});
```

使用 `tokio::spawn` 确保 TUI 启动不被网络请求阻塞。

### 3. 远程版本获取

**函数**：
```rust
async fn check_for_update(version_file: &Path) -> anyhow::Result<()>
```

**版本源选择**：

| 安装方式 | 版本源 | URL |
|---------|--------|-----|
| Homebrew | Homebrew Cask API | `https://formulae.brew.sh/api/cask/codex.json` |
| 其他 | GitHub Releases | `https://api.github.com/repos/openai/codex/releases/latest` |

**原因**：Homebrew 的更新可能滞后于 GitHub Releases，使用 Cask API 获取 Homebrew 实际可用的版本。

### 4. 版本比较

**函数**：
```rust
fn is_newer(latest: &str, current: &str) -> Option<bool>
```

**实现**：
- 解析为 `(major, minor, patch)` 三元组
- 简单字典序比较
- 预发布版本（如 `-beta.1`）返回 `None`（不视为更新）

**标签解析**：
```rust
fn extract_version_from_latest_tag(latest_tag_name: &str) -> anyhow::Result<String> {
    latest_tag_name
        .strip_prefix("rust-v")
        .map(str::to_owned)
        .ok_or_else(|| ...)
}
```

GitHub Releases 标签格式为 `rust-v{version}`（如 `rust-v1.5.0`）。

### 5. 更新提示控制

**函数**：
```rust
pub fn get_upgrade_version_for_popup(config: &Config) -> Option<String>
```

**逻辑**：
1. 获取最新版本
2. 检查用户是否已忽略该版本
3. 如果已忽略，返回 `None`；否则返回版本号

**忽略版本**：
```rust
pub async fn dismiss_version(config: &Config, version: &str) -> anyhow::Result<()>
```

将指定版本写入 `dismissed_version` 字段，持久化到 `version.json`。

## 具体技术实现

### 文件位置

```rust
fn version_filepath(config: &Config) -> PathBuf {
    config.codex_home.join(VERSION_FILENAME)  // "version.json"
}
```

存储在 Codex 配置目录（`~/.codex/`）下。

### 缓存格式

JSON 单行格式（便于追加和读取）：
```json
{"latest_version":"1.5.0","last_checked_at":"2026-03-23T10:00:00Z","dismissed_version":"1.4.0"}
```

### 网络客户端

使用 `codex_core::default_client::create_client()` 创建 HTTP 客户端，支持：
- 自定义 CA 证书
- 超时设置
- 用户代理

### 响应解析

**GitHub Releases**：
```rust
#[derive(Deserialize, Debug, Clone)]
struct ReleaseInfo {
    tag_name: String,
}
```

**Homebrew Cask**：
```rust
#[derive(Deserialize, Debug, Clone)]
struct HomebrewCaskInfo {
    version: String,
}
```

## 关键代码路径与文件引用

### 核心文件

| 文件 | 职责 |
|------|------|
| `updates.rs` | 版本检查和缓存管理 |

### 调用方

| 文件 | 调用函数 | 用途 |
|------|----------|------|
| `update_prompt.rs` | `get_upgrade_version_for_popup` | 决定是否显示更新提示 |
| `update_prompt.rs` | `dismiss_version` | 处理"不再提醒" |
| `history_cell.rs` | `get_upgrade_version` | 显示更新可用历史单元格 |

### 依赖关系

```
updates.rs
├── update_action.rs         (确定版本源)
├── version.rs               (当前版本号)
├── codex_core::config       (配置和路径)
├── codex_core::default_client (HTTP 客户端)
├── chrono                   (日期时间)
├── serde                    (序列化)
└── tokio::fs                (异步文件操作)
```

## 依赖与外部交互

### 外部 crate

| Crate | 用途 |
|-------|------|
| `chrono` | UTC 时间戳处理 |
| `serde` / `serde_json` | JSON 序列化 |
| `tokio` | 异步文件操作和任务调度 |
| `anyhow` | 错误处理 |

### 内部模块

| 模块 | 用途 |
|------|------|
| `crate::update_action` | 确定安装方式和版本源 |
| `crate::version` | 当前版本号（`CODEX_CLI_VERSION`） |
| `codex_core::config::Config` | 配置读取和 Codex home 路径 |
| `codex_core::default_client` | HTTP 客户端创建 |

### 外部服务

| 服务 | URL | 用途 |
|------|-----|------|
| Homebrew Cask API | `https://formulae.brew.sh/api/cask/codex.json` | Homebrew 安装版本检查 |
| GitHub API | `https://api.github.com/repos/openai/codex/releases/latest` | 其他安装方式版本检查 |

## 风险、边界与改进建议

### 已知风险

1. **网络依赖**
   - 版本检查依赖外部 API，网络故障时无法获取更新
   - 缓解：使用缓存，失败时静默处理

2. **API 限制**
   - GitHub API 有速率限制，频繁启动可能触发限制
   - 缓解：20 小时检查间隔减少请求频率

3. **版本格式变化**
   - 如果发布标签格式改变（如从 `rust-v` 改为 `v`），解析会失败
   - 缓解：错误日志记录， graceful 降级

4. **时区问题**
   - 使用 UTC 时间，但用户可能期望本地时间
   - 缓解：仅用于内部比较，不向用户显示

### 边界条件

1. **首次启动**
   - 无缓存文件时立即触发后台检查
   - 当前运行不显示提示（等待缓存建立）

2. **缓存损坏**
   - JSON 解析失败时视为无缓存
   - 触发新的版本检查

3. **版本号解析失败**
   - 非语义化版本号返回 `None`
   - 不视为更新可用

4. **预发布版本**
   - `-beta`、`-rc` 等后缀导致解析失败
   - 有意为之，避免提示预发布版本

### 改进建议

1. **可配置检查间隔**
   - 当前硬编码 20 小时
   - 可添加配置项让用户自定义

2. **代理支持**
   - 当前使用默认客户端，可添加显式代理配置

3. **离线模式**
   - 添加完全禁用网络检查的选项
   - 适用于离线环境

4. **更新日志获取**
   - 获取并缓存发布说明
   - 在更新提示中显示摘要

5. **自动更新**
   - 对于某些安装方式（如 Homebrew），可考虑自动执行更新
   - 需要用户明确授权

6. **版本检查回调**
   - 添加回调机制，让 UI 在版本信息准备好后更新
   - 避免首次启动无提示的问题

7. **缓存过期策略**
   - 当前仅基于时间，可考虑添加强制刷新机制
   - 用户手动触发版本检查
