# PluginListParams 研究文档

## 1. 场景与职责

`PluginListParams` 是获取插件市场列表的请求参数类型，用于控制插件列表的获取范围和同步行为。

**使用场景：**
- 插件市场页面加载：获取可用插件列表
- 工作目录特定的插件发现：根据当前项目发现本地插件
- 远程同步控制：强制与远程服务器同步插件状态

## 2. 功能点目的

该类型的核心目的是：

1. **控制插件发现范围**：通过工作目录参数限定搜索范围
2. **管理远程同步**：控制是否先与远程服务器同步再获取列表
3. **支持本地开发**：允许从本地工作目录发现插件

## 3. 具体技术实现

### TypeScript 定义
```typescript
import type { AbsolutePathBuf } from "../common/AbsolutePathBuf.js";

export type PluginListParams = {
  cwds: Array<AbsolutePathBuf> | null;
  forceRemoteSync: boolean;
};
```

### Rust 源实现
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

### 关键字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `cwds` | `AbsolutePathBuf[] \| null` | 可选的工作目录列表，用于发现仓库级插件市场。省略时只考虑用户级和官方精选市场 |
| `forceRemoteSync` | `boolean` | 为true时，在列出市场之前先与远程插件状态同步官方精选市场 |

## 4. 关键代码路径与文件引用

**主要定义位置：**
- `codex-rs/app-server-protocol/src/protocol/v2.rs` 行3098-3107

**关联的响应类型：**
- `PluginListResponse`：对应的列表响应（行3112-3117）

**API方法：**
- `plugin/list`：使用此参数的RPC方法

## 5. 依赖与外部交互

**导入依赖：**
- `AbsolutePathBuf`：绝对路径类型，用于工作目录路径

**使用场景：**
- 插件列表查询API
- 与 `PluginListResponse` 配对使用

## 6. 风险、边界与改进建议

### 潜在风险
1. **路径遍历攻击**：cwds参数可能包含恶意路径，需要严格验证
2. **性能问题**：大量工作目录或强制远程同步可能导致响应延迟
3. **权限问题**：某些工作目录可能没有读取权限

### 边界情况
- `cwds` 为null：只返回用户级和官方市场
- `cwds` 为空数组：与null行为相同
- `forceRemoteSync` 为true但网络不可用：需要优雅降级

### 改进建议
1. **添加路径验证**：确保所有路径都在允许的范围内
2. **添加分页支持**：如果插件数量很大，支持分页返回
3. **添加缓存机制**：避免频繁的远程同步
4. **添加过滤选项**：支持按类别、安装状态等筛选
5. **添加排序选项**：支持按名称、更新时间等排序
