# DIR codex-rs/connectors/src 深度研究文档

## 1. 场景与职责

### 1.1 模块定位

`codex-rs/connectors/src` 是 `codex-connectors` crate 的唯一源码目录，包含该 crate 的完整实现。该模块是 Codex CLI 项目中负责**连接器（Connectors/Apps）目录数据获取与缓存**的核心基础设施层。

**核心职责：**
- 从 ChatGPT 后端 API 获取连接器目录数据（支持分页）
- 获取工作区专属连接器（仅工作区账户）
- 提供进程级内存缓存（TTL 1小时）
- 合并多来源连接器元数据（目录 + 工作区）
- 数据规范化（名称清理、URL 生成、空值处理）
- 过滤隐藏（HIDDEN）可见性的连接器

**架构定位：**
该模块位于数据访问层的最底层，向上层提供统一的连接器数据获取接口，本身不处理 HTTP 请求的具体实现，而是通过回调函数由调用方注入。

### 1.2 业务场景

| 场景 | 说明 | 调用方 |
|------|------|--------|
| TUI 连接器列表 | TUI 界面展示可安装/已安装的连接器 | `codex-tui` |
| App Server API | 通过 `app/list` RPC 暴露连接器列表 | `codex-app-server` |
| 插件元数据加载 | 为插件应用加载完整元数据 | `codex-app-server/plugin_app_helpers` |
| Tool Suggest | 工具发现功能获取可发现的连接器 | `codex-core` |
| 连接器状态合并 | 合并目录数据与可访问状态 | `codex-chatgpt` |

### 1.3 在架构中的位置

```
┌─────────────────────────────────────────────────────────────────────┐
│                           应用层 (Application)                       │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────┐  │
│  │    TUI       │  │  App Server  │  │  Tool Suggest (core)     │  │
│  └──────┬───────┘  └──────┬───────┘  └───────────┬──────────────┘  │
└─────────┼─────────────────┼──────────────────────┼─────────────────┘
          │                 │                      │
          ▼                 ▼                      ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      业务逻辑层 (Business Logic)                     │
│                    codex-chatgpt / codex-core                        │
│         (list_all_connectors, merge_connectors, etc.)               │
└─────────────────────┬───────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      数据获取层 (Data Access)                        │
│                    codex-connectors (本模块)                         │
│  ┌───────────────────────────────────────────────────────────────┐ │
│  │  src/lib.rs                                                   │ │
│  │  • list_directory_connectors()  - 分页获取目录连接器          │ │
│  │  • list_workspace_connectors()  - 获取工作区连接器            │ │
│  │  • list_all_connectors_with_options() - 统一入口              │ │
│  │  • cached_all_connectors()      - 缓存读取                    │ │
│  │  • merge_directory_apps()       - 元数据合并                  │ │
│  │  • directory_app_to_app_info()  - 类型转换与规范化            │ │
│  └───────────────────────────────────────────────────────────────┘ │
└─────────────────────┬───────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      协议定义层 (Protocol)                           │
│              codex-app-server-protocol                               │
│     (AppInfo, AppBranding, AppMetadata, AppSummary)                 │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 2. 功能点目的

### 2.1 核心功能清单

| 功能 | 目的 | 关键函数 | 行号 |
|------|------|----------|------|
| **目录连接器获取** | 从 ChatGPT 后端分页获取完整连接器目录 | `list_directory_connectors()` | 145-178 |
| **工作区连接器获取** | 获取用户工作区专属连接器 | `list_workspace_connectors()` | 180-195 |
| **统一列表获取** | 组合目录和工作区连接器，提供统一入口 | `list_all_connectors_with_options()` | 92-132 |
| **缓存读取** | 检查并返回缓存的连接器数据 | `cached_all_connectors()` | 74-90 |
| **缓存写入** | 将连接器数据写入进程缓存 | `write_cached_all_connectors()` | 134-143 |
| **数据合并** | 合并重复连接器的元数据（字段级合并） | `merge_directory_apps()` | 197-207 |
| **单应用合并** | 合并两个 DirectoryApp 的元数据 | `merge_directory_app()` | 209-347 |
| **类型转换** | 将 DirectoryApp 转换为 AppInfo | `directory_app_to_app_info()` | 353-369 |
| **安装 URL 生成** | 生成连接器在 ChatGPT 上的安装链接 | `connector_install_url()` | 371-374 |
| **名称规范化** | 清理连接器名称（空值处理、trim） | `normalize_connector_name()` | 393-400 |
| **Slug 生成** | 将名称转换为 URL 友好的 slug | `connector_name_slug()` | 376-391 |
| **隐藏应用过滤** | 过滤 visibility=HIDDEN 的连接器 | `is_hidden_directory_app()` | 349-351 |

### 2.2 数据结构

#### 2.2.1 AllConnectorsCacheKey（缓存键）

```rust
// src/lib.rs:16-37
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AllConnectorsCacheKey {
    chatgpt_base_url: String,        // ChatGPT 后端地址（如 https://chatgpt.com）
    account_id: Option<String>,      // 账户 ID（可能为空）
    chatgpt_user_id: Option<String>, // 用户 ID
    is_workspace_account: bool,      // 是否工作区账户
}
```

**设计意图：**
- 缓存键包含用户身份标识，确保不同用户/账户的缓存隔离
- 包含 base_url，支持不同环境（staging/prod）的缓存隔离
- 实现 `Eq` 用于缓存命中比较

#### 2.2.2 CachedAllConnectors（缓存条目）

```rust
// src/lib.rs:40-44, 46-47
#[derive(Clone)]
struct CachedAllConnectors {
    key: AllConnectorsCacheKey,      // 缓存键
    expires_at: Instant,              // 过期时间点
    connectors: Vec<AppInfo>,         // 缓存的连接器数据
}

