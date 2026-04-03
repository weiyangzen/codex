# PluginListResponse.json 研究文档

## 场景与职责

`PluginListResponse.json` 是 Codex 应用服务器协议 v2 的 JSON Schema 定义文件，用于描述插件列表查询响应的结构。

该响应结构用于 `plugin/list` 方法的返回，包含从多个市场聚合的插件信息，支持客户端实现插件市场浏览、安装和管理功能。

## 功能点目的

1. **市场聚合展示**: 聚合多个来源（home、repo、官方）的插件市场信息
2. **插件发现**: 提供完整的插件元数据，支持浏览和搜索
3. **安装状态跟踪**: 显示每个插件的安装、启用状态
4. **授权策略展示**: 展示插件的授权策略（安装时/使用时）
5. **远程同步状态**: 报告官方市场远程同步的错误信息

## 具体技术实现

### 数据结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "definitions": {
    "AbsolutePathBuf": { "type": "string" },
    "MarketplaceInterface": {
      "properties": { "displayName": { "type": ["string", "null"] } },
      "type": "object"
    },
    "PluginAuthPolicy": { "enum": ["ON_INSTALL", "ON_USE"], "type": "string" },
    "PluginInstallPolicy": { "enum": ["NOT_AVAILABLE", "AVAILABLE", "INSTALLED_BY_DEFAULT"], "type": "string" },
    "PluginInterface": {
      "properties": {
        "brandColor": { "type": ["string", "null"] },
        "capabilities": { "items": { "type": "string" }, "type": "array" },
        "category": { "type": ["string", "null"] },
        "composerIcon": { "anyOf": [{ "$ref": "#/definitions/AbsolutePathBuf" }, { "type": "null" }] },
        "defaultPrompt": { "items": { "type": "string" }, "type": ["array", "null"] },
        "developerName": { "type": ["string", "null"] },
        "displayName": { "type": ["string", "null"] },
        "logo": { "anyOf": [{ "$ref": "#/definitions/AbsolutePathBuf" }, { "type": "null" }] },
        "longDescription": { "type": ["string", "null"] },
        "privacyPolicyUrl": { "type": ["string", "null"] },
        "screenshots": { "items": { "$ref": "#/definitions/AbsolutePathBuf" }, "type": "array" },
        "shortDescription": { "type": ["string", "null"] },
        "termsOfServiceUrl": { "type": ["string", "null"] },
        "websiteUrl": { "type": ["string", "null"] }
      },
      "required": ["capabilities", "screenshots"],
      "type": "object"
    },
    "PluginMarketplaceEntry": {
      "properties": {
        "interface": { "anyOf": [{ "$ref": "#/definitions/MarketplaceInterface" }, { "type": "null" }] },
        "name": { "type": "string" },
        "path": { "$ref": "#/definitions/AbsolutePathBuf" },
        "plugins": { "items": { "$ref": "#/definitions/PluginSummary" }, "type": "array" }
      },
      "required": ["name", "path", "plugins"],
      "type": "object"
    },
    "PluginSource": {
      "oneOf": [{
        "properties": {
          "path": { "$ref": "#/definitions/AbsolutePathBuf" },
          "type": { "enum": ["local"], "type": "string" }
        },
        "required": ["path", "type"],
        "title": "LocalPluginSource",
        "type": "object"
      }]
    },
    "PluginSummary": {
      "properties": {
        "authPolicy": { "$ref": "#/definitions/PluginAuthPolicy" },
        "enabled": { "type": "boolean" },
        "id": { "type": "string" },
        "installPolicy": { "$ref": "#/definitions/PluginInstallPolicy" },
        "installed": { "type": "boolean" },
        "interface": { "anyOf": [{ "$ref": "#/definitions/PluginInterface" }, { "type": "null" }] },
        "name": { "type": "string" },
        "source": { "$ref": "#/definitions/PluginSource" }
      },
      "required": ["authPolicy", "enabled", "id", "installPolicy", "installed", "name", "source"],
      "type": "object"
    }
  },
  "properties": {
    "featuredPluginIds": { "default": [], "items": { "type": "string" }, "type": "array" },
    "marketplaces": { "items": { "$ref": "#/definitions/PluginMarketplaceEntry" }, "type": "array" },
    "remoteSyncError": { "type": ["string", "null"] }
  },
  "required": ["marketplaces"],
  "title": "PluginListResponse",
  "type": "object"
}
```

### 核心字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `marketplaces` | array | 插件市场列表，每个市场包含名称、路径和插件列表 |
| `featuredPluginIds` | array | 精选插件 ID 列表，用于推荐展示 |
| `remoteSyncError` | string \| null | 官方市场远程同步错误信息 |

### 子类型说明

#### PluginSummary
- **id**: 插件唯一标识符
- **name**: 插件名称
- **installed**: 是否已安装
- **enabled**: 是否已启用
- **authPolicy**: 授权策略（ON_INSTALL/ON_USE）
- **installPolicy**: 安装策略（NOT_AVAILABLE/AVAILABLE/INSTALLED_BY_DEFAULT）
- **interface**: 插件界面元数据（名称、描述、图标等）
- **source**: 插件来源（目前仅支持 local）

#### PluginInterface
- **displayName**: 显示名称
- **shortDescription**: 简短描述
- **longDescription**: 详细描述
- **capabilities**: 插件能力列表
- **category**: 分类
- **logo**: 图标路径
- **screenshots**: 截图路径列表
- **defaultPrompt**: 默认提示词（最多3条，每条最多128字符）
- **brandColor**: 品牌色

#### PluginMarketplaceEntry
- **name**: 市场名称
- **path**: 市场路径
- **plugins**: 该市场的插件列表
- **interface**: 市场界面信息

### Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs:3112
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct PluginListResponse {
    pub marketplaces: Vec<PluginMarketplaceEntry>,
    #[serde(default)]
    pub featured_plugin_ids: Vec<String>,
    pub remote_sync_error: Option<String>,
}

// PluginMarketplaceEntry (行 3034-3050)
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct PluginMarketplaceEntry {
    pub name: String,
    pub path: AbsolutePathBuf,
    pub plugins: Vec<PluginSummary>,
    pub interface: Option<MarketplaceInterface>,
}

// PluginSummary (行 3052-3085)
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct PluginSummary {
    pub auth_policy: PluginAuthPolicy,
    pub enabled: bool,
    pub id: String,
    pub install_policy: PluginInstallPolicy,
    pub installed: bool,
    pub interface: Option<PluginInterface>,
    pub name: String,
    pub source: PluginSource,
}
```

