# Plugin System Research Document

## Directory Overview

The `codex-rs/core/src/plugins` directory implements the plugin system for Codex CLI, providing a comprehensive framework for managing, installing, and executing plugins that extend Codex's capabilities through skills, MCP servers, and app connectors.

---

## 1. 场景与职责

### 1.1 核心场景

The plugin system serves several key scenarios:

1. **Plugin Discovery & Installation**: Users can discover plugins from marketplaces (local or remote) and install them into their local Codex environment
2. **Plugin Lifecycle Management**: Handle plugin enable/disable states, version management, and uninstallation
3. **Capability Integration**: Plugins provide three types of capabilities:
   - **Skills**: Reusable prompt templates and instructions (loaded from `skills/` directory or configured paths)
   - **MCP Servers**: Model Context Protocol servers for tool execution (configured in `.mcp.json`)
   - **App Connectors**: Integration with external applications (configured in `.app.json`)
4. **Remote Sync**: Synchronize plugin states with ChatGPT backend for curated marketplace plugins
5. **Tool Suggestions**: Provide discoverable plugin recommendations based on user context

### 1.2 模块职责划分

| Module | Responsibility |
|--------|---------------|
| `mod.rs` | Public API exports and module organization |
| `manager.rs` | Central plugin management (install, uninstall, load, sync) |
| `store.rs` | Local filesystem storage for installed plugins |
| `marketplace.rs` | Marketplace discovery and plugin resolution |
| `manifest.rs` | Plugin manifest parsing (`plugin.json`) |
| `remote.rs` | Remote ChatGPT backend communication |
| `curated_repo.rs` | OpenAI curated plugins repository sync from GitHub |
| `discoverable.rs` | Tool suggestion discoverable plugins listing |
| `injection.rs` | Plugin context injection into model prompts |
| `render.rs` | Plugin instruction rendering for model context |
| `toggles.rs` | Plugin enable/disable state tracking from config edits |
| `test_support.rs` | Test utilities for plugin system |

---

## 2. 功能点目的

### 2.1 Plugin Identification (`store.rs`)

**Purpose**: Establish unique plugin identity across the system.

```rust
pub struct PluginId {
    pub plugin_name: String,
    pub marketplace_name: String,
}
// Key format: "{plugin_name}@{marketplace_name}"
```

- Validates plugin names/marketplace names (alphanumeric, `-`, `_` only)
- Parses from/serializes to string keys for config storage

### 2.2 Plugin Storage (`store.rs`)

**Purpose**: Atomic plugin installation with versioning support.

Storage layout:
```
{codex_home}/plugins/cache/
  {marketplace_name}/
    {plugin_name}/
      {version}/          # "local" for non-curated, SHA for curated
        .codex-plugin/
          plugin.json
        skills/
        .mcp.json
        .app.json
```

Key features:
- Atomic installation using temp directories and rename operations
- Backup/rollback on installation failure
- Version detection for curated plugins (single version = active)

### 2.3 Marketplace System (`marketplace.rs`)

**Purpose**: Plugin discovery and metadata resolution.

Marketplace structure:
```json
{
  "name": "openai-curated",
  "interface": { "displayName": "OpenAI Curated" },
  "plugins": [{
    "name": "github",
    "source": { "source": "local", "path": "./plugins/github" },
    "policy": {
      "installation": "AVAILABLE",
      "authentication": "ON_INSTALL",
      "products": ["CODEX_CLI"]
    }
  }]
}
```

Discovery paths:
1. `~/.agents/plugins/marketplace.json` (user home)
2. `{additional_roots}/.agents/plugins/marketplace.json`
3. Git repo root discovery for marketplace files

### 2.4 Manifest System (`manifest.rs`)

**Purpose**: Plugin self-description and capability declaration.

Manifest location: `.codex-plugin/plugin.json`

```rust
pub struct PluginManifest {
    pub name: String,
    pub description: Option<String>,
    pub paths: PluginManifestPaths,      // skills, mcp_servers, apps paths
    pub interface: Option<PluginManifestInterface>,  // UI metadata
}
```

Interface fields include: display_name, descriptions, developer info, category, capabilities, URLs, default prompts, brand colors, icons, logos, screenshots.

**Security**: Path validation ensures all paths start with `./` and contain no `..` components.

### 2.5 Remote Sync (`remote.rs`)

**Purpose**: Keep local plugin state synchronized with ChatGPT backend.

