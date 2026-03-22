# manager.rs 研究文档

## 场景与职责

`manager.rs` 是 Codex 插件系统的**核心管理模块**，负责插件的全生命周期管理，包括安装、卸载、启用/禁用、远程同步、市场发现等功能。该模块是插件系统的中央协调器，连接配置、存储、市场和远程服务等多个子系统。

### 核心职责
1. **插件生命周期管理**：安装、卸载、启用、禁用
2. **市场管理**：发现、加载、解析市场（marketplace）
3. **远程同步**：与 ChatGPT 后端同步插件状态
4. **缓存管理**：插件加载结果、精选插件 ID 的缓存
5. **精选仓库同步**：后台同步 OpenAI 精选插件仓库
6. **能力聚合**：收集插件的技能、MCP 服务器、应用连接器

---

## 功能点目的

### 1. 插件安装与卸载
- **安装**：`install_plugin()` / `install_plugin_with_remote_sync()`
  - 解析市场插件
  - 原子性复制到缓存目录
  - 更新配置启用插件
  - 发送分析事件
- **卸载**：`uninstall_plugin()` / `uninstall_plugin_with_remote_sync()`
  - 从缓存删除
  - 清理配置
  - 发送分析事件

### 2. 远程同步
- **函数**：`sync_plugins_from_remote()`
- **目的**：与 ChatGPT 后端同步插件安装状态
- **流程**：
  1. 获取远程插件状态列表
  2. 对比本地配置和安装状态
  3. 安装远程启用但本地未安装的插件
  4. 卸载远程禁用但本地已安装的插件
  5. 更新配置状态

### 3. 市场管理
- **列表**：`list_marketplaces_for_config()`
  - 发现所有可用市场
  - 合并精选市场（`openai-curated`）
  - 去重处理
- **读取**：`read_plugin_for_config()`
  - 加载市场定义
  - 解析插件 manifest
  - 收集技能、MCP、应用信息

### 4. 插件加载
- **函数**：`plugins_for_config()` / `plugins_for_config_with_force_reload()`
- **目的**：加载所有启用的插件，聚合其能力
- **输出**：`PluginLoadOutcome`，包含：
  - 加载的插件列表
  - 能力摘要列表
  - 有效的技能根目录
  - 有效的 MCP 服务器配置
  - 有效的应用连接器

### 5. 精选仓库后台同步
- **函数**：`maybe_start_curated_repo_sync_for_config()` / `start_curated_repo_sync()`
- **目的**：后台同步 OpenAI 精选插件仓库
- **机制**：
  - 使用 `AtomicBool` 防止重复启动
  - 独立线程执行同步
  - 同步后刷新缓存

---

## 具体技术实现

### 核心数据结构

```rust
/// 插件管理器
pub struct PluginsManager {
    codex_home: PathBuf,
    store: PluginStore,
    featured_plugin_ids_cache: RwLock<Option<CachedFeaturedPluginIds>>,
    cached_enabled_outcome: RwLock<Option<PluginLoadOutcome>>,
    analytics_events_client: RwLock<Option<AnalyticsEventsClient>>,
}

/// 插件加载结果
pub struct PluginLoadOutcome {
    plugins: Vec<LoadedPlugin>,
    capability_summaries: Vec<PluginCapabilitySummary>,
}

/// 已加载插件
pub struct LoadedPlugin {
    pub config_name: String,        // 配置中的名称（如 "slack@openai-curated"）
    pub manifest_name: Option<String>,  // manifest 中的名称
    pub manifest_description: Option<String>,
    pub root: AbsolutePathBuf,      // 插件根目录
    pub enabled: bool,
    pub skill_roots: Vec<PathBuf>,
    pub mcp_servers: HashMap<String, McpServerConfig>,
    pub apps: Vec<AppConnectorId>,
    pub error: Option<String>,
}

/// 远程同步结果
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct RemotePluginSyncResult {
    pub installed_plugin_ids: Vec<String>,
    pub enabled_plugin_ids: Vec<String>,
    pub disabled_plugin_ids: Vec<String>,
    pub uninstalled_plugin_ids: Vec<String>,
}
```

### 缓存机制