static ALL_CONNECTORS_CACHE: LazyLock<StdMutex<Option<CachedAllConnectors>>> =
    LazyLock::new(|| StdMutex::new(None));
```

**设计意图：**
- 使用 `LazyLock` 实现懒加载的静态缓存
- 使用 `StdMutex` 保护并发访问（简单场景下的选择）
- 单条目设计（`Option<CachedAllConnectors>`），同一时间只缓存一个用户的数据

#### 2.2.3 DirectoryApp（原始目录数据）

```rust
// src/lib.rs:56-72
#[derive(Debug, Deserialize, Clone)]
pub struct DirectoryApp {
    id: String,                           // 连接器唯一标识（如 "app_xxx"）
    name: String,                         // 显示名称（可能为空）
    description: Option<String>,          // 描述
    #[serde(alias = "appMetadata")]
    app_metadata: Option<AppMetadata>,    // 应用元数据（分类、版本、截图等）
    branding: Option<AppBranding>,        // 品牌信息（开发者、网站、隐私政策等）
    labels: Option<HashMap<String, String>>, // 标签键值对
    #[serde(alias = "logoUrl")]
    logo_url: Option<String>,             // Logo URL（亮色模式）
    #[serde(alias = "logoUrlDark")]
    logo_url_dark: Option<String>,        // Logo URL（暗色模式）
    #[serde(alias = "distributionChannel")]
    distribution_channel: Option<String>, // 分发渠道
    visibility: Option<String>,           // 可见性（"HIDDEN" 等）
}
```

**设计意图：**
- 使用 `#[serde(alias = "...")]` 支持 camelCase 和 snake_case 字段名
- 大部分字段为 `Option`，处理后端数据的不完整性
- 与 `AppInfo` 结构相似但字段更多，用于原始数据接收

#### 2.2.4 DirectoryListResponse（API 响应）

```rust
// src/lib.rs:49-54
#[derive(Debug, Deserialize)]
pub struct DirectoryListResponse {
    apps: Vec<DirectoryApp>,              // 连接器列表
    #[serde(alias = "nextToken")]
    next_token: Option<String>,           // 分页令牌（空表示结束）
}
```

