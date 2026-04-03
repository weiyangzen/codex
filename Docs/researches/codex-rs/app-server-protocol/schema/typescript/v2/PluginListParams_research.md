# PluginListParams 研究文档

## 场景与职责

`PluginListParams` 是插件列表查询的请求参数类型，用于控制插件市场列表的获取行为。它支持通过工作目录发现仓库级别的插件市场，并控制是否强制同步远程插件状态。

该类型是 Codex 插件系统发现机制的核心，使用户能够浏览和发现可用的插件。

## 功能点目的

1. **工作目录发现**: 通过 `cwds` 参数指定工作目录，发现仓库级别的插件市场
2. **远程同步控制**: 通过 `forceRemoteSync` 控制是否同步官方插件市场的远程状态
3. **灵活查询**: 支持仅查询本地市场或强制刷新远程数据
4. **多市场聚合**: 可以同时查询多个工作目录对应的市场

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
  forceRemoteSync?: boolean, 
};
```

### 字段详解

| 字段 | 类型 | 可选 | 说明 |
|------|------|------|------|
| `cwds` | `Array<AbsolutePathBuf> \| null` | 可选 | 工作目录列表，用于发现仓库级插件市场 |
| `forceRemoteSync` | `boolean` | 可选 | 是否强制同步官方市场的远程状态 |

### 参数行为

1. **cwds 省略**: 只查询用户主目录范围和官方精选市场的插件
2. **cwds 提供**: 额外查询指定目录对应的仓库级市场
3. **forceRemoteSync = false**: 使用本地缓存的市场数据（更快）
4. **forceRemoteSync = true**: 先同步远程状态，再返回列表（数据最新）

### 生成信息

该文件为自动生成代码，由 [ts-rs](https://github.com/Aleph-Alpha/ts-rs) 从 Rust 源代码生成。

对应的 Rust 定义：
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

### 序列化特性

- `forceRemoteSync` 使用 `#[serde(default, skip_serializing_if = "std::ops::Not::not")]`
- 当值为 `false` 时，序列化会跳过该字段
- 符合 API 设计规范：省略表示 `false`

## 关键代码路径与文件引用

### TypeScript 定义
- **文件**: `codex-rs/app-server-protocol/schema/typescript/v2/PluginListParams.ts`
- **依赖类型**: `AbsolutePathBuf.ts`
- **响应类型**: `PluginListResponse.ts`
- **索引**: `codex-rs/app-server-protocol/schema/typescript/v2/index.ts`

### Rust 源文件
- **主定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行号约 3098-3107)
- **响应定义**: 同一文件 (行号约 3109-3117)

### 协议注册

在 `codex-rs/app-server-protocol/src/protocol/common.rs` 中注册：
```rust
client_request_definitions! {
    // ...
    PluginList => "plugin/list" {
        params: v2::PluginListParams,
        response: v2::PluginListResponse,
    },
    // ...
}
```

### 核心使用位置

1. **App Server 消息处理**
   - 文件: `codex-rs/app-server/src/codex_message_processor.rs`
   - 导入: `use codex_app_server_protocol::PluginListParams;`

2. **测试套件**
   - 文件: `codex-rs/app-server/tests/suite/v2/plugin_list.rs`
   - 文件: `codex-rs/app-server/tests/common/mcp_process.rs`

## 依赖与外部交互

### 完整查询流程

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        插件列表查询流程                                  │
└─────────────────────────────────────────────────────────────────────────┘

  Client                      App Server                   Plugin System
    │                             │                            │
    │  1. plugin/list             │                            │
    │     {                       │                            │
    │       cwds?: ["/path"],     │                            │
    │       forceRemoteSync?: true│                            │
    │     }                       │                            │
    │────────────────────────────▶│                            │
    │                             │                            │
    │                             │  2. 发现市场                │
    │                             │     - 主目录市场            │
    │                             │     - 官方精选市场          │
    │                             │     - 仓库级市场 (如果 cwds)│
    │                             │                            │
    │                             │  3. 可选：同步远程状态       │
    │                             │     (如果 forceRemoteSync)  │
    │                             │───────────────────────────▶│
    │                             │                            │
    │                             │◀───────────────────────────│
    │                             │                            │
    │  4. {                       │                            │
    │       marketplaces,         │                            │
    │       remoteSyncError,      │                            │
    │       featuredPluginIds     │                            │
    │     }                       │                            │
    │◀────────────────────────────│                            │
    │                             │                            │
