# DIR codex-rs/connectors 深度研究文档

## 1. 场景与职责

### 1.1 模块定位

`codex-rs/connectors` 是 Codex CLI 项目中负责**连接器（Connectors/Apps）目录管理**的核心模块。连接器是指第三方应用集成（如 ChatGPT 插件、MCP 工具等），该模块提供：

- 从 ChatGPT 后端获取完整的连接器目录列表
- 缓存机制优化性能（TTL 1小时）
- 支持分页获取大量连接器数据
- 合并目录连接器与可访问连接器的状态
- 过滤和规范化连接器元数据

### 1.2 业务场景

| 场景 | 说明 |
|------|------|
| TUI 应用列表展示 | TUI 界面需要展示用户可安装/已安装的连接器 |
| App Server API | 通过 `app/list` RPC 方法暴露连接器列表 |
| 插件集成 | 将插件配置的连接器与目录数据合并 |
| 工具发现 | Tool Suggest 功能需要获取可发现的连接器 |

### 1.3 架构位置

```
┌─────────────────────────────────────────────────────────────┐
│                        调用方层                              │
│  ┌──────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │ TUI      │  │ App Server   │  │ Tool Suggest         │  │
│  └────┬─────┘  └──────┬───────┘  └──────────┬───────────┘  │
└───────┼───────────────┼─────────────────────┼──────────────┘
        │               │                     │
        ▼               ▼                     ▼
┌─────────────────────────────────────────────────────────────┐
│                    codex-chatgpt                             │
│              (高层业务逻辑封装层)                             │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│  ┌───────────────────────────────────────────────────────┐  │
│  │         codex-connectors (本模块)                      │  │
│  │  • 目录列表获取 (list_directory_connectors)            │  │
│  │  • 工作区连接器获取 (list_workspace_connectors)        │  │
│  │  • 缓存管理 (cached_all_connectors)                    │  │
│  │  • 数据合并与规范化                                    │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│              codex-app-server-protocol                       │
│           (AppInfo, AppBranding, AppMetadata 类型定义)       │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. 功能点目的

### 2.1 核心功能清单

| 功能 | 目的 | 关键 API |
|------|------|----------|
| **目录连接器获取** | 从 ChatGPT 后端获取完整连接器目录 | `list_directory_connectors()` |
| **工作区连接器获取** | 获取用户工作区专属的连接器 | `list_workspace_connectors()` |
| **缓存管理** | 避免频繁请求后端，TTL 1小时 | `cached_all_connectors()`, `write_cached_all_connectors()` |
| **数据合并** | 合并多个来源的连接器元数据 | `merge_directory_apps()` |
| **数据规范化** | 清理名称、描述、生成安装 URL | `normalize_connector_name()`, `connector_install_url()` |
| **完整列表获取** | 组合目录和工作区连接器 | `list_all_connectors_with_options()` |

### 2.2 数据结构

#### 2.2.1 DirectoryApp（原始目录数据）

```rust
#[derive(Debug, Deserialize, Clone)]
pub struct DirectoryApp {
    id: String,                           // 连接器唯一标识
    name: String,                         // 显示名称
    description: Option<String>,          // 描述
    app_metadata: Option<AppMetadata>,    // 应用元数据（分类、版本等）
    branding: Option<AppBranding>,        // 品牌信息（开发者、网站等）
    labels: Option<HashMap<String, String>>, // 标签
    logo_url: Option<String>,             // Logo URL（亮色模式）
    logo_url_dark: Option<String>,        // Logo URL（暗色模式）
    distribution_channel: Option<String>, // 分发渠道
    visibility: Option<String>,           // 可见性（HIDDEN 等）
}
```

#### 2.2.2 DirectoryListResponse（API 响应）

```rust
#[derive(Debug, Deserialize)]
pub struct DirectoryListResponse {
    apps: Vec<DirectoryApp>,              // 连接器列表
    next_token: Option<String>,           // 分页令牌
}
```

#### 2.2.3 AllConnectorsCacheKey（缓存键）

```rust
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AllConnectorsCacheKey {
    chatgpt_base_url: String,             // ChatGPT 后端地址
    account_id: Option<String>,           // 账户 ID
    chatgpt_user_id: Option<String>,     // 用户 ID
    is_workspace_account: bool,          // 是否工作区账户
}
```

---

## 3. 具体技术实现

### 3.1 关键流程

#### 3.1.1 获取连接器列表流程

```
list_all_connectors_with_options()
    │
    ├─► 检查缓存 (cached_all_connectors)
    │   └─► 缓存命中 → 返回缓存数据
    │
    ├─► 缓存未命中/强制刷新
    │   │
    │   ├─► list_directory_connectors()      // 获取目录连接器
    │   │   ├─► 构建请求路径 /connectors/directory/list
    │   │   ├─► 支持分页 (next_token)
    │   │   ├─► 过滤 HIDDEN 可见性的应用
    │   │   └─► 返回 DirectoryApp 列表
    │   │
    │   ├─► list_workspace_connectors()      // 获取工作区连接器（仅工作区账户）
    │   │   └─► 请求路径 /connectors/directory/list_workspace
    │   │
    │   ├─► merge_directory_apps()           // 合并重复连接器元数据
    │   │   └─► 策略：非空字段优先，合并 branding 和 app_metadata
    │   │
    │   ├─► directory_app_to_app_info()      // 转换为 AppInfo
    │   │   ├─► 生成 install_url
    │   │   ├─► 规范化名称和描述
    │   │   └─► 设置 is_accessible = false
    │   │
    │   └─► 排序（按名称、ID）
    │
    └─► 写入缓存 (write_cached_all_connectors)
        └─► TTL = 3600 秒 (CONNECTORS_CACHE_TTL)
