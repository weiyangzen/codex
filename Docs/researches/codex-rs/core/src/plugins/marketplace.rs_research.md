# marketplace.rs 深度研究文档

## 场景与职责

`marketplace.rs` 是 Codex 插件系统的市场管理模块，负责插件市场的发现、加载和解析。市场（Marketplace）是插件的集合，定义在 `marketplace.json` 文件中，通常位于 `.agents/plugins/` 目录下。

### 核心职责

1. **市场发现**：从多个根目录（home 目录、git 仓库根目录）发现市场配置文件
2. **市场加载**：解析 `marketplace.json` 文件，加载市场元数据和插件列表
3. **插件解析**：解析市场中的插件定义，包括来源、策略和界面信息
4. **路径解析**：将相对路径解析为绝对路径，确保安全的路径处理

## 功能点目的

### 1. 核心数据结构

#### `Marketplace` - 市场定义

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Marketplace {
    pub name: String,                           // 市场名称
    pub path: AbsolutePathBuf,                  // 市场文件路径
    pub interface: Option<MarketplaceInterface>, // 市场界面配置
    pub plugins: Vec<MarketplacePlugin>,        // 插件列表
}
```

#### `MarketplacePlugin` - 市场中的插件

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MarketplacePlugin {
    pub name: String,                           // 插件名称
    pub source: MarketplacePluginSource,        // 插件来源
    pub policy: MarketplacePluginPolicy,        // 插件策略
    pub interface: Option<PluginManifestInterface>, // 界面配置（来自 manifest）
}
```

#### `MarketplacePluginSource` - 插件来源

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MarketplacePluginSource {
    Local { path: AbsolutePathBuf },           // 本地路径来源
}
```

目前仅支持本地路径来源，未来可能扩展支持远程 URL。

#### `MarketplacePluginPolicy` - 插件策略

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MarketplacePluginPolicy {
    pub installation: MarketplacePluginInstallPolicy,   // 安装策略
    pub authentication: MarketplacePluginAuthPolicy,    // 认证策略
    pub products: Vec<Product>,                         // 产品限制
}
```

### 2. 安装策略

```rust
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Deserialize)]
pub enum MarketplacePluginInstallPolicy {
    #[serde(rename = "NOT_AVAILABLE")]
    NotAvailable,           // 不可安装
    #[default]
    #[serde(rename = "AVAILABLE")]
    Available,              // 可安装（默认）
    #[serde(rename = "INSTALLED_BY_DEFAULT")]
    InstalledByDefault,     // 默认安装
}
```

### 3. 认证策略

```rust
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Deserialize)]
pub enum MarketplacePluginAuthPolicy {
    #[default]
    #[serde(rename = "ON_INSTALL")]
    OnInstall,              // 安装时认证（默认）
    #[serde(rename = "ON_USE")]
    OnUse,                  // 使用时认证
}
```

### 4. 协议转换

市场策略类型可以转换为 app-server 协议类型：

```rust
impl From<MarketplacePluginInstallPolicy> for PluginInstallPolicy {
    fn from(value: MarketplacePluginInstallPolicy) -> Self {
        match value {
            MarketplacePluginInstallPolicy::NotAvailable => Self::NotAvailable,
            MarketplacePluginInstallPolicy::Available => Self::Available,
            MarketplacePluginInstallPolicy::InstalledByDefault => Self::InstalledByDefault,
        }
    }
}

impl From<MarketplacePluginAuthPolicy> for PluginAuthPolicy {
    fn from(value: MarketplacePluginAuthPolicy) -> Self {
        match value {
            MarketplacePluginAuthPolicy::OnInstall => Self::OnInstall,
            MarketplacePluginAuthPolicy::OnUse => Self::OnUse,
        }
    }
}
```

## 具体技术实现

### 市场发现

```rust
const MARKETPLACE_RELATIVE_PATH: &str = ".agents/plugins/marketplace.json";

pub fn list_marketplaces(
    additional_roots: &[AbsolutePathBuf],
) -> Result<Vec<Marketplace>, MarketplaceError> {
    list_marketplaces_with_home(additional_roots, home_dir().as_deref())
}
```

发现顺序：
1. Home 目录：`~/.agents/plugins/marketplace.json`
2. 额外根目录：直接检查路径
3. Git 仓库根目录：通过 `get_git_repo_root()` 查找

### 插件解析

