# codex-rs/connectors 研究文档

## 概述

`codex-connectors` crate 是 Codex 项目中负责**连接器目录管理**的基础组件。它提供了从 ChatGPT 后端获取、缓存、合并和标准化连接器（Apps/Connectors）元数据的核心功能。该 crate 作为数据访问层，为上层的 `codex-core` 和 `codex-chatgpt` 提供统一的连接器列表服务。

---

## 场景与职责

### 核心场景

1. **连接器目录发现**：从 ChatGPT 后端 API 获取可用的连接器列表
2. **元数据缓存管理**：提供进程级内存缓存，避免频繁请求后端 API
3. **数据合并与标准化**：合并来自不同来源（目录列表、工作区列表）的连接器数据
4. **插件应用集成**：支持将插件应用与目录连接器合并展示

### 主要职责

| 职责 | 说明 |
|------|------|
| 数据获取 | 通过分页 API 获取目录连接器和（可选的）工作区连接器 |
| 缓存管理 | 基于 `AllConnectorsCacheKey` 的进程级缓存，TTL 为 3600 秒 |
| 数据合并 | 合并同一连接器的多个来源数据，优先保留非空字段 |
| 数据标准化 | 规范化连接器名称、生成安装 URL、过滤隐藏应用 |
| 错误容错 | 工作区连接器获取失败时返回空列表而非错误 |

---

## 功能点目的

### 1. 连接器列表获取 (`list_all_connectors_with_options`)

**目的**：提供统一的连接器列表获取接口，支持缓存和强制刷新。

**关键特性**：
- 支持基于 `AllConnectorsCacheKey` 的缓存查找
- 支持 `force_refetch` 强制绕过缓存
- 自动合并目录连接器和工作区连接器（仅对工作区账户）
- 对连接器数据进行标准化处理（名称、URL、排序）

### 2. 分页数据获取 (`list_directory_connectors` / `list_workspace_connectors`)

**目的**：处理后端 API 的分页响应，获取完整的连接器列表。

**API 端点**：
- 目录连接器：`/connectors/directory/list?tier=categorized&external_logos=true`
- 工作区连接器：`/connectors/directory/list_workspace?external_logos=true`

**分页处理**：
- 使用 `next_token` 进行分页遍历
- URL 编码处理 token 中的特殊字符
- 过滤 `visibility: "HIDDEN"` 的隐藏应用

### 3. 数据合并 (`merge_directory_apps` / `merge_directory_app`)

**目的**：当同一连接器出现在多个来源（如目录列表和工作区列表）时，智能合并字段。

**合并策略**（字段级别优先级）：
- 名称：优先非空值
- 描述：优先非空值
- Logo URL：优先第一个非空值
- Branding 信息：递归合并各子字段
- AppMetadata：递归合并各子字段

### 4. 数据标准化

**目的**：确保连接器数据的一致性和可用性。

**标准化操作**：
- `normalize_connector_name`：空名称时使用 ID 作为名称
- `normalize_connector_value`：去除空白，过滤空字符串
- `connector_name_slug`：生成 URL 友好的 slug（小写、非字母数字转 `-`）
- `connector_install_url`：生成 `https://chatgpt.com/apps/{slug}/{connector_id}` 格式的安装链接

### 5. 进程级缓存

**目的**：减少后端 API 调用，提升性能。

**缓存机制**：
- 全局静态变量 `ALL_CONNECTORS_CACHE`（`LazyLock<StdMutex<Option<CachedAllConnectors>>>`）
- 缓存键包含：base URL、账户 ID、用户 ID、工作区账户标志
- TTL：3600 秒（`CONNECTORS_CACHE_TTL`）
- 自动过期清理

---

## 具体技术实现

### 关键数据结构

#### `AllConnectorsCacheKey`
```rust
pub struct AllConnectorsCacheKey {
    chatgpt_base_url: String,
    account_id: Option<String>,
    chatgpt_user_id: Option<String>,
    is_workspace_account: bool,
}
```
缓存键设计考虑了多租户场景，确保不同用户/账户的缓存隔离。

