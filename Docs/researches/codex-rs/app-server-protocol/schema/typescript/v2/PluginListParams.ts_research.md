# PluginListParams 研究文档

## 场景与职责

`PluginListParams` 定义了插件列表查询的请求参数类型。当客户端需要获取可用插件列表时使用此类型指定查询条件。

## 功能点目的

该类型的核心功能是：
1. **工作目录发现**: 支持基于工作目录发现仓库级别的插件市场
2. **远程同步控制**: 支持强制与官方市场远程状态同步
3. **灵活查询**: 提供可选参数支持不同的查询场景

## 具体技术实现

### 数据结构

```typescript
export type PluginListParams = { 
  /**
   * Optional working directories used to discover repo marketplaces. When omitted,
   * only home-scoped marketplaces and the official curated marketplace are considered.
   */
  cwds?: Array<AbsolutePathBuf> | null, 
  /**
   * When true, reconcile the official curated marketplace against the remote plugin state
   * before listing marketplaces.
   */
  forceRemoteSync?: boolean 
};
```

### Rust 源码定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct PluginListParams {
    /// Optional working directories used to discover repo marketplaces. When omitted,
    /// only home-scoped marketplaces and the official curated marketplace are considered.
    #[ts(optional = nullable)]
    pub cwds: Option<Vec<AbsolutePathBuf>>,
    /// When true, reconcile the official curated marketplace against the remote plugin state
    /// before listing marketplaces.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub force_remote_sync: bool,
}
```

### 字段详解

| 字段 | 类型 | 说明 |
|-----|------|------|
| `cwds` | `AbsolutePathBuf[] \| null` (可选) | 用于发现仓库市场的工作目录列表 |
| `forceRemoteSync` | `boolean` (可选) | 是否在列表查询前与远程市场同步 |

### 字段行为

#### cwds
- **可选性**: 使用 `#[ts(optional = nullable)]` 标记为可选且可为 null
- **默认值**: 如果省略，只考虑 home 级别市场和官方策划市场
- **用途**: 支持基于项目目录发现项目特定的插件市场

#### forceRemoteSync
- **默认值**: `false`
- **序列化**: 只有为 `true` 时才序列化
- **用途**: 确保获取最新的官方市场插件信息

### 使用场景

作为 `plugin/list` API 的请求参数：

```rust
client_request_definitions! {
    PluginList => "plugin/list" {
        params: v2::PluginListParams,
        response: v2::PluginListResponse,
    },
}
```

### 响应类型

```rust
pub struct PluginListResponse {
    pub marketplaces: Vec<PluginMarketplaceEntry>,
    pub remote_sync_error: Option<String>,
    pub featured_plugin_ids: Vec<String>,
}
```

## 关键代码路径与文件引用

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 类型定义，行 3098-3107 |
| `codex-rs/app-server-protocol/schema/typescript/v2/PluginListParams.ts` | TypeScript 类型定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 客户端请求定义，行 299-302 |

## 依赖与外部交互

### 依赖类型
- `AbsolutePathBuf`: 绝对路径类型
- `PluginListResponse`: 对应的响应类型
- `PluginMarketplaceEntry`: 响应中的市场条目类型

### 协议集成
- 属于 App-Server Protocol v2 API
- 是客户端向服务器发送的请求
- 方法名: `plugin/list`

### 插件系统集成
- 扫描文件系统发现插件市场
- 可能触发远程市场同步

## 风险、边界与改进建议

### 潜在风险
1. **路径遍历**: `cwds` 中的路径需要验证防止路径遍历攻击
2. **性能问题**: 大量工作目录可能导致查询变慢
3. **网络超时**: `forceRemoteSync` 为 `true` 时可能因网络问题超时

### 边界情况
1. **空列表**: `cwds` 为空数组时的行为
2. **无效路径**: 提供不存在的工作目录路径
3. **权限问题**: 无法访问某些工作目录

### 改进建议
1. 添加 `search` 字段支持关键词搜索
2. 添加 `category` 字段按类别过滤
3. 添加 `installed` 字段过滤已安装/未安装插件
4. 添加 `enabled` 字段过滤已启用/禁用插件
5. 添加分页参数 `cursor` 和 `limit` 处理大量插件
6. 添加 `sortBy` 字段支持排序（如按名称、安装时间等）