---

## 3. 具体技术实现

### 3.1 关键流程

#### 3.1.1 获取连接器列表完整流程

```
list_all_connectors_with_options(cache_key, is_workspace_account, force_refetch, fetch_page)
    │
    ├─► 1. 缓存检查（除非 force_refetch=true）
    │   │
    │   ├─► cached_all_connectors(&cache_key)
    │   │   ├─► 获取 StdMutex 锁
    │   │   ├─► 检查缓存是否存在且未过期（Instant::now() < expires_at）
    │   │   ├─► 检查缓存键是否匹配（cached.key == cache_key）
    │   │   └─► 命中 → 返回 Some(Vec<AppInfo>)
    │   │
    │   └─► 命中 → 直接返回缓存数据
    │
    ├─► 2. 缓存未命中或强制刷新
    │   │
    │   ├─► list_directory_connectors(&mut fetch_page)
    │   │   ├─► 构建请求路径：
    │   │   │   首次：/connectors/directory/list?tier=categorized&external_logos=true
    │   │   │   分页：/connectors/directory/list?tier=categorized&token={encoded}&external_logos=true
    │   │   ├─► 调用 fetch_page(path) 获取响应
    │   │   ├─► 过滤 HIDDEN 可见性的应用（is_hidden_directory_app）
    │   │   ├─► 保存 next_token
    │   │   └─► 循环直到 next_token 为 None
    │   │
    │   ├─► list_workspace_connectors(&mut fetch_page) 【仅当 is_workspace_account=true】
    │   │   ├─► 请求路径：/connectors/directory/list_workspace?external_logos=true
    │   │   ├─► 调用 fetch_page(path)
    │   │   ├─► 过滤 HIDDEN 应用
    │   │   └─► 失败返回空列表（不中断整体流程）
    │   │
    │   ├─► merge_directory_apps(apps) 【合并重复 ID 的元数据】
    │   │   ├─► 使用 HashMap 按 id 去重
    │   │   └─► 对重复 ID 调用 merge_directory_app() 合并字段
    │   │
    │   ├─► directory_app_to_app_info() 【转换为 AppInfo 并规范化】
    │   │   ├─► 映射基础字段（id, name, description, logo_url, ...）
    │   │   ├─► 生成 install_url（如未提供）
    │   │   ├─► normalize_connector_name()：空名称用 ID 替代
    │   │   ├─► normalize_connector_value()：trim 并过滤空描述
    │   │   └─► 设置 is_accessible=false, is_enabled=true
    │   │
    │   └─► 排序：按 name 字母序，name 相同按 id 字母序
    │
    ├─► 3. 写入缓存
    │   └─► write_cached_all_connectors(cache_key, &connectors)
    │       ├─► 获取锁
    │       ├─► 计算过期时间：Instant::now() + CONNECTORS_CACHE_TTL（3600s）
    │       └─► 写入静态缓存
    │
    └─► 4. 返回 Vec<AppInfo>
```

#### 3.1.2 缓存机制详解

```rust
// src/lib.rs:13
pub const CONNECTORS_CACHE_TTL: Duration = Duration::from_secs(3600);

// 缓存读取（src/lib.rs:74-90）
pub fn cached_all_connectors(cache_key: &AllConnectorsCacheKey) -> Option<Vec<AppInfo>> {
    let mut cache_guard = ALL_CONNECTORS_CACHE
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    let now = Instant::now();

    if let Some(cached) = cache_guard.as_ref() {
        if now < cached.expires_at && cached.key == *cache_key {
            return Some(cached.connectors.clone());
        }
        if now >= cached.expires_at {
            *cache_guard = None;  // 过期时清空缓存
        }
    }

    None
}
```