API endpoints:
- `GET /plugins/list` - Fetch user's enabled plugins
- `GET /plugins/featured` - Fetch featured plugin IDs
- `POST /plugins/{id}/enable` - Enable plugin remotely
- `POST /plugins/{id}/uninstall` - Uninstall plugin remotely

Authentication: Requires ChatGPT auth (not API key), uses bearer tokens with account ID headers.

### 2.6 Curated Repository Sync (`curated_repo.rs`)

**Purpose**: Download and cache OpenAI's official curated plugins from GitHub.

Process:
1. Fetch repository default branch from GitHub API
2. Get HEAD SHA for that branch
3. Download zipball archive
4. Extract to temp directory
5. Atomic move to `~/.codex/.tmp/plugins/`
6. Write SHA to `~/.codex/.tmp/plugins.sha`

Version tracking: Uses Git SHA as version identifier for curated plugins.

### 2.7 Plugin Loading (`manager.rs`)

**Purpose**: Load enabled plugins and extract their capabilities.

Loading flow:
1. Read plugin configs from user config layer
2. For each enabled plugin:
   - Resolve plugin root from store
   - Parse manifest
   - Discover skill roots (default: `skills/` dir, or manifest path)
   - Load MCP servers (default: `.mcp.json`, or manifest path)
   - Load app connectors (default: `.app.json`, or manifest path)
3. Aggregate capabilities across all active plugins
4. Handle duplicate MCP server names (first wins with warning)

### 2.8 Context Injection (`injection.rs`, `render.rs`)

**Purpose**: Provide plugin context to the model when plugins are explicitly mentioned.

Renders:
- Plugin capability summaries (skills, MCP servers, apps available)
- Explicit plugin instructions when user mentions a plugin
- Format: Markdown with special XML tags for model consumption

---

## 3. 具体技术实现

### 3.1 关键数据结构

#### Plugin Load Outcome
```rust
pub struct PluginLoadOutcome {
    plugins: Vec<LoadedPlugin>,
    capability_summaries: Vec<PluginCapabilitySummary>,
}

pub struct LoadedPlugin {
    pub config_name: String,           // "plugin@marketplace"
    pub manifest_name: Option<String>, // from plugin.json
    pub manifest_description: Option<String>,
    pub root: AbsolutePathBuf,
    pub enabled: bool,
    pub skill_roots: Vec<PathBuf>,
    pub mcp_servers: HashMap<String, McpServerConfig>,
    pub apps: Vec<AppConnectorId>,
    pub error: Option<String>,
}
```

#### Plugin Capability Summary
```rust
pub struct PluginCapabilitySummary {
    pub config_name: String,
    pub display_name: String,
    pub description: Option<String>,
    pub has_skills: bool,
    pub mcp_server_names: Vec<String>,
    pub app_connector_ids: Vec<AppConnectorId>,
}
```

### 3.2 关键流程

#### Installation Flow
```
PluginInstallRequest
    ↓
resolve_marketplace_plugin() → ResolvedMarketplacePlugin
    ↓
[Optional] enable_remote_plugin() → ChatGPT backend
    ↓
PluginStore::install_with_version()
    ├── Validate source is directory
    ├── Verify manifest name matches
    ├── Validate version string
    └── replace_plugin_root_atomically()
        ├── Copy to temp staging dir
        ├── Backup existing if present
        ├── Rename staging to target
        └── Rollback on failure
    ↓
ConfigService::write_value() → Enable in config
    ↓
Analytics tracking
```

#### Remote Sync Flow
```
sync_plugins_from_remote()
    ↓
fetch_remote_plugin_status() → Vec<RemotePluginStatusSummary>
    ↓
Load local curated marketplace
    ↓
For each plugin in curated marketplace:
    ├── Check if in remote enabled list
    ├── If should be enabled but not installed → install
    ├── If should be enabled but disabled in config → enable
    └── If should be disabled but installed/configured → uninstall/remove
    ↓
Batch apply config edits
    ↓
Return RemotePluginSyncResult
```

#### Plugin Loading Flow
```
plugins_for_config()
    ↓
Check Feature::Plugins enabled
    ↓
Check cache (if not force_reload)
    ↓
load_plugins_from_layer_stack()
    ├── configured_plugins_from_stack() → HashMap<plugin_key, PluginConfig>
    ├── Sort by key for deterministic loading
    └── For each plugin: load_plugin()
        ├── Parse PluginId from config_name
        ├── Resolve plugin root from store
        ├── Parse manifest
        ├── plugin_skill_roots() → merge default + manifest paths
        ├── plugin_mcp_config_paths() → load MCP servers
        └── load_plugin_apps() → load app connectors
    ↓
Filter and collect capability summaries
    ↓
Cache result
```

