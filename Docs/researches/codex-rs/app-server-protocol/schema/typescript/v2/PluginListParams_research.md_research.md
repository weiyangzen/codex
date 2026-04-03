# PluginListParams 研究文档

## 场景与职责

`PluginListParams` 是 app-server v2 API 中 ClientRequest 的 `plugin/list` 方法的参数类型。它用于查询可用的插件市场列表，支持基于工作目录的发现和远程同步控制。

该类型是 Codex 插件发现系统的入口，允许客户端获取用户可安装的所有插件信息，包括官方市场、本地项目和 home 目录的插件。

## 功能点目的

### 核心功能
1. **工作目录感知**：通过 `cwds` 参数支持基于当前工作目录的插件发现
2. **远程同步控制**：通过 `force_remote_sync` 强制同步官方市场的远程状态
3. **多市场聚合**：返回官方市场、repo 市场和 home 市场的聚合结果

### 使用场景
- 插件市场页面加载时获取可用插件
- 项目特定插件的发现（基于项目路径）
- 强制刷新插件列表（绕过缓存）

## 具体技术实现

### 数据结构定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs (lines 3097-3107)
#[derive(Serialize, Deserialize, Debug, Default, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct PluginListParams {
    /// Optional working directories used to discover repo marketplaces.
    /// When omitted, only home-scoped marketplaces and the official curated marketplace are considered.
    #[ts(optional = nullable)]
    pub cwds: Option<Vec<AbsolutePathBuf>>,
    /// When true, reconcile the official curated marketplace against the remote plugin state
    /// before listing marketplaces.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub force_remote_sync: bool,
}
```

### 生成的 TypeScript 类型

```typescript
// schema/typescript/v2/PluginListParams.ts
import type { AbsolutePathBuf } from "../AbsolutePathBuf";

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
    forceRemoteSync?: boolean, 
};
```

### 对应的响应类型

```rust
// PluginListResponse (lines 3109-3117)
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct PluginListResponse {
    pub marketplaces: Vec<PluginMarketplaceEntry>,
    pub remote_sync_error: Option<String>,
    #[serde(default)]
    pub featured_plugin_ids: Vec<String>,
}
```

## 关键代码路径与文件引用

### 定义位置
- **Rust 定义**：`codex-rs/app-server-protocol/src/protocol/v2.rs`
  - 行 3097-3107：`PluginListParams` 结构体
  - 行 3109-3117：`PluginListResponse` 响应类型

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

### 相关类型定义
| 类型 | 文件 | 行号 | 说明 |
|------|------|------|------|
| `PluginListResponse` | v2.rs | 3109-3117 | 对应的响应类型 |
| `PluginMarketplaceEntry` | v2.rs | 3233-3238 | 市场条目 |
| `PluginSummary` | v2.rs | 3272-3284 | 插件摘要 |
| `PluginReadParams` | v2.rs | 3119-3126 | 读取单个插件参数 |

### 生成的 TypeScript 文件
- `codex-rs/app-server-protocol/schema/typescript/v2/PluginListParams.ts`
- `codex-rs/app-server-protocol/schema/typescript/v2/PluginListResponse.ts`（配对）
- `codex-rs/app-server-protocol/schema/typescript/v2/PluginMarketplaceEntry.ts`（依赖）

## 依赖与外部交互

### 内部依赖
1. **ts-rs**：`#[ts(optional = nullable)]` 标记可选字段
2. **schemars**：JSON Schema 生成
3. **serde**：`#[serde(default, skip_serializing_if = "std::ops::Not::not")]` 布尔字段优化
4. **codex_utils_absolute_path**：`AbsolutePathBuf` 类型

### 插件发现流程
```
Client
    ↓
PluginListParams { cwds, force_remote_sync }
    ↓
POST plugin/list
    ↓
Server 处理：
    1. 确定市场列表：
       - 官方市场（始终包含）
       - Home 市场（~/.codex/plugins/）
       - Repo 市场（基于 cwds 参数）
    2. 如 force_remote_sync=true：
       - 同步官方市场的远程状态
    3. 扫描每个市场的插件
    4. 聚合结果
    ↓
PluginListResponse { marketplaces, remote_sync_error, featured_plugin_ids }
```

### 市场类型
| 市场类型 | 路径示例 | 说明 |
|----------|----------|------|
| Official | （远程） | 官方策划的插件市场 |
| Home | `~/.codex/plugins/` | 用户级插件 |
| Repo | `./.codex/plugins/` | 项目特定插件 |

## 风险、边界与改进建议

### 潜在风险
1. **路径遍历**：`cwds` 中的路径需要验证，防止目录遍历攻击
2. **远程同步延迟**：`force_remote_sync=true` 可能导致响应延迟
3. **重复市场**：`cwds` 可能包含重叠路径（如父子目录）

### 边界情况
1. **空 cwds**：仅返回官方和 home 市场
2. **无效路径**：`cwds` 包含不存在的路径时的处理
3. **远程同步失败**：`remote_sync_error` 字段记录错误但返回缓存数据
4. **无插件市场**：所有市场都为空时的空列表处理

### 改进建议
1. **添加验证**：
   ```rust
   impl PluginListParams {
       pub fn validate(&self) -> Result<(), ValidationError> {
           if let Some(cwds) = &self.cwds {
               for cwd in cwds {
                   if !cwd.exists() {
                       return Err(ValidationError::InvalidCwd(cwd.clone()));
                   }
               }
           }
           Ok(())
       }
   }
   ```

2. **添加分页支持**：
   ```rust
   pub struct PluginListParams {
       // ... 现有字段
       pub cursor: Option<String>,
       pub limit: Option<u32>,
   }
   ```

3. **添加过滤选项**：
   ```rust
   pub struct PluginListParams {
       // ... 现有字段
       pub category: Option<String>,
       pub installed_only: bool,
       pub search_query: Option<String>,
   }
   ```

4. **去重 cwds**：
   ```rust
   pub fn sanitize(mut self) -> Self {
       if let Some(cwds) = &mut self.cwds {
           // 移除重复和子目录
           cwds.sort();
           cwds.dedup();
       }
       self
   }
   ```

### 测试覆盖
建议测试场景：
1. 正常查询（含 cwds 和 force_remote_sync）
2. 最小参数查询（默认参数）
3. 无效路径处理
4. 远程同步失败处理
5. 大量市场的性能测试

### API 稳定性
- 此类型属于稳定 API（无 `#[experimental]` 标记）
- 作为 ClientRequest 的参数类型，变更会影响客户端
- 建议通过添加可选字段来扩展

### 与 PluginReadParams 的对比
```rust
// PluginReadParams 用于读取单个插件详情
pub struct PluginReadParams {
    pub marketplace_path: AbsolutePathBuf,  // 必需
    pub plugin_name: String,                // 必需
}
```
`PluginListParams` 用于批量发现，`PluginReadParams` 用于精确获取单个插件详情。