**关键设计决策：**
1. **单条目缓存**：同一时间只缓存一个用户的数据，切换用户时旧缓存会被覆盖
2. **Poison Error 处理**：使用 `unwrap_or_else(std::sync::PoisonError::into_inner)` 在锁中毒时尝试恢复
3. **过期清理**：读取时发现过期会清空缓存，避免脏数据
4. **同步锁**：使用 `StdMutex` 而非异步锁，因为操作极快（仅内存访问）

### 3.2 关键算法

#### 3.2.1 连接器合并策略（字段级合并）

```rust
// src/lib.rs:209-347
fn merge_directory_app(existing: &mut DirectoryApp, incoming: DirectoryApp) {
    // 1. 名称合并：仅当现有名称为空且传入名称非空时更新
    let incoming_name_is_empty = name.trim().is_empty();
    if existing.name.trim().is_empty() && !incoming_name_is_empty {
        existing.name = name;
    }

    // 2. 描述合并：传入描述非空时更新（覆盖现有）
    let incoming_description_present = description
        .as_deref()
        .map(|value| !value.trim().is_empty())
        .unwrap_or(false);
    if incoming_description_present {
        existing.description = description;
    }

    // 3. Logo URL 合并：现有为空时更新
    if existing.logo_url.is_none() && logo_url.is_some() {
        existing.logo_url = logo_url;
    }
    if existing.logo_url_dark.is_none() && logo_url_dark.is_some() {
        existing.logo_url_dark = logo_url_dark;
    }

    // 4. Branding 字段级合并（每个字段独立判断）
    if let Some(incoming_branding) = branding {
        if let Some(existing_branding) = existing.branding.as_mut() {
            // category, developer, website, privacy_policy, terms_of_service
            // 策略：existing 为 None 时才用 incoming 填充
            if existing_branding.category.is_none() && incoming_branding.category.is_some() {
                existing_branding.category = incoming_branding.category;
            }
            // ... 其他字段类似
            
            // is_discoverable_app：布尔值，true 优先
            if !existing_branding.is_discoverable_app && incoming_branding.is_discoverable_app {
                existing_branding.is_discoverable_app = true;
            }
        } else {
            existing.branding = Some(incoming_branding);
        }
    }

    // 5. AppMetadata 字段级合并（类似 Branding）
    // review, categories, sub_categories, seo_description, screenshots
    // developer, version, version_id, version_notes, first_party_type
    // first_party_requires_install, show_in_composer_when_unlinked
}
```

**合并策略总结：**
| 字段类型 | 策略 |
|----------|------|
| 名称 | 现有为空时更新 |
| 描述 | 传入非空时覆盖 |
| URL 类 | 现有为空时更新 |
| Branding 子字段 | 每个子字段独立判断，现有为空时更新 |
| Metadata 子字段 | 每个子字段独立判断，现有为空时更新 |
| 布尔值 | true 优先（或逻辑） |

#### 3.2.2 安装 URL 生成算法

```rust
// src/lib.rs:371-391
fn connector_install_url(name: &str, connector_id: &str) -> String {
    let slug = connector_name_slug(name);
    format!("https://chatgpt.com/apps/{slug}/{connector_id}")
}

fn connector_name_slug(name: &str) -> String {
    let mut normalized = String::with_capacity(name.len());
    for character in name.chars() {
        if character.is_ascii_alphanumeric() {
            normalized.push(character.to_ascii_lowercase());
        } else {
            normalized.push('-');  // 非字母数字字符替换为连字符
        }
    }
    let normalized = normalized.trim_matches('-');
    if normalized.is_empty() {
        "app".to_string()  // 兜底值
    } else {
        normalized.to_string()
    }
}
```

**示例：**
| 名称 | Slug | 最终 URL |
|------|------|----------|
| "Google Drive" | "google-drive" | `https://chatgpt.com/apps/google-drive/app_xxx` |
| "Notion" | "notion" | `https://chatgpt.com/apps/notion/app_xxx` |
| "My.App!" | "my-app-" | `https://chatgpt.com/apps/my-app-/app_xxx` |
| "" (空) | "app" | `https://chatgpt.com/apps/app/app_xxx` |
| "---" | "app" | `https://chatgpt.com/apps/app/app_xxx` |