```rust
pub fn resolve_marketplace_plugin(
    marketplace_path: &AbsolutePathBuf,
    plugin_name: &str,
) -> Result<ResolvedMarketplacePlugin, MarketplaceError> {
    let marketplace = load_raw_marketplace_manifest(marketplace_path)?;
    // 查找插件
    let plugin = marketplace.plugins.into_iter().find(|p| p.name == plugin_name);
    // 检查安装策略
    if install_policy == MarketplacePluginInstallPolicy::NotAvailable {
        return Err(MarketplaceError::PluginNotAvailable { ... });
    }
    // 解析插件 ID 和来源路径
    let plugin_id = PluginId::new(name, marketplace_name)?;
    Ok(ResolvedMarketplacePlugin {
        plugin_id,
        source_path: resolve_plugin_source_path(marketplace_path, source)?,
        auth_policy: policy.authentication,
    })
}
```

### 路径解析安全

插件来源路径必须遵循严格的安全规则：

```rust
fn resolve_plugin_source_path(
    marketplace_path: &AbsolutePathBuf,
    source: RawMarketplaceManifestPluginSource,
) -> Result<AbsolutePathBuf, MarketplaceError> {
    match source {
        RawMarketplaceManifestPluginSource::Local { path } => {
            // 必须以 ./ 开头
            let Some(path) = path.strip_prefix("./") else {
                return Err(MarketplaceError::InvalidMarketplaceFile { ... });
            };
            // 禁止 .. 组件
            if relative_source_path.components().any(|c| !matches!(c, Component::Normal(_))) {
                return Err(MarketplaceError::InvalidMarketplaceFile { ... });
            }
            // 解析相对于市场根目录（marketplace.json 的父目录的父目录的父目录）
            marketplace_root_dir(marketplace_path)?.join(relative_source_path)
        }
    }
}
```

### 市场根目录计算

```rust
fn marketplace_root_dir(
    marketplace_path: &AbsolutePathBuf,
) -> Result<AbsolutePathBuf, MarketplaceError> {
    // marketplace.json 必须位于 <root>/.agents/plugins/marketplace.json
    let Some(plugins_dir) = marketplace_path.parent() else { ... };
    let Some(dot_agents_dir) = plugins_dir.parent() else { ... };
    let Some(marketplace_root) = dot_agents_dir.parent() else { ... };
    
    // 验证目录结构
    if plugins_dir.file_name() != Some("plugins") 
        || dot_agents_dir.file_name() != Some(".agents") {
        return Err(MarketplaceError::InvalidMarketplaceFile { ... });
    }
    Ok(marketplace_root)
}
```

### 市场加载流程

```rust
pub(crate) fn load_marketplace(path: &AbsolutePathBuf) -> Result<Marketplace, MarketplaceError> {
    let marketplace = load_raw_marketplace_manifest(path)?;
    let mut plugins = Vec::new();

    for plugin in marketplace.plugins {
        // 解析来源路径
        let source_path = resolve_plugin_source_path(path, source)?;
        let source = MarketplacePluginSource::Local { path: source_path.clone() };
        
        // 加载插件 manifest 获取界面信息
        let mut interface = load_plugin_manifest(source_path.as_path())
            .and_then(|manifest| manifest.interface);
        
        // 市场分类覆盖 manifest 分类
        if let Some(category) = category {
            interface.get_or_insert_with(PluginManifestInterface::default).category = Some(category);
        }

        plugins.push(MarketplacePlugin { name, source, policy, interface });
    }

    Ok(Marketplace { name, path, interface, plugins })
}
```

## 关键代码路径与文件引用

### 主要函数调用链

```
list_marketplaces(additional_roots)
├── list_marketplaces_with_home(additional_roots, home_dir)
│   ├── discover_marketplace_paths_from_roots()
│   │   ├── home.join(MARKETPLACE_RELATIVE_PATH)  // Home 目录
│   │   ├── root.join(MARKETPLACE_RELATIVE_PATH)  // 直接路径
│   │   └── get_git_repo_root(root) + MARKETPLACE_RELATIVE_PATH  // Git 根目录
│   └── load_marketplace(path)
│       ├── load_raw_marketplace_manifest(path)
│       │   └── fs::read_to_string() + serde_json::from_str()
│       └── 对每个插件:
│           ├── resolve_plugin_source_path()
│           └── load_plugin_manifest()  // 来自 manifest.rs
│
resolve_marketplace_plugin(marketplace_path, plugin_name)
├── load_raw_marketplace_manifest(marketplace_path)
├── 查找插件并验证安装策略
├── PluginId::new(name, marketplace_name)
└── resolve_plugin_source_path(marketplace_path, source)
```

### 文件引用

| 文件 | 引用关系 |
|------|---------|
| `codex-rs/core/src/plugins/manager.rs` | 调用 `list_marketplaces`, `load_marketplace`, `resolve_marketplace_plugin` |
| `codex-rs/core/src/plugins/manifest.rs` | 调用 `load_plugin_manifest` 获取插件界面信息 |
| `codex-rs/core/src/plugins/mod.rs` | 导出 `MarketplaceError`, `MarketplacePluginAuthPolicy`, 等 |
| `codex-rs/core/src/plugins/marketplace_tests.rs` | 内联测试模块 |