#### `DirectoryApp`
```rust
pub struct DirectoryApp {
    id: String,
    name: String,
    description: Option<String>,
    app_metadata: Option<AppMetadata>,
    branding: Option<AppBranding>,
    labels: Option<HashMap<String, String>>,
    logo_url: Option<String>,
    logo_url_dark: Option<String>,
    distribution_channel: Option<String>,
    visibility: Option<String>,
}
```
后端 API 的原始响应结构，使用 `serde(alias)` 处理蛇峰命名转换。

#### `DirectoryListResponse`
```rust
pub struct DirectoryListResponse {
    apps: Vec<DirectoryApp>,
    next_token: Option<String>,
}
```
分页响应结构，`next_token` 用于后续分页请求。

### 关键流程

#### 连接器列表获取流程

```
list_all_connectors_with_options
├── 检查缓存（如果 !force_refetch）
│   └── 返回缓存数据（如果命中且未过期）
├── list_directory_connectors (分页获取)
│   ├── 构建请求路径（含 token）
│   ├── 调用 fetch_page 闭包
│   ├── 过滤 HIDDEN 应用
│   └── 处理 next_token 循环
├── list_workspace_connectors (可选，仅工作区账户)
│   ├── 调用 fetch_page
│   └── 失败时返回空列表（容错）
├── merge_directory_apps (合并重复)
├── directory_app_to_app_info (转换为 AppInfo)
├── 标准化处理（名称、URL、排序）
└── 写入缓存
```

#### 数据合并流程

```
merge_directory_apps
├── 使用 HashMap 按 ID 分组
├── 对于重复 ID：
│   └── merge_directory_app
│       ├── 合并基础字段（name, description, logo_url...）
│       ├── 合并 branding（递归字段级合并）
│       ├── 合并 app_metadata（递归字段级合并）
│       └── 合并 labels
└── 返回合并后的 Vec<DirectoryApp>
```

### 协议与 API

#### 依赖的协议类型

该 crate 依赖 `codex-app-server-protocol` 中的以下类型：

- `AppInfo`：标准化的连接器信息结构（输出类型）
- `AppBranding`：品牌信息（分类、开发者、网站等）
- `AppMetadata`：应用元数据（分类、截图、版本等）

#### HTTP API 接口

| 端点 | 方法 | 说明 |
|------|------|------|
| `/connectors/directory/list` | GET | 获取目录连接器列表 |
| `/connectors/directory/list_workspace` | GET | 获取工作区连接器列表（仅工作区账户） |

**查询参数**：
- `tier=categorized`：请求分类层级的连接器
- `external_logos=true`：请求外部 Logo URL
- `token={encoded_token}`：分页令牌（可选）

---

## 关键代码路径与文件引用

### 当前 crate 文件

| 文件 | 行数 | 说明 |
|------|------|------|
| `codex-rs/connectors/src/lib.rs` | 534 | 主实现文件，包含所有核心逻辑和测试 |
| `codex-rs/connectors/Cargo.toml` | 18 | 包配置，依赖 `codex-app-server-protocol` |
| `codex-rs/connectors/BUILD.bazel` | 6 | Bazel 构建配置 |

### 调用方（上游）

| 文件 | 用途 |
|------|------|
| `codex-rs/chatgpt/src/connectors.rs` | 主要调用方，封装 HTTP 客户端逻辑，提供 `list_all_connectors` 等接口 |
| `codex-rs/core/src/connectors.rs` | 通过 `codex-chatgpt` 间接使用，处理 MCP 工具相关的连接器逻辑 |
| `codex-rs/app-server/src/codex_message_processor/plugin_app_helpers.rs` | 加载插件应用摘要 |
| `codex-rs/tui/src/chatwidget.rs` | TUI 界面使用连接器功能 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | TUI App Server 使用连接器功能 |

### 被调用方/依赖（下游）

| 包/模块 | 提供的类型 |
|---------|-----------|
| `codex-app-server-protocol` | `AppInfo`, `AppBranding`, `AppMetadata` |
| `serde` | 反序列化支持 |
| `urlencoding` | URL 编码处理 |

---

## 依赖与外部交互

### 外部依赖