### 3.3 API 端点与协议

| 端点 | 方法 | 用途 | 参数 |
|------|------|------|------|
| `/connectors/directory/list` | GET | 获取目录连接器 | `tier=categorized`, `token={pagination}`, `external_logos=true` |
| `/connectors/directory/list_workspace` | GET | 获取工作区连接器 | `external_logos=true` |

**分页机制：**
- 后端返回 `next_token`，非空表示还有更多数据
- 使用 `urlencoding::encode(token)` 对 token 进行 URL 编码
- 首次请求不带 token，后续请求携带上一次返回的 token

---

## 4. 关键代码路径与文件引用

### 4.1 本模块文件

| 文件 | 行数 | 职责 | 关键内容 |
|------|------|------|----------|
| `src/lib.rs` | 534 | 完整实现 | 所有核心逻辑 + 单元测试 |
| `Cargo.toml` | 18 | 包配置 | 依赖声明、workspace 继承 |
| `BUILD.bazel` | 6 | Bazel 构建 | 使用 codex_rust_crate 规则 |

### 4.2 调用方代码路径

| Crate | 文件 | 调用点 | 用途 |
|-------|------|--------|------|
| codex-chatgpt | `src/connectors.rs:91-104` | `list_all_connectors_with_options()` | 委托获取目录数据 |
| codex-chatgpt | `src/connectors.rs:72` | `cached_all_connectors()` | 读取缓存 |
| codex-core | `src/connectors.rs:433-450` | `list_all_connectors_with_options()` | Tool Suggest 获取目录 |
| codex-app-server | `src/codex_message_processor/plugin_app_helpers.rs:19` | `list_all_connectors_with_options()` | 加载插件应用元数据 |
| codex-app-server | `src/codex_message_processor.rs:5254` | `list_all_connectors_with_options()` | App List RPC |
| codex-tui | `src/chatwidget.rs:6074` | `list_all_connectors_with_options()` | 获取连接器列表展示 |
| codex-tui-app-server | `src/chatwidget.rs:7174` | `list_all_connectors_with_options()` | TUI App Server 模式 |

### 4.3 依赖协议定义

| Crate | 文件 | 类型定义 |
|-------|------|----------|
| app-server-protocol | `src/protocol/v2.rs:2001-2024` | `AppInfo` - 连接器信息结构 |
| app-server-protocol | `src/protocol/v2.rs:1952-1959` | `AppBranding` - 品牌信息 |
| app-server-protocol | `src/protocol/v2.rs:1982-1995` | `AppMetadata` - 应用元数据 |

---

## 5. 依赖与外部交互

### 5.1 依赖清单（Cargo.toml）

```toml
[dependencies]
anyhow = { workspace = true }                           # 错误处理
serde = { workspace = true, features = ["derive"] }     # JSON 序列化/反序列化
urlencoding = { workspace = true }                      # URL 编码（分页 token）
codex-app-server-protocol = { workspace = true }        # AppInfo 等类型定义
```

### 5.2 外部交互图

```
┌─────────────────────────────────────────────────────────────────────┐
│                    codex-connectors/src/lib.rs                       │
└─────────────────────┬───────────────────────────────────────────────┘
                      │
        ┌─────────────┼─────────────┬─────────────┐
        ▼             ▼             ▼             ▼
┌──────────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────┐
│ ChatGPT API  │ │  Static  │ │  serde   │ │  urlencoding │
│ (via fetch_  │ │  Cache   │ │          │ │              │
│  page cb)    │ │ (StdMutex)│ │          │ │              │
└──────────────┘ └──────────┘ └──────────┘ └──────────────┘
        │
        │ HTTP GET
        ▼
┌─────────────────────────────────────────────────────────────────────┐
│  GET /connectors/directory/list?tier=categorized&external_logos=true │
│  GET /connectors/directory/list_workspace?external_logos=true        │
└─────────────────────────────────────────────────────────────────────┘
```