## 关键代码路径与文件引用

### 协议定义
- **Rust 结构体**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 3112-3121)
- **JSON Schema**: `codex-rs/app-server-protocol/schema/json/v2/PluginListResponse.json`
- **方法注册**: `codex-rs/app-server-protocol/src/protocol/common.rs` (行 299-302)

### 相关类型
- `PluginMarketplaceEntry` (v2.rs 行 3034-3050)
- `PluginSummary` (v2.rs 行 3052-3085)
- `PluginInterface` (v2.rs 行 2952-3019)
- `PluginSource` (v2.rs 行 3021-3032)
- `PluginAuthPolicy` / `PluginInstallPolicy` (枚举)

## 依赖与外部交互

### 上游依赖
1. **插件市场扫描器**: 扫描并解析插件市场
2. **插件元数据解析器**: 读取插件配置和界面信息
3. **远程同步服务**: 获取官方市场数据

### 下游使用方
1. **插件市场 UI**: 展示插件列表和市场信息
2. **插件安装器**: 基于列表结果执行安装
3. **推荐系统**: 基于 `featuredPluginIds` 展示精选插件

### 安装策略说明

#### PluginInstallPolicy
- **NOT_AVAILABLE**: 插件不可用（如平台不支持）
- **AVAILABLE**: 插件可用，可以安装
- **INSTALLED_BY_DEFAULT**: 默认已安装，通常为核心插件

## 风险、边界与改进建议

### 潜在风险
1. **数据量大**: 大量插件和市场的数据可能导致响应体积过大
2. **路径暴露**: 本地路径信息可能暴露敏感目录结构
3. **同步失败**: `remoteSyncError` 非空时客户端需要处理降级
4. **版本信息缺失**: 当前结构不包含插件版本信息

### 边界情况
1. **空市场**: `marketplaces` 为空数组表示无可用插件
2. **重复插件**: 同一插件可能在多个市场中出现
3. **界面信息缺失**: `interface` 字段可能为 null
4. **精选插件不存在**: `featuredPluginIds` 中的插件可能不在列表中

### 改进建议

#### 1. 添加版本信息
```json
{
  "id": "plugin1",
  "name": "Plugin One",
  "version": "1.2.3",
  "latestVersion": "1.3.0",
  "updateAvailable": true
}
```

#### 2. 添加统计信息
```json
{
  "featuredPluginIds": [...],
  "marketplaces": [...],
  "remoteSyncError": null,
  "stats": {
    "totalPlugins": 42,
    "installedPlugins": 10,
    "enabledPlugins": 8
  }
}
```

#### 3. 添加分页支持
```json
{
  "marketplaces": [...],
  "pagination": {
    "cursor": "...",
    "hasMore": true,
    "total": 150
  }
}
```

#### 4. 添加分类信息
```json
{
  "marketplaces": [...],
  "categories": [
    { "id": "productivity", "name": "Productivity", "count": 15 },
    { "id": "development", "name": "Development", "count": 20 }
  ]
}
```

#### 5. 添加依赖信息
```json
{
  "id": "plugin1",
  "name": "Plugin One",
  "dependencies": [
    { "id": "plugin2", "optional": false },
    { "id": "plugin3", "optional": true }
  ]
}
```

### 最佳实践
1. **错误处理**: 当 `remoteSyncError` 存在时，向用户展示警告但继续显示本地数据
2. **精选展示**: 优先展示 `featuredPluginIds` 中的插件
3. **状态过滤**: 客户端应提供按安装状态、启用状态过滤的功能
4. **缓存策略**: 缓存插件列表，定期刷新

### 相关 API
- `PluginListParams` - 插件列表查询参数
- `PluginReadParams` / `PluginReadResponse` - 插件详情
- `PluginInstallParams` / `PluginInstallResponse` - 插件安装
- `AppListUpdatedNotification` - 应用列表更新通知
