# plugin_list.rs 研究文档

## 场景与职责

`plugin_list.rs` 是 Codex App Server v2 API 的集成测试文件，专注于**插件列表（Plugin List）**功能的端到端测试。插件系统允许 Codex 扩展功能，通过市场（Marketplace）机制分发和管理插件。该测试文件验证插件发现、状态查询、远程同步等核心功能。

该测试文件的核心职责包括：
1. 验证插件市场发现和解析
2. 验证插件安装和启用状态查询
3. 验证配置层叠（home vs workspace）对插件状态的影响
4. 验证远程插件同步（与 ChatGPT 后端集成）
5. 验证精选插件 ID 的获取和缓存

## 功能点目的

### 1. 无效市场文件处理 (`plugin_list_skips_invalid_marketplace_file`)
- **目的**：验证当 `marketplace.json` 格式无效时，系统优雅跳过而非崩溃
- **业务价值**：提高系统健壮性，防止单个错误配置影响整体功能
- **关键验证点**：
  - 无效 JSON（如 `{not json`）被跳过
  - 其他有效市场仍正常返回

### 2. 相对路径拒绝 (`plugin_list_rejects_relative_cwds`)
- **目的**：验证 `cwds` 参数必须是绝对路径
- **业务价值**：防止路径遍历和不确定性行为
- **关键验证点**：
  - 相对路径返回 `-32600` 错误
  - 错误消息包含 `Invalid request`

### 3. 省略 cwds 参数 (`plugin_list_accepts_omitted_cwds`)
- **目的**：验证 `cwds` 参数可选，省略时使用默认行为
- **业务价值**：简化客户端调用，支持常见用例
- **关键验证点**：
  - `cwds: None` 时调用成功
  - 返回插件列表响应

### 4. 插件状态查询 (`plugin_list_includes_install_and_enabled_state_from_config`)
- **目的**：验证插件列表包含安装状态、启用状态、安装策略和认证策略
- **业务价值**：客户端可以展示完整的插件管理界面
- **关键验证点**：
  - `installed`：是否已下载到本地缓存
  - `enabled`：是否在配置中启用
  - `install_policy`：安装策略（Available、Required 等）
  - `auth_policy`：认证策略（OnInstall、OnUse 等）
  - 插件 ID 格式：`{name}@{marketplace_name}`

### 5. 配置层叠 (`plugin_list_uses_home_config_for_enabled_state`)
- **目的**：验证插件启用状态优先使用 home 配置而非 workspace 配置
- **业务价值**：确保跨工作空间的插件设置一致性
- **关键验证点**：
  - 同一插件在 workspace A 禁用、workspace B 默认时
  - 使用 home 配置中的启用状态

### 6. 插件界面和资产路径 (`plugin_list_returns_plugin_interface_with_absolute_asset_paths`)
- **目的**：验证插件界面元数据和资产路径正确解析为绝对路径
- **业务价值**：客户端可以正确显示插件图标、截图等
- **关键验证点**：
  - `display_name`, `category`, `website_url` 等元数据
  - `composer_icon`, `logo`, `screenshots` 解析为绝对路径
  - 相对路径基于插件根目录解析

### 7. 向后兼容 (`plugin_list_accepts_legacy_string_default_prompt`)
- **目的**：验证 `defaultPrompt` 字段支持字符串（旧格式）和字符串数组（新格式）
- **业务价值**：保持向后兼容，支持旧插件
- **关键验证点**：
  - 字符串 `"prompt"` 转换为 `["prompt"]`
  - 数组保持不变

### 8. 远程同步失败处理 (`plugin_list_force_remote_sync_returns_remote_sync_error_on_fail_open`)
- **目的**：验证远程同步失败时返回错误但不中断流程
- **业务价值**：优雅处理网络问题或认证过期
- **关键验证点**：
  - `force_remote_sync: true` 时尝试同步
  - 认证失败时 `remote_sync_error` 包含错误信息
  - 本地插件列表仍正常返回