### 5.3 HTTP 请求注入机制

本模块不直接发起 HTTP 请求，而是通过回调函数由调用方注入：

```rust
// src/lib.rs:92-101
pub async fn list_all_connectors_with_options<F, Fut>(
    cache_key: AllConnectorsCacheKey,
    is_workspace_account: bool,
    force_refetch: bool,
    mut fetch_page: F,  // 注入的 HTTP 请求函数
) -> anyhow::Result<Vec<AppInfo>>
where
    F: FnMut(String) -> Fut,
    Fut: Future<Output = anyhow::Result<DirectoryListResponse>>,
```

**调用方实现示例（codex-chatgpt）：**

```rust
// codex-rs/chatgpt/src/connectors.rs:91-104
codex_connectors::list_all_connectors_with_options(
    cache_key,
    token_data.id_token.is_workspace_account(),
    force_refetch,
    |path| async move {
        chatgpt_get_request_with_timeout::<DirectoryListResponse>(
            config,
            path,
            Some(DIRECTORY_CONNECTORS_TIMEOUT),  // 60s
        )
        .await
    },
)
```

**优势：**
- 模块无网络依赖，纯逻辑处理
- 便于单元测试（可注入 mock）
- 调用方控制 HTTP 客户端、超时、重试等策略

---

## 6. 风险、边界与改进建议

### 6.1 潜在风险

| 风险 | 描述 | 影响 | 当前缓解措施 |
|------|------|------|--------------|
| **缓存锁竞争** | 使用 `StdMutex` 而非 `RwLock`，并发读取也会互斥 | 低 | 操作极快（内存访问），实际影响小 |
| **Poison Error** | 使用 `unwrap_or_else(std::sync::PoisonError::into_inner)` 处理毒锁 | 中 | 尝试恢复，但可能隐藏 panic 问题 |
| **内存占用** | 静态缓存永不清理，长期运行可能累积 | 低 | 单条目设计，数据量小（通常 < 1000 个连接器） |
| **缓存穿透** | 同一缓存键的并发请求会触发多次后端调用 | 中 | 无内置防护，依赖调用方控制 |
| **工作区 API 失败** | `list_workspace_connectors` 失败静默处理 | 低 | 返回空列表，不中断整体流程 |

### 6.2 边界情况处理

| 场景 | 处理逻辑 | 代码位置 |
|------|----------|----------|
| 空名称 | 使用 connector_id 作为名称 | `normalize_connector_name()` (393-400) |
| 空描述 | 保持 `None`，不生成默认描述 | `normalize_connector_value()` (402-407) |
| HIDDEN 可见性 | 过滤掉，不返回给调用方 | `is_hidden_directory_app()` (349-351) |
| 工作区 API 失败 | 返回空列表，不中断整体流程 | `list_workspace_connectors()` (185-194) |
| 分页 token 为空 | 终止分页循环 | `list_directory_connectors()` (173-175) |
| 同名连接器 | 合并元数据，保留 ID 唯一性 | `merge_directory_apps()` (197-207) |
| URL 编码 | 使用 `urlencoding::encode()` 编码 token | `list_directory_connectors()` (155) |
| 空 slug | 使用 "app" 作为兜底 | `connector_name_slug()` (386-390) |

### 6.3 改进建议

#### 6.3.1 架构层面

1. **缓存并发优化**
   ```rust
   // 当前：StdMutex 阻塞所有并发访问
   static ALL_CONNECTORS_CACHE: LazyLock<StdMutex<Option<CachedAllConnectors>>>;
   
   // 建议：使用 RwLock 支持并发读
   static ALL_CONNECTORS_CACHE: LazyLock<RwLock<Option<CachedAllConnectors>>>;
   ```

2. **添加请求去重（Request Coalescing）**
   ```rust
   // 同一缓存键的并发请求应只触发一次后端调用
   // 可使用 tokio::sync::OnceCell 或 futures::future::Shared
   ```

