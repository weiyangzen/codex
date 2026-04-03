# AppListUpdatedNotification Research Document

## 1. 场景与职责 (Usage Scenario and Responsibility)

`AppListUpdatedNotification` 是 **EXPERIMENTAL** 状态的服务器通知，用于告知客户端应用列表（App/Connector 市场）已发生变化。

**使用场景：**
- 新的 App/Connector 上架时
- App 信息（描述、版本等）更新时
- App 启用/禁用状态变化时
- 用户安装/卸载 App 后

**职责：**
- 推送完整的应用列表数据
- 同步应用元数据（名称、描述、Logo、截图等）
- 通知应用可访问性/启用状态变化
- 驱动客户端刷新应用市场 UI

## 2. 功能点目的 (Purpose of the Functionality)

该通知的核心目的是实现应用市场数据的实时同步：

1. **列表同步**: 推送完整的应用列表
2. **元数据展示**: 提供丰富的应用信息用于 UI 展示
3. **状态感知**: 告知应用的可访问性和启用状态
4. **市场更新**: 及时通知新应用上架或现有应用更新

**核心数据结构：**
- `AppInfo`: 应用详细信息
  - `id`, `name`, `description`: 基本信息
  - `logoUrl`, `logoUrlDark`: 应用图标（支持暗黑模式）
  - `branding`: 品牌信息（开发者、网站、隐私政策等）
  - `appMetadata`: 元数据（分类、截图、版本等）
  - `isAccessible`, `isEnabled`: 可访问性和启用状态
- `AppBranding`: 品牌信息
- `AppMetadata`: 详细元数据（分类、截图、SEO 描述等）
- `AppScreenshot`: 应用截图

## 3. 具体技术实现 (Technical Implementation Details)

### 数据结构设计

```rust
// 定义位置: codex-rs/app-server-protocol/src/protocol/v2.rs
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
/// EXPERIMENTAL - notification emitted when the app list changes.
pub struct AppListUpdatedNotification {
    pub data: Vec<AppInfo>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
/// EXPERIMENTAL - app metadata returned by app-list APIs.
pub struct AppInfo {
    pub id: String,
    pub name: String,
    pub description: Option<String>,
    pub logo_url: Option<String>,
    pub logo_url_dark: Option<String>,
    pub distribution_channel: Option<String>,
    pub branding: Option<AppBranding>,
    pub app_metadata: Option<AppMetadata>,
    pub labels: Option<HashMap<String, String>>,
    pub install_url: Option<String>,
    #[serde(default)]
    pub is_accessible: bool,
    #[serde(default = "default_enabled")]
    pub is_enabled: bool,
    #[serde(default)]
    pub plugin_display_names: Vec<String>,
}
```

### 协议集成

在 `common.rs` 中注册：

```rust
server_notification_definitions! {
    AppListUpdated => "app/list/updated" (v2::AppListUpdatedNotification),
}
```

### 通知触发时机

1. App 市场数据更新时
2. 用户操作（安装/卸载/启用/禁用）后
3. 配置变更影响 App 可用性时
4. 定期同步（可选）

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### 定义文件
- **主要定义**: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs` (第 2059-2065 行)
- **AppInfo 定义**: v2.rs (第 1997-2024 行)
- **AppBranding 定义**: v2.rs (第 1948-1960 行)
- **AppMetadata 定义**: v2.rs (第 1982-1996 行)
- **协议注册**: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/common.rs`

### 相关 API
- `AppsListParams/Response`: 应用列表查询
- `app/list`: 主动获取应用列表的方法

### 生成文件
- **JSON Schema**: `/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/json/v2/AppListUpdatedNotification.json`

### 相关配置
- `AppsConfig`: 应用配置（启用/禁用等）
- `AppConfig`: 单个应用的配置

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### 内部依赖
- `AppInfo`, `AppBranding`, `AppMetadata`, `AppReview`, `AppScreenshot`: 应用相关类型
- `HashMap<String, String>`: 标签存储
- `#[experimental]` 宏标记实验性功能

### 外部交互
- **App 市场服务**: 获取应用列表和元数据
- **配置系统**: 获取应用的启用/禁用状态
- **权限系统**: 确定应用的可访问性

### 相关配置
```toml
[apps.bad_app]
enabled = false
```

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### 风险点

1. **实验性状态**: API 可能不稳定，后续版本可能变更
2. **数据量大**: 完整列表可能很大，影响传输性能
3. **敏感信息**: 应用元数据可能包含敏感信息
4. **缓存一致性**: 客户端缓存与服务器状态可能不一致

### 边界情况

1. **空列表**: 应用市场为空的情况
2. **大量应用**: 数百个应用的列表处理
3. **图片加载**: Logo 和截图 URL 的加载失败处理
4. **配置覆盖**: 用户配置与默认配置的合并

### 改进建议

1. **增量更新**: 当前推送完整列表，建议改为增量更新
2. **分页支持**: 大量应用时支持分页加载
3. **变更详情**: 添加变更类型（新增/更新/删除）
4. **时间戳**: 添加 `updated_at` 字段
5. **压缩传输**: 大数据量时启用压缩
6. **懒加载**: 截图等大资源支持懒加载

### 测试建议

1. 测试空列表场景
2. 测试大量应用的性能
3. 测试各种元数据组合
4. 验证实验性标记的处理
5. 测试配置变更后的通知

### 客户端实现建议

1. 实现本地缓存减少重复请求
2. 图片懒加载和缓存
3. 分类筛选和搜索功能
4. 展示实验性功能警告
5. 处理应用启用/禁用状态变化

### 注意事项

- 该功能标记为 **EXPERIMENTAL**，生产环境使用需谨慎
- 客户端应做好 API 变更的兼容处理
- 建议关注官方文档获取最新状态
