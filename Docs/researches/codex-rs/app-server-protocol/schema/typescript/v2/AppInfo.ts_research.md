# AppInfo 类型研究文档

## 1. 场景与职责

### 1.1 使用场景

`AppInfo` 是 Codex App-Server Protocol v2 中用于描述应用程序完整信息的核心元数据类型。它是应用生态系统的中心数据模型，主要用于：

- **应用列表展示**：在 `app/list` API 响应中返回完整的应用信息
- **应用商店/发现页面**：支持用户浏览、搜索和安装应用
- **插件管理**：展示与插件关联的应用信息
- **应用状态监控**：跟踪应用的启用/禁用状态和可访问性
- **应用配置管理**：反映 config.toml 中的应用配置

### 1.2 核心职责

- 提供应用的完整标识信息（ID、名称、描述、Logo）
- 聚合品牌信息（通过 `branding` 字段）
- 聚合详细元数据（通过 `appMetadata` 字段）
- 支持应用生命周期管理（安装 URL、启用状态、可访问性）
- 支持标签系统（`labels`）用于分类和筛选
- 关联插件显示名称（`pluginDisplayNames`）

### 1.3 实验性状态

该类型标记为 **EXPERIMENTAL**，表明 API 可能在未来版本中发生变化。

---

## 2. 功能点目的

### 2.1 字段功能说明

| 字段 | 类型 | 目的 |
|------|------|------|
| `id` | `string` | 应用唯一标识符 |
| `name` | `string` | 应用显示名称 |
| `description` | `string \| null` | 应用描述 |
| `logoUrl` | `string \| null` | 应用 Logo URL（亮色模式） |
| `logoUrlDark` | `string \| null` | 应用 Logo URL（暗色模式） |
| `distributionChannel` | `string \| null` | 分发渠道（如 "marketplace", "internal"） |
| `branding` | `AppBranding \| null` | 品牌信息（开发者、网站、隐私政策等） |
| `appMetadata` | `AppMetadata \| null` | 详细元数据（分类、截图、版本等） |
| `labels` | `{ [key: string]?: string } \| null` | 键值对标签，用于筛选和分类 |
| `installUrl` | `string \| null` | 应用安装/配置页面 URL |
| `isAccessible` | `boolean` | 当前用户是否有权限访问此应用 |
| `isEnabled` | `boolean` | 应用是否在 config.toml 中启用 |
| `pluginDisplayNames` | `Array<string>` | 关联的插件显示名称列表 |

### 2.2 设计意图

1. **完整性与分层**：通过嵌套 `AppBranding` 和 `AppMetadata`，将信息分层组织，便于不同场景使用
2. **主题适配**：`logoUrl` 和 `logoUrlDark` 支持亮色/暗色主题切换
3. **配置同步**：`isEnabled` 字段直接反映 config.toml 中的配置状态
4. **权限感知**：`isAccessible` 表示当前用户的访问权限，与 `isEnabled` 独立

---

## 3. 具体技术实现

### 3.1 TypeScript 类型定义

```typescript
export type AppInfo = {
  id: string,
  name: string,
  description: string | null,
  logoUrl: string | null,
  logoUrlDark: string | null,
  distributionChannel: string | null,
  branding: AppBranding | null,
  appMetadata: AppMetadata | null,
  labels: { [key in string]?: string } | null,
  installUrl: string | null,
  isAccessible: boolean,
  /**
   * Whether this app is enabled in config.toml.
   * Example:
   * ```toml
   * [apps.bad_app]
   * enabled = false
   * ```
   */
  isEnabled: boolean,
  pluginDisplayNames: Array<string>,
};
```

### 3.2 Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs
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
    /// Whether this app is enabled in config.toml.
    /// Example:
    /// ```toml
    /// [apps.bad_app]
    /// enabled = false
    /// ```
    #[serde(default = "default_enabled")]
    pub is_enabled: bool,
    #[serde(default)]
    pub plugin_display_names: Vec<String>,
}
```

### 3.3 默认值处理

| 字段 | Rust 默认值 | 说明 |
|------|-------------|------|
| `is_accessible` | `false` | 使用 `#[serde(default)]` |
| `is_enabled` | `true` | 使用 `default_enabled()` 函数 |
| `plugin_display_names` | 空数组 | 使用 `#[serde(default)]` |

### 3.4 类型转换

