# PluginInstallParams 研究文档

## 场景与职责

`PluginInstallParams` 定义了插件安装请求的参数类型。当客户端需要安装插件时使用此类型指定要安装的插件以及安装选项。

## 功能点目的

该类型的核心功能是：
1. **指定安装目标**: 通过市场路径和插件名称唯一标识要安装的插件
2. **远程同步控制**: 支持强制与远程状态同步后再安装
3. **安装流程配置**: 提供安装行为的配置选项

## 具体技术实现

### 数据结构

```typescript
export type PluginInstallParams = { 
  marketplacePath: AbsolutePathBuf, 
  pluginName: string, 
  /**
   * When true, apply the remote plugin change before the local install flow.
   */
  forceRemoteSync?: boolean 
};
```

### Rust 源码定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct PluginInstallParams {
    pub marketplace_path: AbsolutePathBuf,
    pub plugin_name: String,
    /// When true, apply the remote plugin change before the local install flow.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub force_remote_sync: bool,
}
```

### 字段详解

| 字段 | 类型 | 说明 |
|-----|------|------|
| `marketplacePath` | `AbsolutePathBuf` | 插件市场的文件系统路径 |
| `pluginName` | `string` | 要安装的插件名称 |
| `forceRemoteSync` | `boolean` (可选) | 是否在本地安装前强制与远程状态同步 |

### 字段行为

#### forceRemoteSync
- **默认值**: `false`
- **序列化**: 使用 `skip_serializing_if = "std::ops::Not::not"`，即只有为 `true` 时才序列化
- **用途**: 确保在安装前获取最新的插件信息和状态

### 使用场景

作为 `plugin/install` API 的请求参数：

```rust
client_request_definitions! {
    PluginInstall => "plugin/install" {
        params: v2::PluginInstallParams,
        response: v2::PluginInstallResponse,
    },
}
```

### 响应类型

```rust
pub struct PluginInstallResponse {
    pub auth_policy: PluginAuthPolicy,
    pub apps_needing_auth: Vec<AppSummary>,
}
```

## 关键代码路径与文件引用

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 类型定义，行 3360-3366 |
| `codex-rs/app-server-protocol/schema/typescript/v2/PluginInstallParams.ts` | TypeScript 类型定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 客户端请求定义，行 343-346 |

## 依赖与外部交互

### 依赖类型
- `AbsolutePathBuf`: 绝对路径类型
- `PluginInstallResponse`: 对应的响应类型
- `PluginAuthPolicy`: 响应中返回的认证策略

### 协议集成
- 属于 App-Server Protocol v2 API
- 是客户端向服务器发送的请求
- 方法名: `plugin/install`

### 插件系统集成
- 触发插件下载和安装流程
- 可能触发认证流程（取决于 `PluginAuthPolicy`）

## 风险、边界与改进建议

### 潜在风险
1. **路径安全**: `marketplacePath` 是绝对路径，需要验证路径安全性
2. **并发安装**: 同一插件的并发安装请求需要妥善处理
3. **网络依赖**: `forceRemoteSync` 为 `true` 时需要网络连接

### 边界情况
1. **插件不存在**: 指定的 `pluginName` 在市场路径中不存在
2. **已安装**: 插件已经安装时的行为
3. **版本冲突**: 已安装不同版本插件的处理

### 改进建议
1. 添加 `version` 字段支持安装特定版本
2. 添加 `dryRun` 选项用于预检安装
3. 添加 `skipDependencies` 选项控制是否安装依赖
4. 考虑添加 `installLocation` 字段支持自定义安装位置
5. 添加 `backupExisting` 选项在安装前备份现有插件