### 3.3 协议与接口

#### MCP Server Configuration (`.mcp.json`)
```json
{
  "mcpServers": {
    "server-name": {
      "type": "http" | "stdio" | "streamable_http",
      "url": "https://...",
      "oauth": { "clientId": "..." },
      "cwd": "./relative/path"
    }
  }
}
```

Normalization:
- Relative `cwd` paths resolved against plugin root
- OAuth `callbackPort` ignored (uses global settings)
- Transport type validation

#### App Configuration (`.app.json`)
```json
{
  "apps": {
    "app-key": {
      "id": "connector_id"
    }
  }
}
```

### 3.4 缓存机制

#### Featured Plugin IDs Cache
- TTL: 3 hours (`FEATURED_PLUGIN_IDS_CACHE_TTL`)
- Key: `(chatgpt_base_url, account_id, chatgpt_user_id, is_workspace_account)`
- Purpose: Reduce backend calls for featured plugin listing

#### Enabled Plugin Outcome Cache
- In-memory only (RwLock)
- Cleared on: config changes, plugin install/uninstall, remote sync
- Purpose: Avoid re-loading plugins on every turn

---

## 4. 关键代码路径与文件引用

### 4.1 Entry Points

| Operation | File | Function |
|-----------|------|----------|
| Install plugin | `manager.rs:599` | `PluginsManager::install_plugin()` |
| Uninstall plugin | `manager.rs:685` | `PluginsManager::uninstall_plugin()` |
| Sync from remote | `manager.rs:738` | `PluginsManager::sync_plugins_from_remote()` |
| List marketplaces | `manager.rs:925` | `PluginsManager::list_marketplaces_for_config()` |
| Read plugin details | `manager.rs:976` | `PluginsManager::read_plugin_for_config()` |
| Load plugins | `manager.rs:486` | `PluginsManager::plugins_for_config()` |
| Start curated sync | `manager.rs:1053` | `PluginsManager::maybe_start_curated_repo_sync_for_config()` |

### 4.2 Core Implementation Files

| File | Lines | Purpose |
|------|-------|---------|
| `manager.rs` | ~1720 | Central plugin management, loading, and coordination |
| `store.rs` | ~345 | Filesystem storage, atomic installation |
| `marketplace.rs` | ~456 | Marketplace discovery and resolution |
| `manifest.rs` | ~477 | Plugin manifest parsing |
| `remote.rs` | ~307 | ChatGPT backend communication |
| `curated_repo.rs` | ~356 | GitHub repository sync |

### 4.3 Supporting Files

| File | Purpose |
|------|---------|
| `discoverable.rs` | Tool suggestion integration |
| `injection.rs` | Model context injection |
| `render.rs` | Instruction formatting |
| `toggles.rs` | Config edit tracking |
| `test_support.rs` | Test fixtures and helpers |

### 4.4 Test Files

| File | Coverage |
|------|----------|
| `manager_tests.rs` | Plugin loading, MCP normalization, telemetry, sync |
| `store_tests.rs` | Installation, versioning, path resolution |
| `marketplace_tests.rs` | Marketplace loading, plugin resolution |
| `curated_repo_tests.rs` | Repository sync, SHA tracking |
| `discoverable_tests.rs` | Tool suggestion filtering |
| `render_tests.rs` | Instruction rendering |

---

## 5. 依赖与外部交互

### 5.1 Internal Dependencies

```
plugins/
  ├── config/           # Config reading, ConfigService for edits
  ├── config_loader/    # ConfigLayerStack for plugin configs
  ├── features.rs       # Feature::Plugins gating
  ├── skills/           # Skill loading from plugin roots
  ├── mcp/              # MCP server configuration types
  ├── mcp_connection_manager/  # Tool info for injection
  ├── connectors.rs     # App connector integration
  ├── auth/             # CodexAuth for remote sync
  ├── analytics_client/ # Plugin install/uninstall telemetry
  └── git_info.rs       # Repository root discovery
```

### 5.2 External Dependencies