#### 精选插件 ID 缓存
```rust
struct CachedFeaturedPluginIds {
    key: FeaturedPluginIdsCacheKey,  // 包含 base_url, account_id, user_id, is_workspace
    expires_at: Instant,
    featured_plugin_ids: Vec<String>,
}

const FEATURED_PLUGIN_IDS_CACHE_TTL: Duration = Duration::from_secs(60 * 60 * 3); // 3小时
```

#### 插件加载结果缓存
```rust
cached_enabled_outcome: RwLock<Option<PluginLoadOutcome>>

// 使用
if !force_reload && let Some(outcome) = self.cached_enabled_outcome() {
    return outcome;
}
```

### 原子性安装流程

```rust
async fn install_resolved_plugin(&self, resolved: ResolvedMarketplacePlugin) 
    -> Result<PluginInstallOutcome, PluginInstallError> 
{
    // 1. 获取插件版本（精选插件使用 SHA）
    let plugin_version = if resolved.plugin_id.marketplace_name == OPENAI_CURATED_MARKETPLACE_NAME {
        Some(read_curated_plugins_sha(...)?)
    } else {
        None
    };
    
    // 2. 阻塞执行文件操作
    let result = tokio::task::spawn_blocking(move || {
        if let Some(version) = plugin_version {
            store.install_with_version(source_path, plugin_id, version)
        } else {
            store.install(source_path, plugin_id)
        }
    }).await?;
    
    // 3. 更新配置启用插件
    ConfigService::new_with_defaults(...)
        .write_value(ConfigValueWriteParams {
            key_path: format!("plugins.{}", result.plugin_id.as_key()),
            value: json!({ "enabled": true }),
            ...
        }).await?;
    
    // 4. 发送分析事件
    if let Some(client) = analytics_events_client {
        client.track_plugin_installed(...);
    }
    
    Ok(PluginInstallOutcome { ... })
}
```

### 远程同步算法

```rust
pub async fn sync_plugins_from_remote(&self, config: &Config, auth: Option<&CodexAuth>) 
    -> Result<RemotePluginSyncResult, PluginRemoteSyncError> 
{
    // 1. 获取远程状态
    let remote_plugins = fetch_remote_plugin_status(config, auth).await?;
    
    // 2. 获取本地配置
    let configured_plugins = configured_plugins_from_stack(&config.config_layer_stack);
    let curated_marketplace = load_marketplace(&curated_marketplace_path)?;
    
    // 3. 构建本地插件列表
    let mut local_plugins = Vec::new();
    for plugin in curated_marketplace.plugins {
        let plugin_id = PluginId::new(plugin.name.clone(), marketplace_name.clone())?;
        let current_enabled = configured_plugins.get(&plugin_key).map(|p| p.enabled);
        let installed_version = self.store.active_plugin_version(&plugin_id);
        local_plugins.push((plugin_name, plugin_id, source_path, current_enabled, installed_version));
    }
    
    // 4. 计算差异
    let mut config_edits = Vec::new();
    let mut installs = Vec::new();
    let mut uninstalls = Vec::new();
    
    for (name, plugin_id, source_path, current_enabled, installed_version) in local_plugins {
        let is_installed = installed_version.is_some();
        
        if remote_installed_plugin_names.contains(&name) {
            // 远程启用：安装（如未安装）+ 启用（如未启用）
            if !is_installed { installs.push(...); }
            if current_enabled != Some(true) { config_edits.push(ConfigEdit::SetPath { ... }); }
        } else {
            // 远程禁用：卸载（如已安装）+ 清理配置
            if is_installed { uninstalls.push(plugin_id); }
            if current_enabled.is_some() { config_edits.push(ConfigEdit::ClearPath { ... }); }
        }
    }
    
    // 5. 执行变更
    tokio::task::spawn_blocking(move || {
        for (source_path, plugin_id, version) in installs {
            store.install_with_version(source_path, plugin_id, version)?;
        }
        for plugin_id in uninstalls {
            store.uninstall(&plugin_id)?;
        }
    }).await?;
    
    ConfigEditsBuilder::new(&self.codex_home)
        .with_edits(config_edits)
        .apply().await?;
    
    self.clear_cache();
    Ok(result)
}
```

### 插件加载流程