```rust
// AppInfo 可转换为 AppSummary（精简版本）
impl From<AppInfo> for AppSummary {
    fn from(value: AppInfo) -> Self {
        Self {
            id: value.id,
            name: value.name,
            description: value.description,
            install_url: value.install_url,
        }
    }
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 源文件

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 类型定义（约第 1997-2024 行） |
| `codex-rs/app-server-protocol/schema/typescript/v2/AppInfo.ts` | 生成的 TypeScript 类型 |

### 4.2 依赖类型

```
AppInfo
  ├── branding: AppBranding
  ├── appMetadata: AppMetadata
  │   ├── review: AppReview
  │   └── screenshots: AppScreenshot[]
  └── ...
```

### 4.3 引用关系

| 类型 | 关系 |
|------|------|
| `AppsListResponse` | 包含 `Vec<AppInfo>` |
| `AppListUpdatedNotification` | 包含 `Vec<AppInfo>` |
| `AppSummary` | 从 `AppInfo` 转换而来 |
| `PluginSummary` | 包含 `Vec<AppSummary>` |
| `PluginInstallResponse` | 包含 `Vec<AppSummary>`（apps_needing_auth） |

### 4.4 相关 API

| API | 请求/响应 | 说明 |
|-----|-----------|------|
| `app/list` | `AppsListParams` / `AppsListResponse` | 获取应用列表 |
| `AppListUpdatedNotification` | 通知 | 应用列表变更推送 |
| `plugin/install` | - / `PluginInstallResponse` | 返回需要授权的应用 |

---

## 5. 依赖与外部交互

### 5.1 导入依赖

```typescript
import type { AppBranding } from "./AppBranding";
import type { AppMetadata } from "./AppMetadata";
```

### 5.2 内部模块依赖

- `AppBranding`：品牌信息子结构
- `AppMetadata`：详细元数据子结构
- `AppReview`：审核状态（通过 AppMetadata）
- `AppScreenshot`：截图信息（通过 AppMetadata）

### 5.3 配置集成

`isEnabled` 字段与 config.toml 的集成：

```toml
# config.toml 示例
[apps.my_app]
enabled = true

[apps.deprecated_app]
enabled = false
```

### 5.4 客户端使用示例

```typescript
import type { AppInfo } from "./AppInfo";

// 过滤可访问且已启用的应用
function getAvailableApps(apps: AppInfo[]): AppInfo[] {
  return apps.filter(app => app.isAccessible && app.isEnabled);
}

// 按标签筛选应用
function filterAppsByLabel(apps: AppInfo[], labelKey: string, labelValue: string): AppInfo[] {
  return apps.filter(app => 
    app.labels?.[labelKey] === labelValue
  );
}

// 获取应用的暗色模式 Logo
function getAppLogo(app: AppInfo, isDarkMode: boolean): string | null {
  return isDarkMode ? app.logoUrlDark : app.logoUrl;
}
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| **实验性 API** | 类型可能变更 | 关注变更日志，使用版本锁定 |
| **字段膨胀** | 字段较多，部分场景只需要子集 | 使用 `AppSummary` 获取精简信息 |
| **配置同步延迟** | `isEnabled` 反映的是配置加载时的状态 | 监听 `AppListUpdatedNotification` 获取更新 |
| **空数组 vs null** | `pluginDisplayNames` 可能为空数组或 null | 统一处理逻辑 |

### 6.2 边界情况

1. **部分信息缺失**：某些应用可能没有 `branding` 或 `appMetadata`，客户端应优雅降级
2. **Logo URL 失效**：外部托管的 Logo 可能 404，需要 fallback 机制
3. **标签键冲突**：`labels` 使用字符串键，可能存在命名冲突

### 6.3 改进建议

1. **添加版本信息**：
   ```typescript
   interface AppInfo {
     // ...现有字段
     schemaVersion: number;  // 用于处理类型演进
   }
   ```

2. **Logo URL 添加尺寸信息**：
   ```typescript
   type LogoInfo = {
     url: string;
     width: number;
     height: number;
   };
   ```

3. **标签类型安全化**：
   ```typescript
   type AppLabel = 
     | { key: 'category'; value: string }
     | { key: 'tags'; value: string[] }
     | { key: string; value: string };
   ```

4. **稳定化路径**：
   - 收集 `app/list` API 的使用反馈
   - 评估字段必要性，考虑拆分可选字段到扩展对象
   - 考虑添加 `createdAt`、`updatedAt` 等时间戳字段

### 6.4 性能考虑

- `AppInfo` 包含嵌套结构，序列化/反序列化成本较高
- 对于列表场景，考虑使用 `AppSummary` 减少数据传输
- `AppsListParams` 支持分页（`cursor`、`limit`），应合理使用