| Crate | Usage |
|-------|-------|
| `reqwest` | HTTP client for remote sync, GitHub API |
| `serde_json` | Manifest and marketplace parsing |
| `zip` | Curated repository archive extraction |
| `tempfile` | Atomic installation staging |
| `tokio` | Async runtime for remote operations |
| `tracing` | Structured logging |
| `codex_app_server_protocol` | Protocol types for app integration |
| `codex_protocol` | SkillScope, protocol constants |
| `codex_utils_absolute_path` | AbsolutePathBuf for path safety |

### 5.3 External Services

| Service | Purpose |
|---------|---------|
| GitHub API | Fetch curated plugins repository (zipball, refs) |
| ChatGPT Backend | Remote plugin status sync, featured plugins |

---

## 6. 风险、边界与改进建议

### 6.1 Security Considerations

1. **Path Traversal Prevention**
   - All plugin paths validated to start with `./`
   - `..` components rejected
   - Only `Component::Normal` allowed in relative paths
   - See: `manifest.rs:332-373`, `marketplace.rs:316-357`

2. **Atomic Operations**
   - Plugin installation uses temp directories + rename
   - Backup created before replacing existing plugins
   - Rollback on failure
   - See: `store.rs:250-315`

3. **Auth Requirements**
   - Remote sync requires ChatGPT auth (not API key)
   - Bearer tokens used for backend communication
   - Account ID headers for workspace support

### 6.2 Known Limitations

1. **Single Curated Marketplace**
   - Hardcoded to `openai-curated` marketplace name
   - Remote sync only works with OpenAI curated plugins
   - See: `manager.rs:765`, `remote.rs:8`

2. **Version Management**
   - Only curated plugins use versioned storage (Git SHA)
   - Third-party plugins use "local" version
   - No automatic updates for non-curated plugins

3. **Cache Invalidation**
   - Featured plugin cache has fixed 3-hour TTL
   - No manual cache invalidation mechanism
   - Plugin outcome cache cleared on config changes

4. **MCP Server Conflicts**
   - Duplicate MCP server names across plugins: first wins
   - Warning logged but no user-facing error
   - See: `manager.rs:1283-1297`

### 6.3 Error Handling

| Error Type | Handling |
|------------|----------|
| `PluginInstallError` | Categorized into invalid request vs internal error via `is_invalid_request()` |
| `PluginRemoteSyncError` | Auth errors, network errors, decode errors with context |
| `MarketplaceError` | Not found, invalid file, plugin not found/available |
| `PluginStoreError` | IO errors with context, validation errors |

### 6.4 Improvement Suggestions

1. **Multi-Marketplace Support**
   - Extend remote sync to support multiple curated marketplaces
   - Allow third-party marketplace registration

2. **Plugin Updates**
   - Version comparison for curated plugins
   - Update notifications/changelog display
   - Automatic update option

3. **Better Conflict Resolution**
   - UI for resolving MCP server name conflicts
   - Namespace isolation option

4. **Plugin Isolation**
   - Sandboxed plugin execution
   - Resource limits per plugin

5. **Cache Improvements**
   - Configurable cache TTL
   - Manual cache refresh command
   - ETag-based conditional requests

6. **Developer Experience**
   - Plugin validation CLI command
   - Local marketplace development server
   - Plugin template generator

---

## 7. Configuration Integration

### 7.1 Config Structure

```toml
[features]
plugins = true  # Enable plugin system

[plugins]  # Plugin-specific settings (reserved for future)

# Per-plugin config (user layer only)
[plugins."plugin-name@marketplace-name"]
enabled = true
```

### 7.2 Feature Gating

- `Feature::Plugins` controls entire plugin system
- Disabled: Empty outcomes, no marketplace listing
- See: `features.rs:154`, `manager.rs:495-496`

---

## 8. Testing Strategy

### 8.1 Test Categories

1. **Unit Tests**: Individual module testing with mocks
2. **Integration Tests**: Full plugin lifecycle with temp directories
3. **Snapshot Tests**: Rendered output validation (insta)

### 8.2 Test Utilities (`test_support.rs`)

- `write_curated_plugin()` - Create test plugin structure
- `write_openai_curated_marketplace()` - Create test marketplace
- `write_curated_plugin_sha()` - Simulate synced state
- `load_plugins_config()` - Async config loading for tests

### 8.3 Key Test Scenarios

- Plugin loading with default and custom paths
- MCP server normalization (OAuth, cwd resolution)
- Telemetry metadata extraction
- Capability summary generation
- Remote sync with mock backend
- Marketplace discovery and deduplication

---

*Document generated: 2026-03-21*
*Research scope: codex-rs/core/src/plugins/*
