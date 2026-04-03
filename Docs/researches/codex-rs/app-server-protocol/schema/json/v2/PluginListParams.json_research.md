# PluginListParams.json 研究文档

## 场景与职责

`PluginListParams.json` 是 Codex 应用服务器协议 v2 的 JSON Schema 定义文件，用于描述插件列表查询请求的参数结构。

该参数结构用于 `plugin/list` 方法，支持从多个工作目录发现插件市场，并提供远程同步控制选项，使客户端能够获取可用的插件列表。

## 功能点目的

1. **插件发现**: 从本地和远程市场发现可用插件
2. **多目录支持**: 支持从多个工作目录扫描插件市场
3. **远程同步**: 支持在列出前同步官方插件市场
4. **市场聚合**: 聚合多个来源的插件市场信息

## 具体技术实现

### 数据结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "definitions": {
    "AbsolutePathBuf": {
      "description": "A path that is guaranteed to be absolute and normalized (though it is not guaranteed to be canonicalized or exist on the filesystem).\n\nIMPORTANT: When deserializing an `AbsolutePathBuf`, a base path must be set using [AbsolutePathBufGuard::new]. If no base path is set, the deserialization will fail unless the path being deserialized is already absolute.",
      "type": "string"
    }
  },
  "properties": {
    "cwds": {
      "description": "Optional working directories used to discover repo marketplaces. When omitted, only home-scoped marketplaces and the official curated marketplace are considered.",
      "items": { "$ref": "#/definitions/AbsolutePathBuf" },
      "type": ["array", "null"]
    },
    "forceRemoteSync": {
      "description": "When true, reconcile the official curated marketplace against the remote plugin state before listing marketplaces.",
      "type": "boolean"
    }
  },
  "title": "PluginListParams",
  "type": "object"
}
```

### 字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `cwds` | array \| null | 否 | 用于发现仓库插件市场的工作目录列表。省略时仅考虑 home 作用域市场和官方精选市场 |
| `forceRemoteSync` | boolean | 否 | 是否在列出市场前，将官方精选市场与远程插件状态同步 |

### Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs:3098
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Default, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct PluginListParams {
    /// Optional working directories used to discover repo marketplaces.
    /// When omitted, only home-scoped marketplaces and the official curated
    /// marketplace are considered.
    #[ts(optional = nullable)]
    pub cwds: Option<Vec<AbsolutePathBuf>>,
    /// When true, reconcile the official curated marketplace against the remote
    /// plugin state before listing marketplaces.
    #[serde(default)]
    pub force_remote_sync: bool,
}
```

### 方法映射

```rust
// common.rs 行 299-302
PluginList => "plugin/list" {
    params: v2::PluginListParams,
    response: v2::PluginListResponse,
}
```

### 路径类型说明

`AbsolutePathBuf` 是一个保证为绝对路径且已规范化的路径类型：
- 路径不一定是规范化的（canonicalized）
- 路径不一定存在于文件系统上
- 反序列化时需要设置基础路径（通过 `AbsolutePathBufGuard::new`）

## 关键代码路径与文件引用

### 协议定义
- **Rust 结构体**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 3098-3111)
- **JSON Schema**: `codex-rs/app-server-protocol/schema/json/v2/PluginListParams.json`
- **方法注册**: `codex-rs/app-server-protocol/src/protocol/common.rs` (行 299-302)

### 调用方
- **客户端**: 通过 `plugin/list` 方法请求插件列表
- **UI 层**: 插件市场界面、插件管理器

### 响应结构
- **对应响应**: `PluginListResponse` - 包含市场列表和插件摘要信息

### 依赖类型
- **AbsolutePathBuf**: `codex_utils_absolute_path::AbsolutePathBuf`

## 依赖与外部交互

### 上游依赖
1. **插件市场扫描器**: 扫描指定目录发现插件市场
2. **远程市场服务**: 获取官方精选市场的插件信息
3. **文件系统**: 读取本地插件市场配置

### 下游使用方
1. **插件市场 UI**: 展示可用插件列表
2. **插件安装器**: 基于列表结果执行安装
3. **配置管理**: 管理插件启用/禁用状态

### 市场发现流程
1. 客户端调用 `plugin/list` 并传入 `PluginListParams`
2. 服务器扫描 `cwds` 指定的工作目录发现仓库市场
3. 同时扫描 home 作用域市场
4. 如 `forceRemoteSync` 为 true，同步官方远程市场
5. 聚合所有市场的插件信息
6. 返回 `PluginListResponse`

### 市场类型
1. **Home-scoped 市场**: 用户主目录下的插件市场
2. **Repo-scoped 市场**: 代码仓库中的插件市场
3. **官方精选市场**: Codex 官方维护的插件市场

## 风险、边界与改进建议

### 潜在风险
1. **路径遍历**: 需要验证 `cwds` 路径不指向敏感系统目录
2. **远程同步延迟**: `forceRemoteSync` 可能导致响应延迟
3. **市场冲突**: 不同市场中的同名插件可能产生冲突
4. **缓存失效**: 远程市场同步失败时可能返回过期数据

### 边界情况
1. **空 cwds**: 不传 `cwds` 时仅返回 home 和官方市场
2. **无效目录**: `cwds` 中包含不存在或不可访问的目录
3. **重复市场**: 多个 `cwds` 指向同一市场时的去重处理
4. **远程失败**: `forceRemoteSync` 为 true 但远程同步失败

### 改进建议

#### 1. 添加过滤条件
```json
{
  "cwds": ["/path1", "/path2"],
  "forceRemoteSync": true,
  "filter": {
    "installed": null,
    "enabled": true,
    "category": "productivity"
  }
}
```

#### 2. 添加分页支持
```json
{
  "cwds": ["/path1"],
  "forceRemoteSync": false,
  "pagination": {
    "cursor": "...",
    "limit": 20
  }
}
```

#### 3. 添加排序选项
```json
{
  "cwds": ["/path1"],
  "forceRemoteSync": false,
  "sort": {
    "by": "popularity",
    "order": "desc"
  }
}
```

#### 4. 添加搜索功能
```json
{
  "cwds": ["/path1"],
  "forceRemoteSync": false,
  "search": {
    "query": "git",
    "fields": ["name", "description"]
  }
}
```

#### 5. 添加缓存控制
```json
{
  "cwds": ["/path1"],
  "forceRemoteSync": false,
  "cache": {
    "ttl": 300,
    "forceRefresh": false
  }
}
```

### 最佳实践
1. **默认行为**: 不传 `cwds` 时获取标准市场列表
2. **错误处理**: 单个目录扫描失败不应影响其他目录
3. **性能优化**: 谨慎使用 `forceRemoteSync`，避免不必要的远程请求
4. **缓存利用**: 客户端应缓存插件列表，减少重复请求

### 相关 API
- `PluginListResponse` - 插件列表响应
- `PluginReadParams` / `PluginReadResponse` - 插件详情读取
- `PluginInstallParams` / `PluginInstallResponse` - 插件安装
- `PluginUninstallParams` / `PluginUninstallResponse` - 插件卸载