```

#### 3.1.2 缓存机制

```rust
// 全局静态缓存
static ALL_CONNECTORS_CACHE: LazyLock<StdMutex<Option<CachedAllConnectors>>> = 
    LazyLock::new(|| StdMutex::new(None));

pub const CONNECTORS_CACHE_TTL: Duration = Duration::from_secs(3600);

struct CachedAllConnectors {
    key: AllConnectorsCacheKey,      // 缓存键（包含用户标识）
    expires_at: Instant,              // 过期时间
    connectors: Vec<AppInfo>,         // 缓存数据
}
```

### 3.2 关键算法

#### 3.2.1 连接器合并策略

```rust
fn merge_directory_app(existing: &mut DirectoryApp, incoming: DirectoryApp) {
    // 名称：仅当现有名称为空时更新
    if existing.name.trim().is_empty() && !incoming_name_is_empty {
        existing.name = name;
    }
    
    // 描述：传入描述非空时更新
    if incoming_description_present {
        existing.description = description;
    }
    
    // Logo URL：现有为空时更新
    if existing.logo_url.is_none() && logo_url.is_some() {
        existing.logo_url = logo_url;
    }
    
    // Branding 字段级合并（每个字段独立判断）
    if let Some(incoming_branding) = branding {
        if let Some(existing_branding) = existing.branding.as_mut() {
            if existing_branding.category.is_none() && incoming_branding.category.is_some() {
                existing_branding.category = incoming_branding.category;
            }
            // ... 其他字段类似
        }
    }
    
    // AppMetadata 字段级合并
    // ... 类似逻辑
}
```

#### 3.2.2 安装 URL 生成

```rust
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
        "app".to_string()
    } else {
        normalized.to_string()
    }
}
```

### 3.3 API 端点

| 端点 | 用途 | 参数 |
|------|------|------|
| `GET /connectors/directory/list` | 获取目录连接器 | `tier=categorized`, `token={pagination}`, `external_logos=true` |
| `GET /connectors/directory/list_workspace` | 获取工作区连接器 | `external_logos=true` |

---

## 4. 关键代码路径与文件引用

### 4.1 本模块文件

| 文件 | 职责 | 关键内容 |
|------|------|----------|
| `src/lib.rs` | 主实现 | 534 行，包含全部核心逻辑和测试 |
| `Cargo.toml` | 包配置 | 依赖：anyhow, serde, urlencoding, codex-app-server-protocol |
| `BUILD.bazel` | Bazel 构建 | 使用 codex_rust_crate 规则 |

### 4.2 调用方代码路径

| 模块 | 文件 | 调用点 |
|------|------|--------|
| codex-chatgpt | `src/connectors.rs` | `list_all_connectors_with_options()`, `cached_all_connectors()` |
| codex-core | `src/connectors.rs` | 通过 codex-chatgpt 间接使用 |
| app-server | `src/codex_message_processor/plugin_app_helpers.rs` | `list_all_connectors_with_options()` |
| tui | `src/chatwidget.rs` | `connectors::list_all_connectors_with_options()` |

### 4.3 依赖协议定义

| 模块 | 文件 | 类型定义 |
|------|------|----------|
| app-server-protocol | `src/protocol/v2.rs` | `AppInfo`, `AppBranding`, `AppMetadata`, `AppSummary` |

---

## 5. 依赖与外部交互

### 5.1 依赖清单

```toml
[dependencies]
anyhow = { workspace = true }                           # 错误处理
codex-app-server-protocol = { workspace = true }        # 协议类型定义
serde = { workspace = true, features = ["derive"] }     # 序列化
urlencoding = { workspace = true }                      # URL 编码
```

### 5.2 外部交互

```
┌─────────────────────────────────────────────────────────────┐
│                    codex-connectors                          │
└───────────────────────┬─────────────────────────────────────┘
                        │
        ┌───────────────┼───────────────┐
        ▼               ▼               ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│ ChatGPT API  │ │  Static Cache│ │App Server    │