### 9. 远程同步成功 (`plugin_list_force_remote_sync_reconciles_curated_plugin_state`)
- **目的**：验证远程同步成功时更新插件状态和本地缓存
- **业务价值**：保持本地状态与 ChatGPT 账户同步
- **关键验证点**：
  - 调用远程 `/plugins/list` 和 `/plugins/featured` 端点
  - 更新插件启用状态（以远程为准）
  - 更新配置文件
  - 清理已卸载插件的本地缓存

### 10. 精选插件 ID 获取 (`plugin_list_fetches_featured_plugin_ids_without_chatgpt_auth`)
- **目的**：验证无需 ChatGPT 认证即可获取精选插件列表
- **业务价值**：支持匿名用户发现推荐插件
- **关键验证点**：
  - 调用 `/plugins/featured` 端点
  - 返回精选插件 ID 列表

### 11. 精选插件缓存 (`plugin_list_uses_warmed_featured_plugin_ids_cache_on_first_request`)
- **目的**：验证精选插件列表在初始化时预加载并缓存
- **业务价值**：减少首次请求的延迟
- **关键验证点**：
  - 初始化时自动获取精选插件
  - 首次 `plugin/list` 请求使用缓存数据
  - 仅一次 HTTP 请求

## 具体技术实现

### 核心数据结构

#### PluginListParams（请求参数）
```rust
pub struct PluginListParams {
    #[ts(optional = nullable)]
    pub cwds: Option<Vec<AbsolutePathBuf>>,  // 工作目录列表
    pub force_remote_sync: bool,              // 是否强制远程同步
}
```

#### PluginListResponse（响应）
```rust
pub struct PluginListResponse {
    pub marketplaces: Vec<ConfiguredMarketplace>,
    pub featured_plugin_ids: Vec<String>,
    pub remote_sync_error: Option<String>,
}
```

#### ConfiguredMarketplace（配置的市场）
```rust
pub struct ConfiguredMarketplace {
    pub name: String,
    pub path: AbsolutePathBuf,
    pub interface: Option<MarketplaceInterface>,
    pub plugins: Vec<ConfiguredMarketplacePlugin>,
}
```

#### ConfiguredMarketplacePlugin（市场插件）
```rust
pub struct ConfiguredMarketplacePlugin {
    pub id: String,                    // 格式: "{name}@{marketplace}"
    pub name: String,
    pub source: MarketplacePluginSource,
    pub policy: MarketplacePluginPolicy,
    pub interface: Option<PluginManifestInterface>,
    pub installed: bool,
    pub enabled: bool,
}
```

### 插件状态管理

#### 状态来源
| 状态 | 来源 |
|-----|------|
| installed | 本地文件系统检查（`plugins/cache/{marketplace}/{plugin}`） |
| enabled | 配置合并（home config > workspace config） |
| install_policy | `marketplace.json` 中的 `policy.installation` |
| auth_policy | `marketplace.json` 中的 `policy.authentication` |

#### 配置层叠优先级
```
1. Home config (~/.codex/config.toml)
2. Workspace config (.codex/config.toml)
3. 默认值（false）
```

### 远程同步流程

```
plugin/list (force_remote_sync: true)
    |
    v
检查 ChatGPT 认证
    |
    +-- 未认证 --> remote_sync_error = "chatgpt authentication required"
    |
    +-- 已认证 --> 调用 /plugins/list
                       |
                       v
                   获取远程插件状态
                       |
                       v
                   更新本地配置
                       |
                       v
                   清理已卸载插件缓存
                       |
                       v
                   调用 /plugins/featured
                       |
                       v
                   返回更新后的插件列表
```

### 精选插件缓存

#### 缓存键
```rust
struct FeaturedPluginIdsCacheKey {
    chatgpt_base_url: String,
    account_id: Option<String>,
    chatgpt_user_id: Option<String>,
    is_workspace_account: bool,
}
```

#### 缓存 TTL
- 默认：3 小时（`FEATURED_PLUGIN_IDS_CACHE_TTL = Duration::from_secs(60 * 60 * 3)`）