```toml
[dependencies]
anyhow = { workspace = true }
codex-app-server-protocol = { workspace = true }
serde = { workspace = true, features = ["derive"] }
urlencoding = { workspace = true }
```

### 运行时依赖

该 crate 本身不直接发起 HTTP 请求，而是通过**回调函数**（`fetch_page` 闭包）将实际的网络请求委托给调用方。这种设计：

1. **解耦网络逻辑**：crate 专注于业务逻辑，不依赖特定 HTTP 客户端
2. **便于测试**：测试可以注入模拟的 `fetch_page` 实现
3. **灵活适配**：调用方可以添加认证、超时、重试等逻辑

### 与 `codex-chatgpt` 的交互

```
codex-chatgpt/src/connectors.rs
├── 构建 AllConnectorsCacheKey
├── 调用 codex_connectors::list_all_connectors_with_options
│   └── 提供 fetch_page 闭包（使用 chatgpt_get_request_with_timeout）
├── 调用 merge_plugin_apps（合并插件应用）
└── 调用 filter_disallowed_connectors（过滤不允许的连接器）
```

---

## 风险、边界与改进建议

### 已知风险

1. **全局缓存竞争**
   - 使用 `StdMutex` 保护全局缓存，在高并发场景可能产生 contention
   - 缓存是进程级的，无法跨进程共享

2. **缓存键设计局限**
   - 缓存键包含 `chatgpt_base_url`、`account_id`、`chatgpt_user_id`，粒度较细
   - 如果用户切换账户，缓存会失效重新获取

3. **工作区连接器获取失败静默**
   - `list_workspace_connectors` 在失败时返回空列表，调用方无法区分"无数据"和"获取失败"

4. **内存缓存无上限**
   - 当前缓存只存储单个条目（最新的查询），不会无限增长，但设计上是单例模式

### 边界情况

1. **空名称处理**：当连接器名称为空时，使用 ID 作为名称
2. **Slug 生成**：非 ASCII 字母数字字符全部替换为 `-`，可能导致连续 `-` 或首尾 `-`
3. **分页循环**：依赖后端返回的 `next_token` 终止循环，如果后端返回异常可能导致无限循环（实际有 `is_empty()` 检查）
4. **并发安全**：缓存读写使用 `StdMutex`，在异步上下文中需要小心持有锁的时间

### 改进建议

1. **缓存策略增强**
   - 考虑使用 `tokio::sync::RwLock` 替代 `StdMutex`，优化并发读场景
   - 添加缓存统计（命中率、过期次数）便于监控

2. **错误处理改进**
   - 工作区连接器获取失败时，考虑返回错误而非空列表，让调用方决定是否忽略
   - 添加结构化错误类型，区分网络错误、解析错误、权限错误

3. **可观测性**
   - 添加 `tracing` 日志，记录缓存命中/未命中、API 请求耗时、数据合并统计
   - 当前实现无日志输出，调试困难

4. **测试覆盖**
   - 当前测试覆盖了缓存共享和数据合并，但缺少：
     - 分页获取的测试
     - 缓存过期逻辑的测试
     - 工作区连接器获取失败的测试

5. **API 设计优化**
   - `fetch_page` 闭包签名可以改为引用 `&str` 避免 `String` 分配
   - 考虑使用 `async-trait` 定义明确的接口 trait，替代闭包参数

6. **数据验证**
   - 添加对 `DirectoryApp` 字段的验证（如 ID 非空、URL 格式正确）
   - 对 `next_token` 进行长度限制，防止异常数据导致内存问题

---

## 附录：类型对照表

| 内部类型 | 协议类型 | 说明 |
|---------|---------|------|
| `DirectoryApp` | - | 后端 API 原始数据结构 |
| - | `AppInfo` | 标准化后的连接器信息（输出） |
| - | `AppBranding` | 品牌信息（category, developer, website...） |
| - | `AppMetadata` | 元数据（categories, screenshots, version...） |

---

## 附录：关键常量

| 常量 | 值 | 说明 |
|------|-----|------|
| `CONNECTORS_CACHE_TTL` | 3600 秒 | 缓存有效期 |