│ (HTTP GET)   │ │  (Mutex)     │ │Protocol Types│
└──────────────┘ └──────────────┘ └──────────────┘
```

### 5.3 HTTP 请求详情

请求由调用方（codex-chatgpt）通过回调函数 `fetch_page` 注入：

```rust
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

实际 HTTP 请求在 `codex-chatgpt/src/connectors.rs` 中实现：

```rust
let connectors = codex_connectors::list_all_connectors_with_options(
    cache_key,
    token_data.id_token.is_workspace_account(),
    force_refetch,
    |path| async move {
        chatgpt_get_request_with_timeout::<DirectoryListResponse>(
            config,
            path,
            Some(DIRECTORY_CONNECTORS_TIMEOUT),
        )
        .await
    },
)
.await?;
```

---

## 6. 风险、边界与改进建议

### 6.1 潜在风险

| 风险 | 描述 | 影响 |
|------|------|------|
| **缓存污染** | 使用 `StdMutex` 而非 `RwLock`，并发读取也会阻塞 | 低（读少写少） |
| **Poison Error** | 使用 `unwrap_or_else(std::sync::PoisonError::into_inner)` 处理毒锁 | 中（可能隐藏 panic） |
| **内存泄漏** | 静态缓存永不清理，长期运行可能累积 | 低（数据量小） |
| **时区敏感** | 使用 `Instant::now()` 而非系统时间，不受时区影响 | 无风险 |

### 6.2 边界情况

| 场景 | 处理逻辑 |
|------|----------|
| 空名称 | 使用 connector_id 作为名称 (`normalize_connector_name`) |
| 空描述 | 保持 `None`，不生成默认描述 |
| HIDDEN 可见性 | 过滤掉，不返回给调用方 (`is_hidden_directory_app`) |
| 工作区 API 失败 | 返回空列表，不中断整体流程 |
| 分页 token 为空 | 终止分页循环 |
| 同名连接器 | 合并元数据，保留 ID 唯一性 |

### 6.3 改进建议

#### 6.3.1 架构层面

1. **缓存替换为异步友好实现**
   ```rust
   // 当前
   static ALL_CONNECTORS_CACHE: LazyLock<StdMutex<Option<CachedAllConnectors>>>;
   
   // 建议：使用 tokio::sync::RwLock 或 dashmap
   static ALL_CONNECTORS_CACHE: LazyLock<tokio::sync::RwLock<Option<CachedAllConnectors>>>;
   ```

2. **添加缓存失效事件**
   - 当用户切换账户时主动失效缓存
   - 当前依赖 TTL 过期，可能延迟更新

3. **支持缓存持久化**
   - 将缓存写入磁盘，应用重启后快速恢复
   - 减少冷启动时的 API 调用

#### 6.3.2 功能层面

1. **添加指标监控**
   - 缓存命中率
   - API 请求延迟
   - 连接器数量统计

2. **支持增量更新**
   - 当前每次刷新获取全量数据
   - 可支持基于 `updated_at` 的增量同步

3. **增强错误处理**
   - 区分网络错误和 API 错误
   - 支持降级到缓存数据（即使已过期）

#### 6.3.3 代码层面

1. **测试覆盖**
   - 当前测试覆盖基本场景
   - 可添加：
     - 并发访问测试
     - 缓存过期边界测试
     - 大分页数据测试

2. **文档完善**
   - 添加更多内联文档说明合并策略
   - 说明 `is_accessible` 字段的含义

---

## 7. 测试分析

### 7.1 现有测试

```rust
#[tokio::test]
async fn list_all_connectors_uses_shared_cache() -> anyhow::Result<()>
// 验证缓存机制，确保相同 key 的第二次调用使用缓存

#[tokio::test]
async fn list_all_connectors_merges_and_normalizes_directory_apps() -> anyhow::Result<()>
// 验证合并和规范化逻辑，包括：
// - 空名称处理
// - 描述合并
// - HIDDEN 过滤
// - branding 合并
```

### 7.2 测试策略

测试使用 mock 的 `fetch_page` 函数，不依赖真实 HTTP 请求：

```rust
let connectors = list_all_connectors_with_options(key, true, true, move |path| {
    async move {
        // mock 响应
        Ok(DirectoryListResponse { apps: vec![...], next_token: None })
    }
}).await?;
```

---

## 8. 总结

`codex-rs/connectors` 是一个职责单一、设计清晰的模块，专注于连接器目录数据的获取、缓存和规范化。其核心设计特点：

1. **依赖注入 HTTP 层**：通过 `fetch_page` 回调解耦 HTTP 实现，便于测试和复用
2. **智能合并策略**：字段级合并确保元数据完整性
3. **简洁缓存机制**：全局静态缓存 + TTL 过期策略
4. **零外部状态**：纯函数式设计，易于推理和测试

该模块在架构上位于数据获取层（codex-chatgpt）和协议定义层（app-server-protocol）之间，是整个连接器生态系统的数据源头。
