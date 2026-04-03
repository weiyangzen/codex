# PluginMarketplaceEntry 研究文档

## 场景与职责

`PluginMarketplaceEntry` 是 Codex 插件市场系统的核心数据结构，表示一个插件市场的完整信息，包括市场元数据和其中包含的所有插件摘要。它是 `PluginListResponse` 的主要组成部分。

该类型支持多种市场来源（官方市场、用户 home 目录、项目 repo 目录），为客户端提供统一的插件市场视图。

## 功能点目的

### 核心功能
1. **市场标识**：通过 `name` 和 `path` 唯一标识一个插件市场
2. **界面展示**：通过 `interface` 提供市场的显示名称等 UI 信息
3. **插件聚合**：通过 `plugins` 包含该市场的所有可用插件

### 使用场景
- 插件市场页面按市场分组展示插件
- 项目特定插件的发现和安装
- 区分官方插件与第三方/本地插件

## 具体技术实现

### 数据结构定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs (lines 3233-3238)
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct PluginMarketplaceEntry {
    /// 市场名称（标识符）
    pub name: String,
    /// 市场路径（本地文件系统路径）
    pub path: AbsolutePathBuf,
    /// 市场界面信息（可选）
    pub interface: Option<MarketplaceInterface>,
    /// 该市场的插件列表
    pub plugins: Vec<PluginSummary>,
}
```

### 市场界面类型

```rust
// MarketplaceInterface (lines 3240-3245)
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct MarketplaceInterface {
    /// 显示名称（用于 UI 展示）
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
// schema/typescript/v2/PluginMarketplaceEntry.ts
import type { AbsolutePathBuf } from "../AbsolutePathBuf";
import type { MarketplaceInterface } from "./MarketplaceInterface";
import type { PluginSummary } from "./PluginSummary";

export type PluginMarketplaceEntry = { 
    name: string, 
    path: AbsolutePathBuf, 
    interface: MarketplaceInterface | null, 
    plugins: Array<PluginSummary>, 
};
```

## 关键代码路径与文件引用

### 定义位置
- **Rust 定义**：`codex-rs/app-server-protocol/src/protocol/v2.rs`
  - 行 3233-3238：`PluginMarketplaceEntry` 结构体
  - 行 3240-3245：`MarketplaceInterface` 结构体

### 使用位置
```rust
// PluginListResponse (lines 3109-3117)
pub struct PluginListResponse {
    pub marketplaces: Vec<PluginMarketplaceEntry>,  // 使用此类型
    pub remote_sync_error: Option<String>,
    pub featured_plugin_ids: Vec<String>,
}
```

### 相关类型定义
| 类型 | 文件 | 行号 | 说明 |
|------|------|------|------|
| `PluginListResponse` | v2.rs | 3109-3117 | 包含市场条目列表 |
| `MarketplaceInterface` | v2.rs | 3240-3245 | 市场界面信息 |
| `PluginSummary` | v2.rs | 3272-3284 | 插件摘要 |
| `PluginSource` | v2.rs | 3336-3340 | 插件来源 |

### 生成的 TypeScript 文件
- `codex-rs/app-server-protocol/schema/typescript/v2/PluginMarketplaceEntry.ts`
- `codex-rs/app-server-protocol/schema/typescript/v2/MarketplaceInterface.ts`（依赖）
- `codex-rs/app-server-protocol/schema/typescript/v2/PluginSummary.ts`（依赖）

## 依赖与外部交互

### 内部依赖
1. **ts-rs**：TypeScript 类型导出
2. **schemars**：JSON Schema 生成
3. **serde**：驼峰命名序列化
4. **codex_utils_absolute_path**：`AbsolutePathBuf` 类型

### 市场类型映射
| 市场类型 | name 示例 | path 示例 | interface.display_name |
|----------|-----------|-----------|------------------------|
| Official | `"official"` | （缓存路径） | `"Official Marketplace"` |
| Home | `"home"` | `~/.codex/plugins/` | `"User Plugins"` |
| Repo | `"repo:myproject"` | `./.codex/plugins/` | `"Project Plugins"` |

### 数据流
```
文件系统扫描
    ↓
发现插件目录
    ↓
解析市场配置（如有）
    ↓
扫描插件列表
    ↓
生成 PluginMarketplaceEntry {
        name: 市场名称,
        path: 绝对路径,
        interface: 市场界面配置,
        plugins: [插件1, 插件2, ...],
    }
    ↓
聚合到 PluginListResponse
```

## 风险、边界与改进建议

### 潜在风险
1. **路径暴露**：`path` 字段暴露本地文件系统路径，可能包含敏感信息
2. **名称冲突**：不同来源的市场可能使用相同的 `name`
3. **空插件列表**：`plugins` 为空时市场条目仍会被返回

### 边界情况
1. **interface 为 None**：市场没有界面配置时的默认展示
2. **路径不存在**：市场路径被删除但仍在响应中
3. **重复插件**：同一插件出现在多个市场（如官方和 repo 都有）

### 改进建议
1. **添加市场类型字段**：
   ```rust
   pub enum MarketplaceType {
       Official,
       Home,
       Repo,
   }
   
   pub struct PluginMarketplaceEntry {
       // ... 现有字段
       pub market_type: MarketplaceType,
   }
   ```

2. **添加统计信息**：
   ```rust
   pub struct PluginMarketplaceEntry {
       // ... 现有字段
       pub stats: MarketplaceStats,
   }
   
   pub struct MarketplaceStats {
       pub total_plugins: u32,
       pub installed_plugins: u32,
       pub enabled_plugins: u32,
   }
   ```

3. **路径脱敏**：
   ```rust
   pub struct PluginMarketplaceEntry {
       pub name: String,
       // 对外暴露相对路径或 ID，内部保留绝对路径
       pub path_id: String,  // 如 "home", "repo:myproject"
       // path 字段改为内部使用
   }
   ```

4. **添加排序权重**：
   ```rust
   pub struct MarketplaceInterface {
       pub display_name: Option<String>,
       pub sort_order: Option<i32>,  // 用于控制市场展示顺序
   }
   ```

### 测试覆盖
建议测试场景：
1. 不同市场类型的序列化/反序列化
2. 空插件列表处理
3. 特殊字符在市场名称中的处理
4. 路径格式验证

### API 稳定性
- 此类型属于稳定 API（无 `#[experimental]` 标记）
- 作为 PluginListResponse 的核心组件，变更影响广泛
- 建议通过添加可选字段来扩展

### 与 PluginInterface 的关系
```rust
// PluginInterface 是单个插件的界面信息
pub struct PluginInterface {
    pub display_name: Option<String>,
    pub short_description: Option<String>,
    // ... 更多字段
}

// MarketplaceInterface 是市场的界面信息（简化版）
pub struct MarketplaceInterface {
    pub display_name: Option<String>,
}
```
两者都提供界面信息，但 `MarketplaceInterface` 目前较为简化，未来可能扩展。