```

### 市场发现机制

```
┌─────────────────────────────────────────────────────────────────┐
│                        市场发现层级                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. 官方精选市场 (Official Curated)                              │
│     ~/.codex/plugins/official/marketplace.json                  │
│     或远程同步的最新版本                                         │
│                                                                 │
│  2. 用户主目录市场 (Home-scoped)                                 │
│     ~/.codex/plugins/marketplace.json                           │
│                                                                 │
│  3. 仓库级市场 (Repo-scoped)                                     │
│     {cwd}/.agents/plugins/marketplace.json                      │
│     (通过 cwds 参数指定)                                         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 与 PluginListResponse 的关系

```typescript
type PluginListResponse = {
  marketplaces: Array<PluginMarketplaceEntry>,
  remoteSyncError: string | null,
  featuredPluginIds: Array<string>,
};
```

## 风险、边界与改进建议

### 已知风险

1. **路径不存在**: `cwds` 中的路径可能不存在或不可访问
   - 风险: 查询失败或返回空结果
   - 缓解: 服务器应忽略无效路径，继续处理其他路径

2. **远程同步超时**: `forceRemoteSync = true` 时网络延迟
   - 风险: 响应时间过长
   - 缓解: 实现超时机制，返回部分数据

3. **大量 cwds**: 提供过多工作目录
   - 风险: 性能下降
   - 缓解: 限制最大数量或实现分页

4. **路径注入**: 恶意构造的路径参数
   - 风险: 目录遍历攻击
   - 缓解: 严格验证路径格式和权限

### 边界情况

1. **cwds 为空数组**: 等同于省略，只查询主目录和官方市场
2. **cwds 包含重复路径**: 应去重处理
3. **forceRemoteSync 但无网络**: 应使用本地缓存并返回错误信息
4. **所有市场都无效**: 返回空列表，不报错

### 改进建议

1. **添加过滤选项**:
   ```typescript
   filter?: {
     installed?: boolean;     // 只返回已安装/未安装
     category?: string;       // 按分类过滤
     search?: string;         // 关键词搜索
   };
   ```

2. **支持分页**:
   ```typescript
   cursor?: string;  // 分页游标
   limit?: number;   // 每页数量
   ```

3. **排序选项**:
   ```typescript
   sort?: {
     by: "name" | "popularity" | "recent";
     order: "asc" | "desc";
   };
   ```

4. **添加缓存控制**:
   ```typescript
   cacheControl?: "no-cache" | "max-age-seconds";
   ```

5. **指定特定市场**:
   ```typescript
   marketplacePaths?: AbsolutePathBuf[];  // 直接指定市场文件路径
   ```

### 测试建议

1. **单元测试**:
   - 参数序列化/反序列化
   - 默认值处理

2. **集成测试**:
   - 不同 cwds 组合的查询
   - forceRemoteSync 的同步行为
   - 网络异常处理

3. **边界测试**:
   - 空 cwds 数组
   - 无效路径
   - 大量路径

### 性能优化建议

1. **并行查询**: 多个 cwds 并行处理
2. **缓存策略**: 本地市场数据缓存
3. **增量同步**: 远程同步使用增量更新
4. **懒加载**: 插件详情延迟加载

### UI/UX 建议

1. **加载状态**: 显示市场加载进度
2. **刷新按钮**: 提供手动刷新（forceRemoteSync）
3. **错误提示**: 清晰展示哪些路径加载失败
4. **空状态**: 无插件时的友好提示