## 关键代码路径与文件引用

### 协议定义
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | `PluginListParams`, `PluginListResponse`, `ConfiguredMarketplace` 等定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | `ClientRequest::PluginList` 枚举 |

### 核心实现
| 文件 | 说明 |
|------|------|
| `codex-rs/core/src/plugins/manager.rs` | `PluginsManager::list_plugins()` 实现 |
| `codex-rs/core/src/plugins/marketplace.rs` | 市场发现和解析 |
| `codex-rs/core/src/plugins/store.rs` | 插件存储和缓存管理 |
| `codex-rs/core/src/plugins/remote.rs` | 远程插件同步 |

### API 实现
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/src/message_processor.rs` | `plugin/list` 请求处理 |
| `codex-rs/app-server/src/codex_message_processor.rs` | 插件列表查询实现 |

### 测试支持
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/tests/common/mcp_process.rs` | `send_plugin_list_request` 辅助方法 |

## 依赖与外部交互

### 内部依赖
```rust
use codex_app_server_protocol::{
    PluginAuthPolicy, PluginInstallPolicy, PluginListParams,
    PluginListResponse, JSONRPCResponse, RequestId,
};
use codex_core::auth::AuthCredentialsStoreMode;
use codex_core::config::set_project_trust_level;
use codex_protocol::config_types::TrustLevel;
use codex_utils_absolute_path::AbsolutePathBuf;
```

### 外部依赖
- **wiremock**：模拟 ChatGPT 后端 API
- **tempfile**：临时目录管理
- **tokio**：异步运行时

### 测试辅助函数

#### `write_installed_plugin`
创建模拟的已安装插件目录结构：
```
{codex_home}/plugins/cache/{marketplace}/{plugin}/local/.codex-plugin/plugin.json
```

#### `write_plugin_sync_config`
写入支持远程同步的配置：
```toml
chatgpt_base_url = "..."

[features]
plugins = true

[plugins."{plugin}@{marketplace}"]
enabled = {true|false}
```

#### `write_openai_curated_marketplace`
创建 OpenAI 精选市场的模拟数据

## 风险、边界与改进建议

### 风险点

1. **远程同步可靠性**
   - 依赖 ChatGPT 后端可用性
   - 网络故障可能导致同步失败
   - **建议**：实现指数退避重试机制

2. **缓存一致性**
   - 精选插件缓存 3 小时可能过长
   - 用户在其他设备上更改可能不及时同步
   - **建议**：提供手动刷新选项或更短的 TTL

3. **配置冲突**
   - home 和 workspace 配置可能冲突
   - 当前优先使用 home 配置
   - **建议**：提供更明确的配置优先级文档

### 边界情况

1. **大量插件**
   - 测试使用少量插件（3-5 个）
   - **风险**：大量插件（100+）时性能可能下降
   - **建议**：添加分页支持和性能测试

2. **循环依赖**
   - 市场 JSON 可能包含循环引用
   - **风险**：解析时可能无限递归
   - **建议**：添加循环引用检测

3. **并发修改**
   - 测试为单线程
   - **风险**：并发调用可能导致竞态条件
   - **建议**：添加并发安全测试

4. **磁盘空间**
   - 插件缓存可能占用大量空间
   - **风险**：磁盘满时操作失败
   - **建议**：添加磁盘空间检查和清理策略

### 改进建议

1. **增量同步**
   - 当前全量获取插件列表
   - **建议**：支持基于 ETag 或时间戳的增量同步

2. **离线支持**
   - 当前远程同步失败时仅返回错误
   - **建议**：提供离线模式，使用缓存数据

3. **插件搜索**
   - 当前仅支持列表获取
   - **建议**：添加搜索和过滤功能

4. **版本管理**
   - 当前插件版本管理简单
   - **建议**：支持多版本共存和自动更新

5. **遥测**
   - 记录插件使用统计
   - 帮助改进推荐算法

6. **安全扫描**
   - 安装前扫描插件代码
   - 防止恶意插件
