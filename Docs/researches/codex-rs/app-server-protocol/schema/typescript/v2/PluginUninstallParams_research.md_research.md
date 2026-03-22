# PluginUninstallParams 研究文档

## 场景与职责

`PluginUninstallParams` 是 Codex App Server Protocol v2 中用于插件卸载操作的参数结构体。它定义了客户端请求卸载插件时需要提供的参数，支持本地卸载和远程同步两种模式。

该类型在插件生命周期管理中扮演重要角色，特别是在需要同步远程插件状态（如云端配置）与本地安装状态的场景中。

## 功能点目的

1. **插件标识**：通过 `plugin_id` 指定要卸载的插件
2. **远程同步控制**：通过 `force_remote_sync` 控制是否先同步远程状态
3. **卸载流程协调**：支持复杂的卸载场景，如先远程禁用再本地卸载

## 具体技术实现

### 数据结构

```rust
// Rust 定义 (codex-rs/app-server-protocol/src/protocol/v2.rs)
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct PluginUninstallParams {
    pub plugin_id: String,
    /// When true, apply the remote plugin change before the local uninstall flow.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub force_remote_sync: bool,
}
```

```typescript
// TypeScript 生成类型 (schema/typescript/v2/PluginUninstallParams.ts)
export type PluginUninstallParams = { 
    pluginId: string, 
    /**
     * When true, apply the remote plugin change before the local uninstall flow.
     */
    forceRemoteSync?: boolean, 
};
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `plugin_id` | `String` | 要卸载的插件唯一标识符（必填） |
| `force_remote_sync` | `bool` | 是否先同步远程插件状态（可选，默认 false） |

### 序列化行为

- `force_remote_sync` 使用 `#[serde(default)]`，默认为 `false`
- 使用 `skip_serializing_if = "std::ops::Not::not"`，当值为 `false` 时不序列化
- TypeScript 中使用 `?` 标记为可选属性

## 关键代码路径与文件引用

### 定义位置
- **Rust 定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 3376-3384)
- **TypeScript 生成**: `codex-rs/app-server-protocol/schema/typescript/v2/PluginUninstallParams.ts`

### 相关类型
- `PluginUninstallResponse`: 卸载操作的响应类型（空对象）
- `PluginInstallParams`: 安装参数，结构类似

### 使用场景
- 客户端调用 `plugin/uninstall` 方法时传递此参数
- 服务器根据参数执行卸载逻辑

## 依赖与外部交互

### 内部依赖
- `serde`: 序列化/反序列化
- `schemars`: JSON Schema 生成
- `ts_rs`: TypeScript 类型生成

### 协议交互

**请求示例**:
```json
{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "plugin/uninstall",
    "params": {
        "pluginId": "my-plugin",
        "forceRemoteSync": true
    }
}
```

**响应示例**:
```json
{
    "jsonrpc": "2.0",
    "id": 1,
    "result": {}
}
```

## 风险、边界与改进建议

### 当前限制
1. **无返回值**：`PluginUninstallResponse` 为空对象，无法获取卸载结果详情
2. **幂等性**：协议未明确说明重复卸载同一插件的行为
3. **依赖处理**：未处理被其他插件依赖的情况

### 边界情况
1. **插件不存在**：需要明确错误响应
2. **远程同步失败**：`force_remote_sync=true` 但远程操作失败时的处理
3. **部分卸载**：文件被占用或权限不足时的处理

### 改进建议
1. **添加结果详情**：在响应中添加卸载成功/失败的状态
2. **添加错误码**：定义具体的错误类型（如插件不存在、权限不足等）
3. **依赖检查**：卸载前检查是否有其他插件依赖
4. **异步卸载**：对于复杂插件，考虑支持异步卸载流程
5. **回滚机制**：卸载失败时支持回滚操作

### 兼容性注意
- 使用 `#[serde(default)]` 确保旧客户端（不传 `force_remote_sync`）的兼容性
- 字段命名使用 camelCase 确保与 TypeScript 惯例一致
- 布尔值使用 `skip_serializing_if` 减少传输数据量
