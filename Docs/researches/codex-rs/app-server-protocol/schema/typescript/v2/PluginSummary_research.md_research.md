# PluginSummary 研究文档

## 场景与职责

`PluginSummary` 是 Codex App Server Protocol v2 中用于表示插件摘要信息的结构体。它提供了插件的核心元数据，用于插件列表展示、插件管理界面和插件状态追踪。

该类型在插件市场中扮演重要角色，客户端可以通过它快速了解插件的基本信息、安装状态和启用状态，而无需加载完整的插件详情。

## 功能点目的

1. **插件元数据展示**：提供插件的 ID、名称、来源等基本信息
2. **状态追踪**：记录插件的安装状态 (`installed`) 和启用状态 (`enabled`)
3. **策略信息**：包含安装策略和认证策略
4. **接口预览**：可选的插件接口信息，用于 UI 展示

## 具体技术实现

### 数据结构

```rust
// Rust 定义 (codex-rs/app-server-protocol/src/protocol/v2.rs)
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

```typescript
// TypeScript 生成类型 (schema/typescript/v2/PluginSummary.ts)
export type PluginSummary = { 
    id: string, 
    name: string, 
    source: PluginSource, 
    installed: boolean, 
    enabled: boolean, 
    install_policy: PluginInstallPolicy, 
    auth_policy: PluginAuthPolicy, 
    interface: PluginInterface | null, 
};
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | `String` | 插件唯一标识符 |
| `name` | `String` | 插件显示名称 |
| `source` | `PluginSource` | 插件来源信息 |
| `installed` | `bool` | 是否已安装 |
| `enabled` | `bool` | 是否已启用 |
| `install_policy` | `PluginInstallPolicy` | 安装策略 |
| `auth_policy` | `PluginAuthPolicy` | 认证策略 |
| `interface` | `Option<PluginInterface>` | 插件接口信息（可选） |

### 策略类型

```rust
pub enum PluginInstallPolicy {
    #[serde(rename = "NOT_AVAILABLE")]
    NotAvailable,        // 不可安装
    #[serde(rename = "AVAILABLE")]
    Available,           // 可安装
    #[serde(rename = "INSTALLED_BY_DEFAULT")]
    InstalledByDefault,  // 默认已安装
}

pub enum PluginAuthPolicy {
    #[serde(rename = "ON_INSTALL")]
    OnInstall,  // 安装时认证
    #[serde(rename = "ON_USE")]
    OnUse,      // 使用时认证
}
```

## 关键代码路径与文件引用

### 定义位置
- **Rust 定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 3275-3284)
- **TypeScript 生成**: `codex-rs/app-server-protocol/schema/typescript/v2/PluginSummary.ts`

### 相关类型
- `PluginSource`: 插件来源
- `PluginInterface`: 插件接口定义
- `PluginInstallPolicy`: 安装策略枚举
- `PluginAuthPolicy`: 认证策略枚举
- `PluginDetail`: 包含 `PluginSummary` 作为子字段

### 使用场景
- `PluginListResponse`: 插件列表响应
- `PluginReadResponse`: 插件详情响应
- `PluginMarketplaceEntry`: 市场条目中的插件列表

## 依赖与外部交互

### 内部依赖
- `PluginSource`: 来源信息
- `PluginInterface`: 接口定义
- `serde`: 序列化支持
- `schemars`: JSON Schema 生成
- `ts_rs`: TypeScript 类型生成

### 协议交互
- 客户端通过 `plugin/list` 或 `plugin/read` 请求获取插件摘要
- 服务器返回包含 `PluginSummary` 的响应

## 风险、边界与改进建议

### 当前限制
1. **interface 可选性**：`interface` 字段为 `Option` 类型，客户端需要处理缺失情况
2. **状态一致性**：`installed` 和 `enabled` 的组合需要业务逻辑确保一致性
3. **ID 唯一性**：依赖外部系统确保插件 ID 的全局唯一性

### 边界情况
1. **未安装但启用**：理论上不应出现，但需要校验
2. **interface 缺失**：部分插件可能不提供接口信息
3. **策略冲突**：安装策略和认证策略的组合需要验证

### 改进建议
1. 添加状态组合验证方法
2. 考虑添加版本信息字段
3. 考虑添加插件依赖信息
4. 添加创建时间/更新时间字段

### 兼容性注意
- 字段使用 `camelCase` 命名确保与 TypeScript 惯例一致
- 可选字段使用 `Option<T>` 类型
- 枚举值使用大写下划线命名（如 `NOT_AVAILABLE`）
