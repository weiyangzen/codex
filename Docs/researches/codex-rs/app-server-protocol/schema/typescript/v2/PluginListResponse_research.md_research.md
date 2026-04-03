# PluginListResponse 研究文档

## 场景与职责

`PluginListResponse` 是 app-server v2 API 中 ClientRequest 的 `plugin/list` 方法的响应类型。它返回聚合的插件市场列表，包含所有可用插件的摘要信息、远程同步状态以及推荐插件 ID 列表。

该类型是 Codex 插件发现系统的核心响应结构，为客户端提供完整的插件市场视图，支持插件浏览、搜索和安装决策。

## 功能点目的

### 核心功能
1. **市场聚合**：返回多个插件市场的聚合数据（官方、home、repo）
2. **错误报告**：通过 `remote_sync_error` 报告远程同步失败而不中断整体流程
3. **推荐展示**：通过 `featured_plugin_ids` 高亮推荐插件

### 使用场景
- 插件市场页面展示所有可用插件
- 首次启动时的插件推荐
- 远程同步失败时的降级展示（使用缓存数据）

## 具体技术实现

### 数据结构定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs (lines 3109-3117)
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct PluginListResponse {
    /// 插件市场列表
    pub marketplaces: Vec<PluginMarketplaceEntry>,
    /// 远程同步错误信息（如有）
    pub remote_sync_error: Option<String>,
    /// 推荐插件 ID 列表
    #[serde(default)]
    pub featured_plugin_ids: Vec<String>,
}
```

### 市场条目类型

```rust
// PluginMarketplaceEntry (lines 3233-3238)
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct PluginMarketplaceEntry {
    pub name: String,                       // 市场名称
    pub path: AbsolutePathBuf,              // 市场路径
    pub interface: Option<MarketplaceInterface>,
    pub plugins: Vec<PluginSummary>,        // 该市场的插件列表
}

// MarketplaceInterface (lines 3240-3245)
pub struct MarketplaceInterface {
    pub display_name: Option<String>,
}
```

### 插件摘要类型

```rust
// PluginSummary (lines 3272-3284)
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct PluginSummary {
    pub id: String,
    pub name: String,
    pub source: PluginSource,
    pub installed: bool,
    pub enabled: bool,
    pub install_policy: PluginInstallPolicy,
    pub auth_policy: PluginAuthPolicy,
    pub interface: Option<PluginInterface>,
}
```

### 生成的 TypeScript 类型

```typescript
// schema/typescript/v2/PluginListResponse.ts
import type { PluginMarketplaceEntry } from "./PluginMarketplaceEntry";

export type PluginListResponse = { 
    marketplaces: Array<PluginMarketplaceEntry>, 
    remoteSyncError: string | null, 
    featuredPluginIds: Array<string>, 
};
```

## 关键代码路径与文件引用

### 定义位置
- **Rust 定义**：`codex-rs/app-server-protocol/src/protocol/v2.rs`
  - 行 3109-3117：`PluginListResponse` 结构体

### 协议注册
```rust
// codex-rs/app-server-protocol/src/protocol/common.rs (lines 299-302)
client_request_definitions! {
    PluginList => "plugin/list" {
        params: v2::PluginListParams,
        response: v2::PluginListResponse,
    },
}
```

### 请求参数
```rust
// PluginListParams (lines 3097-3107)
#[derive(Serialize, Deserialize, Debug, Default, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct PluginListParams {
    #[ts(optional = nullable)]
    pub cwds: Option<Vec<AbsolutePathBuf>>,
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub force_remote_sync: bool,
}
```

### 相关类型定义
| 类型 | 文件 | 行号 | 说明 |
|------|------|------|------|
| `PluginListParams` | v2.rs | 3097-3107 | 对应的请求参数 |
| `PluginMarketplaceEntry` | v2.rs | 3233-3238 | 市场条目 |
| `PluginSummary` | v2.rs | 3272-3284 | 插件摘要 |
| `MarketplaceInterface` | v2.rs | 3240-3245 | 市场界面 |

### 生成的 TypeScript 文件
- `codex-rs/app-server-protocol/schema/typescript/v2/PluginListResponse.ts`
- `codex-rs/app-server-protocol/schema/typescript/v2/PluginMarketplaceEntry.ts`（依赖）

## 依赖与外部交互

### 内部依赖
1. **ts-rs**：TypeScript 类型导出
2. **schemars**：JSON Schema 生成
3. **serde**：`#[serde(default)]` 为 `featured_plugin_ids` 提供默认值