```rust
fn load_plugin(config_name: String, plugin: &PluginConfig, store: &PluginStore) -> LoadedPlugin {
    // 1. 确定插件根目录
    let plugin_root = PluginId::parse(&config_name)
        .ok()
        .and_then(|id| store.active_plugin_root(&id))
        .unwrap_or_else(|| store.root().clone());
    
    let mut loaded = LoadedPlugin {
        config_name,
        root: plugin_root.clone(),
        enabled: plugin.enabled,
        ...
    };
    
    if !plugin.enabled {
        return loaded;  // 未启用直接返回
    }
    
    // 2. 加载 manifest
    let Some(manifest) = load_plugin_manifest(plugin_root.as_path()) else {
        loaded.error = Some("missing or invalid .codex-plugin/plugin.json".to_string());
        return loaded;
    };
    
    // 3. 加载技能根目录
    loaded.skill_roots = plugin_skill_roots(plugin_root.as_path(), &manifest.paths);
    
    // 4. 加载 MCP 服务器
    for mcp_config_path in plugin_mcp_config_paths(...) {
        let plugin_mcp = load_mcp_servers_from_file(plugin_root.as_path(), &mcp_config_path);
        loaded.mcp_servers.extend(plugin_mcp.mcp_servers);
    }
    
    // 5. 加载应用连接器
    loaded.apps = load_plugin_apps(plugin_root.as_path());
    
    loaded
}
```

---

## 关键代码路径与文件引用

### 模块结构

```
manager.rs (1720 lines)
├── 常量定义
│   ├── DEFAULT_SKILLS_DIR_NAME: &str = "skills"
│   ├── DEFAULT_MCP_CONFIG_FILE: &str = ".mcp.json"
│   ├── DEFAULT_APP_CONFIG_FILE: &str = ".app.json"
│   ├── OPENAI_CURATED_MARKETPLACE_NAME: &str = "openai-curated"
│   └── FEATURED_PLUGIN_IDS_CACHE_TTL: Duration = 3小时
├── 数据结构定义
│   ├── FeaturedPluginIdsCacheKey
│   ├── CachedFeaturedPluginIds
│   ├── PluginInstallRequest / PluginReadRequest
│   ├── PluginInstallOutcome / PluginReadOutcome
│   ├── PluginDetail / ConfiguredMarketplace / ConfiguredMarketplacePlugin
│   ├── LoadedPlugin / PluginCapabilitySummary / PluginTelemetryMetadata
│   ├── PluginLoadOutcome / RemotePluginSyncResult
│   └── 错误类型：PluginRemoteSyncError, PluginInstallError, PluginUninstallError
├── PluginsManager 实现
│   ├── new() / set_analytics_events_client()
│   ├── plugins_for_config() / plugins_for_config_with_force_reload()
│   ├── clear_cache() / cached_enabled_outcome()
│   ├── featured_plugin_ids_for_config()
│   ├── install_plugin() / install_plugin_with_remote_sync()
│   ├── uninstall_plugin() / uninstall_plugin_with_remote_sync()
│   ├── sync_plugins_from_remote()
│   ├── list_marketplaces_for_config() / read_plugin_for_config()
│   ├── maybe_start_curated_repo_sync_for_config() / start_curated_repo_sync()
│   └── 内部辅助方法
├── 错误类型实现
├── 辅助函数
│   ├── load_plugins_from_layer_stack()
│   ├── plugin_namespace_for_skill_path()
│   ├── refresh_curated_plugin_cache()
│   ├── configured_plugins_from_stack()
│   ├── load_plugin() / plugin_skill_roots() / default_skill_roots()
│   ├── plugin_mcp_config_paths() / default_mcp_config_paths()
│   ├── load_plugin_apps() / plugin_app_config_paths() / default_app_config_paths()
│   ├── load_apps_from_paths()
│   ├── plugin_telemetry_metadata_from_root() / installed_plugin_telemetry_metadata()
│   ├── load_mcp_servers_from_file() / normalize_plugin_mcp_servers()
│   └── normalize_plugin_mcp_server_value()
└── 测试模块 (manager_tests.rs)
```

### 依赖关系