## 依赖与外部交互

### 依赖 crate

```rust
use super::PluginManifestInterface;
use super::load_plugin_manifest;           // 来自 manifest.rs
use super::store::PluginId;
use super::store::PluginIdError;
use crate::git_info::get_git_repo_root;    // Git 仓库发现
use codex_app_server_protocol::PluginAuthPolicy;
use codex_app_server_protocol::PluginInstallPolicy;
use codex_protocol::protocol::Product;     // 产品类型
use codex_utils_absolute_path::AbsolutePathBuf;
use dirs::home_dir;                         // 获取 home 目录
use serde::Deserialize;
use std::fs;
use std::io;
use std::path::Component;
use std::path::Path;
use std::path::PathBuf;
use tracing::warn;
```

### 错误类型

```rust
#[derive(Debug, thiserror::Error)]
pub enum MarketplaceError {
    #[error("{context}: {source}")]
    Io { context: &'static str, source: io::Error },

    #[error("marketplace file `{path}` does not exist")]
    MarketplaceNotFound { path: PathBuf },

    #[error("invalid marketplace file `{path}`: {message}")]
    InvalidMarketplaceFile { path: PathBuf, message: String },

    #[error("plugin `{plugin_name}` was not found in marketplace `{marketplace_name}`")]
    PluginNotFound { plugin_name: String, marketplace_name: String },

    #[error("plugin `{plugin_name}` is not available for install in marketplace `{marketplace_name}`")]
    PluginNotAvailable { plugin_name: String, marketplace_name: String },

    #[error("plugins feature is disabled")]
    PluginsDisabled,

    #[error("{0}")]
    InvalidPlugin(String),
}
```

### Raw 类型定义

```rust
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawMarketplaceManifest {
    name: String,
    #[serde(default)]
    interface: Option<RawMarketplaceManifestInterface>,
    plugins: Vec<RawMarketplaceManifestPlugin>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawMarketplaceManifestPlugin {
    name: String,
    source: RawMarketplaceManifestPluginSource,
    #[serde(default)]
    policy: RawMarketplaceManifestPluginPolicy,
    #[serde(default)]
    category: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(tag = "source", rename_all = "lowercase")]
enum RawMarketplaceManifestPluginSource {
    Local { path: String },
}
```

## 风险、边界与改进建议

### 安全风险与防护

| 风险 | 防护措施 |
|------|---------|
| 目录遍历攻击 | 强制 `./` 前缀，禁止 `..` 组件 |
| 绝对路径注入 | 拒绝不以 `./` 开头的路径 |
| 市场文件位置伪造 | 验证 `.agents/plugins/` 目录结构 |
| 空路径 | 拒绝空路径字符串 |

### 边界条件

1. **空市场**：空插件列表是有效的，返回空 `Vec`
2. **重复插件**：同一市场内重复插件名，使用第一个（由调用方处理）
3. **缺失 manifest**：插件 manifest 缺失时，`interface` 为 `None`
4. **分类覆盖**：市场定义的 `category` 覆盖 manifest 中的分类
5. **产品限制**：`products` 字段目前仅传递，未在边界强制执行

### 改进建议

1. **缓存机制**
   - 考虑添加市场文件缓存，避免重复读取
   - 添加文件修改时间检查，支持缓存失效

2. **错误报告增强**
   - 添加行号和列号信息到 JSON 解析错误
   - 提供更详细的上下文（如哪个插件定义出错）

3. **扩展性**
   - 准备支持远程来源（URL）的插件
   - 考虑支持多版本插件定义

4. **验证增强**
   - 添加插件名称唯一性验证
   - 验证插件来源路径是否存在

5. **性能优化**
   - 并行加载多个市场的插件 manifest
   - 使用异步 I/O 避免阻塞

6. **测试覆盖**
   - 添加更多错误路径测试
   - 添加大文件和特殊字符测试

### 已知限制

1. **产品限制未强制执行**：`MarketplacePluginPolicy.products` 字段仅作为元数据传递，实际的产品访问控制需要在消费端实现

2. **Git 依赖**：市场发现依赖 `get_git_repo_root()`，在非 Git 仓库中可能无法发现嵌套市场

3. **同步 I/O**：当前使用 `std::fs` 进行文件操作，在大量市场文件时可能阻塞

### 相关测试

- `codex-rs/core/src/plugins/marketplace_tests.rs`：内联测试模块，包含 14+ 个测试用例
- `codex-rs/core/src/plugins/manager_tests.rs`：集成测试，测试市场列表和插件解析的集成场景