3. **支持缓存失效事件**
   - 当用户切换账户时主动失效缓存
   - 当前依赖 TTL 过期，可能延迟更新

4. **支持缓存持久化**
   - 将缓存写入磁盘，应用重启后快速恢复
   - 减少冷启动时的 API 调用

#### 6.3.2 功能层面

1. **添加指标监控**
   - 缓存命中率
   - API 请求延迟分布
   - 连接器数量统计
   - 分页请求次数

2. **支持增量更新**
   - 当前每次刷新获取全量数据
   - 可支持基于 `updated_at` 或 `etag` 的增量同步

3. **增强错误处理**
   - 区分网络错误和 API 错误
   - 支持降级到缓存数据（即使已过期）
   - 添加错误重试机制

#### 6.3.3 代码层面

1. **测试覆盖增强**
   - 当前测试覆盖基本场景
   - 可添加：
     - 并发访问测试（验证锁行为）
     - 缓存过期边界测试
     - 大分页数据测试（1000+ 页）
     - 工作区 API 失败场景测试

2. **文档完善**
   - 添加更多内联文档说明合并策略
   - 说明 `is_accessible` 字段的含义（由调用方设置）
   - 添加模块级文档（#![doc = "..."]）

3. **性能优化**
   - `merge_directory_apps` 中预分配 HashMap 容量
   - 避免不必要的克隆（考虑使用 Arc<AppInfo>）

---

## 7. 测试分析

### 7.1 现有测试

```rust
// src/lib.rs:409-533

#[tokio::test]
async fn list_all_connectors_uses_shared_cache() -> anyhow::Result<()>
// 验证缓存机制：
// - 首次调用触发 fetch_page
// - 相同 cache_key 的第二次调用直接使用缓存，不触发 fetch_page

#[tokio::test]
async fn list_all_connectors_merges_and_normalizes_directory_apps() -> anyhow::Result<()>
// 验证合并和规范化逻辑：
// - 空名称处理（使用 ID 替代）
// - 描述合并（传入非空覆盖）
// - HIDDEN 应用过滤
// - branding 字段级合并
// - 工作区连接器获取（is_workspace_account=true）
// - install_url 生成
```

### 7.2 测试策略

测试使用 mock 的 `fetch_page` 函数，不依赖真实 HTTP 请求：

```rust
let connectors = list_all_connectors_with_options(key, true, true, move |path| {
    async move {
        // 根据 path 返回不同的 mock 响应
        if path.starts_with("/connectors/directory/list_workspace") {
            Ok(DirectoryListResponse { apps: vec![...], next_token: None })
        } else {
            Ok(DirectoryListResponse { apps: vec![...], next_token: None })
        }
    }
}).await?;
```

**测试覆盖度：**
- ✅ 缓存命中/未命中
- ✅ 数据合并（branding、metadata）
- ✅ 空名称处理
- ✅ HIDDEN 过滤
- ✅ 工作区连接器
- ❌ 并发访问
- ❌ 缓存过期
- ❌ 分页循环
- ❌ 错误处理

---

## 8. 总结

`codex-rs/connectors/src` 是一个职责单一、设计清晰的模块，专注于连接器目录数据的获取、缓存和规范化。其核心设计特点：

1. **依赖注入 HTTP 层**：通过 `fetch_page` 回调解耦 HTTP 实现，便于测试和复用
2. **智能合并策略**：字段级合并确保多来源元数据的完整性
3. **简洁缓存机制**：全局静态缓存 + TTL 过期策略，单条目设计
4. **零外部状态**：纯函数式设计，易于推理和测试
5. **防御式编程**：处理空值、隐藏应用、API 失败等边界情况

该模块在架构上位于数据获取层（codex-chatgpt）和协议定义层（app-server-protocol）之间，是整个连接器生态系统的数据源头。其设计遵循了 Rust 的零成本抽象原则，在保持代码清晰的同时提供了高效的运行时性能。