| 依赖模块 | 用途 |
|---------|------|
| `curated_repo` | 精选仓库同步、SHA 读取 |
| `marketplace` | 市场加载、插件解析 |
| `store` | 插件存储、安装、卸载 |
| `manifest` | 插件 manifest 加载 |
| `remote` | 远程插件状态获取、操作 |
| `config` / `config::edit` | 配置读写 |
| `skills::loader` | 技能加载 |
| `AuthManager` / `CodexAuth` | 认证管理 |
| `AnalyticsEventsClient` | 分析事件发送 |

---

## 依赖与外部交互

### 外部服务

| 服务 | 接口 | 用途 |
|------|------|------|
| ChatGPT API | `GET /plugins/list` | 获取远程插件状态 |
| ChatGPT API | `GET /plugins/featured` | 获取精选插件 ID |
| ChatGPT API | `POST /plugins/{id}/enable` | 启用远程插件 |
| ChatGPT API | `POST /plugins/{id}/uninstall` | 卸载远程插件 |
| GitHub API | (通过 curated_repo) | 下载精选仓库 |

### 文件系统交互

| 路径 | 用途 |
|------|------|
| `{codex_home}/plugins/cache/` | 插件缓存根目录 |
| `{codex_home}/plugins/cache/{marketplace}/{plugin}/{version}/` | 插件安装目录 |
| `{codex_home}/.tmp/plugins/` | 精选仓库本地副本 |
| `{codex_home}/.tmp/plugins.sha` | 精选仓库版本记录 |
| `{plugin_root}/.codex-plugin/plugin.json` | 插件 manifest |
| `{plugin_root}/skills/` | 默认技能目录 |
| `{plugin_root}/.mcp.json` | 默认 MCP 配置 |
| `{plugin_root}/.app.json` | 默认应用配置 |

### 配置键

```toml
[features]
plugins = true

[plugins]
[plugins."slack@openai-curated"]
enabled = true
```

---

## 风险、边界与改进建议

### 已知风险

1. **并发安全**
   - `RwLock` 用于缓存，但 Poison 处理使用 `into_inner()` 可能不安全
   - 精选仓库同步使用 `AtomicBool`，但无进程级锁
   - **建议**：考虑使用 `parking_lot` 的锁，或增加文件锁

2. **性能问题**
   - 插件加载涉及多次文件 IO
   - 每次 `plugins_for_config()` 都重新加载（除非缓存命中）
   - **建议**：增加文件系统监听，实现增量更新

3. **远程同步一致性**
   - 远程 `enabled = false` 被视为卸载而非禁用
   - 注释中提到 TODO：切换到 `plugins/installed` 端点
   - **建议**：尽快实现真正的启用/禁用状态同步

4. **错误处理**
   - 插件加载错误仅记录警告，用户无感知
   - **建议**：增加插件状态 UI 展示

### 边界条件

| 场景 | 当前行为 |
|------|---------|
| Plugins 功能禁用 | 返回空结果或错误 |
| 精选市场不存在 | 远程同步返回 `LocalMarketplaceNotFound` |
| 插件 manifest 损坏 | 记录错误，插件标记为 error 状态 |
| MCP 配置解析失败 | 记录警告，跳过该配置 |
| 重复 MCP 服务器名 | 后加载的覆盖先加载的 |
| 缓存 Poison | 使用 `into_inner()` 尝试恢复 |

### 改进建议

1. **异步化**
   - 当前多处使用 `spawn_blocking` 包裹同步 IO
   - **建议**：使用 `tokio::fs` 实现真正的异步文件操作

2. **增量更新**
   - 当前缓存无过期策略（除精选插件 ID）
   - **建议**：增加文件系统监听，实现实时更新

3. **插件依赖**
   - 当前无插件间依赖机制
   - **建议**：增加依赖声明和自动安装

4. **版本管理**
   - 当前非精选插件使用 "local" 版本
   - **建议**：支持版本号管理和自动更新

5. **遥测增强**
   - 当前仅记录安装/卸载事件
   - **建议**：增加加载时间、错误率等指标

### 测试建议

测试文件：`manager_tests.rs`

**待补充测试**：
- 并发安装/卸载场景
- 缓存 Poison 恢复
- 远程同步网络失败
- 大数量插件加载性能
- 配置编辑冲突处理