### 响应生成流程
```
Server 处理 plugin/list 请求
    ↓
1. 收集所有相关市场
    - 官方市场
    - Home 市场 (~/.codex/plugins/)
    - Repo 市场 (基于 cwds)
    ↓
2. 如 force_remote_sync=true：
    - 尝试同步官方市场远程状态
    - 如失败，记录错误到 remote_sync_error
    ↓
3. 扫描每个市场的插件目录
    - 解析插件配置
    - 生成 PluginSummary
    ↓
4. 确定 featured_plugin_ids
    - 基于用户偏好
    - 基于官方推荐
    ↓
PluginListResponse {
    marketplaces: [...],
    remote_sync_error: None 或 Some("..."),
    featured_plugin_ids: ["plugin1", "plugin2"],
}
```

### 错误处理策略
| 场景 | remote_sync_error | marketplaces |
|------|-------------------|--------------|
| 正常 | `None` | 完整数据 |
| 远程同步失败 | `Some("...")` | 缓存数据 |
| 本地扫描失败 | `None` | 排除失败市场 |

## 风险、边界与改进建议

### 潜在风险
1. **响应体积**：大量插件时响应可能很大，影响性能
2. **ID 冲突**：不同市场的插件可能使用相同 ID
3. **featured_plugin_ids 有效性**：可能包含不存在或已禁用的插件 ID

### 边界情况
1. **空市场**：所有市场都没有插件时的空列表
2. **featured_plugin_ids 为空**：无推荐插件时的空数组
3. **remote_sync_error 与 force_remote_sync**：
   - `force_remote_sync=false` 时 `remote_sync_error` 应为 `None`
   - 但使用缓存数据时也可能有之前的错误

### 改进建议
1. **添加分页支持**：
   ```rust
   pub struct PluginListResponse {
       // ... 现有字段
       pub next_cursor: Option<String>,
       pub total_count: u32,
   }
   ```

2. **添加元数据**：
   ```rust
   pub struct PluginListResponse {
       // ... 现有字段
       pub generated_at: i64,           // 生成时间戳
       pub cache_ttl: Option<i64>,      // 缓存有效期
   }
   ```

3. **验证 featured_plugin_ids**：
   ```rust
   impl PluginListResponse {
       pub fn sanitize(&mut self) {
           // 过滤掉不存在的插件 ID
           let valid_ids: HashSet<_> = self.marketplaces
               .iter()
               .flat_map(|m| m.plugins.iter().map(|p| &p.id))
               .collect();
           self.featured_plugin_ids.retain(|id| valid_ids.contains(id));
       }
   }
   ```

4. **添加统计信息**：
   ```rust
   pub struct PluginListResponse {
       // ... 现有字段
       pub stats: PluginListStats,
   }
   
   pub struct PluginListStats {
       pub total_plugins: u32,
       pub installed_plugins: u32,
       pub official_plugins: u32,
   }
   ```

### 测试覆盖
建议测试场景：
1. 正常响应（多市场、多插件）
2. 远程同步失败响应
3. 空市场响应
4. featured_plugin_ids 过滤验证
5. 大量插件性能测试

### API 稳定性
- 此类型属于稳定 API（无 `#[experimental]` 标记）
- 作为 ClientRequest 的响应类型，变更会影响客户端
- 建议通过添加可选字段来扩展

### 与 PluginReadResponse 的对比
```rust
// PluginReadResponse 返回单个插件详情
pub struct PluginReadResponse {
    pub plugin: PluginDetail,  // 完整详情
}
```
`PluginListResponse` 返回批量摘要信息，`PluginReadResponse` 返回单个插件的完整信息。
